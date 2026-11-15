import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cianjur_wilayah_data.dart';

const defaultNopPrefix = '3205200004';
String _activeNopPrefix = defaultNopPrefix;
String _activeKecamatanCode = '200';
String _activeKelurahanCode = '004';
String _activeDesaName = 'BOBOJONG';
String _activeKecamatanName = 'MANDE';

/// Notifier untuk memberi tahu widget saat wilayah aktif (desa / kecamatan) berubah.
final ValueNotifier<int> activeWilayahRevision = ValueNotifier<int>(0);

/// Prefix NOP 10 digit (Provinsi 2 + Kab 2 + Kec 3 + Kel 3).
/// Secara bawaan mengarah ke Desa Bobojong (3205200004), dan otomatis menyesuaikan
/// jika akun berganti desa atau berkas DHKP desa lain dimuat.
String get nopPrefix => _activeNopPrefix;
String get activeNopPrefix => _activeNopPrefix;
String get activeKecamatanCode => _activeKecamatanCode;
String get activeKelurahanCode => _activeKelurahanCode;
String get activeDesaName => _activeDesaName;
String get activeKecamatanName => _activeKecamatanName;

String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

String _effectivePrefix(String? prefix) =>
    (prefix != null && prefix.length == 10) ? prefix : nopPrefix;

set activeNopPrefix(String value) {
  final clean = _digitsOnly(value);
  if (clean.length == 10) {
    setActiveWilayah(
      kecCode: clean.substring(4, 7),
      kelCode: clean.substring(7, 10),
    );
  }
}

void setActiveWilayah({
  required String kecCode,
  required String kelCode,
  String? desaName,
  String? kecName,
}) {
  final cleanKec = _digitsOnly(kecCode).padLeft(3, '0');
  final cleanKel = _digitsOnly(kelCode).padLeft(3, '0');
  _activeKecamatanCode = cleanKec;
  _activeKelurahanCode = cleanKel;
  _activeNopPrefix = '3205$cleanKec$cleanKel';
  _activeDesaName = (desaName != null && desaName.trim().isNotEmpty)
      ? desaName.trim().toUpperCase()
      : lookupKelurahanName(cleanKel, kecamatanCode: cleanKec);
  _activeKecamatanName = (kecName != null && kecName.trim().isNotEmpty)
      ? kecName.trim().toUpperCase()
      : lookupKecamatanName(cleanKec);
  activeWilayahRevision.value++;
}

/// Menetapkan wilayah aktif dan menyimpannya secara permanen ke SharedPreferences.
Future<void> saveActiveWilayah({
  required String kecCode,
  required String kelCode,
  String? desaName,
  String? kecName,
}) async {
  setActiveWilayah(
    kecCode: kecCode,
    kelCode: kelCode,
    desaName: desaName,
    kecName: kecName,
  );
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('startup_kec_code', _activeKecamatanCode);
    await prefs.setString('startup_kel_code', _activeKelurahanCode);
    await prefs.setString('startup_desa_name', _activeDesaName);
    await prefs.setString('startup_kec_name', _activeKecamatanName);
  } catch (_) {}
}

void resetNopPrefix() {
  setActiveWilayah(
    kecCode: '200',
    kelCode: '004',
    desaName: 'BOBOJONG',
    kecName: 'MANDE',
  );
}

/// Membaca konfigurasi wilayah yang tersimpan di SharedPreferences saat aplikasi dimulai.
Future<void> initActiveWilayah() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final kec = prefs.getString('startup_kec_code');
    final kel = prefs.getString('startup_kel_code');
    final desa = prefs.getString('startup_desa_name');
    final kecName = prefs.getString('startup_kec_name');
    if (kec != null && kec.isNotEmpty && kel != null && kel.isNotEmpty) {
      setActiveWilayah(
        kecCode: kec,
        kelCode: kel,
        desaName: desa,
        kecName: kecName,
      );
    }
  } catch (_) {}
}

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
/// Full NOP = prefix(10) + blok(3) + nomor wilayah(4) + 0 (akhir).
/// Shorthand is the trailing blok+nomor digits with leading zeros dropped:
/// - 5 digits: 2 for blok, 3 for nomor wilayah
/// - 6 digits: 2 for blok, 4 for nomor wilayah
/// - 7 digits: 3 for blok, 4 for nomor wilayah
/// Anything else (including an already-complete 18-digit NOP) passes through unchanged.
String expandNop(String rawInput, [String? prefix]) {
  final digits = _digitsOnly(rawInput);
  if (digits.length != 5 && digits.length != 6 && digits.length != 7) {
    return digits;
  }

  final blokLen = digits.length == 7 ? 3 : 2;
  final blok = digits.substring(0, blokLen).padLeft(3, '0');
  final wilayah = digits.substring(blokLen).padLeft(4, '0');
  return '${_effectivePrefix(prefix)}$blok${wilayah}0';
}

/// Menyusun NOP lengkap dari input blok & nomor wilayah terpisah (dipakai di
/// form input manual). Masing-masing cukup diisi angka pendek tanpa nol di
/// depan — blok di-padLeft ke 3 digit, nomor wilayah ke 4 digit.
/// Contoh: blok "1", wilayah "1" -> blok "001", wilayah "0001".
/// Return string kosong kalau salah satu input kosong.
String buildNop({
  required String blok,
  required String wilayah,
  String? prefix,
}) {
  final blokDigits = _digitsOnly(blok);
  final wilayahDigits = _digitsOnly(wilayah);
  if (blokDigits.isEmpty || wilayahDigits.isEmpty) return '';
  return '${_effectivePrefix(prefix)}${blokDigits.padLeft(3, '0')}${wilayahDigits.padLeft(4, '0')}0';
}

/// Memeriksa apakah input merupakan NOP 18 digit yang valid.
bool isValidNop(String rawInput) => _digitsOnly(rawInput).length == 18;

/// Segmen Propinsi (2 digit pertama, mis. "32").
String nopPropinsi(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(0, 2) : '';

/// Segmen Kabupaten/Kota (digit ke-3 & 4, mis. "05").
String nopKabupaten(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(2, 4) : '';

/// Segmen Kecamatan (digit ke-5 s.d. 7, mis. "200").
String nopKecamatan(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(4, 7) : '';

/// Segmen Kelurahan/Desa (digit ke-8 s.d. 10, mis. "004").
String nopKelurahan(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(7, 10) : '';

/// Segmen blok (3 digit) dari NOP lengkap 18 digit, dipakai untuk membedakan
/// dokumen antar wajib pajak yang kebetulan bernama sama.
String nopBlok(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(10, 13) : '';

/// Segmen nomor wilayah (4 digit) dari NOP lengkap 18 digit.
String nopWilayah(String fullNop) =>
    fullNop.length == 18 ? fullNop.substring(13, 17) : '';

/// Memformat 18 digit NOP menjadi format resmi standar Bapenda:
/// 32.05.200.004.026-0038.0
String formatNop(String nop) {
  final d = _digitsOnly(nop);
  if (d.length != 18) return nop;
  return '${d.substring(0, 2)}.${d.substring(2, 4)}.${d.substring(4, 7)}.${d.substring(7, 10)}.${d.substring(10, 13)}-${d.substring(13, 17)}.${d.substring(17, 18)}';
}

/// Nama desa bawaan untuk Kecamatan Mande berdasarkan 3 digit kode kelurahan (001-012).
String lookupMandeKelurahanName(String kelurahanCode) {
  return lookupKelurahanName(kelurahanCode, kecamatanCode: '200');
}

/// Nama desa/kelurahan untuk Kabupaten Cianjur berdasarkan 3 digit kode kelurahan dan opsional kode kecamatan.
String lookupKelurahanName(String kelurahanCode, {String? kecamatanCode}) {
  final cleanKel = _digitsOnly(kelurahanCode).padLeft(3, '0');
  final cleanKec = _digitsOnly(
    kecamatanCode ?? _activeKecamatanCode,
  ).padLeft(3, '0');
  return lookupCatalogDesaName(cleanKec, cleanKel);
}

/// Nama kecamatan untuk Kabupaten Cianjur berdasarkan 3 digit kode kecamatan (seluruh 32 kecamatan).
String lookupKecamatanName(String kecamatanCode) {
  final clean = _digitsOnly(kecamatanCode).padLeft(3, '0');
  return lookupCatalogKecamatanName(clean);
}
