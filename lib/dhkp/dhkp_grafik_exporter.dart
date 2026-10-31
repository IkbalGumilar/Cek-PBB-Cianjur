import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../tagihan_result.dart' show formatRupiah;
import 'dhkp_grafik_analytics.dart';

class DhkpGrafikExporter {
  const DhkpGrafikExporter._();

  static String buildSafeFileName(String title, String ext) {
    final clean = title
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return 'Grafik_${clean.isEmpty ? 'DHKP' : clean}.$ext';
  }

  static Future<Uint8List> generateSectionPdf({
    required Uint8List? pngBytes,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
    required DhkpGrafikTab activeTab,
    required bool groupByDusun,
    int? drillDownDusun,
  }) async {
    final doc = pw.Document();

    final scopeLabel = drillDownDusun != null
        ? 'Cakupan: Dusun $drillDownDusun (Per Blok)'
        : (groupByDusun ? 'Cakupan: Semua Dusun' : 'Cakupan: Semua Blok');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '$subtitle • $scopeLabel',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          if (pngBytes != null) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(pngBytes),
                fit: pw.BoxFit.contain,
                height: 220,
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          if (groups.isNotEmpty) ...[
            pw.Text(
              'Ringkasan Tabel Data',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal700,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headers: [
                activeTab == DhkpGrafikTab.trenBulanan ? 'Bulan' : 'Wilayah',
                'Objek Lunas',
                activeTab == DhkpGrafikTab.trenBulanan
                    ? 'Nominal Pembayaran'
                    : 'Sudah Bayar',
                if (activeTab != DhkpGrafikTab.trenBulanan) 'Belum Bayar',
                activeTab == DhkpGrafikTab.trenBulanan
                    ? '% Porsi'
                    : 'Persentase',
              ],
              data: [
                for (final g in groups)
                  activeTab == DhkpGrafikTab.trenBulanan
                      ? [
                          g.label,
                          '${g.lunasNop}',
                          formatRupiah(g.lunasNominal),
                          '${g.lunasPct.toStringAsFixed(1)}%',
                        ]
                      : [
                          g.label,
                          '${g.lunasNop}/${g.totalNop}',
                          formatRupiah(g.lunasNominal),
                          formatRupiah(g.belumBayarNominal),
                          '${g.lunasPct.toStringAsFixed(1)}%',
                        ],
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static Future<String?> showFormatChoiceDialog(
    BuildContext context, {
    required String dialogTitle,
    required String dialogSubtitle,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dialogTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              dialogSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'png'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.image_outlined, color: Colors.teal),
              title: Text(
                'Gambar (PNG)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Tangkapan gambar visual grafik siap kirim'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'pdf'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
              title: Text(
                'Dokumen (PDF)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Dokumen grafik lengkap beserta tabel rincian'),
            ),
          ),
        ],
      ),
    );
  }
}
