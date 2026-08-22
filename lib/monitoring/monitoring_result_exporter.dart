import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../staff_portal_client.dart';

enum MonitoringExportFormat {
  pdf('PDF', 'pdf'),
  excel('Excel (XLSX)', 'xlsx'),
  csv('CSV', 'csv');

  final String label;
  final String extension;

  const MonitoringExportFormat(this.label, this.extension);
}

/// Ekspor hasil tabel generik Monitoring Wilayah (headers+rows apa adanya
/// dari server, beda-beda tiap tab) ke CSV/Excel/PDF — pustaka & polanya
/// sama persis dengan [BlokReportExporter]/[BlokReportPdf] di Buku Catatan
/// Blok, cuma skemanya generik karena kolomnya tidak tetap seperti BlokRecord.
class MonitoringResultExporter {
  static Future<Uint8List> build(
    MonitoringExportFormat format,
    MonitoringTableResult result,
    String title,
  ) async {
    switch (format) {
      case MonitoringExportFormat.csv:
        return _buildCsv(result);
      case MonitoringExportFormat.excel:
        return _buildXlsx(result);
      case MonitoringExportFormat.pdf:
        return _buildPdf(result, title);
    }
  }

  static Uint8List _buildCsv(MonitoringTableResult result) {
    final rows = <List<String>>[result.headers, ...result.rows];
    return Uint8List.fromList(utf8.encode(Csv().encode(rows)));
  }

  static Uint8List _buildXlsx(MonitoringTableResult result) {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow(result.headers.map(TextCellValue.new).toList());
    for (final row in result.rows) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    return Uint8List.fromList(excel.encode()!);
  }

  static Future<Uint8List> _buildPdf(
    MonitoringTableResult result,
    String title,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(level: 0, text: title),
          pw.TableHelper.fromTextArray(
            headers: result.headers,
            data: result.rows,
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// [prefix] memisahkan berkas antar-modul yang sama-sama memakai pengekspor
  /// ini (mis. `monitoring_…` vs `anggota_…`), supaya berkas unduhan tidak
  /// tercampur di folder Dokumen.
  static String fileName(
    MonitoringExportFormat format,
    String title, {
    String prefix = 'monitoring',
  }) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${prefix}_${slug}_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
  }
}
