import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app_storage.dart';
import 'batch_notification_service.dart';
import 'blok_batch_check_tracker.dart';
import 'blok_data_store.dart';
import 'currency_format.dart';
import 'download_helper.dart';
import 'nop_helper.dart';
import 'pbb_client.dart';
import 'progress_checkpoint_store.dart';
import 'tax_record.dart';

/// Pengelola siklus hidup tunggal (single source of truth) untuk proses
/// Pengecekan Status Bayar Massal (`BatchCheckScreen`) agar dapat berjalan di
/// latar belakang sembari pengguna tetap memakai menu lain di aplikasi.
class BatchCheckManager extends ChangeNotifier {
  static final BatchCheckManager instance = BatchCheckManager._();

  BatchCheckManager._() {
    _actionSubscription = BatchNotificationService.actionStream.listen(
      _handleNotificationAction,
    );
  }

  StreamSubscription<String>? _actionSubscription;

  List<TaxRecord> _records = const [];
  String _tahun = '${DateTime.now().year}';
  PbbClient? _client;
  Duration _pacingDelay = const Duration(milliseconds: 750);
  int _cooldownBatchSize = 50;
  Duration _cooldownDuration = const Duration(seconds: 3);
  bool _downloadStts = false;
  Directory? _sttsDirectory;
  String? _sttsBlokNumber;
  String? _scopeTitle;
  String _scopeKey = '';

  int _currentIndex = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isCooldown = false;
  bool _isCompleted = false;
  bool _isDismissed = false;
  bool _isScreenOpen = false;
  bool _cancelledNotified = false;
  DateTime? _pausedAt;
  String _statusMessage = 'Menyiapkan pengecekan...';
  int _sessionId = 0;

  /// Callback opsional ketika pengguna mengetuk tombol "Sembunyikan" dari
  /// notifikasi sistem saat layar `BatchCheckScreen` sedang terbuka.
  VoidCallback? onHideScreenRequested;

  /// Callback opsional untuk menyegarkan layar DHKP jika sedang terbuka.
  VoidCallback? onDataUpdated;

  List<TaxRecord> get records => _records;
  String get tahun => _tahun;
  bool get downloadStts => _downloadStts;
  Directory? get sttsDirectory => _sttsDirectory;
  String? get sttsBlokNumber => _sttsBlokNumber;
  String? get scopeTitle => _scopeTitle;
  int get currentIndex => _currentIndex;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isCooldown => _isCooldown;
  bool get isCompleted => _isCompleted;
  bool get isDismissed => _isDismissed;
  bool get isScreenOpen => _isScreenOpen;
  String get statusMessage => _statusMessage;
  int get sessionId => _sessionId;

  bool get isActiveSession => _isRunning || _isPaused;

  TaxRecord? get currentRecord =>
      _currentIndex >= 0 && _currentIndex < _records.length
      ? _records[_currentIndex]
      : null;

  int get totalCount => _records.length;

  int get sudahBayarCount => _records.where((r) => r.isPaid).length;

  int get belumBayarCount => _records
      .where(
        (r) =>
            r.isChecked &&
            !r.isPaid &&
            !r.status.contains('Blacklist') &&
            r.status != 'Dilewati' &&
            !r.status.contains('Gagal'),
      )
      .length;

  int get blacklistCount =>
      _records.where((r) => r.status.contains('Blacklist')).length;

  int get gagalCount =>
      _records.where((r) => r.status.contains('Gagal')).length;

  int get dilewatiCount =>
      _records.where((r) => r.status == 'Dilewati').length;

  int get sisaCount => (totalCount - _currentIndex).clamp(0, totalCount);

  int get sttsDownloadedCount =>
      _records.where((r) => r.buktiBayarDownloaded == true).length;

  double get progressRatio =>
      totalCount == 0 ? 0.0 : (_currentIndex / totalCount).clamp(0.0, 1.0);

  /// Gelembung mengambang tampil ketika pengecekan massal sedang berjalan,
  /// dijeda, atau baru selesai — sementara layar `BatchCheckScreen` sedang
  /// disembunyikan oleh pengguna.
  bool get shouldShowBubble =>
      (_isRunning ||
          _isPaused ||
          (_isCompleted && !_isDismissed && _records.isNotEmpty)) &&
      !_isScreenOpen;

  void setScreenOpen(bool open) {
    if (_isScreenOpen == open) return;
    _isScreenOpen = open;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  void _handleNotificationAction(String action) {
    if (!isActiveSession) return;
    switch (action) {
      case 'pause':
        if (_isRunning && !_isPaused) {
          pause();
        }
        break;
      case 'resume':
        if (_isPaused) {
          resume();
        }
        break;
      case 'cancel':
        cancel();
        break;
      case 'hide':
        if (_isScreenOpen) {
          onHideScreenRequested?.call();
        }
        break;
    }
  }

  /// Memulai sesi pengecekan massal baru di latar belakang.
  Future<void> startBatch({
    required List<TaxRecord> records,
    required String tahun,
    PbbClient? client,
    Duration pacingDelay = const Duration(milliseconds: 750),
    int cooldownBatchSize = 50,
    Duration cooldownDuration = const Duration(seconds: 3),
    bool downloadStts = false,
    Directory? sttsTargetDirectory,
    String? sttsBlokNumber,
    String? scopeTitle,
    bool autoStart = true,
  }) async {
    _sessionId++;
    _records = records;
    _tahun = tahun;
    _client = client ?? PbbClient();
    _pacingDelay = pacingDelay;
    _cooldownBatchSize = cooldownBatchSize;
    _cooldownDuration = cooldownDuration;
    _downloadStts = downloadStts;
    _sttsDirectory = sttsTargetDirectory;
    _sttsBlokNumber = sttsBlokNumber;
    _scopeTitle = scopeTitle;
    _scopeKey = records.isEmpty
        ? ''
        : ProgressCheckpointStore.buildBatchScopeKey(
            tahun: tahun,
            scopeTitle: scopeTitle,
            blokNumber: sttsBlokNumber,
            totalCount: records.length,
            firstNop: records.first.nop,
            lastNop: records.last.nop,
          );

    _currentIndex = 0;
    _isRunning = false;
    _isPaused = false;
    _isCooldown = false;
    _isCompleted = false;
    _isDismissed = false;
    _cancelledNotified = false;
    _pausedAt = null;
    _statusMessage = 'Menyiapkan pengecekan...';

    if (_scopeKey.isNotEmpty) {
      final saved = await ProgressCheckpointStore.instance
          .loadValidBatchCheckpoint(_scopeKey);
      if (saved != null &&
          saved.currentIndex > 0 &&
          saved.currentIndex < _records.length) {
        _currentIndex = saved.currentIndex;
        for (int i = 0; i < _currentIndex; i++) {
          if (!_records[i].isChecked) {
            _records[i].status = 'Dilewati';
          }
        }
        _statusMessage =
            'Melanjutkan pengecekan dari nomor ${_currentIndex + 1}/${_records.length}...';
      }
    }

    notifyListeners();

    if (autoStart && _records.isNotEmpty) {
      unawaited(_runLoop(_sessionId));
    }
  }

  void _persistBatchCheckpoint({DateTime? savedAt}) {
    if (_scopeKey.isEmpty || _records.isEmpty || _isCompleted) return;
    unawaited(
      ProgressCheckpointStore.instance.saveBatchCheckpoint(
        BatchCheckCheckpoint(
          scopeKey: _scopeKey,
          currentIndex: _currentIndex,
          totalCount: _records.length,
          savedAtMs: (savedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void _resetRecordsForFreshRun() {
    for (final r in _records) {
      r.status = 'Menunggu';
      r.buktiBayarDownloaded = null;
    }
    _currentIndex = 0;
  }

  Future<void> _ensureSttsDirectory() async {
    if (!_downloadStts || _sttsDirectory != null) return;

    final blokStr =
        _sttsBlokNumber ??
        (_records.isNotEmpty ? nopBlok(_records.first.nop) : '000');
    final cleanBlok = blokStr.replaceAll(RegExp(r'[^0-9]'), '');
    final blokFormatted = cleanBlok.isNotEmpty
        ? cleanBlok.padLeft(3, '0')
        : blokStr;
    final now = DateTime.now();
    const namaHariList = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    final namaHari = namaHariList[now.weekday - 1];
    final tgl = now.day.toString().padLeft(2, '0');
    final bln = now.month.toString().padLeft(2, '0');
    final thn = now.year.toString();
    final folderLabel = _scopeTitle != null && _scopeTitle!.isNotEmpty
        ? _safeFileName(_scopeTitle!)
        : 'Blok $blokFormatted';
    final folderName = 'STTS $folderLabel - $namaHari, $tgl-$bln-$thn';

    try {
      final pickedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih Folder Penyimpanan Berkas STTS',
      );
      if (pickedPath != null && pickedPath.isNotEmpty) {
        final dir = Directory('$pickedPath/$folderName');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _sttsDirectory = dir;
      }
    } catch (_) {}

    if (_sttsDirectory == null) {
      try {
        final docsDir = await AppStorage.getDocumentsDirectory();
        final dir = Directory('${docsDir.path}/STTS/$folderName');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _sttsDirectory = dir;
      } catch (_) {}
    }
  }

  Future<void> _runLoop(int activeSession) async {
    if (_isRunning || activeSession != _sessionId) return;
    _isRunning = true;
    _isPaused = false;
    notifyListeners();

    await _ensureSttsDirectory();
    if (activeSession != _sessionId || !_isRunning) return;

    if (_downloadStts && _sttsDirectory != null) {
      await _updateBlockInfoTxt(isFinal: false);
    }

    BatchNotificationService.instance.setActiveRecords(_records);
    await BatchNotificationService.instance.requestPermission();
    await BatchNotificationService.instance.showStarted(
      title: _scopeTitle != null && _scopeTitle!.isNotEmpty
          ? 'Cek Massal PBB • $_scopeTitle'
          : 'Pengecekan Massal PBB Dimulai',
      content: 'Sedang memeriksa ${_records.length} NOP...',
      total: _records.length,
    );

    final client = _client ?? PbbClient();

    while (_currentIndex < _records.length &&
        _isRunning &&
        activeSession == _sessionId) {
      if (_isPaused) break;

      final record = _records[_currentIndex];
      _statusMessage = 'Sedang memeriksa NOP ${record.nop}...';
      notifyListeners();

      if (_pacingDelay > Duration.zero) {
        await Future<void>.delayed(_pacingDelay);
      }
      if (!_isRunning || _isPaused || activeSession != _sessionId) break;

      PbbResult? result;
      Object? lastError;

      for (int attempt = 0; attempt < 3; attempt++) {
        if (!_isRunning || _isPaused || activeSession != _sessionId) break;
        try {
          result = await client.checkStatusViaDocument(
            record.nop,
            tahun: _tahun,
          );
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (attempt < 2 &&
              _isRunning &&
              !_isPaused &&
              activeSession == _sessionId) {
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          }
        }
      }

      if (activeSession != _sessionId || !_isRunning || _isPaused) break;

      if (result != null) {
        record.status = result.status;
        record.rawText = result.rawText;
        if (result.namaWajibPajak != null &&
            result.namaWajibPajak!.trim().isNotEmpty) {
          record.namaWajibPajak = result.namaWajibPajak;
        }
        if (result.tanggalBayar != null &&
            result.tanggalBayar!.trim().isNotEmpty) {
          record.tanggalBayar = result.tanggalBayar;
        }
        if (result.nomorStan != null && result.nomorStan!.trim().isNotEmpty) {
          record.nomorStan = result.nomorStan;
        }
        if (result.jumlahPbb != null && result.jumlahPbb!.trim().isNotEmpty) {
          record.jumlahPbb = cleanNominalRupiah(result.jumlahPbb);
        }

        if (record.isPaid) {
          await BlokDataStore.instance.updateStatusBayarFromCheck(
            nop: record.nop,
            tahun: _tahun,
            result: result,
          );
          if (_downloadStts && activeSession == _sessionId) {
            await _downloadSttsFor(
              client,
              record,
              preloadedBytes: result.sttsPdfBytes,
            );
          }
        }
        await BlokBatchCheckTracker.instance.recordChecked(record.nop);
      } else {
        record.status = 'Gagal Cek';
        record.rawText = lastError?.toString() ?? 'Koneksi terputus';
        await BlokBatchCheckTracker.instance.recordChecked(record.nop);
        if (record.isPaid && _downloadStts && activeSession == _sessionId) {
          await _downloadSttsFor(client, record);
        }
      }

      if (activeSession != _sessionId) return;
      _currentIndex++;
      if (_currentIndex % 5 == 0) {
        _persistBatchCheckpoint();
      }
      notifyListeners();

      unawaited(
        BatchNotificationService.instance.showProgress(
          current: _currentIndex,
          total: _records.length,
          currentNop: record.nop,
          lunasCount: sudahBayarCount,
          belumCount: belumBayarCount,
        ),
      );

      // Cooldown berkala agar server Bapenda tetap aman
      if (_cooldownBatchSize > 0 &&
          _currentIndex > 0 &&
          _currentIndex % _cooldownBatchSize == 0 &&
          _currentIndex < _records.length &&
          _isRunning &&
          !_isPaused &&
          activeSession == _sessionId) {
        final totalSecs = _cooldownDuration.inSeconds;
        if (totalSecs > 0) {
          for (int s = totalSecs; s > 0; s--) {
            if (!_isRunning || _isPaused || activeSession != _sessionId) break;
            _isCooldown = true;
            _statusMessage =
                'Istirahat sejenak $s detik agar pencarian tetap lancar...';
            notifyListeners();
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        } else if (_cooldownDuration > Duration.zero) {
          await Future<void>.delayed(_cooldownDuration);
        }
        if (activeSession == _sessionId) {
          _isCooldown = false;
          notifyListeners();
          if (_downloadStts && _sttsDirectory != null) {
            unawaited(_updateBlockInfoTxt(isFinal: false));
          }
        }
      }
    }

    if (activeSession != _sessionId) return;
    if (_currentIndex >= _records.length) {
      _isRunning = false;
      _isPaused = false;
      _isCooldown = false;
      _isCompleted = true;
      _pausedAt = null;
      _statusMessage = 'Semua NOP selesai diperiksa.';
      unawaited(ProgressCheckpointStore.instance.clearBatchCheckpoint());
      if (_downloadStts && _sttsDirectory != null) {
        await _updateBlockInfoTxt(isFinal: true);
      }
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}

      notifyListeners();
      onDataUpdated?.call();

      unawaited(
        BatchNotificationService.instance.showCompleted(
          total: _records.length,
          lunasCount: sudahBayarCount,
          belumCount: belumBayarCount,
          blacklistCount: blacklistCount,
          gagalCount: gagalCount,
        ),
      );
    } else {
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<void> _downloadSttsFor(
    PbbClient client,
    TaxRecord record, {
    Uint8List? preloadedBytes,
  }) async {
    Uint8List? bytes =
        (preloadedBytes != null && preloadedBytes.isNotEmpty)
        ? preloadedBytes
        : null;
    if (bytes == null) {
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          bytes = await client.fetchSttsPdfIfIssued(
            nop: record.nop,
            tahun: _tahun,
          );
          break;
        } catch (_) {
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          }
        }
      }
    }

    if (bytes == null) {
      record.buktiBayarDownloaded = false;
      return;
    }

    try {
      final cleanNop = record.nop.replaceAll(RegExp(r'[^0-9]'), '');
      final nama = (record.namaWajibPajak ?? '').trim();
      final label = nama.isNotEmpty ? nama : cleanNop;
      final fileName = _safeFileName(
        'STTS ($label) No. (${nopBlok(cleanNop)}) (${nopWilayah(cleanNop)}) ($_tahun).pdf',
      );

      final dir = _sttsDirectory;
      if (dir != null) {
        final targetFile = File('${dir.path}/$fileName');
        await targetFile.writeAsBytes(bytes);
        record.buktiBayarDownloaded = true;
      } else {
        await DownloadHelper.saveBytes(
          bytes,
          fileName,
          subfolder: 'STTS',
          useSaveAs: false,
        );
        record.buktiBayarDownloaded = true;
      }
    } catch (_) {
      record.buktiBayarDownloaded = false;
    }

    if (_downloadStts && _sttsDirectory != null) {
      await _updateBlockInfoTxt(isFinal: false);
    }
  }

  String _safeFileName(String name) => name
      .replaceAll(RegExp(r'[\r\n\t\\/:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _updateBlockInfoTxt({bool isFinal = false}) async {
    final dir = _sttsDirectory;
    if (dir == null) return;

    try {
      final blokStr =
          _sttsBlokNumber ??
          (_records.isNotEmpty ? nopBlok(_records.first.nop) : '000');
      final cleanBlok = blokStr.replaceAll(RegExp(r'[^0-9]'), '');
      final isMultiBlok =
          _records.map((r) => nopBlok(r.nop)).toSet().length > 1;
      final blokFormatted = cleanBlok.isNotEmpty
          ? cleanBlok.padLeft(3, '0')
          : blokStr;
      final txtName = isMultiBlok && _scopeTitle != null
          ? 'INFORMASI_${_safeFileName(_scopeTitle!).toUpperCase().replaceAll(' ', '_')}.txt'
          : 'INFORMASI_BLOK_$blokFormatted.txt';
      final txtFile = File('${dir.path}/$txtName');

      final desaName = activeDesaName;
      final kecName = activeKecamatanName;
      final totalRecords = _records.length;
      final sudahBayarList = _records.where((r) => r.isPaid).toList();
      final belumBayarList = _records
          .where((r) => !r.isPaid && r.isChecked)
          .toList();
      final gagalList = _records
          .where((r) => r.status.contains('Gagal'))
          .toList();
      final downloadedCount = sttsDownloadedCount;

      int totalNominalBayar = 0;
      for (final r in sudahBayarList) {
        totalNominalBayar += parseNominalRupiah(r.jumlahPbb);
      }

      int totalNominalBelum = 0;
      for (final r in belumBayarList) {
        totalNominalBelum += parseNominalRupiah(r.jumlahPbb);
      }

      final now = DateTime.now();
      const namaHariList = [
        'Senin',
        'Selasa',
        'Rabu',
        'Kamis',
        'Jumat',
        'Sabtu',
        'Minggu',
      ];
      final namaHari = namaHariList[now.weekday - 1];
      final tglStr =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final jamStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final buf = StringBuffer();
      buf.writeln(
        '================================================================================',
      );
      buf.writeln('                    INFORMASI REKAPITULASI PENGECEKAN BLOK');
      buf.writeln('                              KABUPATEN CIANJUR');
      buf.writeln(
        '================================================================================',
      );
      buf.writeln('Kecamatan         : $kecName');
      buf.writeln('Desa / Kelurahan  : $desaName');
      buf.writeln(
        'Nomor Blok        : ${isMultiBlok ? (_scopeTitle ?? 'Seluruh Blok') : 'Blok $blokFormatted'}',
      );
      buf.writeln('Tahun Pajak       : $_tahun');
      buf.writeln('Waktu Pembuatan   : $namaHari, $tglStr $jamStr');
      buf.writeln(
        'Status Pengecekan : ${isFinal ? "Selesai" : "Sedang Berjalan / Sebagian"}',
      );
      buf.writeln('Folder Berkas STTS: ${dir.path}');
      buf.writeln(
        '--------------------------------------------------------------------------------',
      );
      buf.writeln('RINGKASAN PEMERIKSAAN:');
      buf.writeln(
        '--------------------------------------------------------------------------------',
      );
      buf.writeln('Total Objek Pajak (NOP)  : $totalRecords');
      buf.writeln('Sudah Bayar (Lunas)      : ${sudahBayarList.length}');
      buf.writeln('Belum Bayar              : ${belumBayarList.length}');
      buf.writeln('Gagal / Kendala Cek      : ${gagalList.length}');
      buf.writeln('Berkas STTS Terunduh     : $downloadedCount berkas PDF');
      buf.writeln(
        'Total Nominal Terbayar   : Rp ${formatRibuan(totalNominalBayar)}',
      );
      if (totalNominalBelum > 0) {
        buf.writeln(
          'Total Nominal Belum Bayar: Rp ${formatRibuan(totalNominalBelum)}',
        );
      }
      buf.writeln(
        '--------------------------------------------------------------------------------',
      );
      buf.writeln('DAFTAR RINCIAN OBJEK PAJAK (NOP):');
      buf.writeln(
        '--------------------------------------------------------------------------------',
      );
      buf.writeln(
        'No. | NOP                  | Nama Wajib Pajak             | Status Bayar | Nominal PBB   | Tanggal Bayar | No. STAN         | File STTS',
      );
      buf.writeln(
        '----+----------------------+------------------------------+--------------+---------------+---------------+------------------+------------------',
      );

      for (int i = 0; i < _records.length; i++) {
        final r = _records[i];
        final no = (i + 1).toString().padRight(3);
        final nop = r.nop.padRight(20);
        final nama = (r.namaWajibPajak ?? '-').trim();
        final namaTrunc =
            (nama.length > 28 ? '${nama.substring(0, 25)}...' : nama).padRight(
              28,
            );
        final status =
            (r.isPaid
                    ? 'Sudah Bayar'
                    : (r.isChecked ? r.status : 'Belum Dicek'))
                .padRight(12);
        final nominalVal = parseNominalRupiah(r.jumlahPbb);
        final nominal =
            (nominalVal > 0 ? 'Rp ${formatRibuan(nominalVal)}' : '-').padRight(
              13,
            );
        final tgl = (r.tanggalBayar ?? '-').padRight(13);
        final stan = (r.nomorStan ?? '-').padRight(16);
        final sttsStatus = r.buktiBayarDownloaded == true
            ? 'Terunduh'
            : (r.isPaid ? 'Gagal/Tidak Terbit' : '-');

        buf.writeln(
          '$no | $nop | $namaTrunc | $status | $nominal | $tgl | $stan | $sttsStatus',
        );
      }

      buf.writeln(
        '================================================================================',
      );
      buf.writeln('Catatan:');
      buf.writeln(
        '- Berkas STTS (.pdf) hanya dapat diunduh untuk NOP yang telah berstatus Sudah Bayar.',
      );
      buf.writeln(
        '- Berkas ini dihasilkan secara otomatis oleh Aplikasi Cek PBB Cianjur.',
      );
      buf.writeln(
        '================================================================================',
      );

      await txtFile.writeAsString(buf.toString());
    } catch (e) {
      debugPrint('Gagal menulis berkas informasi blok: $e');
    }
  }

  void pause({DateTime? now}) {
    if (!_isRunning || _isCompleted) return;
    _isPaused = true;
    _isRunning = false;
    _isCooldown = false;
    _pausedAt = now ?? DateTime.now();
    _statusMessage = 'Pengecekan dijeda (progres tersimpan selama 24 jam).';
    _persistBatchCheckpoint(savedAt: _pausedAt);
    notifyListeners();

    final currentNop = currentRecord?.nop ?? '-';
    unawaited(
      BatchNotificationService.instance.showProgress(
        current: _currentIndex,
        total: totalCount,
        currentNop: currentNop,
        lunasCount: sudahBayarCount,
        belumCount: belumBayarCount,
        isPaused: true,
      ),
    );
  }

  @visibleForTesting
  void markPausedForTesting(DateTime pausedAt) {
    _isPaused = true;
    _isRunning = false;
    _pausedAt = pausedAt;
    _persistBatchCheckpoint(savedAt: pausedAt);
  }

  void resume({DateTime? now, bool autoStartLoop = true}) {
    if (_isCompleted || _isRunning || _records.isEmpty) return;

    final pausedMs = _pausedAt?.toUtc().millisecondsSinceEpoch ?? 0;
    if (pausedMs > 0 &&
        !ProgressCheckpointStore.isWithinResumeWindow(pausedMs, now: now)) {
      _resetRecordsForFreshRun();
      _statusMessage =
          'Jeda melebihi 24 jam — memulai ulang pengecekan dari awal...';
      unawaited(ProgressCheckpointStore.instance.clearBatchCheckpoint());
    }

    _pausedAt = null;
    _isPaused = false;
    notifyListeners();

    if (autoStartLoop) {
      unawaited(_runLoop(_sessionId));
    }
  }

  void skipCurrent() {
    if (_currentIndex < _records.length) {
      _records[_currentIndex].status = 'Dilewati';
      _currentIndex++;
      _persistBatchCheckpoint();
      notifyListeners();
      if (_isRunning && !_isPaused) {
        unawaited(_runLoop(_sessionId));
      }
    }
  }

  /// Menghentikan proses pengecekan (dipanggil saat user memilih "Hentikan").
  void stopAndFinalize({bool notifyCancelled = true}) {
    _isRunning = false;
    _isPaused = false;
    _isCooldown = false;
    _pausedAt = null;
    if (_downloadStts && _sttsDirectory != null) {
      unawaited(_updateBlockInfoTxt(isFinal: true));
    }
    unawaited(BatchNotificationService.instance.stopForegroundService());
    if (notifyCancelled && !_isCompleted && !_cancelledNotified) {
      _cancelledNotified = true;
      if (_currentIndex > 0) {
        unawaited(
          BatchNotificationService.instance.showCancelled(
            current: _currentIndex,
            total: totalCount,
            lunasCount: sudahBayarCount,
            belumCount: belumBayarCount,
            blacklistCount: blacklistCount,
            gagalCount: gagalCount,
          ),
        );
      } else {
        unawaited(BatchNotificationService.instance.cancel());
      }
    }
    onDataUpdated?.call();
    notifyListeners();
  }

  void cancel() {
    if (!isActiveSession) return;
    _statusMessage = 'Pengecekan dihentikan.';
    unawaited(ProgressCheckpointStore.instance.clearBatchCheckpoint());
    stopAndFinalize(notifyCancelled: true);
    _isDismissed = true;
    notifyListeners();
  }

  void dismiss() {
    _isDismissed = true;
    if (!_isRunning && !_isPaused) {
      _isCompleted = false;
    }
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _sessionId++;
    _records = const [];
    _tahun = '${DateTime.now().year}';
    _client = null;
    _sttsDirectory = null;
    _sttsBlokNumber = null;
    _scopeTitle = null;
    _scopeKey = '';
    _currentIndex = 0;
    _isRunning = false;
    _isPaused = false;
    _isCooldown = false;
    _isCompleted = false;
    _isDismissed = false;
    _isScreenOpen = false;
    _cancelledNotified = false;
    _pausedAt = null;
    _statusMessage = 'Menyiapkan pengecekan...';
    onHideScreenRequested = null;
    onDataUpdated = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _actionSubscription?.cancel();
    super.dispose();
  }
}
