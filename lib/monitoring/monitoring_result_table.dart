import 'package:flutter/material.dart';

import '../document_preview_screen.dart';
import '../download_helper.dart';
import '../native_file_helper.dart';
import '../staff_portal_client.dart';
import 'monitoring_result_exporter.dart';

const _pageSize = 10;

/// Tabel hasil generik dipakai oleh semua tab Monitoring Wilayah — kolomnya
/// dibaca apa adanya dari [MonitoringTableResult.headers]/[rows], lihat
/// catatan di [StaffPortalClient]. [reportTitle] dipakai untuk judul PDF &
/// nama berkas ekspor (mis. "Sudah Bayar").
///
/// Baris ditampilkan 10 dulu (bukan langsung semua) dengan tombol "Muat
/// Lagi" — hasil query bisa ratusan/ribuan baris dan me-render semuanya
/// sekaligus ke [DataTable] terasa berat di HP, beda dari masalah timeout
/// jaringan (itu sudah ditangani lewat receiveTimeout di StaffPortalClient).
class MonitoringResultView extends StatefulWidget {
  final MonitoringTableResult? result;
  final bool loading;
  final String reportTitle;

  const MonitoringResultView({
    super.key,
    required this.result,
    required this.loading,
    required this.reportTitle,
  });

  @override
  State<MonitoringResultView> createState() => _MonitoringResultViewState();
}

class _MonitoringResultViewState extends State<MonitoringResultView> {
  int _visibleCount = _pageSize;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant MonitoringResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) {
      _visibleCount = _pageSize;
    }
  }

  Future<MonitoringExportFormat?> _pilihFormat(String title) {
    return showDialog<MonitoringExportFormat>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final format in MonitoringExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, format),
              child: Text(format.label),
            ),
        ],
      ),
    );
  }

  Future<void> _unduh(MonitoringTableResult result) async {
    final format = await _pilihFormat('Unduh Sebagai');
    if (format == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await MonitoringResultExporter.build(format, result, widget.reportTitle);
      final fileName = MonitoringResultExporter.fileName(format, widget.reportTitle);
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tersimpan di $location')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengunduh: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bagikan(MonitoringTableResult result) async {
    final format = await _pilihFormat('Bagikan Sebagai');
    if (format == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await MonitoringResultExporter.build(format, result, widget.reportTitle);
      final fileName = MonitoringResultExporter.fileName(format, widget.reportTitle);
      await NativeFileHelper.shareBytes(bytes: bytes, fileName: fileName, mimeType: DownloadHelper.mimeTypeFor(fileName));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membagikan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cetak(MonitoringTableResult result) async {
    setState(() => _busy = true);
    try {
      final bytes = await MonitoringResultExporter.build(MonitoringExportFormat.pdf, result, widget.reportTitle);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(pdfBytes: bytes, fileName: '${widget.reportTitle}.pdf'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyiapkan cetakan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final result = widget.result;
    if (result == null) return const SizedBox.shrink();
    if (result.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(result.errorMessage!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (result.rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Tidak ada data untuk filter ini.'),
      );
    }

    final visibleRows = result.rows.take(_visibleCount).toList();
    final hasMore = _visibleCount < result.rows.length;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('${result.rows.length} data', style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                onPressed: _busy ? null : () => _unduh(result),
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Unduh (PDF/Excel/CSV)',
              ),
              IconButton(
                onPressed: _busy ? null : () => _bagikan(result),
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Bagikan (PDF/Excel/CSV)',
              ),
              IconButton(
                onPressed: _busy ? null : () => _cetak(result),
                icon: const Icon(Icons.print_outlined),
                tooltip: 'Cetak',
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [for (final h in result.headers) DataColumn(label: Text(h))],
              rows: [
                for (final row in visibleRows) DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
              ],
            ),
          ),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: OutlinedButton(
                  onPressed: () => setState(() => _visibleCount += _pageSize),
                  child: Text('Muat 10 Data Lagi (sisa ${result.rows.length - _visibleCount})'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
