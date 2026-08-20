import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'download_helper.dart' show appFolderName;

/// Unduh rilis terbaru dari GitHub, dan (khusus Android) pasang sendiri.
///
/// Android: file diunduh ke cache lalu langsung dibuka lewat installer
/// sistem — Android tidak mengizinkan instalasi sepenuhnya diam-diam tanpa
/// akses root, jadi user tetap konfirmasi "Instal" sendiri (sama seperti
/// F-Droid dan aplikasi sideload lain).
///
/// Windows/Linux: tidak ada mekanisme pasang-sendiri yang aman/generik lintas
/// platform, jadi cukup diunduh ke folder Downloads dan user yang menjalankan
/// berkasnya sendiri.
class ApkInstaller {
  static const _channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/apk');

  static Future<File> download(
    String url, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Platform.isAndroid ? await getTemporaryDirectory() : await _desktopDownloadsFolder();
    final file = File('${dir.path}/$fileName');
    await Dio().download(
      url,
      file.path,
      onReceiveProgress: onProgress,
      options: Options(receiveTimeout: const Duration(minutes: 10)),
    );
    return file;
  }

  static Future<Directory> _desktopDownloadsFolder() async {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      throw Exception('Folder Downloads tidak ditemukan di perangkat ini.');
    }
    final targetDir = Directory('${downloadsDir.path}/$appFolderName');
    await targetDir.create(recursive: true);
    return targetDir;
  }

  /// Balikin 'OPENED' kalau installer sistem berhasil dibuka, 'NEED_PERMISSION'
  /// kalau izin "Instal aplikasi tidak dikenal" belum aktif untuk aplikasi
  /// ini (wajib diaktifkan manual oleh user di Android 8+).
  static Future<String> install(String filePath) async {
    if (!Platform.isAndroid) {
      throw Exception('Pembaruan otomatis hanya tersedia di Android.');
    }
    try {
      final status = await _channel.invokeMethod<String>('installApk', {'filePath': filePath});
      return status ?? 'OPENED';
    } on PlatformException catch (e) {
      throw Exception('Gagal membuka installer: ${e.message ?? e.code}');
    }
  }

  static Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } on PlatformException {
      // Abaikan — user masih bisa buka izinnya manual lewat Pengaturan Android.
    }
  }
}
