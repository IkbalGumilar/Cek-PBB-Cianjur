import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

import 'blok_backup_scheduler.dart';
import 'blok_record.dart';
import 'download_helper.dart';

const _dataFileName = 'blok_data.csv';
const _csvHeader = ['Nama WP', 'NOP', 'Tahun Bayar', 'Tanggal Bayar', 'Jumlah PBB'];

/// Penyimpanan lokal "Buku Catatan Blok" — daftar NOP yang sudah terkonfirmasi
/// "Sudah Bayar", dikelompokkan per blok. Data disimpan sebagai CSV di
/// direktori dokumen aplikasi, bukan di server, jadi hilang kalau aplikasi
/// di-uninstall kecuali sudah di-ekspor (backup) lebih dulu.
class BlokDataStore {
  BlokDataStore._();
  static final instance = BlokDataStore._();

  List<BlokRecord>? _cache;

  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_dataFileName');
  }

  Future<List<BlokRecord>> loadAll() async {
    if (_cache != null) return _cache!;

    final file = await _dataFile();
    if (!await file.exists()) {
      _cache = [];
      return _cache!;
    }

    final content = await file.readAsString();
    _cache = _parseCsv(content);
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
      records.add(BlokRecord(
        namaWajibPajak: row[0].toString().trim(),
        nop: nop,
        tahunBayar: row[2].toString().trim(),
        tanggalBayar: row[3].toString().trim(),
        jumlahPbb: row.length > 4 ? row[4].toString().trim() : '',
      ));
    }
    return records;
  }

  Future<void> _persist(List<BlokRecord> records) async {
    final rows = <List<String>>[
      _csvHeader,
      for (final r in records) [r.namaWajibPajak, r.nop, r.tahunBayar, r.tanggalBayar, r.jumlahPbb],
    ];
    final file = await _dataFile();
    await file.writeAsString(Csv().encode(rows));
    _cache = records;
  }

  /// Simpan/perbarui satu catatan (upsert berdasar NOP+tahun).
  Future<void> upsert(BlokRecord record) async {
    final records = List<BlokRecord>.from(await loadAll());
    final index = records.indexWhere((r) => r.uniqueKey == record.uniqueKey);
    if (index == -1) {
      records.add(record);
    } else {
      records[index] = record;
    }
    await _persist(records);
    await BlokBackupScheduler.instance.markDirty();
  }

  /// Daftar blok yang punya data, terurut.
  Future<List<String>> blokList() async {
    final records = await loadAll();
    final bloks = records.map((r) => r.blok).toSet().toList()..sort();
    return bloks;
  }

  Future<List<BlokRecord>> byBlok(String blok, {String? tahun, BlokSortBy sortBy = BlokSortBy.blokWilayah}) async {
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
    var records = (await loadAll()).where((r) => whitelist.contains(r.blok)).toList();
    if (tahun != null && tahun.isNotEmpty) {
      records = records.where((r) => r.tahunBayar == tahun).toList();
    }
    return sortBlokRecords(records, sortBy);
  }

  Future<int> get totalCount async => (await loadAll()).length;

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

  /// Backup: tulis seluruh data ke berkas CSV yang bisa disimpan/dibagikan.
  /// [fileName] tetap (dipakai backup harian otomatis, ditimpa tiap kali
  /// dipanggil di hari yang sama) kalau diisi; default nama unik per waktu
  /// ekspor (dipakai tombol "Ekspor Data" manual di Setelan).
  Future<String> exportCsv({String? fileName}) async {
    final records = await forReport();
    final rows = <List<String>>[
      _csvHeader,
      for (final r in records) [r.namaWajibPajak, r.nop, r.tahunBayar, r.tanggalBayar, r.jumlahPbb],
    ];
    final content = Csv().encode(rows);
    final name = fileName ?? 'backup_data_blok_${DateTime.now().millisecondsSinceEpoch}.csv';
    return DownloadHelper.saveBytes(Uint8List.fromList(utf8.encode(content)), name);
  }

  /// Laporan data blok (opsional per tahun) untuk diunduh sebagai CSV —
  /// berbeda dari [exportCsv] (backup teknis lengkap): laporan ini menyertakan
  /// kolom Blok & Nomor Wilayah terpisah supaya langsung terbaca saat dibuka.
  Future<String> exportReportCsv({String? tahun}) async {
    final records = await forReport(tahun: tahun);
    final rows = <List<String>>[
      ['Blok', 'Nomor Wilayah', ..._csvHeader],
      for (final r in records)
        [r.blok, r.wilayah, r.namaWajibPajak, r.nop, r.tahunBayar, r.tanggalBayar, r.jumlahPbb],
    ];
    final content = Csv().encode(rows);
    final tahunPart = (tahun == null || tahun.isEmpty) ? 'semua_tahun' : tahun;
    final fileName = 'laporan_data_blok_${tahunPart}_${DateTime.now().millisecondsSinceEpoch}.csv';
    return DownloadHelper.saveBytes(Uint8List.fromList(utf8.encode(content)), fileName);
  }

  /// Restore: gabungkan (upsert) isi berkas CSV backup ke data lokal yang ada
  /// sekarang. Tidak menghapus data lokal yang tidak ada di berkas — hanya
  /// menambah/menimpa baris yang NOP+tahun-nya sama.
  Future<int> importCsv(String path) async {
    final content = await File(path).readAsString();
    final imported = _parseCsv(content);
    if (imported.isEmpty) return 0;

    final records = List<BlokRecord>.from(await loadAll());
    for (final record in imported) {
      final index = records.indexWhere((r) => r.uniqueKey == record.uniqueKey);
      if (index == -1) {
        records.add(record);
      } else {
        records[index] = record;
      }
    }
    await _persist(records);
    await BlokBackupScheduler.instance.markDirty();
    return imported.length;
  }
}
