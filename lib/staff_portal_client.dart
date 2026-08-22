import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

import 'kolektif_nop_berkas.dart';
import 'staff_portal_token_extractor.dart';

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

/// Hasil tabel generik dari salah satu tab Monitoring Wilayah — kolomnya
/// tidak di-hardcode karena belum ada contoh isi asli untuk dicocokkan;
/// [headers] & [rows] mengikuti apa pun yang benar-benar dikembalikan server.
class MonitoringTableResult {
  final List<String> headers;
  final List<List<String>> rows;
  final String? errorMessage;

  const MonitoringTableResult({
    this.headers = const [],
    this.rows = const [],
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
/// hanya BUAT grup ([StaffPortalClient.createKolektifGroup]) dan HAPUS grup
/// ([StaffPortalClient.deleteKolektifGroup]); Kelola Member, Finalkan, dan
/// Generate VA sengaja tidak dibuat karena membuat kode bayar sungguhan.
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
  /// Sengaja TIDAK disimpulkan sendiri dari [statusCode]: keputusan boleh
  /// atau tidaknya menghapus ada di server (dia yang merender tombolnya),
  /// jadi aplikasi cuma ikut apa yang dia render — kalau aturannya berubah
  /// di sana, aplikasi otomatis ikut tanpa perlu diubah.
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
  if (potongan.length > 1 && potongan.every((p) => p.length == 1))
    return potongan.join();
  return nama.trim();
}

/// Ubah angka rupiah kiriman server jadi bilangan bulat.
///
/// Server menulisnya bergaya Inggris — koma sebagai pemisah ribuan dan titik
/// sebagai desimal ("87,453", "590,540.00"). Kalau semua tanda baca dibuang
/// begitu saja, "590,540.00" akan terbaca 59054000, yaitu seratus kali lipat.
/// Jadi koma dibuang lebih dulu, lalu bagian di belakang titik dipotong.
int parseAngkaServer(String raw) {
  var bersih = raw.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '');
  final titik = bersih.indexOf('.');
  if (titik >= 0) bersih = bersih.substring(0, titik);
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

  /// Nama kecamatan untuk ditampilkan. Form aslinya MENGIRIM kode
  /// (mis. `3205200`) tapi MENAMPILKAN nama — namanya diambil terpisah lewat
  /// ajax `showKecamatanAll()`. Kalau pengambilan nama gagal, dibiarkan kosong
  /// dan yang tampil kembali ke kodenya; kode itu yang tetap dikirim, jadi
  /// gagal-tidaknya pengambilan nama tidak mempengaruhi data yang tersimpan.
  final String kecamatanName;

  final List<KolektifKelurahan> kelurahan;
  final String? errorMessage;

  /// Apakah token aksi Tambah/Hapus benar-benar ketemu di halaman asli.
  ///
  /// Diperiksa lebih awal — saat menu dibuka, bukan saat tombol ditekan —
  /// karena aksi ini meninggalkan jejak permanen di server: lebih baik
  /// tombolnya mati sejak awal daripada staf sudah mengisi form, menekan
  /// Simpan, lalu baru ketahuan tokennya tidak terbaca. Pemeriksaannya
  /// sendiri tidak mengirim apa-apa, cuma membaca HTML halaman.
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
/// [rawBody] ikut disimpan supaya kalau responsnya di luar dugaan, isinya
/// bisa dibaca langsung tanpa perlu mengulang aksinya — pengulangan tidak
/// gratis, tiap percobaan tercatat permanen di log server.
class KolektifActionResult {
  final bool success;
  final String? message;
  final String? rawBody;

  /// False kalau jawaban server sama sekali bukan JSON yang dikenali —
  /// biasanya berarti sesi sudah berakhir dan yang terkirim balik adalah
  /// halaman login. Dibedakan dari "gagal biasa" karena penambahan berkas
  /// harus BERHENTI saat ini terjadi: meneruskan sisa NOP cuma menembakkan
  /// puluhan permintaan lagi ke server pemda yang semuanya akan tertolak.
  final bool responsDikenali;

  const KolektifActionResult({
    required this.success,
    this.message,
    this.rawBody,
    this.responsDikenali = true,
  });
}

/// Klien HTTP untuk portal staf `cianjurkab.v-tax.id` — BEDA dari portal
/// publik `cektagihan.cianjurkab.v-tax.id` yang dipakai [PbbClient] (yang itu
/// tidak butuh login sama sekali). Portal ini pakai alur login klasik:
/// username + password + captcha, lalu verifikasi MFA (kode Google
/// Authenticator) sebelum sesi dianggap masuk.
///
/// Deteksi sukses (redirect ke/dari mfa.php) sudah pasti sesuai halaman HTML
/// yang jadi acuan. Deteksi pesan GAGAL (password salah, captcha salah, OTP
/// salah) baru best-effort — belum ada contoh halaman gagal asli untuk
/// dicocokkan, jadi kemungkinan perlu disesuaikan lagi setelah dites nyata.
///
/// Tab-tab Monitoring Wilayah (lihat [fetchSudahBayar] dst.) sudah dicocokkan
/// field-per-field dengan HTML halaman aslinya. [fetchKolektifGroups] lebih
/// spekulatif — modul itu pakai DataTables server-side (butuh parameter
/// paging/sorting standar DataTables yang di-generate otomatis oleh
/// library-nya di browser, di sini direplikasi manual tanpa contoh respons
/// JSON asli) jadi kemungkinan besar perlu penyesuaian setelah dites nyata.
class StaffPortalClient {
  static const _baseUrl = 'https://cianjurkab.v-tax.id';

  /// `param=` tetap (base64 dari `a=aPBB&m=mMonitoringWilayahV3`) untuk masuk
  /// ke modul Monitoring Wilayah — bagian ini statis, tidak terikat sesi.
  static const _monitoringParam = 'YT1hUEJCJm09bU1vbml0b3JpbmdXaWxheWFoVjM=';

  /// `param=` tetap (base64 dari `a=aPBB&m=m179`) untuk modul Pembayaran
  /// Kolektif.
  static const _kolektifParam = 'YT1hUEJCJm09bTE3OQ==';

  String? _monitoringHtml;
  String? _kolektifHtml;
  String? _pageQ23;
  List<BankOption>? _bankOptionsCache;
  bool _cookieManagerAttached = false;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      // Naik dua kali dari percobaan sebelumnya (15 -> 60 -> 120 detik).
      // Tab "Belum Bayar" cuma punya satu tanggal cutoff (bukan rentang
      // awal-akhir) — menghitung SEMUA piutang sejak awal sampai cutoff itu,
      // jadi tetap berat walau kelurahan-nya kecil; 60 detik masih kena
      // timeout saat dites nyata di tab ini.
      receiveTimeout: const Duration(seconds: 120),
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  /// Cookie sesi (mis. `PHPSESSID`) disimpan ke berkas, bukan cuma di memori
  /// — supaya sesi login yang sudah terbentuk bertahan lewat restart
  /// aplikasi, tidak perlu login + MFA ulang tiap kali. Dibuat lazy (bukan
  /// di constructor) karena butuh path direktori dari `path_provider` yang
  /// sifatnya async; constructor [StaffPortalClient] tetap sinkron supaya
  /// tidak perlu ubah cara pemanggilannya di layar-layar yang sudah ada.
  Future<void> _ensureCookieManager() async {
    if (_cookieManagerAttached) return;
    final dir = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage('${dir.path}/staff_portal_cookies'),
    );
    _dio.interceptors.add(CookieManager(jar));
    _cookieManagerAttached = true;
  }

  /// Cek apakah sesi yang tersimpan (dari login sebelumnya) masih aktif di
  /// server, tanpa perlu username/password/captcha — dipakai supaya
  /// pengguna tidak perlu login ulang tiap buka menu Monitoring kalau sesi
  /// sebelumnya belum kedaluwarsa. Deteksinya lewat penanda "sudah login"
  /// yang muncul di halaman `/main.php` (link logout) — belum ada contoh
  /// nyata sesi kedaluwarsa untuk dicocokkan, jadi kalau ternyata server
  /// menampilkan halaman lain saat sesi habis, penanda ini perlu disesuaikan.
  Future<bool> hasActiveSession() async {
    await _ensureCookieManager();
    try {
      final response = await _dio.get<String>(
        '/main.php',
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data ?? '';
      return html.contains('id="user-menu"') && html.contains('logout');
    } catch (_) {
      return false;
    }
  }

  /// Keluar dari sesi — hubungi link logout asli di server (`logout=1`) lalu
  /// hapus cookie & cache lokal, supaya panggilan [hasActiveSession]
  /// berikutnya kembali false dan layar Login Portal Staf tampil lagi.
  Future<void> logout() async {
    await _ensureCookieManager();
    try {
      await _dio.get<String>(
        '/main.php',
        queryParameters: {'param': 'bG9nb3V0PTE='},
        options: Options(responseType: ResponseType.plain),
      );
    } catch (_) {
      // Best-effort — tetap lanjut bersihkan sesi lokal walau request gagal.
    }
    for (final interceptor in _dio.interceptors) {
      if (interceptor is CookieManager) {
        await interceptor.cookieJar.deleteAll();
        break;
      }
    }
    _monitoringHtml = null;
    _kolektifHtml = null;
    _pageQ23 = null;
    _bankOptionsCache = null;
  }

  /// Ambil gambar captcha login — kunjungi halaman login dulu supaya cookie
  /// sesi tersambung ke gambar captcha yang sama yang akan diverifikasi saat
  /// submit.
  Future<Uint8List> fetchLoginCaptcha() async {
    await _ensureCookieManager();
    await _dio.get<String>(
      '/main.php',
      options: Options(responseType: ResponseType.plain),
    );
    final response = await _dio.get<List<int>>(
      '/captcha2.php',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  /// Login tahap 1 (username + password + captcha). [needsMfa] true kalau
  /// server mengarahkan ke halaman verifikasi MFA (kredensial & captcha
  /// benar) — lanjutkan ke [verifyMfa]. False kalau ditolak.
  Future<StaffLoginResult> login({
    required String username,
    required String password,
    required String captchaCode,
  }) async {
    await _ensureCookieManager();
    final response = await _dio.post<String>(
      '/plogin.php',
      data: {
        'login': '1',
        'mac': '',
        'usr': username,
        'pwd': password,
        'cImage': captchaCode,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final location = response.headers.value('location') ?? '';
    if (response.statusCode == 302 && location.contains('mfa.php')) {
      return const StaffLoginResult(needsMfa: true);
    }

    final page = await _followAndRead(response);
    return StaffLoginResult(
      needsMfa: false,
      errorMessage:
          _extractErrorMessage(page) ??
          'Login gagal — periksa username, password, dan kode verifikasi.',
    );
  }

  /// Verifikasi kode MFA (OTP 6 digit dari Google Authenticator).
  Future<StaffMfaResult> verifyMfa(String otp) async {
    await _ensureCookieManager();
    final response = await _dio.post<String>(
      '/mfa.php',
      data: {'otp': otp, 'verify': 'Verifikasi'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final location = response.headers.value('location');
    if (response.statusCode == 302 &&
        (location == null || !location.contains('mfa.php'))) {
      return const StaffMfaResult(success: true);
    }

    final page = await _followAndRead(response);
    return StaffMfaResult(
      success: false,
      errorMessage:
          _extractErrorMessage(page) ??
          'Kode verifikasi salah atau sudah kedaluwarsa.',
    );
  }

  Future<String> _followAndRead(Response<String> response) async {
    final location = response.headers.value('location');
    if (location == null) return response.data ?? '';
    final next = await _dio.get<String>(
      _normalizeLocation(location),
      options: Options(responseType: ResponseType.plain),
    );
    return next.data ?? '';
  }

  /// Server ini kadang balikin header `Location:` relatif tanpa garis miring
  /// di depan (mis. `main.php`, bukan `/main.php`). Dio menggabungkan baseUrl
  /// + path dengan penyambungan string polos (lihat `RequestOptions.uri` di
  /// paket dio) — tanpa garis miring, hasilnya jadi satu host rusak
  /// (`cianjurkab.v-tax.idmain.php`) yang gagal di-DNS-lookup.
  String _normalizeLocation(String location) {
    if (location.startsWith('http://') || location.startsWith('https://'))
      return location;
    return location.startsWith('/') ? location : '/$location';
  }

  String? _extractErrorMessage(String html) {
    final document = html_parser.parse(html);
    final text = document.querySelector('.err-msg')?.text.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Muat halaman Monitoring Wilayah sekali per sesi login — dipakai untuk
  /// menggali token `q` & `funcMode` yang disisipkan server ke tiap tab
  /// (lihat [_fetchTab]), bukan nilai tetap karena terikat sesi/uid akun
  /// yang login.
  Future<String> _ensureMonitoringPage() async {
    if (_monitoringHtml != null) return _monitoringHtml!;
    await _ensureCookieManager();
    final response = await _dio.get<String>(
      '/main.php',
      queryParameters: {'param': _monitoringParam},
      options: Options(responseType: ResponseType.plain),
    );
    _monitoringHtml = response.data ?? '';
    return _monitoringHtml!;
  }

  /// Token `q` dari grup fungsi "s=23" (Sudah Bayar / Belum Bayar / kedua tab
  /// Kolektif / `showBank`) — sama untuk semuanya di satu sesi, jadi cukup
  /// digali sekali lalu dipakai ulang.
  Future<String?> _ensurePageQ23() async {
    if (_pageQ23 != null) return _pageQ23;
    final html = await _ensureMonitoringPage();
    _pageQ23 = StaffPortalTokenExtractor.extractLoadQ(
      html,
      'onSubmitSudahBayar',
    );
    return _pageQ23;
  }

  Future<MonitoringTableResult> _fetchTab({
    required String jsFunctionName,
    required String query,
    required Map<String, String> params,
  }) async {
    final html = await _ensureMonitoringPage();
    final q = StaffPortalTokenExtractor.extractLoadQ(html, jsFunctionName);
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(
      html,
      jsFunctionName,
    );
    if (q == null || funcMode == null) {
      return const MonitoringTableResult(
        errorMessage:
            'Gagal membaca token halaman Monitoring — sesi mungkin sudah berakhir, '
            'coba buka ulang menu Monitoring (login ulang kalau diminta).',
      );
    }
    final response = await _dio.post<String>(
      '/main.php',
      queryParameters: {'q': q},
      data: {'query': query, ...params, 'funcMode': funcMode},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    return _parseGenericTable(response.data ?? '');
  }

  /// Tab "Sudah Bayar" — replika `onSubmitSudahBayar(1)`.
  Future<MonitoringTableResult> fetchSudahBayar({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    String tahunAwal = '',
    String tahunAkhir = '',
    String bukuMin = '',
    String bukuMax = '',
    String bank = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String kodeBayarKolektif = '',
    String va = '',
    String qris = '',
    String operator = '',
    String tglPelimpahanAwal = '',
    String tglPelimpahanAkhir = '',
  }) {
    return _fetchTab(
      jsFunctionName: 'onSubmitSudahBayar',
      query: 'Sudah_Bayar',
      params: {
        'tahun_1': tahunAwal,
        'tahun_2': tahunAkhir,
        'nop': nop,
        'nama_wp': namaWp,
        'bank': bank,
        'merchant': '',
        'mitrabank': '',
        'st': '1',
        'tgl_pembayaran_1': tglBayarAwal,
        'tgl_pembayaran_2': tglBayarAkhir,
        'kec': '',
        'kel': '',
        'buku_1': bukuMin,
        'buku_2': bukuMax,
        'tgl_pelimpahan_1': tglPelimpahanAwal,
        'tgl_pelimpahan_2': tglPelimpahanAkhir,
        'kode_bayar_individu': kodeBayarIndividu,
        'kode_bayar_kolektif': kodeBayarKolektif,
        'va': va,
        'qris': qris,
        'tgl_cutoff': '',
        'operator': operator,
        'exp': '',
        'LBL_KEL': 'Desa/Kelurahan',
      },
    );
  }

  /// Tab "Belum Bayar" — replika `onSubmitBelumBayar(2)`.
  Future<MonitoringTableResult> fetchBelumBayar({
    required String tglCutoff,
    String tahunAwal = '',
    String tahunAkhir = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String bukuMin = '',
    String bukuMax = '',
  }) {
    return _fetchTab(
      jsFunctionName: 'onSubmitBelumBayar',
      query: 'Belum_Bayar',
      params: {
        'tahun_1': tahunAwal,
        'tahun_2': tahunAkhir,
        'nop': nop,
        'nama_wp': namaWp,
        'bank': '',
        'merchant': '',
        'st': '2',
        'tgl_pembayaran_1': '',
        'tgl_pembayaran_2': '',
        'kec': '',
        'kel': '',
        'buku_1': bukuMin,
        'buku_2': bukuMax,
        'tgl_pelimpahan_1': '',
        'tgl_pelimpahan_2': '',
        'kode_bayar_individu': kodeBayarIndividu,
        'kode_bayar_kolektif': '',
        'va': '',
        'qris': '',
        'tgl_cutoff': tglCutoff,
        'operator': '',
        'exp': '',
        'LBL_KEL': 'Desa/Kelurahan',
      },
    );
  }

  /// Tab "Realisasi" — replika `showModelRealisasi1()`.
  Future<MonitoringTableResult> fetchRealisasi({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    required String tglCutoff,
    String tahunAwal = '',
    String tahunAkhir = '',
    String bukuMin = '',
    String bukuMax = '',
    String bank = '',
    String tglPelimpahanAwal = '',
    String tglPelimpahanAkhir = '',
  }) {
    return _fetchTab(
      jsFunctionName: 'showModelRealisasi1',
      query: 'Realisasi',
      params: {
        'bk_min': bukuMin,
        'bk_max': bukuMax,
        'th': tahunAwal,
        'th2': tahunAkhir,
        'st': '1',
        'kc': '',
        'n': '',
        'kl': '',
        'nl': '',
        'eperiode': tglBayarAwal,
        'eperiode2': tglBayarAkhir,
        'tgl_pelimpahan': tglPelimpahanAwal,
        'tgl_pelimpahan_2': tglPelimpahanAkhir,
        'tgl_cutoff': tglCutoff,
        'bank': bank,
        'merchant': '',
        'mitrabank': '',
        'target_ketetapan': 'semua',
        'exp': '',
        'LBL_KEL': 'Desa/Kelurahan',
      },
    );
  }

  /// Tab "Piutang" — replika `showModelPiutang()`.
  Future<MonitoringTableResult> fetchPiutang({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    required String tglCutoff,
    String tahunAwal = '',
    String tahunAkhir = '',
    String bukuMin = '',
    String bukuMax = '',
    String tglPelimpahanAwal = '',
    String tglPelimpahanAkhir = '',
    String orderBy = 'tahun',
  }) {
    return _fetchTab(
      jsFunctionName: 'showModelPiutang',
      query: 'Piutang',
      params: {
        'tahunawal': tahunAwal,
        'tahunakhir': tahunAkhir,
        'st': '1',
        'kecamatan': '',
        'namakec': '',
        'kelurahan': '',
        'namakel': '',
        'tglawal': tglBayarAwal,
        'tglakhir': tglBayarAkhir,
        'tglpelimpahanawal': tglPelimpahanAwal,
        'tglpelimpahanakhir': tglPelimpahanAkhir,
        'tglcutoff': tglCutoff,
        'bukumin': bukuMin,
        'bukumax': bukuMax,
        'orderby': orderBy,
        'exp': '',
        'LBL_KEL': 'Desa/Kelurahan',
      },
    );
  }

  /// Tab "Sudah Bayar Kolektif" — replika `onSubmitSudahBayarKolektif(1)`.
  Future<MonitoringTableResult> fetchSudahBayarKolektif({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    String kodeBayarKolektif = '',
    String namaGrup = '',
    String namaKolektor = '',
  }) {
    return _fetchTab(
      jsFunctionName: 'onSubmitSudahBayarKolektif',
      query: 'Sudah_Bayar_Kolektif',
      params: {
        'tgl_pembayaran_1': tglBayarAwal,
        'tgl_pembayaran_2': tglBayarAkhir,
        'nama_grup': namaGrup,
        'nama_kolektor': namaKolektor,
        'kc': '',
        'kl': '',
        'kode_bayar_kolektif': kodeBayarKolektif,
        'tgl_cutoff_belum_bayar': '',
        'tgl_cutoff_kadaluarsa': '',
        'st': '1',
        'exp': '',
        'LBL_KEL': 'Desa/Kelurahan',
        'ADMIN_SW_DBNAME': 'SW_PBB',
      },
    );
  }

  /// Tab "Belum Bayar Kolektif" — replika `onSubmitBelumBayarKolektif(2)`.
  Future<MonitoringTableResult> fetchBelumBayarKolektif({
    required String tglCutoffBelumBayar,
    required String tglCutoffKadaluarsa,
    String kodeBayarKolektif = '',
    String namaGrup = '',
    String namaKolektor = '',
  }) {
    return _fetchTab(
      jsFunctionName: 'onSubmitBelumBayarKolektif',
      query: 'Belum_Bayar_Kolektif',
      params: {
        'tgl_pembayaran_1': '',
        'tgl_pembayaran_2': '',
        'nama_grup': namaGrup,
        'nama_kolektor': namaKolektor,
        'kode_bayar_kolektif': kodeBayarKolektif,
        'tgl_cutoff_belum_bayar': tglCutoffBelumBayar,
        'tgl_cutoff_kadaluarsa': tglCutoffKadaluarsa,
        'st': '2',
        'kc': '',
        'kl': '',
        'exp': '',
        'LBL_KEL': 'Desa/Kelurahan',
      },
    );
  }

  /// Tab "Rangking Realisasi" — replika `showRangkingRealisasi()`.
  Future<MonitoringTableResult> fetchRangkingRealisasi({
    String bukuFilter = '123',
  }) {
    return _fetchTab(
      jsFunctionName: 'showRangkingRealisasi',
      query: 'Ranking_Realisasi',
      params: {
        'th': '',
        'st': '1',
        'kc': '',
        'kl': '',
        'n': '',
        'bukuFilter': bukuFilter,
        'eperiode': '',
      },
    );
  }

  /// Daftar Bank untuk dropdown filter (tab Sudah Bayar & Realisasi) —
  /// dimuat sekali lalu di-cache untuk sesi ini.
  Future<List<BankOption>> fetchBankOptions() async {
    if (_bankOptionsCache != null) return _bankOptionsCache!;
    final html = await _ensureMonitoringPage();
    final q = await _ensurePageQ23();
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(
      html,
      'showBank',
    );
    if (q == null || funcMode == null) return const [];
    final response = await _dio.post<String>(
      '/main.php',
      data: {'q': q, 'config_filter_bank': '1', 'funcMode': funcMode},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    final options = _parseBankJson(response.data ?? '');
    _bankOptionsCache = options;
    return options;
  }

  List<BankOption> _parseBankJson(String body) {
    try {
      final decoded = jsonDecode(body);
      final list = decoded is Map ? decoded['msg'] : null;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map(
            (m) =>
                BankOption(id: '${m['CDC_B_ID']}', name: '${m['CDC_B_NAME']}'),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// Ambil tabel terbesar (paling banyak sel `<td>`) dari HTML respons —
  /// kolomnya dibaca apa adanya dari header tabel, tidak di-hardcode, karena
  /// belum ada contoh isi asli hasil "Tampilkan" untuk dicocokkan.
  MonitoringTableResult _parseGenericTable(String html) {
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');
    if (tables.isEmpty) {
      final text = document.body?.text.trim();
      return MonitoringTableResult(
        errorMessage: (text == null || text.isEmpty) ? 'Tidak ada data.' : text,
      );
    }
    tables.sort(
      (a, b) => b
          .querySelectorAll('td')
          .length
          .compareTo(a.querySelectorAll('td').length),
    );
    final table = tables.first;
    final trs = table.querySelectorAll('tr');
    if (trs.isEmpty)
      return const MonitoringTableResult(errorMessage: 'Tidak ada data.');

    final headers = trs.first
        .querySelectorAll('th, td')
        .map((c) => c.text.trim())
        .toList();
    final rows = trs
        .skip(1)
        .map(
          (tr) => tr.querySelectorAll('td').map((c) => c.text.trim()).toList(),
        )
        .where((r) => r.isNotEmpty)
        .toList();

    if (rows.isEmpty)
      return const MonitoringTableResult(errorMessage: 'Tidak ada data.');
    return MonitoringTableResult(headers: headers, rows: rows);
  }

  /// Muat halaman Pembayaran Kolektif sekali per sesi login.
  ///
  /// [forceReload] dipakai aksi yang mengubah data (buat/hapus grup): token
  /// `funcMode` berbeda tiap kali halaman dibuka, dan untuk aksi yang cuma
  /// boleh dicoba sekali lebih aman mengambil token yang baru saja diterbitkan
  /// server daripada memakai token hasil cache yang mungkin sudah basi.
  Future<String> _ensureKolektifPage({bool forceReload = false}) async {
    if (_kolektifHtml != null && !forceReload) return _kolektifHtml!;
    await _ensureCookieManager();
    final response = await _dio.get<String>(
      '/main.php',
      queryParameters: {'param': _kolektifParam},
      options: Options(responseType: ResponseType.plain),
    );
    _kolektifHtml = response.data ?? '';
    return _kolektifHtml!;
  }

  /// Kecamatan & daftar kelurahan yang boleh dipilih saat membuat grup.
  ///
  /// Kecamatan diambil dari `var myKecamatan` (baris JS mentah dari server),
  /// bukan dari `<option>` dropdown-nya — dropdown Kecamatan di halaman asli
  /// baru terisi setelah ajax `showKecamatanAll()` jalan di browser, jadi di
  /// HTML yang kita terima isinya belum tentu ada. Kelurahan sebaliknya:
  /// dropdown `#data-kelurahan-group-2` memang dirender server apa adanya.
  Future<KolektifFormOptions> fetchKolektifFormOptions() async {
    final html = await _ensureKolektifPage();
    final kecamatan = StaffPortalTokenExtractor.extractKolektifKecamatanCode(
      html,
    );
    if (kecamatan == null) {
      return const KolektifFormOptions(
        errorMessage:
            'Gagal membaca wilayah dari halaman Pembayaran Kolektif — coba buka ulang menunya.',
      );
    }

    final document = html_parser.parse(html);
    final options = <KolektifKelurahan>[];
    for (final selector in [
      'select#data-kelurahan-group-2',
      'select#data-kelurahan',
    ]) {
      for (final option in document.querySelectorAll('$selector option')) {
        final code = option.attributes['value']?.trim() ?? '';
        if (code.isEmpty) continue;
        if (options.any((o) => o.code == code)) continue;
        options.add(KolektifKelurahan(code: code, name: option.text.trim()));
      }
      if (options.isNotEmpty) break;
    }

    if (options.isEmpty) {
      return const KolektifFormOptions(
        errorMessage:
            'Daftar kelurahan tidak ditemukan di halaman Pembayaran Kolektif.',
      );
    }

    return KolektifFormOptions(
      kecamatanCode: kecamatan,
      kecamatanName: await _fetchKecamatanName(html, kecamatan),
      kelurahan: options,
      bisaTambah:
          StaffPortalTokenExtractor.extractTambahGroupFuncMode(html) != null,
      bisaHapus:
          StaffPortalTokenExtractor.extractHapusGroupFuncMode(html) != null &&
          StaffPortalTokenExtractor.extractGlobalQ(html) != null,
    );
  }

  /// Nama kecamatan untuk sebuah kode — replika `showKecamatanAll()`, yang di
  /// halaman aslinya dipakai untuk mengisi dropdown Kecamatan. Murni baca.
  ///
  /// Gagalnya pengambilan nama TIDAK dianggap error: pemanggilnya cukup
  /// menampilkan kode wilayah apa adanya, dan yang dikirim ke server saat
  /// menyimpan grup tetap kodenya.
  Future<String> _fetchKecamatanName(String html, String code) async {
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(
      html,
      'showKecamatanAll',
      window: 600,
    );
    if (funcMode == null) return '';
    try {
      final response = await _dio.post<String>(
        '/main.php',
        // `3205` = kode Kabupaten Cianjur, tertulis apa adanya di halaman
        // aslinya (`data: {id: "3205", funcMode: funcMode}`). Aplikasi ini
        // memang khusus Cianjur — lihat juga baseUrl & prefix NOP.
        data: {'id': '3205', 'funcMode': funcMode},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      final decoded = jsonDecode(response.data ?? '');
      if (decoded is! Map || decoded['msg'] is! List) return '';
      for (final item in decoded['msg'] as List) {
        if (item is Map && '${item['id']}'.trim() == code) {
          return rapikanNamaWilayah('${item['name']}');
        }
      }
    } on DioException {
      return '';
    } on FormatException {
      return '';
    }
    return '';
  }

  /// BUAT grup kolektif baru — replika `tambahGroup()`.
  ///
  /// Nama field-nya sengaja ditulis persis seperti hasil
  /// `$("#form-tambah-group").serialize()` di halaman asli, termasuk urutannya
  /// dan dua field kosong (`data-edit-group-id`, `data-id-group`) yang di sana
  /// ikut terkirim karena berada di dalam form. `data-edit-group-id` yang
  /// kosong itulah yang membedakan BUAT dari UBAH, jadi tidak boleh dihapus.
  ///
  /// Grup yang terbuat berstatus Draft dan tercatat permanen di server pemda.
  Future<KolektifActionResult> createKolektifGroup({
    required String namaGroup,
    required String keterangan,
    required String namaKolektor,
    required String noHpKolektor,
    required String kecamatanCode,
    required String kelurahanCode,
  }) {
    return _simpanKolektifGroup(
      editGroupId: '',
      namaGroup: namaGroup,
      keterangan: keterangan,
      namaKolektor: namaKolektor,
      noHpKolektor: noHpKolektor,
      kecamatanCode: kecamatanCode,
      kelurahanCode: kelurahanCode,
    );
  }

  /// UBAH data grup yang sudah ada.
  ///
  /// Endpoint & tokennya SAMA PERSIS dengan Tambah Group — di halaman aslinya
  /// tombol Simpan memanggil `tambahGroup()` untuk keduanya. Yang membedakan
  /// cuma satu field: `data-edit-group-id`. Kosong berarti buat baru, terisi
  /// berarti ubah. Karena itu [editGroupId] di bawah diperiksa tidak boleh
  /// kosong — kalau lolos kosong, yang terjadi bukan gagal, melainkan
  /// terbuatnya grup baru yang tidak diminta siapa pun.
  Future<KolektifActionResult> updateKolektifGroup({
    required String editGroupId,
    required String namaGroup,
    required String keterangan,
    required String namaKolektor,
    required String noHpKolektor,
    required String kecamatanCode,
    required String kelurahanCode,
  }) {
    if (editGroupId.trim().isEmpty) {
      return Future.value(
        const KolektifActionResult(
          success: false,
          message:
              'ID grup tidak terbaca, jadi tidak ada yang diubah. '
              '(Melanjutkan tanpa ID justru akan membuat grup baru.)',
        ),
      );
    }
    return _simpanKolektifGroup(
      editGroupId: editGroupId.trim(),
      namaGroup: namaGroup,
      keterangan: keterangan,
      namaKolektor: namaKolektor,
      noHpKolektor: noHpKolektor,
      kecamatanCode: kecamatanCode,
      kelurahanCode: kelurahanCode,
    );
  }

  Future<KolektifActionResult> _simpanKolektifGroup({
    required String editGroupId,
    required String namaGroup,
    required String keterangan,
    required String namaKolektor,
    required String noHpKolektor,
    required String kecamatanCode,
    required String kelurahanCode,
  }) async {
    final html = await _ensureKolektifPage(forceReload: true);
    final funcMode = StaffPortalTokenExtractor.extractTambahGroupFuncMode(html);
    final userId = StaffPortalTokenExtractor.extractKolektifUserId(html);
    if (funcMode == null || userId == null) {
      return KolektifActionResult(
        success: false,
        message:
            'Token halaman Pembayaran Kolektif tidak terbaca, jadi grup TIDAK '
            '${editGroupId.isEmpty ? 'dibuat' : 'diubah'}. '
            'Sesi mungkin sudah berakhir — masuk ulang lalu coba lagi.',
      );
    }

    final response = await _dio.post<String>(
      '/main.php',
      data: {
        'userID': userId,
        'data-edit-group-id': editGroupId,
        'data-id-group': '',
        'data-nama': namaGroup,
        'data-keterangan': keterangan,
        'data-nama-kolektor': namaKolektor,
        'data-no-kolektor': noHpKolektor,
        'data-kecamatan-group': kecamatanCode,
        'data-kelurahan-group': kelurahanCode,
        'funcMode': funcMode,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    _kolektifHtml = null;
    return _parseKolektifActionJson(response.data ?? '');
  }

  /// Unduh "Surat Pengantar" satu grup sebagai PDF — replika
  /// `pdfGroupInfo(group_id)`, yang di halaman aslinya sekadar membuka
  /// `view/PBB/pembayaran_va/setPDFGroupInfo.php?id=…` di tab baru. Murni
  /// baca, tidak mengubah apa pun di server.
  ///
  /// Berkasnya hanya bisa diambil sambil membawa cookie sesi login, jadi tidak
  /// bisa diserahkan begitu saja ke browser luar — di sini diunduh sendiri
  /// lalu ditampilkan di dalam aplikasi.
  Future<Uint8List> fetchSuratPengantarPdf(String groupId) async {
    await _ensureCookieManager();
    final response = await _dio.get<List<int>>(
      '/view/PBB/pembayaran_va/setPDFGroupInfo.php',
      queryParameters: {'id': groupId},
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    // Kalau sesi sudah habis, server membalas halaman login (HTML) dengan
    // status 200 — bukan PDF. Tanpa pemeriksaan ini, pratinjau akan terbuka
    // kosong tanpa keterangan apa-apa.
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
      throw StateError(
        'Server tidak mengirim berkas PDF. Sesi mungkin sudah berakhir — buka ulang menu Monitoring lalu coba lagi.',
      );
    }
    return bytes;
  }

  /// HAPUS grup kolektif — replika handler tombol `#btn-confirm-delete-group`.
  ///
  /// [alasan] wajib diisi (halaman aslinya menolak alasan kosong) dan ikut
  /// tercatat permanen di "Log History Penghapusan" bersama nama user yang
  /// menghapus — penghapusan ini tidak bisa dibatalkan.
  Future<KolektifActionResult> deleteKolektifGroup({
    required String groupId,
    required String alasan,
  }) async {
    if (groupId.trim().isEmpty) {
      return const KolektifActionResult(
        success: false,
        message:
            'ID grup tidak terbaca dari daftar, jadi tidak ada yang dihapus.',
      );
    }
    if (alasan.trim().isEmpty) {
      return const KolektifActionResult(
        success: false,
        message: 'Alasan penghapusan wajib diisi.',
      );
    }

    final html = await _ensureKolektifPage(forceReload: true);
    final q = StaffPortalTokenExtractor.extractGlobalQ(html);
    final funcMode = StaffPortalTokenExtractor.extractHapusGroupFuncMode(html);
    if (q == null || funcMode == null) {
      return const KolektifActionResult(
        success: false,
        message:
            'Token halaman Pembayaran Kolektif tidak terbaca, jadi grup TIDAK dihapus. '
            'Sesi mungkin sudah berakhir — masuk ulang lalu coba lagi.',
      );
    }

    final response = await _dio.post<String>(
      '/main.php',
      data: {'q': q, 'id': groupId, 'alasan': alasan, 'funcMode': funcMode},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    _kolektifHtml = null;
    return _parseKolektifActionJson(response.data ?? '');
  }

  static const _kolektifMemberColumns = [
    '',
    'NOP',
    'SPPT_TAHUN_PAJAK',
    'SPPT_TANGGAL_JATUH_TEMPO',
    'WP_NAMA',
    'OP_KECAMATAN',
    'OP_KELURAHAN',
    'SPPT_PBB_HARUS_DIBAYAR',
    'test',
    'test',
  ];

  /// Daftar anggota (NOP) sebuah grup — replika `getGroupData(group_id, status)`.
  ///
  /// [status] adalah kode status grup apa adanya dari kolom Aksi; server
  /// memakainya untuk menentukan bentuk kolom Aksi tiap baris, jadi ikut
  /// dikirim sama seperti halaman aslinya.
  Future<KolektifMemberListResult> fetchKolektifMembers({
    required String groupId,
    required String status,
    int length = 500,
  }) async {
    final html = await _ensureKolektifPage();
    final funcMode = StaffPortalTokenExtractor.extractListAnggotaFuncMode(html);
    if (funcMode == null) {
      return const KolektifMemberListResult(
        errorMessage:
            'Gagal membaca token daftar anggota — coba buka ulang menu Pembayaran Kolektif.',
      );
    }

    final queryParameters = <String, String>{
      'status': status,
      'group_id': groupId,
      'funcMode': funcMode,
      'draw': '1',
      'start': '0',
      'length': '$length',
      'search[value]': '',
      'search[regex]': 'false',
      'order[0][column]': '1',
      'order[0][dir]': 'asc',
    };
    for (var i = 0; i < _kolektifMemberColumns.length; i++) {
      queryParameters['columns[$i][data]'] = '$i';
      queryParameters['columns[$i][name]'] = _kolektifMemberColumns[i];
      queryParameters['columns[$i][searchable]'] = 'true';
      queryParameters['columns[$i][orderable]'] = 'true';
      queryParameters['columns[$i][search][value]'] = '';
      queryParameters['columns[$i][search][regex]'] = 'false';
    }

    final response = await _dio.get<String>(
      '/main.php',
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.plain),
    );
    return _parseKolektifMemberJson(response.data ?? '');
  }

  KolektifMemberListResult _parseKolektifMemberJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['data'] is! List) {
        return const KolektifMemberListResult(
          errorMessage: 'Format respons daftar anggota tidak dikenali.',
        );
      }
      final members = (decoded['data'] as List).whereType<List>().map((row) {
        String cell(int i) => i < row.length ? _stripHtml('${row[i]}') : '';
        final checkbox = row.isNotEmpty
            ? html_parser
                  .parseFragment('${row[0]}')
                  .querySelector('input[value]')
            : null;
        return KolektifMember(
          nop: checkbox?.attributes['value']?.trim().isNotEmpty == true
              ? checkbox!.attributes['value']!.trim()
              : cell(1),
          tahunPajak: checkbox?.attributes['year']?.trim().isNotEmpty == true
              ? checkbox!.attributes['year']!.trim()
              : cell(2),
          jatuhTempo: cell(3),
          namaWp: cell(4),
          kecamatan: cell(5),
          kelurahan: cell(6),
          pokok: cell(7),
          denda: cell(8),
          total: cell(9),
        );
      }).toList();
      if (members.isEmpty) {
        return const KolektifMemberListResult(
          errorMessage: 'Grup ini belum punya anggota.',
        );
      }
      return KolektifMemberListResult(members: members);
    } on FormatException {
      return const KolektifMemberListResult(
        errorMessage:
            'Gagal membaca daftar anggota — format respons tidak sesuai dugaan.',
      );
    }
  }

  /// TAMBAH NOP ke dalam grup — replika `cariNOP()`.
  ///
  /// [nop] wajib diisi. Di halaman aslinya, `data-nop` yang KOSONG memicu
  /// penambahan MASSAL — seluruh NOP yang belum bayar di satu kelurahan
  /// sekaligus. Aksi seluas itu sengaja tidak disediakan lewat aplikasi ini,
  /// jadi permintaan dengan NOP kosong ditolak di sini sebelum sampai jaringan.
  ///
  /// Aksi ini menambah tagihan ke grup Draft dan masih bisa dibatalkan lewat
  /// [deleteKolektifMembers] selama grup belum difinalkan.
  Future<KolektifActionResult> addKolektifMember({
    required String groupId,
    required String nop,
    required String tahunPajak,
    required String buku,
    required String kelurahanCode,
  }) async {
    if (nop.trim().isEmpty) {
      return const KolektifActionResult(
        success: false,
        message:
            'NOP wajib diisi. Menambahkan seluruh NOP sekelurahan sekaligus tidak disediakan di aplikasi ini.',
      );
    }

    final html = await _ensureKolektifPage(forceReload: true);
    final funcMode = StaffPortalTokenExtractor.extractCariNopFuncMode(html);
    final userId = StaffPortalTokenExtractor.extractKolektifUserId(html);
    if (funcMode == null || userId == null) {
      return const KolektifActionResult(
        success: false,
        message:
            'Token halaman Pembayaran Kolektif tidak terbaca, jadi TIDAK ada NOP yang ditambahkan. '
            'Sesi mungkin sudah berakhir — masuk ulang lalu coba lagi.',
      );
    }

    // Urutan & nama field mengikuti hasil $("#form-cari").serialize() di
    // halaman asli, termasuk `data-group-name` yang di sana selalu terkirim
    // kosong (JS-nya memakai .html(), bukan .val(), jadi nilainya tak pernah
    // terisi) serta `blok`/`blok2` kosong. Input file `berkas` tidak ikut —
    // jQuery memang tidak menyertakan input bertipe file.
    final response = await _dio.post<String>(
      '/main.php',
      data: {
        'userID': userId,
        'data-group-id': groupId,
        'data-group-name': '',
        'data-nop': nop.trim(),
        'data-kelurahan': kelurahanCode,
        'data-tahun-pajak': tahunPajak,
        'data-buku': buku,
        'blok': '',
        'blok2': '',
        'funcMode': funcMode,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    _kolektifHtml = null;
    return _parseKolektifActionJson(response.data ?? '');
  }

  /// Tambahkan BANYAK NOP sekaligus dari berkas — satu NOP satu permintaan.
  ///
  /// Kenapa tidak sekali kirim dengan NOP dipisah koma (yang juga didukung
  /// server)? Karena jawaban server untuk kiriman gabungan cuma SATU pesan
  /// untuk seluruh daftar. Padahal yang dibutuhkan justru nasib per NOP:
  /// mana yang masuk, mana yang sudah bayar, mana yang tidak ketemu. Satu NOP
  /// satu permintaan adalah satu-satunya cara mendapat jawaban per NOP.
  ///
  /// Kenapa tidak memakai jalur unggah CSV milik server sendiri
  /// (`cariNOPCSV()`)? Selain jawabannya juga digabung jadi satu pesan,
  /// tokennya duduk persis di sebelah token `generateva()` — aksi yang
  /// menerbitkan virtual account sungguhan dan tidak boleh tersentuh aplikasi
  /// ini sama sekali. Jalur di bawah memakai ulang token `cariNOP()` yang
  /// sudah dikunci pengujian, jadi tidak ada token baru yang perlu digali di
  /// dekat aksi berbahaya itu.
  ///
  /// Tokennya diambil SEKALI di awal lalu dipakai untuk seluruh daftar —
  /// persis seperti halaman aslinya, yang menambahkan NOP berkali-kali dengan
  /// satu token dari sekali muat halaman.
  ///
  /// [batal] diperiksa sebelum tiap NOP supaya penggunanya bisa menghentikan
  /// proses di tengah jalan; yang sudah telanjur terkirim tetap dilaporkan.
  Future<HasilImporNop> addKolektifMembersFromList({
    required String groupId,
    required List<String> nopList,
    required String tahunPajak,
    required String buku,
    required String kelurahanCode,
    void Function(int selesai, int total)? onProgress,
    bool Function()? batal,
    Duration jeda = const Duration(milliseconds: 250),
  }) async {
    if (nopList.isEmpty) {
      return const HasilImporNop(
        errorFatal: 'Tidak ada NOP yang bisa dikirim.',
      );
    }

    final html = await _ensureKolektifPage(forceReload: true);
    final funcMode = StaffPortalTokenExtractor.extractCariNopFuncMode(html);
    final userId = StaffPortalTokenExtractor.extractKolektifUserId(html);
    if (funcMode == null || userId == null) {
      return const HasilImporNop(
        errorFatal:
            'Token halaman Pembayaran Kolektif tidak terbaca, jadi TIDAK ada NOP yang dikirim. '
            'Sesi mungkin sudah berakhir — masuk ulang lalu coba lagi.',
      );
    }

    final item = <ItemImporNop>[];
    var gagalBeruntun = 0;
    String? errorFatal;

    for (var i = 0; i < nopList.length; i++) {
      if (batal?.call() == true) {
        return HasilImporNop(item: item, dibatalkan: true);
      }
      final nop = nopList[i];

      KolektifActionResult hasil;
      try {
        final response = await _dio.post<String>(
          '/main.php',
          data: {
            'userID': userId,
            'data-group-id': groupId,
            'data-group-name': '',
            'data-nop': nop,
            'data-kelurahan': kelurahanCode,
            'data-tahun-pajak': tahunPajak,
            'data-buku': buku,
            'blok': '',
            'blok2': '',
            'funcMode': funcMode,
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
          ),
        );
        hasil = _parseKolektifActionJson(response.data ?? '');
      } on DioException catch (e) {
        // Jaringan putus di tengah permintaan: NOP ini nasibnya BELUM PASTI —
        // bisa jadi sudah masuk sebelum jawabannya hilang. Karena itu dicatat
        // sebagai "perlu diperiksa", bukan sebagai gagal.
        gagalBeruntun++;
        item.add(
          ItemImporNop(
            nop: nop,
            status: StatusImporNop.perluDiperiksa,
            pesan:
                'Koneksi terputus sebelum jawaban server sampai, jadi belum pasti masuk atau tidak. '
                '(${e.type.name})',
          ),
        );
        if (gagalBeruntun >= 3) {
          errorFatal =
              'Koneksi gagal tiga kali berturut-turut, jadi sisa NOP tidak dikirim. '
              'Periksa daftar anggota lalu ulangi untuk NOP yang belum masuk.';
          break;
        }
        onProgress?.call(i + 1, nopList.length);
        await Future<void>.delayed(jeda);
        continue;
      }

      // Jawaban bukan JSON = hampir pasti halaman login, artinya sesi habis.
      // Diteruskan pun sisanya cuma menembakkan permintaan sia-sia ke server
      // pemda, jadi berhenti di sini.
      if (!hasil.responsDikenali) {
        errorFatal =
            'Server berhenti menjawab dalam format yang dikenali di NOP ke-${i + 1} — '
            'biasanya berarti sesi login sudah berakhir. Sisa NOP TIDAK dikirim. '
            'Masuk ulang, periksa daftar anggota, lalu ulangi untuk yang belum masuk.';
        break;
      }

      gagalBeruntun = 0;
      item.add(
        ItemImporNop(
          nop: nop,
          status: klasifikasiHasilTambahNop(
            success: hasil.success,
            pesan: hasil.message,
          ),
          pesan: hasil.message,
        ),
      );
      onProgress?.call(i + 1, nopList.length);
      if (i < nopList.length - 1) await Future<void>.delayed(jeda);
    }

    _kolektifHtml = null;
    return HasilImporNop(item: item, errorFatal: errorFatal);
  }

  /// HAPUS anggota terpilih dari grup — replika handler `#btn-delete-all`.
  ///
  /// Bentuk datanya array of object (`data[0][nop]`, `data[0][tahun]`, …)
  /// persis seperti yang dikirim jQuery di sana.
  Future<KolektifActionResult> deleteKolektifMembers({
    required List<KolektifMember> members,
  }) async {
    if (members.isEmpty) {
      return const KolektifActionResult(
        success: false,
        message: 'Silakan pilih data terlebih dahulu.',
      );
    }

    final html = await _ensureKolektifPage(forceReload: true);
    final funcMode = StaffPortalTokenExtractor.extractHapusAnggotaFuncMode(
      html,
    );
    if (funcMode == null) {
      return const KolektifActionResult(
        success: false,
        message:
            'Token halaman Pembayaran Kolektif tidak terbaca, jadi TIDAK ada anggota yang dihapus. '
            'Sesi mungkin sudah berakhir — masuk ulang lalu coba lagi.',
      );
    }

    final response = await _dio.post<String>(
      '/main.php',
      data: {
        'data': [
          for (final m in members) {'nop': m.nop, 'tahun': m.tahunPajak},
        ],
        'funcMode': funcMode,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    _kolektifHtml = null;
    return _parseKolektifActionJson(response.data ?? '');
  }

  /// Baca respons aksi buat/hapus grup. Halaman aslinya cuma melihat
  /// `data.success` lalu menampilkan `data.message` kalau gagal, jadi itu
  /// yang ditiru. Kalau responsnya bukan JSON yang dikenali, isi mentahnya
  /// ikut dibawa pulang — statusnya jadi "tidak pasti", dan itu yang paling
  /// jujur: request-nya sudah telanjur sampai ke server.
  KolektifActionResult _parseKolektifActionJson(String body) {
    final trimmed = body.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final message = decoded['message']?.toString();
        return KolektifActionResult(
          success: decoded['success'] == true,
          message: (message == null || message.isEmpty) ? null : message,
          rawBody: trimmed,
        );
      }
    } on FormatException {
      // Bukan JSON — jatuh ke penanganan di bawah.
    }
    final cuplikan = trimmed.length > 300
        ? '${trimmed.substring(0, 300)}…'
        : trimmed;
    return KolektifActionResult(
      success: false,
      message:
          'Server menjawab dengan format yang tidak dikenali, jadi hasilnya belum pasti. '
          'Periksa dulu daftar grup sebelum mencoba lagi.\n\nJawaban server:\n$cuplikan',
      rawBody: trimmed,
      responsDikenali: false,
    );
  }

  static const _kolektifColumns = [
    'AKSI',
    'CPM_CG_NAME',
    'CPM_CG_COLLECTOR',
    'CPM_CG_HP_COLLECTOR',
    'JML_ANGGOTA',
    'CPM_CG_PAYMENT_CODE',
    'CPM_CG_STATUS',
    'NAMA_KECAMATAN',
    'NAMA_KELURAHAN',
    'CPM_CG_DESC',
    'CPM_CG_EXPIRED_DATE',
    'CPM_CG_EXPIRED_DATE',
  ];

  /// Daftar grup Pembayaran Kolektif (read-only) — replika `reloadDataGroup()`
  /// yang di sana dijalankan oleh library DataTables (server-side mode), jadi
  /// di sini parameter paging/sorting standar DataTables direplikasi manual.
  /// Belum ada contoh respons JSON asli untuk dicocokkan — kalau format
  /// respons meleset, [KolektifListResult.errorMessage] akan menjelaskan itu.
  Future<KolektifListResult> fetchKolektifGroups({
    String bulan = '0',
    String status = '',
    String tahun = '',
    String tglAwal = '',
    String tglAkhir = '',
  }) async {
    final html = await _ensureKolektifPage();
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(
      html,
      'reloadDataGroup',
      window: 800,
    );
    final userId = StaffPortalTokenExtractor.extractKolektifUserId(html);
    if (funcMode == null || userId == null) {
      return const KolektifListResult(
        errorMessage:
            'Gagal membaca token halaman Pembayaran Kolektif — coba buka ulang menunya.',
      );
    }

    final queryParameters = <String, String>{
      'userID': userId,
      'bulan': bulan,
      'status': status,
      'kec': '',
      'kel': '',
      'tahun': tahun,
      'tgl1': tglAwal,
      'tgl2': tglAkhir,
      'funcMode': funcMode,
      'draw': '1',
      'start': '0',
      'length': '50',
      'search[value]': '',
      'search[regex]': 'false',
      // Kolom 11 = "Tanggal Buat" — kolom terakhir yang di halaman aslinya
      // sengaja disembunyikan dan cuma dipakai sebagai kunci urutan default
      // (`"order": [[ 11, "desc" ]]`), supaya grup terbaru tampil di atas.
      // Sebelumnya di sini keliru memakai kolom 10 (Tanggal Kadaluarsa), yang
      // untuk grup Draft isinya kosong sehingga urutannya jadi tidak keruan.
      'order[0][column]': '11',
      'order[0][dir]': 'desc',
    };
    for (var i = 0; i < _kolektifColumns.length; i++) {
      queryParameters['columns[$i][data]'] = '$i';
      queryParameters['columns[$i][name]'] = _kolektifColumns[i];
      queryParameters['columns[$i][searchable]'] = 'true';
      queryParameters['columns[$i][orderable]'] = 'true';
      queryParameters['columns[$i][search][value]'] = '';
      queryParameters['columns[$i][search][regex]'] = 'false';
    }

    final response = await _dio.get<String>(
      '/main.php',
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.plain),
    );
    return _parseKolektifJson(response.data ?? '');
  }

  KolektifListResult _parseKolektifJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['data'] is! List) {
        return const KolektifListResult(
          errorMessage: 'Format respons daftar grup tidak dikenali.',
        );
      }
      final rows = (decoded['data'] as List).whereType<List>();
      final groups = rows.map((row) {
        String cell(int i) => i < row.length ? _stripHtml('${row[i]}') : '';
        final aksi = _parseKolektifAksiCell(row.isNotEmpty ? '${row[0]}' : '');
        final kel = _parseKolektifKelurahanCell(
          row.length > 8 ? '${row[8]}' : '',
        );
        return KolektifGroup(
          id: aksi.id,
          statusCode: aksi.statusCode,
          canDelete: aksi.canDelete,
          canEdit: aksi.canEdit,
          canPrintSurat: aksi.canPrintSurat,
          kelurahanCode: kel.kode,
          namaGroup: cell(1),
          namaKolektor: cell(2),
          hpKolektor: cell(3),
          anggota: cell(4),
          kodeBayar: cell(5),
          status: cell(6),
          kecamatan: cell(7),
          kelurahan: kel.nama,
          keterangan: cell(9),
          tanggalKadaluarsa: cell(10),
        );
      }).toList();
      if (groups.isEmpty)
        return const KolektifListResult(errorMessage: 'Tidak ada data.');
      return KolektifListResult(groups: groups);
    } on FormatException {
      return const KolektifListResult(
        errorMessage:
            'Gagal membaca daftar grup — format respons tidak sesuai dugaan.',
      );
    }
  }

  /// Bongkar kolom "Aksi" — satu-satunya tempat server menaruh `CPM_CG_ID`,
  /// kode status, dan (lewat ada/tidaknya tombol `.btn-delete-group`) izin
  /// menghapus baris itu.
  ///
  /// Perhatikan ejaan atributnya beda antar tombol di halaman asli: tombol
  /// Kelola Member memakai `group-id` (strip), tombol Hapus memakai
  /// `group_id` (garis bawah). Keduanya berisi ID yang sama, jadi dua-duanya
  /// dicoba.
  ({
    String id,
    String statusCode,
    bool canDelete,
    bool canEdit,
    bool canPrintSurat,
  })
  _parseKolektifAksiCell(String cellHtml) {
    if (cellHtml.isEmpty) {
      return (
        id: '',
        statusCode: '',
        canDelete: false,
        canEdit: false,
        canPrintSurat: false,
      );
    }
    final fragment = html_parser.parseFragment(cellHtml);
    final id =
        (fragment.querySelector('[group-id]')?.attributes['group-id'] ??
                fragment.querySelector('[group_id]')?.attributes['group_id'] ??
                '')
            .trim();
    final statusCode =
        fragment.querySelector('[status]')?.attributes['status'] ?? '';
    final punyaId = id.isNotEmpty;
    return (
      id: id,
      statusCode: statusCode.trim(),
      canDelete: punyaId && fragment.querySelector('.btn-delete-group') != null,
      canEdit: punyaId && fragment.querySelector('.btn-edit-group') != null,
      canPrintSurat:
          punyaId && fragment.querySelector('.btn-cetak-info-group') != null,
    );
  }

  /// Bongkar kolom "Kelurahan", yang berisi DUA elemen sekaligus: nama yang
  /// tampil (`.nm-kel`) dan kode wilayah yang disembunyikan (`.kd-kel`).
  /// Kalau keduanya diambil sebagai teks polos, hasilnya menyatu jadi
  /// "BOBOJONG3205200004" — jadi masing-masing dibaca terpisah.
  ({String nama, String kode}) _parseKolektifKelurahanCell(String cellHtml) {
    if (cellHtml.isEmpty) return (nama: '', kode: '');
    final fragment = html_parser.parseFragment(cellHtml);
    final nama = fragment.querySelector('.nm-kel')?.text.trim();
    final kode = fragment.querySelector('.kd-kel')?.text.trim();
    if (nama != null || kode != null)
      return (nama: nama ?? '', kode: kode ?? '');
    return (nama: _stripHtml(cellHtml), kode: '');
  }

  String _stripHtml(String value) =>
      (html_parser.parseFragment(value).text ?? value).trim();
}
