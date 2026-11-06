// Utility terpusat untuk pemformatan ribuan dan mata uang Rupiah.

/// Format angka bilangan bulat menjadi string dengan pemisah ribuan titik.
/// Contoh: 1250000 -> "1.250.000"
String formatRibuan(num value) {
  final s = value.toInt().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Parsing nominal Rupiah dari berbagai format teks/angka menjadi bilangan bulat (int).
/// Aman menangani format desimal sen seperti ",00", ".00", ",50", ".-", ",-" dll.
/// Contoh:
/// - "51.245,00" -> 51245
/// - "51.245.00" -> 51245
/// - "52.453,00" -> 52453
/// - "Rp. 51.425" -> 51425
/// - "Rp 50.000,-" -> 50000
/// - "10.000" -> 10000
/// - 51425 -> 51425
int parseNominalRupiah(Object? raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toInt();
  var s = raw.toString().trim();
  if (s.isEmpty || s == '-') return 0;

  // Hapus akhiran strip/dash seperti ",-" atau ".-"
  s = s.replaceAll(RegExp(r'[,.]-$'), '');

  // Hapus desimal sen di akhir:
  // Koma atau titik diikuti tepat 1 atau 2 angka di paling akhir (mis. ",00", ".00", ",50", ",5").
  // Pemisah ribuan Indonesia selalu 3 digit (".000"), sehingga titik/koma dengan
  // 1 atau 2 digit di akhir string adalah desimal sen.
  s = s.replaceAll(RegExp(r'[,.]\d{1,2}$'), '');

  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

/// Menstandarkan string nominal PBB menjadi format bersih tanpa sen berlebih (mis. "Rp 51.245").
/// Jika format asal mengandung desimal sen (mis. "51.245,00" atau "51.245.00"), diubah menjadi "Rp 51.245".
String cleanNominalRupiah(Object? raw) {
  if (raw == null) return '';
  final s = raw.toString().trim();
  if (s.isEmpty || s == '-') return '';

  if (RegExp(r'[,.]\d{1,2}$').hasMatch(s)) {
    final val = parseNominalRupiah(s);
    return 'Rp ${formatRibuan(val)}';
  }
  return s;
}

/// Format nominal ke format Rupiah standar.
/// Menerima [num] (contoh: 1250000 -> "Rp. 1.250.000")
/// atau [String] (contoh: "1.250.000" -> "Rp. 1.250.000", "Rp 1.250.000" -> "Rp. 1.250.000",
/// "52.453,00" -> "Rp. 52.453", "Rp. Rp. 1.250.000" -> "Rp. 1.250.000").
String formatRupiah(Object? raw) {
  if (raw == null) return '-';
  if (raw is num) {
    return 'Rp. ${formatRibuan(raw)}';
  }
  var trimmed = raw.toString().trim();
  if (trimmed.isEmpty || trimmed == '-') {
    return '-';
  }
  // Jika mengandung format desimal sen seperti ",00" atau ".00", bersihkan nilainya
  if (RegExp(r'[,.]\d{1,2}$').hasMatch(trimmed)) {
    final val = parseNominalRupiah(trimmed);
    return 'Rp. ${formatRibuan(val)}';
  }
  // Bersihkan semua awalan "Rp", "Rp.", "rp", "RP" yang berulang agar tidak dobel/ganda
  trimmed = trimmed
      .replaceAll(RegExp(r'^(?:rp\.?\s*)+', caseSensitive: false), '')
      .trim();
  if (trimmed.isEmpty || trimmed == '-') {
    return '-';
  }
  return 'Rp. $trimmed';
}
