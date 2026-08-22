import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'blok_record.dart' show formatRibuan;
import 'check_mode.dart';
import 'qris_result.dart';
import 'tagihan_result.dart';
import 'va_result.dart';

class PbbResult {
  final String status;
  final String rawText;
  final String? namaWajibPajak;
  final String? tanggalBayar;
  final String? jumlahPbb;

  PbbResult(
    this.status,
    this.rawText, {
    this.namaWajibPajak,
    this.tanggalBayar,
    this.jumlahPbb,
  });
}

class CaptchaError implements Exception {
  final String message;

  CaptchaError(this.message);
}

const _captchaErrorKeywords = [
  'kode verifikasi harus benar',
  'kode verifikasi salah',
  'verifikasi salah',
  'captcha salah',
  'kode salah',
  'captcha tidak sesuai',
  'kode tidak sesuai',
];

class PbbClient {
  static const _baseUrl = 'https://cektagihan.cianjurkab.v-tax.id/portlet.php';
  static const _captchaBaseUrl =
      'https://cektagihan.cianjurkab.v-tax.id/image-2018/securimage_show.php';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  final CookieJar _cookieJar = CookieJar();

  PbbClient() {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<Uint8List> fetchCaptchaImage(CheckMode mode) async {
    await _dio.get(_baseUrl);
    final namespace = mode == CheckMode.statusBayar ? 'pbb' : 'single';
    final response = await _dio.get<List<int>>(
      '$_captchaBaseUrl?namespace=$namespace',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<PbbResult> checkStatusBayar({
    required String nop,
    required String tahun,
    required String captchaCode,
  }) async {
    final response = await _dio.post<String>(
      _baseUrl,
      data: {
        'fungsi': 'cek-stts-pbb',
        'area': '',
        'client': '',
        'nop2': nop,
        'thn2': tahun,
        'cImage2': captchaCode,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    return _classifyStatusBayar(response.data ?? '');
  }

  Future<TagihanResult> checkTagihan({
    required String nop,
    required String captchaCode,
  }) async {
    final response = await _dio.post<String>(
      _baseUrl,
      data: {
        'fungsi': 'cek-tagihan-pbb',
        'area': '',
        'client': '',
        'tahun-pajak-1': '',
        'tahun-pajak-2': '',
        'nop': nop,
        'cImagePBB': captchaCode,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    return _parseTagihan(response.data ?? '');
  }

  TagihanResult parseTagihanResponse(String html) => _parseTagihan(html);

  PbbResult classifyStatusBayarResponse(String html) =>
      _classifyStatusBayar(html);

  void _throwIfCaptchaError(String text) {
    final lowered = text.toLowerCase();
    for (final kw in _captchaErrorKeywords) {
      if (lowered.contains(kw)) {
        throw CaptchaError('Captcha salah/gagal, silakan coba lagi.');
      }
    }
  }

  PbbResult _classifyStatusBayar(String html) {
    final document = html_parser.parse(html);
    final text = _responseText(document);
    _throwIfCaptchaError(text);
    final lowered = text.toLowerCase();

    final inactiveMessage = _inactiveSpptMessage(lowered);
    if (inactiveMessage != null) {
      return PbbResult(inactiveMessage, text);
    }

    if (lowered.contains('data tidak ditemukan')) {
      return PbbResult('Belum Bayar (Data Tidak Ditemukan)', text);
    }

    final nama = _extractColumn(
      document,
      (h) => h.contains('nama wajib pajak'),
    );
    final jumlahPbb = _extractColumn(document, (h) => h == 'pbb');

    final match = RegExp(
      r'lunas\s+([\d\-:\s]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final tanggal = match.group(1)!.trim();
      return PbbResult(
        'Sudah Bayar (LUNAS $tanggal)',
        text,
        namaWajibPajak: nama,
        tanggalBayar: tanggal,
        jumlahPbb: jumlahPbb,
      );
    }
    if (lowered.contains('lunas')) {
      return PbbResult(
        'Sudah Bayar (LUNAS)',
        text,
        namaWajibPajak: nama,
        jumlahPbb: jumlahPbb,
      );
    }

    return PbbResult(
      'Perlu Cek Manual (status tidak dikenali)',
      text,
      namaWajibPajak: nama,
    );
  }

  /// Ambil isi kolom pertama dari baris data pertama pada tabel hasil, dicari
  /// lewat header yang cocok dengan [matchesHeader] (dibandingkan dalam huruf
  /// kecil). Dipakai untuk kolom "Nama Wajib Pajak" dan "PBB" pada tabel hasil
  /// Cek Status Bayar.
  String? _extractColumn(
    Document document,
    bool Function(String header) matchesHeader,
  ) {
    final table = _findResultTable(document);
    if (table == null) return null;

    final headerCells =
        table
            .querySelector('tr')
            ?.querySelectorAll('th, td')
            .map((c) => c.text.trim().toLowerCase())
            .toList() ??
        [];
    final col = headerCells.indexWhere(matchesHeader);
    if (col == -1) return null;

    final dataRows = table.querySelectorAll('tr').skip(1).toList();
    if (dataRows.isEmpty) return null;

    final cells = dataRows.first
        .querySelectorAll('td')
        .map((c) => c.text.trim())
        .toList();
    if (col >= cells.length) return null;

    final value = cells[col];
    return value.isEmpty ? null : value;
  }

  TagihanResult _parseTagihan(String html) {
    final document = html_parser.parse(html);
    final text = _responseText(document);
    _throwIfCaptchaError(text);

    final inactiveMessage = _inactiveSpptMessage(text.toLowerCase());
    if (inactiveMessage != null) {
      return TagihanResult.message(
        inactiveMessage,
        text,
        inactiveUntilYear: _inactiveSpptYear(text.toLowerCase()),
      );
    }

    if (text.toLowerCase().contains('tidak ditemukan') ||
        text.toLowerCase().contains('data tidak ada')) {
      return TagihanResult.notFound(text);
    }

    final table = _findResultTable(document);
    if (table == null) {
      return TagihanResult.notFound(text);
    }

    final headerCells =
        table
            .querySelector('tr')
            ?.querySelectorAll('th, td')
            .map((c) => c.text.trim().toLowerCase())
            .toList() ??
        [];

    int findColumn(List<String> keywords) {
      for (var i = 0; i < headerCells.length; i++) {
        if (keywords.any((kw) => headerCells[i].contains(kw))) return i;
      }
      return -1;
    }

    final namaCol = findColumn(['nama wajib pajak']);
    final tahunCol = findColumn(['tahun pajak']);
    final pbbCol = findColumn(['pbb']);
    final dendaCol = findColumn(['denda']);
    final kurangCol = findColumn(['kurang bayar', 'kurangbayar']);
    final statusCol = findColumn(['status bayar', 'status pembayaran']);

    final dataRows = table.querySelectorAll('tr').skip(1).toList();
    final rows = <TagihanYearRow>[];
    var namaWajibPajak = '';
    var totalPbb = '';
    var totalDenda = '';
    var totalKurangBayar = '';

    for (final tr in dataRows) {
      final cells = tr
          .querySelectorAll('td')
          .map((c) => c.text.trim())
          .toList();
      if (cells.isEmpty) continue;

      String cellAt(int idx) =>
          (idx >= 0 && idx < cells.length) ? cells[idx] : '';

      final nama = cellAt(namaCol);
      final tahun = cellAt(tahunCol);
      final pbb = cellAt(pbbCol);
      final denda = cellAt(dendaCol);
      final kurang = cellAt(kurangCol);

      final isTotalRow = nama.isEmpty && tahun.isEmpty && pbb.isNotEmpty;
      if (isTotalRow) {
        totalPbb = pbb;
        totalDenda = denda;
        totalKurangBayar = kurang;
        continue;
      }
      if (tahun.isEmpty) continue;

      if (nama.isNotEmpty) namaWajibPajak = nama;
      rows.add(
        TagihanYearRow(
          tahun: tahun,
          pbb: pbb,
          denda: denda,
          kurangBayar: kurang,
          statusBayar: cellAt(statusCol),
          paymentCodeVa: _extractPaymentCodeVa(tr),
        ),
      );
    }

    if (rows.isEmpty) {
      return TagihanResult.notFound(text);
    }

    return TagihanResult(
      namaWajibPajak: namaWajibPajak,
      rows: rows,
      totalPbb: totalPbb,
      totalDenda: totalDenda,
      totalKurangBayar: totalKurangBayar,
      notFound: false,
      rawText: text,
    );
  }

  String _responseText(Document document) =>
      (document.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _inactiveSpptMessage(String loweredText) {
    if (!loweredText.contains('aktif sampai dengan tahun')) return null;

    final year = _inactiveSpptYear(loweredText);
    return year == null || year.isEmpty
        ? 'SPPT tidak aktif. Silakan datang ke kantor Bapenda untuk menerbitkan SPPT terbaru.'
        : 'SPPT tidak aktif dari tahun $year. Silakan datang ke kantor Bapenda untuk menerbitkan SPPT terbaru.';
  }

  String? _inactiveSpptYear(String loweredText) => RegExp(
    r'aktif sampai dengan tahun\s*(\d{4})?',
  ).firstMatch(loweredText)?.group(1);

  /// Ambil kode bayar VA dari tombol "Payment VA" pada baris tabel [tr],
  /// contoh: onclick="confirmVA(0, '2026','1261179232')" -> '1261179232'.
  /// Server tidak mencantumkan kode ini di teks kolom manapun, hanya di
  /// attribute onclick, jadi harus digali dari HTML mentah baris tersebut.
  String? _extractPaymentCodeVa(Element tr) {
    final button = tr
        .querySelectorAll('button')
        .firstWhere(
          (b) => (b.attributes['onclick'] ?? '').startsWith('confirmVA('),
          orElse: () => Element.tag('button'),
        );
    final onclick = button.attributes['onclick'];
    if (onclick == null) return null;
    final match = RegExp(
      r"confirmVA\(\s*\d+\s*,\s*'[^']*'\s*,\s*'([^']*)'\s*\)",
    ).firstMatch(onclick);
    return match?.group(1);
  }

  Element? _findResultTable(Document document) {
    final tables = document.querySelectorAll('table');
    if (tables.isEmpty) return null;
    tables.sort(
      (a, b) => b
          .querySelectorAll('td')
          .length
          .compareTo(a.querySelectorAll('td').length),
    );
    return tables.first;
  }

  /// Ambil bytes PDF "Tagihan PBB" (satu dokumen untuk seluruh tahun NOP ini),
  /// mereplikasi tombol "Cetak PDF" di atas tabel hasil Cek Tagihan
  /// (JS: printToPDF1 -> print-pdf.php).
  Future<Uint8List> fetchTagihanPdf({required String nop}) async {
    final response = await _dio.get<List<int>>(
      'https://cektagihan.cianjurkab.v-tax.id/print-pdf.php',
      queryParameters: {
        'nop': nop,
        'idwp': '',
        'thn1': '',
        'thn2': '',
        'act': '(Cetak PDF)',
        'fungsi': 'cek-tagihan-pbb',
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return _requirePdfBytes(response);
  }

  /// Ambil bytes PDF "Bukti Bayar" (STTS) untuk satu NOP+tahun, mereplikasi
  /// tombol cetak di kolom STTS hasil Cek Status Bayar
  /// (JS: printPDF -> stts-pdf-pbb.php).
  Future<Uint8List> fetchBuktiBayarPdf({
    required String nop,
    required String tahun,
  }) async {
    final response = await _dio.get<List<int>>(
      'https://cektagihan.cianjurkab.v-tax.id/stts-pdf-pbb.php',
      queryParameters: {
        'nop': nop,
        'thn': tahun,
        'act': '(Cetak STTS)',
        'fungsi': 'cek-stts-pbb',
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return _requirePdfBytes(response);
  }

  Uint8List _requirePdfBytes(Response<List<int>> response) {
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.toLowerCase().contains('pdf')) {
      throw Exception(
        'Server tidak mengembalikan PDF (sesi mungkin sudah habis, coba cek ulang).',
      );
    }
    return Uint8List.fromList(response.data!);
  }

  Future<QrisResult> generateQrisPbb({
    required String nop,
    required String tahun,
  }) async {
    final response = await _dio.post<String>(
      'https://cektagihan.cianjurkab.v-tax.id/svcGenerateQrcode.php',
      data: {
        'modul': 'pbb',
        'kdbayar': nop,
        'tahun': tahun,
        'area': '3205',
        'tax_type': '2',
        'email': '',
        'telp': '',
        'kode_bank': '3202110',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final raw = response.data ?? '';

    try {
      final json = jsonDecode(raw);
      if (json is Map && json['rc'] != '0000') {
        if (json['rc'] == '0014') {
          throw QrisGenerationError(
            'NOP ini untuk tahun $tahun sudah pernah generate VA. Silakan gunakan pembayaran VA.',
          );
        }
        throw QrisGenerationError(
          'Terjadi kesalahan sistem, silakan dicoba beberapa saat lagi.',
        );
      }
    } on FormatException {
      // Bukan JSON -> respons sukses berupa HTML berisi QR code, lanjut parse di bawah.
    }

    return _parseQrisHtml(raw);
  }

  /// Generate Virtual Account BJB untuk pembayaran PBB, replika tombol
  /// "Payment VA" di portal resmi (JS: generateVA -> svcGenerateVA.php).
  /// [paymentCode] wajib diisi dari [TagihanYearRow.paymentCodeVa] baris yang
  /// bersangkutan, ini kode unik per NOP+tahun yang dibutuhkan server.
  Future<VaResult> generateVaPbb({
    required String nop,
    required String tahun,
    required String paymentCode,
  }) async {
    final response = await _dio.post<String>(
      'https://cektagihan.cianjurkab.v-tax.id/svcGenerateVA.php',
      data: {
        'modul': 'pbb',
        'kdbayar': nop,
        'tahun': tahun,
        'area': '3205',
        'tax_type': '2',
        'payment_code': paymentCode,
        'email': '',
        'telp': '',
        'kode_bank': '3202110',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final raw = response.data ?? '';
    final json = jsonDecode(raw);
    if (json is! Map || json['rc'] != '0000') {
      final rc = json is Map ? json['rc'] : null;
      if (rc == '0014') {
        throw VaGenerationError(
          'NOP ini untuk tahun $tahun sudah pernah generate QRIS. Silakan gunakan pembayaran QRIS.',
        );
      }
      final rcm = json is Map ? json['rcm'] as String? : null;
      throw VaGenerationError(
        rcm ?? 'Terjadi kesalahan sistem, silakan dicoba beberapa saat lagi.',
      );
    }

    final data = json['data'] as Map;
    final amountValue =
        num.tryParse(data['trx_amount'].toString())?.round() ?? 0;
    return VaResult(
      virtualAccount: data['virtual_account'].toString(),
      customerName: data['customer_name'].toString(),
      amount: formatRibuan(amountValue),
      expiredAt: data['datetime_expired'].toString(),
    );
  }

  QrisResult _parseQrisHtml(String html) {
    final imageMatch = RegExp(
      r'data:image/png;base64,([A-Za-z0-9+/=]+)',
    ).firstMatch(html);
    if (imageMatch == null) {
      throw QrisGenerationError('Gagal membaca QRIS dari respons server.');
    }

    final document = html_parser.parse(html);
    final texts = document
        .querySelectorAll('div')
        .map((d) => d.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    String findText(bool Function(String) matcher, String fallback) =>
        texts.firstWhere(matcher, orElse: () => fallback);

    return QrisResult(
      qrImageBytes: base64Decode(imageMatch.group(1)!),
      transactionId: findText((t) => t.toUpperCase().startsWith('QRIS'), '-'),
      amount: findText((t) => t.toLowerCase().contains('rp'), '-'),
      expiredAt: findText((t) => t.toLowerCase().contains('masa berlaku'), '-'),
    );
  }
}
