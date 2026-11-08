class TaxRecord {
  final String nop;
  String status;
  String rawText;
  String? namaWajibPajak;
  String? tanggalBayar;
  String? nomorStan;
  String? jumlahPbb;

  /// null = belum dicoba unduh (mis. mode tidak minta unduh bukti bayar),
  /// true = berhasil diunduh, false = dicoba tapi gagal.
  bool? buktiBayarDownloaded;

  TaxRecord({
    required this.nop,
    this.status = '',
    this.rawText = '',
    this.namaWajibPajak,
    this.tanggalBayar,
    this.nomorStan,
    this.jumlahPbb,
    this.buktiBayarDownloaded,
  });

  bool get isChecked => status.isNotEmpty;
  bool get isPaid {
    final s = status.toLowerCase();
    if (s.contains('belum')) return false;
    return s.startsWith('sudah') ||
        s.startsWith('lunas') ||
        (tanggalBayar != null &&
            tanggalBayar!.trim().isNotEmpty &&
            tanggalBayar!.trim() != '-' &&
            tanggalBayar!.trim() != '0');
  }
}
