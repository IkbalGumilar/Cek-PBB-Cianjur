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

  static const _targetUrl =
      'https://cektagihan.cianjurkab.v-tax.id/portlet.php';
  static const _probeUrl = 'https://www.gstatic.com/generate_204';
  static const _slowThreshold = Duration(seconds: 3);
  static const _normalCheckInterval = Duration(seconds: 90);
  static const _retryCheckInterval = Duration(seconds: 30);

  final status = ValueNotifier<NetworkStatus>(NetworkStatus.normal);

  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 6)));
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _checking = false;
  bool _isPaused = false;

  void start() {
    _isPaused = false;
    _subscription ??= Connectivity().onConnectivityChanged.listen(
      (_) => _check(),
    );
    _scheduleNextCheck(_normalCheckInterval);
    // Ditunda sebentar supaya tidak rebutan koneksi dengan permintaan
    // captcha yang juga jalan otomatis saat layar pertama dibuka.
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isPaused) _check();
    });
  }

  /// Pause polling saat aplikasi masuk ke background agar tidak memboroskan
  /// baterai dan kuota data untuk ping server yang tidak terlihat pengguna.
  void pause() {
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Resume polling saat aplikasi kembali ke foreground.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    checkNow();
    _scheduleNextCheck(_normalCheckInterval);
  }

  void _scheduleNextCheck(Duration interval) {
    _timer?.cancel();
    _timer = Timer(interval, () {
      if (!_isPaused) {
        _check();
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _subscription?.cancel();
    _subscription = null;
    status.value = NetworkStatus.normal;
  }

  /// Paksa cek ulang sekarang juga — dipanggil saat app kembali ke
  /// foreground, supaya status jaringan tidak "nyangkut" di kondisi lama
  /// yang mungkin sudah tidak relevan (mis. koneksi sempat terputus saat
  /// app di-background lalu pulih lagi).
  void checkNow() => unawaited(_check());

  Future<void> _check() async {
    if (_checking || _isPaused) return;
    _checking = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none) ||
          connectivity.isEmpty) {
        status.value = NetworkStatus.noInternet;
        _scheduleNextCheck(_retryCheckInterval);
        return;
      }

      if (!await _probe(_probeUrl)) {
        status.value = NetworkStatus.noInternet;
        _scheduleNextCheck(_retryCheckInterval);
        return;
      }

      final targetStatus = await _probeTarget();
      status.value = targetStatus;
      if (targetStatus == NetworkStatus.serverError) {
        _scheduleNextCheck(_retryCheckInterval);
      } else {
        _scheduleNextCheck(_normalCheckInterval);
      }
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
