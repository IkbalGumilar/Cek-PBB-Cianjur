import 'package:flutter/material.dart';

import 'result_exporter.dart';
import 'tax_record.dart';

class ResultScreen extends StatelessWidget {
  final List<TaxRecord> records;

  const ResultScreen({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    final total = records.length;
    final sudahBayar = records.where((r) => r.isPaid).length;
    final belumBayar = records
        .where(
          (r) =>
              r.isChecked &&
              !r.isPaid &&
              !r.status.contains('Blacklist') &&
              r.status != 'Dilewati' &&
              !r.status.contains('Gagal'),
        )
        .length;
    final blacklist = records
        .where((r) => r.status.contains('Blacklist'))
        .length;
    final dilewati = records.where((r) => r.status == 'Dilewati').length;
    final gagal = records.where((r) => r.status.contains('Gagal')).length;

    final sudahPct = total > 0
        ? (sudahBayar / total * 100).toStringAsFixed(1)
        : '0';
    final belumPct = total > 0
        ? (belumBayar / total * 100).toStringAsFixed(1)
        : '0';

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Hasil Cek'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Ekspor Hasil (CSV)',
            onPressed: () async {
              try {
                final path = await ResultExporter.saveCsv(records);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Laporan CSV tersimpan: $path'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal mengekspor: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ringkasan Metrics
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Ringkasan Pengecekan',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Total: $total NOP',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: 'Sudah Bayar',
                                  value: sudahBayar,
                                  subLabel: '$sudahPct%',
                                  color: Colors.green,
                                  icon: Icons.check_circle_outline,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: 'Belum Bayar',
                                  value: belumBayar,
                                  subLabel: '$belumPct%',
                                  color: Colors.orange,
                                  icon: Icons.schedule,
                                ),
                              ),
                            ],
                          ),
                          if (blacklist > 0 || gagal > 0 || dilewati > 0) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (blacklist > 0)
                                  Expanded(
                                    child: _MiniStatCard(
                                      label: 'Blacklist',
                                      value: blacklist,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                if (blacklist > 0 &&
                                    (gagal > 0 || dilewati > 0))
                                  const SizedBox(width: 8),
                                if (gagal > 0)
                                  Expanded(
                                    child: _MiniStatCard(
                                      label: 'Gagal Cek',
                                      value: gagal,
                                      color: Colors.red,
                                    ),
                                  ),
                                if (gagal > 0 && dilewati > 0)
                                  const SizedBox(width: 8),
                                if (dilewati > 0)
                                  Expanded(
                                    child: _MiniStatCard(
                                      label: 'Dilewati',
                                      value: dilewati,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Header Rincian
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Rincian Status NOP ($total)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Sudah: $sudahBayar | Belum: $belumBayar',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Daftar NOP
                  Expanded(
                    child: ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final r = records[index];
                        final isPaid = r.isPaid;
                        final isBlacklist = r.status.contains('Blacklist');
                        final isFailed = r.status.contains('Gagal');
                        final isSkipped = r.status == 'Dilewati';

                        final Color statusColor = isPaid
                            ? Colors.green
                            : isBlacklist
                            ? Colors.deepPurple
                            : isFailed
                            ? Colors.red
                            : isSkipped
                            ? Colors.grey
                            : Colors.orange;

                        final IconData statusIcon = isPaid
                            ? Icons.check_circle
                            : isBlacklist
                            ? Icons.block
                            : isFailed
                            ? Icons.error_outline
                            : isSkipped
                            ? Icons.skip_next
                            : Icons.schedule;

                        return Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              statusIcon,
                              color: statusColor,
                              size: 22,
                            ),
                            title: Text(
                              r.nop,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle:
                                (r.namaWajibPajak != null &&
                                        r.namaWajibPajak!.isNotEmpty) ||
                                    (r.tanggalBayar != null &&
                                        r.tanggalBayar!.isNotEmpty)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (r.namaWajibPajak != null &&
                                          r.namaWajibPajak!.isNotEmpty)
                                        Text(
                                          r.namaWajibPajak!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (r.tanggalBayar != null &&
                                          r.tanggalBayar!.isNotEmpty)
                                        Text(
                                          'Tgl Bayar: ${r.tanggalBayar}${r.nomorStan != null && r.nomorStan!.isNotEmpty ? ' • STAN: ${r.nomorStan}' : ''}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  )
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                r.status.isEmpty ? '(Belum Dicek)' : r.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Tombol Selesai
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Selesai',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final String subLabel;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($subLabel)',
                      style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
