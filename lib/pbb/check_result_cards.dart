import 'dart:io';

import 'package:flutter/material.dart';

import '../document_preview_screen.dart';
import '../nop_helper.dart';
import '../pbb_client.dart';
import '../qris_result.dart';
import '../qris_view_screen.dart';
import '../tagihan_result.dart';
import '../va_result.dart';
import '../va_view_screen.dart';

class StatusBayarResultCard extends StatelessWidget {
  final PbbResult result;
  final String nop;
  final String tahun;
  final PbbClient client;

  const StatusBayarResultCard({
    super.key,
    required this.result,
    required this.nop,
    required this.tahun,
    required this.client,
  });

  bool get _isPaid => result.status.startsWith('Sudah Bayar');

  Future<void> _previewBuktiBayar(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await client.fetchBuktiBayarPdf(nop: nop, tahun: tahun);
      if (!context.mounted) return;
      Navigator.pop(context);
      final fileName =
          'Bukti Bayar (${result.namaWajibPajak ?? nop}) No. (${nopBlok(nop)}) (${nopWilayah(nop)}) ($tahun).pdf';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(pdfBytes: bytes, fileName: fileName),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Gagal'),
          content: Text('Gagal memuat PDF: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _isPaid
          ? Colors.green.withValues(alpha: 0.12)
          : Colors.orange.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                result.status,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isPaid)
              IconButton(
                onPressed: () => _previewBuktiBayar(context),
                icon: const Icon(Icons.visibility),
                tooltip: 'Detail',
              ),
          ],
        ),
      ),
    );
  }
}

class TagihanResultCard extends StatelessWidget {
  final TagihanResult result;
  final String nop;
  final PbbClient client;
  final void Function(String blok, String wilayah, String tahun)?
  onOpenStatusBayar;

  const TagihanResultCard({
    super.key,
    required this.result,
    required this.nop,
    required this.client,
    this.onOpenStatusBayar,
  });

  Future<void> _payWithQris(BuildContext context, String tahun) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'PEMBAYARAN QRIS PBB KABUPATEN CIANJUR',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          '1. Pembayaran QRIS berlaku selama 1 jam\n'
          '2. Pembayaran dapat dilakukan melalui penyedia pembayaran QRIS\n'
          '3. Jika Setuju, dalam 1 jam kedepan pembayaran hanya dapat dilakukan melalui QRIS\n'
          '4. QRIS tersebut hanya berlaku untuk 1 x pembayaran',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setuju'),
          ),
        ],
      ),
    );

    if (agreed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final qris = await client.generateQrisPbb(nop: nop, tahun: tahun);
      if (!context.mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QrisViewScreen(result: qris, nop: nop, tahun: tahun),
        ),
      );
    } on QrisGenerationError catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, 'Gagal generate QRIS: $e');
    }
  }

  Future<void> _payWithVa(BuildContext context, TagihanYearRow row) async {
    final paymentCode = row.paymentCodeVa;
    if (paymentCode == null) {
      _showError(
        context,
        'Pembayaran VA tidak tersedia untuk tahun ${row.tahun}.',
      );
      return;
    }

    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'PEMBAYARAN VIRTUAL ACCOUNT BANK BJB',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          '1. Pembayaran VA berlaku selama 1 jam\n'
          '2. Pembayaran dapat dilakukan melalui penyedia pembayaran VA\n'
          '3. Jika Setuju, dalam 1 jam kedepan pembayaran hanya dapat dilakukan melalui VA\n'
          '4. VA tersebut hanya berlaku untuk 1 x pembayaran',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setuju'),
          ),
        ],
      ),
    );

    if (agreed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final va = await client.generateVaPbb(
        nop: nop,
        tahun: row.tahun,
        paymentCode: paymentCode,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VaViewScreen(
            result: va,
            nop: nop,
            tahun: row.tahun,
            paymentCode: paymentCode,
          ),
        ),
      );
    } on VaGenerationError catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, 'Gagal generate VA: $e');
    }
  }

  Future<void> _previewTagihan(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await client.fetchTagihanPdf(nop: nop);
      if (!context.mounted) return;
      Navigator.pop(context);
      final fileName =
          'Tagihan PBB (${result.namaWajibPajak}) No. (${nopBlok(nop)}) (${nopWilayah(nop)}).pdf';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(pdfBytes: bytes, fileName: fileName),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, 'Gagal memuat PDF: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gagal'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (result.serverMessage != null) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.serverMessage!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (result.inactiveUntilYear != null && onOpenStatusBayar != null)
                TextButton(
                  onPressed: () => onOpenStatusBayar!(
                    nopBlok(nop),
                    nopWilayah(nop),
                    result.inactiveUntilYear!,
                  ),
                  child: Text(
                    '[Cek status bayar tahun ${result.inactiveUntilYear}]',
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (result.notFound) {
      return Card(
        color: Colors.green.withValues(alpha: 0.12),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Data Tidak Ditemukan (tidak ada tunggakan tercatat)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (result.namaWajibPajak.isNotEmpty)
                  Expanded(
                    child: Text(
                      result.namaWajibPajak,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _previewTagihan(context),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Cetak PDF'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                // VA hanya lewat aplikasi bank di HP (butuh channel native
                // Android) — di Windows/Linux pembayaran cuma lewat QRIS.
                columns: [
                  const DataColumn(label: Text('Tahun')),
                  const DataColumn(label: Text('PBB')),
                  const DataColumn(label: Text('Denda')),
                  const DataColumn(label: Text('Kurang Bayar')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('QRIS')),
                  if (Platform.isAndroid) const DataColumn(label: Text('VA')),
                ],
                rows: result.rows
                    .map(
                      (r) => DataRow(
                        cells: [
                          DataCell(Text(r.tahun)),
                          DataCell(Text(formatRupiah(r.pbb))),
                          DataCell(Text(formatRupiah(r.denda))),
                          DataCell(Text(formatRupiah(r.kurangBayar))),
                          DataCell(
                            Text(r.statusBayar.isEmpty ? '-' : r.statusBayar),
                          ),
                          DataCell(
                            FilledButton(
                              onPressed: () => _payWithQris(context, r.tahun),
                              child: const Text('Bayar QRIS'),
                            ),
                          ),
                          if (Platform.isAndroid)
                            DataCell(
                              r.paymentCodeVa == null
                                  ? const Text('-')
                                  : FilledButton(
                                      onPressed: () => _payWithVa(context, r),
                                      child: const Text('Bayar VA'),
                                    ),
                            ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(),
            Text(
              'Total Kurang Bayar: ${result.totalKurangBayar.isEmpty ? '-' : formatRupiah(result.totalKurangBayar)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
