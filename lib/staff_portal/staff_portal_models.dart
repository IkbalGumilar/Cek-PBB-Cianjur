class StaffLoginResult {
  final bool needsMfa;
  final String? errorMessage;

  const StaffLoginResult({required this.needsMfa, this.errorMessage});
}

class StaffMfaResult {
  final bool success;
  final String? errorMessage;

  const StaffMfaResult({required this.success, this.errorMessage});
}

/// Ringkasan angka (KPI/Totals) yang dikembalikan oleh tab Monitoring Wilayah
/// (Jumlah OP, Pokok Ketetapan, Pokok Pembayaran, Denda, Total Penerimaan / Realisasi).
class MonitoringSummaryTotals {
  final int jumlahOp;
  final int pokokKetetapan;
  final int pokokPembayaran;
  final int denda;
  final int totalPenerimaan;

  const MonitoringSummaryTotals({
    this.jumlahOp = 0,
    this.pokokKetetapan = 0,
    this.pokokPembayaran = 0,
    this.denda = 0,
    this.totalPenerimaan = 0,
  });

  bool get isEmpty =>
      jumlahOp == 0 &&
      pokokKetetapan == 0 &&
      pokokPembayaran == 0 &&
      denda == 0 &&
      totalPenerimaan == 0;

  bool get isNotEmpty => !isEmpty;
}

/// Hasil tabel generik dari salah satu tab Monitoring Wilayah — kolomnya
/// tidak di-hardcode karena belum ada contoh isi asli untuk dicocokkan;
/// [headers] & [rows] mengikuti apa pun yang benar-benar dikembalikan server.
class MonitoringTableResult {
  final List<String> headers;
  final List<List<String>> rows;
  final String? errorMessage;
  final MonitoringSummaryTotals? summary;
  final int totalRecords;
  final int pageStart;
  final int pageEnd;
  final bool hasNextPage;

  const MonitoringTableResult({
    this.headers = const [],
    this.rows = const [],
    this.errorMessage,
    this.summary,
    this.totalRecords = 0,
    this.pageStart = 0,
    this.pageEnd = 0,
    this.hasNextPage = false,
  });
}

/// Satu baris dalam daftar antrean ekspor Excel di server V-Tax.
class MonitoringExcelQueueItem {
  final String no;
  final String tanggal;
  final String filterSummary;
  final bool isProcessing;
  final String? downloadUrl;
  final String? fileName;
  final String? hapusId;

  const MonitoringExcelQueueItem({
    required this.no,
    required this.tanggal,
    required this.filterSummary,
    required this.isProcessing,
    this.downloadUrl,
    this.fileName,
    this.hapusId,
  });
}

class MonitoringExcelQueueResult {
  final List<MonitoringExcelQueueItem> items;
  final String? paginationText;
  final String? errorMessage;

  const MonitoringExcelQueueResult({
    this.items = const [],
    this.paginationText,
    this.errorMessage,
  });
}

/// Satu opsi pada dropdown filter Bank (dimuat dinamis dari server, bukan
/// nilai tetap — daftar bank bisa berubah).
class BankOption {
  final String id;
  final String name;

  const BankOption({required this.id, required this.name});
}

/// Satu baris grup pada modul Pembayaran Kolektif (`m179`) — BEDA modul dari
/// Monitoring Wilayah (`mMonitoringWilayahV3`). Yang bisa diubah dari sini
/// hanya BUAT grup, HAPUS grup, dan FINALKAN grup; Generate VA sengaja tidak
/// dibuat karena membuat kode bayar sungguhan.
class KolektifGroup {
  /// `CPM_CG_ID` dari kolom Aksi — wajib untuk aksi hapus.
  final String id;
  final String namaGroup;
  final String namaKolektor;
  final String hpKolektor;
  final String anggota;
  final String kodeBayar;
  final String status;
  final String kecamatan;
  final String kelurahan;

  /// Kode kelurahan (`CPM_CG_AREA_CODE`). Server menaruhnya di kolom yang sama
  /// dengan nama kelurahan, di dalam `<div class="kd-kel">` yang disembunyikan
  /// — dan halaman aslinya memang mengambilnya dari situ saat membuka Kelola
  /// Member. Dibutuhkan untuk menambah NOP ke grup ini.
  final String kelurahanCode;

  final String keterangan;
  final String tanggalKadaluarsa;

  /// Kode status mentah (`0` Draft, `1` Siap Dibayar, `2` Sudah Di Bayar,
  /// `99` Expired) — dipakai untuk menjelaskan ke staf kenapa sebuah grup
  /// tidak bisa dihapus.
  final String statusCode;

  /// Apakah server sendiri menampilkan tombol "Hapus Group" untuk baris ini.
  final bool canDelete;

  /// Apakah server merender tombol "Ubah Data Group" (ikon pensil) untuk baris
  /// ini — di sana muncul pada kondisi yang sama dengan tombol hapus.
  final bool canEdit;

  /// Apakah server merender tombol "Cetak Surat Pengantar" (ikon buku) —
  /// hanya untuk grup yang sudah final atau sudah dibayar, karena suratnya
  /// memuat kode bayar.
  final bool canPrintSurat;

  const KolektifGroup({
    required this.id,
    required this.namaGroup,
    required this.namaKolektor,
    required this.hpKolektor,
    required this.anggota,
    required this.kodeBayar,
    required this.status,
    required this.kecamatan,
    required this.kelurahan,
    required this.kelurahanCode,
    required this.keterangan,
    required this.tanggalKadaluarsa,
    required this.statusCode,
    required this.canDelete,
    required this.canEdit,
    required this.canPrintSurat,
  });
}

class KolektifListResult {
  final List<KolektifGroup> groups;
  final String? errorMessage;

  const KolektifListResult({this.groups = const [], this.errorMessage});
}

/// Server menuliskan sebagian nama wilayah dengan spasi di antara tiap huruf
/// ("M A N D E", "J A M A L I"). Kalau SEMUA potongannya satu huruf, spasinya
/// dirapatkan supaya terbaca wajar; nama yang memang bersuku kata banyak
/// ("CIKIDANGBAYABANG") dibiarkan apa adanya.
String rapikanNamaWilayah(String nama) {
  final potongan = nama
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (potongan.length > 1 && potongan.every((p) => p.length == 1)) {
    return potongan.join();
  }
  return nama.trim();
}

/// Ubah angka rupiah kiriman server jadi bilangan bulat.
///
/// Server menulisnya bergaya Inggris — koma sebagai pemisah ribuan dan titik
/// sebagai desimal ("87,453", "590,540.00"). Kalau semua tanda baca dibuang
/// begitu saja, "590,540.00" akan terbaca 59054000, yaitu seratus kali lipat.
/// Jadi koma dibuang lebih dulu, lalu bagian di belakang titik dipotong.
int parseAngkaServer(String raw) {
  var s = raw.trim();
  // Jika di ujung ada 2 digit desimal (mis. .00 atau ,00 atau .50), buang bagian desimalnya.
  if (RegExp(r'[,.][0-9]{2}$').hasMatch(s)) {
    s = s.substring(0, s.length - 3);
  }
  final bersih = s.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(bersih) ?? 0;
}

/// Satu anggota (satu NOP untuk satu tahun pajak) di dalam grup kolektif.
/// [nop] + [tahunPajak] adalah pasangan yang dipakai server untuk menghapus
/// anggota, jadi keduanya diambil dari atribut checkbox yang dirender server
/// (bukan dari teks kolomnya) supaya persis sama dengan yang halaman aslinya
/// kirim.
class KolektifMember {
  final String nop;
  final String tahunPajak;
  final String jatuhTempo;
  final String namaWp;
  final String kecamatan;
  final String kelurahan;
  final String pokok;
  final String denda;
  final String total;

  const KolektifMember({
    required this.nop,
    required this.tahunPajak,
    required this.jatuhTempo,
    required this.namaWp,
    required this.kecamatan,
    required this.kelurahan,
    required this.pokok,
    required this.denda,
    required this.total,
  });

  /// Kunci unik satu baris — satu NOP bisa muncul lebih dari sekali dengan
  /// tahun pajak berbeda (tagihan tahun-tahun sebelumnya), jadi NOP saja
  /// tidak cukup untuk membedakan baris.
  String get kunci => '$nop|$tahunPajak';
}

class KolektifMemberListResult {
  final List<KolektifMember> members;
  final String? errorMessage;

  const KolektifMemberListResult({this.members = const [], this.errorMessage});

  /// Total seluruh anggota — halaman aslinya juga menghitung ini sendiri di
  /// kaki tabel (`footerCallback`), bukan mengambilnya dari server.
  int get totalPokok =>
      members.fold(0, (a, m) => a + parseAngkaServer(m.pokok));
  int get totalDenda =>
      members.fold(0, (a, m) => a + parseAngkaServer(m.denda));
  int get totalBayar =>
      members.fold(0, (a, m) => a + parseAngkaServer(m.total));
}

/// Satu pilihan kelurahan pada form Tambah Group.
class KolektifKelurahan {
  final String code;
  final String name;

  const KolektifKelurahan({required this.code, required this.name});
}

/// Wilayah yang boleh dipakai akun ini saat membuat grup, digali dari halaman
/// aslinya (bukan daftar bawaan aplikasi) supaya selalu ikut hak akses akun.
class KolektifFormOptions {
  final String kecamatanCode;
  final String kecamatanName;
  final List<KolektifKelurahan> kelurahan;
  final String? errorMessage;
  final bool bisaTambah;
  final bool bisaHapus;

  const KolektifFormOptions({
    this.kecamatanCode = '',
    this.kecamatanName = '',
    this.kelurahan = const [],
    this.errorMessage,
    this.bisaTambah = false,
    this.bisaHapus = false,
  });
}

/// Hasil aksi yang MENGUBAH data di server pemda (buat/hapus grup).
class KolektifActionResult {
  final bool success;
  final String? message;
  final String? rawBody;
  final bool responsDikenali;

  const KolektifActionResult({
    required this.success,
    this.message,
    this.rawBody,
    this.responsDikenali = true,
  });
}
