import 'base_table_exporter.dart';
import 'download_helper.dart';
import 'tax_record.dart';

class ResultExporter extends BaseTableExporter {
  static Future<String> saveCsv(List<TaxRecord> records) async {
    final bytes = BaseTableExporter.buildCsvData(
      const ['NOP', 'Status'],
      [for (final r in records) [r.nop, r.status]],
    );
    final fileName = BaseTableExporter.formatFileName(
      prefix: 'hasil_cek_pbb',
      format: AppExportFormat.csv,
    );
    return DownloadHelper.saveBytes(bytes, fileName);
  }
}
