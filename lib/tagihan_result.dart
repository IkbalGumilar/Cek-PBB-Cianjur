String formatRupiah(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '-' || trimmed.toLowerCase().startsWith('rp')) {
    return trimmed;
  }
  return 'Rp. $trimmed';
}

class TagihanYearRow {
  final String tahun;
  final String pbb;
  final String denda;
  final String kurangBayar;
  final String statusBayar;

  /// Kode bayar VA milik baris tahun ini (dari tombol "Payment VA" di respons
  /// server), dipakai sebagai parameter `payment_code` saat generate Virtual
  /// Account. Null kalau baris ini tidak punya opsi pembayaran VA.
  final String? paymentCodeVa;

  TagihanYearRow({
    required this.tahun,
    required this.pbb,
    required this.denda,
    required this.kurangBayar,
    required this.statusBayar,
    this.paymentCodeVa,
  });
}

class TagihanResult {
  final String namaWajibPajak;
  final List<TagihanYearRow> rows;
  final String totalPbb;
  final String totalDenda;
  final String totalKurangBayar;
  final bool notFound;
  final String rawText;

  TagihanResult({
    required this.namaWajibPajak,
    required this.rows,
    required this.totalPbb,
    required this.totalDenda,
    required this.totalKurangBayar,
    required this.notFound,
    required this.rawText,
  });

  factory TagihanResult.notFound(String rawText) => TagihanResult(
    namaWajibPajak: '',
    rows: const [],
    totalPbb: '',
    totalDenda: '',
    totalKurangBayar: '',
    notFound: true,
    rawText: rawText,
  );
}
