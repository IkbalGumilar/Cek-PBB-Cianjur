/// Data wilayah kerja per dusun. Setiap dusun punya daftar blok (3 digit,
/// mis. "017") yang jadi wilayahnya — dipetakan manual per kepala dusun.
///
/// Baru Dusun 3 yang datanya diisi. Dusun 1, 2, 4, 5 sengaja dikosongkan
/// dulu sampai kepala dusun terkait mengonfirmasi daftar bloknya sendiri —
/// isi [Dusun.bloks]-nya kalau datanya sudah ada.
class Dusun {
  final int number;
  final List<String> bloks;

  const Dusun({required this.number, required this.bloks});

  String get label => 'Dusun $number';
}

const dusunList = [
  Dusun(number: 1, bloks: []),
  Dusun(number: 2, bloks: []),
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
  Dusun(number: 4, bloks: []),
  Dusun(number: 5, bloks: []),
];

Dusun? dusunByNumber(int number) {
  for (final dusun in dusunList) {
    if (dusun.number == number) return dusun;
  }
  return null;
}
