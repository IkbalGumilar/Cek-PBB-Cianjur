import 'dart:io';

void copyDir(Directory src, Directory dst) {
  if (!dst.existsSync()) {
    dst.createSync(recursive: true);
  }
  for (var entity in src.listSync(recursive: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final newPath = '${dst.path}\\$name';
    if (entity is Directory) {
      copyDir(entity, Directory(newPath));
    } else if (entity is File) {
      entity.copySync(newPath);
    }
  }
}

void main() {
  final pubCache = r'C:\Users\ikbal\AppData\Local\Pub\Cache\hosted\pub.dev';
  final plugins = [
    'connectivity_plus',
    'dynamic_color',
    'file_selector_windows',
    'flutter_local_notifications_windows',
    'flutter_secure_storage_windows',
    'image_picker_windows',
    'jni',
    'local_auth_windows',
    'path_provider_windows',
    'printing',
    'screen_brightness_windows',
    'shared_preferences_windows',
    'url_launcher_windows',
    'windows_file_picker',
  ];

  final symlinksDir = Directory(r'Z:\windows\flutter\ephemeral\.plugin_symlinks');
  
  // Robust directory reset for SMB shares
  bool isClean = false;
  try {
    final testDir = Directory('${symlinksDir.path}\\.test_access');
    testDir.createSync(recursive: true);
    testDir.deleteSync();
    isClean = true;
  } catch (_) {
    isClean = false;
  }

  if (!isClean) {
    try {
      final renamed = 'Z:\\windows\\flutter\\ephemeral\\plugin_symlinks_${DateTime.now().millisecondsSinceEpoch}';
      symlinksDir.renameSync(renamed);
    } catch (_) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      Process.runSync('powershell', [
        '-NoProfile',
        '-Command',
        'Rename-Item -Path "Z:\\windows\\flutter\\ephemeral\\.plugin_symlinks" -NewName "plugin_symlinks_$ts" -ErrorAction SilentlyContinue',
      ]);
    }
    symlinksDir.createSync(recursive: true);
  }

  final cacheDir = Directory(pubCache);
  if (!cacheDir.existsSync()) {
    print('Pub cache not found at $pubCache');
    exit(1);
  }

  final cacheEntries = cacheDir.listSync().whereType<Directory>().toList();

  for (final plugin in plugins) {
    // Find matching directory in pub cache (e.g. connectivity_plus-7.3.1)
    final matched = cacheEntries.where((d) {
      final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
      return name == plugin || name.startsWith('$plugin-');
    }).toList();

    if (matched.isEmpty) {
      print('Warning: plugin $plugin not found in pub cache!');
      continue;
    }

    // Pick highest version if multiple
    matched.sort((a, b) => a.path.compareTo(b.path));
    final srcDir = matched.last;
    final target = '${symlinksDir.path}\\$plugin';

    final l = Link(target);
    if (l.existsSync()) {
      try { l.deleteSync(); } catch (_) {}
    }
    final f = File(target);
    if (f.existsSync()) {
      try { f.deleteSync(); } catch (_) {}
    }
    final d = Directory(target);
    if (d.existsSync()) {
      try { d.deleteSync(recursive: true); } catch (_) {}
    }

    print('Syncing $plugin from ${srcDir.path} -> $target');
    copyDir(srcDir, Directory(target));
  }

  print('All Windows plugin dependencies synced successfully!');
}
