import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Format ekspor yang didukung secara universal oleh aplikasi (PDF, Excel, CSV).
enum AppExportFormat {
  pdf('PDF', 'pdf'),
  excel('Excel (XLSX)', 'xlsx'),
  csv('CSV', 'csv');

  final String label;
  final String extension;

  const AppExportFormat(this.label, this.extension);
}

/// Kontrak representasi data tabel 2D generik yang dapat diekspor.
abstract class ExportableTable {
  List<String> get headers;
  List<List<String>> get rows;
}

/// Implementasi tabel sederhana dalam memori.
class SimpleExportableTable implements ExportableTable {
  @override
  final List<String> headers;

  @override
  final List<List<String>> rows;

  const SimpleExportableTable({
    required this.headers,
    required this.rows,
  });
}

/// Kelas dasar pengekspor tabel yang mengenkapsulasi logika pembuatan berkas
/// CSV (via [Csv]), Excel (via [Excel]), dan PDF (via [pw.Document]).
///
/// Subclass atau modul pengekspor dapat mewarisi kelas ini untuk menghindari
/// duplikasi konversi biner dan penamaan berkas.
abstract class BaseTableExporter {
  /// Membangun byte CSV dari tabel atau kombinasi headers dan rows.
  static Uint8List buildCsvData(List<String> headers, List<List<String>> rows) {
    final combined = <List<String>>[headers, ...rows];
    return Uint8List.fromList(utf8.encode(Csv().encode(combined)));
  }

  /// Membangun byte Excel (.xlsx) dari headers dan rows.
  static Uint8List buildXlsxData(
    List<String> headers,
    List<List<String>> rows, {
    String? sheetName,
  }) {
    final excel = Excel.createExcel();
    final targetSheet = sheetName ?? excel.getDefaultSheet()!;
    final sheet = excel[targetSheet];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Membangun byte PDF tabel landscape standar.
  static Future<Uint8List> buildPdfData({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    PdfPageFormat? pageFormat,
    double fontSize = 7,
  }) async {
    final effectivePageFormat = pageFormat ?? PdfPageFormat.a4.landscape;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: effectivePageFormat,
        build: (context) => [
          pw.Header(level: 0, text: title),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            cellStyle: pw.TextStyle(fontSize: fontSize),
            headerStyle: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Membangun byte berkas berdasarkan format yang dipilih.
  static Future<Uint8List> buildFormatted({
    required AppExportFormat format,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    switch (format) {
      case AppExportFormat.csv:
        return buildCsvData(headers, rows);
      case AppExportFormat.excel:
        return buildXlsxData(headers, rows);
      case AppExportFormat.pdf:
        return buildPdfData(title: title, headers: headers, rows: rows);
    }
  }

  /// Menghasilkan nama berkas ekspor terstandarisasi dengan timestamp.
  static String formatFileName({
    required String prefix,
    String? identifier,
    required AppExportFormat format,
  }) {
    final slug = (identifier ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final suffix = slug.isEmpty ? '' : '_$slug';
    return '$prefix${suffix}_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
  }
}
