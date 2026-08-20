import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'blok_record.dart';

/// Membuat PDF laporan data blok. [records] harus sudah diurutkan sebelum
/// dipanggil (laporan selalu urut blok lalu nomor wilayah menaik).
class BlokReportPdf {
  static Future<Uint8List> build(List<BlokRecord> records, {String? tahun}) async {
    final doc = pw.Document();
    final judul = (tahun == null || tahun.isEmpty)
        ? 'Laporan Data Blok - Semua Tahun'
        : 'Laporan Data Blok - Tahun $tahun';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Header(level: 0, text: judul),
          pw.TableHelper.fromTextArray(
            headers: const ['Blok', 'No. Wilayah', 'Nama WP', 'NOP', 'Tahun', 'Tanggal Bayar', 'Jumlah PBB'],
            data: [
              for (final r in records)
                [r.blok, r.wilayah, r.namaWajibPajak, r.nop, r.tahunBayar, r.tanggalBayar, r.jumlahPbb],
            ],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    return doc.save();
  }
}
