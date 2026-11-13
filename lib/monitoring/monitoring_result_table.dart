import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../document_preview_screen.dart';
import '../download_helper.dart';
import '../native_file_helper.dart';
import '../staff_portal_client.dart';
import '../ui/app_design_system.dart';
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
  bool? _forceTableMode;

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
    if (format == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await MonitoringResultExporter.build(
        format,
        result,
        widget.reportTitle,
      );
      final fileName = MonitoringResultExporter.fileName(
        format,
        widget.reportTitle,
      );
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted || location == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tersimpan di $location')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mengunduh: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bagikan(MonitoringTableResult result) async {
    final format = await _pilihFormat('Bagikan Sebagai');
    if (format == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await MonitoringResultExporter.build(
        format,
        result,
        widget.reportTitle,
      );
      final fileName = MonitoringResultExporter.fileName(
        format,
        widget.reportTitle,
      );
      await NativeFileHelper.shareBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: DownloadHelper.mimeTypeFor(fileName),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membagikan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cetak(MonitoringTableResult result) async {
    setState(() => _busy = true);
    try {
      final bytes = await MonitoringResultExporter.build(
        MonitoringExportFormat.pdf,
        result,
        widget.reportTitle,
      );
      if (!mounted) return;
      await DocumentPreviewScreen.printOrPreview(
        context,
        pdfBytes: bytes,
        fileName: '${widget.reportTitle}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menyiapkan cetakan: $e')));
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
        child: AppAlertBanner(
          message: result.errorMessage!,
          tone: AppBadgeTone.error,
        ),
      );
    }
    if (result.rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: AppEmptyStateCard(
          icon: Icons.inbox_outlined,
          title: 'Tidak ada data untuk filter ini.',
          subtitle:
              'Coba ubah rentang tanggal, tahun pajak, atau filter wilayah di atas.',
        ),
      );
    }

    final visibleRows = result.rows.take(_visibleCount).toList();
    final hasMore = _visibleCount < result.rows.length;

    // Normalisasi defensif: pastikan setiap baris punya tepat jumlah sel yang sama dengan header
    // agar DataTable tidak pernah melempar AssertionError pada layout tabel server yang tidak teratur.
    var colCount = result.headers.length;
    if (colCount == 0 && visibleRows.isNotEmpty) {
      colCount = visibleRows.first.length;
    }
    final safeHeaders = result.headers.isNotEmpty
        ? result.headers
        : List.generate(colCount, (i) => i == 0 ? 'No' : 'Kolom ${i + 1}');

    final safeRows = visibleRows.map((row) {
      if (row.length == safeHeaders.length) return row;
      if (row.length < safeHeaders.length) {
        return [...row, ...List.filled(safeHeaders.length - row.length, '')];
      }
      return row.take(safeHeaders.length).toList();
    }).toList();

    final isMobile = AppBreakpoints.isMobileOf(context);
    final useTableMode =
        _forceTableMode ?? (!isMobile || safeHeaders.length <= 3);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          if (!_busy) _cetak(result);
        },
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () {
          if (!_busy) _cetak(result);
        },
      },
      child: Focus(
        autofocus: false,
        child: AppAnimatedReveal(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${result.rows.length} data',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (safeHeaders.length > 3)
                      IconButton(
                        onPressed: () {
                          setState(() => _forceTableMode = !useTableMode);
                        },
                        icon: Icon(
                          useTableMode
                              ? Icons.view_agenda_outlined
                              : Icons.table_rows_outlined,
                        ),
                        tooltip: useTableMode
                            ? 'Tampilkan sebagai Kartu Ringkas'
                            : 'Tampilkan sebagai Tabel Lengkap',
                      ),
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
                      tooltip: 'Cetak (Ctrl+P)',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (useTableMode)
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AppHorizontalTableScroll(
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        columns: [
                          for (final h in safeHeaders)
                            DataColumn(
                              label: Text(
                                h.isEmpty ? '-' : h,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                        rows: [
                          for (final row in safeRows)
                            DataRow(
                              cells: [
                                for (final cell in row) DataCell(Text(cell)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (var rIdx = 0; rIdx < safeRows.length; rIdx++)
                        _MonitoringCompactRowCard(
                          headers: safeHeaders,
                          cells: safeRows[rIdx],
                          index: rIdx,
                        ),
                    ],
                  ),
                if (hasMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _visibleCount += _pageSize),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          'Muat 10 Data Lagi (sisa ${result.rows.length - _visibleCount})',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonitoringCompactRowCard extends StatelessWidget {
  final List<String> headers;
  final List<String> cells;
  final int index;

  const _MonitoringCompactRowCard({
    required this.headers,
    required this.cells,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < headers.length; i++)
              if (cells[i].trim().isNotEmpty) ...[
                if (i > 0) const Divider(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        headers[i].isEmpty ? 'Kolom ${i + 1}' : headers[i],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: SelectableText(
                        cells[i],
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: i <= 2 || i == headers.length - 1
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}
