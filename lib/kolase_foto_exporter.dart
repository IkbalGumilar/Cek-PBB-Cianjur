import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'image_crop_helper.dart';

/// Pilihan template grid kolase foto dokumentasi penyerahan SPPT.
enum KolaseGridTemplate {
  grid1x2(1, 2, '1x2', '1 Baris, 2 Kolom'),
  grid2x1(2, 1, '2x1', '2 Baris, 1 Kolom'),
  grid2x2(2, 2, '2x2', '2 Baris, 2 Kolom'),
  grid2x3(2, 3, '2x3', '2 Baris, 3 Kolom'),
  grid3x2(3, 2, '3x2', '3 Baris, 2 Kolom'),
  grid3x3(3, 3, '3x3', '3 Baris, 3 Kolom');

  final int rows;
  final int cols;
  final String label;
  final String description;

  const KolaseGridTemplate(this.rows, this.cols, this.label, this.description);

  int get capacity => rows * cols;
}

/// Helper untuk membuat dokumen PDF kolase foto dokumentasi penyerahan SPPT.
///
/// Spesifikasi:
/// 1. Ukuran kertas default adalah F4 / Folio (21.5 x 33.0 cm).
/// 2. Judul HANYA muncul di halaman pertama di bagian paling atas:
///    - Jika Semua / 1 Wilayah: "Foto dokumentasi penyerahan SPPT kepada masyarakat"
///    - Jika Blok Tertentu: "Foto dokumentasi penyerahan SPPT kepada masyarakat - Blok [nomor]"
/// 3. Halaman ke-2, 3, dan seterusnya TIDAK memiliki judul (full kolase foto).
class KolaseFotoExporter {
  /// Ukuran kertas Folio / F4 standar Indonesia (21.5 cm x 33.0 cm).
  static final PdfPageFormat f4PageFormat = PdfPageFormat(
    21.5 * PdfPageFormat.cm,
    33.0 * PdfPageFormat.cm,
    marginLeft: 1.2 * PdfPageFormat.cm,
    marginRight: 1.2 * PdfPageFormat.cm,
    marginTop: 1.2 * PdfPageFormat.cm,
    marginBottom: 1.2 * PdfPageFormat.cm,
  );

  /// Menghasilkan string judul sesuai cakupan wilayah / blok.
  static String formatJudul({String? blok}) {
    final cleanBlok = blok?.trim();
    if (cleanBlok == null ||
        cleanBlok.isEmpty ||
        cleanBlok == 'Semua' ||
        cleanBlok == 'Semua Blok') {
      return 'Foto dokumentasi penyerahan SPPT kepada masyarakat';
    }
    return 'Foto dokumentasi penyerahan SPPT kepada masyarakat - Blok $cleanBlok';
  }

  /// Membuat dokumen PDF kolase dari kumpulan byte gambar.
  static Future<Uint8List> buildPdf({
    required List<Uint8List> imageBytesList,
    required KolaseGridTemplate template,
    String? blok,
    PdfPageFormat? pageFormat,
  }) async {
    final doc = pw.Document();
    final effectiveFormat = pageFormat ?? f4PageFormat;
    final judul = formatJudul(blok: blok);

    if (imageBytesList.isEmpty) {
      // Halaman kosong dengan pesan jika tidak ada gambar
      doc.addPage(
        pw.Page(
          pageFormat: effectiveFormat,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                judul,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text(
                  'Belum ada foto dokumentasi untuk dicetak.',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ),
            ],
          ),
        ),
      );
      return doc.save();
    }

    final capacity = template.capacity;
    final totalPages = (imageBytesList.length / capacity).ceil();

    // Cache MemoryImage untuk efisiensi PDF, pastikan gambar 1:1 persegi
    final pwImages = <pw.MemoryImage>[];
    for (final bytes in imageBytesList) {
      final squareBytes = ImageCropHelper.cropToSquare(bytes);
      pwImages.add(pw.MemoryImage(squareBytes));
    }

    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final startIndex = pageIdx * capacity;
      final endIndex = (startIndex + capacity > pwImages.length)
          ? pwImages.length
          : startIndex + capacity;
      final pageImages = pwImages.sublist(startIndex, endIndex);

      final isFirstPage = pageIdx == 0;

      doc.addPage(
        pw.Page(
          pageFormat: effectiveFormat,
          build: (context) {
            final gridWidget = _buildGrid(
              images: pageImages,
              rows: template.rows,
              cols: template.cols,
            );

            if (isFirstPage) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Text(
                      judul,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(child: gridWidget),
                ],
              );
            }

            // Halaman 2, 3, dst TANPA judul: Full grid foto
            return pw.Expanded(child: gridWidget);
          },
        ),
      );
    }

    return doc.save();
  }

  /// Membuat layout grid dari foto-foto dengan row & column terukur
  static pw.Widget _buildGrid({
    required List<pw.MemoryImage> images,
    required int rows,
    required int cols,
  }) {
    final rowWidgets = <pw.Widget>[];

    for (var r = 0; r < rows; r++) {
      final colWidgets = <pw.Widget>[];
      for (var c = 0; c < cols; c++) {
        final imgIdx = r * cols + c;
        if (imgIdx < images.length) {
          final img = images[imgIdx];
          colWidgets.add(
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.all(3),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                  color: PdfColors.grey100,
                ),
                child: pw.Center(
                  child: pw.AspectRatio(
                    aspectRatio: 1.0,
                    child: pw.Image(
                      img,
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          // Kotak kosong bila foto di halaman terakhir tidak genap
          colWidgets.add(
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.all(3),
              ),
            ),
          );
        }
      }

      rowWidgets.add(
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: colWidgets,
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: rowWidgets,
    );
  }

  /// Memuat file-file foto lokal dari daftar file
  static Future<List<Uint8List>> loadImagesFromFiles(List<File> files) async {
    final list = <Uint8List>[];
    for (final file in files) {
      if (await file.exists()) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            list.add(bytes);
          }
        } catch (_) {}
      }
    }
    return list;
  }
}
