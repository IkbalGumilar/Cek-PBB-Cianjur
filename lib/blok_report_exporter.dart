import 'dart:typed_data';

import 'base_table_exporter.dart';
import 'blok_record.dart';
import 'blok_report_pdf.dart';
import 'tagihan_result.dart' show formatRupiah;

export 'base_table_exporter.dart' show AppExportFormat;

typedef BlokExportFormat = AppExportFormat;

const _reportHeader = [
  'Blok',
  'Nomor Wilayah',
  'Nama WP',
  'NOP',
  'Tahun Bayar',
  'Tanggal Bayar',
  'Jumlah PBB',
  'Status Bayar',
  'Target Pemda',
  'Catatan',
];

/// Membangun berkas laporan data blok (CSV/Excel/PDF) dari daftar record yang
/// sama — mewarisi logika encoding CSV/Excel dan penamaan berkas dari
/// [BaseTableExporter].
class BlokReportExporter extends BaseTableExporter {
  static Future<Uint8List> build(
    BlokExportFormat format,
    List<BlokRecord> records, {
    String? tahun,
  }) async {
    final totalPbb = records.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
    switch (format) {
      case BlokExportFormat.csv:
        return BaseTableExporter.buildCsvData(
          _reportHeader,
          _buildDataRows(records, totalPbb),
        );
      case BlokExportFormat.excel:
        return BaseTableExporter.buildXlsxData(
          _reportHeader,
          _buildDataRows(records, totalPbb),
        );
      case BlokExportFormat.pdf:
        return BlokReportPdf.build(records, tahun: tahun, totalPbb: totalPbb);
    }
  }

  static List<List<String>> _buildDataRows(
    List<BlokRecord> records,
    int totalPbb,
  ) {
    return [
      for (final r in records)
        [
          r.blok,
          r.wilayah,
          r.namaWajibPajak,
          r.nop,
          r.tahunBayar,
          r.tanggalBayar,
          r.jumlahPbb,
          r.statusBayar,
          r.isTargetPemda ? 'Target Pemda' : '-',
          r.catatan,
        ],
      [
        '',
        '',
        '',
        '',
        '',
        '',
        'Total Keseluruhan',
        formatRupiah(totalPbb),
        '',
        '',
      ],
    ];
  }

  static String fileName(
    BlokExportFormat format, {
    String? tahun,
    String prefix = 'laporan_data_blok',
  }) {
    final tahunPart = (tahun == null || tahun.isEmpty) ? 'semua_tahun' : tahun;
    return BaseTableExporter.formatFileName(
      prefix: prefix,
      identifier: tahunPart,
      format: format,
    );
  }
}
