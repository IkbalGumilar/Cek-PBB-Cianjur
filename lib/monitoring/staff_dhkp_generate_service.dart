import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_storage.dart';
import '../blok_data_store.dart';
import '../blok_record.dart';
import '../dhkp_widget_sync_service.dart';
import '../dusun_data.dart';
import '../nop_helper.dart';
import '../staff_portal_client.dart';
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
    this.errorMessage,
    this.isCancelled = false,
  });
}

/// Layanan penarikan seluruh data SPPT desa dari Portal Staf untuk
/// menghasilkan (Generate) master DHKP baru dan langsung menimpa database lokal.
class StaffDhkpGenerateService {
  StaffDhkpGenerateService._();
  static final instance = StaffDhkpGenerateService._();

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
    Duration pacingDelay = const Duration(milliseconds: 500),
    int maxPages = 2000,
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

    try {
      final effKel = kelurahanCode.isNotEmpty
          ? kelurahanCode
          : client.activeKelurahanCode;
      final effKec = kecamatanCode.isNotEmpty
          ? kecamatanCode
          : client.activeKecamatanCode;

      final allowedBlocks = <String>{};
      for (final d in dusuns) {
        for (final b in d.bloks) {
          final cb = b.padLeft(3, '0');
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
            desaName: desaName,
            isCancelled: true,
          );
        }

        pageBb = page;
        notify('Memuat Belum Bayar (Halaman $page)...');

        final tableResult = await client.fetchBelumBayar(
          tglCutoff: effectiveCutoff,
          tahunAwal: effTahunAwal,
          tahunAkhir: effTahunAkhir,
          bukuMin: bukuMin,
          bukuMax: bukuMax,
          kelurahan: effKel,
          kecamatan: effKec,
          page: page,
        );

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

        notify('Belum Bayar: Hal $page dari $estimatedTotalPagesBb (${bbRows.length} SPPT)...');

        if (tableResult.hasNextPage && page < maxPages) {
          page++;
          if (pacingDelay > Duration.zero) {
            await Future.delayed(pacingDelay);
          }
        } else {
          hasMoreBb = false;
        }
      }

      // 2. UNDUH SELURUH SUDAH BAYAR (SB) DARI SERVER BAPENDA
      page = 1;
      bool hasMoreSb = true;
      String? sbError;
      final tglAwal = '$effTahunAwal-01-01';
      final tglAkhir = '$effTahunAkhir-12-31';

      while (hasMoreSb) {
        if (shouldCancel?.call() ?? false) {
          return StaffDhkpGenerateOutcome(
            success: false,
            tahun: effTahunLabel,
            desaName: desaName,
            isCancelled: true,
          );
        }

        pageSb = page;
        notify('Memuat Sudah Bayar (Halaman $page)...');

        final tableResult = await client.fetchSudahBayar(
          tglBayarAwal: tglAwal,
          tglBayarAkhir: tglAkhir,
          tahunAwal: effTahunAwal,
          tahunAkhir: effTahunAkhir,
          bukuMin: bukuMin,
          bukuMax: bukuMax,
          kelurahan: effKel,
          kecamatan: effKec,
          page: page,
        );

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

        notify('Sudah Bayar: Hal $page dari $estimatedTotalPagesSb (${sbRows.length} SPPT)...');

        if (tableResult.hasNextPage && page < maxPages) {
          page++;
          if (pacingDelay > Duration.zero) {
            await Future.delayed(pacingDelay);
          }
        } else {
          hasMoreSb = false;
        }
      }

      if (bbRows.isEmpty && sbRows.isEmpty) {
        final err = bbError ?? sbError ?? 'Tidak ada data SPPT yang ditemukan untuk tahun $effTahunLabel di portal staf.';
        return StaffDhkpGenerateOutcome(
          success: false,
          tahun: effTahunLabel,
          desaName: desaName,
          errorMessage: err,
        );
      }

      notify('Menyusun struktur data DHKP master baru...');

      // 3. BANGUN RECORD DHKP
      final recordsMap = <String, BlokRecord>{};

      // Proses Belum Bayar
      for (final parsed in bbRows) {
        final rowTahun = parsed.tahun.isNotEmpty
            ? parsed.tahun
            : (effTahunAwal == effTahunAkhir ? effTahunAwal : effTahunAkhir);
        final key = '${parsed.nop}|$rowTahun';
        final pokokVal = parseNominalRupiah(parsed.jumlahPbb);
        final isTp = pokokVal >= targetPemdaThreshold;
        final isZeroNominal = pokokVal == 0;
        final cleanNominal = pokokVal > 0 ? cleanNominalRupiah(pokokVal) : 'Rp 0';

        recordsMap[key] = BlokRecord(
          nop: parsed.nop,
          namaWajibPajak: parsed.namaWp.isNotEmpty
              ? parsed.namaWp
              : 'WP ${nopBlok(parsed.nop)}/${nopWilayah(parsed.nop)}',
          tahunBayar: rowTahun,
          tanggalBayar: '',
          jumlahPbb: cleanNominal,
          statusBayar: isZeroNominal ? 'Sudah Bayar' : 'Belum Bayar',
          alamatObjek: parsed.alamatOp.isNotEmpty ? parsed.alamatOp : 'Kp. Terdata Server',
          alamatWp: parsed.alamatWp,
          rtObjek: parsed.rtOp,
          luasBumi: parsed.luasBumi,
          njopBumi: parsed.njopBumi,
          luasBangunan: parsed.luasBangunan,
          njopBangunan: parsed.njopBangunan,
          isTargetPemda: isTp,
          catatan: isZeroNominal ? 'Sudah bayar (Ketetapan Rp 0 / Nihil)' : '',
        );
      }

      // Proses Sudah Bayar (timpa/tambahkan ke map)
      for (final parsed in sbRows) {
        final rowTahun = parsed.tahun.isNotEmpty
            ? parsed.tahun
            : (effTahunAwal == effTahunAkhir ? effTahunAwal : effTahunAkhir);
        final key = '${parsed.nop}|$rowTahun';
        final pokokVal = parseNominalRupiah(parsed.jumlahPbb);
        final isTp = pokokVal >= targetPemdaThreshold;
        final cleanNominal = pokokVal > 0 ? cleanNominalRupiah(pokokVal) : (parsed.jumlahPbb.isNotEmpty ? cleanNominalRupiah(parsed.jumlahPbb) : '-');
        final existing = recordsMap[key];
        final effTgl = parsed.tanggalBayar.isNotEmpty ? parsed.tanggalBayar : (existing?.tanggalBayar ?? '');
        final catatanBayar = formatCatatanSudahBayar(effTgl, rowTahun);

        if (existing != null) {
          recordsMap[key] = existing.copyWith(
            statusBayar: 'Sudah Bayar',
            tanggalBayar: effTgl,
            jumlahPbb: cleanNominal,
            namaWajibPajak: parsed.namaWp.isNotEmpty ? parsed.namaWp : existing.namaWajibPajak,
            alamatObjek: parsed.alamatOp.isNotEmpty ? parsed.alamatOp : existing.alamatObjek,
            alamatWp: parsed.alamatWp.isNotEmpty ? parsed.alamatWp : existing.alamatWp,
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
            alamatObjek: parsed.alamatOp.isNotEmpty ? parsed.alamatOp : 'Kp. Terdata Server',
            alamatWp: parsed.alamatWp,
            rtObjek: parsed.rtOp,
            luasBumi: parsed.luasBumi,
            njopBumi: parsed.njopBumi,
            luasBangunan: parsed.luasBangunan,
            njopBangunan: parsed.njopBangunan,
            isTargetPemda: isTp,
            catatan: catatanBayar,
          );
        }
      }

      notify('Mencadangkan data lama dan menerapkan data baru ke aplikasi...');

      // 4. CADANGKAN DATABASE LAMA TERLEBIH DAHULU (PENGAMAN)
      try {
        final currentFile = await AppStorage.getDatabaseFile();
        if (await currentFile.exists()) {
          final backupDir = await AppStorage.getBackupsDirectory();
          final ts = DateTime.now().millisecondsSinceEpoch;
          await currentFile.copy('${backupDir.path}/cadangan_sebelum_generate_$ts.csv');
        }
      } catch (e) {
        debugPrint('Warning: gagal membuat file cadangan sebelum timpa DHKP: $e');
      }

      // 5. TIMPA DATABASE LOKAL DENGAN DATA BARU
      final recordList = recordsMap.values.toList();
      await BlokDataStore.instance.clearAll();
      await BlokDataStore.instance.upsertAll(recordList);

      // 6. SIMPAN PEMBAGIAN DUSUN & KOORDINAT
      if (dusuns.isNotEmpty) {
        await DusunData.instance.setDusuns(dusuns);
      }
      if (kantorDesaLat != null && kantorDesaLng != null) {
        await DusunData.instance.setKantorDesaLocation(kantorDesaLat, kantorDesaLng);
      }

      // Sinkronisasi widget
      DhkpWidgetSyncService.syncFromRecords(recordList);

      // Hitung ringkasan
      final totalRecords = recordList.length;
      final paidCount = recordList.where((r) => r.isPaid && !r.isTargetPemda).length;
      final unpaidCount = recordList.where((r) => !r.isPaid && !r.isTargetPemda).length;
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
        desaName: desaName,
      );
    } catch (e, stack) {
      debugPrint('Error generateAndApply: $e\n$stack');
      return StaffDhkpGenerateOutcome(
        success: false,
        tahun: effTahunLabel,
        desaName: desaName,
        errorMessage: 'Terjadi kesalahan saat generate DHKP: $e',
      );
    }
  }
}
