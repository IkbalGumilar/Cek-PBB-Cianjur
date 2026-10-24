import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'app_storage.dart';
import 'backup_crypto.dart';
import 'blok_backup_scheduler.dart';
import 'blok_record.dart';
import 'dkhp_package_helper.dart';
import 'download_helper.dart';
import 'pbb_client.dart';

const _csvHeader = [
  'Nama WP',
  'NOP',
  'Tahun Bayar',
  'Tanggal Bayar',
  'Jumlah PBB',
];
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
    _cache = _parseCsv(content);
    countNotifier.value = _cache!.length;
    return _cache!;
  }

  List<BlokRecord> _parseCsv(String content) {
    if (content.trim().isEmpty) return [];
    final rows = Csv().decode(content);
    final records = <BlokRecord>[];
    for (final row in rows.skip(1)) {
      // >= 4 (bukan == 5) supaya backup lama (sebelum kolom Jumlah PBB ada)
      // tetap bisa diimpor.
      if (row.length < 4) continue;
      final nop = row[1].toString().trim();
      if (nop.length != 18) continue;
      final status = row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim()
          : (row[3].toString().trim().isNotEmpty
              ? 'Sudah Bayar'
              : 'Belum Bayar');
      final namaFoto = row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : null;
      final rawTargetPemda = row.length > 7 ? row[7].toString().trim().toLowerCase() : '';
      final isTargetPemda = rawTargetPemda == '1' ||
          rawTargetPemda == 'true' ||
          rawTargetPemda == 'ya' ||
          rawTargetPemda == 'yes' ||
          rawTargetPemda.contains('target') ||
          rawTargetPemda.contains('pemda');
      final catatan = row.length > 8 ? row[8].toString().trim() : '';
      final luasBumi = row.length > 9 ? row[9].toString().trim() : '';
      final luasBangunan = row.length > 10 ? row[10].toString().trim() : '';
      final njopBumi = row.length > 11 ? row[11].toString().trim() : '';
      final njopBangunan = row.length > 12 ? row[12].toString().trim() : '';
      final kecamatan = row.length > 13 && row[13].toString().trim().isNotEmpty
          ? row[13].toString().trim()
          : 'MANDE';
      final kelurahan = row.length > 14 && row[14].toString().trim().isNotEmpty
          ? row[14].toString().trim()
          : 'BOBOJONG';
      final alamatObjek = row.length > 15 ? row[15].toString().trim() : '';
      final alamatWp = row.length > 16 ? row[16].toString().trim() : '';
      final rtObjek = row.length > 17 ? row[17].toString().trim() : '';
      records.add(
        BlokRecord(
          namaWajibPajak: row[0].toString().trim(),
          nop: nop,
          tahunBayar: row[2].toString().trim(),
          tanggalBayar: row[3].toString().trim(),
          jumlahPbb: row.length > 4 ? row[4].toString().trim() : '',
          statusBayar: status,
          namaFoto: namaFoto,
          isTargetPemda: isTargetPemda,
          catatan: catatan,
          luasBumi: luasBumi,
          luasBangunan: luasBangunan,
          njopBumi: njopBumi,
          njopBangunan: njopBangunan,
          kecamatan: kecamatan,
          kelurahan: kelurahan,
          alamatObjek: alamatObjek,
          alamatWp: alamatWp,
          rtObjek: rtObjek,
        ),
      );
    }
    return records;
  }

  Future<void> _persist(List<BlokRecord> records) async {
    final rows = <List<String>>[
      [
        ..._csvHeader,
        'Status Bayar',
        'Foto',
        'Target Pemda',
        'Catatan',
        'Luas Bumi',
        'Luas Bangunan',
        'NJOP Bumi',
        'NJOP Bangunan',
        'Kecamatan',
        'Kelurahan',
        'Alamat Objek',
        'Alamat WP',
        'RT Objek',
      ],
      for (final r in records)
        [
          r.namaWajibPajak,
          r.nop,
          r.tahunBayar,
          r.tanggalBayar,
          r.jumlahPbb,
          r.statusBayar,
          r.namaFoto ?? '',
          r.isTargetPemda ? '1' : '0',
          r.catatan,
          r.luasBumi,
          r.luasBangunan,
          r.njopBumi,
          r.njopBangunan,
          r.kecamatan,
          r.kelurahan,
          r.alamatObjek,
          r.alamatWp,
          r.rtObjek,
        ],
    ];
    final file = await _dataFile();
    file.writeAsStringSync(Csv().encode(rows));
    _cache = records;
    countNotifier.value = records.length;
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
      final updatedTanggal = (result.tanggalBayar != null && result.tanggalBayar!.trim().isNotEmpty)
          ? result.tanggalBayar!.trim()
          : (isPaid && existing.tanggalBayar.isEmpty
              ? DateTime.now().toIso8601String().substring(0, 10)
              : existing.tanggalBayar);
      final updatedJumlah = (result.jumlahPbb != null && result.jumlahPbb!.trim().isNotEmpty)
          ? result.jumlahPbb!.trim()
          : existing.jumlahPbb;
      final updatedNama = (result.namaWajibPajak != null && result.namaWajibPajak!.trim().isNotEmpty)
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
        tanggalBayar: (result.tanggalBayar != null && result.tanggalBayar!.trim().isNotEmpty)
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

  /// Backup: tulis seluruh data dan foto ke berkas paket terenkripsi (.dkhp).
  /// Format .bak lama telah dipensiunkan penuh dan digantikan oleh paket .dkhp.
  /// Bila [includePhotos] bernilai false, hanya data DHKP yang dipaketkan (hemat memori).
  Future<String> exportDkhp({
    String? fileName,
    bool includePhotos = true,
  }) async {
    final records = await loadAll();
    final base =
        fileName ?? 'backup_dkhp_${DateTime.now().millisecondsSinceEpoch}';
    final backupsDir = await AppStorage.getBackupsDirectory();
    final outputPath = '${backupsDir.path}/$base$_backupExtension';
    final file = await DhkpPackageHelper.packDkhp(
      outputPath: outputPath,
      records: records,
      includePhotos: includePhotos,
    );
    return file.path;
  }

  /// Alias kompatibilitas mundur untuk [exportDkhp].
  Future<String> exportCsv({
    String? fileName,
    bool includePhotos = true,
  }) =>
      exportDkhp(fileName: fileName, includePhotos: includePhotos);

  /// Laporan data blok (opsional per tahun) untuk diunduh sebagai CSV —
  /// berbeda dari [exportDkhp] (backup teknis lengkap): laporan ini menyertakan
  /// kolom Blok & Nomor Wilayah terpisah supaya langsung terbaca saat dibuka.
  Future<String> exportReportCsv({String? tahun}) async {
    final records = await forReport(tahun: tahun);
    final rows = <List<String>>[
      ['Blok', 'Nomor Wilayah', ..._csvHeader],
      for (final r in records)
        [
          r.blok,
          r.wilayah,
          r.namaWajibPajak,
          r.nop,
          r.tahunBayar,
          r.tanggalBayar,
          r.jumlahPbb,
        ],
    ];
    final content = Csv().encode(rows);
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
  Future<int> importCsv(String path, {String? password}) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dkhp') || lower.endsWith('.zip')) {
      final records = await DhkpPackageHelper.unpackDkhp(
        path,
        password: password,
      );
      return records.length;
    }

    final fileBytes = await File(path).readAsBytes();
    final identities = await BackupCrypto.allowedRestoreIdentities();
    final decrypted = BackupCrypto.tryDecrypt(fileBytes, identities);
    final content = decrypted != null
        ? utf8.decode(decrypted)
        : _legacyPlainCsv(fileBytes);
    if (content == null) {
      throw const BackupAccessDeniedException(
        'Berkas ini bukan backup untuk wilayah/mode Anda saat ini (kunci tidak cocok) — impor dibatalkan.',
      );
    }

    final imported = _parseCsv(content);
    if (imported.isEmpty) return 0;

    await upsertAll(imported);
    return imported.length;
  }

  /// Backward-compat: backup lama (sebelum format terenkripsi ada) masih
  /// berupa CSV polos tanpa penguncian wilayah — kalau berkas gagal
  /// didekripsi sama sekali tapi isinya kebetulan teks CSV dengan header
  /// yang dikenali, tetap diterima supaya backup lama tidak hilang begitu
  /// saja.
  String? _legacyPlainCsv(Uint8List fileBytes) {
    try {
      final text = utf8.decode(fileBytes);
      if (!text.trimLeft().startsWith(_csvHeader.first)) return null;
      return text;
    } catch (_) {
      return null;
    }
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

