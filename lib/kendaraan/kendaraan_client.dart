import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../base_http_client.dart';

enum KendaraanErrorKind { notFound, rateLimited, network, service }

class KendaraanException implements Exception {
  final String message;
  final KendaraanErrorKind kind;
  final int? code;

  const KendaraanException(
    this.message, {
    this.kind = KendaraanErrorKind.service,
    this.code,
  });

  @override
  String toString() => message;
}

class KendaraanInfo {
  final String nomorPolisi;
  final String warna;
  final String merk;
  final String model;
  final String milikKe;
  final String jenis;
  final String tahunBuatan;
  final String wilayah;
  final String masaPajak;
  final String tanggalPajak;
  final String tanggalStnk;
  final Map<String, int> biaya;
  final int total;
  final String? keterangan;
  final bool canBePaid;
  final bool isFiveYear;
  final String tanggalProses;

  const KendaraanInfo({
    required this.nomorPolisi,
    required this.warna,
    required this.merk,
    required this.model,
    required this.milikKe,
    required this.jenis,
    required this.tahunBuatan,
    required this.wilayah,
    required this.masaPajak,
    required this.tanggalPajak,
    required this.tanggalStnk,
    required this.biaya,
    required this.total,
    required this.keterangan,
    required this.canBePaid,
    required this.isFiveYear,
    required this.tanggalProses,
  });

  factory KendaraanInfo.fromJson(Map<String, dynamic> json) {
    final umum = _map(json['informasi-umum']);
    final pajak = _map(json['informasi-pkb-pnbp']);
    final pembayaran = _map(json['pembayaran-pkb-pnbp']);
    final biaya = <String, int>{};
    for (final entry in pembayaran.entries) {
      final value = _int(entry.value);
      if (value != null) biaya[entry.key] = value;
    }

    return KendaraanInfo(
      nomorPolisi: _text(umum['nomor-polisi']),
      warna: _text(umum['warna']),
      merk: _text(umum['merk']),
      model: _text(umum['model']),
      milikKe: _text(umum['milik-ke']),
      jenis: _text(umum['jenis']),
      tahunBuatan: _text(umum['tahun-buatan']),
      wilayah: _text(pajak['wilayah']),
      masaPajak: _dateRange(pajak['dari'], pajak['ke']),
      tanggalPajak: _text(pajak['tanggal-pajak']),
      tanggalStnk: _text(pajak['tanggal-stnk']),
      biaya: biaya,
      total: _int(pembayaran['total']) ?? 0,
      keterangan: _nullableText(json['keterangan']),
      canBePaid: json['canBePaid'] == true,
      isFiveYear: json['isFiveYear'] == true,
      tanggalProses: _text(json['tanggal-proses']),
    );
  }

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : const <String, dynamic>{};

  static String _text(Object? value) => value?.toString().trim() ?? '-';

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String _dateRange(Object? from, Object? to) {
    final left = _text(from);
    final right = _text(to);
    if (left == '-' && right == '-') return '-';
    return '$left - $right';
  }
}

class KendaraanClient extends BaseHttpClient {
  static const baseUrl = 'https://sambara-v2.bapenda.jabarprov.go.id';
  // A developer can point the client at a temporary relay with
  // --dart-define=KENDARAAN_API_BASE_URL=... when the device network cannot
  // reach the official host. Production builds keep the official endpoint.
  static const apiBaseUrl = String.fromEnvironment(
    'KENDARAAN_API_BASE_URL',
    defaultValue: baseUrl,
  );

  // These values are part of the public JavaScript bundle supplied by the
  // official page. They are not treated as application secrets.
  static const _username = 'psip.bapenda';
  static const _password = 'jj4Mb+Lz1>j>UV&*0UNg~';
  static const _aesPassphrase = 'KKIC6ozwsqKXuk+q68GrTn2XdDNdeUAJcq1csvHl4T8=';
  static const _hmacSecret = '8jV2BITnbT3LCXVDd/Sa1P05m9BYvBMqK/zrvI0CvkQ=';

  Dio get _dio => dio;
  String? _token;
  Future<String>? _loginInFlight;

  KendaraanClient({Dio? dio})
      : super(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          customDio: dio,
        );

  Future<KendaraanInfo> check({
    required String platDepan,
    required String angka,
    required String platBelakang,
    required String warna,
  }) async {
    final depan = platDepan.trim().toUpperCase();
    final nomor = angka.trim();
    final belakang = platBelakang.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{1,2}$').hasMatch(depan) ||
        !RegExp(r'^\d{1,4}$').hasMatch(nomor) ||
        !RegExp(r'^[A-Z]{1,3}$').hasMatch(belakang)) {
      throw const KendaraanException('Nomor polisi belum lengkap.');
    }
    if (!RegExp(r'^[1-3]$').hasMatch(warna)) {
      throw const KendaraanException('Warna TNKB tidak valid.');
    }

    // The Sambara Bapenda Jabar backend strictly enforces that `no_polisi` must
    // be exactly 9 characters long. Shorter or longer values result in validation
    // errors (code 0001). The 9 characters are structured as:
    // - Slot 1 (Plat depan, 2 chars): right-padded with space
    // - Slot 2 (Plat belakang, 3 chars): right-padded with space
    // - Slot 3 (Nomor angka, 4 chars): right-padded with space
    final noPolisi = formatNoPolisi(
      platDepan: depan,
      angka: nomor,
      platBelakang: belakang,
    );
    try {
      var token = await _login();
      var response = await _getInfo(noPolisi, warna, token);
      if (_isTokenUsed(response)) {
        token = await _login(force: true);
        response = await _getInfo(noPolisi, warna, token);
      }
      return _parseResponse(response);
    } finally {
      // The service marks a bearer token as used after a lookup. Never reuse
      // it for a later search, including when the response is an error.
      _token = null;
    }
  }

  /// Formats the plate components into the fixed 9-character buffer
  /// required by the Sambara Bapenda Jabar backend:
  /// - Slot 1 (Plat depan, 2 chars): right-padded with space
  /// - Slot 2 (Plat belakang, 3 chars): right-padded with space
  /// - Slot 3 (Nomor angka, 4 chars): right-padded with space
  /// Total length is strictly guaranteed to be 9 characters.
  static String formatNoPolisi({
    required String platDepan,
    required String angka,
    required String platBelakang,
  }) {
    final depan = platDepan.trim().toUpperCase().padRight(2, ' ');
    final belakang = platBelakang.trim().toUpperCase().padRight(3, ' ');
    final nomor = angka.trim().padRight(4, ' ');
    return '$depan$belakang$nomor';
  }

  Future<String> _login({bool force = false}) {
    if (!force && _token != null) return Future.value(_token!);
    final inFlight = _loginInFlight;
    if (!force && inFlight != null) return inFlight;
    final future = _requestLogin();
    _loginInFlight = future;
    return future.whenComplete(() => _loginInFlight = null);
  }

  Future<String> _requestLogin() async {
    final data = _encryptPayload({
      'username': _username,
      'password': _password,
    });
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = _nonce();
    final signature = _signature(data, timestamp, nonce);
    try {
      final response = await _dio.post<dynamic>(
        '/api/renew-sambara/v2/login',
        data: {
          'data': data,
          'timestamp': timestamp,
          'nonce': nonce,
          'signature': signature,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final body = _map(response.data);
      if (body['success'] == true) {
        final token = _map(body['data'])['token']?.toString();
        if (token != null && token.isNotEmpty) {
          _token = token;
          return token;
        }
      }
      throw _exceptionFromBody(body, response.statusCode);
    } on KendaraanException {
      rethrow;
    } on DioException catch (error) {
      throw _networkException(error);
    }
  }

  Future<Response<dynamic>> _getInfo(
    String noPolisi,
    String warna,
    String token,
  ) async {
    try {
      return await _dio.post<dynamic>(
        '/api/renew-sambara/v2/get-info-pkb-v2',
        data: {'no_polisi': noPolisi, 'kd_plat': warna},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (error) {
      throw _networkException(error);
    }
  }

  KendaraanInfo _parseResponse(Response<dynamic> response) {
    final body = _map(response.data);
    if (body['success'] == true && body['data'] is Map) {
      return KendaraanInfo.fromJson(_map(body['data']));
    }
    throw _exceptionFromBody(body, response.statusCode);
  }

  KendaraanException _exceptionFromBody(
    Map<String, dynamic> body,
    int? statusCode,
  ) {
    final code = int.tryParse(body['code']?.toString() ?? '');
    final message = body['message']?.toString().trim();
    if (code == 76 || body['code']?.toString() == '0076') {
      return KendaraanException(
        'Data kendaraan tidak ditemukan.',
        kind: KendaraanErrorKind.notFound,
        code: code,
      );
    }
    if (statusCode == 429 || code == 429000) {
      return KendaraanException(
        message?.isNotEmpty == true
            ? message!
            : 'Permintaan terlalu sering. Coba lagi beberapa saat.',
        kind: KendaraanErrorKind.rateLimited,
        code: code,
      );
    }

    String? resolvedMessage = message;
    final detail = body['detail'];
    if (detail is List && detail.isNotEmpty) {
      final detailStr = detail
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
      if (detailStr.isNotEmpty) {
        resolvedMessage = (resolvedMessage != null && resolvedMessage.isNotEmpty)
            ? '$resolvedMessage: $detailStr'
            : detailStr;
      }
    }

    return KendaraanException(
      resolvedMessage?.isNotEmpty == true
          ? resolvedMessage!
          : 'Layanan kendaraan gagal merespons.',
      code: code,
    );
  }

  KendaraanException _networkException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const KendaraanException(
        'Layanan kendaraan terlalu lama merespons. Periksa koneksi lalu coba lagi.',
        kind: KendaraanErrorKind.network,
      );
    }
    final status = error.response?.statusCode;
    if (status != null && status >= 500) {
      return KendaraanException(
        'Server Samsat/Bapenda sedang bermasalah (HTTP $status). Silakan coba lagi nanti.',
        kind: KendaraanErrorKind.service,
        code: status,
      );
    }
    return const KendaraanException(
      'Tidak dapat menghubungi layanan kendaraan. Periksa koneksi internet.',
      kind: KendaraanErrorKind.network,
    );
  }

  static bool _isTokenUsed(Response<dynamic> response) {
    final body = _map(response.data);
    return body['code']?.toString() == '401006';
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    if (value is String && value.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((key, val) => MapEntry(key.toString(), val));
        }
      } catch (_) {
        // Not a valid JSON string map.
      }
    }
    return const <String, dynamic>{};
  }

  static String _nonce() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _signature(String data, int timestamp, String nonce) {
    final value = utf8.encode('$data$timestamp$nonce');
    return Hmac(sha256, utf8.encode(_hmacSecret)).convert(value).toString();
  }

  static String _encryptPayload(Map<String, String> payload) {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final salt = Uint8List.fromList(
      List<int>.generate(8, (_) => math.Random.secure().nextInt(256)),
    );
    final keyAndIv = _evpBytesToKey(utf8.encode(_aesPassphrase), salt, 48);
    final key = encrypt.Key(Uint8List.fromList(keyAndIv.sublist(0, 32)));
    final iv = encrypt.IV(Uint8List.fromList(keyAndIv.sublist(32, 48)));
    final encrypted = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    ).encryptBytes(plain, iv: iv);
    return base64Encode(<int>[
      ...utf8.encode('Salted__'),
      ...salt,
      ...encrypted.bytes,
    ]);
  }

  static Uint8List _evpBytesToKey(
    List<int> password,
    List<int> salt,
    int length,
  ) {
    final result = <int>[];
    var previous = <int>[];
    while (result.length < length) {
      previous = md5.convert(<int>[...previous, ...password, ...salt]).bytes;
      result.addAll(previous);
    }
    return Uint8List.fromList(result.take(length).toList());
  }
}
