import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cek_pbb_app/pbb_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> _createSampleSttsPdfBytes() async {
  final doc = PdfDocument();
  final page = doc.pages.add();
  page.graphics.drawString(
    'SURAT SETORAN PAJAK DAERAH (SSPD)\n'
    'NOP : 32.05.200.004.017-0154.0\n'
    'Tanggal Transaksi : 2024-04-16 14:59:06\n'
    'Nomor bukti/stan : FCCC68DBDE7B400BA2E54864A0F62AC6\n',
    PdfStandardFont(PdfFontFamily.helvetica, 12),
    bounds: const Rect.fromLTWH(0, 0, 500, 200),
  );
  final saved = await doc.save();
  doc.dispose();
  return Uint8List.fromList(saved);
}

void main() {
  test('extractSttsInMemory parses PDF text in-memory accurately', () async {
    final file = File('/tmp/test_stts.pdf');
    final bytes = file.existsSync()
        ? await file.readAsBytes()
        : await _createSampleSttsPdfBytes();

    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text.contains('SURAT SETORAN PAJAK DAERAH'), isTrue);
    expect(text.contains('Tanggal Transaksi'), isTrue);

    final matchTanggal = RegExp(
      r'Tanggal\s+Transaksi\s*:\s*([0-9\-\:\s]+)',
      caseSensitive: false,
    ).firstMatch(text);
    final tanggal = matchTanggal?.group(1)?.trim().split('\n').first.trim();

    expect(tanggal, isNotNull);
    expect(tanggal, '2024-04-16 14:59:06');

    final matchStan = RegExp(
      r'Nomor\s+bukti/stan\s*:\s*([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(text);
    expect(matchStan?.group(1)?.trim(), 'FCCC68DBDE7B400BA2E54864A0F62AC6');
  });

  test('PbbResult handles extracted tanggalBayar and isPaid correctly', () {
    final result = PbbResult(
      'Sudah Bayar',
      'NOP ini tidak ada tunggakan PBB (LUNAS)',
      tanggalBayar: '2024-04-16 14:59:06',
      nomorStan: 'FCCC68DBDE7B400BA2E54864A0F62AC6',
    );

    expect(result.isPaid, isTrue);
    expect(result.tanggalBayar, '2024-04-16 14:59:06');
    expect(result.nomorStan, 'FCCC68DBDE7B400BA2E54864A0F62AC6');
  });
}
