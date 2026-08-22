import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/nop_scanner.dart';

void main() {
  test('membaca NOP lengkap yang dipisah spasi', () {
    expect(NopScanParser.extract('NOP: 3205200004 0220070 0'), [
      '320520000402200700',
    ]);
  });

  test('membaca kode singkat blok dan nomor wilayah', () {
    expect(NopScanParser.extract('Blok 022, nomor 0070, kode: 0220070'), [
      '320520000402200700',
    ]);
  });

  test('mengabaikan angka yang bukan NOP', () {
    expect(
      NopScanParser.extract('Tahun 2026, total 0, nomor 1234567'),
      isEmpty,
    );
  });

  test('menghapus duplikat dan mengurutkan hasil', () {
    expect(NopScanParser.extract('NOP: 0300584\nNOP: 0170154\nNOP: 0300584'), [
      '320520000401701540',
      '320520000403005840',
    ]);
  });
}
