/// Data wilayah kerja per dusun. Setiap dusun punya daftar blok (3 digit,
/// mis. "017") yang jadi wilayahnya — dipetakan manual per kepala dusun.
///
/// Kode blok disimpan sebagai string tiga digit agar konsisten dengan format
/// blok pada NOP.
class Dusun {
  final int number;
  final List<String> bloks;

  const Dusun({required this.number, required this.bloks});

  String get label => 'Dusun $number';
}

const List<Dusun> dusunList = [
  Dusun(
    number: 1,
    bloks: [
      '001',
      '002',
      '003',
      '004',
      '011',
      '012',
      '013',
      '014',
      '015',
      '016',
      '027',
    ],
  ),
  Dusun(
    number: 2,
    bloks: ['005', '006', '007', '008', '009', '010', '019', '020', '021'],
  ),
  Dusun(
    number: 3,
    bloks: [
      '017',
      '018',
      '022',
      '023',
      '024',
      '025',
      '026',
      '028',
      '029',
      '030',
      '031',
    ],
  ),
  Dusun(number: 4, bloks: ['032', '033', '035', '036']),
  Dusun(number: 5, bloks: ['034', '037', '038', '039', '040']),
];

Dusun? dusunByNumber(int number) {
  for (final dusun in dusunList) {
    if (dusun.number == number) return dusun;
  }
  return null;
}
