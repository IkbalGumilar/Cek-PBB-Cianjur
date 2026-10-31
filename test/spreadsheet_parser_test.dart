import 'dart:io';

import 'package:cek_pbb_app/spreadsheet/spreadsheet_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'spreadsheet_parser_test_',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('CSV parser detects semicolon delimiters and normalizes rows', () async {
    final file = File('${tempDirectory.path}/records.csv');
    await file.writeAsString('NOP;Nama;\n001;Warga A\n002;Warga B;extra\n');

    final tables = await CsvSpreadsheetParser().parseFile(file);

    expect(tables, hasLength(1));
    expect(tables.single.sheetName, 'Data CSV');
    expect(tables.single.headers, ['NOP', 'Nama', 'Kolom 3']);
    expect(tables.single.rows, [
      ['001', 'Warga A', ''],
      ['002', 'Warga B', 'extra'],
    ]);
  });

  test('CSV parser rejects empty files', () async {
    final file = File('${tempDirectory.path}/empty.csv');
    await file.writeAsString('');

    await expectLater(
      CsvSpreadsheetParser().parseFile(file),
      throwsA(isA<FormatException>()),
    );
  });
}
