import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../blok_record.dart';
import '../nop_helper.dart';

/// Codec terpusat untuk serialisasi dan deserialisasi CSV [BlokRecord].
///
/// Mempertahankan urutan 18 kolom standar serta kompatibilitas mundur
/// dengan backup CSV versi lama (minimal 4 kolom pada database lokal
/// dan minimal 2 kolom pada paket arsip `.dkhp`).
class BlokCsvCodec {
  BlokCsvCodec._();

  static const List<String> baseCsvHeader = [
    'Nama WP',
    'NOP',
    'Tahun Bayar',
    'Tanggal Bayar',
    'Jumlah PBB',
  ];

  static const List<String> fullCsvHeader = [
    ...baseCsvHeader,
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
  ];

  static String encodeRecords(Iterable<BlokRecord> records) {
    final rows = <List<String>>[
      fullCsvHeader,
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
    return Csv().encode(rows);
  }

  static String encodeReportCsv(Iterable<BlokRecord> records) {
    final rows = <List<String>>[
      ['Blok', 'Nomor Wilayah', ...baseCsvHeader],
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
    return Csv().encode(rows);
  }

  /// Membaca isi CSV database lokal `blok_data.csv` atau backup CSV legacy.
  static List<BlokRecord> decodeDatabaseCsv(String content) {
    if (content.trim().isEmpty) return [];
    final rows = Csv().decode(content);
    final records = <BlokRecord>[];
    for (final row in rows.skip(1)) {
      // >= 4 (bukan == 5) supaya backup lama (sebelum kolom Jumlah PBB ada)
      // tetap bisa diimpor.
      if (row.length < 4) continue;
      final nop = row[1].toString().trim();
      if (nop.length != 18) continue;
      final tanggalBayar = row[3].toString().trim();
      final rawStatus = row.length > 5 ? row[5].toString().trim() : '';
      final status = (tanggalBayar.isNotEmpty && tanggalBayar != '0')
          ? 'Sudah Bayar'
          : (rawStatus.isNotEmpty ? rawStatus : 'Belum Bayar');
      final namaFoto = row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : null;
      final rawTargetPemda = row.length > 7
          ? row[7].toString().trim().toLowerCase()
          : '';
      final isTargetPemda = _isTruthyTargetPemda(rawTargetPemda);
      records.add(
        BlokRecord(
          namaWajibPajak: row[0].toString().trim(),
          nop: nop,
          tahunBayar: row[2].toString().trim(),
          tanggalBayar: tanggalBayar,
          jumlahPbb: row.length > 4 ? row[4].toString().trim() : '',
          statusBayar: status,
          namaFoto: namaFoto,
          isTargetPemda: isTargetPemda,
          catatan: _cell(row, 8),
          luasBumi: _cell(row, 9),
          luasBangunan: _cell(row, 10),
          njopBumi: _cell(row, 11),
          njopBangunan: _cell(row, 12),
          kecamatan: _cellOrDefault(row, 13, 'MANDE'),
          kelurahan: _cellOrDefault(row, 14, 'BOBOJONG'),
          alamatObjek: _cell(row, 15),
          alamatWp: _cell(row, 16),
          rtObjek: _cell(row, 17),
        ),
      );
    }
    return records;
  }

  /// Membaca isi `data.csv` dari dalam arsip `.dkhp` / `.dat`.
  static List<BlokRecord> decodeArchiveCsv(
    String content, {
    String? fallbackYear,
  }) {
    if (content.trim().isEmpty) return [];
    final currentYear = fallbackYear ?? '${DateTime.now().year}';
    final rows = Csv().decode(content);
    final records = <BlokRecord>[];

    for (final row in rows.skip(1)) {
      if (row.length < 2) continue;
      final rawNop = row[1].toString().trim();
      final nopDigits = rawNop.replaceAll(RegExp(r'[^0-9]'), '');
      if (nopDigits.length != 18) continue;

      final nama = row[0].toString().trim();
      final tahun = row.length > 2 && row[2].toString().trim().isNotEmpty
          ? row[2].toString().trim()
          : currentYear;
      final tanggal = _cell(row, 3);
      final pokok = _cell(row, 4);
      final rawStatus = _cell(row, 5);
      final status = (tanggal.isNotEmpty && tanggal != '0')
          ? 'Sudah Bayar'
          : (rawStatus.isNotEmpty ? rawStatus : 'Belum Bayar');
      final namaFoto = row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : null;
      final rawTargetPemda = row.length > 7
          ? row[7].toString().trim().toLowerCase()
          : '';
      final pokokDigits = pokok.replaceAll(RegExp(r'[^0-9]'), '');
      final pokokVal = int.tryParse(pokokDigits) ?? 0;
      final isTargetPemda =
          _isTruthyTargetPemda(rawTargetPemda) ||
          (rawTargetPemda.isEmpty && pokokVal >= 1500000);

      records.add(
        BlokRecord(
          namaWajibPajak: nama.isEmpty
              ? 'WP ${nopBlok(nopDigits)}/${nopWilayah(nopDigits)}'
              : nama,
          nop: nopDigits,
          tahunBayar: tahun,
          tanggalBayar: tanggal,
          jumlahPbb: pokok,
          statusBayar: status,
          namaFoto: namaFoto,
          isTargetPemda: isTargetPemda,
          catatan: _cell(row, 8),
          luasBumi: _cell(row, 9),
          luasBangunan: _cell(row, 10),
          njopBumi: _cell(row, 11),
          njopBangunan: _cell(row, 12),
          kecamatan: _cellOrDefault(row, 13, 'MANDE'),
          kelurahan: _cellOrDefault(row, 14, 'BOBOJONG'),
          alamatObjek: _cell(row, 15),
          alamatWp: _cell(row, 16),
          rtObjek: _cell(row, 17),
        ),
      );
    }
    return records;
  }

  /// Backward-compat: mendeteksi CSV polos warisan yang diawali `Nama WP`.
  static String? tryDecodeLegacyPlainCsv(Uint8List fileBytes) {
    try {
      final text = utf8.decode(fileBytes);
      if (!text.trimLeft().startsWith(baseCsvHeader.first)) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  static bool _isTruthyTargetPemda(String raw) {
    return raw == '1' ||
        raw == 'true' ||
        raw == 'ya' ||
        raw == 'yes' ||
        raw.contains('target') ||
        raw.contains('pemda');
  }

  static String _cell(List<dynamic> row, int index) {
    return row.length > index ? row[index].toString().trim() : '';
  }

  static String _cellOrDefault(
    List<dynamic> row,
    int index,
    String defaultValue,
  ) {
    final val = _cell(row, index);
    return val.isNotEmpty ? val : defaultValue;
  }
}
