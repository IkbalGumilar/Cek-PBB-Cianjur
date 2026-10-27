import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';
import 'native_file_helper.dart';

const appFolderName = 'Cek PBB Cianjur';

/// Simpan bytes (CSV, XLSX, PDF, .bak, .dkhp, dll) ke folder publik terpadu:
/// - Android: `Android/media/id.cianjur.pbb/[subfolder]/` (bisa diakses File Manager)
/// - Linux: `~/.local/share/id.cianjur.pbb/[subfolder]/`
/// - Windows: `%LOCALAPPDATA%\id.cianjur.pbb\[subfolder]\`
class DownloadHelper {
  static Future<String> saveBytes(
    Uint8List bytes,
    String fileName, {
    String? subfolder,
  }) async {
    final lower = fileName.toLowerCase();
    final isBackup = lower.endsWith('.bak') || lower.endsWith('.dkhp');
    final folder = subfolder ?? (isBackup ? 'backups' : 'documents');

    if (Platform.isAndroid) {
      try {
        return await NativeFileHelper.saveToMedia(
          bytes: bytes,
          fileName: fileName,
          subfolder: folder,
          mimeType: mimeTypeFor(fileName),
        );
      } catch (_) {
        return await NativeFileHelper.saveToDocuments(
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeTypeFor(fileName),
        );
      }
    }

    try {
      final Directory targetDir;
      if (folder == 'backups') {
        targetDir = await AppStorage.getBackupsDirectory();
      } else if (folder == 'documents') {
        targetDir = await AppStorage.getDocumentsDirectory();
      } else {
        final mediaDir = await AppStorage.getMediaDirectory();
        final customDir = Directory('${mediaDir.path}/$folder');
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        targetDir = customDir;
      }
      final targetFile = File('${targetDir.path}/$fileName');
      await targetFile.writeAsBytes(bytes);
      return targetFile.path;
    } catch (_) {
      return _saveToDownloadsDesktop(bytes, fileName);
    }
  }

  static String mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.apk')) {
      return 'application/vnd.android.package-archive';
    }
    return 'application/octet-stream';
  }

  static Future<String> _saveToDownloadsDesktop(
    Uint8List bytes,
    String fileName,
  ) async {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      throw Exception('Folder Downloads tidak ditemukan di perangkat ini.');
    }

    final targetDir = Directory('${downloadsDir.path}/$appFolderName');
    await targetDir.create(recursive: true);
    final targetFile = File('${targetDir.path}/$fileName');
    await targetFile.writeAsBytes(bytes);
    return targetFile.path;
  }
}
