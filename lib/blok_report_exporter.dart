import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'blok_record.dart';
import 'blok_report_pdf.dart';
import 'tagihan_result.dart' show formatRupiah;

enum BlokExportFormat {
  pdf('PDF', 'pdf'),
  excel('Excel (XLSX)', 'xlsx'),
  csv('CSV', 'csv');

  final String label;
  final String extension;

  const BlokExportFormat(this.label, this.extension);
}

const _reportHeader = ['Blok', 'Nomor Wilayah', 'Nama WP', 'NOP', 'Tahun Bayar', 'Tanggal Bayar', 'Jumlah PBB'];

/// Membangun berkas laporan data blok (CSV/Excel/PDF) dari daftar record yang
/// sama — dipakai bareng oleh aksi Unduh, Bagikan, dan Cetak di layar Buku
/// Catatan Blok supaya isi & urutan kolomnya selalu konsisten.
class BlokReportExporter {
  static Future<Uint8List> build(
    BlokExportFormat format,
    List<BlokRecord> records, {
    String? tahun,
  }) async {
    final totalPbb = records.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
    switch (format) {
      case BlokExportFormat.csv:
        return _buildCsv(records, totalPbb);
      case BlokExportFormat.excel:
        return _buildXlsx(records, totalPbb);
      case BlokExportFormat.pdf:
        return BlokReportPdf.build(records, tahun: tahun, totalPbb: totalPbb);
    }
  }

  static Uint8List _buildCsv(List<BlokRecord> records, int totalPbb) {
    final rows = <List<String>>[
      _reportHeader,
      for (final r in records)
        [r.blok, r.wilayah, r.namaWajibPajak, r.nop, r.tahunBayar, r.tanggalBayar, r.jumlahPbb],
      ['', '', '', '', '', 'Total Keseluruhan', formatRupiah(formatRibuan(totalPbb))],
    ];
    return Uint8List.fromList(utf8.encode(Csv().encode(rows)));
  }

  static Uint8List _buildXlsx(List<BlokRecord> records, int totalPbb) {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow(_reportHeader.map(TextCellValue.new).toList());
    for (final r in records) {
      sheet.appendRow([
        TextCellValue(r.blok),
        TextCellValue(r.wilayah),
        TextCellValue(r.namaWajibPajak),
        TextCellValue(r.nop),
        TextCellValue(r.tahunBayar),
        TextCellValue(r.tanggalBayar),
        TextCellValue(r.jumlahPbb),
      ]);
    }
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total Keseluruhan'),
      TextCellValue(formatRupiah(formatRibuan(totalPbb))),
    ]);
    return Uint8List.fromList(excel.encode()!);
  }

  static String fileName(BlokExportFormat format, {String? tahun, String prefix = 'laporan_data_blok'}) {
    final tahunPart = (tahun == null || tahun.isEmpty) ? 'semua_tahun' : tahun;
    return '${prefix}_${tahunPart}_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
  }
}
