import 'package:material_ui/material_ui.dart';

import '../blok_record.dart';
import '../dusun_data.dart';
import '../nop_helper.dart'
    show lookupMandeKelurahanName, nopKecamatan, nopKelurahan;
import '../tagihan_result.dart' show formatRupiah;

/// Mode tampilan blok pada tab Tren saat melihat Semua Blok (mencegah 41 garis tumpang-tindih).
enum DhkpAllBlokTrendMode {
  top5('Top 5 Tertinggi'),
  bottom5('5 Terendah'),
  custom('Pilih Blok');

  final String label;
  const DhkpAllBlokTrendMode(this.label);
}

/// Satu seri garis tren bulanan (Jan–Des) untuk grafik tunggal maupun multi-perbandingan.
class DhkpTrendSeries {
  final String id;
  final String label;
  final List<int> monthlyNominal;
  final List<int> monthlyCounts;
  final int totalNominal;
  final int totalCount;
  final Color color;
  final bool isPrimary;
  final bool isDashed;

  const DhkpTrendSeries({
    required this.id,
    required this.label,
    required this.monthlyNominal,
    required this.monthlyCounts,
    required this.totalNominal,
    required this.totalCount,
    required this.color,
    this.isPrimary = false,
    this.isDashed = false,
  });
}

/// 5 Tab Kategori Data Grafik Utama:
/// 1. Jumlah Persentase (Default)
/// 2. Jumlah Pendapatan
/// 3. Belum Bayar
/// 4. Sudah Bayar
/// 5. Tren Pembayaran tiap bulan Jan-Des
enum DhkpGrafikTab {
  persentase(
    'Jumlah Persentase',
    'Persentase',
    Icons.pie_chart_rounded,
    Colors.green,
  ),
  pendapatan(
    'Jumlah Pendapatan',
    'Pendapatan',
    Icons.account_balance_wallet_rounded,
    Colors.teal,
  ),
  belumBayar(
    'Belum Bayar',
    'Belum Bayar',
    Icons.pending_actions_rounded,
    Colors.orange,
  ),
  sudahBayar('Sudah Bayar', 'Sudah Bayar', Icons.task_alt_rounded, Colors.blue),
  trenBulanan(
    'Tren Pembayaran',
    'Tren Jan - Des',
    Icons.insights_rounded,
    Colors.purple,
  );

  final String label;
  final String shortLabel;
  final IconData icon;
  final MaterialColor accentColor;
  const DhkpGrafikTab(this.label, this.shortLabel, this.icon, this.accentColor);
}

/// Mode tampilan diagram grafik (Default: Diagram Batang)
enum ChartStyle {
  batang('Batang', Icons.bar_chart_rounded),
  bar('Mendatar', Icons.align_horizontal_left_rounded),
  pie('Lingkaran', Icons.pie_chart_outline_rounded),
  semua('Semua', Icons.dashboard_customize_rounded);

  final String label;
  final IconData icon;
  const ChartStyle(this.label, this.icon);
}

/// Mode pengurutan data pada grafik & tabel
enum GrafikSortMode {
  wilayah('Urut Kode', Icons.sort_by_alpha_rounded),
  tertinggi('Tertinggi ↓', Icons.trending_down_rounded),
  terendah('Terendah ↑', Icons.trending_up_rounded);

  final String label;
  final IconData icon;
  const GrafikSortMode(this.label, this.icon);
}

String formatShortRupiah(int value) {
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)} M';
  } else if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)} Jt';
  } else if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)} Rb';
  }
  return '$value';
}

DateTime? parsePaymentDate(String? raw) =>
    DhkpGrafikAnalytics.parsePaymentDate(raw);

class DhkpGroupInfo {
  final String label;
  final int totalNop;
  final int lunasNop;
  final int belumBayarNop;
  final int lunasNominal;
  final int belumBayarNominal;
  final int totalNominal;
  final double lunasPct;
  final double lunasNopPct;

  const DhkpGroupInfo({
    required this.label,
    required this.totalNop,
    required this.lunasNop,
    required this.belumBayarNop,
    required this.lunasNominal,
    required this.belumBayarNominal,
    required this.totalNominal,
    required this.lunasPct,
    required this.lunasNopPct,
  });
}

class DhkpPieSliceInfo {
  final String label;
  final double nominal;
  final double ratio;
  final Color color;

  const DhkpPieSliceInfo({
    required this.label,
    required this.nominal,
    required this.ratio,
    required this.color,
  });
}

class DhkpStatItem {
  final String label;
  final String value;
  final String sub;
  final MaterialColor color;
  final IconData icon;
  final List<double>? sparklinePoints;
  final String? deltaText;
  final bool? deltaIsFavorable;
  final double? gaugeRatio;
  final double? numericValue;
  final String Function(double animatedValue)? animatedValueBuilder;

  const DhkpStatItem({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
    this.sparklinePoints,
    this.deltaText,
    this.deltaIsFavorable,
    this.gaugeRatio,
    this.numericValue,
    this.animatedValueBuilder,
  });
}

class DhkpGaugeSummary {
  final String scopeTitle;
  final String tahun;
  final double achievedPct;
  final double objPct;
  final int paidNominal;
  final int targetNominal;
  final int paidCount;
  final int totalCount;
  final String? prevYear;
  final String? deltaText;
  final bool deltaIsFavorable;
  final MaterialColor accentColor;

  const DhkpGaugeSummary({
    required this.scopeTitle,
    required this.tahun,
    required this.achievedPct,
    required this.objPct,
    required this.paidNominal,
    required this.targetNominal,
    required this.paidCount,
    required this.totalCount,
    this.prevYear,
    this.deltaText,
    this.deltaIsFavorable = true,
    this.accentColor = Colors.green,
  });
}

class DhkpGrafikAnalytics {
  const DhkpGrafikAnalytics._();

  static DateTime? parsePaymentDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty || RegExp(r'^\d{4}$').hasMatch(s) || s == '-' || s == '0') {
      return null;
    }
    try {
      if (s.length > 4) {
        return DateTime.parse(s);
      }
    } catch (_) {}
    final dmy = RegExp(
      r'^(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
    ).firstMatch(s);
    if (dmy != null) {
      final d = int.tryParse(dmy.group(1)!);
      final m = int.tryParse(dmy.group(2)!);
      final y = int.tryParse(dmy.group(3)!);
      final hour = int.tryParse(dmy.group(4) ?? '') ?? 0;
      final minute = int.tryParse(dmy.group(5) ?? '') ?? 0;
      final second = int.tryParse(dmy.group(6) ?? '') ?? 0;
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d, hour, minute, second);
      }
    }
    return null;
  }

  static const monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Ags',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static const fullMonthNames = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// Format tanggal bayar beserta jam bayar untuk rincian bulanan.
  /// Contoh: "15 Juli 2026, 14:23:05 WIB" atau "15 Juli 2026" jika tanpa jam.
  static String formatTanggalJamBayar(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final dt = parsePaymentDate(raw);
    if (dt == null) return raw;
    final d = dt.day.toString().padLeft(2, '0');
    final monthName = (dt.month >= 1 && dt.month <= 12)
        ? fullMonthNames[dt.month - 1]
        : '${dt.month}';
    final y = dt.year;
    final hasTime = raw.contains(':');
    if (hasTime) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$d $monthName $y, $h:$m:$s WIB';
    }
    return '$d $monthName $y';
  }

  /// Ambil daftar objek pajak yang sudah lunas pada bulan tertentu [monthIndex] (1..12),
  /// diurutkan default dari waktu pembayaran terlama ke terbaru (awal ke akhir bulan).
  /// Parameter opsional [tahun] memastikan hanya transaksi pembayaran di tahun tersebut yang diambil.
  static List<BlokRecord> getPaidRecordsForMonth(
    List<BlokRecord> records,
    int monthIndex, {
    String? tahun,
  }) {
    final filtered = <BlokRecord>[];
    for (final r in records) {
      if (r.isPaid && r.tanggalBayar.isNotEmpty) {
        final dt = parsePaymentDate(r.tanggalBayar);
        if (dt != null && dt.month == monthIndex) {
          if (tahun != null &&
              tahun.isNotEmpty &&
              dt.year.toString() != tahun) {
            continue;
          }
          if (r.tahunBayar.isNotEmpty && dt.year.toString() != r.tahunBayar) {
            continue;
          }
          filtered.add(r);
        }
      }
    }
    filtered.sort((a, b) {
      final dtA = parsePaymentDate(a.tanggalBayar);
      final dtB = parsePaymentDate(b.tanggalBayar);
      if (dtA != null && dtB != null) {
        final cmp = dtA.compareTo(dtB);
        if (cmp != 0) return cmp;
      } else if (dtA != null) {
        return -1;
      } else if (dtB != null) {
        return 1;
      }
      return a.nop.compareTo(b.nop);
    });
    return filtered;
  }

  static ({
    List<int> nominal,
    List<int> counts,
    int totalNominal,
    int totalCount,
  })
  _aggregateMonthly(List<BlokRecord> records, {String? tahun}) {
    final monthlyNominal = List<int>.filled(12, 0);
    final monthlyCount = List<int>.filled(12, 0);

    for (final r in records) {
      if (r.isPaid && r.tanggalBayar.isNotEmpty) {
        final dt = parsePaymentDate(r.tanggalBayar);
        if (dt != null && dt.month >= 1 && dt.month <= 12) {
          if (tahun != null &&
              tahun.isNotEmpty &&
              dt.year.toString() != tahun) {
            continue;
          }
          if (r.tahunBayar.isNotEmpty && dt.year.toString() != r.tahunBayar) {
            continue;
          }
          monthlyNominal[dt.month - 1] += r.jumlahPbbValue;
          monthlyCount[dt.month - 1]++;
        }
      }
    }

    final totalNominal = monthlyNominal.fold<int>(0, (sum, v) => sum + v);
    final totalCount = monthlyCount.fold<int>(0, (sum, v) => sum + v);
    return (
      nominal: monthlyNominal,
      counts: monthlyCount,
      totalNominal: totalNominal,
      totalCount: totalCount,
    );
  }

  static DhkpGroupInfo _summarizeGroup(
    String label,
    List<BlokRecord> groupRecs,
  ) {
    final lunasRecs = groupRecs.where((r) => r.isPaid).toList();
    final belumRecs = groupRecs.where((r) => !r.isPaid).toList();

    final lunasNominal = lunasRecs.fold<int>(
      0,
      (sum, r) => sum + r.jumlahPbbValue,
    );
    final belumNominal = belumRecs.fold<int>(
      0,
      (sum, r) => sum + r.jumlahPbbValue,
    );
    final totalNominal = groupRecs.fold<int>(
      0,
      (sum, r) => sum + r.jumlahPbbValue,
    );

    final lunasNopPct = groupRecs.isNotEmpty
        ? (lunasRecs.length / groupRecs.length * 100)
        : 0.0;
    final lunasPct = (totalNominal > 0 && belumNominal > 0)
        ? (lunasNominal / totalNominal * 100)
        : (belumRecs.isEmpty
              ? (groupRecs.isNotEmpty ? 100.0 : 0.0)
              : lunasNopPct);

    return DhkpGroupInfo(
      label: label,
      totalNop: groupRecs.length,
      lunasNop: lunasRecs.length,
      belumBayarNop: belumRecs.length,
      lunasNominal: lunasNominal,
      belumBayarNominal: belumNominal,
      totalNominal: totalNominal,
      lunasPct: lunasPct,
      lunasNopPct: lunasNopPct,
    );
  }

  static List<Color> trendSeriesPalette({required bool isDark}) => isDark
      ? const [
          Color(0xFFA78BFA),
          Color(0xFF38BDF8),
          Color(0xFF34D399),
          Color(0xFFFBBF24),
          Color(0xFFF472B6),
          Color(0xFF818CF8),
          Color(0xFF2DD4BF),
          Color(0xFFFB923C),
          Color(0xFF60A5FA),
          Color(0xFFA3E635),
          Color(0xFFC084FC),
          Color(0xFFFB7185),
        ]
      : const [
          Color(0xFF7C3AED),
          Color(0xFF0284C7),
          Color(0xFF059669),
          Color(0xFFD97706),
          Color(0xFFDB2777),
          Color(0xFF4F46E5),
          Color(0xFF0D9488),
          Color(0xFFEA580C),
          Color(0xFF2563EB),
          Color(0xFF65A30D),
          Color(0xFF9333EA),
          Color(0xFFE11D48),
        ];

  /// Menentukan 1 kode kecamatan utama dari dataset (antisipasi skala kecamatan: batas 1 kecamatan).
  static String resolvePrimaryKecamatanCode(List<BlokRecord> records) {
    final counts = <String, int>{};
    for (final r in records) {
      final d = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length == 18) {
        final kec = nopKecamatan(d);
        counts[kec] = (counts[kec] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '';
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final cmp = b.value.compareTo(a.value);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    return sorted.first.key;
  }

  /// Mengambil daftar kode kelurahan/desa unik di dalam 1 kecamatan.
  static List<String> resolveDesaCodesInKecamatan(
    List<BlokRecord> records,
    String kecamatanCode,
  ) {
    final set = <String>{};
    for (final r in records) {
      final d = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length == 18 &&
          (kecamatanCode.isEmpty || nopKecamatan(d) == kecamatanCode)) {
        set.add(nopKelurahan(d));
      }
    }
    return set.toList()..sort();
  }

  /// Format nama desa dari kode 3 digit NOP.
  static String formatDesaLabel(String kelCode) {
    final raw = lookupMandeKelurahanName(kelCode);
    if (raw.startsWith('Desa ')) return raw;
    final lower = raw.toLowerCase();
    return 'Desa ${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  static List<DhkpGroupInfo> buildMonthGroups(
    List<BlokRecord> records, {
    String? tahun,
  }) {
    final agg = _aggregateMonthly(records, tahun: tahun);
    final monthGroups = <DhkpGroupInfo>[];
    for (int i = 0; i < 12; i++) {
      final nom = agg.nominal[i];
      final cnt = agg.counts[i];
      final pct = agg.totalNominal > 0 ? (nom / agg.totalNominal * 100) : 0.0;
      monthGroups.add(
        DhkpGroupInfo(
          label: monthNames[i],
          totalNop: cnt,
          lunasNop: cnt,
          belumBayarNop: 0,
          lunasNominal: nom,
          belumBayarNominal: 0,
          totalNominal: nom,
          lunasPct: pct,
          lunasNopPct: agg.totalCount > 0 ? (cnt / agg.totalCount * 100) : 0.0,
        ),
      );
    }
    return monthGroups;
  }

  /// Membangun seri perbandingan lintas tahun (maksimal [maxYears] = 5 tahun)
  /// khusus untuk 1 entitas tunggal (mis. Se-Desa, Se-Kecamatan, atau 1 Dusun/Kadus).
  static List<DhkpTrendSeries> buildYearComparisonSeries({
    required List<BlokRecord> entityRecords,
    required String primaryYear,
    required List<String> compareYears,
    required bool isDark,
    int maxYears = 5,
  }) {
    final orderedYears = <String>[primaryYear];
    final others = compareYears.where((y) => y != primaryYear).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    for (final y in others) {
      if (orderedYears.length >= maxYears) break;
      orderedYears.add(y);
    }

    final palette = trendSeriesPalette(isDark: isDark);
    final series = <DhkpTrendSeries>[];
    for (int i = 0; i < orderedYears.length; i++) {
      final year = orderedYears[i];
      final yearRecs = entityRecords.where((r) {
        if (r.tahunBayar.isNotEmpty) return r.tahunBayar == year;
        final dt = parsePaymentDate(r.tanggalBayar);
        return dt != null && dt.year.toString() == year;
      }).toList();
      final agg = _aggregateMonthly(yearRecs, tahun: year);
      series.add(
        DhkpTrendSeries(
          id: 'year:$year',
          label: year,
          monthlyNominal: agg.nominal,
          monthlyCounts: agg.counts,
          totalNominal: agg.totalNominal,
          totalCount: agg.totalCount,
          color: palette[i % palette.length],
          isPrimary: i == 0,
          isDashed: i > 0,
        ),
      );
    }
    return series;
  }

  /// Membangun seri garis tren per Dusun (Dusun 1–5) pada tahun aktif.
  static List<DhkpTrendSeries> buildMultiDusunMonthlySeries({
    required List<BlokRecord> records,
    String? tahun,
    required bool isDark,
  }) {
    final palette = trendSeriesPalette(isDark: isDark);
    final series = <DhkpTrendSeries>[];
    var colorIdx = 0;

    for (final dusun in dusunList) {
      final dBloks = dusun.bloks.toSet();
      final dRecs = records.where((r) => dBloks.contains(r.blok)).toList();
      if (dRecs.isEmpty) continue;
      final agg = _aggregateMonthly(dRecs, tahun: tahun);
      series.add(
        DhkpTrendSeries(
          id: 'dusun:${dusun.number}',
          label: 'Dusun ${dusun.number}',
          monthlyNominal: agg.nominal,
          monthlyCounts: agg.counts,
          totalNominal: agg.totalNominal,
          totalCount: agg.totalCount,
          color: palette[colorIdx % palette.length],
        ),
      );
      colorIdx++;
    }
    return series;
  }

  /// Membangun seri garis tren per Blok.
  /// Jika [dusunNumber] diisi, mengembalikan semua blok dalam dusun tersebut (maks ~12 di Dusun 3).
  /// Jika [dusunNumber] null (Semua Blok), menerapkan [mode] (Top 5 / 5 Terendah / Pilih Manual maks 6)
  /// untuk mencegah 41 garis menumpuk.
  static List<DhkpTrendSeries> buildBlokMonthlySeries({
    required List<BlokRecord> records,
    String? tahun,
    required bool isDark,
    int? dusunNumber,
    DhkpAllBlokTrendMode mode = DhkpAllBlokTrendMode.top5,
    Set<String> customBloks = const {},
    int maxCustomBloks = 6,
  }) {
    final allowedBloks = dusunNumber != null
        ? (dusunByNumber(dusunNumber)?.bloks.toSet() ?? <String>{})
        : null;

    final blokMap = <String, List<BlokRecord>>{};
    for (final r in records) {
      if (allowedBloks != null && !allowedBloks.contains(r.blok)) continue;
      blokMap.putIfAbsent(r.blok, () => []).add(r);
    }

    final sortedBloks = blokMap.keys.toList()..sort();
    final computed =
        <
          ({
            String blok,
            String label,
            int totalNominal,
            int totalCount,
            List<int> nominal,
            List<int> counts,
          })
        >[];
    for (final b in sortedBloks) {
      final agg = _aggregateMonthly(blokMap[b]!, tahun: tahun);
      computed.add((
        blok: b,
        label: 'Blok ${int.tryParse(b) ?? b}',
        totalNominal: agg.totalNominal,
        totalCount: agg.totalCount,
        nominal: agg.nominal,
        counts: agg.counts,
      ));
    }

    List<
      ({
        String blok,
        String label,
        int totalNominal,
        int totalCount,
        List<int> nominal,
        List<int> counts,
      })
    >
    selected;
    if (dusunNumber != null) {
      selected = computed;
    } else {
      switch (mode) {
        case DhkpAllBlokTrendMode.top5:
          selected = [...computed]
            ..sort((a, b) {
              final cmp = b.totalNominal.compareTo(a.totalNominal);
              if (cmp != 0) return cmp;
              final cntCmp = b.totalCount.compareTo(a.totalCount);
              return cntCmp != 0 ? cntCmp : a.blok.compareTo(b.blok);
            });
          selected = selected.take(5).toList();
        case DhkpAllBlokTrendMode.bottom5:
          selected = [...computed]
            ..sort((a, b) {
              final cmp = a.totalNominal.compareTo(b.totalNominal);
              if (cmp != 0) return cmp;
              final cntCmp = a.totalCount.compareTo(b.totalCount);
              return cntCmp != 0 ? cntCmp : a.blok.compareTo(b.blok);
            });
          selected = selected.take(5).toList();
        case DhkpAllBlokTrendMode.custom:
          final chosen = computed
              .where((e) => customBloks.contains(e.blok))
              .take(maxCustomBloks)
              .toList();
          if (chosen.isNotEmpty) {
            selected = chosen;
          } else {
            selected = [...computed]
              ..sort((a, b) => b.totalNominal.compareTo(a.totalNominal));
            selected = selected.take(5).toList();
          }
      }
    }

    final palette = trendSeriesPalette(isDark: isDark);
    return [
      for (int i = 0; i < selected.length; i++)
        DhkpTrendSeries(
          id: 'blok:${selected[i].blok}',
          label: selected[i].label,
          monthlyNominal: selected[i].nominal,
          monthlyCounts: selected[i].counts,
          totalNominal: selected[i].totalNominal,
          totalCount: selected[i].totalCount,
          color: palette[i % palette.length],
        ),
    ];
  }

  /// Membangun seri garis tren per Desa di dalam 1 Kecamatan (maks [maxDesas] = 5 desa).
  static List<DhkpTrendSeries> buildDesaMonthlySeries({
    required List<BlokRecord> records,
    String? tahun,
    required bool isDark,
    Set<String> customDesas = const {},
    int maxDesas = 5,
  }) {
    final desaMap = <String, List<BlokRecord>>{};
    for (final r in records) {
      final d = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
      final kel = d.length == 18 ? nopKelurahan(d) : '000';
      desaMap.putIfAbsent(kel, () => []).add(r);
    }

    final computed =
        <
          ({
            String kel,
            String label,
            int totalNominal,
            int totalCount,
            List<int> nominal,
            List<int> counts,
          })
        >[];
    for (final entry in desaMap.entries) {
      final agg = _aggregateMonthly(entry.value, tahun: tahun);
      computed.add((
        kel: entry.key,
        label: formatDesaLabel(entry.key),
        totalNominal: agg.totalNominal,
        totalCount: agg.totalCount,
        nominal: agg.nominal,
        counts: agg.counts,
      ));
    }

    List<
      ({
        String kel,
        String label,
        int totalNominal,
        int totalCount,
        List<int> nominal,
        List<int> counts,
      })
    >
    chosen;
    if (customDesas.isNotEmpty) {
      chosen = computed
          .where((e) => customDesas.contains(e.kel))
          .take(maxDesas)
          .toList();
      if (chosen.isEmpty) {
        chosen = [...computed]
          ..sort((a, b) => b.totalNominal.compareTo(a.totalNominal));
        chosen = chosen.take(maxDesas).toList();
      }
    } else {
      chosen = [...computed]
        ..sort((a, b) => b.totalNominal.compareTo(a.totalNominal));
      chosen = chosen.take(maxDesas).toList();
    }

    final palette = trendSeriesPalette(isDark: isDark);
    return [
      for (int i = 0; i < chosen.length; i++)
        DhkpTrendSeries(
          id: 'desa:${chosen[i].kel}',
          label: chosen[i].label,
          monthlyNominal: chosen[i].nominal,
          monthlyCounts: chosen[i].counts,
          totalNominal: chosen[i].totalNominal,
          totalCount: chosen[i].totalCount,
          color: palette[i % palette.length],
        ),
    ];
  }

  static List<DhkpGroupInfo> groupData(
    List<BlokRecord> records, {
    required bool hasMultiDusun,
    required bool groupByDusun,
    int? drillDownDusun,
    bool seDesaMode = false,
    bool groupByDesa = false,
    String singleEntityLabel = 'Se-Desa',
    GrafikSortMode sortMode = GrafikSortMode.wilayah,
    double Function(DhkpGroupInfo)? sortValueFn,
    bool applySort = true,
  }) {
    final list = <DhkpGroupInfo>[];

    if (seDesaMode && drillDownDusun == null) {
      if (records.isNotEmpty) {
        list.add(_summarizeGroup(singleEntityLabel, records));
      }
      return list;
    }

    if (groupByDesa && drillDownDusun == null) {
      final desaMap = <String, List<BlokRecord>>{};
      for (final r in records) {
        final d = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
        final kel = d.length == 18 ? nopKelurahan(d) : '000';
        desaMap.putIfAbsent(kel, () => []).add(r);
      }
      final sortedKels = desaMap.keys.toList()..sort();
      for (final kel in sortedKels) {
        list.add(_summarizeGroup(formatDesaLabel(kel), desaMap[kel]!));
      }
    } else {
      // Hanya kelompokkan per Dusun apabila data memang skala Desa (multi-dusun)
      final effectiveGroupByDusun =
          hasMultiDusun && groupByDusun && drillDownDusun == null;

      if (effectiveGroupByDusun) {
        for (final dusun in dusunList) {
          final dBloks = dusun.bloks.toSet();
          final dRecs = records.where((r) => dBloks.contains(r.blok)).toList();
          if (dRecs.isEmpty) continue;
          list.add(_summarizeGroup('Dusun ${dusun.number}', dRecs));
        }
      }

      if (list.isEmpty) {
        // Kelompokkan per Blok (default otomatis untuk tingkat Dusun, atau saat pilih Semua Blok / drill-down Dusun)
        final blokMap = <String, List<BlokRecord>>{};
        for (final r in records) {
          blokMap.putIfAbsent(r.blok, () => []).add(r);
        }
        final sortedBlokKeys = blokMap.keys.toList()..sort();

        for (final b in sortedBlokKeys) {
          list.add(
            _summarizeGroup('Blok ${int.tryParse(b) ?? b}', blokMap[b]!),
          );
        }
      }
    }

    if (applySort &&
        sortValueFn != null &&
        sortMode != GrafikSortMode.wilayah) {
      if (sortMode == GrafikSortMode.tertinggi) {
        list.sort((a, b) => sortValueFn(b).compareTo(sortValueFn(a)));
      } else if (sortMode == GrafikSortMode.terendah) {
        list.sort((a, b) => sortValueFn(a).compareTo(sortValueFn(b)));
      }
    }

    return list;
  }

  static List<DhkpPieSliceInfo> makeSlices(
    List<DhkpGroupInfo> groups,
    double Function(DhkpGroupInfo) valFn,
    double totalVal,
  ) {
    const colors = [
      Colors.teal,
      Colors.indigo,
      Colors.amber,
      Colors.purple,
      Colors.cyan,
      Colors.deepOrange,
      Colors.blue,
      Colors.green,
      Colors.pink,
      Colors.lime,
      Colors.brown,
      Colors.blueGrey,
    ];
    final slices = <DhkpPieSliceInfo>[];
    for (int i = 0; i < groups.length; i++) {
      final g = groups[i];
      final val = valFn(g);
      if (val <= 0) continue;
      final ratio = totalVal > 0 ? (val / totalVal) : 0.0;
      slices.add(
        DhkpPieSliceInfo(
          label: g.label,
          nominal: val,
          ratio: ratio,
          color: colors[i % colors.length],
        ),
      );
    }
    return slices;
  }

  static List<double>? _validSparkline(List<double> raw) {
    if (raw.length < 2) return null;
    var hasNonZero = false;
    var hasVariance = false;
    final first = raw.first;
    for (final v in raw) {
      if (v > 0) hasNonZero = true;
      if ((v - first).abs() > 1e-6) hasVariance = true;
    }
    if (!hasNonZero || !hasVariance) return null;
    return raw;
  }

  static List<double>? _buildMonthlySparkline(
    List<int> monthlyBuckets, {
    required bool cumulative,
    List<double>? fallbackGroupValues,
  }) {
    var nonZeroCount = 0;
    var lastActive = -1;
    for (int i = 0; i < monthlyBuckets.length; i++) {
      if (monthlyBuckets[i] > 0) {
        nonZeroCount++;
        lastActive = i;
      }
    }
    if (nonZeroCount >= 2 && lastActive >= 1) {
      final pts = <double>[];
      var running = 0.0;
      for (int i = 0; i <= lastActive; i++) {
        final v = monthlyBuckets[i].toDouble();
        running = cumulative ? (running + v) : v;
        pts.add(running);
      }
      final valid = _validSparkline(pts);
      if (valid != null) return valid;
    }
    if (fallbackGroupValues != null && fallbackGroupValues.length >= 2) {
      return _validSparkline(fallbackGroupValues.take(12).toList());
    }
    return null;
  }

  static ({String text, bool isFavorable})? _computeDelta({
    required double current,
    required double? previous,
    required String? prevYear,
    bool isPercentagePoint = false,
    bool favorableWhenHigher = true,
  }) {
    if (previous == null || prevYear == null || prevYear.isEmpty) {
      return null;
    }
    if (isPercentagePoint) {
      final diff = current - previous;
      if (diff.abs() < 0.05) {
        return (text: '0.0% vs $prevYear', isFavorable: true);
      }
      final sign = diff > 0 ? '+' : '';
      return (
        text: '$sign${diff.toStringAsFixed(1)}% vs $prevYear',
        isFavorable: favorableWhenHigher ? diff >= 0 : diff <= 0,
      );
    }
    if (previous <= 0) return null;
    final pct = ((current - previous) / previous) * 100.0;
    final formatted = pct.abs() > 999
        ? '${pct >= 0 ? '>' : '<-'}999%'
        : pct.abs() >= 100
        ? '${pct > 0 ? '+' : ''}${pct.round()}%'
        : '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
    return (
      text: '$formatted vs $prevYear',
      isFavorable: favorableWhenHigher ? pct >= 0 : pct <= 0,
    );
  }

  static ({
    int totalNop,
    int paidCount,
    int unpaidCount,
    int paidNominal,
    int unpaidNominal,
    int targetNominal,
    double lunasNominalPct,
    double lunasNopPct,
    int datedCount,
  })
  _summarizePeriod(List<BlokRecord> recs, {String? tahun}) {
    var paidCount = 0;
    var unpaidCount = 0;
    var paidNominal = 0;
    var unpaidNominal = 0;
    var targetNominal = 0;
    for (final r in recs) {
      final val = r.jumlahPbbValue;
      targetNominal += val;
      if (r.isPaid) {
        paidCount++;
        paidNominal += val;
      } else {
        unpaidCount++;
        unpaidNominal += val;
      }
    }
    final totalNop = recs.length;
    final lunasNopPct = totalNop > 0 ? (paidCount / totalNop * 100) : 0.0;
    final lunasNominalPct = (targetNominal > 0 && unpaidNominal > 0)
        ? (paidNominal / targetNominal * 100)
        : (unpaidCount == 0 ? (totalNop > 0 ? 100.0 : 0.0) : lunasNopPct);
    final agg = _aggregateMonthly(recs, tahun: tahun);
    return (
      totalNop: totalNop,
      paidCount: paidCount,
      unpaidCount: unpaidCount,
      paidNominal: paidNominal,
      unpaidNominal: unpaidNominal,
      targetNominal: targetNominal,
      lunasNominalPct: lunasNominalPct,
      lunasNopPct: lunasNopPct,
      datedCount: agg.totalCount,
    );
  }

  static DhkpGaugeSummary buildGaugeSummary({
    required String scopeTitle,
    required String tahun,
    required int paidNominal,
    required int targetNominal,
    required int paidCount,
    required int totalCount,
    required double achievedPct,
    required double objPct,
    MaterialColor accentColor = Colors.green,
    List<BlokRecord>? previousYearRecords,
    String? previousYearLabel,
  }) {
    String? deltaText;
    bool deltaIsFavorable = true;
    if (previousYearRecords != null &&
        previousYearRecords.isNotEmpty &&
        previousYearLabel != null &&
        previousYearLabel.isNotEmpty) {
      final prev = _summarizePeriod(
        previousYearRecords,
        tahun: previousYearLabel,
      );
      final delta = _computeDelta(
        current: achievedPct,
        previous: prev.lunasNominalPct,
        prevYear: previousYearLabel,
        isPercentagePoint: true,
        favorableWhenHigher: true,
      );
      if (delta != null) {
        deltaText = delta.text;
        deltaIsFavorable = delta.isFavorable;
      }
    }

    return DhkpGaugeSummary(
      scopeTitle: scopeTitle,
      tahun: tahun,
      achievedPct: achievedPct.clamp(0.0, 100.0),
      objPct: objPct.clamp(0.0, 100.0),
      paidNominal: paidNominal,
      targetNominal: targetNominal,
      paidCount: paidCount,
      totalCount: totalCount,
      prevYear: previousYearLabel,
      deltaText: deltaText,
      deltaIsFavorable: deltaIsFavorable,
      accentColor: accentColor,
    );
  }

  static List<DhkpStatItem> buildHighlightStats({
    required DhkpGrafikTab activeTab,
    required int totalNop,
    required int sudahBayarCount,
    required int belumBayarCount,
    required int sudahBayarNominal,
    required int belumBayarNominal,
    required int totalNominalTarget,
    required double lunasNominalPct,
    required double lunasNopPct,
    required List<BlokRecord> records,
    String? tahun,
    List<BlokRecord>? previousYearRecords,
    String? previousYearLabel,
    List<DhkpGroupInfo>? groups,
  }) {
    final agg = _aggregateMonthly(records, tahun: tahun);
    final prev =
        (previousYearRecords != null &&
            previousYearRecords.isNotEmpty &&
            previousYearLabel != null &&
            previousYearLabel.isNotEmpty)
        ? _summarizePeriod(previousYearRecords, tahun: previousYearLabel)
        : null;

    final groupTargets = groups?.map((g) => g.totalNominal.toDouble()).toList();
    final groupPaidNominal = groups
        ?.map((g) => g.lunasNominal.toDouble())
        .toList();
    final groupUnpaidNominal = groups
        ?.map((g) => g.belumBayarNominal.toDouble())
        .toList();
    final groupUnpaidCount = groups
        ?.map((g) => g.belumBayarNop.toDouble())
        .toList();
    final groupPct = groups?.map((g) => g.lunasPct).toList();
    final groupNopPct = groups?.map((g) => g.lunasNopPct).toList();
    final groupPaidCount = groups?.map((g) => g.lunasNop.toDouble()).toList();

    final paidNominalSpark = _buildMonthlySparkline(
      agg.nominal,
      cumulative: true,
      fallbackGroupValues: groupPaidNominal,
    );
    final paidCountSpark = _buildMonthlySparkline(
      agg.counts,
      cumulative: true,
      fallbackGroupValues: groupPaidCount,
    );
    final monthlyVelocitySpark = _buildMonthlySparkline(
      agg.nominal,
      cumulative: false,
      fallbackGroupValues: groupPaidNominal,
    );
    final monthlyCountVelocitySpark = _buildMonthlySparkline(
      agg.counts,
      cumulative: false,
      fallbackGroupValues: groupPaidCount,
    );

    switch (activeTab) {
      case DhkpGrafikTab.pendapatan:
        final dPaid = _computeDelta(
          current: sudahBayarNominal.toDouble(),
          previous: prev?.paidNominal.toDouble(),
          prevYear: previousYearLabel,
        );
        final dTarget = _computeDelta(
          current: totalNominalTarget.toDouble(),
          previous: prev?.targetNominal.toDouble(),
          prevYear: previousYearLabel,
        );
        final dUnpaid = _computeDelta(
          current: belumBayarNominal.toDouble(),
          previous: prev?.unpaidNominal.toDouble(),
          prevYear: previousYearLabel,
          favorableWhenHigher: false,
        );
        return [
          DhkpStatItem(
            label: 'Pendapatan Masuk',
            value: formatRupiah(sudahBayarNominal),
            sub: 'Uang pajak terkumpul',
            color: Colors.teal,
            icon: Icons.account_balance_wallet_rounded,
            sparklinePoints: paidNominalSpark,
            deltaText: dPaid?.text,
            deltaIsFavorable: dPaid?.isFavorable,
            numericValue: sudahBayarNominal.toDouble(),
            animatedValueBuilder: (v) => formatRupiah(v.round()),
          ),
          DhkpStatItem(
            label: 'Total Target',
            value: 'Rp ${formatShortRupiah(totalNominalTarget)}',
            sub: 'Ketetapan pokok wilayah',
            color: Colors.indigo,
            icon: Icons.flag_rounded,
            sparklinePoints: _validSparkline(groupTargets ?? const []),
            deltaText: dTarget?.text,
            deltaIsFavorable: dTarget?.isFavorable,
            numericValue: totalNominalTarget.toDouble(),
            animatedValueBuilder: (v) => 'Rp ${formatShortRupiah(v.round())}',
          ),
          DhkpStatItem(
            label: 'Belum Masuk',
            value: 'Rp ${formatShortRupiah(belumBayarNominal)}',
            sub: 'Selisih dari target',
            color: Colors.orange,
            icon: Icons.hourglass_bottom_rounded,
            sparklinePoints: _validSparkline(groupUnpaidNominal ?? const []),
            deltaText: dUnpaid?.text,
            deltaIsFavorable: dUnpaid?.isFavorable,
            numericValue: belumBayarNominal.toDouble(),
            animatedValueBuilder: (v) => 'Rp ${formatShortRupiah(v.round())}',
          ),
        ];

      case DhkpGrafikTab.persentase:
        final dPct = _computeDelta(
          current: lunasNominalPct,
          previous: prev?.lunasNominalPct,
          prevYear: previousYearLabel,
          isPercentagePoint: true,
        );
        final dNopPct = _computeDelta(
          current: lunasNopPct,
          previous: prev?.lunasNopPct,
          prevYear: previousYearLabel,
          isPercentagePoint: true,
        );
        final remPct = (100 - lunasNominalPct).clamp(0.0, 100.0);
        final prevRemPct = prev != null
            ? (100 - prev.lunasNominalPct).clamp(0.0, 100.0)
            : null;
        final dRemPct = _computeDelta(
          current: remPct,
          previous: prevRemPct,
          prevYear: previousYearLabel,
          isPercentagePoint: true,
          favorableWhenHigher: false,
        );
        return [
          DhkpStatItem(
            label: 'Capaian Uang (%)',
            value: '${lunasNominalPct.toStringAsFixed(1)}%',
            sub: 'Dari total nilai target',
            color: Colors.green,
            icon: Icons.percent_rounded,
            sparklinePoints: paidNominalSpark ?? _validSparkline(groupPct ?? const []),
            deltaText: dPct?.text,
            deltaIsFavorable: dPct?.isFavorable,
            gaugeRatio: (lunasNominalPct / 100).clamp(0.0, 1.0),
            numericValue: lunasNominalPct,
            animatedValueBuilder: (v) => '${v.toStringAsFixed(1)}%',
          ),
          DhkpStatItem(
            label: 'Capaian Objek Pajak',
            value: '${lunasNopPct.toStringAsFixed(1)}%',
            sub: '$sudahBayarCount dari $totalNop objek',
            color: Colors.teal,
            icon: Icons.check_circle_outline_rounded,
            sparklinePoints: paidCountSpark ?? _validSparkline(groupNopPct ?? const []),
            deltaText: dNopPct?.text,
            deltaIsFavorable: dNopPct?.isFavorable,
            gaugeRatio: (lunasNopPct / 100).clamp(0.0, 1.0),
            numericValue: lunasNopPct,
            animatedValueBuilder: (v) => '${v.toStringAsFixed(1)}%',
          ),
          DhkpStatItem(
            label: 'Sisa Belum Tercapai',
            value: '${remPct.toStringAsFixed(1)}%',
            sub: 'Perlu ditagih',
            color: Colors.amber,
            icon: Icons.timelapse_rounded,
            sparklinePoints: _validSparkline(
              (groupPct ?? const []).map((p) => (100 - p).clamp(0.0, 100.0)).toList(),
            ),
            deltaText: dRemPct?.text,
            deltaIsFavorable: dRemPct?.isFavorable,
            numericValue: remPct,
            animatedValueBuilder: (v) => '${v.toStringAsFixed(1)}%',
          ),
        ];

      case DhkpGrafikTab.belumBayar:
        final dUnpaid = _computeDelta(
          current: belumBayarNominal.toDouble(),
          previous: prev?.unpaidNominal.toDouble(),
          prevYear: previousYearLabel,
          favorableWhenHigher: false,
        );
        final dUnpaidCount = _computeDelta(
          current: belumBayarCount.toDouble(),
          previous: prev?.unpaidCount.toDouble(),
          prevYear: previousYearLabel,
          favorableWhenHigher: false,
        );
        final unpaidPct = (100 - lunasNominalPct).clamp(0.0, 100.0);
        final prevUnpaidPct = prev != null
            ? (100 - prev.lunasNominalPct).clamp(0.0, 100.0)
            : null;
        final dUnpaidPct = _computeDelta(
          current: unpaidPct,
          previous: prevUnpaidPct,
          prevYear: previousYearLabel,
          isPercentagePoint: true,
          favorableWhenHigher: false,
        );
        return [
          DhkpStatItem(
            label: 'Tagihan Belum Bayar',
            value: formatRupiah(belumBayarNominal),
            sub: 'Total belum lunas',
            color: Colors.orange,
            icon: Icons.pending_actions_rounded,
            sparklinePoints: _validSparkline(groupUnpaidNominal ?? const []),
            deltaText: dUnpaid?.text,
            deltaIsFavorable: dUnpaid?.isFavorable,
            numericValue: belumBayarNominal.toDouble(),
            animatedValueBuilder: (v) => formatRupiah(v.round()),
          ),
          DhkpStatItem(
            label: 'Objek Belum Lunas',
            value: '$belumBayarCount Objek',
            sub: 'Wajib pajak belum bayar',
            color: Colors.deepOrange,
            icon: Icons.person_search_rounded,
            sparklinePoints: _validSparkline(groupUnpaidCount ?? const []),
            deltaText: dUnpaidCount?.text,
            deltaIsFavorable: dUnpaidCount?.isFavorable,
            numericValue: belumBayarCount.toDouble(),
            animatedValueBuilder: (v) => '${v.round()} Objek',
          ),
          DhkpStatItem(
            label: 'Persentase Belum Bayar',
            value: '${unpaidPct.toStringAsFixed(1)}%',
            sub: 'Dari total target wilayah',
            color: Colors.red,
            icon: Icons.pie_chart_rounded,
            sparklinePoints: _validSparkline(
              (groupPct ?? const []).map((p) => (100 - p).clamp(0.0, 100.0)).toList(),
            ),
            deltaText: dUnpaidPct?.text,
            deltaIsFavorable: dUnpaidPct?.isFavorable,
            numericValue: unpaidPct,
            animatedValueBuilder: (v) => '${v.toStringAsFixed(1)}%',
          ),
        ];

      case DhkpGrafikTab.sudahBayar:
        final avgNom = sudahBayarCount > 0
            ? (sudahBayarNominal ~/ sudahBayarCount)
            : 0;
        final prevAvgNom = (prev != null && prev.paidCount > 0)
            ? (prev.paidNominal / prev.paidCount)
            : null;
        final dPaid = _computeDelta(
          current: sudahBayarNominal.toDouble(),
          previous: prev?.paidNominal.toDouble(),
          prevYear: previousYearLabel,
        );
        final dPaidCount = _computeDelta(
          current: sudahBayarCount.toDouble(),
          previous: prev?.paidCount.toDouble(),
          prevYear: previousYearLabel,
        );
        final dAvg = _computeDelta(
          current: avgNom.toDouble(),
          previous: prevAvgNom,
          prevYear: previousYearLabel,
        );
        return [
          DhkpStatItem(
            label: 'Total Sudah Bayar',
            value: formatRupiah(sudahBayarNominal),
            sub: 'Uang sudah lunas',
            color: Colors.blue,
            icon: Icons.task_alt_rounded,
            sparklinePoints: paidNominalSpark,
            deltaText: dPaid?.text,
            deltaIsFavorable: dPaid?.isFavorable,
            numericValue: sudahBayarNominal.toDouble(),
            animatedValueBuilder: (v) => formatRupiah(v.round()),
          ),
          DhkpStatItem(
            label: 'Jumlah Objek Lunas',
            value: '$sudahBayarCount Objek',
            sub: 'Wajib pajak sudah bayar',
            color: Colors.teal,
            icon: Icons.receipt_rounded,
            sparklinePoints: paidCountSpark,
            deltaText: dPaidCount?.text,
            deltaIsFavorable: dPaidCount?.isFavorable,
            numericValue: sudahBayarCount.toDouble(),
            animatedValueBuilder: (v) => '${v.round()} Objek',
          ),
          DhkpStatItem(
            label: 'Rata-rata Pembayaran',
            value: 'Rp ${formatShortRupiah(avgNom)}',
            sub: 'Nilai rata-rata per objek',
            color: Colors.indigo,
            icon: Icons.calculate_rounded,
            sparklinePoints: monthlyVelocitySpark,
            deltaText: dAvg?.text,
            deltaIsFavorable: dAvg?.isFavorable,
            numericValue: avgNom.toDouble(),
            animatedValueBuilder: (v) => 'Rp ${formatShortRupiah(v.round())}',
          ),
        ];

      case DhkpGrafikTab.trenBulanan:
        int peakMonth = 0;
        int peakVal = 0;
        for (int i = 0; i < 12; i++) {
          if (agg.nominal[i] > peakVal) {
            peakVal = agg.nominal[i];
            peakMonth = i + 1;
          }
        }
        final peakName = peakMonth > 0
            ? '${monthNames[peakMonth - 1]} (Rp ${formatShortRupiah(peakVal)})'
            : '-';

        final dTotal = _computeDelta(
          current: sudahBayarNominal.toDouble(),
          previous: prev?.paidNominal.toDouble(),
          prevYear: previousYearLabel,
        );
        final dDated = _computeDelta(
          current: agg.totalCount.toDouble(),
          previous: prev?.datedCount.toDouble(),
          prevYear: previousYearLabel,
        );

        return [
          DhkpStatItem(
            label: 'Bulan Tertinggi',
            value: peakName,
            sub: 'Penerimaan terbanyak',
            color: Colors.purple,
            icon: Icons.trending_up_rounded,
            sparklinePoints: monthlyVelocitySpark,
            numericValue: peakMonth > 0 ? peakVal.toDouble() : null,
            animatedValueBuilder: peakMonth > 0
                ? (v) =>
                      '${monthNames[peakMonth - 1]} (Rp ${formatShortRupiah(v.round())})'
                : null,
          ),
          DhkpStatItem(
            label: 'Pembayaran Tercatat',
            value: '${agg.totalCount} Objek',
            sub: 'Memiliki tanggal bayar',
            color: Colors.indigo,
            icon: Icons.calendar_today_rounded,
            sparklinePoints: monthlyCountVelocitySpark,
            deltaText: dDated?.text,
            deltaIsFavorable: dDated?.isFavorable,
            numericValue: agg.totalCount.toDouble(),
            animatedValueBuilder: (v) => '${v.round()} Objek',
          ),
          DhkpStatItem(
            label: 'Total Jan - Des',
            value: 'Rp ${formatShortRupiah(sudahBayarNominal)}',
            sub: 'Penerimaan tahun ini',
            color: Colors.teal,
            icon: Icons.date_range_rounded,
            sparklinePoints: paidNominalSpark,
            deltaText: dTotal?.text,
            deltaIsFavorable: dTotal?.isFavorable,
            numericValue: sudahBayarNominal.toDouble(),
            animatedValueBuilder: (v) => 'Rp ${formatShortRupiah(v.round())}',
          ),
        ];
    }
  }
}
