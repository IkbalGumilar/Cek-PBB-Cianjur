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
    final row = document.querySelector('table tbody tr');
    if (row == null) {
      final message = (document.body?.text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
      if (message.contains('captcha') || message.contains('huruf kode')) {
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
      final value = cell.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return value.isEmpty ? '—' : value;
    }).toList();
    if (cells.length < 10) {
      throw const BansosException(
        'Format hasil layanan berubah. Silakan coba lagi nanti.',
      );
    }

    final badge = document.querySelector('.badge');
    return BansosResult(
      periodeDtsen: badge?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '',
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
  String? _csrfToken;

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

  Future<Uint8List> fetchCaptchaImage() async {
    try {
      await _loadHome();
      final response = await _dio.get<List<int>>(
        '$_baseUrl/captcha/flat',
        queryParameters: {'_': DateTime.now().microsecondsSinceEpoch},
        options: Options(responseType: ResponseType.bytes),
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
          // Kemensos memakai pola POST-Redirect-GET. Dio tidak selalu
          // mengikuti 302 dari POST seperti browser, sehingga redirect perlu
          // diambil kembali sebagai GET sambil mempertahankan cookie sesi.
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: const {'Origin': _baseUrl, 'Referer': '$_baseUrl/'},
        ),
      );
      final responseHtml = await _redirectedResponseHtml(response);
      return BansosResult.fromHtml(responseHtml);
    } on DioException catch (error) {
      _logNetworkError('cek NIK', error);
      throw BansosException(
        _networkMessage(error),
        kind: BansosErrorKind.network,
      );
    }
  }

  Future<void> _loadHome() async {
    final response = await _dio.get<String>(
      _baseUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final document = html_parser.parse(response.data ?? '');
    final token = document
        .querySelector('input[name="_token"]')
        ?.attributes['value'];
    if (token == null || token.isEmpty) {
      throw const BansosException(
        'Sesi layanan tidak dapat dibuat. Coba beberapa saat lagi.',
      );
    }
    _csrfToken = token;
  }

  Future<String> _redirectedResponseHtml(Response<String> response) async {
    final statusCode = response.statusCode;
    if (statusCode == null || statusCode < 300 || statusCode >= 400) {
      return response.data ?? '';
    }

    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      throw const BansosException(
        'Layanan Kemensos mengarahkan permintaan tanpa halaman hasil.',
      );
    }

    final baseUri = Uri.parse(_baseUrl);
    final resultUri = baseUri.resolve(location);
    if (resultUri.scheme != baseUri.scheme || resultUri.host != baseUri.host) {
      throw const BansosException(
        'Layanan Kemensos mengarahkan ke alamat yang tidak dikenali.',
      );
    }

    final resultResponse = await _dio.get<String>(
      resultUri.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    return resultResponse.data ?? '';
  }

  static String _networkMessage(DioException error) {
    if (error.type == DioExceptionType.badResponse) {
      return 'Layanan Kemensos menolak permintaan (${error.response?.statusCode ?? 'tanpa status'}). Coba ulang captcha.';
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
