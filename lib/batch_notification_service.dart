import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'result_screen.dart';
import 'tax_record.dart';

/// Global navigator key agar notifikasi dapat membuka halaman hasil (ResultScreen)
/// langsung saat diketuk oleh pengguna dari notification drawer sistem.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class BatchNotificationService {
  BatchNotificationService._();
  static final BatchNotificationService instance = BatchNotificationService._();

  static const MethodChannel _fgChannel =
      MethodChannel('id.cianjur.cekpbb.cek_pbb_app/batch_foreground_service');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  List<TaxRecord>? _activeRecords;

  static const int _notificationId = 1001;
  static const String _progressChannelId = 'batch_check_progress_channel';
  static const String _progressChannelName = 'Proses Pengecekan Massal';
  static const String _completeChannelId = 'batch_check_complete_channel';
  static const String _completeChannelName = 'Hasil Pengecekan Massal';

  /// Inisialisasi awal notifikasi lokal
  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Buka Aplikasi',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;

    // Bersihkan ID pengingat lama jika sebelumnya sempat tersimpan di sistem
    for (final day in [7, 14, 28]) {
      try {
        await _notifications.cancel(id: 7000 + day);
      } catch (_) {}
    }
  }

  /// Meminta izin notifikasi runtime (Android 13+ / Tiramisu ke atas)
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        final android = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          final granted = await android.requestNotificationsPermission();
          return granted ?? false;
        }
      }
    } catch (e) {
      debugPrint('Gagal meminta izin notifikasi: $e');
    }
    return true;
  }

  /// Simpan referensi data pengecekan saat ini untuk navigasi saat notifikasi diketuk
  void setActiveRecords(List<TaxRecord> records) {
    _activeRecords = records;
  }

  /// Memulai Foreground Service Android (tipe dataSync & Partial WakeLock)
  /// agar CPU dan socket jaringan tidak ditidurkan oleh Android 14/15 saat app di latar belakang / layar mati.
  Future<void> startForegroundService({
    required String title,
    required String content,
    required int progress,
    required int max,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _fgChannel.invokeMethod('startService', {
        'title': title,
        'content': content,
        'progress': progress,
        'max': max,
      });
    } catch (e) {
      debugPrint('Gagal startForegroundService: $e');
    }
  }

  /// Memperbarui judul, status, dan progress bar pada notifikasi Foreground Service
  Future<void> updateForegroundService({
    required String title,
    required String content,
    required int progress,
    required int max,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _fgChannel.invokeMethod('updateService', {
        'title': title,
        'content': content,
        'progress': progress,
        'max': max,
      });
    } catch (e) {
      debugPrint('Gagal updateForegroundService: $e');
    }
  }

  /// Menghentikan Foreground Service dan melepaskan WakeLock sistem
  Future<void> stopForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _fgChannel.invokeMethod('stopService');
    } catch (e) {
      debugPrint('Gagal stopForegroundService: $e');
    }
  }

  /// Menampilkan / memperbarui progress notifikasi berjalan (ongoing)
  Future<void> showProgress({
    required int current,
    required int total,
    required String currentNop,
    required int lunasCount,
    required int belumCount,
  }) async {
    final percent = total > 0 ? ((current / total) * 100).toStringAsFixed(0) : '0';
    final title = 'Memeriksa PBB: $current/$total NOP ($percent%)';
    final content = 'NOP: $currentNop • Lunas: $lunasCount, Belum: $belumCount';

    if (Platform.isAndroid) {
      await updateForegroundService(
        title: title,
        content: content,
        progress: current,
        max: total > 0 ? total : 100,
      );
      return;
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        _progressChannelId,
        _progressChannelName,
        channelDescription:
            'Menampilkan progress pengecekan massal PBB yang sedang berlangsung',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: total > 0 ? total : 100,
        progress: current,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        subText: '$current/$total NOP',
        color: const Color(0xFF1565C0), // Biru Pemda
      );

      final details = NotificationDetails(android: androidDetails);

      await _notifications.show(
        id: _notificationId,
        title: title,
        body: content,
        notificationDetails: details,
        payload: 'batch_in_progress',
      );
    } catch (e) {
      debugPrint('Error showProgress notification: $e');
    }
  }

  /// Menampilkan notifikasi selesai yang MENGGANTIKAN notifikasi progress (ID sama 1001)
  Future<void> showCompleted({
    required int total,
    required int lunasCount,
    required int belumCount,
    required int blacklistCount,
    required int gagalCount,
  }) async {
    await stopForegroundService();
    try {
      final androidDetails = AndroidNotificationDetails(
        _completeChannelId,
        _completeChannelName,
        channelDescription:
            'Notifikasi penyelesaian pengecekan massal PBB di latar belakang',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        color: const Color(0xFF2E7D32), // Hijau Sukses
        subText: 'Selesai',
      );

      final details = NotificationDetails(android: androidDetails);
      final ringkasan =
          'Lunas: $lunasCount, Belum: $belumCount${blacklistCount > 0 ? ", Blacklist: $blacklistCount" : ""}${gagalCount > 0 ? ", Gagal: $gagalCount" : ""}';

      await _notifications.show(
        id: _notificationId,
        title: '✅ Pengecekan PBB Selesai ($total NOP)',
        body: '$ringkasan. Ketuk untuk melihat laporan hasil lengkap.',
        notificationDetails: details,
        payload: 'show_batch_result',
      );
    } catch (e) {
      debugPrint('Error showCompleted notification: $e');
    }
  }

  /// Menampilkan notifikasi bahwa proses dibatalkan (MENGGANTIKAN notifikasi progress, ID sama 1001)
  /// Pengguna dapat mengetuk notifikasi ini untuk membuka dan melihat hasil parsial.
  Future<void> showCancelled({
    required int current,
    required int total,
    required int lunasCount,
    required int belumCount,
    int blacklistCount = 0,
    int gagalCount = 0,
  }) async {
    await stopForegroundService();
    try {
      final androidDetails = AndroidNotificationDetails(
        _completeChannelId,
        _completeChannelName,
        channelDescription:
            'Notifikasi ketika pengecekan massal PBB dihentikan oleh pengguna',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        color: const Color(0xFFE65100), // Oranye Peringatan
        subText: 'Dibatalkan',
      );

      final details = NotificationDetails(android: androidDetails);
      final ringkasan =
          'Lunas: $lunasCount, Belum: $belumCount${blacklistCount > 0 ? ", Blacklist: $blacklistCount" : ""}${gagalCount > 0 ? ", Gagal: $gagalCount" : ""}';

      await _notifications.show(
        id: _notificationId,
        title: '⚠️ Pengecekan PBB Dibatalkan ($current/$total NOP)',
        body: '$ringkasan. Ketuk untuk melihat hasil yang sempat diperiksa.',
        notificationDetails: details,
        payload: 'show_batch_result',
      );
    } catch (e) {
      debugPrint('Error showCancelled notification: $e');
    }
  }

  /// Hapus notifikasi pengecekan jika diperlukan
  Future<void> cancel() async {
    await stopForegroundService();
    try {
      await _notifications.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
  }

  /// Handler ketika pengguna mengetuk notifikasi dari notification bar
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload == 'show_batch_result') {
      _navigateToResult();
    }
  }

  void _navigateToResult() {
    final nav = rootNavigatorKey.currentState;
    if (nav == null || _activeRecords == null || _activeRecords!.isEmpty) return;

    nav.push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(records: _activeRecords!),
      ),
    );
  }
}
