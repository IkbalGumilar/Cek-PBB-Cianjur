import 'dart:convert';
import 'dart:io';

/// Menyalin direktori secara rekursif saat Windows tidak dapat mengikuti
/// symlink lintas drive / shared folder (mis. drive jaringan `Z:\`).
void _copyDirectory(Directory src, Directory dst) {
  if (!dst.existsSync()) {
    dst.createSync(recursive: true);
  }
  for (final entity in src.listSync(recursive: false, followLinks: true)) {
    final name = _lastSegment(entity.path);
    final newPath = '${dst.path}${Platform.pathSeparator}$name';
    if (entity is Directory) {
      _copyDirectory(entity, Directory(newPath));
    } else if (entity is File) {
      entity.copySync(newPath);
    }
  }
}

String _lastSegment(String rawPath) {
  final cleaned = rawPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final idx = cleaned.lastIndexOf('/');
  return idx >= 0 ? cleaned.substring(idx + 1) : cleaned;
}

Directory? _resolvePubHostedCache(String? cliOverride) {
  final sep = Platform.pathSeparator;
  final candidates = <String>[
    if (cliOverride != null && cliOverride.isNotEmpty) cliOverride,
    if (Platform.environment['PUB_CACHE'] case final pubCache?
        when pubCache.isNotEmpty)
      '$pubCache${sep}hosted${sep}pub.dev',
    if (Platform.environment['LOCALAPPDATA'] case final localAppData?
        when localAppData.isNotEmpty)
      '$localAppData${sep}Pub${sep}Cache${sep}hosted${sep}pub.dev',
    if (Platform.environment['USERPROFILE'] case final userProfile?
        when userProfile.isNotEmpty)
      '$userProfile${sep}AppData${sep}Local${sep}Pub${sep}Cache${sep}hosted${sep}pub.dev',
    if (Platform.environment['HOME'] case final home? when home.isNotEmpty)
      '$home$sep.pub-cache${sep}hosted${sep}pub.dev',
  ];

  for (final path in candidates) {
    final dir = Directory(path);
    if (dir.existsSync()) return dir;
  }
  return null;
}

bool _isPluginTargetHealthy(String targetPath) {
  final sep = Platform.pathSeparator;
  try {
    final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    final resolvedPath = type == FileSystemEntityType.link
        ? Link(targetPath).resolveSymbolicLinksSync()
        : targetPath;
    final dir = Directory(resolvedPath);
    if (!dir.existsSync()) return false;
    return File('$resolvedPath${sep}pubspec.yaml').existsSync();
  } catch (_) {
    return false;
  }
}

void _deleteEntitySafely(String targetPath) {
  try {
    final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
    if (type == FileSystemEntityType.link) {
      Link(targetPath).deleteSync();
    } else if (type == FileSystemEntityType.file) {
      File(targetPath).deleteSync();
    } else if (type == FileSystemEntityType.directory) {
      Directory(targetPath).deleteSync(recursive: true);
    }
  } catch (_) {}
}

Directory? _findPluginSource({
  required String name,
  required String? recordedPath,
  required Directory? pubCacheDir,
}) {
  if (recordedPath != null && recordedPath.isNotEmpty) {
    final direct = Directory(recordedPath);
    if (direct.existsSync()) return direct;

    // Jika .flutter-plugins-dependencies dibuat dari OS lain (mis. Linux),
    // ambil nama folder paket persis (<nama>-<versi>) dan cari di Pub Cache lokal.
    if (pubCacheDir != null) {
      final exactFolderName = _lastSegment(recordedPath);
      if (exactFolderName.isNotEmpty) {
        final mapped = Directory(
          '${pubCacheDir.path}${Platform.pathSeparator}$exactFolderName',
        );
        if (mapped.existsSync()) return mapped;
      }
    }
  }

  if (pubCacheDir != null) {
    final matches = pubCacheDir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((d) {
          final folder = _lastSegment(d.path);
          return folder == name || folder.startsWith('$name-');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (matches.isNotEmpty) return matches.last;
  }

  return null;
}

void main(List<String> args) {
  final sep = Platform.pathSeparator;
  final forceSync = args.contains('--force');
  String? pubCacheArg;
  for (final arg in args) {
    if (arg.startsWith('--pub-cache=')) {
      pubCacheArg = arg.substring('--pub-cache='.length);
    }
  }

  final projectDir = Directory.current;
  final pubspecFile = File('${projectDir.path}${sep}pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln(
      'Jalankan skrip ini dari direktori root proyek (pubspec.yaml tidak ditemukan di ${projectDir.path}).',
    );
    exit(1);
  }

  final depsFile = File(
    '${projectDir.path}$sep.flutter-plugins-dependencies',
  );
  if (!depsFile.existsSync()) {
    stderr.writeln(
      '.flutter-plugins-dependencies belum ada. Jalankan "flutter pub get" terlebih dahulu.',
    );
    exit(1);
  }

  final decoded = jsonDecode(depsFile.readAsStringSync()) as Map<String, dynamic>;
  final pluginsMap = decoded['plugins'] as Map<String, dynamic>?;
  final windowsPlugins =
      (pluginsMap?['windows'] as List<dynamic>?) ?? const <dynamic>[];

  if (windowsPlugins.isEmpty) {
    stdout.writeln('Tidak ada plugin Windows di .flutter-plugins-dependencies.');
    return;
  }

  final ephemeralDir = Directory(
    '${projectDir.path}${sep}windows${sep}flutter${sep}ephemeral',
  );
  final symlinksDir = Directory('${ephemeralDir.path}$sep.plugin_symlinks');

  if (forceSync && symlinksDir.existsSync()) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      symlinksDir.renameSync('${ephemeralDir.path}${sep}plugin_symlinks_$ts');
    } catch (_) {}
  }
  if (!symlinksDir.existsSync()) {
    symlinksDir.createSync(recursive: true);
  }

  final pubCacheDir = _resolvePubHostedCache(pubCacheArg);
  var copiedCount = 0;
  var okCount = 0;

  for (final rawEntry in windowsPlugins) {
    final entry = rawEntry as Map<String, dynamic>;
    final name = entry['name'] as String;
    final recordedPath = entry['path'] as String?;
    final targetPath = '${symlinksDir.path}$sep$name';

    if (!forceSync && _isPluginTargetHealthy(targetPath)) {
      okCount++;
      continue;
    }

    final srcDir = _findPluginSource(
      name: name,
      recordedPath: recordedPath,
      pubCacheDir: pubCacheDir,
    );
    if (srcDir == null) {
      stderr.writeln(
        'Peringatan: sumber plugin "$name" tidak ditemukan (pastikan "flutter pub get" sudah dijalankan).',
      );
      continue;
    }

    _deleteEntitySafely(targetPath);
    stdout.writeln('Syncing $name dari ${srcDir.path} -> $targetPath');
    _copyDirectory(srcDir, Directory(targetPath));
    copiedCount++;
  }

  stdout.writeln(
    'Sinkronisasi plugin Windows selesai (valid: $okCount, disalin ulang: $copiedCount).',
  );
}
