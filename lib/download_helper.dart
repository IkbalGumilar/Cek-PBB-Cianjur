import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'native_file_helper.dart';

const appFolderName = 'Cek PBB Cianjur';

/// Simpan bytes (CSV, XLSX, PDF, dll) ke folder Dokumen/[_folderName]
/// (Android) atau Downloads/[_folderName] (desktop, sebagai fallback karena
/// tidak ada folder Documents publik yang mudah diakses lintas platform).
/// Return lokasi yang ditampilkan ke user.
class DownloadHelper {
  static Future<String> saveBytes(Uint8List bytes, String fileName) async {
    if (Platform.isAndroid) {
      return NativeFileHelper.saveToDocuments(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeTypeFor(fileName),
      );
    }
    return _saveToDownloadsDesktop(bytes, fileName);
  }

  static String mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.apk')) return 'application/vnd.android.package-archive';
    return 'application/octet-stream';
  }

  static Future<String> _saveToDownloadsDesktop(Uint8List bytes, String fileName) async {
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
