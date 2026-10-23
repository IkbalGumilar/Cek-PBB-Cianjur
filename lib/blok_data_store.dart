import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_crypto.dart';
import 'blok_backup_scheduler.dart';
import 'blok_record.dart';
import 'download_helper.dart';

const _dataFileName = 'blok_data.csv';
const _csvHeader = [
  'Nama WP',
  'NOP',
  'Tahun Bayar',
  'Tanggal Bayar',
  'Jumlah PBB',
];
const _backupExtension = '.bak';

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

  static const initialDhkpRecords = [
    BlokRecord(
      namaWajibPajak: 'SUGENG RAHARJO',
      nop: '320520000402600340',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: 'Rp 102.378',
      statusBayar: 'Belum Bayar',
      namaFoto: '320520000402600340.jpg',
      isTargetPemda: false,
      catatan: '',
      luasBumi: '450 m2',
      luasBangunan: '120 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '350.000,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL PASIR PARAHU',
      alamatWp: 'KP PASIR PARAHU RT 02/05',
      rtObjek: '002',
    ),
    BlokRecord(
      namaWajibPajak: 'AHMAD SUHADA',
      nop: '320520000402600350',
      tahunBayar: '2026',
      tanggalBayar: '2026-03-15',
      jumlahPbb: 'Rp 45.000',
      statusBayar: 'Sudah Bayar',
      namaFoto: '320520000402600350.jpg',
      isTargetPemda: false,
      catatan: 'Lunas via Bank BJB',
      luasBumi: '210 m2',
      luasBangunan: '54 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '250.000,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL CIKANGKUNG',
      alamatWp: 'KP CIKANGKUNG',
      rtObjek: '018',
    ),
    BlokRecord(
      namaWajibPajak: 'SITI ROHMAH',
      nop: '320520000402600360',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: 'Rp 85.500',
      statusBayar: 'Blacklist',
      namaFoto: '320520000402600360.jpg',
      isTargetPemda: false,
      catatan: 'Nunggak 6 tahun sejak 2020. Pemilik tidak di lokasi.',
      luasBumi: '380 m2',
      luasBangunan: '0 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '0,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'BLOK PASIR',
      alamatWp: 'KP PASIR PARAHU',
      rtObjek: '015',
    ),
    BlokRecord(
      namaWajibPajak: 'DUDI KURNIAWAN',
      nop: '320520000402600370',
      tahunBayar: '2026',
      tanggalBayar: '2026-02-20',
      jumlahPbb: 'Rp 150.000',
      statusBayar: 'Sudah Bayar',
      namaFoto: null,
      isTargetPemda: false,
      catatan: '',
      luasBumi: '600 m2',
      luasBangunan: '150 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '400.000,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL UTAMA BOBOJONG',
      alamatWp: 'KP BOBOJONG TENGAH',
      rtObjek: '005',
    ),
    BlokRecord(
      namaWajibPajak: 'H ACEP',
      nop: '320520000402600380',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: 'Rp 320.000',
      statusBayar: 'Belum Bayar',
      namaFoto: '320520000402600380.jpg',
      isTargetPemda: true,
      catatan: 'Prioritas Penagihan Target Pemda 2026.',
      luasBumi: '1438 m2',
      luasBangunan: '0 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '0,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL CIKANGKUNG',
      alamatWp: 'PASIR PARAHU',
      rtObjek: '019',
    ),
  ];

  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_dataFileName');
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
    if (!await file.exists()) {
      _cache = List<BlokRecord>.from(initialDhkpRecords);
      countNotifier.value = _cache!.length;
      await _persist(_cache!);
      return _cache!;
    }

    final content = await file.readAsString();
    _cache = _parseCsv(content);
    if (_cache!.isEmpty) {
      _cache = List<BlokRecord>.from(initialDhkpRecords);
      await _persist(_cache!);
    }
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
    await file.writeAsString(Csv().encode(rows));
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

  /// Backup: tulis seluruh data ke berkas terenkripsi (.bak) yang bisa
  /// disimpan/dibagikan — dikunci otomatis dengan kunci wilayah kerja/Mode
  /// Operator perangkat ini saat ekspor (lihat backup_crypto.dart), supaya
  /// tidak bisa dibuka wilayah lain atau dibaca sebagai teks biasa.
  /// [fileName] (tanpa ekstensi) tetap dipakai backup harian otomatis
  /// (ditimpa tiap kali dipanggil di hari yang sama) kalau diisi; default
  /// nama unik per waktu ekspor (dipakai tombol "Ekspor Data" manual di
  /// Setelan).
  Future<String> exportCsv({String? fileName}) async {
    final records = await forReport();
    final rows = <List<String>>[
      _csvHeader,
      for (final r in records)
        [r.namaWajibPajak, r.nop, r.tahunBayar, r.tanggalBayar, r.jumlahPbb],
    ];
    final csvBytes = Uint8List.fromList(utf8.encode(Csv().encode(rows)));
    final identity = await BackupCrypto.currentIdentity();
    final encrypted = BackupCrypto.encryptForIdentity(identity, csvBytes);
    final base =
        fileName ?? 'backup_data_blok_${DateTime.now().millisecondsSinceEpoch}';
    return DownloadHelper.saveBytes(encrypted, '$base$_backupExtension');
  }

  /// Laporan data blok (opsional per tahun) untuk diunduh sebagai CSV —
  /// berbeda dari [exportCsv] (backup teknis lengkap): laporan ini menyertakan
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

  /// Restore: gabungkan (upsert) isi berkas backup terenkripsi (.bak) ke data
  /// lokal yang ada sekarang. Berkas hanya bisa dibuka kalau dienkripsi oleh
  /// identitas yang cocok dengan perangkat ini sekarang (wilayah kerja yang
  /// sama, atau Mode Operator yang bisa membuka laporan semua dusun) — kalau
  /// tidak cocok, [BackupAccessDeniedException] dilempar dan tidak ada data
  /// yang berubah. Tidak menghapus data lokal yang tidak ada di berkas —
  /// hanya menambah/menimpa baris yang NOP+tahun-nya sama.
  Future<int> importCsv(String path) async {
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
