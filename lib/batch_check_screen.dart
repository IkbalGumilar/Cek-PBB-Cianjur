import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_storage.dart';
import 'batch_notification_service.dart';
import 'blok_batch_check_tracker.dart';
import 'blok_data_store.dart';
import 'currency_format.dart';
import 'download_helper.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart';
import 'pbb_client.dart';
import 'result_screen.dart';
import 'tax_record.dart';
import 'unity_lerp_widgets.dart';

class BatchCheckScreen extends StatefulWidget {
  final List<TaxRecord> records;
  final String tahun;
  final PbbClient? client;
  final Duration pacingDelay;
  final int cooldownBatchSize;
  final Duration cooldownDuration;
  final bool autoStart;

  /// Jika true, NOP yang terdeteksi sudah bayar juga diunduh berkas STTS-nya.
  final bool downloadStts;

  /// Folder khusus untuk menampung seluruh berkas STTS dan berkas informasi blok (.txt).
  final Directory? sttsTargetDirectory;

  /// Nomor blok yang sedang diperiksa (misalnya "001" atau "1").
  final String? sttsBlokNumber;

  const BatchCheckScreen({
    super.key,
    required this.records,
    required this.tahun,
    this.client,
    this.pacingDelay = const Duration(milliseconds: 750),
    this.cooldownBatchSize = 50,
    this.cooldownDuration = const Duration(seconds: 3),
    this.autoStart = true,
    this.downloadStts = false,
    this.sttsTargetDirectory,
    this.sttsBlokNumber,
  });

  @override
  State<BatchCheckScreen> createState() => _BatchCheckScreenState();
}

class _BatchCheckScreenState extends State<BatchCheckScreen> {
  late final PbbClient _client;
  final ScrollController _scrollController = ScrollController();

  Directory? _sttsDirectory;
  int _currentIndex = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isCooldown = false;
  bool _isCompleted = false;
  bool _cancelledNotified = false;
  String _statusMessage = 'Menyiapkan pengecekan...';
  StreamSubscription<String>? _actionSubscription;

  TaxRecord? get _current => _currentIndex < widget.records.length
      ? widget.records[_currentIndex]
      : null;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? PbbClient();
    _sttsDirectory = widget.sttsTargetDirectory;
    _actionSubscription = BatchNotificationService.actionStream.listen((action) {
      if (!mounted) return;
      switch (action) {
        case 'pause':
          if (_isRunning && !_isPaused) {
            _pause();
          }
          break;
        case 'resume':
          if (_isPaused) {
            _resume();
          }
          break;
        case 'cancel':
          _cancelFromNotification();
          break;
        case 'hide':
          // Dibiarkan tetap tenang berjalan di latar belakang
          break;
      }
    });

    if (widget.autoStart && widget.records.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runBatch();
      });
    }
  }

  @override
  void dispose() {
    _actionSubscription?.cancel();
    _isRunning = false;
    _scrollController.dispose();
    unawaited(BatchNotificationService.instance.stopForegroundService());
    if (!_isCompleted) {
      _notifyCancelledIfPartial();
    }
    super.dispose();
  }

  void _notifyCancelledIfPartial() {
    if (_cancelledNotified || _isCompleted) return;
    _cancelledNotified = true;

    if (widget.downloadStts && _sttsDirectory != null) {
      unawaited(_updateBlockInfoTxt(isFinal: true));
    }

    if (_currentIndex > 0) {
      final sudahCount = widget.records.where((r) => r.isPaid).length;
      final belumCount = widget.records
          .where(
            (r) =>
                r.isChecked &&
                !r.isPaid &&
                !r.status.contains('Blacklist') &&
                r.status != 'Dilewati' &&
                !r.status.contains('Gagal'),
          )
          .length;
      final blacklistCount = widget.records
          .where((r) => r.status.contains('Blacklist'))
          .length;
      final gagalCount = widget.records
          .where((r) => r.status.contains('Gagal'))
          .length;

      unawaited(
        BatchNotificationService.instance.showCancelled(
          current: _currentIndex,
          total: widget.records.length,
          lunasCount: sudahCount,
          belumCount: belumCount,
          blacklistCount: blacklistCount,
          gagalCount: gagalCount,
        ),
      );
    } else {
      unawaited(BatchNotificationService.instance.cancel());
    }
  }

  /// Unduh STTS NOP yang sudah bayar dan simpan ke folder STTS khusus. Hasilnya
  /// dicatat di [TaxRecord.buktiBayarDownloaded]: true bila tersimpan, false
  /// bila STTS belum terbit di server atau gagal diunduh. Kegagalan di sini
  /// tidak menghentikan pengecekan massal.
  Future<void> _downloadSttsFor(TaxRecord record) async {
    Uint8List? bytes;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        bytes = await _client.fetchSttsPdfIfIssued(
          nop: record.nop,
          tahun: widget.tahun,
        );
        break;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 1000));
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
        'STTS ($label) No. (${nopBlok(cleanNop)}) (${nopWilayah(cleanNop)}) (${widget.tahun}).pdf',
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

    if (widget.downloadStts && _sttsDirectory != null) {
      await _updateBlockInfoTxt(isFinal: false);
    }
  }

  String _safeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    const itemExtent = 64.0;
    final targetOffset = (_currentIndex * itemExtent) - 100.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxScroll);
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _runBatch() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _isPaused = false;
    });

    if (widget.downloadStts && _sttsDirectory == null) {
      try {
        final pickedPath = await FilePicker.getDirectoryPath(
          dialogTitle: 'Pilih Folder Penyimpanan Berkas STTS',
        );
        if (pickedPath != null && pickedPath.isNotEmpty) {
          final blokStr = widget.sttsBlokNumber ??
              (widget.records.isNotEmpty
                  ? nopBlok(widget.records.first.nop)
                  : '000');
          final cleanBlok = blokStr.replaceAll(RegExp(r'[^0-9]'), '');
          final blokFormatted =
              cleanBlok.isNotEmpty ? cleanBlok.padLeft(3, '0') : blokStr;
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
          final folderName =
              'STTS Blok $blokFormatted - $namaHari, $tgl-$bln-$thn';

          final dir = Directory('$pickedPath/$folderName');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          _sttsDirectory = dir;
        }
      } catch (_) {}

      // Fallback ke penyimpanan default dokumen jika dialog dibatalkan / di lingkungan pengujian
      if (_sttsDirectory == null) {
        try {
          final docsDir = await AppStorage.getDocumentsDirectory();
          final dir = Directory('${docsDir.path}/STTS');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          _sttsDirectory = dir;
        } catch (_) {}
      }
    }

    if (widget.downloadStts && _sttsDirectory != null) {
      await _updateBlockInfoTxt(isFinal: false);
    }

    BatchNotificationService.instance.setActiveRecords(widget.records);
    await BatchNotificationService.instance.requestPermission();
    await BatchNotificationService.instance.showStarted(
      title: 'Pengecekan Massal PBB Dimulai',
      content: 'Sedang memeriksa ${widget.records.length} NOP...',
      total: widget.records.length,
    );

    while (_currentIndex < widget.records.length && _isRunning) {
      if (_isPaused) break;

      final record = widget.records[_currentIndex];
      if (mounted) {
        setState(() {
          _statusMessage = 'Sedang memeriksa NOP ${record.nop}...';
        });
        _scrollToCurrent();
      }

      // Jeda aman per NOP (750 ms) untuk mencegah beban berlebih ke server
      if (widget.pacingDelay > Duration.zero) {
        await Future<void>.delayed(widget.pacingDelay);
      }
      if (!_isRunning || _isPaused || !mounted) break;

      PbbResult? result;
      Object? lastError;

      // Coba sampai 3x (retry 2x) jika terjadi gangguan soket/koneksi saat layar mati atau app di latar belakang
      for (int attempt = 0; attempt < 3; attempt++) {
        if (!_isRunning || _isPaused || !mounted) break;
        try {
          result = await _client.checkStatusViaDocument(
            record.nop,
            tahun: widget.tahun,
          );
          lastError = null;
          break; // Sukses, keluar dari loop retry
        } catch (e) {
          lastError = e;
          if (attempt < 2 && _isRunning && !_isPaused && mounted) {
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          }
        }
      }

      if (!mounted) return;

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
            tahun: widget.tahun,
            result: result,
          );
          if (widget.downloadStts && mounted) {
            await _downloadSttsFor(record);
          }
        }
        await BlokBatchCheckTracker.instance.recordChecked(record.nop);
      } else {
        record.status = 'Gagal Cek';
        record.rawText = lastError?.toString() ?? 'Koneksi terputus';
        await BlokBatchCheckTracker.instance.recordChecked(record.nop);
        if (record.isPaid && widget.downloadStts && mounted) {
          await _downloadSttsFor(record);
        }
      }

      if (!mounted) return;
      setState(() {
        _currentIndex++;
      });

      // Update notifikasi progress berjalan di status bar / drawer sistem
      final sudahCount = widget.records.where((r) => r.isPaid).length;
      final belumCount = widget.records
          .where(
            (r) =>
                r.isChecked &&
                !r.isPaid &&
                !r.status.contains('Blacklist') &&
                r.status != 'Dilewati' &&
                !r.status.contains('Gagal'),
          )
          .length;

      unawaited(
        BatchNotificationService.instance.showProgress(
          current: _currentIndex,
          total: widget.records.length,
          currentNop: record.nop,
          lunasCount: sudahCount,
          belumCount: belumCount,
        ),
      );

      // Cooldown berkala (misal setiap 50 NOP jeda 3 detik) agar server Bapenda tetap aman
      if (widget.cooldownBatchSize > 0 &&
          _currentIndex > 0 &&
          _currentIndex % widget.cooldownBatchSize == 0 &&
          _currentIndex < widget.records.length &&
          _isRunning &&
          !_isPaused) {
        final totalSecs = widget.cooldownDuration.inSeconds;
        if (totalSecs > 0) {
          for (int s = totalSecs; s > 0; s--) {
            if (!_isRunning || _isPaused || !mounted) break;
            setState(() {
              _isCooldown = true;
              _statusMessage =
                  'Istirahat sejenak $s detik agar pencarian tetap lancar...';
            });
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        } else if (widget.cooldownDuration > Duration.zero) {
          await Future<void>.delayed(widget.cooldownDuration);
        }
        if (mounted) {
          setState(() {
            _isCooldown = false;
          });
          if (widget.downloadStts && _sttsDirectory != null) {
            unawaited(_updateBlockInfoTxt(isFinal: false));
          }
        }
      }
    }

    if (!mounted) return;
    if (_currentIndex >= widget.records.length) {
      setState(() {
        _isRunning = false;
        _isCompleted = true;
        _statusMessage = 'Semua NOP selesai diperiksa.';
      });
      if (widget.downloadStts && _sttsDirectory != null) {
        await _updateBlockInfoTxt(isFinal: true);
      }
      HapticFeedback.mediumImpact();

      final sudahCount = widget.records.where((r) => r.isPaid).length;
      final belumCount = widget.records
          .where(
            (r) =>
                r.isChecked &&
                !r.isPaid &&
                !r.status.contains('Blacklist') &&
                r.status != 'Dilewati' &&
                !r.status.contains('Gagal'),
          )
          .length;
      final blacklistCount = widget.records
          .where((r) => r.status.contains('Blacklist'))
          .length;
      final gagalCount = widget.records
          .where((r) => r.status.contains('Gagal'))
          .length;

      // Munculkan notifikasi ke-2 yang menggantikan notifikasi progress (ID sama)
      unawaited(
        BatchNotificationService.instance.showCompleted(
          total: widget.records.length,
          lunasCount: sudahCount,
          belumCount: belumCount,
          blacklistCount: blacklistCount,
          gagalCount: gagalCount,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) _goToResult();
    } else {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _pause() {
    setState(() {
      _isPaused = true;
      _isRunning = false;
      _isCooldown = false;
      _statusMessage = 'Pengecekan dijeda.';
    });
    final total = widget.records.length;
    final currentNop =
        _currentIndex < total ? widget.records[_currentIndex].nop : '-';
    final sudahCount = widget.records.where((r) => r.isPaid).length;
    final belumCount = widget.records
        .where(
          (r) =>
              r.isChecked &&
              !r.isPaid &&
              !r.status.contains('Blacklist') &&
              r.status != 'Dilewati' &&
              !r.status.contains('Gagal'),
        )
        .length;
    unawaited(
      BatchNotificationService.instance.showProgress(
        current: _currentIndex,
        total: total,
        currentNop: currentNop,
        lunasCount: sudahCount,
        belumCount: belumCount,
        isPaused: true,
      ),
    );
  }

  void _cancelFromNotification() {
    if (!_isRunning && !_isPaused) return;
    _isRunning = false;
    _isPaused = false;
    unawaited(BatchNotificationService.instance.stopForegroundService());
    _notifyCancelledIfPartial();
    if (mounted) {
      setState(() {
        _statusMessage = 'Pengecekan dibatalkan dari notifikasi.';
      });
    }
  }

  void _resume() {
    _runBatch();
  }

  void _skipCurrent() {
    if (_currentIndex < widget.records.length) {
      widget.records[_currentIndex].status = 'Dilewati';
      setState(() {
        _currentIndex++;
      });
      if (_isRunning && !_isPaused) {
        _runBatch();
      }
    }
  }

  Future<void> _updateBlockInfoTxt({bool isFinal = false}) async {
    final dir = _sttsDirectory;
    if (dir == null) return;

    try {
      final blokStr = widget.sttsBlokNumber ??
          (widget.records.isNotEmpty
              ? nopBlok(widget.records.first.nop)
              : '000');
      final cleanBlok = blokStr.replaceAll(RegExp(r'[^0-9]'), '');
      final blokFormatted =
          cleanBlok.isNotEmpty ? cleanBlok.padLeft(3, '0') : blokStr;
      final txtFile = File('${dir.path}/INFORMASI_BLOK_$blokFormatted.txt');

      final desaName = activeDesaName;
      final kecName = activeKecamatanName;
      final totalRecords = widget.records.length;
      final sudahBayarList = widget.records.where((r) => r.isPaid).toList();
      final belumBayarList = widget.records
          .where((r) => !r.isPaid && r.isChecked)
          .toList();
      final gagalList =
          widget.records.where((r) => r.status.contains('Gagal')).toList();
      final sttsDownloadedCount = widget.records
          .where((r) => r.buktiBayarDownloaded == true)
          .length;

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
      buf.writeln('================================================================================');
      buf.writeln('                    INFORMASI REKAPITULASI PENGECEKAN BLOK');
      buf.writeln('                              KABUPATEN CIANJUR');
      buf.writeln('================================================================================');
      buf.writeln('Kecamatan         : $kecName');
      buf.writeln('Desa / Kelurahan  : $desaName');
      buf.writeln('Nomor Blok        : Blok $blokFormatted');
      buf.writeln('Tahun Pajak       : ${widget.tahun}');
      buf.writeln('Waktu Pembuatan   : $namaHari, $tglStr $jamStr');
      buf.writeln('Status Pengecekan : ${isFinal ? "Selesai" : "Sedang Berjalan / Sebagian"}');
      buf.writeln('Folder Berkas STTS: ${dir.path}');
      buf.writeln('--------------------------------------------------------------------------------');
      buf.writeln('RINGKASAN PEMERIKSAAN:');
      buf.writeln('--------------------------------------------------------------------------------');
      buf.writeln('Total Objek Pajak (NOP)  : $totalRecords');
      buf.writeln('Sudah Bayar (Lunas)      : ${sudahBayarList.length}');
      buf.writeln('Belum Bayar              : ${belumBayarList.length}');
      buf.writeln('Gagal / Kendala Cek      : ${gagalList.length}');
      buf.writeln('Berkas STTS Terunduh     : $sttsDownloadedCount berkas PDF');
      buf.writeln('Total Nominal Terbayar   : Rp ${formatRibuan(totalNominalBayar)}');
      if (totalNominalBelum > 0) {
        buf.writeln('Total Nominal Belum Bayar: Rp ${formatRibuan(totalNominalBelum)}');
      }
      buf.writeln('--------------------------------------------------------------------------------');
      buf.writeln('DAFTAR RINCIAN OBJEK PAJAK (NOP):');
      buf.writeln('--------------------------------------------------------------------------------');
      buf.writeln('No. | NOP                  | Nama Wajib Pajak             | Status Bayar | Nominal PBB   | Tanggal Bayar | No. STAN         | File STTS');
      buf.writeln('----+----------------------+------------------------------+--------------+---------------+---------------+------------------+------------------');

      for (int i = 0; i < widget.records.length; i++) {
        final r = widget.records[i];
        final no = (i + 1).toString().padRight(3);
        final nop = r.nop.padRight(20);
        final nama = (r.namaWajibPajak ?? '-').trim();
        final namaTrunc =
            (nama.length > 28 ? '${nama.substring(0, 25)}...' : nama)
                .padRight(28);
        final status = (r.isPaid
                ? 'Sudah Bayar'
                : (r.isChecked ? r.status : 'Belum Dicek'))
            .padRight(12);
        final nominal = (r.jumlahPbb != null && r.jumlahPbb!.isNotEmpty
                ? 'Rp ${cleanNominalRupiah(r.jumlahPbb!)}'
                : '-')
            .padRight(13);
        final tgl = (r.tanggalBayar ?? '-').padRight(13);
        final stan = (r.nomorStan ?? '-').padRight(16);
        final sttsStatus = r.buktiBayarDownloaded == true
            ? 'Terunduh'
            : (r.isPaid ? 'Gagal/Tidak Terbit' : '-');

        buf.writeln(
            '$no | $nop | $namaTrunc | $status | $nominal | $tgl | $stan | $sttsStatus');
      }

      buf.writeln('================================================================================');
      buf.writeln('Catatan:');
      buf.writeln('- Berkas STTS (.pdf) hanya dapat diunduh untuk NOP yang telah berstatus Sudah Bayar.');
      buf.writeln('- Berkas ini dihasilkan secara otomatis oleh Aplikasi Cek PBB Cianjur.');
      buf.writeln('================================================================================');

      await txtFile.writeAsString(buf.toString());
    } catch (e) {
      debugPrint('Gagal menulis berkas informasi blok: $e');
    }
  }

  void _goToResult() {
    _isRunning = false;
    _isPaused = false;
    if (widget.downloadStts && _sttsDirectory != null) {
      unawaited(_updateBlockInfoTxt(isFinal: true));
    }
    unawaited(BatchNotificationService.instance.stopForegroundService());
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ResultScreen(records: widget.records)),
    );
  }

  Future<bool> _onWillPop() async {
    if (!_isRunning) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hentikan Pengecekan Massal?'),
        content: const Text(
          'Pengecekan sedang berjalan. Data yang sudah selesai diperiksa tetap tersimpan aman di catatan perangkat Anda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjutkan Cek'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hentikan & Keluar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _isRunning = false;
      _isPaused = false;
      unawaited(BatchNotificationService.instance.stopForegroundService());
      _notifyCancelledIfPartial();
      return true;
    }
    return false;
  }

  Widget _buildCounterBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: LerpAnimatedCounter(
        value: count,
        formatter: (v) => '$label: ${v.round()}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme scheme) {
    final s = status.toLowerCase();
    if (s.contains('sudah') || s.contains('lunas')) return Colors.green;
    if (s.contains('belum')) return Colors.orange;
    if (s.contains('blacklist')) return Colors.deepPurple;
    if (s.contains('lewat')) return Colors.grey;
    if (s.contains('gagal') || s.contains('error')) return Colors.red;
    return scheme.outline;
  }

  IconData _statusIcon(String status) {
    final s = status.toLowerCase();
    if (s.contains('sudah') || s.contains('lunas')) return Icons.check_circle;
    if (s.contains('belum')) return Icons.schedule;
    if (s.contains('blacklist')) return Icons.block;
    if (s.contains('lewat')) return Icons.skip_next;
    if (s.contains('gagal') || s.contains('error')) return Icons.error_outline;
    return Icons.radio_button_unchecked;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.records.length;
    final sudahBayarCount = widget.records.where((r) => r.isPaid).length;
    final belumBayarCount = widget.records
        .where(
          (r) =>
              r.isChecked &&
              !r.isPaid &&
              r.status != 'Blacklist' &&
              r.status != 'Dilewati' &&
              r.status != 'Gagal Cek',
        )
        .length;
    final blacklistCount = widget.records
        .where((r) => r.status.contains('Blacklist'))
        .length;
    final gagalCount = widget.records
        .where((r) => r.status.contains('Gagal Cek'))
        .length;
    final dilewatiCount = widget.records
        .where((r) => r.status == 'Dilewati')
        .length;
    final sisaCount = (total - _currentIndex).clamp(0, total);
    final sttsDownloadedCount =
        widget.records.where((r) => r.buktiBayarDownloaded == true).length;
    final scheme = Theme.of(context).colorScheme;

    final progressVal = total == 0
        ? 0.0
        : (_currentIndex / total).clamp(0.0, 1.0);

    return PopScope(
      canPop: !_isRunning,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Cek Massal (${_currentIndex.clamp(0, total)}/$total)'),
          actions: [
            if (_currentIndex > 0)
              TextButton.icon(
                onPressed: _goToResult,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Hasil'),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  // Progress and Counters Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LerpAnimatedProgress(
                          value: progressVal,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildCounterBadge(
                              label: 'Sudah',
                              count: sudahBayarCount,
                              color: Colors.green,
                            ),
                            _buildCounterBadge(
                              label: 'Belum',
                              count: belumBayarCount,
                              color: Colors.orange,
                            ),
                            if (widget.downloadStts)
                              _buildCounterBadge(
                                label: 'STTS',
                                count: sttsDownloadedCount,
                                color: Colors.teal,
                              ),
                            if (blacklistCount > 0)
                              _buildCounterBadge(
                                label: 'Blacklist',
                                count: blacklistCount,
                                color: Colors.deepPurple,
                              ),
                            if (gagalCount > 0)
                              _buildCounterBadge(
                                label: 'Gagal',
                                count: gagalCount,
                                color: Colors.red,
                              ),
                            if (dilewatiCount > 0)
                              _buildCounterBadge(
                                label: 'Lewat',
                                count: dilewatiCount,
                                color: Colors.grey,
                              ),
                            _buildCounterBadge(
                              label: 'Sisa',
                              count: sisaCount,
                              color: scheme.primary,
                            ),
                          ],
                        ),
                        if (widget.downloadStts && _sttsDirectory != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.teal.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.folder_outlined,
                                  size: 16,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'STTS: ${_sttsDirectory!.path.split(Platform.pathSeparator).last}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.teal,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () =>
                                      NativeFileHelper.showInFileManager(
                                    _sttsDirectory!.path,
                                  ),
                                  child: const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      'Buka Folder',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                        decoration:
                                            TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Active Item & Controls Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      color: scheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (_isCooldown)
                                  const Icon(
                                    Icons.hourglass_top,
                                    size: 18,
                                    color: Colors.cyan,
                                  )
                                else if (_isRunning)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else if (_isPaused)
                                  const Icon(
                                    Icons.pause_circle_outline,
                                    size: 18,
                                    color: Colors.orange,
                                  )
                                else if (_isCompleted)
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                    color: Colors.green,
                                  )
                                else
                                  const Icon(
                                    Icons.pending_outlined,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _statusMessage,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: _isCooldown
                                              ? Colors.cyan.shade700
                                              : scheme.onSurfaceVariant,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (_current != null) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _current!.nop,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.05,
                                              ),
                                        ),
                                        if (_current!.namaWajibPajak != null &&
                                            _current!
                                                .namaWajibPajak!
                                                .isNotEmpty)
                                          Text(
                                            _current!.namaWajibPajak!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (nopBlok(_current!.nop).isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Blok ${nopBlok(_current!.nop)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            // Action controls
                            Row(
                              children: [
                                if (_isRunning) ...[
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: _pause,
                                      icon: const Icon(Icons.pause, size: 18),
                                      label: const Text('Jeda'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _goToResult,
                                      icon: const Icon(
                                        Icons.stop_circle_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Hentikan'),
                                    ),
                                  ),
                                ] else if (!_isCompleted) ...[
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _resume,
                                      icon: const Icon(
                                        Icons.play_arrow,
                                        size: 18,
                                      ),
                                      label: const Text('Lanjutkan'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _skipCurrent,
                                    child: const Text('Lewati'),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.outlined(
                                    tooltip: 'Lihat Hasil Sementara',
                                    onPressed: _goToResult,
                                    icon: const Icon(
                                      Icons.fact_check_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ] else ...[
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _goToResult,
                                      icon: const Icon(
                                        Icons.check_circle,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Buka Hasil Pengecekan',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Live Records List
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Daftar NOP (${widget.records.length})',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Tahun Pajak: ${widget.tahun}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),

                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: widget.records.length,
                      itemBuilder: (context, index) {
                        final item = widget.records[index];
                        final isCurrent = index == _currentIndex && _isRunning;
                        final color = _statusColor(item.status, scheme);
                        final icon = _statusIcon(item.status);

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? scheme.primaryContainer.withValues(alpha: 0.3)
                                : scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent
                                  ? scheme.primary
                                  : scheme.outlineVariant.withValues(
                                      alpha: 0.3,
                                    ),
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isCurrent ? Icons.sync : icon,
                              color: isCurrent ? scheme.primary : color,
                              size: 20,
                            ),
                            title: Text(
                              item.nop,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            subtitle:
                                (item.namaWajibPajak != null &&
                                        item.namaWajibPajak!.isNotEmpty) ||
                                    (item.tanggalBayar != null &&
                                        item.tanggalBayar!.isNotEmpty) ||
                                    item.buktiBayarDownloaded != null
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (item.namaWajibPajak != null &&
                                          item.namaWajibPajak!.isNotEmpty)
                                        Text(
                                          item.namaWajibPajak!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (item.tanggalBayar != null &&
                                          item.tanggalBayar!.isNotEmpty)
                                        Text(
                                          'Tgl Bayar: ${item.tanggalBayar}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (item.buktiBayarDownloaded != null)
                                        Text(
                                          item.buktiBayarDownloaded!
                                              ? 'STTS tersimpan'
                                              : 'STTS belum terbit / gagal diunduh',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: item.buktiBayarDownloaded!
                                                ? Colors.teal.shade700
                                                : Colors.orange.shade800,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  )
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                item.status.isEmpty
                                    ? (isCurrent ? 'Memeriksa...' : 'Antrean')
                                    : item.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
