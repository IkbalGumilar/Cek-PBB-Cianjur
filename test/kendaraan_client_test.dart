import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/kendaraan/kendaraan_client.dart';

void main() {
  test('parses PKB response into vehicle, tax, and payment sections', () {
    final result = KendaraanInfo.fromJson({
      'informasi-umum': {
        'merk': 'HONDA',
        'model': 'H1B02N41L0 A/T',
        'nomor-polisi': 'F 6286 WAK',
        'warna': 'MERAH HITAM',
        'milik-ke': '1',
        'jenis': 'Roda 2',
        'tahun-buatan': '2021',
      },
      'informasi-pkb-pnbp': {
        'dari': '2025-09-01',
        'ke': '2027-09-01',
        'tanggal-pajak': '2025-09-01',
        'tanggal-stnk': '2026-09-01',
        'wilayah': 'CIANJUR',
      },
      'pembayaran-pkb-pnbp': {
        'pkb-pokok': 238200,
        'swdkllj-pokok': 70000,
        'total': 308200,
      },
      'tanggal-proses': '2026-09-12 05:27:52',
      'canBePaid': false,
      'isFiveYear': true,
    });

    expect(result.nomorPolisi, 'F 6286 WAK');
    expect(result.wilayah, 'CIANJUR');
    expect(result.masaPajak, '2025-09-01 - 2027-09-01');
    expect(result.biaya['pkb-pokok'], 238200);
    expect(result.total, 308200);
    expect(result.isFiveYear, isTrue);
    expect(result.canBePaid, isFalse);
  });

  test('uses safe defaults when optional sections are absent', () {
    final result = KendaraanInfo.fromJson(const <String, dynamic>{});

    expect(result.nomorPolisi, '-');
    expect(result.masaPajak, '-');
    expect(result.biaya, isEmpty);
    expect(result.total, 0);
    expect(result.keterangan, isNull);
  });

  group('formatNoPolisi', () {
    test('formats standard 1-letter front, 4-digit number, 3-letter suffix into 9 chars', () {
      final formatted = KendaraanClient.formatNoPolisi(
        platDepan: 'F',
        angka: '6286',
        platBelakang: 'WAK',
      );
      expect(formatted, 'F WAK6286');
      expect(formatted.length, 9);
    });

    test('formats 2-letter suffix with trailing space into exactly 9 chars', () {
      final formatted = KendaraanClient.formatNoPolisi(
        platDepan: 'F',
        angka: '6286',
        platBelakang: 'WA',
      );
      expect(formatted, 'F WA 6286');
      expect(formatted.length, 9);
    });

    test('formats 1-letter suffix into exactly 9 chars', () {
      final formatted = KendaraanClient.formatNoPolisi(
        platDepan: 'D',
        angka: '1234',
        platBelakang: 'A',
      );
      expect(formatted, 'D A  1234');
      expect(formatted.length, 9);
    });

    test('formats short numbers (1-3 digits) into exactly 9 chars', () {
      final singleDigit = KendaraanClient.formatNoPolisi(
        platDepan: 'F',
        angka: '1',
        platBelakang: 'WA',
      );
      expect(singleDigit, 'F WA 1   ');
      expect(singleDigit.length, 9);

      final twoDigits = KendaraanClient.formatNoPolisi(
        platDepan: 'F',
        angka: '12',
        platBelakang: 'WA',
      );
      expect(twoDigits, 'F WA 12  ');
      expect(twoDigits.length, 9);

      final threeDigits = KendaraanClient.formatNoPolisi(
        platDepan: 'F',
        angka: '123',
        platBelakang: 'WA',
      );
      expect(threeDigits, 'F WA 123 ');
      expect(threeDigits.length, 9);
    });

    test('formats 2-letter front plate prefix into exactly 9 chars', () {
      final formatted = KendaraanClient.formatNoPolisi(
        platDepan: 'BA',
        angka: '1234',
        platBelakang: 'ABC',
      );
      expect(formatted, 'BAABC1234');
      expect(formatted.length, 9);
    });
  });
}

