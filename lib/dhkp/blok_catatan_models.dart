import '../blok_record.dart';
import '../blok_report_exporter.dart';
import '../check_mode.dart';

/// Dikembalikan lewat Navigator.pop saat user menekan "Rincian Tagihan" (mode tagihan)
/// atau "Cetak Bukti Bayar" (mode status bayar) — dipakai MainShell untuk membuka form
/// dengan blok/nomor wilayah/tahun sudah terisi otomatis.
class BlokNavigationRequest {
  final String blok;
  final String wilayah;
  final String tahun;
  final CheckMode targetMode;

  const BlokNavigationRequest({
    required this.blok,
    required this.wilayah,
    required this.tahun,
    this.targetMode = CheckMode.statusBayar,
  });
}

class OpsiEksporResult {
  final String blok;
  final BlokExportFormat format;

  const OpsiEksporResult({required this.blok, required this.format});
}

class EditRincianResult {
  final String namaWajibPajak;
  final String alamatObjek;
  final String alamatWp;

  const EditRincianResult({
    required this.namaWajibPajak,
    required this.alamatObjek,
    required this.alamatWp,
  });
}

/// Nilai dropdown Blok untuk menampilkan gabungan semua blok wilayah kerja
/// sekaligus, bukan satu blok saja.
const semuaBlokValue = '__SEMUA_BLOK__';

enum DhkpKategoriFilter {
  semua('Semua Data'),
  targetPemda('🎯 Target Pemda'),
  blacklist('⛔ Blacklist (≥ 5 Thn)'),
  sudahBayar('✓ Sudah Bayar'),
  belumBayar('⏳ Belum Bayar');

  final String label;
  const DhkpKategoriFilter(this.label);
}

/// Tahun 2022 s.d. tahun berjalan (menyesuaikan tanggal saat ini secara
/// dinamis — kalau sekarang sudah 2027, 2027 ikut tersedia).
List<int> availableDhkpYears() {
  final currentYear = DateTime.now().year;
  return [for (var y = 2022; y <= currentYear; y++) y];
}

/// Ringkasan statistik data DHKP (Sudah Bayar, Belum Bayar, Target Pemda, Total Desa).
class DhkpSummaryMetrics {
  final int sudahBayarCount;
  final int sudahBayarNominal;
  final int belumBayarCount;
  final int belumBayarNominal;
  final int targetPemdaCount;
  final int targetPemdaNominal;
  final int totalCount;
  final int totalNominal;

  const DhkpSummaryMetrics({
    this.sudahBayarCount = 0,
    this.sudahBayarNominal = 0,
    this.belumBayarCount = 0,
    this.belumBayarNominal = 0,
    this.targetPemdaCount = 0,
    this.targetPemdaNominal = 0,
    this.totalCount = 0,
    this.totalNominal = 0,
  });

  /// Hitung ringkasan statistik dalam 1 kali loop O(N).
  /// Total keseluruhan hanya menghitung Sudah Bayar dan Belum Bayar desa
  /// (Target Pemda dipisah tersendiri dan tidak dihitung ke target desa).
  factory DhkpSummaryMetrics.compute(Iterable<BlokRecord> records) {
    int sBayarCount = 0;
    int sBayarNom = 0;
    int bBayarCount = 0;
    int bBayarNom = 0;
    int tPemdaCount = 0;
    int tPemdaNom = 0;

    for (final r in records) {
      final pbb = r.jumlahPbbValue;
      if (r.isTargetPemda) {
        tPemdaCount++;
        tPemdaNom += pbb;
      } else if (r.isPaid) {
        sBayarCount++;
        sBayarNom += pbb;
      } else {
        bBayarCount++;
        bBayarNom += pbb;
      }
    }

    return DhkpSummaryMetrics(
      sudahBayarCount: sBayarCount,
      sudahBayarNominal: sBayarNom,
      belumBayarCount: bBayarCount,
      belumBayarNominal: bBayarNom,
      targetPemdaCount: tPemdaCount,
      targetPemdaNominal: tPemdaNom,
      totalCount: sBayarCount + bBayarCount,
      totalNominal: sBayarNom + bBayarNom,
    );
  }

  static String formatPct(double val) {
    if (val.isNaN || val.isInfinite || val <= 0) return '0%';
    if (val >= 100 || (val - val.roundToDouble()).abs() < 0.05) {
      return '${val.round()}%';
    }
    return '${val.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  String get pctSudah => totalNominal > 0
      ? formatPct((sudahBayarNominal / totalNominal) * 100)
      : '0%';

  String get pctBelum => totalNominal > 0
      ? formatPct((belumBayarNominal / totalNominal) * 100)
      : '0%';

  String get pctTotal => '100%';

  static List<BlokRecord> filterByKategori(
    List<BlokRecord> records,
    DhkpKategoriFilter filter,
  ) {
    switch (filter) {
      case DhkpKategoriFilter.semua:
        return records;
      case DhkpKategoriFilter.targetPemda:
        return records.where((r) => r.isTargetPemda).toList();
      case DhkpKategoriFilter.blacklist:
        return records.where((r) => r.isBlacklist).toList();
      case DhkpKategoriFilter.sudahBayar:
        return records.where((r) => r.isPaid && !r.isTargetPemda).toList();
      case DhkpKategoriFilter.belumBayar:
        return records.where((r) => !r.isPaid && !r.isTargetPemda).toList();
    }
  }

  static List<BlokRecord> filterBySearch(
    List<BlokRecord> records,
    String searchQuery,
  ) {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return records;
    return records.where((r) {
      return r.namaWajibPajak.toLowerCase().contains(q) ||
          r.nop.contains(q) ||
          r.alamatObjek.toLowerCase().contains(q) ||
          r.catatan.toLowerCase().contains(q);
    }).toList();
  }
}
