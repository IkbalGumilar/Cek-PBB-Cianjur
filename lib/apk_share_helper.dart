import 'dart:io';

import 'package:flutter/services.dart';

import 'download_helper.dart';

class ApkShareHelper {
  static const _channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/apk');

  /// Minta sisi native (Kotlin) menyalin APK aplikasi yang sedang berjalan ke
  /// cache internal aplikasi (native yang menyalin, bukan Dart, supaya tidak
  /// gagal baca path sistem seperti /data/app/...), simpan permanen ke
  /// folder Dokumen/Cek PBB Cianjur, lalu buka share sheet Android
  /// (WhatsApp, Quick Share, Bluetooth, dll).
  ///
  /// Share sheet dibuka lewat Intent native (bukan package share_plus):
  /// share_plus menunggu user memilih aplikasi tujuan dulu sebelum
  /// hasilnya dikembalikan ke Dart, dan pemanggilan berikutnya sebelum
  /// pilihan itu dibuat akan "memaksa selesai" panggilan sebelumnya tanpa
  /// share sheet pernah benar-benar tampil ke user.
  ///
  /// Return lokasi penyimpanan permanennya untuk ditampilkan ke user, atau
  /// null kalau share sheet berhasil dibuka tapi salinan ke folder Dokumen
  /// gagal/macet (bukan kegagalan fatal, share sheet tetap sudah terbuka).
  static Future<String?> shareApk() async {
    if (!Platform.isAndroid) {
      throw Exception('Fitur bagikan aplikasi hanya tersedia di Android.');
    }

    final String exportedPath;
    try {
      final path = await _channel.invokeMethod<String>('exportApk');
      if (path == null || path.isEmpty) {
        throw Exception('Gagal menyiapkan berkas APK.');
      }
      exportedPath = path;
    } on PlatformException catch (e) {
      throw Exception('Gagal menyiapkan berkas APK: ${e.message ?? e.code}');
    }

    final exportedFile = File(exportedPath);
    if (!await exportedFile.exists()) {
      throw Exception('Berkas APK tidak ditemukan di $exportedPath.');
    }

    // Buka share sheet duluan (pakai berkas hasil export, tidak menunggu
    // proses simpan ke folder Dokumen) — supaya kalau proses simpan itu
    // macet/lambat, itu tidak menahan share sheet untuk terbuka.
    try {
      await _channel.invokeMethod<void>('shareApk');
    } on PlatformException catch (e) {
      throw Exception('Gagal membuka share sheet: ${e.message ?? e.code}');
    }

    final bytes = await exportedFile.readAsBytes();
    try {
      final savedLocation = await DownloadHelper.saveBytes(
        bytes,
        'CekPBBCianjur.apk',
      ).timeout(const Duration(seconds: 15));
      return savedLocation;
    } catch (_) {
      // Share sheet sudah terbuka (tujuan utama tercapai); gagal/macetnya
      // penyimpanan salinan permanen ke folder Dokumen bukan alasan untuk
      // menampilkan error ke user.
      return null;
    }
  }
}
