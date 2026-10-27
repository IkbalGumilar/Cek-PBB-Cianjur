import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'blok_record.dart';
import 'dusun_data.dart';
import 'nop_helper.dart';
import 'tax_record.dart';

class FileImporter {
  /// Impor daftar TaxRecord sederhana (hanya NOP). Kompatibel mundur dengan fitur cek massal.
  static Future<List<TaxRecord>> importFrom(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.txt')) {
      return _importTxt(path);
    }
    if (lower.endsWith('.csv')) {
      return _importCsv(path);
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return _importXlsx(path);
    }
    throw UnsupportedError('Format file tidak didukung: $path');
  }

  /// Impor lengkap seluruh baris DHKP ke bentuk [BlokRecord] dari file Excel (.xlsx/.xls) atau .csv.
  ///
  /// Otomatis memetakan seluruh kolom (Nama WP, NOP, Pokok PBB, Status Bayar, Target Pemda,
  /// Luas, NJOP, Alamat, RT) dan memvalidasi aturan:
  /// 1. Pokok PBB >= Rp 1.500.000 otomatis berstatus Target Pemda (isTargetPemda = true).
  /// 2. Bila terdapat kolom Dusun, otomatis menyusun pemetaan Dusun dinamis di [DusunData].
  static Future<List<BlokRecord>> importBlokRecordsFrom(String path) async {
    final lower = path.toLowerCase();
    List<List<dynamic>> rows;

    if (lower.endsWith('.csv')) {
      final content = await File(path).readAsString();
      rows = Csv().decode(content);
    } else if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      final bytes = await File(path).readAsBytes();
      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) return [];

      // Pilih sheet yang memiliki data tabel lengkap (mis. "Semua NOP" atau sheet pertama yang cocok)
      Sheet sheet = workbook.tables[workbook.tables.keys.first]!;
      for (final name in workbook.tables.keys) {
        final lowerName = name.toLowerCase();
        if (lowerName.contains('semua nop') ||
            lowerName.contains('all') ||
            lowerName.contains('dhkp')) {
          sheet = workbook.tables[name]!;
          break;
        }
      }

      rows = sheet.rows
          .map(
            (row) => row.map((cell) => cell?.value?.toString() ?? '').toList(),
          )
          .toList();
    } else {
      throw UnsupportedError('Format file tidak didukung: $path');
    }

    return _parseBlokRows(rows);
  }

  static List<BlokRecord> _parseBlokRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    // Cari baris header yang memuat kolom NOP
    int headerRowIdx = -1;
    for (var i = 0; i < rows.length && i < 15; i++) {
      final line = rows[i].map((c) => c.toString().trim().toLowerCase()).toList();
      if (line.contains('nop')) {
        headerRowIdx = i;
        break;
      }
    }

    if (headerRowIdx == -1) return [];

    final headers = rows[headerRowIdx]
        .map((c) => c.toString().trim().toLowerCase())
        .toList();

    int findCol(List<String> candidates) {
      for (final c in candidates) {
        final idx = headers.indexOf(c.toLowerCase());
        if (idx != -1) return idx;
      }
      return -1;
    }

    final nopCol = findCol(['nop']);
    final namaCol = findCol(['nama wp', 'nama_wp', 'nama']);
    final tahunCol = findCol(['tahun bayar', 'tahun_pajak', 'tahun']);
    final tglCol = findCol(['tanggal bayar', 'tanggal_pembayaran', 'tgl bayar', 'tgl']);
    final pokokCol = findCol(['jumlah pbb', 'pokok_tagihan', 'pokok_ketetapan', 'pokok', 'pbb']);
    final statusCol = findCol(['status bayar', 'status']);
    final fotoCol = findCol(['foto', 'nama foto', 'gambar']);
    final tpCol = findCol(['target pemda', 'target_pemda', 'pemda']);
    final catatanCol = findCol(['catatan', 'keterangan']);
    final luasBumiCol = findCol(['luas bumi', 'luas_bumi']);
    final luasBngCol = findCol(['luas bangunan', 'luas_bangunan']);
    final njopBumiCol = findCol(['njop bumi', 'njop_bumi']);
    final njopBngCol = findCol(['njop bangunan', 'njop_bangunan']);
    final kecCol = findCol(['kecamatan', 'kecamatan_op']);
    final kelCol = findCol(['kelurahan', 'kelurahan_op']);
    final almtObjCol = findCol(['alamat objek', 'alamat_op']);
    final almtWpCol = findCol(['alamat wp', 'alamat_wp']);
    final rtCol = findCol(['rt objek', 'rt_op', 'rt']);
    final dusunCol = findCol(['dusun', 'wilayah']);

    final currentYear = '${DateTime.now().year}';
    final records = <BlokRecord>[];
    final dusunBlockMap = <int, Set<String>>{};

    for (var i = headerRowIdx + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= nopCol) continue;

      final rawNop = row[nopCol].toString().trim();
      final nopDigits = rawNop.replaceAll(RegExp(r'[^0-9]'), '');
      if (nopDigits.length != 18) continue;

      final nama = namaCol != -1 && row.length > namaCol
          ? row[namaCol].toString().trim()
          : '';
      final tahun = tahunCol != -1 && row.length > tahunCol && row[tahunCol].toString().trim().isNotEmpty
          ? row[tahunCol].toString().trim()
          : currentYear;
      final tanggal = tglCol != -1 && row.length > tglCol
          ? row[tglCol].toString().trim()
          : '';
      final pokok = pokokCol != -1 && row.length > pokokCol
          ? row[pokokCol].toString().trim()
          : '';
      var status = statusCol != -1 && row.length > statusCol && row[statusCol].toString().trim().isNotEmpty
          ? row[statusCol].toString().trim()
          : (tanggal.isNotEmpty ? 'Sudah Bayar' : 'Belum Bayar');

      // Standarisasi status dari format mentah jika ada
      if (status.toLowerCase() == 'belum lunas') status = 'Belum Bayar';
      if (status.toLowerCase() == 'lunas') status = 'Sudah Bayar';

      final namaFoto = fotoCol != -1 && row.length > fotoCol && row[fotoCol].toString().trim().isNotEmpty
          ? row[fotoCol].toString().trim()
          : null;

      final rawTp = tpCol != -1 && row.length > tpCol
          ? row[tpCol].toString().trim().toLowerCase()
          : '';

      final pokokDigits = pokok.replaceAll(RegExp(r'[^0-9]'), '');
      final pokokVal = int.tryParse(pokokDigits) ?? 0;

      // Aturan Target Pemda: Pokok PBB >= Rp 1.500.000 atau bendera eksplisit Target Pemda
      final isTargetPemda =
          rawTp == '1' ||
          rawTp == 'true' ||
          rawTp == 'ya' ||
          rawTp == 'yes' ||
          rawTp.contains('target') ||
          rawTp.contains('pemda') ||
          (pokokVal >= 1500000);

      final catatan = catatanCol != -1 && row.length > catatanCol
          ? row[catatanCol].toString().trim()
          : '';
      final luasBumi = luasBumiCol != -1 && row.length > luasBumiCol
          ? row[luasBumiCol].toString().trim()
          : '';
      final luasBng = luasBngCol != -1 && row.length > luasBngCol
          ? row[luasBngCol].toString().trim()
          : '';
      final njopBumi = njopBumiCol != -1 && row.length > njopBumiCol
          ? row[njopBumiCol].toString().trim()
          : '';
      final njopBng = njopBngCol != -1 && row.length > njopBngCol
          ? row[njopBngCol].toString().trim()
          : '';
      final kec = kecCol != -1 && row.length > kecCol && row[kecCol].toString().trim().isNotEmpty
          ? row[kecCol].toString().trim()
          : 'MANDE';
      final kel = kelCol != -1 && row.length > kelCol && row[kelCol].toString().trim().isNotEmpty
          ? row[kelCol].toString().trim()
          : 'BOBOJONG';
      final almtObj = almtObjCol != -1 && row.length > almtObjCol
          ? row[almtObjCol].toString().trim()
          : '';
      final almtWp = almtWpCol != -1 && row.length > almtWpCol
          ? row[almtWpCol].toString().trim()
          : '';
      final rtObj = rtCol != -1 && row.length > rtCol
          ? row[rtCol].toString().trim()
          : '';

      // Deteksi dusun bila ada di baris
      if (dusunCol != -1 && row.length > dusunCol) {
        final dStr = row[dusunCol].toString();
        final dDigits = dStr.replaceAll(RegExp(r'[^0-9]'), '');
        final dNum = int.tryParse(dDigits);
        if (dNum != null && dNum > 0) {
          final blok = nopBlok(nopDigits);
          dusunBlockMap.putIfAbsent(dNum, () => <String>{}).add(blok);
        }
      }

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
          catatan: catatan,
          luasBumi: luasBumi,
          luasBangunan: luasBng,
          njopBumi: njopBumi,
          njopBangunan: njopBng,
          kecamatan: kec,
          kelurahan: kel,
          alamatObjek: almtObj,
          alamatWp: almtWp,
          rtObjek: rtObj,
        ),
      );
    }

    // Jika berhasil mendeteksi pembagian dusun dari file, perbarui DusunData secara dinamis
    if (dusunBlockMap.isNotEmpty) {
      final detectedDusuns = dusunBlockMap.entries.map((e) {
        final bloksList = e.value.toList()..sort();
        return Dusun(number: e.key, bloks: bloksList);
      }).toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      DusunData.instance.setDusuns(detectedDusuns);
    }

    return records;
  }

  static Future<List<TaxRecord>> _importTxt(String path) async {
    final content = await File(path).readAsString();
    return importFromText(content);
  }

  static List<TaxRecord> importFromText(String content) {
    final tokens = content.split(RegExp(r'[,\n\r]+'));
    return _toRecords(tokens);
  }

  static Future<List<TaxRecord>> _importCsv(String path) async {
    final content = await File(path).readAsString();
    final rows = Csv().decode(content);
    return _extractNopColumn(rows);
  }

  static Future<List<TaxRecord>> _importXlsx(String path) async {
    final bytes = await File(path).readAsBytes();
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];

    final sheet = workbook.tables[workbook.tables.keys.first]!;
    final rows = sheet.rows
        .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
        .toList();
    return _extractNopColumn(rows);
  }

  static List<TaxRecord> _extractNopColumn(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    var nopColumn = 0;
    var startRow = 0;
    final firstRow = rows.first
        .map((c) => c.toString().trim().toLowerCase())
        .toList();
    final headerIndex = firstRow.indexWhere((c) => c == 'nop');
    if (headerIndex != -1) {
      nopColumn = headerIndex;
      startRow = 1;
    }

    final tokens = <String>[];
    for (var i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (nopColumn < row.length) {
        tokens.add(row[nopColumn].toString());
      }
    }
    return _toRecords(tokens);
  }

  static List<TaxRecord> _toRecords(List<String> tokens) {
    final seen = <String>{};
    final records = <TaxRecord>[];
    for (final raw in tokens) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'nan') continue;
      final nop = expandNop(trimmed);
      if (!seen.add(nop)) continue;
      records.add(TaxRecord(nop: nop));
    }
    return records;
  }
}
