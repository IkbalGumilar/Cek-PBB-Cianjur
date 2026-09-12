import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/kendaraan/plat_scanner.dart';

void main() {
  test('membaca plat dua huruf, angka, dan dua huruf', () {
    final candidates = PlatScanParser.extractCandidates('BD 2541 WH');

    expect(candidates.first.formatted, 'BD 2541 WH');
  });

  test('membaca plat satu huruf tanpa bergantung pada spasi', () {
    final candidates = PlatScanParser.extractCandidates('H8780VQ');

    expect(candidates.first.formatted, 'H 8780 VQ');
  });

  test('mengabaikan tanggal TNKB setelah plat', () {
    final candidates = PlatScanParser.extractCandidates('L 1996 YZ\n01 - 22');

    expect(candidates.first.formatted, 'L 1996 YZ');
  });

  test('menyediakan kandidat saat wilayah terbaca ambigu', () {
    final candidates = PlatScanParser.extractCandidates('B0 2541 WH');

    expect(
      candidates.map((candidate) => candidate.formatted),
      contains('BO 2541 WH'),
    );
    expect(
      candidates.map((candidate) => candidate.formatted),
      contains('BD 2541 WH'),
    );
  });

  test('teks tanpa huruf belakang tidak dianggap plat', () {
    final candidates = PlatScanParser.extractCandidates('01 - 22');

    expect(candidates, isEmpty);
  });
}
