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

/// Format nominal ke format Rupiah standar.
/// Menerima [num] (contoh: 1250000 -> "Rp. 1.250.000")
/// atau [String] (contoh: "1.250.000" -> "Rp. 1.250.000").
String formatRupiah(Object? raw) {
  if (raw == null) return '-';
  if (raw is num) {
    return 'Rp. ${formatRibuan(raw)}';
  }
  final trimmed = raw.toString().trim();
  if (trimmed.isEmpty ||
      trimmed == '-' ||
      trimmed.toLowerCase().startsWith('rp')) {
    return trimmed;
  }
  return 'Rp. $trimmed';
}
