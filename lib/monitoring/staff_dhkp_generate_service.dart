import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_storage.dart';
import '../blok_data_store.dart';
import '../blok_record.dart';
import '../cianjur_wilayah_data.dart';
import '../dhkp_widget_sync_service.dart';
import '../dkhp_package_helper.dart';
import '../dusun_data.dart';
import '../nop_helper.dart';
import '../staff_portal_client.dart';
import '../user_friendly_error.dart';
import 'staff_dhkp_sync_service.dart' show ParsedStaffRow, StaffDhkpSyncService;

/// Progres proses pembuatan (Generate) data DHKP
class StaffDhkpGenerateProgress {
  final int currentPage;
  final int estimatedTotalPages;
  final int checkedRecords;
  final int belumBayarCount;
  final int sudahBayarCount;
  final String currentStatus;

  const StaffDhkpGenerateProgress({
    required this.currentPage,
    required this.estimatedTotalPages,
    required this.checkedRecords,
    required this.belumBayarCount,
    required this.sudahBayarCount,
    required this.currentStatus,
  });

  double get ratio => estimatedTotalPages > 0
      ? (currentPage / estimatedTotalPages).clamp(0.0, 1.0)
      : 0.0;
}

/// Hasil akhir pembuatan (Generate) data DHKP
class StaffDhkpGenerateOutcome {
  final bool success;
  final int totalRecords;
  final int belumBayarCount;
  final int sudahBayarCount;
  final int targetPemdaCount;
  final int totalBloks;
  final String tahun;
  final String desaName;
  final String kecamatanName;
  final String kecamatanCode;
  final String kelurahanCode;
  final SplitDkhpExportResult? splitExportResult;
  final File? generatedMasterFile;
  final String? errorMessage;
  final bool isCancelled;

  const StaffDhkpGenerateOutcome({
    required this.success,
    this.totalRecords = 0,
    this.belumBayarCount = 0,
    this.sudahBayarCount = 0,
    this.targetPemdaCount = 0,
    this.totalBloks = 0,
    required this.tahun,
    required this.desaName,
    this.kecamatanName = '',
    this.kecamatanCode = '',
    this.kelurahanCode = '',
    this.splitExportResult,
    this.generatedMasterFile,
    this.errorMessage,
    this.isCancelled = false,
  });
}

/// Layanan penarikan seluruh data SPPT desa dari Portal Staf untuk
/// menghasilkan (Generate) paket berkas `.dkhp` terenkripsi.
/// Secara bawaan TIDAK menghapus/menimpa database lokal sebelum pengguna
/// memasang berkas `.dkhp` yang dihasilkan.
class StaffDhkpGenerateService {
  StaffDhkpGenerateService._();
  static final instance = StaffDhkpGenerateService._();

  /// Menormalisasi kode kecamatan & kode desa/kelurahan dari input form, manifest,
  /// katalog wilayah Cianjur, maupun sesi login Portal Staf (Bapenda / Kecamatan / Desa).
  static ({
    String kecCode3,
    String kelCode3,
    String vtaxKecCode,
    String vtaxKelCode,
    String kecName,
    String desaName,
  })
  resolveWilayahParameters({
    required String kelurahanCode,
    required String kecamatanCode,
    required String desaName,
    required String kecamatanName,
    String clientKelurahanCode = '',
    String clientKecamatanCode = '',
  }) {
    final cleanDesaInput = desaName.trim().toUpperCase();
    final cleanKecInput = kecamatanName.trim().toUpperCase();

    var kec3 = extractKecamatanCode3(kecamatanCode);
    var kel3 = extractKelurahanCode3(kelurahanCode);

    // Cari dari katalog resmi Kabupaten Cianjur berdasarkan nama desa & kecamatan bila ada
    final catalogByName = findWilayahByName(
      desaName: cleanDesaInput,
      kecamatanName: cleanKecInput,
      kecamatanCode: kec3,
    );

    if (catalogByName != null) {
      final (catKec, catDesa) = catalogByName;
      // Jika kode belum diisi atau masih memakai kode sesi default yang berbeda dari nama desa yang diketik
      final clientKel3 = extractKelurahanCode3(clientKelurahanCode);
      final clientKec3 = extractKecamatanCode3(clientKecamatanCode);
      if (kec3.isEmpty ||
          (kec3 == clientKec3 &&
              cleanKecInput.isNotEmpty &&
              catKec.name.toUpperCase() == cleanKecInput)) {
        kec3 = catKec.code;
      }
      if (kel3.isEmpty ||
          (kel3 == clientKel3 &&
              cleanDesaInput.isNotEmpty &&
              catDesa.name.toUpperCase() == cleanDesaInput)) {
        kel3 = catDesa.code;
      }
    }

    if (kec3.isEmpty) {
      final byKecName = findKecamatanByName(cleanKecInput);
      if (byKecName != null) {
        kec3 = byKecName.code;
      }
    }

    if (kec3.isEmpty) {
      kec3 = extractKecamatanCode3(clientKecamatanCode);
    }
    if (kel3.isEmpty) {
      kel3 = extractKelurahanCode3(clientKelurahanCode);
    }
    if (kec3.isEmpty) {
      kec3 = activeKecamatanCode.isNotEmpty ? activeKecamatanCode : '200';
    }
    if (kel3.isEmpty) {
      kel3 = activeKelurahanCode.isNotEmpty ? activeKelurahanCode : '004';
    }

    final resolvedKecName = cleanKecInput.isNotEmpty
        ? cleanKecInput
        : lookupKecamatanName(kec3);
    final resolvedDesaName = cleanDesaInput.isNotEmpty
        ? cleanDesaInput
        : lookupKelurahanName(kel3, kecamatanCode: kec3);

    final vtaxKec = toVtaxKecamatanCode(kec3);
    final vtaxKel = toVtaxKelurahanCode(kelCode: kel3, kecCode: kec3);

    return (
      kecCode3: kec3,
      kelCode3: kel3,
      vtaxKecCode: vtaxKec,
      vtaxKelCode: vtaxKel,
      kecName: resolvedKecName,
      desaName: resolvedDesaName,
    );
  }

  Future<({MonitoringTableResult result, Duration elapsed})> _fetchPageWithRetry({
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
          errorMessage:
              'Gangguan koneksi pada halaman $page: ${friendlyErrorMessage(e)}',
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

  Future<StaffDhkpGenerateOutcome> generateAndApply({
    required StaffPortalClient client,
    String? tahun,
    String? tahunAwal,
    String? tahunAkhir,
    required String kelurahanCode,
    required String kecamatanCode,
    required String desaName,
    required String kecamatanName,
    required List<Dusun> dusuns,
    bool filterByDusunBlocks = true,
    double? kantorDesaLat,
    double? kantorDesaLng,
    int targetPemdaThreshold = 2000000,
    String bukuMin = '',
    String bukuMax = '',
    void Function(StaffDhkpGenerateProgress)? onProgress,
    bool Function()? shouldCancel,
    Duration pacingDelay = const Duration(milliseconds: 550),
    Duration retryBaseDelay = const Duration(milliseconds: 1500),
    int maxRetriesPerPage = 3,
    int maxPages = 2000,
    bool exportSplitByDusun = false,
    bool includeMasterInSplit = true,
    Directory? splitOutputDirectory,
    String? encryptionPassword,
    bool applyToLocalDb = false,
  }) async {
    final effTahunAwal = (tahunAwal != null && tahunAwal.isNotEmpty)
        ? tahunAwal
        : (tahun ?? '${DateTime.now().year}');
    final effTahunAkhir = (tahunAkhir != null && tahunAkhir.isNotEmpty)
        ? tahunAkhir
        : (tahun ?? '${DateTime.now().year}');
    final effTahunLabel = effTahunAwal == effTahunAkhir
        ? effTahunAwal
        : '$effTahunAwal s/d $effTahunAkhir';

    final resolvedWilayah = resolveWilayahParameters(
      kelurahanCode: kelurahanCode,
      kecamatanCode: kecamatanCode,
      desaName: desaName,
      kecamatanName: kecamatanName,
      clientKelurahanCode: client.activeKelurahanCode,
      clientKecamatanCode: client.activeKecamatanCode,
    );

    final trimmedEncryptionPassword = encryptionPassword?.trim();
    final effectiveEncryptionPassword =
        (trimmedEncryptionPassword != null &&
            trimmedEncryptionPassword.isNotEmpty)
        ? trimmedEncryptionPassword
        : null;
    if (effectiveEncryptionPassword != null) {
      final passwordError = DhkpCrypto.validateOptionalPassword(
        effectiveEncryptionPassword,
      );
      if (passwordError != null) {
        return StaffDhkpGenerateOutcome(
          success: false,
          tahun: effTahunLabel,
          desaName: resolvedWilayah.desaName,
          kecamatanName: resolvedWilayah.kecName,
          kecamatanCode: resolvedWilayah.kecCode3,
          kelurahanCode: resolvedWilayah.kelCode3,
          errorMessage: passwordError,
        );
      }
    }

    try {
      final effKel = resolvedWilayah.vtaxKelCode;
      final effKec = resolvedWilayah.vtaxKecCode;

      final allowedBlocks = <String>{};
      for (final d in dusuns) {
        for (final b in d.bloks) {
          final cb = b.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
          if (cb.isNotEmpty) allowedBlocks.add(cb);
        }
      }

      final bbRows = <ParsedStaffRow>[];
      final sbRows = <ParsedStaffRow>[];

      int pageBb = 0;
      int estimatedTotalPagesBb = 1;
      int pageSb = 0;
      int estimatedTotalPagesSb = 1;

      void notify(String status) {
        final totalEstPages = estimatedTotalPagesBb + estimatedTotalPagesSb;
        final currentTotalPage = pageBb + pageSb;
        onProgress?.call(
          StaffDhkpGenerateProgress(
            currentPage: currentTotalPage,
            estimatedTotalPages: totalEstPages,
            checkedRecords: bbRows.length + sbRows.length,
            belumBayarCount: bbRows.length,
            sudahBayarCount: sbRows.length,
            currentStatus: status,
          ),
        );
      }

      // 1. UNDUH SELURUH BELUM BAYAR (BB) DARI SERVER BAPENDA
      int page = 1;
      bool hasMoreBb = true;
      String? bbError;
      final now = DateTime.now();
      final effectiveCutoff =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      while (hasMoreBb) {
        if (shouldCancel?.call() ?? false) {
          return StaffDhkpGenerateOutcome(
            success: false,
            tahun: effTahunLabel,
            desaName: resolvedWilayah.desaName,
            kecamatanName: resolvedWilayah.kecName,
            kecamatanCode: resolvedWilayah.kecCode3,
            kelurahanCode: resolvedWilayah.kelCode3,
            isCancelled: true,
          );
        }

        pageBb = page;
        notify('Memuat Belum Bayar (Halaman $page)...');

        final fetched = await _fetchPageWithRetry(
          fetcher: () => client.fetchBelumBayar(
            tglCutoff: effectiveCutoff,
            tahunAwal: effTahunAwal,
            tahunAkhir: effTahunAkhir,
            bukuMin: bukuMin,
            bukuMax: bukuMax,
            kelurahan: effKel,
            kecamatan: effKec,
            page: page,
          ),
          label: 'Belum Bayar',
          page: page,
          maxRetries: maxRetriesPerPage,
          retryBaseDelay: retryBaseDelay,
          notify: notify,
          shouldCancel: shouldCancel,
        );
        final tableResult = fetched.result;

        if (tableResult.errorMessage != null && tableResult.rows.isEmpty) {
          bbError = tableResult.errorMessage;
          break;
        }

        if (tableResult.rows.isEmpty) break;

        if (tableResult.totalRecords > 0) {
          estimatedTotalPagesBb = (tableResult.totalRecords / 50).ceil();
          if (estimatedTotalPagesBb < 1) estimatedTotalPagesBb = 1;
        }

        final headers = tableResult.headers;
        for (final row in tableResult.rows) {
          final parsed = StaffDhkpSyncService.parseRow(
            row,
            headers,
            defaultTahun: effTahunAwal == effTahunAkhir ? effTahunAwal : null,
          );
          if (parsed != null) {
            if (filterByDusunBlocks && allowedBlocks.isNotEmpty) {
              final blok = nopBlok(parsed.nop);
              if (!allowedBlocks.contains(blok)) continue;
            }
            bbRows.add(parsed);
          }
        }

        notify(
          'Belum Bayar: Hal $page dari $estimatedTotalPagesBb (${bbRows.length} SPPT)...',
        );

        if (tableResult.hasNextPage && page < maxPages) {
          page++;
          // Pacing adaptif agar server V-Tax Bapenda tidak mengalami overload / crash
          var adaptiveDelay = pacingDelay;
          if (pacingDelay > Duration.zero &&
              fetched.elapsed.inMilliseconds > 2000) {
            adaptiveDelay += const Duration(milliseconds: 650);
          }
          if (adaptiveDelay > Duration.zero) {
            await Future.delayed(adaptiveDelay);
          }
        } else {
          hasMoreBb = false;
        }
      }

      if (bbError != null) {
        return StaffDhkpGenerateOutcome(
          success: false,
          tahun: effTahunLabel,
          desaName: resolvedWilayah.desaName,
          kecamatanName: resolvedWilayah.kecName,
          kecamatanCode: resolvedWilayah.kecCode3,
          kelurahanCode: resolvedWilayah.kelCode3,
          errorMessage:
              'Pengunduhan Belum Bayar terhenti pada halaman $pageBb ($bbError). Data lokal tidak ditimpa demi menjaga keutuhan data.',
        );
      }

      // 2. UNDUH SELURUH SUDAH BAYAR (SB) DARI SERVER BAPENDA
      page = 1;
      bool hasMoreSb = true;
      String? sbError;
      final tglAwal = '$effTahunAwal-01-01';
      final endOfTargetYear = '$effTahunAkhir-12-31';
      // Gunakan tanggal hari ini bila lebih baru dari akhir tahun pajak agar pembayaran
      // piutang/tunggakan lintas tahun tetap terambil 100%.
      final tglAkhir = effectiveCutoff.compareTo(endOfTargetYear) > 0
          ? effectiveCutoff
          : endOfTargetYear;

      while (hasMoreSb) {
        if (shouldCancel?.call() ?? false) {
          return StaffDhkpGenerateOutcome(
            success: false,
            tahun: effTahunLabel,
            desaName: resolvedWilayah.desaName,
            kecamatanName: resolvedWilayah.kecName,
            kecamatanCode: resolvedWilayah.kecCode3,
            kelurahanCode: resolvedWilayah.kelCode3,
            isCancelled: true,
          );
        }

        pageSb = page;
        notify('Memuat Sudah Bayar (Halaman $page)...');

        final fetched = await _fetchPageWithRetry(
          fetcher: () => client.fetchSudahBayar(
            tglBayarAwal: tglAwal,
            tglBayarAkhir: tglAkhir,
            tahunAwal: effTahunAwal,
            tahunAkhir: effTahunAkhir,
            bukuMin: bukuMin,
            bukuMax: bukuMax,
            kelurahan: effKel,
            kecamatan: effKec,
            page: page,
          ),
          label: 'Sudah Bayar',
          page: page,
          maxRetries: maxRetriesPerPage,
          retryBaseDelay: retryBaseDelay,
          notify: notify,
          shouldCancel: shouldCancel,
        );
        final tableResult = fetched.result;

        if (tableResult.errorMessage != null && tableResult.rows.isEmpty) {
          sbError = tableResult.errorMessage;
          break;
        }

        if (tableResult.rows.isEmpty) break;

        if (tableResult.totalRecords > 0) {
          estimatedTotalPagesSb = (tableResult.totalRecords / 50).ceil();
          if (estimatedTotalPagesSb < 1) estimatedTotalPagesSb = 1;
        }

        final headers = tableResult.headers;
        for (final row in tableResult.rows) {
          final parsed = StaffDhkpSyncService.parseRow(
            row,
            headers,
            defaultTahun: effTahunAwal == effTahunAkhir ? effTahunAwal : null,
          );
          if (parsed != null) {
            if (filterByDusunBlocks && allowedBlocks.isNotEmpty) {
              final blok = nopBlok(parsed.nop);
              if (!allowedBlocks.contains(blok)) continue;
            }
            sbRows.add(parsed);
          }
        }

        notify(
          'Sudah Bayar: Hal $page dari $estimatedTotalPagesSb (${sbRows.length} SPPT)...',
        );

        if (tableResult.hasNextPage && page < maxPages) {
          page++;
          var adaptiveDelay = pacingDelay;
          if (pacingDelay > Duration.zero &&
              fetched.elapsed.inMilliseconds > 2000) {
            adaptiveDelay += const Duration(milliseconds: 650);
          }
          if (adaptiveDelay > Duration.zero) {
            await Future.delayed(adaptiveDelay);
          }
        } else {
          hasMoreSb = false;
        }
      }

      if (sbError != null) {
        return StaffDhkpGenerateOutcome(
          success: false,
          tahun: effTahunLabel,
          desaName: resolvedWilayah.desaName,
          kecamatanName: resolvedWilayah.kecName,
          kecamatanCode: resolvedWilayah.kecCode3,
          kelurahanCode: resolvedWilayah.kelCode3,
          errorMessage:
              'Pengunduhan Sudah Bayar terhenti pada halaman $pageSb ($sbError). Data lokal tidak ditimpa demi menjaga keutuhan data.',
        );
      }

      if (bbRows.isEmpty && sbRows.isEmpty) {
        return StaffDhkpGenerateOutcome(
          success: false,
          tahun: effTahunLabel,
          desaName: resolvedWilayah.desaName,
          kecamatanName: resolvedWilayah.kecName,
          kecamatanCode: resolvedWilayah.kecCode3,
          kelurahanCode: resolvedWilayah.kelCode3,
          errorMessage:
              'Tidak ada data SPPT yang ditemukan untuk Desa ${resolvedWilayah.desaName} (${resolvedWilayah.vtaxKelCode}) tahun $effTahunLabel di portal staf.',
        );
      }

      notify('Menyusun struktur data DHKP master baru...');

      // Muat catatan/foto petugas lokal yang sudah ada agar tidak hilang bila NOP sama
      final previousRecords = await BlokDataStore.instance.loadAll();
      final previousByKey = <String, BlokRecord>{
        for (final r in previousRecords)
          '${r.nop.replaceAll(RegExp(r'[^0-9]'), '')}|${r.tahunBayar}': r,
      };

      // 3. BANGUN RECORD DHKP
      final recordsMap = <String, BlokRecord>{};

      // Proses Belum Bayar
      for (final parsed in bbRows) {
        final rowTahun = parsed.tahun.isNotEmpty
            ? parsed.tahun
            : (effTahunAwal == effTahunAkhir ? effTahunAwal : effTahunAkhir);
        final key = '${parsed.nop}|$rowTahun';
        final prev = previousByKey[key];
        final pokokVal = parseNominalRupiah(parsed.jumlahPbb);
        final isTp = pokokVal >= targetPemdaThreshold;
        final isZeroNominal = pokokVal == 0;
        final cleanNominal = pokokVal > 0
            ? cleanNominalRupiah(pokokVal)
            : 'Rp 0';

        recordsMap[key] = BlokRecord(
          nop: parsed.nop,
          namaWajibPajak: parsed.namaWp.isNotEmpty
              ? parsed.namaWp
              : 'WP ${nopBlok(parsed.nop)}/${nopWilayah(parsed.nop)}',
          tahunBayar: rowTahun,
          tanggalBayar: '',
          jumlahPbb: cleanNominal,
          statusBayar: isZeroNominal
              ? 'Sudah Bayar'
              : ((prev != null && (prev.isBermasalah || prev.isBlacklist))
                    ? prev.statusBayar
                    : 'Belum Bayar'),
          alamatObjek: parsed.alamatOp.isNotEmpty
              ? parsed.alamatOp
              : 'Kp. Terdata Server',
          alamatWp: parsed.alamatWp,
          rtObjek: parsed.rtOp,
          kecamatan: resolvedWilayah.kecName,
          kelurahan: resolvedWilayah.desaName,
          luasBumi: parsed.luasBumi,
          njopBumi: parsed.njopBumi,
          luasBangunan: parsed.luasBangunan,
          njopBangunan: parsed.njopBangunan,
          isTargetPemda: isTp,
          namaFoto: prev?.namaFoto,
          catatan: isZeroNominal
              ? 'Sudah bayar (Ketetapan Rp 0 / Nihil)'
              : (prev != null &&
                        prev.catatan.isNotEmpty &&
                        !prev.catatan.startsWith('Sudah bayar tanggal'))
              ? prev.catatan
              : '',
        );
      }

      // Proses Sudah Bayar (timpa/tambahkan ke map)
      for (final parsed in sbRows) {
        final rowTahun = parsed.tahun.isNotEmpty
            ? parsed.tahun
            : (effTahunAwal == effTahunAkhir ? effTahunAwal : effTahunAkhir);
        final key = '${parsed.nop}|$rowTahun';
        final prev = previousByKey[key];
        final pokokVal = parseNominalRupiah(parsed.jumlahPbb);
        final isTp = pokokVal >= targetPemdaThreshold;
        final cleanNominal = pokokVal > 0
            ? cleanNominalRupiah(pokokVal)
            : (parsed.jumlahPbb.isNotEmpty
                  ? cleanNominalRupiah(parsed.jumlahPbb)
                  : '-');
        final existing = recordsMap[key];
        final effTgl = parsed.tanggalBayar.isNotEmpty
            ? parsed.tanggalBayar
            : (existing?.tanggalBayar ?? '');
        final catatanBayar = formatCatatanSudahBayar(effTgl, rowTahun);

        if (existing != null) {
          recordsMap[key] = existing.copyWith(
            statusBayar: 'Sudah Bayar',
            tanggalBayar: effTgl,
            jumlahPbb: cleanNominal,
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
            kecamatan: resolvedWilayah.kecName,
            kelurahan: resolvedWilayah.desaName,
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
            isTargetPemda: isTp,
            catatan: catatanBayar,
          );
        } else {
          recordsMap[key] = BlokRecord(
            nop: parsed.nop,
            namaWajibPajak: parsed.namaWp.isNotEmpty
                ? parsed.namaWp
                : 'WP ${nopBlok(parsed.nop)}/${nopWilayah(parsed.nop)}',
            tahunBayar: rowTahun,
            tanggalBayar: parsed.tanggalBayar,
            jumlahPbb: cleanNominal,
            statusBayar: 'Sudah Bayar',
            alamatObjek: parsed.alamatOp.isNotEmpty
                ? parsed.alamatOp
                : 'Kp. Terdata Server',
            alamatWp: parsed.alamatWp,
            rtObjek: parsed.rtOp,
            kecamatan: resolvedWilayah.kecName,
            kelurahan: resolvedWilayah.desaName,
            luasBumi: parsed.luasBumi,
            njopBumi: parsed.njopBumi,
            luasBangunan: parsed.luasBangunan,
            njopBangunan: parsed.njopBangunan,
            isTargetPemda: isTp,
            namaFoto: prev?.namaFoto,
            catatan: catatanBayar,
          );
        }
      }

      final recordList = recordsMap.values.toList();
      final targetDir =
          splitOutputDirectory ?? await AppStorage.getBackupsDirectory();
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // 4. EKSPOR PAKET .DKHP TERENKRIPSI (TIDAK MENGHAPUS/MENIMPA DB LOKAL)
      SplitDkhpExportResult? splitResult;
      File? generatedMasterFile;

      if (exportSplitByDusun && dusuns.isNotEmpty) {
        notify(
          'Mengenkripsi & memecah paket .dkhp untuk ${dusuns.length} Kedusunan...',
        );
        splitResult = await DhkpPackageHelper.packSplitDkhpByDusun(
          outputDirectory: targetDir,
          records: recordList,
          dusuns: dusuns,
          kecamatanCode: resolvedWilayah.kecCode3,
          kecamatanName: resolvedWilayah.kecName,
          kelurahanCode: resolvedWilayah.kelCode3,
          desaName: resolvedWilayah.desaName,
          kantorDesaLat: kantorDesaLat,
          kantorDesaLng: kantorDesaLng,
          tahunPajak: effTahunAkhir,
          password: effectiveEncryptionPassword,
          includeMasterDesa: includeMasterInSplit,
        );
        generatedMasterFile = splitResult.masterEntry?.file;
      }

      if (generatedMasterFile == null) {
        notify('Mengemas berkas paket Master .dkhp terenkripsi...');
        final safeDesa = resolvedWilayah.desaName
            .trim()
            .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
        final safeTahun = effTahunAkhir.replaceAll(
          RegExp(r'[^a-zA-Z0-9_\-]+'),
          '_',
        );
        final masterPath =
            '${targetDir.path}${Platform.pathSeparator}DHKP_MASTER_${safeDesa.isEmpty ? "DESA" : safeDesa}_$safeTahun.dkhp';
        generatedMasterFile = await DhkpPackageHelper.packDkhp(
          outputPath: masterPath,
          records: recordList,
          baseRecords: recordList,
          deltaOnly: false,
          includePhotos: true,
          encrypt: true,
          password: effectiveEncryptionPassword,
          dusuns: dusuns,
          scope: const DusunScope(role: 'desa'),
          kecamatanCode: resolvedWilayah.kecCode3,
          kecamatanName: resolvedWilayah.kecName,
          kelurahanCode: resolvedWilayah.kelCode3,
          desaName: resolvedWilayah.desaName,
          kantorDesaLat: kantorDesaLat,
          kantorDesaLng: kantorDesaLng,
          tahunPajak: effTahunAkhir,
        );
      }

      // 5. OPSIONAL: TERAPKAN KE DATABASE LOKAL HANYA JIKA DIMINTA SECARA EKSPLISIT
      // Proses generate standar TIDAK menghapus/menimpa data lokal sebelum pengguna
      // memasang file `.dkhp` yang dihasilkan.
      if (applyToLocalDb) {
        notify('Mencadangkan data lama dan menerapkan data baru ke aplikasi...');
        try {
          final currentFile = await AppStorage.getDatabaseFile();
          if (await currentFile.exists()) {
            final backupDir = await AppStorage.getBackupsDirectory();
            final ts = DateTime.now().millisecondsSinceEpoch;
            await currentFile.copy(
              '${backupDir.path}/cadangan_sebelum_generate_$ts.csv',
            );
          }
        } catch (e) {
          debugPrint(
            'Warning: gagal membuat file cadangan sebelum menerapkan DHKP: $e',
          );
        }

        final incomingYears = recordList
            .map((r) => r.tahunBayar.trim())
            .where((y) => y.isNotEmpty)
            .toSet();
        await BlokDataStore.instance.replaceByYears(
          targetYears: incomingYears,
          newRecords: recordList,
        );

        await saveActiveWilayah(
          kecCode: resolvedWilayah.kecCode3,
          kelCode: resolvedWilayah.kelCode3,
          desaName: resolvedWilayah.desaName,
          kecName: resolvedWilayah.kecName,
        );
        await DusunData.instance.clearScope();
        if (dusuns.isNotEmpty) {
          await DusunData.instance.setDusuns(dusuns);
        }
        if (kantorDesaLat != null && kantorDesaLng != null) {
          await DusunData.instance.setKantorDesaLocation(
            kantorDesaLat,
            kantorDesaLng,
          );
        }

        DhkpWidgetSyncService.syncFromRecords(
          await BlokDataStore.instance.loadAll(),
        );
      }

      // Hitung ringkasan
      final totalRecords = recordList.length;
      final paidCount = recordList
          .where((r) => r.isPaid && !r.isTargetPemda)
          .length;
      final unpaidCount = recordList
          .where((r) => !r.isPaid && !r.isTargetPemda)
          .length;
      final tpCount = recordList.where((r) => r.isTargetPemda).length;
      final totalBloks = recordList.map((r) => r.blok).toSet().length;

      return StaffDhkpGenerateOutcome(
        success: true,
        totalRecords: totalRecords,
        belumBayarCount: unpaidCount,
        sudahBayarCount: paidCount,
        targetPemdaCount: tpCount,
        totalBloks: totalBloks,
        tahun: effTahunLabel,
        desaName: resolvedWilayah.desaName,
        kecamatanName: resolvedWilayah.kecName,
        kecamatanCode: resolvedWilayah.kecCode3,
        kelurahanCode: resolvedWilayah.kelCode3,
        splitExportResult: splitResult,
        generatedMasterFile: generatedMasterFile,
      );
    } catch (e, stack) {
      debugPrint('Error generateAndApply: $e\n$stack');
      return StaffDhkpGenerateOutcome(
        success: false,
        tahun: effTahunLabel,
        desaName: resolvedWilayah.desaName,
        kecamatanName: resolvedWilayah.kecName,
        kecamatanCode: resolvedWilayah.kecCode3,
        kelurahanCode: resolvedWilayah.kelCode3,
        errorMessage: friendlyErrorMessage(
          e,
          fallback: 'Gagal membuat paket DHKP. Silakan coba lagi.',
        ),
      );
    }
  }
}

