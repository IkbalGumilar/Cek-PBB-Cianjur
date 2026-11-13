import 'dart:io';

import 'package:flutter/material.dart';

import '../document_preview_screen.dart';
import '../nop_helper.dart';
import '../pbb_client.dart';
import '../qris_result.dart';
import '../qris_view_screen.dart';
import '../tagihan_result.dart';
import '../ui/app_design_system.dart';
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

  Future<void> _previewBuktiBayar(
    BuildContext context, {
    bool directPrint = false,
  }) async {
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
      if (directPrint) {
        await DocumentPreviewScreen.printOrPreview(
          context,
          pdfBytes: bytes,
          fileName: fileName,
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DocumentPreviewScreen(pdfBytes: bytes, fileName: fileName),
          ),
        );
      }
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
    final bgColor = _isPaid
        ? AppSemanticColors.successContainer(context)
        : AppSemanticColors.warningContainer(context);
    final fgColor = _isPaid
        ? AppSemanticColors.onSuccessContainer(context)
        : AppSemanticColors.onWarningContainer(context);
    final borderColor = _isPaid
        ? AppSemanticColors.successBorder(context)
        : AppSemanticColors.warningBorder(context);

    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isPaid
                  ? Icons.check_circle_rounded
                  : Icons.pending_actions_rounded,
              color: fgColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.status,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                ),
              ),
            ),
            if (_isPaid) ...[
              IconButton(
                onPressed: () => _previewBuktiBayar(context, directPrint: true),
                icon: Icon(Icons.print_outlined, color: fgColor),
                tooltip: 'Cetak Bukti Bayar',
              ),
              IconButton(
                onPressed: () => _previewBuktiBayar(context),
                icon: Icon(Icons.visibility, color: fgColor),
                tooltip: 'Detail',
              ),
            ],
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
      await DocumentPreviewScreen.printOrPreview(
        context,
        pdfBytes: bytes,
        fileName: fileName,
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
      final fgColor = AppSemanticColors.onWarningContainer(context);
      return Card(
        color: AppSemanticColors.warningContainer(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppSemanticColors.warningBorder(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: fgColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.serverMessage!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                  ),
                ],
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
      final fgColor = AppSemanticColors.onSuccessContainer(context);
      return Card(
        color: AppSemanticColors.successContainer(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppSemanticColors.successBorder(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: fgColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Data Tidak Ditemukan (tidak ada tunggakan tercatat)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: fgColor,
                  ),
                ),
              ),
            ],
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
            AppHorizontalTableScroll(
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
                          DataCell(
                            Text(
                              r.tahun,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(Text(formatRupiah(r.pbb))),
                          DataCell(Text(formatRupiah(r.denda))),
                          DataCell(
                            Text(
                              formatRupiah(r.kurangBayar),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            r.statusBayar.isEmpty
                                ? const Text('-')
                                : AppStatusBadge(
                                    label: r.statusBayar,
                                    tone:
                                        r.statusBayar.toLowerCase().contains(
                                          'sudah',
                                        )
                                        ? AppBadgeTone.success
                                        : AppBadgeTone.warning,
                                    compact: true,
                                  ),
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
