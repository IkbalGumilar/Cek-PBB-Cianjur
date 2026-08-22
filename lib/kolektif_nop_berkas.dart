import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// Pembacaan berkas NOP (CSV / Excel / teks) dan penggolongan jawaban server
/// untuk fitur "Unggah Berkas" di Kelola Anggota grup kolektif.
///
/// Sengaja tanpa `package:flutter` dan tanpa jaringan sama sekali supaya
/// seluruh aturan di sini — penguraian NOP, penebakan kolom, penggolongan
/// pesan server — bisa dites langsung. Lihat
/// `test/kolektif_nop_berkas_test.dart`.

/// Batas jumlah baris yang dibaca dari satu berkas. Bukan batasan server,
/// cuma penjaga supaya berkas raksasa (atau berkas yang bukan daftar NOP)
/// tidak membekukan layar saat diuraikan.
const maksBarisBerkas = 5000;

/// Satu baris berkas setelah diuraikan.
class BarisBerkasNop {
  /// Nomor baris di berkas aslinya (1 = baris pertama), supaya kalau ada yang
  /// tidak terbaca, penggunanya tahu persis baris mana yang harus diperbaiki.
  final int nomorBaris;

  /// Isi selnya apa adanya, sebelum diuraikan.
  final String asli;

  /// NOP 18 angka hasil uraian, atau null kalau tidak terbaca.
  final String? nop;

  /// Alasan kalau [nop] null.
  final String? alasan;

  /// True kalau NOP-nya berasal dari singkatan (5–7 angka) sehingga awalan
  /// wilayahnya DILENGKAPI aplikasi dari kelurahan grup — bukan berasal dari
  /// berkasnya. Perlu ditandai karena awalan yang salah berarti NOP milik
  /// orang lain.
  final bool dariSingkatan;

  const BarisBerkasNop({
    required this.nomorBaris,
    required this.asli,
    this.nop,
    this.alasan,
    this.dariSingkatan = false,
  });
}

/// Hasil membaca satu berkas.
class BacaanBerkasNop {
  /// Label tiap kolom — dari baris judul kalau ada, kalau tidak "Kolom 1" dst.
  final List<String> namaKolom;

  /// Kolom yang dipakai sebagai NOP. -1 kalau tidak ada yang masuk akal.
  final int kolomNop;

  final List<BarisBerkasNop> baris;

  /// Hal-hal yang perlu dilihat pengguna sebelum mengirim (mis. Excel yang
  /// menyimpan NOP sebagai angka sehingga digitnya bisa berubah).
  final List<String> peringatan;

  final String? errorMessage;

  const BacaanBerkasNop({
    this.namaKolom = const [],
    this.kolomNop = -1,
    this.baris = const [],
    this.peringatan = const [],
    this.errorMessage,
  });

  List<BarisBerkasNop> get terbaca =>
      baris.where((b) => b.nop != null).toList();
  List<BarisBerkasNop> get tidakTerbaca =>
      baris.where((b) => b.nop == null).toList();
}

/// Uraikan satu isian jadi NOP 18 angka.
///
/// Aturannya sama dengan `expandNop` di nop_helper.dart, dengan satu bedanya:
/// awalan wilayah diambil dari [kelurahanCode] milik GRUP, bukan dari tetapan
/// desa. Grup bisa saja milik kelurahan lain, dan salah awalan berarti NOP
/// orang lain yang masuk ke grup.
({String? nop, String? alasan, bool dariSingkatan}) uraikanSatuNop(
  String mentah, {
  required String kelurahanCode,
}) {
  final digits = mentah.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return (
      nop: null,
      alasan: 'Tidak ada angka di baris ini.',
      dariSingkatan: false,
    );
  }
  if (digits.length == 18) {
    return (nop: digits, alasan: null, dariSingkatan: false);
  }
  if (kelurahanCode.length == 10 && digits.length >= 5 && digits.length <= 7) {
    final blokLen = digits.length == 7 ? 3 : 2;
    final blok = digits.substring(0, blokLen).padLeft(3, '0');
    final wilayah = digits.substring(blokLen).padLeft(4, '0');
    return (
      nop: '$kelurahanCode$blok${wilayah}0',
      alasan: null,
      dariSingkatan: true,
    );
  }
  return (
    nop: null,
    alasan:
        '${digits.length} angka — perlu 18 angka lengkap, atau singkatan blok+nomor wilayah 5–7 angka.',
    dariSingkatan: false,
  );
}

/// Versi untuk kolom isian manual: satu teks berisi beberapa NOP dipisah koma.
/// Gagal satu, gagal semua — kalau satu entri tidak terbaca, lebih baik
/// penggunanya membetulkan dulu daripada sebagian terkirim diam-diam.
({List<String> nop, String? error}) uraikanNopKolektif(
  String input, {
  required String kelurahanCode,
}) {
  final hasil = <String>[];
  for (final mentah in input.split(',')) {
    if (mentah.replaceAll(RegExp(r'[^0-9]'), '').isEmpty) continue;
    final satu = uraikanSatuNop(mentah, kelurahanCode: kelurahanCode);
    if (satu.nop == null) {
      return (
        nop: const <String>[],
        error:
            '"${mentah.trim()}" belum bisa dikenali sebagai NOP.\n\n'
            'Isi salah satu dari:\n'
            '• NOP lengkap 18 angka, atau\n'
            '• singkatan blok + nomor wilayah 5–7 angka (contoh: 17154 → blok 017, nomor 0154).\n\n'
            'Angka 4 digit saja belum cukup karena bloknya belum ketahuan.',
      );
    }
    hasil.add(satu.nop!);
  }
  if (hasil.isEmpty) {
    return (
      nop: const <String>[],
      error: 'Belum ada NOP yang bisa dibaca dari isian itu.',
    );
  }
  return (nop: hasil, error: null);
}

/// Tebak kolom mana yang berisi NOP.
///
/// Urutan pertimbangannya:
///  1. Baris judul yang selnya bernama persis "nop" — ini paling meyakinkan.
///  2. Baris judul yang selnya MENGANDUNG "nop" (mis. "NOP SPPT").
///  3. Kalau tidak ada judul: kolom dengan nilai paling banyak terbaca sebagai
///     NOP, di mana NOP 18 angka dihitung 10 poin dan singkatan 5–7 angka cuma
///     1 poin. Bobot timpang itu disengaja: kolom nominal uang (mis. 87453) dan
///     kolom lain yang kebetulan 5–6 angka juga "terbaca" sebagai singkatan,
///     jadi kolom yang punya NOP utuh harus menang telak.
///
/// Hasilnya tetap bisa diganti pengguna lewat layar pratinjau — penebakan ini
/// cuma nilai awal, bukan keputusan akhir.
int tebakKolomNop(List<List<String>> baris, {required String kelurahanCode}) {
  if (baris.isEmpty) return -1;

  final judul = baris.first.map((c) => c.trim().toLowerCase()).toList();
  final persis = judul.indexWhere((c) => c == 'nop');
  if (persis != -1) return persis;
  final mengandung = judul.indexWhere((c) => c.contains('nop'));
  if (mengandung != -1) return mengandung;

  final jumlahKolom = baris.fold<int>(0, (a, b) => b.length > a ? b.length : a);
  var kolomTerbaik = -1;
  var skorTerbaik = 0;
  for (var c = 0; c < jumlahKolom; c++) {
    var skor = 0;
    for (final row in baris) {
      if (c >= row.length) continue;
      final satu = uraikanSatuNop(row[c], kelurahanCode: kelurahanCode);
      if (satu.nop == null) continue;
      skor += satu.dariSingkatan ? 1 : 10;
    }
    if (skor > skorTerbaik) {
      skorTerbaik = skor;
      kolomTerbaik = c;
    }
  }
  return skorTerbaik > 0 ? kolomTerbaik : -1;
}

/// Baca berkas jadi daftar NOP siap kirim.
///
/// [kolomPaksa] dipakai kalau pengguna memilih kolom sendiri di layar
/// pratinjau; kalau null, kolomnya ditebak lewat [tebakKolomNop].
BacaanBerkasNop bacaBerkasNop({
  required String namaBerkas,
  required Uint8List bytes,
  required String kelurahanCode,
  int? kolomPaksa,
}) {
  final tabel = _bacaTabel(namaBerkas, bytes);
  if (tabel.error != null) {
    return BacaanBerkasNop(
      errorMessage: tabel.error,
      peringatan: tabel.peringatan,
    );
  }
  if (tabel.baris.isEmpty) {
    return BacaanBerkasNop(
      errorMessage:
          'Berkas "$namaBerkas" kosong — tidak ada baris yang bisa dibaca.',
      peringatan: tabel.peringatan,
    );
  }

  final jumlahKolom = tabel.baris.fold<int>(
    0,
    (a, b) => b.length > a ? b.length : a,
  );
  final kolom =
      kolomPaksa ?? tebakKolomNop(tabel.baris, kelurahanCode: kelurahanCode);
  final namaKolom = _namaKolom(tabel.baris.first, jumlahKolom);

  if (kolom < 0 || kolom >= jumlahKolom) {
    return BacaanBerkasNop(
      namaKolom: namaKolom,
      kolomNop: -1,
      peringatan: tabel.peringatan,
      errorMessage:
          'Tidak ada kolom di "$namaBerkas" yang isinya terbaca sebagai NOP. '
          'Pilih kolomnya sendiri, atau pastikan berkasnya memuat NOP 18 angka.',
    );
  }

  final baris = <BarisBerkasNop>[];
  for (var i = 0; i < tabel.baris.length; i++) {
    final row = tabel.baris[i];
    final asli = kolom < row.length ? row[kolom].trim() : '';
    if (asli.isEmpty) continue;
    final satu = uraikanSatuNop(asli, kelurahanCode: kelurahanCode);
    baris.add(
      BarisBerkasNop(
        nomorBaris: i + 1,
        asli: asli,
        nop: satu.nop,
        alasan: satu.alasan,
        dariSingkatan: satu.dariSingkatan,
      ),
    );
  }

  return BacaanBerkasNop(
    namaKolom: namaKolom,
    kolomNop: kolom,
    baris: baris,
    peringatan: tabel.peringatan,
  );
}

/// Label kolom: pakai baris pertama sebagai judul hanya kalau baris itu memang
/// terlihat seperti judul (ada sel yang bukan angka). Kalau baris pertama sudah
/// berisi data, labelnya jadi "Kolom 1" dst. supaya tidak ada data yang
/// tersamar jadi judul.
List<String> _namaKolom(List<String> barisPertama, int jumlahKolom) {
  // Ada huruf = baris judul. Sengaja tidak memakai "bukan angka murni":
  // nominal seperti "87,453" juga bukan angka murni, dan baris data pertama
  // yang tersamar jadi judul berarti satu NOP hilang tanpa jejak.
  final terlihatJudul = barisPertama.any(
    (c) => RegExp(r'[A-Za-z]').hasMatch(c),
  );
  return [
    for (var i = 0; i < jumlahKolom; i++)
      terlihatJudul &&
              i < barisPertama.length &&
              barisPertama[i].trim().isNotEmpty
          ? '${i + 1}. ${barisPertama[i].trim()}'
          : 'Kolom ${i + 1}',
  ];
}

class _Tabel {
  final List<List<String>> baris;
  final List<String> peringatan;
  final String? error;

  const _Tabel({this.baris = const [], this.peringatan = const [], this.error});
}

_Tabel _bacaTabel(String namaBerkas, Uint8List bytes) {
  final lower = namaBerkas.toLowerCase();
  try {
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls'))
      return _bacaExcel(bytes);
    if (lower.endsWith('.csv')) return _bacaCsv(bytes);
    if (lower.endsWith('.txt')) return _bacaTeks(bytes);
    return _Tabel(
      error:
          'Format berkas "$namaBerkas" belum didukung. Pakai CSV, Excel (.xlsx/.xls), atau teks (.txt).',
    );
  } on Exception catch (e) {
    return _Tabel(error: 'Berkas "$namaBerkas" gagal dibaca: $e');
  }
}

/// Bersihkan BOM UTF-8 di awal berkas — Excel selalu menaruhnya saat menyimpan
/// CSV, dan kalau dibiarkan ia menempel ke sel pertama sehingga judul kolom
/// "NOP" tidak pernah cocok.
String _keTeks(Uint8List bytes) {
  final teks = utf8.decode(bytes, allowMalformed: true);
  return teks.startsWith('﻿') ? teks.substring(1) : teks;
}

_Tabel _bacaCsv(Uint8List bytes) {
  // autoDetect menangani pemisah koma maupun titik koma — Excel berbahasa
  // Indonesia menyimpan CSV dengan titik koma.
  final rows = Csv().decode(_keTeks(bytes));
  return _Tabel(
    baris: [
      for (final row in rows.take(maksBarisBerkas))
        [for (final sel in row) '${sel ?? ''}'.trim()],
    ],
  );
}

_Tabel _bacaTeks(Uint8List bytes) {
  final baris = <List<String>>[];
  for (final l in _keTeks(bytes).split(RegExp(r'[\r\n]+'))) {
    if (l.trim().isEmpty) continue;
    baris.add([for (final sel in l.split(RegExp(r'[;,\t]'))) sel.trim()]);
    if (baris.length >= maksBarisBerkas) break;
  }
  return _Tabel(baris: baris);
}

_Tabel _bacaExcel(Uint8List bytes) {
  final workbook = Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) {
    return const _Tabel(
      error: 'Berkas Excel ini tidak punya lembar kerja yang bisa dibaca.',
    );
  }
  final sheet = workbook.tables[workbook.tables.keys.first]!;

  var adaAngkaPresisiHilang = false;
  final baris = <List<String>>[];
  for (final row in sheet.rows.take(maksBarisBerkas)) {
    baris.add([
      for (final sel in row) ...[
        () {
          final nilai = sel?.value;
          // Angka pecahan di atas 1e15 sudah melewati batas bilangan bulat yang
          // bisa disimpan tepat oleh Excel maupun oleh tipe double. NOP 18 angka
          // ada di rentang itu, jadi kalau sampai ketemu, digit belakangnya
          // patut dicurigai sudah berubah.
          if (nilai is DoubleCellValue && nilai.value.abs() >= 1e15) {
            adaAngkaPresisiHilang = true;
          }
          return _selKeTeks(nilai);
        }(),
      ],
    ]);
  }

  return _Tabel(
    baris: baris,
    peringatan: [
      if (adaAngkaPresisiHilang)
        'Berkas Excel ini menyimpan sebagian NOP sebagai ANGKA, bukan teks. Excel hanya menyimpan '
            '15 angka pertama dengan tepat, jadi digit belakang NOP 18 angka bisa sudah berubah di '
            'berkasnya. Periksa daftar di bawah sebelum mengirim, atau simpan ulang kolom NOP '
            'sebagai Teks (atau pakai CSV).',
    ],
  );
}

String _selKeTeks(CellValue? nilai) {
  switch (nilai) {
    case null:
      return '';
    case TextCellValue():
      return nilai.value.toString().trim();
    case IntCellValue():
      return nilai.value.toString();
    case DoubleCellValue():
      // toString() pada double besar berubah jadi notasi ilmiah
      // ("3.2052e+17"); kalau itu dibersihkan dari non-angka, hasilnya jadi
      // deretan digit yang bukan NOP. Bilangan bulat ditulis penuh.
      final v = nilai.value;
      return v == v.roundToDouble() && v.abs() < 1e21
          ? v.toStringAsFixed(0)
          : v.toString();
    default:
      return nilai.toString().trim();
  }
}

/// Nasib satu NOP setelah dikirim ke server.
enum StatusImporNop {
  /// Ketemu, belum bayar, masuk jadi anggota grup.
  ditambahkan,

  /// Ketemu tapi tagihannya sudah lunas, jadi tidak dimasukkan.
  sudahBayar,

  /// Tidak ada di data server, jadi tidak dimasukkan.
  tidakDitemukan,

  /// Server menjawab hal lain. TIDAK dipaksa masuk salah satu golongan di atas
  /// — pesan aslinya ditampilkan apa adanya, karena menebak di sini berarti
  /// memberi tahu pengguna sesuatu yang belum tentu benar tentang data pajak.
  perluDiperiksa,
}

/// Frasa yang menandai tagihannya sudah lunas.
const _frasaSudahBayar = [
  'sudah bayar',
  'sudah di bayar',
  'sudah dibayar',
  'sudah terbayar',
  'sudah melakukan pembayaran',
  'telah dibayar',
  'telah bayar',
  'lunas',
];

/// Frasa yang menandai NOP-nya tidak ada di data server.
const _frasaTidakDitemukan = [
  'tidak ditemukan',
  'tidak terdaftar',
  'tidak dikenali',
  'tidak valid',
  'nop salah',
  'not found',
];

/// Golongkan jawaban server untuk SATU NOP.
///
/// Yang tidak cocok dengan frasa mana pun sengaja jatuh ke
/// [StatusImporNop.perluDiperiksa] berikut pesan aslinya, bukan dipaksa masuk
/// "sudah bayar" atau "tidak ditemukan". Daftar frasa ini disusun dari
/// dugaan atas bahasa sistem aslinya, jadi salah golong sangat mungkin —
/// dan salah golong yang diam-diam lebih berbahaya daripada satu golongan
/// tambahan yang isinya apa adanya.
StatusImporNop klasifikasiHasilTambahNop({
  required bool success,
  String? pesan,
}) {
  if (success) return StatusImporNop.ditambahkan;
  final teks = (pesan ?? '').toLowerCase();
  if (teks.isEmpty) return StatusImporNop.perluDiperiksa;
  if (_frasaTidakDitemukan.any(teks.contains))
    return StatusImporNop.tidakDitemukan;
  if (_frasaSudahBayar.any(teks.contains)) return StatusImporNop.sudahBayar;
  return StatusImporNop.perluDiperiksa;
}

/// Nasib satu NOP dalam sekali unggah.
class ItemImporNop {
  final String nop;
  final StatusImporNop status;

  /// Pesan server apa adanya — ikut disimpan bahkan untuk yang sudah tergolong,
  /// supaya kalau penggolongannya meleset, isinya masih bisa dilihat.
  final String? pesan;

  const ItemImporNop({required this.nop, required this.status, this.pesan});
}

/// Ringkasan sekali unggah.
class HasilImporNop {
  final List<ItemImporNop> item;

  /// Dihentikan pengguna di tengah jalan.
  final bool dibatalkan;

  /// Terisi kalau prosesnya berhenti karena masalah yang membuat sisa NOP tidak
  /// jadi dikirim sama sekali (sesi habis, jaringan putus berulang).
  final String? errorFatal;

  const HasilImporNop({
    this.item = const [],
    this.dibatalkan = false,
    this.errorFatal,
  });

  List<ItemImporNop> ofStatus(StatusImporNop s) =>
      item.where((i) => i.status == s).toList();

  List<ItemImporNop> get ditambahkan => ofStatus(StatusImporNop.ditambahkan);
  List<ItemImporNop> get sudahBayar => ofStatus(StatusImporNop.sudahBayar);
  List<ItemImporNop> get tidakDitemukan =>
      ofStatus(StatusImporNop.tidakDitemukan);
  List<ItemImporNop> get perluDiperiksa =>
      ofStatus(StatusImporNop.perluDiperiksa);
}
