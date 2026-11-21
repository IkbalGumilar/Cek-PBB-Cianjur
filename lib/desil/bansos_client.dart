import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../base_http_client.dart';

enum BansosErrorKind { captcha, notFound, service, network }

class BansosException implements Exception {
  final String message;
  final BansosErrorKind kind;

  const BansosException(this.message, {this.kind = BansosErrorKind.service});

  @override
  String toString() => message;
}

class BansosResult {
  final String periodeDtsen;
  final String nama;
  final String desil;
  final String sembakoStatus;
  final String sembakoPeriode;
  final String pkhStatus;
  final String pkhPeriode;
  final String pbiJkStatus;
  final String pbiJkPeriode;
  final String keteranganPbi;
  final String statusKpd;

  const BansosResult({
    required this.periodeDtsen,
    required this.nama,
    required this.desil,
    required this.sembakoStatus,
    required this.sembakoPeriode,
    required this.pkhStatus,
    required this.pkhPeriode,
    required this.pbiJkStatus,
    required this.pbiJkPeriode,
    required this.keteranganPbi,
    required this.statusKpd,
  });

  factory BansosResult.fromHtml(String html) {
    final document = html_parser.parse(html);
    String cleanText(String? raw) =>
        (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    String dashIfEmpty(String? raw) {
      final t = cleanText(raw);
      return (t.isEmpty || t == '-') ? '—' : t;
    }

    // 1. Cek pesan alert eksplisit pada format baru (.cb-alert / .alert)
    final alertText = cleanText(
      document.querySelector('.cb-alert, .alert-danger, .alert')?.text,
    ).toLowerCase();
    if (alertText.isNotEmpty) {
      if (alertText.contains('captcha') || alertText.contains('huruf kode')) {
        throw const BansosException(
          'Captcha salah atau sudah kedaluwarsa.',
          kind: BansosErrorKind.captcha,
        );
      }
      if (alertText.contains('tidak ditemukan') ||
          alertText.contains('data tidak ada') ||
          alertText.contains('tidak terdaftar') ||
          alertText.contains('belum terdaftar')) {
        throw const BansosException(
          'Data penerima manfaat tidak ditemukan.',
          kind: BansosErrorKind.notFound,
        );
      }
    }

    // 2. Cek kartu kosong pada halaman /hasil-nik format baru (.cb-empty)
    final emptyCard = document.querySelector('.cb-empty');
    if (emptyCard != null) {
      throw const BansosException(
        'Data penerima manfaat tidak ditemukan.',
        kind: BansosErrorKind.notFound,
      );
    }

    // 3. Parsing format baru cb-v4 (/hasil-nik dengan .cb-profile & .cb-programs)
    final profileNameEl = document.querySelector(
      '.cb-profile .cb-name, .cb-v4 .cb-name',
    );
    if (profileNameEl != null) {
      final nama = dashIfEmpty(profileNameEl.text);
      String desil = dashIfEmpty(
        document
            .querySelector('.cb-desil, .cb-stat-desil .cb-stat-value')
            ?.text,
      );
      String periodeDtsen = cleanText(
        document.querySelector('.cb-hero .cb-chip, .badge')?.text,
      );
      String keteranganPbi = '—';
      String statusKpd = '—';

      for (final stat in document.querySelectorAll('.cb-profile-stats .cb-stat')) {
        if (stat.classes.contains('cb-stat-desil')) {
          if (desil == '—') {
            desil = dashIfEmpty(
              stat.querySelector('.cb-desil, .cb-stat-value')?.text,
            );
          }
          continue;
        }
        final kicker = cleanText(
          stat.querySelector('.cb-kicker')?.text,
        ).toLowerCase();
        final val = dashIfEmpty(
          stat.querySelector('.cb-stat-value, .cb-desil')?.text,
        );
        if (kicker.contains('kpd') || kicker.contains('disabilitas')) {
          statusKpd = val;
        } else if (kicker.contains('pbi') || kicker.contains('keterangan')) {
          keteranganPbi = val;
        } else if (kicker.contains('periode') || kicker.contains('dtsen')) {
          if (periodeDtsen.isEmpty && val != '—') {
            periodeDtsen = val;
          }
        }
      }

      String sembakoStatus = '—';
      String sembakoPeriode = '—';
      String pkhStatus = '—';
      String pkhPeriode = '—';
      String pbiJkStatus = '—';
      String pbiJkPeriode = '—';

      for (final prog in document.querySelectorAll('.cb-program')) {
        final title = cleanText(
          prog.querySelector('.cb-program-head h3, h3, .cb-kicker')?.text,
        ).toLowerCase();

        String status = '—';
        String periode = '—';
        String ekstra = '—';

        final dlDivs = prog.querySelectorAll('.cb-dl > div');
        if (dlDivs.isNotEmpty) {
          for (final item in dlDivs) {
            final dt = cleanText(item.querySelector('dt')?.text).toLowerCase();
            final dd = dashIfEmpty(item.querySelector('dd')?.text);
            if (dt.contains('status')) {
              status = dd;
            } else if (dt.contains('periode')) {
              periode = dd;
            } else if (dt.contains('keterangan') || dt.contains('info')) {
              ekstra = dd;
            }
          }
        } else {
          final dts = prog.querySelectorAll('dt');
          final dds = prog.querySelectorAll('dd');
          final count = dts.length < dds.length ? dts.length : dds.length;
          for (int i = 0; i < count; i++) {
            final dt = cleanText(dts[i].text).toLowerCase();
            final dd = dashIfEmpty(dds[i].text);
            if (dt.contains('status')) {
              status = dd;
            } else if (dt.contains('periode')) {
              periode = dd;
            } else if (dt.contains('keterangan')) {
              ekstra = dd;
            }
          }
        }

        if (title.contains('sembako') || title.contains('bpnt')) {
          sembakoStatus = status;
          sembakoPeriode = periode;
        } else if (title.contains('pkh')) {
          pkhStatus = status;
          pkhPeriode = periode;
        } else if (title.contains('pbi')) {
          pbiJkStatus = status;
          pbiJkPeriode = periode;
          if (ekstra != '—' && keteranganPbi == '—') {
            keteranganPbi = ekstra;
          }
        } else if (title.contains('kpd') || title.contains('disabilitas')) {
          if (status != '—') statusKpd = status;
        }
      }

      return BansosResult(
        periodeDtsen: periodeDtsen,
        nama: nama,
        desil: desil,
        sembakoStatus: sembakoStatus,
        sembakoPeriode: sembakoPeriode,
        pkhStatus: pkhStatus,
        pkhPeriode: pkhPeriode,
        pbiJkStatus: pbiJkStatus,
        pbiJkPeriode: pbiJkPeriode,
        keteranganPbi: keteranganPbi,
        statusKpd: statusKpd,
      );
    }

    // 4. Fallback format tabel lama (table tbody tr)
    final row = document.querySelector('table tbody tr');
    if (row == null) {
      final hasSearchForm =
          document.querySelector('form[action*="cekbansos_nik"]') != null;
      final message = cleanText(document.body?.text).toLowerCase();
      if (!hasSearchForm &&
          (message.contains('captcha') || message.contains('huruf kode'))) {
        throw const BansosException(
          'Captcha salah atau sudah kedaluwarsa.',
          kind: BansosErrorKind.captcha,
        );
      }
      if (message.contains('kode captcha salah') ||
          message.contains('captcha tidak sesuai')) {
        throw const BansosException(
          'Captcha salah atau sudah kedaluwarsa.',
          kind: BansosErrorKind.captcha,
        );
      }
      if (message.contains('tidak ditemukan') ||
          message.contains('data tidak ada') ||
          message.contains('tidak terdaftar') ||
          message.contains('belum terdaftar')) {
        throw const BansosException(
          'Data penerima manfaat tidak ditemukan.',
          kind: BansosErrorKind.notFound,
        );
      }
      throw const BansosException(
        'Hasil dari layanan belum dapat diproses. Silakan coba lagi nanti.',
      );
    }

    final cells = row.querySelectorAll('td').map((cell) {
      return dashIfEmpty(cell.text);
    }).toList();
    if (cells.length < 10) {
      throw const BansosException(
        'Format hasil layanan berubah. Silakan coba lagi nanti.',
      );
    }

    final badge = document.querySelector('.badge');
    return BansosResult(
      periodeDtsen: cleanText(badge?.text),
      nama: cells[0],
      desil: cells[1],
      sembakoStatus: cells[2],
      sembakoPeriode: cells[3],
      pkhStatus: cells[4],
      pkhPeriode: cells[5],
      pbiJkStatus: cells[6],
      pbiJkPeriode: cells[7],
      keteranganPbi: cells[8],
      statusKpd: cells[9],
    );
  }
}

class BansosClient extends BaseHttpClient {
  static const _baseUrl = 'https://cekbansos.kemensos.go.id';
  static const _formUrl =
      '$_baseUrl/?page_title=FORM%20PENCARIAN%20PM%20%28PENERIMA%20MANFAAT%29';
  String? _csrfToken;
  String? _captchaUrl;

  Dio get _dio => dio;

  BansosClient({Dio? dio})
    : super(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        enableCookies: true,
        customDio: dio,
      );

  Future<Uint8List> fetchCaptchaImage({bool forceNewSession = false}) async {
    try {
      String targetUrl;
      if (forceNewSession || _csrfToken == null || _captchaUrl == null) {
        await _loadHome();
        targetUrl = (_captchaUrl != null && _captchaUrl!.isNotEmpty)
            ? _captchaUrl!
            : '$_baseUrl/captcha/flat';
      } else {
        // Sama seperti tombol refresh resmi Kemensos: pakai sesi aktif & cache-buster acak.
        targetUrl =
            '$_baseUrl/captcha/flat?${DateTime.now().millisecondsSinceEpoch}';
      }
      final useQueryTimestamp = !targetUrl.contains('?');
      final response = await _dio.get<List<int>>(
        targetUrl,
        queryParameters: useQueryTimestamp
            ? {'_': DateTime.now().microsecondsSinceEpoch}
            : null,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Referer': _formUrl},
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const BansosException('Captcha tidak dapat dimuat.');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      _logNetworkError('captcha', error);
      throw BansosException(
        _networkMessage(error),
        kind: BansosErrorKind.network,
      );
    }
  }

  Future<BansosResult> checkByNik({
    required String nik,
    required String captcha,
  }) async {
    try {
      if (_csrfToken == null) await _loadHome();
      final response = await _dio.post<String>(
        '$_baseUrl/cekbansos_nik',
        data: {'_token': _csrfToken, 'nik_input': nik, 'captcha': captcha},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          // Kemensos memakai pola POST-Redirect-GET (302 ke /hasil-nik atau /).
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: const {'Origin': _baseUrl, 'Referer': _formUrl},
        ),
      );
      final responseHtml = await _redirectedResponseHtml(response);
      _updateTokensFromHtml(responseHtml);
      return BansosResult.fromHtml(responseHtml);
    } on DioException catch (error) {
      _logNetworkError('cek NIK', error);
      if (error.response?.statusCode == 419) {
        _csrfToken = null;
        _captchaUrl = null;
        throw const BansosException(
          'Sesi captcha sudah kedaluwarsa. Kode baru sedang dimuat.',
          kind: BansosErrorKind.captcha,
        );
      }
      throw BansosException(
        _networkMessage(error),
        kind: BansosErrorKind.network,
      );
    }
  }

  Future<void> _loadHome() async {
    final response = await _dio.get<String>(
      _formUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final html = response.data ?? '';
    _updateTokensFromHtml(html);
    if (_csrfToken == null || _csrfToken!.isEmpty) {
      throw const BansosException(
        'Sesi layanan tidak dapat dibuat. Coba beberapa saat lagi.',
      );
    }
  }

  void _updateTokensFromHtml(String html) {
    if (html.isEmpty) return;
    final document = html_parser.parse(html);
    final token =
        document
            .querySelector('input[name="_token"]')
            ?.attributes['value']
            ?.trim() ??
        document
            .querySelector('meta[name="csrf-token"]')
            ?.attributes['content']
            ?.trim();
    if (token != null && token.isNotEmpty) {
      _csrfToken = token;
    }

    final rawCapSrc = document
        .querySelector('img#captchaCode2, img.cb-captcha-img')
        ?.attributes['src']
        ?.trim();
    if (rawCapSrc != null && rawCapSrc.isNotEmpty) {
      final resolved = Uri.parse(_baseUrl).resolve(rawCapSrc);
      if (resolved.host == Uri.parse(_baseUrl).host) {
        _captchaUrl = resolved.toString();
      }
    }
  }

  Future<String> _redirectedResponseHtml(Response<String> response) async {
    final statusCode = response.statusCode;
    if (statusCode == null || statusCode < 300 || statusCode >= 400) {
      return response.data ?? '';
    }

    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      throw const BansosException(
        'Layanan Kemensos belum mengembalikan halaman hasil. Silakan coba lagi.',
      );
    }

    final baseUri = Uri.parse(_baseUrl);
    final resultUri = baseUri.resolve(location);
    if (resultUri.scheme != baseUri.scheme || resultUri.host != baseUri.host) {
      throw const BansosException(
        'Respons layanan Kemensos tidak dikenali. Silakan coba beberapa saat lagi.',
      );
    }

    final resultResponse = await _dio.get<String>(
      resultUri.toString(),
      options: Options(
        responseType: ResponseType.plain,
        headers: const {'Referer': _formUrl},
      ),
    );
    return resultResponse.data ?? '';
  }

  static String _networkMessage(DioException error) {
    if (error.type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      if (status == 429) {
        return 'Layanan Kemensos sedang sibuk karena banyak permintaan. Tunggu sebentar lalu coba lagi.';
      }
      if (status != null && status >= 500) {
        return 'Server Kemensos sedang mengalami gangguan. Silakan coba beberapa saat lagi.';
      }
      return 'Layanan Kemensos belum dapat memproses permintaan. Silakan muat ulang kode lalu coba lagi.';
    }
    return BaseHttpClient.describeNetworkError(error, serviceName: 'Kemensos');
  }

  static void _logNetworkError(String operation, DioException error) {
    developer.log(
      '$operation gagal: type=${error.type}, status=${error.response?.statusCode ?? '-'}',
      name: 'CekDesil',
    );
  }
}
