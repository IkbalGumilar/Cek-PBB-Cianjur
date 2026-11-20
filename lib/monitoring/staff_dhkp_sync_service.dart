import 'dart:async';

import 'package:flutter/foundation.dart';

import '../batch_notification_service.dart';
import '../blok_data_store.dart';
import '../blok_record.dart';
import '../cianjur_wilayah_data.dart';
import '../currency_format.dart';
import '../dhkp/dhkp_grafik_analytics.dart';
import '../dhkp_widget_sync_service.dart';
import '../dusun_data.dart';
import '../nop_helper.dart';
import '../staff_portal_client.dart';
import '../user_friendly_error.dart';


/// Pilihan mode sinkronisasi DHKP dari Portal Staf
enum StaffSyncMode {
  paidOnly('Hanya Pelunasan (Sudah Bayar Saja) ⚡ Cepat & Rekomendasi'),
  full('Keseluruhan DHKP (Termasuk Belum Bayar) 🐢 Lambat');

  final String label;
  const StaffSyncMode(this.label);
}

/// Pilihan rentang waktu tanggal pelunasan untuk sinkronisasi cepat
enum StaffSyncDatePreset {
  allYear('Sepanjang Tahun Ini (01 Jan s/d Hari Ini)'),
  last7Days('7 Hari Terakhir (⚡ Kilat / Harian)'),
  last30Days('30 Hari Terakhir (1 Bulan)'),
  thisMonth('Bulan Ini (Awal Bulan s/d Hari Ini)'),
  custom('Pilih Tanggal Kustom...');

  final String label;
  const StaffSyncDatePreset(this.label);
}

/// Data hasil parsing satu baris tabel dari Portal Staf
class ParsedStaffRow {
  final String nop;
  final String namaWp;
  final String alamatWp;
  final String alamatOp;
  final String rtOp;
  final String rwOp;
  final String luasBumi;
  final String njopBumi;
  final String luasBangunan;
  final String njopBangunan;
  final String tanggalBayar;
  final String jumlahPbb;
  final String status;
  final String tahun;

  const ParsedStaffRow({
    required this.nop,
    required this.namaWp,
    this.alamatWp = '',
    required this.alamatOp,
    this.rtOp = '',
    this.rwOp = '',
    this.luasBumi = '',
    this.njopBumi = '',
    this.luasBangunan = '',
    this.njopBangunan = '',
    required this.tanggalBayar,
    required this.jumlahPbb,
    this.status = '',
    this.tahun = '',
  });
}

/// Ringkasan hasil akhir proses sinkronisasi DHKP dari Portal Staf
class StaffDhkpSyncOutcome {
  final String blokLabel;
  final String tahun;
  final int totalCheckedRows;
  final int updatedPaidCount;
  final int newSpptCount;
  final int alreadyPaidCount;
  final List<String> updatedNops;
  final List<String> newNops;
  final List<BlokRecord> updatedRecords;
  final List<BlokRecord> newRecords;
  final String? errorMessage;
  final bool isCancelled;

  const StaffDhkpSyncOutcome({
    required this.blokLabel,
    required this.tahun,
    this.totalCheckedRows = 0,
    this.updatedPaidCount = 0,
    this.newSpptCount = 0,
    this.alreadyPaidCount = 0,
    this.updatedNops = const [],
    this.newNops = const [],
    this.updatedRecords = const [],
    this.newRecords = const [],
    this.errorMessage,
    this.isCancelled = false,
  });

  bool get isSuccess => errorMessage == null && !isCancelled;
}

/// Status kemajuan terkini saat sinkronisasi sedang berjalan
class StaffDhkpSyncProgress {
  final int currentBlokIndex;
  final int totalBloks;
  final String currentBlok;
  final int totalCheckedRows;
  final int updatedPaidCount;
  final int newSpptCount;
  final String statusMessage;

  const StaffDhkpSyncProgress({
    required this.currentBlokIndex,
    required this.totalBloks,
    required this.currentBlok,
    required this.totalCheckedRows,
    required this.updatedPaidCount,
    required this.newSpptCount,
    required this.statusMessage,
  });

  double get ratio =>
      totalBloks > 0 ? (currentBlokIndex / totalBloks).clamp(0.0, 1.0) : 0.0;
}

/// Service untuk mengeksekusi sinkronisasi data bayar & SPPT baru
/// langsung dari tabel web Portal Staf ke database DHKP lokal.
class StaffDhkpSyncService {
  const StaffDhkpSyncService._();
  static const StaffDhkpSyncService instance = StaffDhkpSyncService._();

  /// Hasil sinkronisasi DHKP terakhir untuk laporan popup atau notifikasi klik
  static StaffDhkpSyncOutcome? lastOutcome;

  /// Parse satu baris data dari sel tabel HTML Monitoring Wilayah
  static ParsedStaffRow? parseRow(
    List<String> cells,
    List<String> headers, {
    String? defaultTahun,
  }) {
    if (cells.isEmpty) return null;

    int nopIdx = -1;
    int namaIdx = -1;
    int alamatWpIdx = -1;
    int alamatOpIdx = -1;
    int rtIdx = -1;
    int rwIdx = -1;
    int luasBumiIdx = -1;
    int njopBumiIdx = -1;
    int luasBgnIdx = -1;
    int njopBgnIdx = -1;
    int pokokBayarIdx = -1;
    int pokokKetetapanIdx = -1;
    int totalIdx = -1;
    int fallbackPokokIdx = -1;
    int statusIdx = -1;
    int tglIdx = -1;
    int jamIdx = -1;
    int tahunIdx = -1;

    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].toUpperCase();
      if (h == 'NOP' || (nopIdx == -1 && h.contains('NOP'))) {
        nopIdx = i;
      } else if (h.contains('ALAMAT WP') || h.contains('ALAMAT WAJIB')) {
        alamatWpIdx = i;
      } else if (h.contains('ALAMAT OP') ||
          h.contains('LETAK') ||
          (alamatOpIdx == -1 && h.contains('ALAMAT'))) {
        alamatOpIdx = i;
      } else if (h.contains('NAMA')) {
        namaIdx = i;
      } else if (h.contains('RT OP') || h == 'RT') {
        rtIdx = i;
      } else if (h.contains('RW OP') || h == 'RW') {
        rwIdx = i;
      } else if (h.contains('LUAS BUMI') || h.contains('LUAS TANAH')) {
        luasBumiIdx = i;
      } else if (h.contains('NJOP BUMI') || h.contains('NJOP TANAH')) {
        njopBumiIdx = i;
      } else if (h.contains('LUAS BANGUNAN')) {
        luasBgnIdx = i;
      } else if (h.contains('NJOP BANGUNAN')) {
        njopBgnIdx = i;
      } else if (h.contains('POKOK PEMBAYARAN') ||
          h.contains('ESTIMASI_POKOK') ||
          h.contains('ESTIMASI POKOK')) {
        pokokBayarIdx = i;
      } else if (h.contains('POKOK KETETAPAN')) {
        pokokKetetapanIdx = i;
      } else if (h == 'TOTAL' || (totalIdx == -1 && h.contains('TOTAL'))) {
        totalIdx = i;
      } else if (fallbackPokokIdx == -1 &&
          (h.contains('POKOK') ||
              h.contains('KETETAPAN') ||
              h.contains('TAGIHAN') ||
              h.contains('NOMINAL') ||
              h.contains('JUMLAH'))) {
        fallbackPokokIdx = i;
      } else if (h.contains('TANGGAL PEMBAYARAN') ||
          (tglIdx == -1 &&
              (h.contains('TGL') ||
                  h.contains('TANGGAL') ||
                  h.contains('BAYAR')))) {
        tglIdx = i;
      } else if (h.contains('JAM') ||
          h.contains('WAKTU') ||
          h.contains('PUKUL')) {
        jamIdx = i;
      } else if (h == 'THN' ||
          h == 'TAHUN' ||
          h.contains('THN PAJAK') ||
          h.contains('TAHUN PAJAK') ||
          h.contains('THN_PAJAK')) {
        tahunIdx = i;
      } else if (h == 'STATUS') {
        statusIdx = i;
      }
    }

    String rawNop = '';
    if (nopIdx != -1 && nopIdx < cells.length) {
      rawNop = cells[nopIdx];
    } else {
      // Fallback: cari sel yang memuat tepat 18 digit
      for (final c in cells) {
        final digits = c.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 18) {
          rawNop = digits;
          break;
        }
      }
    }

    final clean = rawNop.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length != 18) return null;

    final nama = (namaIdx != -1 && namaIdx < cells.length)
        ? cells[namaIdx].trim()
        : '';
    final alamatWp = (alamatWpIdx != -1 && alamatWpIdx < cells.length)
        ? cells[alamatWpIdx].trim()
        : '';
    final alamatOp = (alamatOpIdx != -1 && alamatOpIdx < cells.length)
        ? cells[alamatOpIdx].trim()
        : '';
    final rtOp = (rtIdx != -1 && rtIdx < cells.length)
        ? cells[rtIdx].trim()
        : '';
    final rwOp = (rwIdx != -1 && rwIdx < cells.length)
        ? cells[rwIdx].trim()
        : '';
    final luasBumi = (luasBumiIdx != -1 && luasBumiIdx < cells.length)
        ? cells[luasBumiIdx].trim()
        : '';
    final njopBumi = (njopBumiIdx != -1 && njopBumiIdx < cells.length)
        ? cells[njopBumiIdx].trim()
        : '';
    final luasBangunan = (luasBgnIdx != -1 && luasBgnIdx < cells.length)
        ? cells[luasBgnIdx].trim()
        : '';
    final njopBangunan = (njopBgnIdx != -1 && njopBgnIdx < cells.length)
        ? cells[njopBgnIdx].trim()
        : '';
    final status = (statusIdx != -1 && statusIdx < cells.length)
        ? cells[statusIdx].trim()
        : '';

    final tglRaw = (tglIdx != -1 && tglIdx < cells.length)
        ? cells[tglIdx].trim()
        : '';
    var tgl = (tglRaw.isNotEmpty && tglRaw != '-' && tglRaw != '0')
        ? normalizePaymentDate(tglRaw, defaultTahun: defaultTahun)
        : '';

    if (jamIdx != -1 && jamIdx < cells.length) {
      final jamRaw = cells[jamIdx].trim();
      if (RegExp(r'\d{1,2}:\d{1,2}').hasMatch(jamRaw) && !tgl.contains(':')) {
        tgl = '$tgl $jamRaw';
      }
    }

    String parsedTahun = '';
    if (tahunIdx != -1 && tahunIdx < cells.length) {
      final tDigits = cells[tahunIdx].replaceAll(RegExp(r'[^0-9]'), '').trim();
      if (tDigits.length == 4) {
        parsedTahun = tDigits;
      }
    }
    if (parsedTahun.isEmpty) {
      for (var i = 0; i < cells.length; i++) {
        if (i == nopIdx ||
            i == luasBumiIdx ||
            i == njopBumiIdx ||
            i == luasBgnIdx ||
            i == njopBgnIdx ||
            i == pokokBayarIdx ||
            i == pokokKetetapanIdx ||
            i == totalIdx ||
            i == fallbackPokokIdx) {
          continue;
        }
        final trimmed = cells[i].trim();
        if (RegExp(r'^(19\d\d|20\d\d)$').hasMatch(trimmed)) {
          parsedTahun = trimmed;
          break;
        }
      }
    }
    if (parsedTahun.isEmpty &&
        defaultTahun != null &&
        defaultTahun.isNotEmpty) {
      parsedTahun = defaultTahun;
    }

    String extractDigits(int idx) {
      if (idx != -1 && idx < cells.length) {
        return cells[idx].replaceAll(RegExp(r'[^0-9]'), '');
      }
      return '';
    }

    final bayarDigits = extractDigits(pokokBayarIdx);
    final ketetapanDigits = extractDigits(pokokKetetapanIdx);
    final fallbackDigits = extractDigits(fallbackPokokIdx);
    final totalDigits = extractDigits(totalIdx);

    // Prioritas pemilihan nilai PBB:
    // 1. Jika ada pokokBayar/estimasi dan bernilai > 0, gunakan ini (karena pada tabel Belum Bayar di sistem V-Tax Cianjur, pokok ketetapan diisi 0 sementara nominal aktual ada di kolom estimasi/pokok pembayaran)
    // 2. Jika pokokKetetapan > 0, gunakan pokokKetetapan
    // 3. Fallback ke kolom lain yang memuat angka > 0
    // 4. Jika semua 0 tetapi total > 0, gunakan total
    String selectedPokok = '';
    if (bayarDigits.isNotEmpty && (int.tryParse(bayarDigits) ?? 0) > 0) {
      selectedPokok = bayarDigits;
    } else if (ketetapanDigits.isNotEmpty &&
        (int.tryParse(ketetapanDigits) ?? 0) > 0) {
      selectedPokok = ketetapanDigits;
    } else if (fallbackDigits.isNotEmpty &&
        (int.tryParse(fallbackDigits) ?? 0) > 0) {
      selectedPokok = fallbackDigits;
    } else if (totalDigits.isNotEmpty && (int.tryParse(totalDigits) ?? 0) > 0) {
      selectedPokok = totalDigits;
    } else {
      selectedPokok = bayarDigits.isNotEmpty
          ? bayarDigits
          : (ketetapanDigits.isNotEmpty ? ketetapanDigits : fallbackDigits);
    }

    return ParsedStaffRow(
      nop: clean,
      namaWp: nama,
      alamatWp: alamatWp,
      alamatOp: alamatOp,
      rtOp: rtOp,
      rwOp: rwOp,
      luasBumi: luasBumi,
      njopBumi: njopBumi,
      luasBangunan: luasBangunan,
      njopBangunan: njopBangunan,
      tanggalBayar: tgl,
      jumlahPbb: selectedPokok,
      status: status,
      tahun: parsedTahun,
    );
  }

  /// Menormalkan format tanggal bayar ke format YYYY-MM-DD (dan jam jika tersedia)
  static String normalizePaymentDate(String raw, {String? defaultTahun}) {
    if (raw.isEmpty || raw == '0' || raw == '-') return '';

    // Jika sudah format YYYY-MM-DD atau YYYY-MM-DD HH:mm(:ss)
    if (RegExp(
      r'^\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{1,2}(?::\d{1,2})?)?$',
    ).hasMatch(raw)) {
      return raw;
    }

    final dt = parsePaymentDate(raw);
    if (dt != null) {
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hasTime = dt.hour != 0 || dt.minute != 0 || dt.second != 0;
      if (hasTime) {
        final h = dt.hour.toString().padLeft(2, '0');
        final min = dt.minute.toString().padLeft(2, '0');
        final sec = dt.second.toString().padLeft(2, '0');
        return '$y-$m-$d $h:$min:$sec';
      }
      return '$y-$m-$d';
    }

    return raw;
  }

  Future<({MonitoringTableResult result, Duration elapsed})> _fetchSyncPageWithRetry({
    required Future<MonitoringTableResult> Function() fetcher,
    required String label,
    required int page,
    required int maxRetries,
    required Duration retryBaseDelay,
    required void Function(String status) notify,
    bool Function()? shouldCancel,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final sw = Stopwatch()..start();
      MonitoringTableResult tableResult;
      try {
        tableResult = await fetcher();
      } catch (e) {
        tableResult = MonitoringTableResult(
          headers: const [],
          rows: const [],
          errorMessage: friendlyErrorMessage(
            e,
            fallback: 'Koneksi terganggu saat memuat halaman $page.',
          ),
        );
      }
      sw.stop();


      final hasError =
          tableResult.errorMessage != null && tableResult.rows.isEmpty;
      if (!hasError || attempt > maxRetries) {
        return (result: tableResult, elapsed: sw.elapsed);
      }

      if (shouldCancel?.call() ?? false) {
        return (result: tableResult, elapsed: sw.elapsed);
      }

      final backoffMs = retryBaseDelay.inMilliseconds * attempt;
      notify(
        'Server sibuk saat memuat $label Hal $page. Mencoba ulang ($attempt/$maxRetries)...',
      );
      if (backoffMs > 0) {
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  /// Eksekusi sinkronisasi data bayar dari Portal Staf ke DHKP lokal.
  /// Bekerja bertahap per halaman secara ramah server (dilengkapi retry otomatis, jeda adaptif & wake lock).
  Future<StaffDhkpSyncOutcome> syncBloks({
    required StaffPortalClient client,
    required String tahun,
    required List<String> bloks,
    required String kelurahanCode,
    required String kecamatanCode,
    StaffSyncMode mode = StaffSyncMode.paidOnly,
    String? tglBayarAwal,
    String? tglBayarAkhir,
    String? tglCutoff,
    String bukuMin = '',
    String bukuMax = '',
    Duration pacingDelay = const Duration(milliseconds: 350),
    Duration retryBaseDelay = const Duration(milliseconds: 1200),
    int maxRetriesPerPage = 3,
    int maxPages = 1000,
    void Function(StaffDhkpSyncProgress progress)? onProgress,
    bool Function()? shouldCancel,
    bool Function()? isPaused,
    int initialPageBb = 1,
    int initialPageSb = 1,
    bool skipBelumBayar = false,
    void Function(int nextPageBb, int nextPageSb, bool bbCompleted)?
    onPageCheckpoint,
  }) async {
    final effectiveTglAwal = (tglBayarAwal != null && tglBayarAwal.isNotEmpty)
        ? tglBayarAwal
        : '$tahun-01-01';
    final effectiveTglAkhir =
        (tglBayarAkhir != null && tglBayarAkhir.isNotEmpty)
        ? tglBayarAkhir
        : DateTime.now().toIso8601String().substring(0, 10);
    final effectiveCutoff = (tglCutoff != null && tglCutoff.isNotEmpty)
        ? tglCutoff
        : DateTime.now().toIso8601String().substring(0, 10);

    // Normalisasi kode wilayah V-Tax agar tetap bekerja baik untuk akun Bapenda, Kecamatan, maupun Desa
    final rawKec3 = extractKecamatanCode3(
      kecamatanCode.isNotEmpty
          ? kecamatanCode
          : (client.activeKecamatanCode.isNotEmpty
                ? client.activeKecamatanCode
                : activeKecamatanCode),
    );
    final rawKel3 = extractKelurahanCode3(
      kelurahanCode.isNotEmpty
          ? kelurahanCode
          : (client.activeKelurahanCode.isNotEmpty
                ? client.activeKelurahanCode
                : activeKelurahanCode),
    );
    final kecCode3 = rawKec3.isNotEmpty ? rawKec3 : '200';
    final kelCode3 = rawKel3.isNotEmpty ? rawKel3 : '004';
    final effKecCode = toVtaxKecamatanCode(kecCode3);
    final effKelCode = toVtaxKelurahanCode(kelCode: kelCode3, kecCode: kecCode3);
    final effKecName = activeKecamatanName.isNotEmpty
        ? activeKecamatanName
        : lookupKecamatanName(kecCode3);
    final effDesaName = activeDesaName.isNotEmpty
        ? activeDesaName
        : lookupKelurahanName(kelCode3, kecamatanCode: kecCode3);

    final totalBloks = bloks.length;
    final blokSummaryLabel = totalBloks == 1
        ? 'Blok ${bloks.first}'
        : '$totalBloks Blok';

    // 1. Notifikasi awal (Android Foreground Service & 1 notif awal di Desktop)
    await BatchNotificationService.instance.showStarted(
      title: 'Sinkronisasi DHKP Dimulai ($blokSummaryLabel)',
      content: 'Menghubungkan ke Portal Petugas Bapenda ($totalBloks blok)...',
      total: totalBloks,
    );

    int totalCheckedRows = 0;
    int updatedPaidCount = 0;
    int newSpptCount = 0;
    int alreadyPaidCount = 0;
    final updatedNops = <String>[];
    final newNops = <String>[];
    final updatedRecords = <BlokRecord>[];
    final newRecords = <BlokRecord>[];

    final recordsToUpsertMap = <String, BlokRecord>{};

    try {
      if (shouldCancel?.call() ?? false) {
        await BatchNotificationService.instance.showStaffSyncCancelled(
          currentBlok: 0,
          totalBloks: totalBloks,
          updatedPaidCount: 0,
          newSpptCount: 0,
          blokLabel: blokSummaryLabel,
        );
        return StaffDhkpSyncOutcome(
          blokLabel: blokSummaryLabel,
          tahun: tahun,
          isCancelled: true,
        );
      }

      // 2. Baca data DHKP lokal sekali di awal untuk pencocokan cepat
      final existingAll = await BlokDataStore.instance.loadAll();
      final keyToExisting = <String, BlokRecord>{};
      final nopToPriorPbb = <String, String>{};
      final existingBloksSet = <String>{};
      for (final r in existingAll) {
        keyToExisting[r.uniqueKey] = r;
        final rb = r.blok.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
        if (rb.isNotEmpty && rb != '000') existingBloksSet.add(rb);
        if (r.jumlahPbbValue > 0) {
          nopToPriorPbb[r.nop] = r.jumlahPbb;
        }
      }

      final targetBlokSet = bloks
          .map((b) => b.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0'))
          .where((b) => b.isNotEmpty && b != '000')
          .toSet();

      final dusunScope = DusunData.instance.scope;
      final dusunAllowedSet = dusunScope.isDusunScope
          ? dusunScope.allowedBloks
                .map((b) => b.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0'))
                .where((b) => b.isNotEmpty && b != '000')
                .toSet()
          : <String>{};

      // Tentukan apakah pengguna menyinkronkan seluruh blok se-desa (tanpa kunci dusun)
      // atau memfilter ke blok/dusun tertentu.
      final isFullVillageSelection =
          dusunAllowedSet.isEmpty &&
          (targetBlokSet.isEmpty ||
              (existingBloksSet.isNotEmpty &&
                  targetBlokSet.length >= existingBloksSet.length &&
                  targetBlokSet.containsAll(existingBloksSet)));

      bool isBlokAllowed(String blok3) {
        if (dusunAllowedSet.isNotEmpty && !dusunAllowedSet.contains(blok3)) {
          return false;
        }
        if (!isFullVillageSelection &&
            targetBlokSet.isNotEmpty &&
            !targetBlokSet.contains(blok3)) {
          return false;
        }
        return true;
      }

      // -------------------------------------------------------------
      // PENGAMBILAN DATA (BERURUTAN & RAMAH SERVER UNTUK BB & SB)
      // -------------------------------------------------------------
      int pageBb = 0;
      int estimatedTotalPagesBb = 1;
      int checkedBb = 0;
      final bbRows = <ParsedStaffRow>[];
      String? bbErrorMessage;

      int pageSb = 0;
      int estimatedTotalPagesSb = 1;
      int checkedSb = 0;
      final sbRows = <ParsedStaffRow>[];
      String? sbErrorMessage;

      void notifyProgress(String currentStatus) {
        final totalPages = (mode == StaffSyncMode.full)
            ? (estimatedTotalPagesBb + estimatedTotalPagesSb)
            : estimatedTotalPagesSb;
        final currentPage = (mode == StaffSyncMode.full)
            ? (pageBb + pageSb)
            : pageSb;
        final currentChecked = checkedBb + checkedSb;

        final statusMsg = (mode == StaffSyncMode.full)
            ? 'Menyinkronkan: BB Hal $pageBb/$estimatedTotalPagesBb • SB Hal $pageSb/$estimatedTotalPagesSb ($currentChecked baris diperiksa)...'
            : 'Menyinkronkan: Sudah Bayar Hal $pageSb/$estimatedTotalPagesSb ($currentChecked baris diperiksa)...';

        onProgress?.call(
          StaffDhkpSyncProgress(
            currentBlokIndex: currentPage,
            totalBloks: totalPages,
            currentBlok: '$blokSummaryLabel ($statusMsg)',
            totalCheckedRows: currentChecked,
            updatedPaidCount: updatedPaidCount,
            newSpptCount: newSpptCount,
            statusMessage: currentStatus.isNotEmpty ? currentStatus : statusMsg,
          ),
        );

        BatchNotificationService.instance.showStaffSyncProgress(
          currentBlok: currentPage,
          totalBloks: totalPages,
          currentBlokName: '$blokSummaryLabel ($statusMsg)',
          updatedPaid: updatedPaidCount,
          newSppt: newSpptCount,
          isPaused: isPaused?.call() ?? false,
        );
      }

      Future<void> runBelumBayar() async {
        if (skipBelumBayar) {
          pageBb = initialPageBb > 1 ? initialPageBb - 1 : 0;
          return;
        }
        int page = initialPageBb < 1 ? 1 : initialPageBb;
        bool hasMore = true;
        while (hasMore) {
          if (shouldCancel?.call() ?? false) return;
          while (isPaused?.call() ?? false) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (shouldCancel?.call() ?? false) return;
          }

          pageBb = page;
          notifyProgress('Memuat data Belum Bayar (Halaman $page)...');

          final fetched = await _fetchSyncPageWithRetry(
            fetcher: () => client.fetchBelumBayar(
              tglCutoff: effectiveCutoff,
              tahunAwal: tahun,
              tahunAkhir: tahun,
              bukuMin: bukuMin,
              bukuMax: bukuMax,
              nop: '',
              kelurahan: effKelCode,
              kecamatan: effKecCode,
              page: page,
            ),
            label: 'Belum Bayar',
            page: page,
            maxRetries: maxRetriesPerPage,
            retryBaseDelay: retryBaseDelay,
            notify: notifyProgress,
            shouldCancel: shouldCancel,
          );
          final tableResult = fetched.result;

          if (tableResult.errorMessage != null && tableResult.rows.isEmpty) {
            bbErrorMessage ??= (page == 1)
                ? tableResult.errorMessage
                : 'Terputus di halaman $page: ${tableResult.errorMessage}';
            break;
          }

          if (tableResult.rows.isEmpty) break;

          if (tableResult.totalRecords > 0) {
            estimatedTotalPagesBb = (tableResult.totalRecords / 50).ceil();
            if (estimatedTotalPagesBb < 1) estimatedTotalPagesBb = 1;
          }

          checkedBb += tableResult.rows.length;
          final headers = tableResult.headers;
          for (final row in tableResult.rows) {
            final parsed = parseRow(row, headers, defaultTahun: tahun);
            if (parsed != null) bbRows.add(parsed);
          }

          notifyProgress(
            'Memuat data Belum Bayar: Hal $page dari $estimatedTotalPagesBb...',
          );

          if (tableResult.hasNextPage && page < maxPages) {
            page++;
            onPageCheckpoint?.call(page, initialPageSb, false);
            var adaptiveDelay = pacingDelay;
            if (pacingDelay > Duration.zero &&
                fetched.elapsed.inMilliseconds > 2000) {
              adaptiveDelay += const Duration(milliseconds: 500);
            }
            if (adaptiveDelay > Duration.zero) {
              await Future.delayed(adaptiveDelay);
            }
          } else {
            hasMore = false;
            onPageCheckpoint?.call(page + 1, initialPageSb, true);
          }
        }
      }

      Future<void> runSudahBayar() async {
        int page = initialPageSb < 1 ? 1 : initialPageSb;
        bool hasMore = true;
        while (hasMore) {
          if (shouldCancel?.call() ?? false) return;
          while (isPaused?.call() ?? false) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (shouldCancel?.call() ?? false) return;
          }

          pageSb = page;
          notifyProgress('Memuat data Sudah Bayar (Halaman $page)...');

          final fetched = await _fetchSyncPageWithRetry(
            fetcher: () => client.fetchSudahBayar(
              tglBayarAwal: effectiveTglAwal,
              tglBayarAkhir: effectiveTglAkhir,
              tahunAwal: tahun,
              tahunAkhir: tahun,
              bukuMin: bukuMin,
              bukuMax: bukuMax,
              nop: '',
              kelurahan: effKelCode,
              kecamatan: effKecCode,
              page: page,
            ),
            label: 'Sudah Bayar',
            page: page,
            maxRetries: maxRetriesPerPage,
            retryBaseDelay: retryBaseDelay,
            notify: notifyProgress,
            shouldCancel: shouldCancel,
          );
          final tableResult = fetched.result;

          if (tableResult.errorMessage != null && tableResult.rows.isEmpty) {
            sbErrorMessage ??= (page == 1)
                ? tableResult.errorMessage
                : 'Terputus di halaman $page: ${tableResult.errorMessage}';
            break;
          }

          if (tableResult.rows.isEmpty) break;

          if (tableResult.totalRecords > 0) {
            estimatedTotalPagesSb = (tableResult.totalRecords / 50).ceil();
            if (estimatedTotalPagesSb < 1) estimatedTotalPagesSb = 1;
          }

          checkedSb += tableResult.rows.length;
          final headers = tableResult.headers;
          for (final row in tableResult.rows) {
            final parsed = parseRow(row, headers, defaultTahun: tahun);
            if (parsed != null) sbRows.add(parsed);
          }

          notifyProgress(
            'Memuat data Sudah Bayar: Hal $page dari $estimatedTotalPagesSb...',
          );

          if (tableResult.hasNextPage && page < maxPages) {
            page++;
            onPageCheckpoint?.call(pageBb + 1, page, true);
            var adaptiveDelay = pacingDelay;
            if (pacingDelay > Duration.zero &&
                fetched.elapsed.inMilliseconds > 2000) {
              adaptiveDelay += const Duration(milliseconds: 500);
            }
            if (adaptiveDelay > Duration.zero) {
              await Future.delayed(adaptiveDelay);
            }
          } else {
            hasMore = false;
          }
        }
      }

      // Jalankan proses unduh data secara berurutan agar aman dari rate-limit server
      if (mode == StaffSyncMode.full) {
        await runBelumBayar();
        await runSudahBayar();
      } else {
        await runSudahBayar();
      }

      totalCheckedRows = checkedBb + checkedSb;

      if (shouldCancel?.call() ?? false) {
        await BatchNotificationService.instance.showStaffSyncCancelled(
          currentBlok: pageBb + pageSb,
          totalBloks: estimatedTotalPagesBb + estimatedTotalPagesSb,
          updatedPaidCount: updatedPaidCount,
          newSpptCount: newSpptCount,
          blokLabel: blokSummaryLabel,
        );
        return StaffDhkpSyncOutcome(
          blokLabel: blokSummaryLabel,
          tahun: tahun,
          totalCheckedRows: totalCheckedRows,
          updatedPaidCount: updatedPaidCount,
          newSpptCount: newSpptCount,
          alreadyPaidCount: alreadyPaidCount,
          updatedNops: updatedNops,
          newNops: newNops,
          isCancelled: true,
        );
      }

      final isSessionDead =
          (bbErrorMessage?.contains('kedaluwarsa') ?? false) ||
          (sbErrorMessage?.contains('kedaluwarsa') ?? false);
      if (isSessionDead) {
        return StaffDhkpSyncOutcome(
          blokLabel: blokSummaryLabel,
          tahun: tahun,
          errorMessage:
              'Sesi login ke Portal Petugas telah kedaluwarsa. Silakan masuk kembali melalui Menu Petugas sebelum melanjutkan sinkronisasi.',
        );
      }

      if (mode == StaffSyncMode.paidOnly &&
          sbErrorMessage != null &&
          sbRows.isEmpty) {
        return StaffDhkpSyncOutcome(
          blokLabel: blokSummaryLabel,
          tahun: tahun,
          errorMessage: sbErrorMessage,
        );
      } else if (mode == StaffSyncMode.full) {
        if (bbErrorMessage != null &&
            bbRows.isEmpty &&
            sbErrorMessage != null &&
            sbRows.isEmpty) {
          return StaffDhkpSyncOutcome(
            blokLabel: blokSummaryLabel,
            tahun: tahun,
            errorMessage:
                'Belum Bayar: $bbErrorMessage; Sudah Bayar: $sbErrorMessage',
          );
        } else if (bbErrorMessage != null && bbRows.isEmpty) {
          return StaffDhkpSyncOutcome(
            blokLabel: blokSummaryLabel,
            tahun: tahun,
            errorMessage: 'Gagal memuat data Belum Bayar: $bbErrorMessage',
          );
        } else if (sbErrorMessage != null && sbRows.isEmpty) {
          return StaffDhkpSyncOutcome(
            blokLabel: blokSummaryLabel,
            tahun: tahun,
            errorMessage: 'Gagal memuat data Sudah Bayar: $sbErrorMessage',
          );
        }
      }

      // -------------------------------------------------------------
      // PENGOLAHAN DATA KE MEMORI LOKAL SECARA MENYELURUH
      // -------------------------------------------------------------

      // 1. TAHAP BELUM BAYAR:
      // Memperbarui informasi rincian objek pajak (nama, alamat, luas, NJOP, ketetapan)
      // untuk NOP yang ada di DHKP lokal dan belum lunas. NOP tidak dikenal di Belum Bayar
      // diabaikan agar NOP nonaktif/blokir di server tidak mencemari DHKP aktif.
      for (final parsed in bbRows) {
        final b = nopBlok(parsed.nop);
        if (!isBlokAllowed(b)) {
          continue;
        }

        final rowTahun = parsed.tahun.isNotEmpty ? parsed.tahun : tahun;
        final key = '${parsed.nop}|$rowTahun';
        final existing = keyToExisting[key];

        if (existing != null && !existing.isPaid) {
          final parsedPbbVal = parseNominalRupiah(parsed.jumlahPbb);
          final existingPbbVal = existing.jumlahPbbValue;
          final priorPbb = nopToPriorPbb[parsed.nop] ?? '';

          String resolvedPbb = existing.jumlahPbb;
          num effectivePbbVal = existingPbbVal;
          if (parsedPbbVal > 0) {
            resolvedPbb = formatRupiah(parsedPbbVal);
            effectivePbbVal = parsedPbbVal;
          } else if (existingPbbVal > 0) {
            resolvedPbb = existing.jumlahPbb;
          } else if (priorPbb.isNotEmpty) {
            resolvedPbb = formatRupiah(priorPbb);
            effectivePbbVal = parseNominalRupiah(priorPbb);
          }

          final updated = existing.copyWith(
            namaWajibPajak: parsed.namaWp.isNotEmpty
                ? parsed.namaWp
                : existing.namaWajibPajak,
            alamatObjek: parsed.alamatOp.isNotEmpty
                ? parsed.alamatOp
                : existing.alamatObjek,
            alamatWp: parsed.alamatWp.isNotEmpty
                ? parsed.alamatWp
                : existing.alamatWp,
            rtObjek: parsed.rtOp.isNotEmpty ? parsed.rtOp : existing.rtObjek,
            kecamatan: existing.kecamatan.isNotEmpty
                ? existing.kecamatan
                : effKecName,
            kelurahan: existing.kelurahan.isNotEmpty
                ? existing.kelurahan
                : effDesaName,
            luasBumi: parsed.luasBumi.isNotEmpty
                ? parsed.luasBumi
                : existing.luasBumi,
            njopBumi: parsed.njopBumi.isNotEmpty
                ? parsed.njopBumi
                : existing.njopBumi,
            luasBangunan: parsed.luasBangunan.isNotEmpty
                ? parsed.luasBangunan
                : existing.luasBangunan,
            njopBangunan: parsed.njopBangunan.isNotEmpty
                ? parsed.njopBangunan
                : existing.njopBangunan,
            jumlahPbb: resolvedPbb,
            isTargetPemda:
                effectivePbbVal >= 2000000 || existing.isTargetPemda,
          );
          keyToExisting[key] = updated;
          recordsToUpsertMap[key] = updated;
        }
      }

      // 2. TAHAP SUDAH BAYAR:
      // Memperbarui status pembayaran menjadi 'Sudah Bayar' beserta seluruh metadata objek,
      // serta mencatat NOP baru yang terbit dan telah lunas.
      for (final parsed in sbRows) {
        final b = nopBlok(parsed.nop);
        if (!isBlokAllowed(b)) {
          continue;
        }

        final rowTahun = parsed.tahun.isNotEmpty ? parsed.tahun : tahun;
        final key = '${parsed.nop}|$rowTahun';
        final existing = keyToExisting[key];

        final parsedPbbVal = parseNominalRupiah(parsed.jumlahPbb);
        final priorPbb = nopToPriorPbb[parsed.nop] ?? '';

        if (existing != null) {
          final existingPbbVal = existing.jumlahPbbValue;
          String resolvedPbb = existing.jumlahPbb;
          num effectivePbbVal = existingPbbVal;

          if (parsedPbbVal > 0) {
            resolvedPbb = cleanNominalRupiah(parsedPbbVal);
            effectivePbbVal = parsedPbbVal;
          } else if (existingPbbVal > 0) {
            resolvedPbb = cleanNominalRupiah(existing.jumlahPbb);
          } else if (priorPbb.isNotEmpty) {
            resolvedPbb = cleanNominalRupiah(priorPbb);
            effectivePbbVal = parseNominalRupiah(priorPbb);
          }

          final effTgl = parsed.tanggalBayar.isNotEmpty
              ? parsed.tanggalBayar
              : existing.tanggalBayar;
          final catatanBayar =
              (existing.catatan.isNotEmpty &&
                  !existing.catatan.startsWith('Sudah bayar') &&
                  !existing.catatan.startsWith('SPPT Baru'))
              ? existing.catatan
              : formatCatatanSudahBayar(effTgl, rowTahun);

          if (!existing.isPaid) {
            final updated = existing.copyWith(
              statusBayar: 'Sudah Bayar',
              tanggalBayar: effTgl,
              jumlahPbb: resolvedPbb,
              namaWajibPajak: parsed.namaWp.isNotEmpty
                  ? parsed.namaWp
                  : existing.namaWajibPajak,
              alamatObjek: parsed.alamatOp.isNotEmpty
                  ? parsed.alamatOp
                  : existing.alamatObjek,
              alamatWp: parsed.alamatWp.isNotEmpty
                  ? parsed.alamatWp
                  : existing.alamatWp,
              rtObjek: parsed.rtOp.isNotEmpty ? parsed.rtOp : existing.rtObjek,
              kecamatan: existing.kecamatan.isNotEmpty
                  ? existing.kecamatan
                  : effKecName,
              kelurahan: existing.kelurahan.isNotEmpty
                  ? existing.kelurahan
                  : effDesaName,
              luasBumi: parsed.luasBumi.isNotEmpty
                  ? parsed.luasBumi
                  : existing.luasBumi,
              njopBumi: parsed.njopBumi.isNotEmpty
                  ? parsed.njopBumi
                  : existing.njopBumi,
              luasBangunan: parsed.luasBangunan.isNotEmpty
                  ? parsed.luasBangunan
                  : existing.luasBangunan,
              njopBangunan: parsed.njopBangunan.isNotEmpty
                  ? parsed.njopBangunan
                  : existing.njopBangunan,
              isTargetPemda:
                  effectivePbbVal >= 2000000 || existing.isTargetPemda,
              catatan: catatanBayar,
            );
            keyToExisting[key] = updated;
            recordsToUpsertMap[key] = updated;
            updatedPaidCount++;
            updatedNops.add(parsed.nop);
            updatedRecords.add(updated);
          } else {
            alreadyPaidCount++;
            // Tetap lengkapi metadata bila record Sudah Bayar lokal sebelumnya belum lengkap
            final enriched = existing.copyWith(
              tanggalBayar: existing.tanggalBayar.isNotEmpty
                  ? existing.tanggalBayar
                  : effTgl,
              jumlahPbb: resolvedPbb,
              namaWajibPajak: parsed.namaWp.isNotEmpty
                  ? parsed.namaWp
                  : existing.namaWajibPajak,
              alamatObjek: parsed.alamatOp.isNotEmpty
                  ? parsed.alamatOp
                  : existing.alamatObjek,
              alamatWp: parsed.alamatWp.isNotEmpty
                  ? parsed.alamatWp
                  : existing.alamatWp,
              rtObjek: parsed.rtOp.isNotEmpty ? parsed.rtOp : existing.rtObjek,
              kecamatan: existing.kecamatan.isNotEmpty
                  ? existing.kecamatan
                  : effKecName,
              kelurahan: existing.kelurahan.isNotEmpty
                  ? existing.kelurahan
                  : effDesaName,
              luasBumi: parsed.luasBumi.isNotEmpty
                  ? parsed.luasBumi
                  : existing.luasBumi,
              njopBumi: parsed.njopBumi.isNotEmpty
                  ? parsed.njopBumi
                  : existing.njopBumi,
              luasBangunan: parsed.luasBangunan.isNotEmpty
                  ? parsed.luasBangunan
                  : existing.luasBangunan,
              njopBangunan: parsed.njopBangunan.isNotEmpty
                  ? parsed.njopBangunan
                  : existing.njopBangunan,
              isTargetPemda:
                  effectivePbbVal >= 2000000 || existing.isTargetPemda,
            );
            if (enriched != existing) {
              keyToExisting[key] = enriched;
              recordsToUpsertMap[key] = enriched;
            }
          }
        } else {
          final finalPbb = parsedPbbVal > 0
              ? cleanNominalRupiah(parsedPbbVal)
              : (priorPbb.isNotEmpty
                    ? cleanNominalRupiah(priorPbb)
                    : cleanNominalRupiah(parsed.jumlahPbb));

          final newRecord = BlokRecord(
            nop: parsed.nop,
            namaWajibPajak: parsed.namaWp.isNotEmpty
                ? parsed.namaWp
                : 'WP Baru (Bapenda)',
            tahunBayar: rowTahun,
            tanggalBayar: parsed.tanggalBayar,
            jumlahPbb: finalPbb,
            statusBayar: 'Sudah Bayar',
            alamatObjek: parsed.alamatOp.isNotEmpty
                ? parsed.alamatOp
                : 'Kp. Terdata Server',
            alamatWp: parsed.alamatWp,
            rtObjek: parsed.rtOp,
            kecamatan: effKecName,
            kelurahan: effDesaName,
            luasBumi: parsed.luasBumi,
            njopBumi: parsed.njopBumi,
            luasBangunan: parsed.luasBangunan,
            njopBangunan: parsed.njopBangunan,
            isTargetPemda: parsedPbbVal >= 2000000,
            catatan: 'SPPT Baru terdeteksi dari Portal Petugas',
          );
          keyToExisting[key] = newRecord;
          recordsToUpsertMap[key] = newRecord;
          newSpptCount++;
          newNops.add(parsed.nop);
          newRecords.add(newRecord);
        }
      }

      // 3. Simpan seluruh pembaruan sekaligus ke database lokal
      if (recordsToUpsertMap.isNotEmpty) {
        await BlokDataStore.instance.upsertAll(
          recordsToUpsertMap.values.toList(),
        );
        DhkpWidgetSyncService.syncFromRecords(
          await BlokDataStore.instance.loadAll(),
        );
      }

      // 4. Kirim notifikasi selesai (Android & Desktop)
      await BatchNotificationService.instance.showStaffSyncCompleted(
        updatedPaidCount: updatedPaidCount,
        newSpptCount: newSpptCount,
        totalChecked: totalCheckedRows,
        blokLabel: blokSummaryLabel,
      );

      final outcome = StaffDhkpSyncOutcome(
        blokLabel: blokSummaryLabel,
        tahun: tahun,
        totalCheckedRows: totalCheckedRows,
        updatedPaidCount: updatedPaidCount,
        newSpptCount: newSpptCount,
        alreadyPaidCount: alreadyPaidCount,
        updatedNops: updatedNops,
        newNops: newNops,
        updatedRecords: updatedRecords,
        newRecords: newRecords,
      );
      lastOutcome = outcome;
      return outcome;
    } catch (e, stack) {
      debugPrint('Error syncBloks StaffDhkpSyncService: $e\n$stack');
      await BatchNotificationService.instance.stopForegroundService();
      final errOutcome = StaffDhkpSyncOutcome(
        blokLabel: blokSummaryLabel,
        tahun: tahun,
        totalCheckedRows: totalCheckedRows,
        updatedPaidCount: updatedPaidCount,
        newSpptCount: newSpptCount,
        alreadyPaidCount: alreadyPaidCount,
        updatedNops: updatedNops,
        newNops: newNops,
        updatedRecords: updatedRecords,
        newRecords: newRecords,
        errorMessage: friendlyErrorMessage(
          e,
          fallback: 'Gagal menyinkronkan data DHKP. Silakan coba lagi.',
        ),
      );
      lastOutcome = errOutcome;
      return errOutcome;
    }
  }
}

