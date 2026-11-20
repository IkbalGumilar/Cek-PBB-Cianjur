import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apakah aplikasi berjalan pada perangkat seluler (Android atau iOS).
bool get isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Apakah aplikasi berjalan pada perangkat komputer desktop (Windows, Linux, macOS).
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Menerjemahkan berbagai pengecualian teknis (jaringan, berkas, plugin OS,
/// format data) menjadi pesan bahasa Indonesia singkat yang ramah bagi
/// pengguna akhir tanpa membocorkan nama kelas exception atau detail teknis.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Terjadi kendala. Silakan coba lagi.',
}) {
  if (error is SocketException) {
    return 'Tidak dapat terhubung ke internet. Periksa koneksi Anda lalu coba lagi.';
  }
  if (error is TimeoutException) {
    return 'Waktu tunggu koneksi habis. Silakan coba beberapa saat lagi.';
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Koneksi terlalu lambat atau server belum merespons. Silakan coba lagi.';
      case DioExceptionType.connectionError:
        return 'Tidak ada koneksi internet atau server sedang tidak dapat dijangkau.';
      case DioExceptionType.badCertificate:
        return 'Koneksi aman ke server tidak dapat diverifikasi.';
      case DioExceptionType.cancel:
        return 'Permintaan dibatalkan.';
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          return 'Sesi akses tidak berlaku. Silakan masuk ulang lalu coba lagi.';
        }
        if (status == 404) {
          return 'Data atau layanan yang diminta tidak ditemukan.';
        }
        if (status == 429) {
          return 'Terlalu banyak permintaan. Tunggu sebentar lalu coba lagi.';
        }
        if (status != null && status >= 500) {
          return 'Server layanan sedang mengalami gangguan. Coba beberapa saat lagi.';
        }
        return 'Layanan belum dapat memproses permintaan. Silakan coba lagi.';
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return 'Tidak dapat terhubung ke internet. Periksa koneksi Anda lalu coba lagi.';
        }
        return fallback;
    }
  }
  if (error is MissingPluginException || error is UnsupportedError) {
    return 'Fitur ini tidak tersedia pada perangkat yang Anda gunakan.';
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('network') || code.contains('sign_in_failed')) {
      return 'Gagal terhubung ke layanan perangkat. Periksa koneksi internet Anda.';
    }
    if (code.contains('cancel')) {
      return 'Tindakan dibatalkan.';
    }
    if (code.contains('permission') || code.contains('denied')) {
      return 'Izin akses perangkat belum diberikan.';
    }
    return fallback;
  }
  if (error is FileSystemException) {
    return 'Berkas tidak dapat diakses atau penyimpanan perangkat penuh.';
  }
  if (error is FormatException) {
    final msg = error.message.trim();
    if (_looksCleanIndonesianMessage(msg)) return msg;
    return 'Format data atau berkas tidak sesuai.';
  }

  final raw = error.toString().trim();
  final cleaned = raw
      .replaceFirst(RegExp(r'^(Exception|StateError|ArgumentError|FormatException):\s*'), '')
      .trim();

  if (cleaned.isEmpty || _looksTechnical(cleaned)) {
    return fallback;
  }
  return cleaned;
}

/// Mengambil nama berkas yang rapi dari path penyimpanan sistem agar pengguna
/// tidak melihat jalur folder internal mentah (`/storage/emulated/0/...`).
String friendlyFileName(String path) {
  final normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return 'berkas';
  final idx = normalized.lastIndexOf('/');
  return idx >= 0 && idx + 1 < normalized.length
      ? normalized.substring(idx + 1)
      : normalized;
}

bool _looksTechnical(String msg) {
  if (msg.length > 220) return true;
  final lower = msg.toLowerCase();
  const technicalMarkers = [
    'exception',
    'stacktrace',
    'errno',
    'os error',
    'socketexception',
    'dioexception',
    'platformexception',
    'filesystemexception',
    'missingpluginexception',
    'failed host lookup',
    'handshakeexception',
    'connection refused',
    'clientexception',
    'rangeerror',
    'null check operator',
    'type \'',
    'is not a subtype of',
    'invalid argument',
    'unhandled',
    'httpstatus',
    'statuscode',
    'instance of \'',
    'dart-define',
    'env.desktop.json',
    'google cloud console',
    'base32',
    'otpauth',
  ];
  for (final marker in technicalMarkers) {
    if (lower.contains(marker)) return true;
  }
  return false;
}

bool _looksCleanIndonesianMessage(String msg) {
  if (msg.isEmpty || _looksTechnical(msg)) return false;
  return msg.length <= 160;
}
