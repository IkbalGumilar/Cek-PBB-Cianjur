import 'nop_helper.dart';

/// Satu baris data pembayaran yang tersimpan lokal di "Buku Catatan Blok",
/// diisi otomatis tiap kali Cek Status Bayar (satuan atau massal) menemukan
/// status "Sudah Bayar" untuk sebuah NOP+tahun.
class BlokRecord {
  final String nop;
  final String namaWajibPajak;
  final String tahunBayar;
  final String tanggalBayar;
  final String jumlahPbb;

  const BlokRecord({
    required this.nop,
    required this.namaWajibPajak,
    required this.tahunBayar,
    required this.tanggalBayar,
    this.jumlahPbb = '',
  });

  String get blok => nopBlok(nop);
  String get wilayah => nopWilayah(nop);

  /// Nilai numerik dari [jumlahPbb] (mis. "Rp. 51.425" -> 51425), dipakai
  /// untuk mengurutkan berdasarkan jumlah bayar PBB.
  int get jumlahPbbValue =>
      int.tryParse(jumlahPbb.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// NOP+tahun mengidentifikasi satu baris pembayaran secara unik (satu NOP
  /// bisa punya beberapa baris untuk tahun yang berbeda-beda).
  String get uniqueKey => '$nop|$tahunBayar';
}

enum BlokSortBy {
  blokWilayah('Blok & Nomor Wilayah'),
  nama('Nama'),
  jumlahBayar('Jumlah Bayar PBB');

  final String label;

  const BlokSortBy(this.label);
}

/// Urutan blok(asc) lalu nomor wilayah(asc) — dipakai sebagai urutan baku
/// tetap untuk data yang dicetak/diunduh, apa pun filter urutan yang sedang
/// dipakai untuk tampilan di layar.
int compareBlokWilayah(BlokRecord a, BlokRecord b) {
  final blokCompare = a.blok.compareTo(b.blok);
  if (blokCompare != 0) return blokCompare;
  return a.wilayah.compareTo(b.wilayah);
}

List<BlokRecord> sortBlokRecords(List<BlokRecord> records, BlokSortBy sortBy) {
  final sorted = List<BlokRecord>.from(records);
  switch (sortBy) {
    case BlokSortBy.blokWilayah:
      sorted.sort(compareBlokWilayah);
    case BlokSortBy.nama:
      sorted.sort((a, b) => a.namaWajibPajak.compareTo(b.namaWajibPajak));
    case BlokSortBy.jumlahBayar:
      sorted.sort((a, b) => b.jumlahPbbValue.compareTo(a.jumlahPbbValue));
  }
  return sorted;
}

/// Format angka dengan pemisah ribuan titik ala Indonesia (mis. 51425 ->
/// "51.425"), dipakai untuk menampilkan Total Jumlah PBB di Buku Catatan Blok.
String formatRibuan(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
