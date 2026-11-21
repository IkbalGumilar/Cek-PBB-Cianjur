import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../batch_notification_service.dart';
import '../blok_catatan_screen.dart';
import '../progress_checkpoint_store.dart';
import '../staff_portal_client.dart';
import '../user_friendly_error.dart';
import 'staff_dhkp_sync_dialog.dart';
import 'staff_dhkp_sync_service.dart';

/// Pengelola status siklus hidup sinkronisasi DHKP dari Portal Staf.
/// Berfungsi sebagai single source of truth untuk:
/// 1. Status sinkronisasi di latar belakang (berjalan, jeda, batal, selesai).
/// 2. Menampilkan/menyembunyikan modal bottom sheet progres.
/// 3. Menampilkan floating bubble chat saat sheet disembunyikan.
/// 4. Menyimpan progres checkpoint agar jeda < 24 jam dapat dilanjutkan,
///    dan jeda >= 24 jam otomatis dimulai dari awal.
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

  String _scopeKey = '';
  DateTime? _pausedAt;
  int _nextPageBb = 1;
  int _nextPageSb = 1;
  bool _bbCompleted = false;
  int _syncRunId = 0;

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
      if (!_isSyncing) return;
      switch (action) {
        case 'pause':
          if (!_isPaused && !_isCompleted) {
            togglePause();
          }
          break;
        case 'resume':
          if (_isPaused && !_isCompleted) {
            togglePause();
          }
          break;
        case 'cancel':
          if (!_isCompleted) {
            cancelSync();
          }
          break;
        case 'hide':
          hideSheet();
          break;
      }
    });
  }

  void _persistCurrentCheckpoint() {
    if (_scopeKey.isEmpty) return;
    unawaited(
      ProgressCheckpointStore.instance.saveStaffSyncCheckpoint(
        StaffSyncCheckpoint(
          scopeKey: _scopeKey,
          nextPageBb: _nextPageBb,
          nextPageSb: _nextPageSb,
          bbCompleted: _bbCompleted,
          savedAtMs: (_pausedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  /// Memulai proses sinkronisasi DHKP dan langsung menampilkan sheet progres.
  /// Jika terdapat checkpoint tersimpan `< 24 jam` untuk cakupan yang sama,
  /// otomatis dilanjutkan dari halaman terakhir; jika `>= 24 jam`, dimulai dari awal.
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
    _syncRunId++;
    _client = client;
    _tahun = tahun;
    _bloks = bloks;
    _kelurahan = kelurahan;
    _kecamatan = kecamatan;
    _blokLabel = blokLabel;
    _mode = mode;
    _tglBayarAwal = tglBayarAwal;
    _tglBayarAkhir = tglBayarAkhir;
    _scopeKey = ProgressCheckpointStore.buildStaffSyncScopeKey(
      tahun: tahun,
      kecamatan: kecamatan,
      kelurahan: kelurahan,
      modeName: mode.name,
      bloks: bloks,
    );

    _isSyncing = true;
    _isPaused = false;
    _isCancelled = false;
    _isCompleted = false;
    _isDismissed = false;
    _pausedAt = null;
    _nextPageBb = 1;
    _nextPageSb = 1;
    _bbCompleted = false;
    _progress = null;
    _outcome = null;
    notifyListeners();

    // Buka lembaran modal progres di layar
    openSheet(context);

    // Jalankan eksekusi background sync
    _executeSync(_syncRunId);
  }

  Future<void> _executeSync(int runId, {bool forceFresh = false}) async {
    if (_client == null || _tahun == null) return;

    int initialPageBb = 1;
    int initialPageSb = 1;
    bool skipBelumBayar = false;

    if (!forceFresh && _scopeKey.isNotEmpty) {
      final saved = await ProgressCheckpointStore.instance
          .loadValidStaffSyncCheckpoint(_scopeKey);
      if (runId != _syncRunId) return;
      if (saved != null) {
        initialPageBb = saved.nextPageBb < 1 ? 1 : saved.nextPageBb;
        initialPageSb = saved.nextPageSb < 1 ? 1 : saved.nextPageSb;
        skipBelumBayar = saved.bbCompleted;
        _nextPageBb = initialPageBb;
        _nextPageSb = initialPageSb;
        _bbCompleted = skipBelumBayar;
      }
    }

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
        initialPageBb: initialPageBb,
        initialPageSb: initialPageSb,
        skipBelumBayar: skipBelumBayar,
        onPageCheckpoint: (nextBb, nextSb, bbDone) {
          if (runId != _syncRunId) return;
          _nextPageBb = nextBb;
          _nextPageSb = nextSb;
          _bbCompleted = bbDone;
          _persistCurrentCheckpoint();
        },
        onProgress: (p) {
          if (runId != _syncRunId) return;
          _progress = p;
          notifyListeners();
        },
        shouldCancel: () => _isCancelled || runId != _syncRunId,
        isPaused: () => _isPaused,
      );

      if (runId != _syncRunId) return;
      _outcome = res;
      if (res.isSuccess || res.isCancelled) {
        await ProgressCheckpointStore.instance.clearStaffSyncCheckpoint();
      }
    } catch (e) {
      if (runId != _syncRunId) return;
      _outcome = StaffDhkpSyncOutcome(
        blokLabel: _blokLabel ?? 'DHKP',
        tahun: _tahun ?? '',
        errorMessage: friendlyErrorMessage(
          e,
          fallback: 'Gagal menyinkronkan data DHKP. Silakan coba lagi.',
        ),
      );
    } finally {
      if (runId == _syncRunId) {
        _isSyncing = false;
        _isCompleted = true;
        _pausedAt = null;
        notifyListeners();
        BlokCatatanScreen.refreshIfOpen();
      }
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

  /// Menjeda atau melanjutkan proses sinkronisasi.
  /// Jika terjeda `>= 24 jam`, otomatis dibersihkan dan dimulai ulang dari awal.
  void togglePause({DateTime? now}) {
    if (_isCompleted) return;
    if (!_isPaused) {
      _isPaused = true;
      _pausedAt = now ?? DateTime.now();
      _persistCurrentCheckpoint();
      notifyListeners();
      return;
    }

    final pausedMs = _pausedAt?.toUtc().millisecondsSinceEpoch ?? 0;
    final expired =
        pausedMs > 0 &&
        !ProgressCheckpointStore.isWithinResumeWindow(pausedMs, now: now);

    if (expired) {
      _syncRunId++;
      _isPaused = false;
      _isCancelled = false;
      _pausedAt = null;
      _nextPageBb = 1;
      _nextPageSb = 1;
      _bbCompleted = false;
      _progress = null;
      unawaited(ProgressCheckpointStore.instance.clearStaffSyncCheckpoint());
      notifyListeners();
      unawaited(_executeSync(_syncRunId, forceFresh: true));
      return;
    }

    _isPaused = false;
    _pausedAt = null;
    notifyListeners();
  }

  /// Membatalkan proses sinkronisasi
  void cancelSync() {
    if (_isCompleted) return;
    _isCancelled = true;
    _pausedAt = null;
    unawaited(ProgressCheckpointStore.instance.clearStaffSyncCheckpoint());
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
    resetStaffDhkpSyncReportDialogForTesting();
    _syncRunId++;
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
    _scopeKey = '';
    _pausedAt = null;
    _nextPageBb = 1;
    _nextPageSb = 1;
    _bbCompleted = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    super.dispose();
  }
}
