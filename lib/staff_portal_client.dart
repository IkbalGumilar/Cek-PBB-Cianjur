import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

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

  const MonitoringTableResult({this.headers = const [], this.rows = const [], this.errorMessage});
}

/// Satu opsi pada dropdown filter Bank (dimuat dinamis dari server, bukan
/// nilai tetap — daftar bank bisa berubah).
class BankOption {
  final String id;
  final String name;

  const BankOption({required this.id, required this.name});
}

/// Satu baris grup pada modul Pembayaran Kolektif (`m179`) — BEDA modul dari
/// Monitoring Wilayah (`mMonitoringWilayahV3`). Versi ini read-only (belum
/// ada Tambah/Hapus Group, Kelola Member, Finalkan, atau Generate VA — itu
/// semua mengubah data pembayaran asli di server, jadi sengaja belum dibuat).
class KolektifGroup {
  final String namaGroup;
  final String namaKolektor;
  final String hpKolektor;
  final String anggota;
  final String kodeBayar;
  final String status;
  final String kecamatan;
  final String kelurahan;
  final String keterangan;
  final String tanggalKadaluarsa;

  const KolektifGroup({
    required this.namaGroup,
    required this.namaKolektor,
    required this.hpKolektor,
    required this.anggota,
    required this.kodeBayar,
    required this.status,
    required this.kecamatan,
    required this.kelurahan,
    required this.keterangan,
    required this.tanggalKadaluarsa,
  });
}

class KolektifListResult {
  final List<KolektifGroup> groups;
  final String? errorMessage;

  const KolektifListResult({this.groups = const [], this.errorMessage});
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
    final jar = PersistCookieJar(ignoreExpires: true, storage: FileStorage('${dir.path}/staff_portal_cookies'));
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
      final response = await _dio.get<String>('/main.php', options: Options(responseType: ResponseType.plain));
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
    await _dio.get<String>('/main.php', options: Options(responseType: ResponseType.plain));
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
      errorMessage: _extractErrorMessage(page) ?? 'Login gagal — periksa username, password, dan kode verifikasi.',
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
    if (response.statusCode == 302 && (location == null || !location.contains('mfa.php'))) {
      return const StaffMfaResult(success: true);
    }

    final page = await _followAndRead(response);
    return StaffMfaResult(
      success: false,
      errorMessage: _extractErrorMessage(page) ?? 'Kode verifikasi salah atau sudah kedaluwarsa.',
    );
  }

  Future<String> _followAndRead(Response<String> response) async {
    final location = response.headers.value('location');
    if (location == null) return response.data ?? '';
    final next = await _dio.get<String>(_normalizeLocation(location), options: Options(responseType: ResponseType.plain));
    return next.data ?? '';
  }

  /// Server ini kadang balikin header `Location:` relatif tanpa garis miring
  /// di depan (mis. `main.php`, bukan `/main.php`). Dio menggabungkan baseUrl
  /// + path dengan penyambungan string polos (lihat `RequestOptions.uri` di
  /// paket dio) — tanpa garis miring, hasilnya jadi satu host rusak
  /// (`cianjurkab.v-tax.idmain.php`) yang gagal di-DNS-lookup.
  String _normalizeLocation(String location) {
    if (location.startsWith('http://') || location.startsWith('https://')) return location;
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
    _pageQ23 = StaffPortalTokenExtractor.extractLoadQ(html, 'onSubmitSudahBayar');
    return _pageQ23;
  }

  Future<MonitoringTableResult> _fetchTab({
    required String jsFunctionName,
    required String query,
    required Map<String, String> params,
  }) async {
    final html = await _ensureMonitoringPage();
    final q = StaffPortalTokenExtractor.extractLoadQ(html, jsFunctionName);
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(html, jsFunctionName);
    if (q == null || funcMode == null) {
      return const MonitoringTableResult(
        errorMessage: 'Gagal membaca token halaman Monitoring — sesi mungkin sudah berakhir, '
            'coba buka ulang menu Monitoring (login ulang kalau diminta).',
      );
    }
    final response = await _dio.post<String>(
      '/main.php',
      queryParameters: {'q': q},
      data: {'query': query, ...params, 'funcMode': funcMode},
      options: Options(contentType: Headers.formUrlEncodedContentType, responseType: ResponseType.plain),
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
  Future<MonitoringTableResult> fetchRangkingRealisasi({String bukuFilter = '123'}) {
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
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(html, 'showBank');
    if (q == null || funcMode == null) return const [];
    final response = await _dio.post<String>(
      '/main.php',
      data: {'q': q, 'config_filter_bank': '1', 'funcMode': funcMode},
      options: Options(contentType: Headers.formUrlEncodedContentType, responseType: ResponseType.plain),
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
          .map((m) => BankOption(id: '${m['CDC_B_ID']}', name: '${m['CDC_B_NAME']}'))
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
      return MonitoringTableResult(errorMessage: (text == null || text.isEmpty) ? 'Tidak ada data.' : text);
    }
    tables.sort((a, b) => b.querySelectorAll('td').length.compareTo(a.querySelectorAll('td').length));
    final table = tables.first;
    final trs = table.querySelectorAll('tr');
    if (trs.isEmpty) return const MonitoringTableResult(errorMessage: 'Tidak ada data.');

    final headers = trs.first.querySelectorAll('th, td').map((c) => c.text.trim()).toList();
    final rows = trs
        .skip(1)
        .map((tr) => tr.querySelectorAll('td').map((c) => c.text.trim()).toList())
        .where((r) => r.isNotEmpty)
        .toList();

    if (rows.isEmpty) return const MonitoringTableResult(errorMessage: 'Tidak ada data.');
    return MonitoringTableResult(headers: headers, rows: rows);
  }

  /// Muat halaman Pembayaran Kolektif sekali per sesi login.
  Future<String> _ensureKolektifPage() async {
    if (_kolektifHtml != null) return _kolektifHtml!;
    await _ensureCookieManager();
    final response = await _dio.get<String>(
      '/main.php',
      queryParameters: {'param': _kolektifParam},
      options: Options(responseType: ResponseType.plain),
    );
    _kolektifHtml = response.data ?? '';
    return _kolektifHtml!;
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
    final funcMode = StaffPortalTokenExtractor.extractFuncMode(html, 'reloadDataGroup', window: 800);
    final userId = StaffPortalTokenExtractor.extractKolektifUserId(html);
    if (funcMode == null || userId == null) {
      return const KolektifListResult(
        errorMessage: 'Gagal membaca token halaman Pembayaran Kolektif — coba buka ulang menunya.',
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
      'order[0][column]': '10',
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
        return const KolektifListResult(errorMessage: 'Format respons daftar grup tidak dikenali.');
      }
      final rows = (decoded['data'] as List).whereType<List>();
      final groups = rows.map((row) {
        String cell(int i) => i < row.length ? _stripHtml('${row[i]}') : '';
        return KolektifGroup(
          namaGroup: cell(1),
          namaKolektor: cell(2),
          hpKolektor: cell(3),
          anggota: cell(4),
          kodeBayar: cell(5),
          status: cell(6),
          kecamatan: cell(7),
          kelurahan: cell(8),
          keterangan: cell(9),
          tanggalKadaluarsa: cell(10),
        );
      }).toList();
      if (groups.isEmpty) return const KolektifListResult(errorMessage: 'Tidak ada data.');
      return KolektifListResult(groups: groups);
    } on FormatException {
      return const KolektifListResult(errorMessage: 'Gagal membaca daftar grup — format respons tidak sesuai dugaan.');
    }
  }

  String _stripHtml(String value) => (html_parser.parseFragment(value).text ?? value).trim();
}
