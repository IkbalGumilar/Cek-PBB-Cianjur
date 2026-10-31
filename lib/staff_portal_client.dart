import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'app_storage.dart';
import 'base_http_client.dart';
import 'kolektif_nop_berkas.dart';
import 'staff_portal/staff_portal_models.dart';
import 'staff_portal/staff_portal_parser.dart';
import 'staff_portal_token_extractor.dart';

export 'staff_portal/staff_portal_models.dart';

/// Klien HTTP untuk portal staf `cianjurkab.v-tax.id` — BEDA dari portal
/// publik `cektagihan.cianjurkab.v-tax.id` yang dipakai [PbbClient] (yang itu
/// tidak butuh login sama sekali). Portal ini pakai alur login klasik:
/// username + password + captcha, lalu verifikasi MFA (kode Google
/// Authenticator) sebelum sesi dianggap masuk.
class StaffPortalClient extends BaseHttpClient {
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

  StaffPortalClient({super.customDio})
    : super(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
      ) {
    dio.options.followRedirects = false;
    dio.options.validateStatus = (status) => status != null && status < 500;
  }

  Dio get _dio => dio;

  /// Cookie sesi (mis. `PHPSESSID`) disimpan ke berkas, bukan cuma di memori
  /// — supaya sesi login yang sudah terbentuk bertahan lewat restart
  /// aplikasi, tidak perlu login + MFA ulang tiap kali.
  Future<void> _ensureCookieManager() async {
    if (_cookieManagerAttached) return;
    final dir = await AppStorage.getCookiesDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage(dir.path),
    );
    _dio.interceptors.add(CookieManager(jar));
    _cookieManagerAttached = true;
  }

  /// Cek apakah sesi yang tersimpan (dari login sebelumnya) masih aktif di
  /// server, tanpa perlu username/password/captcha.
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
  /// hapus cookie & cache lokal.
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

  /// Login tahap 1 (username + password + captcha).
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
          StaffPortalParser.extractErrorMessage(page) ??
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
          StaffPortalParser.extractErrorMessage(page) ??
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

  String _normalizeLocation(String location) {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return location;
    }
    return location.startsWith('/') ? location : '/$location';
  }

  /// Muat halaman Monitoring Wilayah sekali per sesi login.
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

  /// Token `q` dari grup fungsi "s=23".
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
    return StaffPortalParser.parseGenericTable(response.data ?? '');
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

  /// Daftar Bank untuk dropdown filter (tab Sudah Bayar & Realisasi).
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
    final options = StaffPortalParser.parseBankJson(response.data ?? '');
    _bankOptionsCache = options;
    return options;
  }

  /// Muat halaman Pembayaran Kolektif sekali per sesi login.
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

    final options = StaffPortalParser.parseKolektifKelurahanOptions(html);
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

  /// Nama kecamatan untuk sebuah kode — replika `showKecamatanAll()`.
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
        data: {'id': '3205', 'funcMode': funcMode},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      return StaffPortalParser.parseKecamatanNameFromJson(
        response.data ?? '',
        code,
      );
    } on DioException {
      return '';
    }
  }

  /// BUAT grup kolektif baru — replika `tambahGroup()`.
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

  /// FINALKAN grup kolektif — replika fungsi `finalkan()` pada halaman asli.
  Future<KolektifActionResult> finalkanKolektifGroup({
    required String groupId,
  }) async {
    if (groupId.trim().isEmpty) {
      return const KolektifActionResult(
        success: false,
        message:
            'ID grup tidak terbaca dari daftar, jadi grup tidak difinalkan.',
      );
    }

    final html = await _ensureKolektifPage(forceReload: true);
    final userId = StaffPortalTokenExtractor.extractKolektifUserId(html);
    final funcMode = StaffPortalTokenExtractor.extractFinalkanFuncMode(html);
    if (userId == null || funcMode == null) {
      return const KolektifActionResult(
        success: false,
        message:
            'Token Finalkan tidak terbaca, jadi grup TIDAK difinalkan. '
            'Sesi mungkin sudah berakhir — masuk ulang lalu coba lagi.',
      );
    }

    final response = await _dio.post<String>(
      '/main.php',
      data: {'id': groupId.trim(), 'userID': userId, 'funcMode': funcMode},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    _kolektifHtml = null;
    return StaffPortalParser.parseKolektifActionJson(response.data ?? '');
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
    return StaffPortalParser.parseKolektifActionJson(response.data ?? '');
  }

  /// Unduh "Surat Pengantar" satu grup sebagai PDF — replika `pdfGroupInfo(group_id)`.
  Future<Uint8List> fetchSuratPengantarPdf(String groupId) async {
    await _ensureCookieManager();
    final response = await _dio.get<List<int>>(
      '/view/PBB/pembayaran_va/setPDFGroupInfo.php',
      queryParameters: {'id': groupId},
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
      throw StateError(
        'Server tidak mengirim berkas PDF. Sesi mungkin sudah berakhir — buka ulang menu Monitoring lalu coba lagi.',
      );
    }
    return bytes;
  }

  /// HAPUS grup kolektif — replika handler tombol `#btn-confirm-delete-group`.
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
    return StaffPortalParser.parseKolektifActionJson(response.data ?? '');
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
    return StaffPortalParser.parseKolektifMemberJson(response.data ?? '');
  }

  /// TAMBAH NOP ke dalam grup — replika `cariNOP()`.
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
    return StaffPortalParser.parseKolektifActionJson(response.data ?? '');
  }

  /// Tambahkan BANYAK NOP sekaligus dari berkas — satu NOP satu permintaan.
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
        hasil = StaffPortalParser.parseKolektifActionJson(response.data ?? '');
      } on DioException catch (e) {
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
    return StaffPortalParser.parseKolektifActionJson(response.data ?? '');
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

  /// Daftar grup Pembayaran Kolektif (read-only) — replika `reloadDataGroup()`.
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
    return StaffPortalParser.parseKolektifGroupsJson(response.data ?? '');
  }
}
