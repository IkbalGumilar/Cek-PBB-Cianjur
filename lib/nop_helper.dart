const nopPrefix = '3205200004';

const nopShortcutExamples = [
  (
    '17154',
    '3205200004'
        '017'
        '0154'
        '0',
  ),
  (
    '300584',
    '3205200004'
        '030'
        '0584'
        '0',
  ),
];

/// Expands a shorthand NOP entry into the full 18-digit NOP for this desa.
///
/// Full NOP = 3205200004 (prefix, fixed) + blok(3) + nomor wilayah(4) + 0 (akhir).
/// Shorthand is the trailing blok+nomor digits with leading zeros dropped:
/// - 5 digits: 2 for blok, 3 for nomor wilayah
/// - 6 digits: 2 for blok, 4 for nomor wilayah
/// - 7 digits: 3 for blok, 4 for nomor wilayah
/// Anything else (including an already-complete 18-digit NOP) passes through unchanged.
String expandNop(String rawInput) {
  final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 5 && digits.length != 6 && digits.length != 7) {
    return digits;
  }

  final blokLen = digits.length == 7 ? 3 : 2;
  final blok = digits.substring(0, blokLen).padLeft(3, '0');
  final wilayah = digits.substring(blokLen).padLeft(4, '0');
  return '$nopPrefix$blok${wilayah}0';
}

/// Menyusun NOP lengkap dari input blok & nomor wilayah terpisah (dipakai di
/// form input manual). Masing-masing cukup diisi angka pendek tanpa nol di
/// depan — blok di-padLeft ke 3 digit, nomor wilayah ke 4 digit.
/// Contoh: blok "1", wilayah "1" -> blok "001", wilayah "0001".
/// Return string kosong kalau salah satu input kosong.
String buildNop({required String blok, required String wilayah}) {
  final blokDigits = blok.replaceAll(RegExp(r'[^0-9]'), '');
  final wilayahDigits = wilayah.replaceAll(RegExp(r'[^0-9]'), '');
  if (blokDigits.isEmpty || wilayahDigits.isEmpty) return '';
  return '$nopPrefix${blokDigits.padLeft(3, '0')}${wilayahDigits.padLeft(4, '0')}0';
}

/// Segmen blok (3 digit) dari NOP lengkap 18 digit, dipakai untuk membedakan
/// dokumen antar wajib pajak yang kebetulan bernama sama.
String nopBlok(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(10, 13) : '';

/// Segmen nomor wilayah (4 digit) dari NOP lengkap 18 digit.
String nopWilayah(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(13, 17) : '';
