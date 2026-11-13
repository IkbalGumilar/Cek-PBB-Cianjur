import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../blok_record.dart';
import '../blok_report_pdf.dart'
    show BlokPrintCancelToken, BlokPrintCancelledException;
import '../calculator/pbb_calculator_models.dart';
import '../tagihan_result.dart' show formatRupiah;
import '../unity_lerp_widgets.dart';
import 'blok_catatan_models.dart';

export '../blok_report_pdf.dart'
    show BlokPrintCancelToken, BlokPrintCancelledException;

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
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dividerColor = Colors.grey.withValues(alpha: 0.3);
            final sudahColor = isDark
                ? Colors.green.shade400
                : Colors.green.shade700;
            final belumColor = isDark
                ? Colors.orange.shade300
                : Colors.orange.shade800;
            final targetColor = isDark
                ? Colors.red.shade300
                : Colors.red.shade700;
            final totalColor = isDark
                ? Colors.lightBlue.shade300
                : Colors.blue.shade800;

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
                          color: sudahColor,
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
                          color: belumColor,
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
                          color: targetColor,
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
                          color: totalColor,
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
                      color: sudahColor,
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
                      color: belumColor,
                      icon: Icons.pending_actions_outlined,
                    ),
                  ),
                  Container(width: 1, height: 38, color: dividerColor),
                  Expanded(
                    child: _buildSummaryMetric(
                      label: 'Target Pemda',
                      count: targetPemdaCount,
                      nominal: targetPemdaNominal,
                      color: targetColor,
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
                      color: totalColor,
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

/// Tombol aksi Celengan / Tabungan PBB per baris DHKP.
///
/// Baris yang sejak awal berstatus Sudah Bayar tanpa data celengan disembunyikan,
/// sedangkan baris yang memiliki atau dilunasi lewat celengan tetap ditampilkan
/// (ikon hijau saat lunas).
class DhkpRowCelenganButton extends StatelessWidget {
  final BlokRecord record;
  final VoidCallback onPressed;

  const DhkpRowCelenganButton({
    super.key,
    required this.record,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tabungan = PbbTabunganHelper.extractTabungan(
      record.catatan,
      defaultTarget: record.jumlahPbbValue > 0 ? record.jumlahPbbValue : 50000,
    );
    final hasTabungan = tabungan.saldo > 0;
    final isLunas = tabungan.isLunas;
    if (record.isPaid && !hasTabungan) {
      return const SizedBox.shrink();
    }

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        hasTabungan ? Icons.savings_rounded : Icons.savings_outlined,
        color: isLunas
            ? Colors.green.shade700
            : (hasTabungan ? Colors.pink.shade600 : Colors.grey.shade500),
      ),
      tooltip: isLunas
          ? (tabungan.hasKelebihan
                ? 'Celengan Warga: LUNAS (${tabungan.persentase.toStringAsFixed(0)}% • Lebih ${formatRupiah(tabungan.kelebihanSaldo)}${tabungan.kelebihanAlokasi != null ? ' • ${tabungan.kelebihanAlokasi!.label}' : ''})'
                : 'Celengan Warga: LUNAS (${formatRupiah(tabungan.saldo)})')
          : (hasTabungan
                ? 'Celengan Warga: ${formatRupiah(tabungan.saldo)} / ${formatRupiah(tabungan.target)} (${tabungan.persentase.toStringAsFixed(0)}%)'
                : 'Mulai Tabungan / Cicilan PBB Warga'),
    );
  }
}

/// Kondisi progres penyusunan PDF cetak DHKP.
class DhkpPrintProgressState {
  final String message;
  final int current;
  final int total;

  const DhkpPrintProgressState({
    required this.message,
    this.current = 0,
    this.total = 0,
  });

  double? get fraction => total > 0 ? (current / total).clamp(0.0, 1.0) : null;
}

/// Menjalankan pembuatan PDF DHKP di dalam dialog progres dengan tombol
/// "Batal Cetak" agar pengguna dapat membatalkan penyusunan laporan kapan saja
/// sebelum dokumen dikirim ke printer. Mengembalikan `null` jika dibatalkan.
Future<T?> runCancellableDhkpPrint<T>({
  required BuildContext context,
  required BlokPrintCancelToken cancelToken,
  required String title,
  required String initialMessage,
  String? subtitle,
  required Future<T> Function(
    void Function(int current, int total, {String? message}) onProgress,
  )
  task,
}) async {
  final progress = ValueNotifier<DhkpPrintProgressState>(
    DhkpPrintProgressState(message: initialMessage),
  );
  BuildContext? dialogContext;
  var dialogClosed = false;

  void closeDialog() {
    if (dialogClosed) return;
    dialogClosed = true;
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
  }

  void cancelPrint() {
    cancelToken.cancel();
    closeDialog();
  }

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) {
        dialogContext = dCtx;
        if (dialogClosed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (dCtx.mounted && Navigator.of(dCtx).canPop()) {
              Navigator.of(dCtx).pop();
            }
          });
          return const SizedBox.shrink();
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              cancelPrint();
            }
          },
          child: AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.print_rounded,
                  color: Theme.of(dCtx).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
              ],
            ),
            content: ValueListenableBuilder<DhkpPrintProgressState>(
              valueListenable: progress,
              builder: (ctx, state, _) {
                final scheme = Theme.of(ctx).colorScheme;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      state.message,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: state.fraction,
                        minHeight: 6,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            actions: [
              FilledButton.tonalIcon(
                key: const ValueKey('dhkp_cancel_print_btn'),
                onPressed: cancelPrint,
                style: FilledButton.styleFrom(
                  foregroundColor: Theme.of(dCtx).colorScheme.error,
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Batal Cetak'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      dialogClosed = true;
      progress.dispose();
    }),
  );

  try {
    final result = await task((current, total, {String? message}) {
      if (cancelToken.isCancelled || dialogClosed) return;
      progress.value = DhkpPrintProgressState(
        message: message ?? 'Menyusun halaman $current dari $total...',
        current: current,
        total: total,
      );
    });
    closeDialog();
    if (cancelToken.isCancelled) return null;
    return result;
  } on BlokPrintCancelledException {
    closeDialog();
    return null;
  } catch (e) {
    closeDialog();
    rethrow;
  }
}
