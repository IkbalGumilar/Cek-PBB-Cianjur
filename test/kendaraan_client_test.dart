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
}
