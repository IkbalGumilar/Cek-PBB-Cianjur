import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_excel_queue_view.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';
import 'monitoring_summary_cards.dart';

/// Kerangka bersama untuk 7 tab Monitoring Wilayah: mengelola state loading,
/// error handling seragam, badge wilayah, sub-tab ganda (Tampilan Data vs Berkas Excel),
/// formulir filter yang rapi & responsif (dapat dilipat di layar ponsel/HP),
/// kartu ringkasan metrik (KPI Summary), dan antrean unduhan Excel server.
class MonitoringTabScaffold extends StatefulWidget {
  final String reportTitle;
  final Future<MonitoringTableResult?> Function() onFetch;
  final List<Widget> Function(BuildContext context, bool loading) formBuilder;

  /// Klien portal staf untuk ekspor dan antrean Excel (opsional).
  final StaffPortalClient? client;

  /// Nama fungsi JS pemuat antrean Excel (mis. 'loadDataDownloadExcelSudahBayar').
  final String? excelQueueFunctionName;

  /// Nama fungsi JS pemicu antrean ekspor Excel (mis. 'toExcelSudahBayar').
  final String? toExcelFunctionName;

  /// Nilai parameter `query` untuk ekspor (mis. 'Sudah_Bayar').
  final String? queryName;

  /// Kode status tab (1 atau 2).
  final int st;

  /// Apakah merupakan tab kolektif (memakai svc-monitoring-hapus-kolektif.php).
  final bool isKolektif;

  /// Callback pengambil parameter filter aktif untuk ekspor Excel.
  final Map<String, String> Function()? getExportParams;

  /// Callback ekspor langsung (dipakai tab Rangking Realisasi yang tidak memiliki antrean).
  final Future<void> Function()? onDirectExcelExport;

  const MonitoringTabScaffold({
    super.key,
    required this.reportTitle,
    required this.onFetch,
    required this.formBuilder,
    this.client,
    this.excelQueueFunctionName,
    this.toExcelFunctionName,
    this.queryName,
    this.st = 1,
    this.isKolektif = false,
    this.getExportParams,
    this.onDirectExcelExport,
  });

  @override
  State<MonitoringTabScaffold> createState() => _MonitoringTabScaffoldState();
}

class _MonitoringTabScaffoldState extends State<MonitoringTabScaffold> {
  int _selectedSubTab = 0; // 0: View (Tampilan Data), 1: Excel Server
  bool _loading = false;
  bool _exportLoading = false;
  bool _filterExpanded = true;
  MonitoringTableResult? _result;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final res = await widget.onFetch();
      if (!mounted) return;
      if (res != null) {
        setState(() {
          _result = res;
          // Di layar sempit, jika hasil sudah ada, otomatis lipat filter agar data langsung terlihat
          if (res.rows.isNotEmpty) {
            _filterExpanded = false;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _result = MonitoringTableResult(
          errorMessage: 'Gagal memuat data: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportExcel() async {
    if (widget.onDirectExcelExport != null) {
      await widget.onDirectExcelExport!();
      return;
    }

    if (widget.client == null ||
        widget.toExcelFunctionName == null ||
        widget.queryName == null ||
        widget.getExportParams == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konfigurasi ekspor Excel server belum tersedia.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ekspor ke Excel (Server V-Tax)'),
        content: Text(
          'Server V-Tax akan memproses pembuatan berkas Excel untuk "${widget.reportTitle}" di latar belakang.\n\n'
          'Setelah antrean dibuat, Anda dapat mengunduh berkasnya dari sub-tab "Berkas Excel Server".\n\n'
          'Apakah Anda ingin melanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.file_download_outlined, size: 18),
            onPressed: () => Navigator.pop(ctx, true),
            label: const Text('Buat Antrean Ekspor'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _exportLoading = true);
    try {
      final params = widget.getExportParams!();
      final res = await widget.client!.requestExportExcel(
        jsFunctionName: widget.toExcelFunctionName!,
        query: widget.queryName!,
        params: params,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          action: SnackBarAction(
            label: 'Lihat Antrean',
            onPressed: () {
              if (mounted) setState(() => _selectedSubTab = 1);
            },
          ),
        ),
      );
      // Otomatis pindah ke sub-tab berkas Excel agar staf langsung memantau progresnya
      setState(() => _selectedSubTab = 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal meminta ekspor ke server: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasExcelSubTab = widget.client != null &&
        widget.excelQueueFunctionName != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sub-tab switcher jika tab ini mendukung antrean Excel
          if (hasExcelSubTab) ...[
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Tampilan Data'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.file_copy_outlined, size: 18),
                  label: Text('${widget.reportTitle} Excel'),
                ),
              ],
              selected: {_selectedSubTab},
              onSelectionChanged: (newVal) {
                setState(() => _selectedSubTab = newVal.first);
              },
            ),
            const SizedBox(height: 14),
          ],

          // Jika tab Excel dipilih
          if (_selectedSubTab == 1 && hasExcelSubTab) ...[
            MonitoringExcelQueueView(
              client: widget.client!,
              jsFunctionName: widget.excelQueueFunctionName!,
              st: widget.st,
              isKolektif: widget.isKolektif,
              reportTitle: widget.reportTitle,
              onTriggerNewExport: _exportExcel,
            ),
          ] else ...[
            // Sub-tab Tampilan Data (View)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Filter dengan tombol lipat/buka
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() => _filterExpanded = !_filterExpanded);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Filter & Parameter (${widget.reportTitle})',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            Icon(
                              _filterExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Formulir filter saat dibuka
                    if (_filterExpanded) ...[
                      const Divider(height: 16),
                      const WilayahBadge(),
                      ...widget.formBuilder(context, _loading || _exportLoading),
                      const SizedBox(height: 16),
                    ],

                    // Baris Tombol Aksi (Tampilkan Data & Ekspor ke xls)
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: _loading || _exportLoading ? null : _submit,
                            icon: _loading
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.search, size: 18),
                            label: Text(
                              _loading ? 'Memuat Data...' : 'Tampilkan Data',
                            ),
                          ),
                        ),
                        if (widget.toExcelFunctionName != null ||
                            widget.onDirectExcelExport != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: _loading || _exportLoading
                                  ? null
                                  : _exportExcel,
                              icon: _exportLoading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.file_download_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                _exportLoading ? 'Proses...' : 'Ekspor ke xls',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Kartu Ringkasan Metrik (KPI Cards) jika server mengirim summary
            if (_result?.summary != null)
              MonitoringSummaryCards(summary: _result!.summary),

            // Tabel Hasil Tampilan Data
            MonitoringResultView(
              result: _result,
              loading: _loading,
              reportTitle: widget.reportTitle,
            ),
          ],
        ],
      ),
    );
  }
}
