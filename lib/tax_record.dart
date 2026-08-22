class TaxRecord {
  final String nop;
  String status;
  String rawText;
  String? namaWajibPajak;

  /// null = belum dicoba unduh (mis. mode tidak minta unduh bukti bayar),
  /// true = berhasil diunduh, false = dicoba tapi gagal.
  bool? buktiBayarDownloaded;

  TaxRecord({
    required this.nop,
    this.status = '',
    this.rawText = '',
    this.namaWajibPajak,
    this.buktiBayarDownloaded,
  });

  bool get isChecked => status.isNotEmpty;
  bool get isPaid =>
      status.startsWith('Sudah Bayar') || status.startsWith('Lunas');
}
