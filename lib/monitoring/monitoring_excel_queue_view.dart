import 'package:flutter/material.dart';

import '../download_helper.dart';
import '../native_file_helper.dart';
import '../staff_portal_client.dart';

/// Tampilan antrean unduhan berkas Excel dari server V-Tax (`loadDataDownloadExcel...`).
/// Menampilkan status berkas (Siap Diunduh atau Sedang Diproses), tautan unduhan langsung,
/// serta fungsi pembatalan/penghapusan antrean server (`svc-monitoring-hapus.php`).
class MonitoringExcelQueueView extends StatefulWidget {
  final StaffPortalClient client;
  final String jsFunctionName;
  final int st;
  final bool isKolektif;
  final String reportTitle;
  final VoidCallback? onTriggerNewExport;

  const MonitoringExcelQueueView({
    super.key,
    required this.client,
    required this.jsFunctionName,
    required this.st,
    this.isKolektif = false,
    required this.reportTitle,
    this.onTriggerNewExport,
  });

  @override
  State<MonitoringExcelQueueView> createState() =>
      _MonitoringExcelQueueViewState();
}

class _MonitoringExcelQueueViewState extends State<MonitoringExcelQueueView> {
  bool _loading = false;
  bool _actionBusy = false;
  String? _downloadingFileName;
  MonitoringExcelQueueResult? _queueResult;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.client.fetchExcelQueue(
        jsFunctionName: widget.jsFunctionName,
        st: widget.st,
      );
      if (mounted) setState(() => _queueResult = res);
    } catch (e) {
      if (mounted) {
        setState(
          () => _queueResult = MonitoringExcelQueueResult(
            errorMessage: 'Gagal memuat antrean Excel: $e',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unduhBerkas(MonitoringExcelQueueItem item) async {
    final fileName = item.fileName;
    if (fileName == null || fileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama berkas tidak ditemukan di server.')),
      );
      return;
    }

    setState(() {
      _actionBusy = true;
      _downloadingFileName = fileName;
    });

    try {
      final bytes = await widget.client.downloadMonitoringExcelFile(fileName);
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted || location == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tersimpan di: $location'),
          action: SnackBarAction(
            label: 'Bagikan',
            onPressed: () => NativeFileHelper.shareBytes(
              bytes: bytes,
              fileName: fileName,
              mimeType: DownloadHelper.mimeTypeFor(fileName),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunduh berkas dari server: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
          _downloadingFileName = null;
        });
      }
    }
  }

  Future<void> _konfirmasiHapus(MonitoringExcelQueueItem item) async {
    final hapusId = item.hapusId;
    if (hapusId == null || hapusId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID antrean tidak ditemukan.')),
      );
      return;
    }

    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Antrean Server?'),
        content: Text(
          'Apakah Anda yakin ingin membatalkan dan menghapus hasil unduh '
          'tanggal ${item.tanggal} dari server V-Tax?\n\n'
          'Tindakan ini aman dan berguna untuk membersihkan proses ekspor yang macet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus dari Server'),
          ),
        ],
      ),
    );

    if (setuju != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      final res = await widget.client.deleteExportQueueItem(
        cpmId: hapusId,
        isKolektif: widget.isKolektif,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
      await _loadQueue();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus antrean: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final res = _queueResult;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Baris tombol aksi antrean
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_download_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Antrean Berkas Excel (${widget.reportTitle})',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loading || _actionBusy ? null : _loadQueue,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Segarkan Antrean',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Server V-Tax memproses ekspor Excel di latar belakang. '
                    'Jika proses selesai, tombol Unduh akan aktif. Jika proses macet, gunakan tombol Hapus.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                  if (widget.onTriggerNewExport != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _actionBusy ? null : widget.onTriggerNewExport,
                      icon: const Icon(Icons.post_add_outlined, size: 18),
                      label: const Text('Buat Permintaan Ekspor Baru ke Server'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Konten antrean
          if (_loading && res == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (res?.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  res!.errorMessage!,
                  style: TextStyle(color: colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (res == null || res.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 48,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Belum ada berkas ekspor dalam antrean server.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: res.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = res.items[index];
                final isDownloadingThis =
                    _downloadingFileName == item.fileName;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: item.isProcessing
                          ? Colors.orange.shade300
                          : Colors.green.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${item.no}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.tanggal,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Status Chip
                            if (item.isProcessing)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Processing...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 14,
                                      color: Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Siap Diunduh',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Filter details
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.filterSummary.isNotEmpty
                                ? item.filterSummary
                                : 'Filter: Semua Data',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Action row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!item.isProcessing && item.fileName != null) ...[
                              FilledButton.icon(
                                onPressed: _actionBusy || isDownloadingThis
                                    ? null
                                    : () => _unduhBerkas(item),
                                icon: isDownloadingThis
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.download_rounded, size: 16),
                                label: Text(isDownloadingThis
                                    ? 'Mengunduh...'
                                    : 'Unduh .xlsx'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (item.hapusId != null)
                              OutlinedButton.icon(
                                onPressed: _actionBusy
                                    ? null
                                    : () => _konfirmasiHapus(item),
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: colorScheme.error,
                                ),
                                label: Text(
                                  'Hapus',
                                  style: TextStyle(color: colorScheme.error),
                                ),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide(
                                    color: colorScheme.error.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          if (res?.paginationText != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  res!.paginationText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
