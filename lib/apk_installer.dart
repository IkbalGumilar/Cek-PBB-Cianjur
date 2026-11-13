import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'download_helper.dart' show appFolderName;

/// Unduh rilis terbaru dari GitHub, verifikasi integritasnya, dan (khusus Android/Windows) pasang sendiri.
///
/// Android: file diunduh ke berkas sementara, diverifikasi ukuran, magic header,
/// serta checksum SHA-256 (bila tersedia di rilis), lalu dibuka lewat installer sistem.
///
/// Windows/Linux: diunduh ke folder Downloads secara aman tanpa eksekusi shell.
class ApkInstaller {
  static const _channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/apk');

  /// Membersihkan nama berkas unduhan agar hanya berisi basename dengan karakter aman
  /// (`[a-zA-Z0-9._-]`) dan bebas dari karakter path traversal (`..`, `/`, `\`).
  static String sanitizeFileName(
    String rawFileName, {
    String fallback = 'CekPBBCianjur-update.apk',
  }) {
    final trimmed = rawFileName.trim();
    if (trimmed.isEmpty) return fallback;

    // Ambil hanya segmen terakhir setelah pemisah direktori Unix maupun Windows
    final base = trimmed.split(RegExp(r'[/\\]')).last.trim();
    // Ganti karakter di luar whitelist dengan underscore dan hilangkan '..'
    var cleaned = base
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    // Hindari nama berkas tersembunyi (diawali titik) atau kosong
    cleaned = cleaned.replaceFirst(RegExp(r'^\.+'), '');
    if (cleaned.isEmpty || !cleaned.contains('.')) {
      return fallback;
    }
    return cleaned;
  }

  /// Memastikan bahwa [targetFile] benar-benar berada di dalam [parentDir]
  /// (mencegah path traversal keluar dari direktori unduhan).
  static bool isPathWithinDirectory(Directory parentDir, File targetFile) {
    final parentUri = parentDir.absolute.uri.normalizePath();
    final targetUri = targetFile.absolute.uri.normalizePath();
    final parentSegs = parentUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final targetSegs = targetUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (targetSegs.length <= parentSegs.length) return false;
    for (var i = 0; i < parentSegs.length; i++) {
      final a = Platform.isWindows
          ? parentSegs[i].toLowerCase()
          : parentSegs[i];
      final b = Platform.isWindows
          ? targetSegs[i].toLowerCase()
          : targetSegs[i];
      if (a != b) return false;
    }
    return true;
  }

  /// Memeriksa kecocokan magic bytes (header biner) berkas terhadap ekstensinya.
  static bool verifyMagicHeader(List<int> headerBytes, String fileName) {
    if (headerBytes.isEmpty) return false;
    final lower = fileName.toLowerCase();

    if (lower.endsWith('.apk') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.msix')) {
      // ZIP / APK local file header: "PK\x03\x04"
      return headerBytes.length >= 4 &&
          headerBytes[0] == 0x50 &&
          headerBytes[1] == 0x4B &&
          headerBytes[2] == 0x03 &&
          headerBytes[3] == 0x04;
    }

    if (lower.endsWith('.exe')) {
      // Windows PE executable header: "MZ"
      return headerBytes.length >= 2 &&
          headerBytes[0] == 0x4D &&
          headerBytes[1] == 0x5A;
    }

    if (lower.endsWith('.gz') || lower.endsWith('.tar.gz')) {
      // GZIP magic: 0x1F 0x8B
      return headerBytes.length >= 2 &&
          headerBytes[0] == 0x1F &&
          headerBytes[1] == 0x8B;
    }

    if (lower.endsWith('.deb')) {
      // Debian archive magic: "!<arch>\n"
      const debMagic = [0x21, 0x3C, 0x61, 0x72, 0x63, 0x68, 0x3E, 0x0A];
      if (headerBytes.length < debMagic.length) return false;
      for (var i = 0; i < debMagic.length; i++) {
        if (headerBytes[i] != debMagic[i]) return false;
      }
      return true;
    }

    return true;
  }

  /// Memverifikasi bahwa berkas hasil unduhan tidak kosong, sesuai ukuran rilis,
  /// memiliki header biner (magic bytes) yang sah, serta cocok dengan checksum SHA-256
  /// apabila tersedia. Jika salah satu gagal, berkas langsung dihapus dan eksepsi dilempar.
  static Future<void> verifyDownloadedFile(
    File file, {
    required String fileName,
    int? expectedSize,
    String? expectedSha256,
  }) async {
    Future<Never> failAndDelete(String reason) async {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      throw Exception(reason);
    }

    if (!await file.exists()) {
      throw Exception('Berkas unduhan tidak ditemukan.');
    }

    final actualSize = await file.length();
    if (actualSize <= 0) {
      await failAndDelete('Berkas pembaruan yang diunduh kosong (0 byte).');
    }

    if (expectedSize != null &&
        expectedSize > 0 &&
        actualSize != expectedSize) {
      await failAndDelete(
        'Ukuran berkas unduhan ($actualSize byte) tidak sesuai dengan ukuran rilis resmi ($expectedSize byte).',
      );
    }

    final raf = await file.open();
    final List<int> headerBytes;
    try {
      headerBytes = await raf.read(8);
    } finally {
      await raf.close();
    }

    if (!verifyMagicHeader(headerBytes, fileName)) {
      await failAndDelete(
        'Format berkas pembaruan ($fileName) tidak valid atau rusak (magic header tidak cocok).',
      );
    }

    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final cleanExpected = expectedSha256
          .trim()
          .replaceFirst(RegExp(r'^sha256:', caseSensitive: false), '')
          .toLowerCase();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(cleanExpected)) {
        await failAndDelete('Format checksum SHA-256 rilis tidak valid.');
      }
      final digest = await sha256.bind(file.openRead()).first;
      final actualHash = digest.toString().toLowerCase();
      if (actualHash != cleanExpected) {
        await failAndDelete(
          'Verifikasi integritas SHA-256 gagal! Berkas unduhan rusak atau telah dimodifikasi.',
        );
      }
    } else {
      debugPrint(
        'ApkInstaller: Rilis ini tidak menyertakan checksum SHA-256 pada metadata GitHub; '
        'verifikasi dilakukan terhadap ukuran berkas dan header biner.',
      );
    }
  }

  static Future<File> download(
    String url, {
    required String fileName,
    int? expectedSize,
    String? expectedSha256,
    Directory? targetDirOverride,
    void Function(int received, int total)? onProgress,
  }) async {
    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null || parsedUri.scheme != 'https') {
      throw Exception(
        'URL unduhan pembaruan harus menggunakan protokol HTTPS.',
      );
    }

    final dir =
        targetDirOverride ??
        (Platform.isAndroid
            ? await getTemporaryDirectory()
            : await _desktopDownloadsFolder());
    final safeName = sanitizeFileName(fileName);
    final sep = Platform.pathSeparator;
    final finalFile = File('${dir.path}$sep$safeName');
    final tempFile = File('${dir.path}$sep$safeName.part');

    if (!isPathWithinDirectory(dir, finalFile) ||
        !isPathWithinDirectory(dir, tempFile)) {
      throw Exception(
        'Nama berkas pembaruan tidak aman (path traversal ditolak).',
      );
    }

    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      await Dio().download(
        url,
        tempFile.path,
        onReceiveProgress: onProgress,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
      );

      await verifyDownloadedFile(
        tempFile,
        fileName: safeName,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      );

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      return await tempFile.rename(finalFile.path);
    } catch (e) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Mengambil daftar arsitektur CPU (ABI) yang didukung perangkat Android.
  static Future<List<String>> getSupportedAbis() async {
    if (!Platform.isAndroid) return const [];
    try {
      final abis = await _channel.invokeListMethod<String>('getSupportedAbis');
      return abis ?? const [];
    } catch (_) {
      return const [];
    }
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
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Berkas instalasi pembaruan tidak ditemukan: $filePath');
    }

    if (Platform.isWindows) {
      try {
        final canonicalPath = file.absolute.path;
        final lower = canonicalPath.toLowerCase();
        if (lower.endsWith('.exe')) {
          await Process.start(canonicalPath, const [], runInShell: false);
          return 'OPENED';
        } else {
          await Process.start('explorer.exe', [
            '/select,$canonicalPath',
          ], runInShell: false);
          return 'OPENED';
        }
      } catch (e) {
        throw Exception('Gagal membuka berkas pembaruan Windows: $e');
      }
    }
    if (!Platform.isAndroid) {
      throw Exception(
        'Pembaruan otomatis hanya tersedia di Android dan Windows.',
      );
    }
    try {
      final status = await _channel.invokeMethod<String>('installApk', {
        'filePath': filePath,
      });
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
