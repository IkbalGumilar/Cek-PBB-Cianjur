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
}
