import 'dart:async';

import 'package:flutter/material.dart';

import '../batch_notification_service.dart';
import '../staff_portal_client.dart';
import 'staff_dhkp_sync_dialog.dart';
import 'staff_dhkp_sync_service.dart';

/// Pengelola status siklus hidup sinkronisasi DHKP dari Portal Staf.
/// Berfungsi sebagai single source of truth untuk:
/// 1. Status sinkronisasi di latar belakang (berjalan, jeda, batal, selesai).
/// 2. Menampilkan/menyembunyikan modal bottom sheet progres.
/// 3. Menampilkan floating bubble chat saat sheet disembunyikan.
class StaffDhkpSyncManager extends ChangeNotifier {
  static final StaffDhkpSyncManager instance = StaffDhkpSyncManager._();

  StaffDhkpSyncManager._() {
    _initActionStream();
  }

  bool _isSyncing = false;
  bool _isSheetOpen = false;
  bool _isPaused = false;
  bool _isCancelled = false;
  bool _isCompleted = false;
  bool _isDismissed = false;

  StaffDhkpSyncProgress? _progress;
  StaffDhkpSyncOutcome? _outcome;

  StaffPortalClient? _client;
  String? _tahun;
  List<String> _bloks = const [];
  String? _kelurahan;
  String? _kecamatan;
  String? _blokLabel;
  StaffSyncMode _mode = StaffSyncMode.paidOnly;
  String? _tglBayarAwal;
  String? _tglBayarAkhir;

  StreamSubscription<String>? _actionSub;

  bool get isSyncing => _isSyncing;
  bool get isSheetOpen => _isSheetOpen;
  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;
  bool get isCompleted => _isCompleted;
  bool get isDismissed => _isDismissed;
  StaffDhkpSyncProgress? get progress => _progress;
  StaffDhkpSyncOutcome? get outcome => _outcome;
  StaffPortalClient? get client => _client;
  String? get tahun => _tahun;
  List<String> get bloks => _bloks;
  String? get kelurahan => _kelurahan;
  String? get kecamatan => _kecamatan;
  String? get blokLabel => _blokLabel;
  StaffSyncMode get mode => _mode;

  /// Floating bubble harus tampil bila sinkronisasi sedang berjalan atau baru saja selesai,
  /// DAN modal bottom sheet sedang tidak terbuka (misal: pengguna menekan "Sembunyikan").
  bool get shouldShowBubble =>
      (_isSyncing || (_isCompleted && !_isDismissed && _outcome != null)) &&
      !_isSheetOpen;

  void _initActionStream() {
    _actionSub = BatchNotificationService.actionStream.listen((action) {
      switch (action) {
        case 'pause':
          if (!_isPaused && !_isCompleted) {
            _isPaused = true;
            notifyListeners();
          }
          break;
        case 'resume':
          if (_isPaused && !_isCompleted) {
            _isPaused = false;
            notifyListeners();
          }
          break;
        case 'cancel':
          if (!_isCompleted) {
            _isCancelled = true;
            notifyListeners();
          }
          break;
        case 'hide':
          hideSheet();
          break;
      }
    });
  }

  /// Memulai proses sinkronisasi DHKP dan langsung menampilkan sheet progres
  void startSync({
    required BuildContext context,
    required StaffPortalClient client,
    required String tahun,
    required List<String> bloks,
    required String kelurahan,
    required String kecamatan,
    required String blokLabel,
    StaffSyncMode mode = StaffSyncMode.paidOnly,
    String? tglBayarAwal,
    String? tglBayarAkhir,
  }) {
    _client = client;
    _tahun = tahun;
    _bloks = bloks;
    _kelurahan = kelurahan;
    _kecamatan = kecamatan;
    _blokLabel = blokLabel;
    _mode = mode;
    _tglBayarAwal = tglBayarAwal;
    _tglBayarAkhir = tglBayarAkhir;

    _isSyncing = true;
    _isPaused = false;
    _isCancelled = false;
    _isCompleted = false;
    _isDismissed = false;
    _progress = null;
    _outcome = null;
    notifyListeners();

    // Buka lembaran modal progres di layar
    openSheet(context);

    // Jalankan eksekusi background sync
    _executeSync();
  }

  Future<void> _executeSync() async {
    if (_client == null || _tahun == null) return;

    try {
      final res = await StaffDhkpSyncService.instance.syncBloks(
        client: _client!,
        tahun: _tahun!,
        bloks: _bloks,
        kelurahanCode: _kelurahan ?? '',
        kecamatanCode: _kecamatan ?? '',
        mode: _mode,
        tglBayarAwal: _tglBayarAwal,
        tglBayarAkhir: _tglBayarAkhir,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
        shouldCancel: () => _isCancelled,
        isPaused: () => _isPaused,
      );

      _outcome = res;
    } catch (e) {
      _outcome = StaffDhkpSyncOutcome(
        blokLabel: _blokLabel ?? 'DHKP',
        tahun: _tahun ?? '',
        errorMessage: 'Gagal menyinkronkan data: $e',
      );
    } finally {
      _isSyncing = false;
      _isCompleted = true;
      notifyListeners();
    }
  }

  /// Membuka lembaran modal progres sinkronisasi
  void openSheet([BuildContext? context]) {
    if (_isSheetOpen) return;
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx == null) return;

    _isSheetOpen = true;
    notifyListeners();

    showStaffDhkpSyncRunningSheetModal(ctx).whenComplete(() {
      _isSheetOpen = false;
      notifyListeners();
    });
  }

  /// Menyembunyikan modal progres sinkronisasi (memicu kemunculan bubble)
  void hideSheet([BuildContext? context]) {
    if (!_isSheetOpen) return;
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
    _isSheetOpen = false;
    notifyListeners();
  }

  /// Menjeda atau melanjutkan proses sinkronisasi
  void togglePause() {
    if (_isCompleted) return;
    _isPaused = !_isPaused;
    notifyListeners();
  }

  /// Membatalkan proses sinkronisasi
  void cancelSync() {
    if (_isCompleted) return;
    _isCancelled = true;
    notifyListeners();
  }

  /// Menutup status sinkronisasi & menghilangkan bubble setelah selesai
  void dismiss() {
    _isDismissed = true;
    _isSyncing = false;
    _isCompleted = false;
    _progress = null;
    notifyListeners();
  }

  /// Reset status untuk keperluan pengujian
  @visibleForTesting
  void reset() {
    _isSyncing = false;
    _isSheetOpen = false;
    _isPaused = false;
    _isCancelled = false;
    _isCompleted = false;
    _isDismissed = false;
    _progress = null;
    _outcome = null;
    _client = null;
    _tahun = null;
    _bloks = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    super.dispose();
  }
}
