import 'currency_format.dart';
import 'nop_helper.dart';

export 'currency_format.dart'
    show formatRibuan, parseNominalRupiah, cleanNominalRupiah;

/// Satu baris data pembayaran yang tersimpan lokal di "Buku Catatan Blok",
/// diisi otomatis tiap kali Cek Status Bayar (satuan atau massal) menemukan
/// status "Sudah Bayar" untuk sebuah NOP+tahun.
class BlokRecord {
  final String nop;
  final String namaWajibPajak;
  final String tahunBayar;
  final String tanggalBayar;
  final String jumlahPbb;
  final String statusBayar;
  final String? namaFoto;
  final bool isTargetPemda;
  final String catatan;

  // Data rincian objek & pembayaran (sesuai lembar printout Bapenda)
  final String luasBumi;
  final String luasBangunan;
  final String njopBumi;
  final String njopBangunan;
  final String kecamatan;
  final String kelurahan;
  final String alamatObjek;
  final String alamatWp;
  final String rtObjek;

  const BlokRecord({
    required this.nop,
    required this.namaWajibPajak,
    required this.tahunBayar,
    required this.tanggalBayar,
    this.jumlahPbb = '',
    this.statusBayar = 'Sudah Bayar',
    this.namaFoto,
    this.isTargetPemda = false,
    this.catatan = '',
    this.luasBumi = '',
    this.luasBangunan = '',
    this.njopBumi = '',
    this.njopBangunan = '',
    this.kecamatan = 'MANDE',
    this.kelurahan = 'BOBOJONG',
    this.alamatObjek = '',
    this.alamatWp = '',
    this.rtObjek = '',
  });

  bool get isPaid =>
      statusBayar.toLowerCase().contains('sudah') ||
      statusBayar.toLowerCase().contains('lunas') ||
      tanggalBayar.isNotEmpty;

  bool get isBlacklist =>
      !isPaid &&
      (statusBayar.toLowerCase().contains('black') ||
          statusBayar.toLowerCase().contains('daftar hitam') ||
          statusBayar.toLowerCase().contains('hitam'));

  bool get hasPhoto => namaFoto != null && namaFoto!.trim().isNotEmpty;

  String get blok => nopBlok(nop);
  String get wilayah => nopWilayah(nop);
  String get formattedNop => formatNop(nop);

  /// Nilai numerik dari [jumlahPbb] (mis. "Rp. 51.425" -> 51425, "51.245,00" -> 51245),
  /// dipakai untuk kalkulasi total dan pengurutan nominal PBB.
  int get jumlahPbbValue => parseNominalRupiah(jumlahPbb);

  /// NOP+tahun mengidentifikasi satu baris pembayaran secara unik (satu NOP
  /// bisa punya beberapa baris untuk tahun yang berbeda-beda).
  String get uniqueKey => '$nop|$tahunBayar';

  BlokRecord copyWith({
    String? nop,
    String? namaWajibPajak,
    String? tahunBayar,
    String? tanggalBayar,
    String? jumlahPbb,
    String? statusBayar,
    String? namaFoto,
    bool? isTargetPemda,
    String? catatan,
    String? luasBumi,
    String? luasBangunan,
    String? njopBumi,
    String? njopBangunan,
    String? kecamatan,
    String? kelurahan,
    String? alamatObjek,
    String? alamatWp,
    String? rtObjek,
  }) {
    return BlokRecord(
      nop: nop ?? this.nop,
      namaWajibPajak: namaWajibPajak ?? this.namaWajibPajak,
      tahunBayar: tahunBayar ?? this.tahunBayar,
      tanggalBayar: tanggalBayar ?? this.tanggalBayar,
      jumlahPbb: jumlahPbb ?? this.jumlahPbb,
      statusBayar: statusBayar ?? this.statusBayar,
      namaFoto: namaFoto ?? this.namaFoto,
      isTargetPemda: isTargetPemda ?? this.isTargetPemda,
      catatan: catatan ?? this.catatan,
      luasBumi: luasBumi ?? this.luasBumi,
      luasBangunan: luasBangunan ?? this.luasBangunan,
      njopBumi: njopBumi ?? this.njopBumi,
      njopBangunan: njopBangunan ?? this.njopBangunan,
      kecamatan: kecamatan ?? this.kecamatan,
      kelurahan: kelurahan ?? this.kelurahan,
      alamatObjek: alamatObjek ?? this.alamatObjek,
      alamatWp: alamatWp ?? this.alamatWp,
      rtObjek: rtObjek ?? this.rtObjek,
    );
  }
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

const Map<String, String> _bulanIndo = {
  '01': 'Januari',
  '02': 'Februari',
  '03': 'Maret',
  '04': 'April',
  '05': 'Mei',
  '06': 'Juni',
  '07': 'Juli',
  '08': 'Agustus',
  '09': 'September',
  '10': 'Oktober',
  '11': 'November',
  '12': 'Desember',
};

/// Format standar catatan resmi pelunasan:
/// "Sudah bayar tanggal [hari] bulan [bulan] [tahun] jam [jam]"
String formatCatatanSudahBayar(String tglBayar, [String? tahunBayar]) {
  final t = tglBayar.trim();
  if (t.isEmpty || t == '0') {
    return tahunBayar != null && tahunBayar.isNotEmpty
        ? 'Sudah bayar tahun $tahunBayar'
        : 'Sudah bayar';
  }
  final parts = t.split(' ');
  final dateParts = parts[0].split('-');
  if (dateParts.length == 3) {
    final y = dateParts[0];
    final m = dateParts[1];
    final d = int.tryParse(dateParts[2])?.toString() ?? dateParts[2];
    final namaBulan = _bulanIndo[m] ?? m;
    final timePart = parts.length > 1 ? parts[1].trim() : '';
    if (timePart.isNotEmpty && timePart != '00:00:00') {
      return 'Sudah bayar tanggal $d bulan $namaBulan $y jam $timePart';
    } else if (timePart == '00:00:00') {
      return 'Sudah bayar tanggal $d bulan $namaBulan $y jam 00:00';
    } else {
      return 'Sudah bayar tanggal $d bulan $namaBulan $y';
    }
  }
  return 'Sudah bayar $t';
}

