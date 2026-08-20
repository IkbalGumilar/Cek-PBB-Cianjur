import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum NetworkStatus { normal, noInternet, slowInternet, serverError }

/// Memantau koneksi internet perangkat & kesehatan server situs PBB secara
/// berkala, supaya UI bisa kasih peringatan dini kalau jaringan lambat/mati
/// atau server situs asli sedang bermasalah.
class ConnectivityMonitor {
  ConnectivityMonitor._();
  static final instance = ConnectivityMonitor._();

  static const _targetUrl = 'https://cektagihan.cianjurkab.v-tax.id/portlet.php';
  static const _probeUrl = 'https://www.gstatic.com/generate_204';
  static const _slowThreshold = Duration(seconds: 3);
  static const _checkInterval = Duration(seconds: 20);

  final status = ValueNotifier<NetworkStatus>(NetworkStatus.normal);

  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6)));
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _checking = false;

  void start() {
    _subscription = Connectivity().onConnectivityChanged.listen((_) => _check());
    _timer = Timer.periodic(_checkInterval, (_) => _check());
    // Ditunda sebentar supaya tidak rebutan koneksi dengan permintaan
    // captcha yang juga jalan otomatis saat layar pertama dibuka.
    Future.delayed(const Duration(seconds: 3), _check);
  }

  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    status.dispose();
  }

  /// Paksa cek ulang sekarang juga — dipanggil saat app kembali ke
  /// foreground, supaya status jaringan tidak "nyangkut" di kondisi lama
  /// yang mungkin sudah tidak relevan (mis. koneksi sempat terputus saat
  /// app di-background lalu pulih lagi).
  void checkNow() => unawaited(_check());

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        status.value = NetworkStatus.noInternet;
        return;
      }

      if (!await _probe(_probeUrl)) {
        status.value = NetworkStatus.noInternet;
        return;
      }

      status.value = await _probeTarget();
    } finally {
      _checking = false;
    }
  }

  Future<bool> _probe(String url) async {
    try {
      await _dio.head<void>(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  Future<NetworkStatus> _probeTarget() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.get<void>(
        _targetUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      );
      stopwatch.stop();

      if ((response.statusCode ?? 0) >= 500) {
        return NetworkStatus.serverError;
      }
      if (stopwatch.elapsed > _slowThreshold) {
        return NetworkStatus.slowInternet;
      }
      return NetworkStatus.normal;
    } on DioException {
      return NetworkStatus.serverError;
    }
  }
}
