import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'monitoring/monitoring_wilayah_screen.dart';
import 'monitoring/staff_dhkp_sync_dialog.dart';
import 'monitoring/staff_dhkp_sync_manager.dart';
import 'monitoring/staff_dhkp_sync_service.dart';
import 'result_screen.dart';
import 'staff_portal_client.dart';
import 'tax_record.dart';
import 'theme_controller.dart';

/// Global navigator key agar notifikasi dapat membuka halaman hasil (ResultScreen)
/// langsung saat diketuk oleh pengguna dari notification drawer sistem.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class BatchNotificationService {
  BatchNotificationService._();
  static final BatchNotificationService instance = BatchNotificationService._();

  static const MethodChannel _fgChannel = MethodChannel(
    'id.cianjur.cekpbb.cek_pbb_app/batch_foreground_service',
  );

  static final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  /// Aliran aksi dari tombol notifikasi interaktif (pause, resume, hide, cancel)
  static Stream<String> get actionStream => _actionController.stream;

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

    _fgChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments as String?;
        if (action != null) {
          _actionController.add(action);
        }
      }
    });

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Buka Aplikasi',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Cek PBB Cianjur',
      appUserModelId: 'IkbalGumilar.CekPBBCianjur.App.1',
      guid: '9B7E3E5D-4921-4F25-9B21-8848CBE1A964',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    try {
      await _notifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final resp = launchDetails.notificationResponse;
        if (resp != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onNotificationTapped(resp);
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal inisialisasi flutter_local_notifications: $e');
    }

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
        final android = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
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
    bool isPaused = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _fgChannel.invokeMethod('startService', {
        'title': title,
        'content': content,
        'progress': progress,
        'max': max,
        'isPaused': isPaused,
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
    bool? isPaused,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _fgChannel.invokeMethod('updateService', {
        'title': title,
        'content': content,
        'progress': progress,
        'max': max,
        'isPaused': ?isPaused,
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

  /// Memeriksa apakah Foreground Service Android saat ini sedang aktif
  Future<bool> isForegroundServiceRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final running = await _fgChannel.invokeMethod<bool>('isRunning');
      return running ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Notifikasi awal saat proses pengecekan massal atau sinkronisasi dimulai.
  /// Di Desktop (Linux & Windows), ini adalah SATU-SATUNYA notifikasi selama proses berlangsung
  /// hingga proses selesai, mencegah spam popup notifikasi setiap kali NOP dicek.
  Future<void> showStarted({
    required String title,
    required String content,
    required int total,
  }) async {
    if (Platform.isAndroid) {
      await startForegroundService(
        title: title,
        content: content,
        progress: 0,
        max: total,
      );
      return;
    }

    // Khusus Desktop (Linux & Windows): Munculkan 1 notifikasi bahwa proses dimulai
    if (!_isInitialized) return;
    try {
      final details = NotificationDetails(
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.low,
        ),
      );
      await _notifications.show(
        id: _notificationId,
        title: title,
        body: content,
        notificationDetails: details,
        payload: 'batch_in_progress',
      );
    } catch (e) {
      debugPrint('Error showStarted notification: $e');
    }
  }

  /// Menampilkan / memperbarui progress notifikasi berjalan (ongoing)
  /// Format sesuai permintaan:
  /// Baris 1: Mengecek berapa dari berapa. NOP yg di cek
  /// Baris 2: persentase
  /// Bar progres
  /// Tombol: Jeda / Lanjutkan, Sembunyikan, Batalkan
  Future<void> showProgress({
    required int current,
    required int total,
    required String currentNop,
    required int lunasCount,
    required int belumCount,
    bool isPaused = false,
  }) async {
    final percent = total > 0
        ? ((current / total) * 100).toStringAsFixed(0)
        : '0';

    final title = 'Mengecek $current dari $total. NOP: $currentNop';
    final content = '$percent% • Lunas: $lunasCount, Belum: $belumCount';

    if (Platform.isAndroid) {
      await updateForegroundService(
        title: title,
        content: content,
        progress: current,
        max: total > 0 ? total : 100,
        isPaused: isPaused,
      );
      return;
    }

    // Di Desktop (Linux & Windows): jangan tampilkan notifikasi berkala per NOP
    // agar tidak menimbulkan popup mengganggu secara berulang di layar.
    if (Platform.isLinux || Platform.isWindows) {
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
        subText: '$percent%',
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
    if (!_isInitialized) return;
    try {
      await _notifications.cancel(id: _notificationId);
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

      final details = NotificationDetails(
        android: androidDetails,
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.normal,
        ),
      );
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
    if (!_isInitialized) return;
    try {
      await _notifications.cancel(id: _notificationId);
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

      final details = NotificationDetails(
        android: androidDetails,
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.normal,
        ),
      );
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

  /// Notifikasi progres sinkronisasi DHKP dari Portal Staf di latar belakang
  Future<void> showStaffSyncProgress({
    required int currentBlok,
    required int totalBloks,
    required String currentBlokName,
    required int updatedPaid,
    required int newSppt,
    bool isPaused = false,
  }) async {
    final percent = totalBloks > 0
        ? ((currentBlok / totalBloks) * 100).toStringAsFixed(0)
        : '0';

    final title =
        'Mengecek Blok $currentBlok dari $totalBloks. $currentBlokName';
    final content = '$percent% • $updatedPaid Lunas Baru, $newSppt SPPT Baru';

    if (Platform.isAndroid) {
      final fgRunning = await isForegroundServiceRunning();
      if (fgRunning) {
        await updateForegroundService(
          title: title,
          content: content,
          progress: currentBlok,
          max: totalBloks > 0 ? totalBloks : 100,
          isPaused: isPaused,
        );
        return;
      }
    }

    // Di Desktop: abaikan progress berkala per-blok untuk mencegah popup berulang
    if (Platform.isLinux || Platform.isWindows) {
      return;
    }

    if (!_isInitialized) return;
    try {
      final androidDetails = AndroidNotificationDetails(
        _progressChannelId,
        _progressChannelName,
        channelDescription:
            'Menampilkan progress sinkronisasi DHKP yang sedang berlangsung',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: totalBloks > 0 ? totalBloks : 100,
        progress: currentBlok,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        subText: '$percent%',
        color: const Color(0xFF00796B),
      );

      final details = NotificationDetails(android: androidDetails);
      await _notifications.show(
        id: _notificationId,
        title: title,
        body: content,
        notificationDetails: details,
        payload: 'staff_sync_in_progress',
      );
    } catch (e) {
      debugPrint('Error showStaffSyncProgress notification: $e');
    }
  }

  /// Notifikasi penyelesaian sinkronisasi DHKP dari Portal Staf
  Future<void> showStaffSyncCompleted({
    required int updatedPaidCount,
    required int newSpptCount,
    required int totalChecked,
    String? blokLabel,
  }) async {
    await stopForegroundService();
    if (!_isInitialized) return;
    try {
      await _notifications.cancel(id: _notificationId);
      final androidDetails = AndroidNotificationDetails(
        _completeChannelId,
        _completeChannelName,
        channelDescription:
            'Notifikasi penyelesaian sinkronisasi portal staf PBB di latar belakang',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        color: const Color(0xFF2E7D32),
        subText: 'Sinkronisasi Selesai',
      );

      final details = NotificationDetails(
        android: androidDetails,
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.normal,
        ),
      );
      final body =
          '$updatedPaidCount NOP diperbarui Lunas, $newSpptCount SPPT Baru terdeteksi ($totalChecked baris diperiksa).';

      await _notifications.show(
        id: _notificationId,
        title: '✅ Sinkronisasi Portal Staf Selesai (${blokLabel ?? "DHKP"})',
        body: body,
        notificationDetails: details,
        payload: 'staff_sync_completed',
      );
    } catch (e) {
      debugPrint('Error showStaffSyncCompleted notification: $e');
    }
  }

  /// Notifikasi pembatalan sinkronisasi DHKP dari Portal Staf
  Future<void> showStaffSyncCancelled({
    required int currentBlok,
    required int totalBloks,
    required int updatedPaidCount,
    required int newSpptCount,
    String? blokLabel,
  }) async {
    await stopForegroundService();
    if (!_isInitialized) return;
    try {
      await _notifications.cancel(id: _notificationId);
      final androidDetails = AndroidNotificationDetails(
        _completeChannelId,
        _completeChannelName,
        channelDescription:
            'Notifikasi pembatalan sinkronisasi portal staf PBB',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        color: const Color(0xFFE65100),
        subText: 'Dibatalkan',
      );

      final details = NotificationDetails(
        android: androidDetails,
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.normal,
        ),
      );
      final body =
          'Dihentikan pada blok $currentBlok/$totalBloks. $updatedPaidCount Lunas diperbarui, $newSpptCount SPPT Baru.';

      await _notifications.show(
        id: _notificationId,
        title: '⚠️ Sinkronisasi DHKP Dibatalkan (${blokLabel ?? "DHKP"})',
        body: body,
        notificationDetails: details,
        payload: 'staff_sync_cancelled',
      );
    } catch (e) {
      debugPrint('Error showStaffSyncCancelled notification: $e');
    }
  }

  /// Hapus notifikasi pengecekan jika diperlukan
  Future<void> cancel() async {
    await stopForegroundService();
    if (!_isInitialized) return;
    try {
      await _notifications.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
  }

  /// Handler ketika pengguna mengetuk notifikasi dari notification bar
  @visibleForTesting
  void onNotificationTapped(NotificationResponse response) =>
      _onNotificationTapped(response);

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload == 'show_batch_result') {
      _navigateToResult();
    } else if (response.payload == 'staff_sync_completed') {
      _navigateToStaffPortalAndReport(showReport: true);
    } else if (response.payload == 'staff_sync_in_progress') {
      _navigateToStaffPortalAndReport(showReport: false);
    } else if (response.payload == 'staff_sync_cancelled') {
      _navigateToStaffPortalAndReport(showReport: true);
    }
  }

  void _navigateToResult() {
    final nav = rootNavigatorKey.currentState;
    if (nav == null || _activeRecords == null || _activeRecords!.isEmpty) {
      return;
    }

    nav.push(
      MaterialPageRoute(builder: (_) => ResultScreen(records: _activeRecords!)),
    );
  }

  void _navigateToStaffPortalAndReport({bool showReport = true}) {
    if (showReport) {
      StaffDhkpSyncManager.instance.dismiss();
    }

    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      return;
    }

    final client = StaffDhkpSyncManager.instance.client ?? StaffPortalClient();
    final themeController = ThemeController.current;
    final outcome =
        StaffDhkpSyncService.lastOutcome ??
        StaffDhkpSyncManager.instance.outcome;

    if (!MonitoringWilayahScreen.isCurrentlyOpen) {
      nav.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'MonitoringWilayahScreen'),
          builder: (_) => MonitoringWilayahScreen(
            client: client,
            themeController: themeController,
            initialReportOutcome: showReport ? outcome : null,
          ),
        ),
      );
    } else {
      final context = nav.overlay?.context ?? rootNavigatorKey.currentContext;
      if (context != null) {
        if (showReport && outcome != null) {
          showStaffDhkpSyncReportDialog(context, outcome);
        } else if (!showReport) {
          StaffDhkpSyncManager.instance.openSheet(context);
        }
      }
    }
  }
}
