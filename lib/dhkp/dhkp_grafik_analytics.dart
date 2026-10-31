import 'package:flutter/material.dart';

import '../blok_record.dart';
import '../dusun_data.dart';
import '../tagihan_result.dart' show formatRupiah;

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
    'Tren Jan–Des',
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

DateTime? parsePaymentDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s == '2026') return null;
  try {
    return DateTime.parse(s);
  } catch (_) {}
  final dmy = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(s);
  if (dmy != null) {
    final d = int.tryParse(dmy.group(1)!);
    final m = int.tryParse(dmy.group(2)!);
    final y = int.tryParse(dmy.group(3)!);
    if (d != null && m != null && y != null) {
      return DateTime(y, m, d);
    }
  }
  return null;
}

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

  const DhkpStatItem({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });
}

class DhkpGrafikAnalytics {
  const DhkpGrafikAnalytics._();

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

  static List<DhkpGroupInfo> buildMonthGroups(List<BlokRecord> records) {
    final monthlyNominal = List<int>.filled(12, 0);
    final monthlyCount = List<int>.filled(12, 0);

    for (final r in records) {
      if (r.isPaid && r.tanggalBayar.isNotEmpty) {
        final dt = parsePaymentDate(r.tanggalBayar);
        if (dt != null && dt.month >= 1 && dt.month <= 12) {
          monthlyNominal[dt.month - 1] += r.jumlahPbbValue;
          monthlyCount[dt.month - 1]++;
        }
      }
    }

    final totalDatedNominal = monthlyNominal.fold<int>(0, (sum, v) => sum + v);
    final totalDatedCount = monthlyCount.fold<int>(0, (sum, v) => sum + v);

    final monthGroups = <DhkpGroupInfo>[];
    for (int i = 0; i < 12; i++) {
      final nom = monthlyNominal[i];
      final cnt = monthlyCount[i];
      final pct = totalDatedNominal > 0 ? (nom / totalDatedNominal * 100) : 0.0;
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
          lunasNopPct: totalDatedCount > 0
              ? (cnt / totalDatedCount * 100)
              : 0.0,
        ),
      );
    }
    return monthGroups;
  }

  static List<DhkpGroupInfo> groupData(
    List<BlokRecord> records, {
    required bool hasMultiDusun,
    required bool groupByDusun,
    int? drillDownDusun,
    GrafikSortMode sortMode = GrafikSortMode.wilayah,
    double Function(DhkpGroupInfo)? sortValueFn,
    bool applySort = true,
  }) {
    final list = <DhkpGroupInfo>[];

    // Hanya kelompokkan per Dusun apabila data memang skala Desa (multi-dusun)
    final effectiveGroupByDusun =
        hasMultiDusun && groupByDusun && drillDownDusun == null;

    if (effectiveGroupByDusun) {
      for (final dusun in dusunList) {
        final dBloks = dusun.bloks.toSet();
        final dRecs = records.where((r) => dBloks.contains(r.blok)).toList();
        if (dRecs.isEmpty) continue;

        final lunasRecs = dRecs.where((r) => r.isPaid).toList();
        final belumRecs = dRecs.where((r) => !r.isPaid).toList();

        final lunasNominal = lunasRecs.fold<int>(
          0,
          (sum, r) => sum + r.jumlahPbbValue,
        );
        final belumNominal = belumRecs.fold<int>(
          0,
          (sum, r) => sum + r.jumlahPbbValue,
        );
        final totalNominal = dRecs.fold<int>(
          0,
          (sum, r) => sum + r.jumlahPbbValue,
        );

        final lunasPct = totalNominal > 0
            ? (lunasNominal / totalNominal * 100)
            : 0.0;
        final lunasNopPct = dRecs.isNotEmpty
            ? (lunasRecs.length / dRecs.length * 100)
            : 0.0;

        list.add(
          DhkpGroupInfo(
            label: 'Dusun ${dusun.number}',
            totalNop: dRecs.length,
            lunasNop: lunasRecs.length,
            belumBayarNop: belumRecs.length,
            lunasNominal: lunasNominal,
            belumBayarNominal: belumNominal,
            totalNominal: totalNominal,
            lunasPct: lunasPct,
            lunasNopPct: lunasNopPct,
          ),
        );
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
        final bRecs = blokMap[b]!;
        final lunasRecs = bRecs.where((r) => r.isPaid).toList();
        final belumRecs = bRecs.where((r) => !r.isPaid).toList();

        final lunasNominal = lunasRecs.fold<int>(
          0,
          (sum, r) => sum + r.jumlahPbbValue,
        );
        final belumNominal = belumRecs.fold<int>(
          0,
          (sum, r) => sum + r.jumlahPbbValue,
        );
        final totalNominal = bRecs.fold<int>(
          0,
          (sum, r) => sum + r.jumlahPbbValue,
        );

        final lunasPct = totalNominal > 0
            ? (lunasNominal / totalNominal * 100)
            : 0.0;
        final lunasNopPct = bRecs.isNotEmpty
            ? (lunasRecs.length / bRecs.length * 100)
            : 0.0;

        list.add(
          DhkpGroupInfo(
            label: 'Blok ${int.tryParse(b) ?? b}',
            totalNop: bRecs.length,
            lunasNop: lunasRecs.length,
            belumBayarNop: belumRecs.length,
            lunasNominal: lunasNominal,
            belumBayarNominal: belumNominal,
            totalNominal: totalNominal,
            lunasPct: lunasPct,
            lunasNopPct: lunasNopPct,
          ),
        );
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
  }) {
    switch (activeTab) {
      case DhkpGrafikTab.pendapatan:
        return [
          DhkpStatItem(
            label: 'Pendapatan Masuk',
            value: formatRupiah(sudahBayarNominal),
            sub: 'Uang pajak terkumpul',
            color: Colors.teal,
            icon: Icons.account_balance_wallet_rounded,
          ),
          DhkpStatItem(
            label: 'Total Target',
            value: 'Rp ${formatShortRupiah(totalNominalTarget)}',
            sub: 'Ketetapan pokok wilayah',
            color: Colors.indigo,
            icon: Icons.flag_rounded,
          ),
          DhkpStatItem(
            label: 'Belum Masuk',
            value: 'Rp ${formatShortRupiah(belumBayarNominal)}',
            sub: 'Selisih dari target',
            color: Colors.orange,
            icon: Icons.hourglass_bottom_rounded,
          ),
        ];

      case DhkpGrafikTab.persentase:
        return [
          DhkpStatItem(
            label: 'Capaian Uang (%)',
            value: '${lunasNominalPct.toStringAsFixed(1)}%',
            sub: 'Dari total nilai target',
            color: Colors.green,
            icon: Icons.percent_rounded,
          ),
          DhkpStatItem(
            label: 'Capaian Objek Pajak',
            value: '${lunasNopPct.toStringAsFixed(1)}%',
            sub: '$sudahBayarCount dari $totalNop objek',
            color: Colors.teal,
            icon: Icons.check_circle_outline_rounded,
          ),
          DhkpStatItem(
            label: 'Sisa Belum Tercapai',
            value:
                '${(100 - lunasNominalPct).clamp(0, 100).toStringAsFixed(1)}%',
            sub: 'Perlu ditagih',
            color: Colors.amber,
            icon: Icons.timelapse_rounded,
          ),
        ];

      case DhkpGrafikTab.belumBayar:
        return [
          DhkpStatItem(
            label: 'Tagihan Belum Bayar',
            value: formatRupiah(belumBayarNominal),
            sub: 'Total belum lunas',
            color: Colors.orange,
            icon: Icons.pending_actions_rounded,
          ),
          DhkpStatItem(
            label: 'Objek Belum Lunas',
            value: '$belumBayarCount Objek',
            sub: 'Wajib pajak belum bayar',
            color: Colors.deepOrange,
            icon: Icons.person_search_rounded,
          ),
          DhkpStatItem(
            label: 'Persentase Belum Bayar',
            value:
                '${(100 - lunasNominalPct).clamp(0, 100).toStringAsFixed(1)}%',
            sub: 'Dari total target wilayah',
            color: Colors.red,
            icon: Icons.pie_chart_rounded,
          ),
        ];

      case DhkpGrafikTab.sudahBayar:
        final avgNom = sudahBayarCount > 0
            ? (sudahBayarNominal ~/ sudahBayarCount)
            : 0;
        return [
          DhkpStatItem(
            label: 'Total Sudah Bayar',
            value: formatRupiah(sudahBayarNominal),
            sub: 'Uang sudah lunas',
            color: Colors.blue,
            icon: Icons.task_alt_rounded,
          ),
          DhkpStatItem(
            label: 'Jumlah Objek Lunas',
            value: '$sudahBayarCount Objek',
            sub: 'Wajib pajak sudah bayar',
            color: Colors.teal,
            icon: Icons.receipt_rounded,
          ),
          DhkpStatItem(
            label: 'Rata-rata Pembayaran',
            value: 'Rp ${formatShortRupiah(avgNom)}',
            sub: 'Nilai rata-rata per objek',
            color: Colors.indigo,
            icon: Icons.calculate_rounded,
          ),
        ];

      case DhkpGrafikTab.trenBulanan:
        final monthlyData = List<int>.filled(12, 0);
        int datedCount = 0;
        for (final r in records) {
          if (r.isPaid && r.tanggalBayar.isNotEmpty) {
            final dt = parsePaymentDate(r.tanggalBayar);
            if (dt != null && dt.month >= 1 && dt.month <= 12) {
              monthlyData[dt.month - 1] += r.jumlahPbbValue;
              datedCount++;
            }
          }
        }
        int peakMonth = 0;
        int peakVal = 0;
        for (int i = 0; i < 12; i++) {
          if (monthlyData[i] > peakVal) {
            peakVal = monthlyData[i];
            peakMonth = i + 1;
          }
        }
        final peakName = peakMonth > 0
            ? '${monthNames[peakMonth - 1]} (Rp ${formatShortRupiah(peakVal)})'
            : '-';

        return [
          DhkpStatItem(
            label: 'Bulan Tertinggi',
            value: peakName,
            sub: 'Penerimaan terbanyak',
            color: Colors.purple,
            icon: Icons.trending_up_rounded,
          ),
          DhkpStatItem(
            label: 'Pembayaran Tercatat',
            value: '$datedCount Objek',
            sub: 'Memiliki tanggal bayar',
            color: Colors.indigo,
            icon: Icons.calendar_today_rounded,
          ),
          DhkpStatItem(
            label: 'Total Jan–Des',
            value: 'Rp ${formatShortRupiah(sudahBayarNominal)}',
            sub: 'Penerimaan tahun ini',
            color: Colors.teal,
            icon: Icons.date_range_rounded,
          ),
        ];
    }
  }
}
