import 'package:flutter/material.dart';

import '../blok_record.dart';
import '../tagihan_result.dart' show formatRupiah;
import '../unity_lerp_widgets.dart';
import 'blok_catatan_models.dart';

class BlokCatatanLoadingView extends StatelessWidget {
  final String title;

  const BlokCatatanLoadingView({
    super.key,
    this.title = 'Memuat Data DHKP & Status Bayar',
  });

  @override
  Widget build(BuildContext context) {
    return SmoothLoadingCard(
      icon: Icons.receipt_long_rounded,
      title: title,
      subtitle:
          'Menyiapkan seluruh catatan blok, bukti STTS, dan rekapitulasi data...',
      badgeText: 'Memastikan semua data termuat',
    );
  }
}

class DhkpStatusBadge extends StatelessWidget {
  final BlokRecord record;

  const DhkpStatusBadge({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor;
    Color textColor;
    Color borderColor;
    String displayStatus = record.isPaid ? 'Sudah Bayar' : record.statusBayar;

    if (record.isBlacklist) {
      if (isDark) {
        bgColor = Colors.white;
        textColor = Colors.black87;
        borderColor = Colors.white;
      } else {
        bgColor = Colors.black87;
        textColor = Colors.white;
        borderColor = Colors.black;
      }
      if (!displayStatus.toLowerCase().contains('black') &&
          !displayStatus.toLowerCase().contains('daftar')) {
        displayStatus = 'Blacklist (≥ 5 Thn)';
      }
    } else if (record.isPaid) {
      bgColor = Colors.green.withValues(alpha: 0.15);
      textColor = isDark ? Colors.green.shade300 : Colors.green.shade800;
      borderColor = Colors.green;
    } else {
      bgColor = Colors.orange.withValues(alpha: 0.15);
      textColor = isDark ? Colors.orange.shade300 : Colors.orange.shade900;
      borderColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        displayStatus,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class BlokCatatanPaginationBar extends StatelessWidget {
  final int startIndex;
  final int endIndex;
  final int totalRecords;
  final int safePage;
  final int totalPages;
  final int rowsPerPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  const BlokCatatanPaginationBar({
    super.key,
    required this.startIndex,
    required this.endIndex,
    required this.totalRecords,
    required this.safePage,
    required this.totalPages,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;

          final infoWidget = Text(
            'Menampilkan ${startIndex + 1}-$endIndex dari $totalRecords data',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          );

          final controlsWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.first_page, size: 20),
                tooltip: 'Halaman Pertama',
                onPressed: safePage > 0 ? () => onPageChanged(0) : null,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_left, size: 20),
                tooltip: 'Halaman Sebelumnya',
                onPressed: safePage > 0
                    ? () => onPageChanged(safePage - 1)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Hal ${safePage + 1} / $totalPages',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_right, size: 20),
                tooltip: 'Halaman Berikutnya',
                onPressed: safePage < totalPages - 1
                    ? () => onPageChanged(safePage + 1)
                    : null,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.last_page, size: 20),
                tooltip: 'Halaman Terakhir',
                onPressed: safePage < totalPages - 1
                    ? () => onPageChanged(totalPages - 1)
                    : null,
              ),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: rowsPerPage,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                      value: 25,
                      child: Text('25 / hal', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 50,
                      child: Text('50 / hal', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 100,
                      child: Text('100 / hal', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 200,
                      child: Text('200 / hal', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: -1,
                      child: Text('Semua', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      onRowsPerPageChanged(val);
                    }
                  },
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                infoWidget,
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: controlsWidget,
                ),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [infoWidget, controlsWidget],
          );
        },
      ),
    );
  }
}

class DhkpSummaryFooterCard extends StatelessWidget {
  final DhkpSummaryMetrics metrics;

  const DhkpSummaryFooterCard({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final sudahBayarCount = metrics.sudahBayarCount;
    final sudahBayarNominal = metrics.sudahBayarNominal;
    final belumBayarCount = metrics.belumBayarCount;
    final belumBayarNominal = metrics.belumBayarNominal;
    final targetPemdaCount = metrics.targetPemdaCount;
    final targetPemdaNominal = metrics.targetPemdaNominal;
    final totalCount = metrics.totalCount;
    final totalNominal = metrics.totalNominal;
    final pctSudah = metrics.pctSudah;
    final pctBelum = metrics.pctBelum;
    final pctTotal = metrics.pctTotal;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dividerColor = Colors.grey.withValues(alpha: 0.3);

            if (constraints.maxWidth < 480) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryMetric(
                          label: 'Sudah Bayar',
                          count: sudahBayarCount,
                          nominal: sudahBayarNominal,
                          percentage: pctSudah,
                          color: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                      Container(width: 1, height: 36, color: dividerColor),
                      Expanded(
                        child: _buildSummaryMetric(
                          label: 'Belum Bayar',
                          count: belumBayarCount,
                          nominal: belumBayarNominal,
                          percentage: pctBelum,
                          color: Colors.orange.shade800,
                          icon: Icons.pending_actions_outlined,
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 12, color: dividerColor),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryMetric(
                          label: 'Target Pemda',
                          count: targetPemdaCount,
                          nominal: targetPemdaNominal,
                          color: Colors.red.shade700,
                          icon: Icons.track_changes,
                        ),
                      ),
                      Container(width: 1, height: 36, color: dividerColor),
                      Expanded(
                        child: _buildSummaryMetric(
                          label: 'Total Keseluruhan',
                          count: totalCount,
                          nominal: totalNominal,
                          percentage: pctTotal,
                          color: Colors.blue.shade800,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            } else {
              return Row(
                children: [
                  Expanded(
                    child: _buildSummaryMetric(
                      label: 'Sudah Bayar',
                      count: sudahBayarCount,
                      nominal: sudahBayarNominal,
                      percentage: pctSudah,
                      color: Colors.green,
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                  Container(width: 1, height: 38, color: dividerColor),
                  Expanded(
                    child: _buildSummaryMetric(
                      label: 'Belum Bayar',
                      count: belumBayarCount,
                      nominal: belumBayarNominal,
                      percentage: pctBelum,
                      color: Colors.orange.shade800,
                      icon: Icons.pending_actions_outlined,
                    ),
                  ),
                  Container(width: 1, height: 38, color: dividerColor),
                  Expanded(
                    child: _buildSummaryMetric(
                      label: 'Target Pemda',
                      count: targetPemdaCount,
                      nominal: targetPemdaNominal,
                      color: Colors.red.shade700,
                      icon: Icons.track_changes,
                    ),
                  ),
                  Container(width: 1, height: 38, color: dividerColor),
                  Expanded(
                    child: _buildSummaryMetric(
                      label: 'Total Keseluruhan',
                      count: totalCount,
                      nominal: totalNominal,
                      percentage: pctTotal,
                      color: Colors.blue.shade800,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required int count,
    required int nominal,
    required Color color,
    required IconData icon,
    String? percentage,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (percentage != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    percentage,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          LerpAnimatedCounter(
            value: nominal,
            formatter: (v) => formatRupiah(v.round()),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          LerpAnimatedCounter(
            value: count,
            formatter: (v) => '${v.round()} WP',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
