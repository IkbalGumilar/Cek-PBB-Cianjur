import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';
import 'native_file_helper.dart';

const appFolderName = 'Cek PBB Cianjur';

/// Simpan bytes (CSV, XLSX, PDF, .bak, .dkhp, dll) ke penyimpanan:
/// - Menggunakan dialog "Simpan Sebagai" (Save As) bawaan OS (Storage Access Framework di Android,
///   portal XDG di Linux, dialog Common Item di Windows). Pengguna dapat memilih lokasi penyimpanan
///   dan nama berkas secara leluasa tanpa memerlukan izin penyimpanan khusus.
/// - Fallback ke folder Dokumen/Media aplikasi bila platform tidak mendukung FilePicker.saveFile.
class DownloadHelper {
  static Future<String?> saveBytes(
    Uint8List bytes,
    String fileName, {
    String? subfolder,
    String? dialogTitle,
    bool useSaveAs = true,
  }) async {
    // Sanitasi nama file untuk mencegah Path Traversal (CWE-22)
    final cleanFileName = fileName
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll('..', '')
        .trim();
    final effectiveFileName =
        cleanFileName.isEmpty ? 'download.bin' : cleanFileName;

    if (useSaveAs) {
      final mime = mimeTypeFor(effectiveFileName);
      final ext = _allowedExtensionFor(effectiveFileName);

      try {
        final uri = await FilePicker.saveFile(
          dialogTitle: dialogTitle ?? 'Simpan Berkas',
          fileName: effectiveFileName,
          bytes: bytes,
          mimeType: mime,
          type: ext != null ? FileType.custom : FileType.any,
          allowedExtensions: ext != null ? [ext] : null,
        );

        if (uri == null) {
          // Pengguna membatalkan dialog penyimpanan
          return null;
        }

        if (uri.isScheme('file')) {
          try {
            return uri.toFilePath();
          } catch (_) {
            return uri.path;
          }
        }
        return uri.toString();
      } catch (_) {
        // Fallback jika platform tidak mendukung saveFile
      }
    }

    return _saveFallback(bytes, effectiveFileName, subfolder: subfolder);
  }

  static String? _allowedExtensionFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot != -1 && dot < fileName.length - 1) {
      return fileName.substring(dot + 1).toLowerCase();
    }
    return null;
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
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  static Future<String> _saveFallback(
    Uint8List bytes,
    String effectiveFileName, {
    String? subfolder,
  }) async {
    final lower = effectiveFileName.toLowerCase();
    final isBackup = lower.endsWith('.bak') || lower.endsWith('.dkhp');
    final folder = subfolder ?? (isBackup ? 'backups' : 'documents');

    if (Platform.isAndroid) {
      try {
        return await NativeFileHelper.saveToMedia(
          bytes: bytes,
          fileName: effectiveFileName,
          subfolder: folder,
          mimeType: mimeTypeFor(effectiveFileName),
        );
      } catch (_) {
        return await NativeFileHelper.saveToDocuments(
          bytes: bytes,
          fileName: effectiveFileName,
          mimeType: mimeTypeFor(effectiveFileName),
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
      final targetFile = File('${targetDir.path}/$effectiveFileName');
      await targetFile.writeAsBytes(bytes);
      return targetFile.path;
    } catch (_) {
      return _saveToDownloadsDesktop(bytes, effectiveFileName);
    }
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
