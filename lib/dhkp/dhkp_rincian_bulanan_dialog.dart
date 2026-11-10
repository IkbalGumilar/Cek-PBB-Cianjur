import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../blok_record.dart';
import '../document_preview_screen.dart';
import '../download_helper.dart';
import '../native_file_helper.dart';
import '../nop_helper.dart';
import '../tagihan_result.dart' show formatRupiah;
import 'dhkp_grafik_analytics.dart';

String _cleanPdfText(String text) {
  if (text.isEmpty) return text;
  final replaced = text
      .replaceAll('•', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('…', '...')
      .replaceAll('✓', '[Lunas]')
      .replaceAll('✔', '[Lunas]')
      .replaceAll('🎯', '[Target]')
      .replaceAll('⛔', '[Blacklist]')
      .replaceAll('⏳', '[Belum Bayar]')
      .replaceAll('≥', '>=')
      .replaceAll('≤', '<=')
      .replaceAll('\u00A0', ' ');

  final buffer = StringBuffer();
  for (final rune in replaced.runes) {
    if (rune == 10 || rune == 13 || rune == 9) {
      buffer.writeCharCode(rune);
    } else if ((rune >= 32 && rune <= 126) || (rune >= 160 && rune <= 255)) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

/// Pilihan mode pengurutan data rincian pembayaran bulanan
enum RincianBulananSortMode {
  terlama('Terlama (Awal Bulan)', 'Terlama', Icons.history_rounded),
  terbaru('Terbaru (Akhir Bulan)', 'Terbaru', Icons.update_rounded),
  terbanyak('Nominal Terbanyak', 'Terbanyak', Icons.trending_up_rounded),
  tersedikit('Nominal Tersedikit', 'Tersedikit', Icons.trending_down_rounded),
  nop('Nomor NOP', 'NOP', Icons.pin_outlined),
  nama('Nama WP (A-Z)', 'Nama', Icons.sort_by_alpha_rounded);

  final String label;
  final String shortLabel;
  final IconData icon;
  const RincianBulananSortMode(this.label, this.shortLabel, this.icon);
}

/// Menampilkan modal/dialog interaktif berisi daftar seluruh wajib pajak
/// yang sudah bayar pada bulan tertentu, lengkap dengan tanggal & jam bayar,
/// serta tombol unduh, bagikan, dan cetak langsung.
Future<void> showDhkpRincianBulananDialog(
  BuildContext context, {
  required List<BlokRecord> allRecords,
  required int monthIndex,
  required String tahun,
  required bool isDark,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DhkpRincianBulananSheet(
      allRecords: allRecords,
      monthIndex: monthIndex,
      tahun: tahun,
      isDark: isDark,
    ),
  );
}

class DhkpRincianBulananSheet extends StatefulWidget {
  final List<BlokRecord> allRecords;
  final int monthIndex;
  final String tahun;
  final bool isDark;

  const DhkpRincianBulananSheet({
    super.key,
    required this.allRecords,
    required this.monthIndex,
    required this.tahun,
    required this.isDark,
  });

  @override
  State<DhkpRincianBulananSheet> createState() =>
      _DhkpRincianBulananSheetState();
}

class _DhkpRincianBulananSheetState extends State<DhkpRincianBulananSheet> {
  final TextEditingController _searchController = TextEditingController();
  late List<BlokRecord> _monthRecords;
  String _searchQuery = '';
  RincianBulananSortMode _sortMode = RincianBulananSortMode.terlama;
  bool _isProcessing = false;

  String get _monthName =>
      (widget.monthIndex >= 1 &&
              widget.monthIndex <= DhkpGrafikAnalytics.fullMonthNames.length)
          ? DhkpGrafikAnalytics.fullMonthNames[widget.monthIndex - 1]
          : 'Bulan ${widget.monthIndex}';

  @override
  void initState() {
    super.initState();
    _monthRecords = DhkpGrafikAnalytics.getPaidRecordsForMonth(
      widget.allRecords,
      widget.monthIndex,
      tahun: widget.tahun,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BlokRecord> get _filteredRecords {
    List<BlokRecord> list;
    if (_searchQuery.trim().isEmpty) {
      list = List<BlokRecord>.from(_monthRecords);
    } else {
      final q = _searchQuery.toLowerCase().trim();
      list = _monthRecords.where((r) {
        final name = r.namaWajibPajak.toLowerCase();
        final nop = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
        final blok = nopBlok(r.nop).toLowerCase();
        final alamat = r.alamatObjek.toLowerCase();
        return name.contains(q) ||
            nop.contains(q) ||
            blok.contains(q) ||
            alamat.contains(q);
      }).toList();
    }

    list.sort((a, b) {
      switch (_sortMode) {
        case RincianBulananSortMode.terlama:
          final dtA = DhkpGrafikAnalytics.parsePaymentDate(a.tanggalBayar);
          final dtB = DhkpGrafikAnalytics.parsePaymentDate(b.tanggalBayar);
          if (dtA != null && dtB != null) {
            final cmp = dtA.compareTo(dtB);
            if (cmp != 0) return cmp;
          } else if (dtA != null) {
            return -1;
          } else if (dtB != null) {
            return 1;
          }
          return a.nop.compareTo(b.nop);

        case RincianBulananSortMode.terbaru:
          final dtA = DhkpGrafikAnalytics.parsePaymentDate(a.tanggalBayar);
          final dtB = DhkpGrafikAnalytics.parsePaymentDate(b.tanggalBayar);
          if (dtA != null && dtB != null) {
            final cmp = dtB.compareTo(dtA);
            if (cmp != 0) return cmp;
          } else if (dtA != null) {
            return -1;
          } else if (dtB != null) {
            return 1;
          }
          return a.nop.compareTo(b.nop);

        case RincianBulananSortMode.terbanyak:
          final cmp = b.jumlahPbbValue.compareTo(a.jumlahPbbValue);
          if (cmp != 0) return cmp;
          return a.nop.compareTo(b.nop);

        case RincianBulananSortMode.tersedikit:
          final cmp = a.jumlahPbbValue.compareTo(b.jumlahPbbValue);
          if (cmp != 0) return cmp;
          return a.nop.compareTo(b.nop);

        case RincianBulananSortMode.nop:
          return a.nop.compareTo(b.nop);

        case RincianBulananSortMode.nama:
          final cmp = a.namaWajibPajak
              .toLowerCase()
              .compareTo(b.namaWajibPajak.toLowerCase());
          if (cmp != 0) return cmp;
          return a.nop.compareTo(b.nop);
      }
    });

    return list;
  }

  int get _totalNominal =>
      _monthRecords.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

  Future<Uint8List> _generatePdfBytes() async {
    final doc = pw.Document();
    final targetRecords = _filteredRecords;
    final totalNominal =
        targetRecords.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

    final rows = <List<String>>[];
    for (int i = 0; i < targetRecords.length; i++) {
      final r = targetRecords[i];
      final blok = nopBlok(r.nop);
      final tglJam = DhkpGrafikAnalytics.formatTanggalJamBayar(r.tanggalBayar);
      rows.add([
        '${i + 1}',
        formatNop(r.nop),
        _cleanPdfText(r.namaWajibPajak),
        blok.isNotEmpty ? 'Blok $blok' : '-',
        tglJam,
        formatRupiah(r.jumlahPbbValue),
      ]);
    }

    const headers = [
      'No',
      'NOP',
      'Nama Wajib Pajak',
      'Blok',
      'Tanggal & Jam Bayar',
      'Jumlah PBB',
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'LAPORAN PEMBAYARAN PBB BULAN ${_monthName.toUpperCase()} ${_cleanPdfText(widget.tahun)}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Pemerintah Kabupaten Cianjur | Badan Pendapatan Daerah',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Urutan: ${_cleanPdfText(_sortMode.label)}${_searchQuery.trim().isNotEmpty ? " | Filter: \"${_cleanPdfText(_searchQuery.trim())}\"" : ""}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.purple800,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Hal ${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Total: ${targetRecords.length} Objek Pajak | Total Penerimaan: ${formatRupiah(totalNominal)}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal900,
              ),
            ),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey200,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.center,
              5: pw.Alignment.centerRight,
            },
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 3,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColors.teal50,
              border: pw.Border.all(color: PdfColors.teal200),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL BULAN ${_monthName.toUpperCase()}',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  formatRupiah(totalNominal),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Uint8List _generateCsvBytes() {
    final targetRecords = _filteredRecords;
    final totalNominal =
        targetRecords.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
    final sb = StringBuffer();
    sb.writeln(
      '# LAPORAN PEMBAYARAN PBB BULAN ${_monthName.toUpperCase()} ${widget.tahun}',
    );
    sb.writeln('# Urutan: ${_sortMode.label}');
    if (_searchQuery.trim().isNotEmpty) {
      sb.writeln('# Filter: "${_searchQuery.trim()}"');
    }
    sb.writeln(
      'No,NOP,Nama Wajib Pajak,Blok,Tanggal dan Jam Bayar,Jumlah PBB',
    );
    for (int i = 0; i < targetRecords.length; i++) {
      final r = targetRecords[i];
      final blok = nopBlok(r.nop);
      final tglJam = DhkpGrafikAnalytics.formatTanggalJamBayar(r.tanggalBayar);
      final cleanName = r.namaWajibPajak.replaceAll('"', '""');
      final nop = formatNop(r.nop);
      sb.writeln(
        '${i + 1},"$nop","$cleanName","${blok.isNotEmpty ? 'Blok $blok' : '-'}","$tglJam",${r.jumlahPbbValue}',
      );
    }
    sb.writeln(
      ',,"TOTAL",,,$totalNominal',
    );
    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  Future<void> _handleDownload() async {
    if (_monthRecords.isEmpty) return;
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Format Berkas'),
          content: Text(
            'Unduh laporan pembayaran bulan $_monthName ${widget.tahun} dalam format berkas:',
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('CSV / Excel'),
              onPressed: () => Navigator.pop(ctx, 'csv'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Dokumen PDF'),
              onPressed: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      );

      if (choice == null || !mounted) return;

      final safeMonth = _monthName.toLowerCase();
      final fileName =
          'Laporan_Bayar_${safeMonth}_${widget.tahun}_${DateTime.now().millisecondsSinceEpoch}.$choice';

      final bytes =
          choice == 'pdf' ? await _generatePdfBytes() : _generateCsvBytes();
      final savedPath = await DownloadHelper.saveBytes(
        bytes,
        fileName,
        subfolder: 'documents',
      );
      if (savedPath == null) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('Laporan bulan $_monthName berhasil disimpan di: $savedPath'),
          action: SnackBarAction(
            label: 'Buka',
            onPressed: () => NativeFileHelper.showInFileManager(savedPath),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mengunduh laporan: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleShare() async {
    if (_monthRecords.isEmpty) return;
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdfBytes = await _generatePdfBytes();
      final safeMonth = _monthName.toLowerCase();
      final fileName =
          'Laporan_Bayar_${safeMonth}_${widget.tahun}.pdf';

      if (Platform.isAndroid) {
        await NativeFileHelper.shareBytes(
          bytes: pdfBytes,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
      } else {
        final savedPath = await DownloadHelper.saveBytes(
          pdfBytes,
          fileName,
          subfolder: 'documents',
          useSaveAs: false,
        );
        if (savedPath == null) return;
        await NativeFileHelper.showInFileManager(savedPath);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Dokumen PDF disimpan di: $savedPath'),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal membagikan laporan: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handlePrint() async {
    if (_monthRecords.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      final pdfBytes = await _generatePdfBytes();
      if (!mounted) return;
      final fileName =
          'Laporan_Bayar_${_monthName.toLowerCase()}_${widget.tahun}.pdf';
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: fileName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyiapkan cetak PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filteredRecords;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: widget.isDark ? scheme.surface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Garis handle atas
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header Utama
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rincian Pembayaran Bulan $_monthName ${widget.tahun}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_monthRecords.length} Objek Pajak • Total ${formatRupiah(_totalNominal)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.teal.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Baris Tombol Aksi: Unduh, Bagikan, Cetak
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: const Text(
                          'Unduh',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed:
                            (_monthRecords.isEmpty || _isProcessing)
                                ? null
                                : _handleDownload,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share_rounded, size: 17),
                        label: const Text(
                          'Bagikan',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed:
                            (_monthRecords.isEmpty || _isProcessing)
                                ? null
                                : _handleShare,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.print_rounded, size: 17),
                        label: const Text(
                          'Cetak',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed:
                            (_monthRecords.isEmpty || _isProcessing)
                                ? null
                                : _handlePrint,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Kotak Pencarian Cepat & Pilihan Urutan
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Cari nama WP, NOP, atau Blok...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: widget.isDark
                              ? scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3)
                              : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<RincianBulananSortMode>(
                      tooltip: 'Urutkan rincian',
                      initialValue: _sortMode,
                      onSelected: (mode) {
                        setState(() => _sortMode = mode);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3)
                              : Colors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.purple.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sortMode.icon,
                              size: 18,
                              color: Colors.purple,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sortMode.shortLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: Colors.purple,
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => [
                        for (final mode in RincianBulananSortMode.values)
                          PopupMenuItem<RincianBulananSortMode>(
                            value: mode,
                            child: Row(
                              children: [
                                Icon(
                                  mode.icon,
                                  size: 18,
                                  color: _sortMode == mode
                                      ? Colors.purple
                                      : Colors.grey.shade700,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    mode.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: _sortMode == mode
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _sortMode == mode
                                          ? Colors.purple
                                          : null,
                                    ),
                                  ),
                                ),
                                if (_sortMode == mode)
                                  const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Colors.purple,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 18),

              // Daftar Objek Pajak
              Expanded(
                child: _monthRecords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Belum ada transaksi pembayaran di bulan $_monthName',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Tidak ada data yang cocok dengan pencarian "$_searchQuery"',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (context, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final blok = nopBlok(item.nop);
                              final tglJam =
                                  DhkpGrafikAnalytics.formatTanggalJamBayar(
                                item.tanggalBayar,
                              );

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: widget.isDark
                                      ? scheme.surfaceContainerLow
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: widget.isDark
                                        ? Colors.white12
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Nomor urut
                                    Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.purple
                                            .withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Rincian
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.namaWajibPajak.isNotEmpty
                                                ? item.namaWajibPajak
                                                : 'WP Tanpa Nama',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${blok.isNotEmpty ? 'Blok $blok • ' : ''}NOP: ${formatNop(item.nop)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.access_time_filled_rounded,
                                                size: 13,
                                                color: Colors.blue.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  tglJam,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.blue.shade800,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Nominal
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          formatRupiah(item.jumlahPbbValue),
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Lunas',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
