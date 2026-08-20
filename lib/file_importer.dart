import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'nop_helper.dart';
import 'tax_record.dart';

class FileImporter {
  static Future<List<TaxRecord>> importFrom(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.txt')) {
      return _importTxt(path);
    }
    if (lower.endsWith('.csv')) {
      return _importCsv(path);
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return _importXlsx(path);
    }
    throw UnsupportedError('Format file tidak didukung: $path');
  }

  static Future<List<TaxRecord>> _importTxt(String path) async {
    final content = await File(path).readAsString();
    return importFromText(content);
  }

  static List<TaxRecord> importFromText(String content) {
    final tokens = content.split(RegExp(r'[,\n\r]+'));
    return _toRecords(tokens);
  }

  static Future<List<TaxRecord>> _importCsv(String path) async {
    final content = await File(path).readAsString();
    final rows = Csv().decode(content);
    return _extractNopColumn(rows);
  }

  static Future<List<TaxRecord>> _importXlsx(String path) async {
    final bytes = await File(path).readAsBytes();
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];

    final sheet = workbook.tables[workbook.tables.keys.first]!;
    final rows = sheet.rows
        .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
        .toList();
    return _extractNopColumn(rows);
  }

  static List<TaxRecord> _extractNopColumn(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    var nopColumn = 0;
    var startRow = 0;
    final firstRow = rows.first.map((c) => c.toString().trim().toLowerCase()).toList();
    final headerIndex = firstRow.indexWhere((c) => c == 'nop');
    if (headerIndex != -1) {
      nopColumn = headerIndex;
      startRow = 1;
    }

    final tokens = <String>[];
    for (var i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (nopColumn < row.length) {
        tokens.add(row[nopColumn].toString());
      }
    }
    return _toRecords(tokens);
  }

  static List<TaxRecord> _toRecords(List<String> tokens) {
    final seen = <String>{};
    final records = <TaxRecord>[];
    for (final raw in tokens) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'nan') continue;
      final nop = expandNop(trimmed);
      if (!seen.add(nop)) continue;
      records.add(TaxRecord(nop: nop));
    }
    return records;
  }
}
