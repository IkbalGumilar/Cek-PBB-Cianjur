import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

set activeNopPrefix(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.length == 10) {
    _activeNopPrefix = clean;
    _activeKecamatanCode = clean.substring(4, 7);
    _activeKelurahanCode = clean.substring(7, 10);
    activeWilayahRevision.value++;
  }
}

void setActiveWilayah({
  required String kecCode,
  required String kelCode,
  String? desaName,
  String? kecName,
}) {
  final cleanKec = kecCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  final cleanKel = kelCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  _activeKecamatanCode = cleanKec;
  _activeKelurahanCode = cleanKel;
  _activeNopPrefix = '3205$cleanKec$cleanKel';
  if (desaName != null && desaName.isNotEmpty) {
    _activeDesaName = desaName.toUpperCase();
  }
  if (kecName != null && kecName.isNotEmpty) {
    _activeKecamatanName = kecName.toUpperCase();
  }
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
  _activeNopPrefix = defaultNopPrefix;
  _activeKecamatanCode = '200';
  _activeKelurahanCode = '004';
  _activeDesaName = 'BOBOJONG';
  _activeKecamatanName = 'MANDE';
  activeWilayahRevision.value++;
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
  final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 5 && digits.length != 6 && digits.length != 7) {
    return digits;
  }

  final blokLen = digits.length == 7 ? 3 : 2;
  final blok = digits.substring(0, blokLen).padLeft(3, '0');
  final wilayah = digits.substring(blokLen).padLeft(4, '0');
  final effPrefix =
      (prefix != null && prefix.length == 10) ? prefix : nopPrefix;
  return '$effPrefix$blok${wilayah}0';
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
  final blokDigits = blok.replaceAll(RegExp(r'[^0-9]'), '');
  final wilayahDigits = wilayah.replaceAll(RegExp(r'[^0-9]'), '');
  if (blokDigits.isEmpty || wilayahDigits.isEmpty) return '';
  final effPrefix =
      (prefix != null && prefix.length == 10) ? prefix : nopPrefix;
  return '$effPrefix${blokDigits.padLeft(3, '0')}${wilayahDigits.padLeft(4, '0')}0';
}

/// Memeriksa apakah input merupakan NOP 18 digit yang valid.
bool isValidNop(String rawInput) {
  final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length == 18;
}

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
  final d = nop.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 18) return nop;
  return '${d.substring(0, 2)}.${d.substring(2, 4)}.${d.substring(4, 7)}.${d.substring(7, 10)}.${d.substring(10, 13)}-${d.substring(13, 17)}.${d.substring(17, 18)}';
}

/// Nama desa bawaan untuk Kecamatan Mande berdasarkan 3 digit kode kelurahan (001-012).
String lookupMandeKelurahanName(String kelurahanCode) {
  final clean =
      kelurahanCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  return switch (clean) {
    '001' => 'MEKARJAYA',
    '002' => 'SUKAMANAH',
    '003' => 'KADEMANGAN',
    '004' => 'BOBOJONG',
    '005' => 'CIKIDANGBAYABANG',
    '006' => 'MANDE',
    '007' => 'MURNISARI',
    '008' => 'MULYASARI',
    '009' => 'JAMALI',
    '010' => 'CIANDAM',
    '011' => 'KUTAWARINGIN',
    '012' => 'LEUWIKOJA',
    _ => 'Desa $clean',
  };
}

/// Nama kecamatan bawaan untuk Kabupaten Cianjur berdasarkan 3 digit kode kecamatan (misal 200 -> MANDE).
String lookupKecamatanName(String kecamatanCode) {
  final clean =
      kecamatanCode.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0');
  return switch (clean) {
    '200' => 'MANDE',
    _ => 'Kecamatan $clean',
  };
}
