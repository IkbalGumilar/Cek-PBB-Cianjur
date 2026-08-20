import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'download_helper.dart';
import 'tax_record.dart';

class ResultExporter {
  static Future<String> saveCsv(List<TaxRecord> records) async {
    final rows = <List<String>>[
      ['NOP', 'Status'],
      for (final r in records) [r.nop, r.status],
    ];
    final csvContent = Csv().encode(rows);
    final fileName = 'hasil_cek_pbb_${DateTime.now().millisecondsSinceEpoch}.csv';
    return DownloadHelper.saveBytes(Uint8List.fromList(utf8.encode(csvContent)), fileName);
  }
}
