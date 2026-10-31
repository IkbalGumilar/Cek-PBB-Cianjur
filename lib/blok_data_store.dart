import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'app_storage.dart';
import 'backup_crypto.dart';
import 'blok_backup_scheduler.dart';
import 'blok_record.dart';
import 'dhkp/blok_csv_codec.dart';
import 'dhkp_widget_sync_service.dart';
import 'dkhp_package_helper.dart';
import 'download_helper.dart';
import 'pbb_client.dart';

const _backupExtension = '.dkhp';

/// Penyimpanan lokal "Buku Catatan Blok" — daftar NOP yang sudah terkonfirmasi
/// "Sudah Bayar", dikelompokkan per blok. Data disimpan sebagai CSV di
/// direktori dokumen aplikasi, bukan di server, jadi hilang kalau aplikasi
/// di-uninstall kecuali sudah di-ekspor (backup) lebih dulu.
class BlokDataStore {
  BlokDataStore._();
  static final instance = BlokDataStore._();

  List<BlokRecord>? _cache;

  /// Notifier jumlah total catatan agar UI (seperti badge tombol Buku Catatan)
  /// dapat merespons secara reaktif tanpa perlu I/O disk ulang.
  final countNotifier = ValueNotifier<int>(0);

  Future<File> _dataFile() async {
    return AppStorage.getDatabaseFile();
  }

  void invalidateCache() {
    _cache = null;
  }

  @visibleForTesting
  void resetForTesting() {
    _cache = null;
    countNotifier.value = 0;
  }

  Future<List<BlokRecord>> loadAll() async {
    if (_cache != null) return _cache!;

    final file = await _dataFile();
    if (!file.existsSync()) {
      _cache = [];
      countNotifier.value = 0;
      return _cache!;
    }

    final content = file.readAsStringSync();
    _cache = BlokCsvCodec.decodeDatabaseCsv(content);
    countNotifier.value = _cache!.length;
    DhkpWidgetSyncService.syncFromRecords(_cache!);
    return _cache!;
  }

  Future<void> _persist(List<BlokRecord> records) async {
    final file = await _dataFile();
    file.writeAsStringSync(BlokCsvCodec.encodeRecords(records));
    _cache = records;
    countNotifier.value = records.length;
    DhkpWidgetSyncService.syncFromRecords(records);
  }

  /// Simpan/perbarui beberapa catatan sekaligus (upsert berdasar NOP+tahun).
  /// Menggunakan indexing Map O(N + M) untuk menghindari bottleneck scan O(N * M).
  Future<void> upsertAll(Iterable<BlokRecord> newRecords) async {
    if (newRecords.isEmpty) return;
    final records = List<BlokRecord>.from(await loadAll());
    final keyToIndex = <String, int>{};
    for (var i = 0; i < records.length; i++) {
      keyToIndex[records[i].uniqueKey] = i;
    }

    for (final record in newRecords) {
      final index = keyToIndex[record.uniqueKey];
      if (index == null) {
        keyToIndex[record.uniqueKey] = records.length;
        records.add(record);
      } else {
        records[index] = record;
      }
    }
    await _persist(records);
    await BlokBackupScheduler.instance.markDirty();
  }

  /// Simpan/perbarui satu catatan (upsert berdasar NOP+tahun).
  Future<void> upsert(BlokRecord record) => upsertAll([record]);

  /// Memperbarui data DHKP berdasarkan hasil Cek Status Bayar.
  /// Jika data NOP+tahun sudah ada (mis. awalnya "Belum Bayar"), statusnya akan
  /// diupdate ke "Sudah Bayar" dan tanggal bayar diisi, tanpa menghapus
  /// rincian objek pajak (luas tanah/bangunan, NJOP, alamat, RT, target pemda, catatan, foto).
  /// Jika belum ada dan hasilnya lunas, record baru akan ditambahkan.
  Future<DhkpCheckUpdateOutcome?> updateStatusBayarFromCheck({
    required String nop,
    required String tahun,
    required PbbResult result,
  }) async {
    final records = List<BlokRecord>.from(await loadAll());
    final key = '$nop|$tahun';
    final index = records.indexWhere((r) => r.uniqueKey == key);

    final isPaid = result.isPaid;

    if (index != -1) {
      final existing = records[index];
      final wasUnpaid = !existing.isPaid;

      // Jika di server belum bayar dan di lokal juga belum, atau tidak ada perubahan
      if (!isPaid && !wasUnpaid) {
        return null;
      }

      final updatedStatus = isPaid ? 'Sudah Bayar' : existing.statusBayar;
      final updatedTanggal =
          (result.tanggalBayar != null &&
              result.tanggalBayar!.trim().isNotEmpty)
          ? result.tanggalBayar!.trim()
          : (isPaid && existing.tanggalBayar.isEmpty
                ? DateTime.now().toIso8601String().substring(0, 10)
                : existing.tanggalBayar);
      final updatedJumlah =
          (result.jumlahPbb != null && result.jumlahPbb!.trim().isNotEmpty)
          ? result.jumlahPbb!.trim()
          : existing.jumlahPbb;
      final updatedNama =
          (result.namaWajibPajak != null &&
              result.namaWajibPajak!.trim().isNotEmpty)
          ? result.namaWajibPajak!.trim()
          : existing.namaWajibPajak;

      final updatedRecord = existing.copyWith(
        statusBayar: updatedStatus,
        tanggalBayar: updatedTanggal,
        jumlahPbb: updatedJumlah,
        namaWajibPajak: updatedNama,
      );

      records[index] = updatedRecord;
      await _persist(records);
      await BlokBackupScheduler.instance.markDirty();

      return DhkpCheckUpdateOutcome(
        wasExisting: true,
        changedFromUnpaid: wasUnpaid && isPaid,
        record: updatedRecord,
      );
    } else if (isPaid) {
      // Record belum ada di database, buat baru
      final newRecord = BlokRecord(
        nop: nop,
        namaWajibPajak: result.namaWajibPajak ?? '',
        tahunBayar: tahun,
        tanggalBayar:
            (result.tanggalBayar != null &&
                result.tanggalBayar!.trim().isNotEmpty)
            ? result.tanggalBayar!.trim()
            : DateTime.now().toIso8601String().substring(0, 10),
        jumlahPbb: result.jumlahPbb ?? '',
        statusBayar: 'Sudah Bayar',
      );
      records.add(newRecord);
      await _persist(records);
      await BlokBackupScheduler.instance.markDirty();

      return DhkpCheckUpdateOutcome(
        wasExisting: false,
        changedFromUnpaid: true,
        record: newRecord,
      );
    }
    return null;
  }

  /// Hapus satu catatan berdasar [BlokRecord.uniqueKey] (NOP+tahun) — dipakai
  /// untuk mengoreksi baris yang salah tercatat (mis. salah impor), beda dari
  /// [clearAll] yang menghapus semuanya.
  Future<void> deleteByKey(String uniqueKey) async {
    final records = List<BlokRecord>.from(await loadAll());
    records.removeWhere((r) => r.uniqueKey == uniqueKey);
    await _persist(records);
    await BlokBackupScheduler.instance.markDirty();
  }

  /// Daftar blok yang punya data, terurut.
  Future<List<String>> blokList() async {
    final records = await loadAll();
    final bloks = records.map((r) => r.blok).toSet().toList()..sort();
    return bloks;
  }

  Future<List<BlokRecord>> byBlok(
    String blok, {
    String? tahun,
    BlokSortBy sortBy = BlokSortBy.blokWilayah,
  }) async {
    var records = (await loadAll()).where((r) => r.blok == blok).toList();
    if (tahun != null && tahun.isNotEmpty) {
      records = records.where((r) => r.tahunBayar == tahun).toList();
    }
    return sortBlokRecords(records, sortBy);
  }

  /// Semua record dari blok-blok di [whitelist] digabung jadi satu (dipakai
  /// untuk tampilan "Semua Blok (Wilayah Kerja)"), opsional difilter per
  /// tahun.
  Future<List<BlokRecord>> byWhitelist(
    Set<String> whitelist, {
    String? tahun,
    BlokSortBy sortBy = BlokSortBy.blokWilayah,
  }) async {
    var records = (await loadAll())
        .where((r) => whitelist.contains(r.blok))
        .toList();
    if (tahun != null && tahun.isNotEmpty) {
      records = records.where((r) => r.tahunBayar == tahun).toList();
    }
    return sortBlokRecords(records, sortBy);
  }

  Future<int> get totalCount async {
    if (_cache != null) return _cache!.length;
    return (await loadAll()).length;
  }

  /// Hapus seluruh data Buku Catatan Blok — dipakai saat mengganti wilayah
  /// kerja (data lama tidak relevan lagi untuk wilayah yang baru). Backup
  /// dulu lewat [exportCsv] kalau datanya masih mau disimpan.
  Future<void> clearAll() async {
    await _persist([]);
    await BlokBackupScheduler.instance.markDirty();
  }

  /// Seluruh data (opsional difilter per tahun), selalu terurut blok lalu
  /// nomor wilayah menaik — dipakai untuk laporan yang dicetak/diunduh, tidak
  /// terpengaruh filter urutan tampilan (nama/jumlah bayar) di layar.
  Future<List<BlokRecord>> forReport({String? tahun}) async {
    var records = await loadAll();
    if (tahun != null && tahun.isNotEmpty) {
      records = records.where((r) => r.tahunBayar == tahun).toList();
    }
    return sortBlokRecords(records, BlokSortBy.blokWilayah);
  }

  /// Backup: tulis data perubahan dan gambar dokumentasi ke berkas paket terenkripsi (.dkhp)
  /// beserta sidik jari berkas DHKP dasar (`dhkpFingerprint`).
  Future<String> exportDkhp({
    String? fileName,
    bool includePhotos = true,
    bool deltaOnly = true,
  }) async {
    final records = await loadAll();
    final base =
        fileName ?? 'backup_dkhp_${DateTime.now().millisecondsSinceEpoch}';
    final backupsDir = await AppStorage.getBackupsDirectory();
    final outputPath = '${backupsDir.path}/$base$_backupExtension';
    final file = await DhkpPackageHelper.packDkhp(
      outputPath: outputPath,
      records: records,
      baseRecords: records,
      includePhotos: includePhotos,
      deltaOnly: deltaOnly,
    );
    return file.path;
  }

  /// Alias kompatibilitas mundur untuk [exportDkhp].
  Future<String> exportCsv({String? fileName, bool includePhotos = true}) =>
      exportDkhp(fileName: fileName, includePhotos: includePhotos);

  /// Laporan data blok (opsional per tahun) untuk diunduh sebagai CSV —
  /// berbeda dari [exportDkhp] (backup teknis lengkap): laporan ini menyertakan
  /// kolom Blok & Nomor Wilayah terpisah supaya langsung terbaca saat dibuka.
  Future<String> exportReportCsv({String? tahun}) async {
    final records = await forReport(tahun: tahun);
    final content = BlokCsvCodec.encodeReportCsv(records);
    final tahunPart = (tahun == null || tahun.isEmpty) ? 'semua_tahun' : tahun;
    final fileName =
        'laporan_data_blok_${tahunPart}_${DateTime.now().millisecondsSinceEpoch}.csv';
    return DownloadHelper.saveBytes(
      Uint8List.fromList(utf8.encode(content)),
      fileName,
    );
  }

  /// Restore: gabungkan (upsert) isi berkas backup (.dkhp atau arsip tabel) ke data
  /// lokal yang ada sekarang. Mendukung format paket .dkhp modern serta fallback
  /// berkas warisan jika diperlukan.
  Future<int> importCsv(
    String path, {
    String? password,
    bool requireBaseDhkp = false,
  }) async {
    if (DhkpPackageHelper.isDkhpArchivePath(path)) {
      final records = await DhkpPackageHelper.unpackDkhp(
        path,
        password: password,
        requireBaseDhkp: requireBaseDhkp,
      );
      return records.length;
    }

    final fileBytes = await File(path).readAsBytes();
    final identities = await BackupCrypto.allowedRestoreIdentities();
    final decrypted = BackupCrypto.tryDecrypt(fileBytes, identities);
    final content = decrypted != null
        ? utf8.decode(decrypted)
        : BlokCsvCodec.tryDecodeLegacyPlainCsv(fileBytes);
    if (content == null) {
      throw const BackupAccessDeniedException(
        'Berkas ini bukan backup untuk wilayah/mode Anda saat ini (kunci tidak cocok) — impor dibatalkan.',
      );
    }

    final imported = BlokCsvCodec.decodeDatabaseCsv(content);
    if (imported.isEmpty) return 0;

    await upsertAll(imported);
    return imported.length;
  }
}

/// Hasil dari operasi pembaruan status bayar DHKP berdasarkan Cek Status Bayar.
class DhkpCheckUpdateOutcome {
  final bool wasExisting;
  final bool changedFromUnpaid;
  final BlokRecord record;

  const DhkpCheckUpdateOutcome({
    required this.wasExisting,
    required this.changedFromUnpaid,
    required this.record,
  });
}
