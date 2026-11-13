import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'download_helper.dart';

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

  const SimpleExportableTable({required this.headers, required this.rows});
}

/// Kelas dasar pengekspor tabel yang mengenkapsulasi logika pembuatan berkas
/// CSV (via [Csv]), Excel (via [Excel]), dan PDF (via [pw.Document]).
///
/// Subclass atau modul pengekspor dapat mewarisi kelas ini untuk menghindari
/// duplikasi konversi biner dan penamaan berkas.
abstract class BaseTableExporter {
  static final RegExp _legitimateNegativeNumberPattern = RegExp(
    r'^-\d+(?:[.,]\d+)*$',
  );

  /// Menyanitasi nilai sel ekspor (CSV / XLSX) terhadap serangan Formula Injection
  /// (CSV/Spreadsheet Injection).
  ///
  /// - Mendeteksi karakter awal berbahaya (`=`, `+`, `-`, `@`, `\t`, `\r`, `\n`),
  ///   termasuk apabila didahului oleh spasi di depan.
  /// - Membiarkan angka negatif yang sah (misal `-125000` atau `-12.500,00`) tetap utuh.
  /// - Menambahkan prefix tanda kutip tunggal (`'`) pada nilai yang mencurigakan.
  static String sanitizeSpreadsheetCell(String value) {
    if (value.isEmpty) return value;

    final firstChar = value[0];
    final startsWithControl =
        firstChar == '\t' || firstChar == '\r' || firstChar == '\n';

    final trimmedLeft = value.trimLeft();
    if (trimmedLeft.isEmpty) return value;

    final leadingTrigger = trimmedLeft[0];
    final isFormulaTrigger =
        startsWithControl ||
        leadingTrigger == '=' ||
        leadingTrigger == '+' ||
        leadingTrigger == '-' ||
        leadingTrigger == '@' ||
        leadingTrigger == '\t' ||
        leadingTrigger == '\r' ||
        leadingTrigger == '\n';

    if (!isFormulaTrigger) return value;

    // Izinkan angka negatif murni yang sah (tanpa operator/karakter formula tambahan)
    if (!startsWithControl &&
        leadingTrigger == '-' &&
        _legitimateNegativeNumberPattern.hasMatch(trimmedLeft.trimRight())) {
      return value;
    }

    return "'$value";
  }

  /// Membangun byte CSV dari tabel atau kombinasi headers dan rows (dengan sanitasi formula injection).
  static Uint8List buildCsvData(List<String> headers, List<List<String>> rows) {
    final sanitizedHeaders = headers.map(sanitizeSpreadsheetCell).toList();
    final sanitizedRows = rows
        .map((r) => r.map(sanitizeSpreadsheetCell).toList())
        .toList();
    final combined = <List<String>>[sanitizedHeaders, ...sanitizedRows];
    return Uint8List.fromList(utf8.encode(Csv().encode(combined)));
  }

  /// Membangun byte Excel (.xlsx) dari headers dan rows (dengan sanitasi formula injection).
  static Uint8List buildXlsxData(
    List<String> headers,
    List<List<String>> rows, {
    String? sheetName,
  }) {
    final excel = Excel.createExcel();
    final targetSheet = sheetName ?? excel.getDefaultSheet()!;
    final sheet = excel[targetSheet];
    sheet.appendRow(
      headers.map((h) => TextCellValue(sanitizeSpreadsheetCell(h))).toList(),
    );
    for (final row in rows) {
      sheet.appendRow(
        row
            .map((cell) => TextCellValue(sanitizeSpreadsheetCell(cell)))
            .toList(),
      );
    }
    return Uint8List.fromList(excel.encode()!);
  }

  static String _cleanPdfText(String text) {
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

  /// Membangun byte PDF tabel landscape standar.
  static Future<Uint8List> buildPdfData({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    PdfPageFormat? pageFormat,
    double fontSize = 7,
    int rowsPerPage = 28,
  }) async {
    final effectivePageFormat = pageFormat ?? PdfPageFormat.a4.landscape;
    final doc = pw.Document();
    final cleanTitle = _cleanPdfText(title);
    final cleanHeaders = headers.map(_cleanPdfText).toList();
    final cleanRows = rows.map((r) => r.map(_cleanPdfText).toList()).toList();

    if (cleanRows.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: effectivePageFormat,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                cleanTitle,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Tidak ada data.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      );
      return doc.save();
    }

    doc.addPage(
      pw.MultiPage(
        maxPages: 10000,
        pageFormat: effectivePageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  cleanTitle,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Hal ${context.pageNumber} dari ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: cleanHeaders,
            data: cleanRows,
            cellStyle: pw.TextStyle(fontSize: fontSize),
            headerStyle: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 2,
            ),
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

  /// Simpan byte berkas hasil ekspor ke penyimpanan publik / dokumen (Save As).
  static Future<String?> saveExportedBytes({
    required Uint8List bytes,
    required String fileName,
    String? subfolder,
    String? dialogTitle,
    bool useSaveAs = true,
  }) => DownloadHelper.saveBytes(
    bytes,
    fileName,
    subfolder: subfolder,
    dialogTitle: dialogTitle,
    useSaveAs: useSaveAs,
  );
}
