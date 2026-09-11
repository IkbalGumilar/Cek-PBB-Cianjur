import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/desil/nik_scanner.dart';

void main() {
  test('membaca NIK 16 digit dari teks OCR', () {
    final result = NikScanParser.extract('NIK: 3203010101010001');

    expect(result, contains('3203010101010001'));
  });

  test('mengoreksi karakter kotak yang sering tertukar', () {
    final result = NikScanParser.extract('NIK: 3203O1O1O1O1S001');

    expect(result, contains('3203010101015001'));
  });

  test('menggabungkan angka yang dipisah spasi oleh OCR', () {
    final result = NikScanParser.extract('NIK 3203 0101 0101 0001');

    expect(result, contains('3203010101010001'));
  });

  test('mengembalikan beberapa nomor unik agar bisa dipilih pengguna', () {
    final result = NikScanParser.extract(
      'NIK 3203010101010001\nNIK 3203020202020002',
    );

    expect(result, contains('3203010101010001'));
    expect(result, contains('3203020202020002'));
    expect(result, hasLength(2));
  });

  test('kandidat dengan struktur tanggal valid dirangking lebih tinggi', () {
    final result = NikScanParser.extractCandidates('NIK: 3203D10101010001');

    expect(result.first.value, '3203010101010001');
  });

  test(
    'angka ikut dikembangkan bila rangkaian OCR mengandung karakter ambigu',
    () {
      final result = NikScanParser.extract('NIK: 3203D10101010001');

      expect(result, contains('3203010101010001'));
      expect(result, contains('3203810101010001'));
    },
  );

  test(
    'NIK 16 digit yang terbaca bersih tidak dibuat menjadi puluhan kandidat',
    () {
      final result = NikScanParser.extract('NIK: 3203010101010001');

      expect(result, ['3203010101010001']);
    },
  );
}
