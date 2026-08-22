import 'dart:io';

import 'package:flutter/services.dart';

/// Simpan/bagikan berkas lewat Kotlin native (bukan media_store_plus): plugin
/// itu menyerialisasi hasilnya lewat Gson di sisi native, dan R8 di build
/// release mengacak nama field Kotlin-nya sehingga parsing manual di sisi
/// Dart gagal diam-diam (lihat MainActivity.kt untuk detail). Ditulis native
/// di sini supaya kontrol penuh atas formatnya.
class NativeFileHelper {
  static const _channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/files');

  /// Simpan [bytes] ke folder publik Dokumen/Cek PBB Cianjur (Android) atau
  /// Documents/Cek PBB Cianjur (desktop). Return lokasi untuk ditampilkan ke
  /// user. File dengan nama sama akan ditimpa (dipakai untuk backup harian).
  static Future<String> saveToDocuments({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Penyimpanan ke Dokumen hanya didukung di Android saat ini.',
      );
    }
    try {
      final location = await _channel.invokeMethod<String>('saveToDocuments', {
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': mimeType,
      });
      if (location == null || location.isEmpty) {
        throw Exception('Gagal menyimpan berkas.');
      }
      return location;
    } on PlatformException catch (e) {
      throw Exception('Gagal menyimpan berkas: ${e.message ?? e.code}');
    }
  }

  /// Bagikan [bytes] langsung lewat share sheet Android.
  static Future<void> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Fitur bagikan hanya tersedia di Android.');
    }
    try {
      await _channel.invokeMethod<void>('shareBytes', {
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': mimeType,
      });
    } on PlatformException catch (e) {
      throw Exception('Gagal membagikan berkas: ${e.message ?? e.code}');
    }
  }
}
