import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;

import '../base_table_exporter.dart';
import '../dkhp_package_helper.dart';

/// Representasi tabel lembar kerja tunggal dalam memori.
class SpreadsheetTable extends SimpleExportableTable {
  final String sheetName;
  final Map<String, dynamic>? manifest;

  const SpreadsheetTable({
    required this.sheetName,
    required super.headers,
    required super.rows,
    this.manifest,
  });

  int get rowCount => rows.length;
  int get columnCount => headers.length;
}

abstract class BaseSpreadsheetParser {
  static const int maxSafeSizeBytes = 100 * 1024 * 1024;

  void validateFileSize(int bytes) {
    if (bytes > maxSafeSizeBytes) {
      throw const FormatException(
        'Ukuran berkas melebihi batas aman (maksimal 100 MB).',
      );
    }
  }

  Future<List<SpreadsheetTable>> parseFile(File file, {String? password});
}

class ExcelSpreadsheetParser extends BaseSpreadsheetParser {
  @override
  Future<List<SpreadsheetTable>> parseFile(
    File file, {
    String? password,
  }) async {
    final length = await file.length();
    validateFileSize(length);

    final bytes = await file.readAsBytes();
    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw FormatException(
        'Gagal membaca berkas Excel: Format berkas tidak valid atau rusak.',
      );
    }

    if (excel.tables.isEmpty) {
      throw const FormatException(
        'Berkas Excel tidak memiliki lembar kerja (sheet).',
      );
    }

    final tables = <SpreadsheetTable>[];

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;

      final rawSheetRows = <List<String>>[];
      for (final row in sheet.rows) {
        final rowCells = row
            .map((cell) => _formatCellValue(cell?.value))
            .toList();
        if (rowCells.any((cell) => cell.trim().isNotEmpty)) {
          rawSheetRows.add(rowCells);
        }
      }

      if (rawSheetRows.isEmpty) continue;

      final headers = List<String>.from(rawSheetRows.first);
      for (var i = 0; i < headers.length; i++) {
        if (headers[i].trim().isEmpty) {
          headers[i] = 'Kolom ${i + 1}';
        }
      }

      final rows = <List<String>>[];
      for (var rowIndex = 1; rowIndex < rawSheetRows.length; rowIndex++) {
        final row = rawSheetRows[rowIndex];
        final normalizedRow = List<String>.generate(headers.length, (
          columnIndex,
        ) {
          if (columnIndex < row.length) return row[columnIndex];
          return '';
        });
        rows.add(normalizedRow);
      }

      tables.add(
        SpreadsheetTable(sheetName: entry.key, headers: headers, rows: rows),
      );
    }

    if (tables.isEmpty) {
      return [
        const SpreadsheetTable(
          sheetName: 'Sheet Kosong',
          headers: ['Informasi'],
          rows: [
            ['Tidak ada baris data pada berkas ini.'],
          ],
        ),
      ];
    }

    return tables;
  }

  static String _formatCellValue(CellValue? cell) {
    if (cell == null) return '';
    if (cell is TextCellValue) return cell.value.toString();
    if (cell is IntCellValue) return cell.value.toString();
    if (cell is DoubleCellValue) {
      if (cell.value % 1 == 0) {
        return cell.value.toInt().toString();
      }
      return cell.value.toString();
    }
    if (cell is BoolCellValue) return cell.value ? 'YA' : 'TIDAK';
    if (cell is DateCellValue) {
      return '${cell.year.toString().padLeft(4, '0')}-${cell.month.toString().padLeft(2, '0')}-${cell.day.toString().padLeft(2, '0')}';
    }
    if (cell is DateTimeCellValue) {
      return '${cell.year.toString().padLeft(4, '0')}-${cell.month.toString().padLeft(2, '0')}-${cell.day.toString().padLeft(2, '0')} ${cell.hour.toString().padLeft(2, '0')}:${cell.minute.toString().padLeft(2, '0')}';
    }
    if (cell is TimeCellValue) {
      return '${cell.hour.toString().padLeft(2, '0')}:${cell.minute.toString().padLeft(2, '0')}';
    }
    return cell.toString();
  }
}

class CsvSpreadsheetParser extends BaseSpreadsheetParser {
  @override
  Future<List<SpreadsheetTable>> parseFile(
    File file, {
    String? password,
  }) async {
    final length = await file.length();
    validateFileSize(length);

    final bytes = await file.readAsBytes();
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    if (content.trim().isEmpty) {
      throw const FormatException('Berkas CSV kosong.');
    }

    final firstLine = content.split('\n').first;
    final semicolonCount = ';'.allMatches(firstLine).length;
    final commaCount = ','.allMatches(firstLine).length;
    final delimiter = semicolonCount > commaCount ? ';' : ',';
    final rawRows = Csv(fieldDelimiter: delimiter).decode(content);

    if (rawRows.isEmpty) {
      throw const FormatException(
        'Tidak ada data yang dapat dibaca dari berkas CSV.',
      );
    }

    final headers = rawRows.first
        .map((value) => value.toString().trim())
        .toList();
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].isEmpty) {
        headers[i] = 'Kolom ${i + 1}';
      }
    }

    final rows = <List<String>>[];
    for (var rowIndex = 1; rowIndex < rawRows.length; rowIndex++) {
      final row = rawRows[rowIndex];
      if (row.isEmpty ||
          (row.length == 1 && row.first.toString().trim().isEmpty)) {
        continue;
      }
      final normalizedRow = List<String>.generate(headers.length, (
        columnIndex,
      ) {
        if (columnIndex < row.length) {
          return row[columnIndex]?.toString().trim() ?? '';
        }
        return '';
      });
      rows.add(normalizedRow);
    }

    return [
      SpreadsheetTable(sheetName: 'Data CSV', headers: headers, rows: rows),
    ];
  }
}

class DkhpSpreadsheetParser extends BaseSpreadsheetParser {
  @override
  Future<List<SpreadsheetTable>> parseFile(
    File file, {
    String? password,
  }) async {
    final length = await file.length();
    validateFileSize(length);

    final preview = await DhkpPackageHelper.extractPreviewData(
      file.path,
      password: password,
    );

    return [
      SpreadsheetTable(
        sheetName: 'Pratinjau DHKP',
        headers: preview.headers,
        rows: preview.rows,
        manifest: preview.manifest,
      ),
    ];
  }
}

class SpreadsheetParserFactory {
  static BaseSpreadsheetParser parserForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return ExcelSpreadsheetParser();
    }
    if (lower.endsWith('.csv')) {
      return CsvSpreadsheetParser();
    }
    if (lower.endsWith('.dkhp') ||
        lower.endsWith('.dhkp') ||
        lower.endsWith('.dat')) {
      return DkhpSpreadsheetParser();
    }
    return ExcelSpreadsheetParser();
  }
}
