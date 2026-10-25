import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'native_file_helper.dart';

/// Pengelola penyimpanan terpadu lintas-platform dengan pola WhatsApp:
/// 1. Data Privat (Database CSV, Cookie Sesi):
///    - Android: `/storage/emulated/0/Android/data/id.cianjur.pbb/files/`
///    - Linux: `~/.local/share/id.cianjur.pbb/`
///    - Windows: `%LOCALAPPDATA%\id.cianjur.pbb\`
/// 2. Media & Dokumen Publik (Foto SPPT, Laporan PDF/Excel, Backup .bak/.dkhp):
///    - Android: `/storage/emulated/0/Android/media/id.cianjur.pbb/` (bisa dibuka File Manager biasa)
///    - Linux: `~/.local/share/id.cianjur.pbb/`
///    - Windows: `%LOCALAPPDATA%\id.cianjur.pbb\`
class AppStorage {
  AppStorage._();

  static const appPackageName = 'id.cianjur.pbb';

  static Directory? _cachedDataDir;
  static Directory? _cachedMediaDir;

  static bool get isTestEnvironment =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      (_cachedDataDir?.path.contains('test') ?? false) ||
      (_cachedDataDir?.path.contains('tmp') ?? false);

  @visibleForTesting
  static void setMockDirectories({Directory? dataDir, Directory? mediaDir}) {
    _cachedDataDir = dataDir;
    _cachedMediaDir = mediaDir;
  }

  @visibleForTesting
  static void resetForTesting() {
    _cachedDataDir = null;
    _cachedMediaDir = null;
  }

  /// Folder data privat (khusus aplikasi).
  static Future<Directory> getDataDirectory() async {
    if (_cachedDataDir != null) return _cachedDataDir!;

    if (isTestEnvironment) {
      final tempDir = Directory.systemTemp.createTempSync('${appPackageName}_test_');
      _cachedDataDir = tempDir;
      return tempDir;
    }

    Directory dir;
    if (Platform.isAndroid) {
      dir = await getApplicationSupportDirectory();
      // Migrasi otomatis dari penyimpanan eksternal lama jika ada
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null && ext.existsSync()) {
          final oldDb = File('${ext.path}/blok_data.csv');
          final newDb = File('${dir.path}/blok_data.csv');
          if (oldDb.existsSync() && !newDb.existsSync()) {
            await oldDb.copy(newDb.path);
          }
          final oldCookies = Directory('${ext.path}/cookies');
          final newCookies = Directory('${dir.path}/cookies');
          if (oldCookies.existsSync() && !newCookies.existsSync()) {
            await newCookies.create(recursive: true);
            for (final entity in oldCookies.listSync(recursive: true)) {
              if (entity is File) {
                final rel = entity.path.substring(oldCookies.path.length);
                final dest = File('${newCookies.path}$rel');
                await dest.parent.create(recursive: true);
                await entity.copy(dest.path);
              }
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      dir = Directory('$home/.local/share/$appPackageName');
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          '';
      dir = Directory('$localAppData\\$appPackageName');
    } else if (Platform.isMacOS || Platform.isIOS) {
      dir = await getApplicationSupportDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDataDir = dir;
    return dir;
  }

  /// Folder media & dokumen publik (bisa diakses File Manager/Galeri).
  static Future<Directory> getMediaDirectory() async {
    if (_cachedMediaDir != null) return _cachedMediaDir!;

    if (isTestEnvironment) {
      final tempDir = Directory.systemTemp.createTempSync('${appPackageName}_media_test_');
      _cachedMediaDir = tempDir;
      return tempDir;
    }

    Directory dir;
    if (Platform.isAndroid) {
      try {
        final path = await NativeFileHelper.getMediaDirectoryPath();
        dir = Directory(path);
      } catch (_) {
        dir = Directory('/storage/emulated/0/Android/media/$appPackageName');
      }
    } else {
      // Pada Desktop (Linux, Windows, macOS), satukan di dalam folder aplikasi
      dir = await getDataDirectory();
    }

    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {
        // Fallback jika permission tertahan
        dir = await getDataDirectory();
      }
    }
    _ensurePrivacyMarkers(dir);
    _cachedMediaDir = dir;
    return dir;
  }

  /// Lokasi file database utama [blok_data.csv] dengan migrasi otomatis dari lokasi lama.
  static Future<File> getDatabaseFile() async {
    final dataDir = await getDataDirectory();
    final targetFile = File('${dataDir.path}/blok_data.csv');

    if (!isTestEnvironment && !await targetFile.exists()) {
      // Migrasi dari lokasi sebelumnya jika ada
      final candidateOldFiles = <File>[];
      try {
        final oldDocsDir = await getApplicationDocumentsDirectory();
        if (oldDocsDir.path != dataDir.path) {
          candidateOldFiles.add(File('${oldDocsDir.path}/blok_data.csv'));
        }
      } catch (_) {}

      if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        candidateOldFiles.add(File('$home/.local/share/pbb.cianjur/blok_data.csv'));
        candidateOldFiles.add(File('$home/.local/share/id.cianjur.cekpbb.cek_pbb_app/blok_data.csv'));
      } else if (Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
        candidateOldFiles.add(File('$localAppData\\pbb.cianjur\\blok_data.csv'));
      } else if (Platform.isAndroid) {
        candidateOldFiles.add(File('/storage/emulated/0/Android/data/pbb.cianjur/files/blok_data.csv'));
      }

      for (final oldFile in candidateOldFiles) {
        try {
          if (await oldFile.exists()) {
            await oldFile.copy(targetFile.path);
            break;
          }
        } catch (_) {}
      }
    }

    return targetFile;
  }

  /// Folder foto-foto dokumen & SPPT DHKP di dalam folder media publik.
  static Future<Directory> getPhotosDirectory() async {
    final mediaDir = await getMediaDirectory();
    final photosDir = Directory('${mediaDir.path}/photos');
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }

    // Migrasi foto-foto dari folder lama jika ada (hanya di lingkungan produksi)
    if (!isTestEnvironment) {
      try {
        final oldDirs = <Directory>[];
        final oldDocsDir = await getApplicationDocumentsDirectory();
        oldDirs.add(Directory('${oldDocsDir.path}/dhkp_photos'));

        if (Platform.isLinux) {
          final home = Platform.environment['HOME'] ?? '';
          oldDirs.add(Directory('$home/.local/share/pbb.cianjur/photos'));
        } else if (Platform.isWindows) {
          final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
          oldDirs.add(Directory('$localAppData\\pbb.cianjur\\photos'));
        } else if (Platform.isAndroid) {
          oldDirs.add(Directory('/storage/emulated/0/Android/media/pbb.cianjur/photos'));
        }

        for (final oldPhotosDir in oldDirs) {
          if (await oldPhotosDir.exists()) {
            final oldFiles = oldPhotosDir.listSync().whereType<File>();
            for (final file in oldFiles) {
              final fileName = file.uri.pathSegments.last;
              final newFile = File('${photosDir.path}/$fileName');
              if (!await newFile.exists()) {
                await file.copy(newFile.path);
              }
            }
          }
        }
      } catch (_) {}
    }

    _ensurePrivacyMarkers(photosDir);
    return photosDir;
  }

  /// Folder dokumen hasil ekspor (PDF, Excel, Bukti Bayar) di dalam media publik.
  static Future<Directory> getDocumentsDirectory() async {
    final mediaDir = await getMediaDirectory();
    final docDir = Directory('${mediaDir.path}/documents');
    if (!docDir.existsSync()) {
      docDir.createSync(recursive: true);
    }
    _ensurePrivacyMarkers(docDir);
    return docDir;
  }

  /// Folder backup cadangan terenkripsi (.bak dan .dkhp).
  static Future<Directory> getBackupsDirectory() async {
    final mediaDir = await getMediaDirectory();
    final backupDir = Directory('${mediaDir.path}/backups');
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    _ensurePrivacyMarkers(backupDir);
    return backupDir;
  }

  /// Folder sesi cookie portal Bapenda (di dalam data privat).
  static Future<Directory> getCookiesDirectory() async {
    final dataDir = await getDataDirectory();
    final cookiesDir = Directory('${dataDir.path}/cookies');
    if (!cookiesDir.existsSync()) {
      cookiesDir.createSync(recursive: true);
    }
    return cookiesDir;
  }

  /// Memastikan berkas proteksi `.nomedia` dan `.nosearch` ada di direktori tersebut.
  /// Mencegah foto/dokumen muncul di Galeri HP, Google Photos, atau indeks pencarian global Android.
  static void _ensurePrivacyMarkers(Directory dir) {
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final noMedia = File('${dir.path}/.nomedia');
      if (!noMedia.existsSync()) {
        noMedia.createSync();
      }
      final noSearch = File('${dir.path}/.nosearch');
      if (!noSearch.existsSync()) {
        noSearch.createSync();
      }
    } catch (_) {}
  }
}
