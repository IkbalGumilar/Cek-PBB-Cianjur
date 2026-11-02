import 'package:flutter/material.dart';

import '../currency_format.dart';
import '../staff_portal/staff_portal_models.dart';

/// Widget kartu ringkasan metrik (KPI Summary) untuk hasil Monitoring Wilayah:
/// Jumlah OP, Pokok Ketetapan, Pokok Bayar, Denda, dan Total Penerimaan.
/// Otomatis responsif untuk tampilan layar ponsel sempit (HP) maupun tablet/desktop.
class MonitoringSummaryCards extends StatelessWidget {
  final MonitoringSummaryTotals? summary;
  final String? customLabelPokokBayar;
  final String? customLabelTotal;

  const MonitoringSummaryCards({
    super.key,
    required this.summary,
    this.customLabelPokokBayar,
    this.customLabelTotal,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null || s.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final cards = <_KpiCardData>[
      if (s.jumlahOp > 0)
        _KpiCardData(
          title: 'Jumlah OP',
          value: '${formatRibuan(s.jumlahOp)} OP',
          icon: Icons.home_work_outlined,
          color: colorScheme.primary,
          containerColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
        ),
      if (s.pokokKetetapan > 0)
        _KpiCardData(
          title: 'Pokok Ketetapan',
          value: formatRupiah(s.pokokKetetapan),
          icon: Icons.assignment_outlined,
          color: colorScheme.secondary,
          containerColor: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        ),
      if (s.pokokPembayaran > 0)
        _KpiCardData(
          title: customLabelPokokBayar ?? 'Pokok Pembayaran',
          value: formatRupiah(s.pokokPembayaran),
          icon: Icons.payments_outlined,
          color: Colors.green.shade700,
          containerColor: Colors.green.shade50,
        ),
      if (s.denda > 0)
        _KpiCardData(
          title: 'Denda',
          value: formatRupiah(s.denda),
          icon: Icons.warning_amber_rounded,
          color: Colors.orange.shade800,
          containerColor: Colors.orange.shade50,
        ),
      if (s.totalPenerimaan > 0)
        _KpiCardData(
          title: customLabelTotal ?? 'Total Realisasi',
          value: formatRupiah(s.totalPenerimaan),
          icon: Icons.account_balance_wallet_outlined,
          color: colorScheme.tertiary,
          containerColor: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final crossAxisCount = isNarrow ? 2 : (cards.length > 3 ? 4 : cards.length);

        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ringkasan Penerimaan Wilayah',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: isNarrow ? 76 : 84,
                ),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final item = cards[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: item.containerColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: item.color.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(item.icon, size: 20, color: item.color),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.title,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    item.value,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: item.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color containerColor;

  const _KpiCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.containerColor,
  });
}
