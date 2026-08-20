import 'package:flutter/material.dart';

import 'result_exporter.dart';
import 'tax_record.dart';

class ResultScreen extends StatelessWidget {
  final List<TaxRecord> records;

  const ResultScreen({super.key, required this.records});

  Future<void> _saveCsv(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await ResultExporter.saveCsv(records);
      messenger.showSnackBar(
        SnackBar(content: Text('Tersimpan di $location')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sudahBayar = records.where((r) => r.isPaid).length;
    final belumBayar = records.where((r) => r.isChecked && !r.isPaid).length;
    final downloadAttempted = records.where((r) => r.buktiBayarDownloaded != null).length;
    final downloadFailed = records.where((r) => r.buktiBayarDownloaded == false).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Hasil Pengecekan')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Sudah Bayar',
                      value: sudahBayar,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Belum Bayar',
                      value: belumBayar,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              if (downloadAttempted > 0) ...[
                const SizedBox(height: 8),
                Text(
                  downloadFailed == 0
                      ? 'Bukti bayar berhasil diunduh untuk $downloadAttempted NOP.'
                      : 'Bukti bayar diunduh untuk $downloadAttempted NOP, $downloadFailed di antaranya gagal.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: downloadFailed == 0 ? Colors.green : Colors.orange,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = records[index];
                    return ListTile(
                      title: Text(r.nop),
                      subtitle: Text(
                        r.status.isEmpty ? '(belum dicek)' : r.status,
                      ),
                      leading: Icon(
                        r.isPaid ? Icons.check_circle : Icons.error_outline,
                        color: r.isPaid ? Colors.green : Colors.orange,
                      ),
                      trailing: r.buktiBayarDownloaded == null
                          ? null
                          : Icon(
                              r.buktiBayarDownloaded == true
                                  ? Icons.download_done
                                  : Icons.download_for_offline_outlined,
                              color: r.buktiBayarDownloaded == true ? Colors.green : Colors.orange,
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _saveCsv(context),
                icon: const Icon(Icons.download),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Simpan Hasil (CSV)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    );
  }
}
