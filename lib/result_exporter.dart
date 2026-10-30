import 'base_table_exporter.dart';
import 'tax_record.dart';

class ResultExporter extends BaseTableExporter {
  static Future<String> saveCsv(List<TaxRecord> records) async {
    final bytes = BaseTableExporter.buildCsvData(
      const ['NOP', 'Nama WP', 'Status', 'Tanggal Bayar', 'No. STAN', 'Nominal'],
      [
        for (final r in records)
          [
            r.nop,
            r.namaWajibPajak ?? '-',
            r.status,
            r.tanggalBayar ?? '-',
            r.nomorStan ?? '-',
            r.jumlahPbb ?? '-',
          ]
      ],
    );
    final fileName = BaseTableExporter.formatFileName(
      prefix: 'hasil_cek_pbb',
      format: AppExportFormat.csv,
    );
    return BaseTableExporter.saveExportedBytes(
      bytes: bytes,
      fileName: fileName,
    );
  }
}
