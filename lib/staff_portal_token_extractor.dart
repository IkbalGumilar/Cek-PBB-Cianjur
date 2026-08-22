/// Fungsi murni untuk menggali token `q`/`funcMode`/`userID` yang disisipkan
/// server ke dalam HTML halaman Portal Staf — sengaja dipisah dari
/// [StaffPortalClient] (yang perlu koneksi jaringan) supaya bisa dites
/// langsung pakai potongan HTML asli tanpa perlu login sungguhan. Lihat
/// `test/staff_portal_token_extractor_test.dart`, yang menjalankan fungsi
/// ini terhadap `test/fixtures/*.html` — potongan HTML asli yang dikirim
/// pengguna, bukan rekaan.
class StaffPortalTokenExtractor {
  const StaffPortalTokenExtractor._();

  /// Cari `main.php?q=XXXX` di dalam body fungsi JavaScript [jsFunctionName]
  /// — dipakai fungsi-fungsi yang memuat hasil lewat `.load("main.php?q=...")`
  /// (semua tab Monitoring Wilayah). Default [window] punya margin longgar —
  /// diuji lewat fixture asli, `showModelRealisasi1` misalnya baru menaruh
  /// token-nya di karakter ke-2041 dari awal fungsi karena banyak deklarasi
  /// variabel & validasi sebelum baris `.load(...)`.
  static String? extractLoadQ(String html, String jsFunctionName, {int window = 3000}) {
    final name = RegExp.escape(jsFunctionName);
    final match = RegExp(
      'function\\s+$name\\s*\\([^)]*\\)[\\s\\S]{0,$window}?main\\.php\\?q=([A-Za-z0-9+/=]+)',
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Cari token `funcMode` di dalam body fungsi JavaScript [jsFunctionName].
  /// Halaman aslinya menyisipkan `funcMode` dengan TIGA sintaks JS berbeda
  /// tergantung fungsinya (dibuktikan lewat fixture asli, lihat
  /// test/staff_portal_token_extractor_test.dart):
  ///   - object literal:  `funcMode: 'XXXX'`      (dipakai tab Monitoring Wilayah)
  ///   - var assignment:  `var funcMode = 'XXXX'`  (dipakai `reloadDataGroup` Kolektif)
  ///   - string concat:   `"&funcMode=" + 'XXXX'`  (dipakai `showBank`)
  /// Ketiganya dicoba lewat satu pola gabungan.
  static String? extractFuncMode(String html, String jsFunctionName, {int window = 4000}) {
    final name = RegExp.escape(jsFunctionName);
    final match = RegExp(
      "function\\s+$name\\s*\\([^)]*\\)[\\s\\S]{0,$window}?(?:funcMode\\s*[:=]\\s*|\"&funcMode=\"\\s*\\+\\s*)'([^']+)'",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Cari nilai `var q = 'XXXX';` global — dipakai halaman Pembayaran
  /// Kolektif, yang menaruh token `q` sekali di scope global (bukan di
  /// dalam body tiap fungsi seperti Monitoring Wilayah).
  static String? extractGlobalQ(String html) {
    final match = RegExp(r"var\s+q\s*=\s*'([^']+)'").firstMatch(html);
    return match?.group(1);
  }

  /// Cari `userID=XXXX` yang disisipkan server ke URL ajax DataTables
  /// (`main.php?userID=XXXX&bulan=...`) di halaman Pembayaran Kolektif.
  static String? extractKolektifUserId(String html) {
    final match = RegExp(r'main\.php\?userID=([^&"]+)&bulan=').firstMatch(html);
    return match?.group(1);
  }

  /// Token milik `tambahGroup()` — aksi BUAT grup kolektif.
  ///
  /// Sengaja TIDAK memakai [extractFuncMode], dan ini bukan sekadar soal
  /// kerapian: di halaman aslinya `tambahGroup()` menyimpan tokennya pada
  /// variabel bernama `funMode` (tanpa "c" — typo di sistem sumbernya),
  /// sedangkan `function finalkan()` berada persis SESUDAHNYA dan memakai
  /// `var funcMode`. Pola umum yang menyapu 4000 karakter dari awal fungsi
  /// akan melewati batas `tambahGroup()` lalu menangkap token Finalkan.
  /// Salah token di sini bukan sekadar gagal — Finalkan mengunci grup dan
  /// memicu pembuatan kode bayar sungguhan di server pemda, yang tidak bisa
  /// dibatalkan. Karena itu polanya dikunci ke nama variabel `funMode`,
  /// jendelanya dipersempit, dan baris `data:` pengirimnya wajib ikut cocok
  /// sebagai bukti bahwa token yang terambil memang milik fungsi ini.
  /// Kalau halaman berubah bentuk, hasilnya `null` (aksi dibatalkan), bukan
  /// token yang salah.
  static String? extractTambahGroupFuncMode(String html) {
    final match = RegExp(
      r"""function\s+tambahGroup\s*\([^)]*\)\s*\{[\s\S]{0,2000}?var\s+funMode\s*=\s*'([^']+)'\s*;[\s\S]{0,600}?data\s*:\s*data\s*\+\s*"&funcMode="\s*\+\s*funMode""",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Token milik handler tombol `#btn-confirm-delete-group` — aksi HAPUS grup
  /// kolektif. Tokennya tidak berada di dalam sebuah `function` bernama
  /// (melainkan di dalam handler `$(document).on("click", ...)`), jadi
  /// [extractFuncMode] tidak bisa dipakai sama sekali.
  ///
  /// Di atas handler ini ada dua handler lain yang bentuknya nyaris identik
  /// (`.btn-return` = kembalikan ke draft, `.btn-reaktivasi` = aktifkan ulang)
  /// yang sama-sama mengirim `q`+`id`+`funcMode`. Untuk memastikan tidak
  /// tertukar, baris `data:` pengirimnya wajib ikut cocok — hanya aksi hapus
  /// yang membawa parameter `&alasan=`.
  static String? extractHapusGroupFuncMode(String html) {
    final match = RegExp(
      r"""on\s*\(\s*"click"\s*,\s*"#btn-confirm-delete-group"[\s\S]{0,1500}?var\s+funcMode\s*=\s*'([^']+)'\s*;[\s\S]{0,600}?data\s*:\s*"q="\s*\+\s*q\s*\+\s*"&id="\s*\+\s*group_id\s*\+\s*"&alasan="\s*\+\s*encodeURIComponent""",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Token milik `getGroupData()` — daftar anggota (NOP) sebuah grup.
  /// Baris `"ajax"` pengirimnya ikut dicocokkan supaya tidak tertukar dengan
  /// `getGroupDataByID()` (data grup, bukan anggotanya) yang ada sesudahnya.
  static String? extractListAnggotaFuncMode(String html) {
    final match = RegExp(
      r"""function\s+getGroupData\s*\([^)]*\)\s*\{[\s\S]{0,1500}?var\s+funcMode\s*=\s*'([^']+)'\s*;[\s\S]{0,600}?"ajax"\s*:\s*"main\.php\?status="\s*\+\s*status\s*\+\s*"&group_id="\s*\+\s*group_id""",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Token milik `cariNOP()` — aksi TAMBAH NOP ke dalam grup.
  ///
  /// Persis sebelum fungsi ini ada `cariNOPCSV()` yang badannya nyaris sama
  /// (juga `var funcMode` lalu `data: data+"&funcMode="+funcMode`), bedanya
  /// dia mengunggah berkas CSV. Pola di bawah tidak bisa keliru menangkapnya
  /// karena `cariNOP\s*\(` tidak cocok dengan `cariNOPCSV(`.
  static String? extractCariNopFuncMode(String html) {
    final match = RegExp(
      r"""function\s+cariNOP\s*\([^)]*\)\s*\{[\s\S]{0,2500}?var\s+funcMode\s*=\s*'([^']+)'\s*;[\s\S]{0,600}?data\s*:\s*data\s*\+\s*"&funcMode="\s*\+\s*funcMode""",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Token milik handler `#btn-delete-all` — aksi HAPUS NOP terpilih dari grup.
  ///
  /// Tepat sesudahnya ada `#btn-delete-all-temp` yang badannya nyaris sama.
  /// Dua pengaman dipakai sekaligus: tanda kutip penutup pada
  /// `"#btn-delete-all"` (jadi tidak cocok dengan `"#btn-delete-all-temp"`),
  /// dan baris `data:` pengirimnya — hanya handler yang benar yang ikut
  /// menyertakan `funcMode` di dalam objek datanya.
  static String? extractHapusAnggotaFuncMode(String html) {
    final match = RegExp(
      r"""on\s*\(\s*"click"\s*,\s*"#btn-delete-all"[\s\S]{0,1500}?var\s+funcMode\s*=\s*'([^']+)'\s*;[\s\S]{0,600}?data\s*:\s*\{\s*data\s*:\s*data\s*,\s*funcMode\s*:\s*funcMode""",
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Kode kecamatan milik akun yang login, dari `var myKecamatan = 'XXXX';`
  /// yang disisipkan server ke dalam `showKecamatanAll()`. Diambil dari sini
  /// (bukan dari `<option>` dropdown) karena isi dropdown Kecamatan diganti
  /// oleh ajax saat halaman dibuka di browser — jadi di HTML mentah yang
  /// kita terima dropdown itu belum tentu terisi, sedangkan baris JS ini
  /// selalu apa adanya dari server.
  static String? extractKolektifKecamatanCode(String html) {
    final match = RegExp(r"var\s+myKecamatan\s*=\s*'([^']*)'").firstMatch(html);
    final value = match?.group(1);
    return (value == null || value.isEmpty) ? null : value;
  }
}
