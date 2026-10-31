import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// Kelas dasar klien HTTP berbasis [Dio] dengan konfigurasi standar:
/// - Batas waktu (timeout) terstandarisasi
/// - User-Agent mobile yang seragam
/// - Manajemen cookie (opsional dengan [CookieJar])
/// - Penerjemahan pesan kesalahan jaringan [DioException] yang konsisten
abstract class BaseHttpClient {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36';

  final Dio dio;
  final CookieJar? cookieJar;

  BaseHttpClient({
    String? baseUrl,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 20),
    Map<String, dynamic>? headers,
    bool enableCookies = false,
    CookieJar? customCookieJar,
    Dio? customDio,
  }) : cookieJar = enableCookies ? (customCookieJar ?? CookieJar()) : null,
       dio =
           customDio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl ?? '',
               connectTimeout: connectTimeout,
               sendTimeout: sendTimeout,
               receiveTimeout: receiveTimeout,
               headers: {'User-Agent': defaultUserAgent, ...?headers},
             ),
           ) {
    if (cookieJar != null) {
      dio.interceptors.add(CookieManager(cookieJar!));
    }
  }

  /// Menerjemahkan [DioException] ke pesan bahasa Indonesia yang ramah pengguna.
  static String describeNetworkError(
    DioException error, {
    String serviceName = 'layanan',
  }) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout =>
        'Koneksi ke $serviceName terlalu lama. Coba lagi nanti.',
      DioExceptionType.receiveTimeout =>
        'Server $serviceName belum merespons. Coba lagi nanti.',
      DioExceptionType.sendTimeout =>
        'Pengiriman data ke $serviceName gagal karena batas waktu terlampaui.',
      DioExceptionType.connectionError =>
        'Domain $serviceName tidak dapat dihubungi. Periksa internet atau DNS perangkat.',
      DioExceptionType.badResponse =>
        'Layanan $serviceName menolak permintaan (${error.response?.statusCode ?? 'tanpa status'}).',
      _ => 'Koneksi ke $serviceName gagal. Coba lagi nanti.',
    };
  }
}
