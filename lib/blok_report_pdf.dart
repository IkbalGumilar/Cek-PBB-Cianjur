import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'blok_record.dart';
import 'dhkp/blok_catatan_models.dart';
import 'tagihan_result.dart' show formatRupiah;

String _cleanPdfText(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAll('✓', '[Lunas]')
      .replaceAll('🎯', '[Target]')
      .replaceAll('⛔', '[Blacklist]')
      .replaceAll('⏳', '[Belum Bayar]')
      .replaceAll('≥', '>=')
      .replaceAll('≤', '<=')
      .replaceAll('•', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'");
}

class _PdfIsolateParam {
  final SendPort sendPort;
  final List<List<String>> rows;
  final String judul;
  final int totalPbb;
  final int pacingDelayMs;
  final int sudahBayarCount;
  final int sudahBayarNominal;
  final int belumBayarCount;
  final int belumBayarNominal;
  final int targetPemdaCount;
  final int targetPemdaNominal;
  final int totalCount;
  final int totalNominal;

  const _PdfIsolateParam({
    required this.sendPort,
    required this.rows,
    required this.judul,
    required this.totalPbb,
    required this.pacingDelayMs,
    required this.sudahBayarCount,
    required this.sudahBayarNominal,
    required this.belumBayarCount,
    required this.belumBayarNominal,
    required this.targetPemdaCount,
    required this.targetPemdaNominal,
    required this.totalCount,
    required this.totalNominal,
  });
}

void _pdfWorkerEntry(_PdfIsolateParam param) async {
  try {
    final doc = pw.Document();
    const headers = [
      'Blok',
      'No. Wilayah',
      'Nama WP',
      'NOP',
      'Tahun',
      'Tanggal Bayar',
      'Jumlah PBB',
      'Status Bayar',
      'Target Pemda',
      'Catatan',
    ];

    if (param.rows.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                param.judul,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Tidak ada data yang tersedia.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      );
      final bytes = await doc.save();
      param.sendPort.send({'type': 'done', 'bytes': bytes});
      return;
    }

    const rowsPerPage = 28;
    final totalPages = (param.rows.length / rowsPerPage).ceil();

    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final start = pageIdx * rowsPerPage;
      final end = (start + rowsPerPage < param.rows.length)
          ? start + rowsPerPage
          : param.rows.length;
      final pageRows = param.rows.sublist(start, end);
      final isLastPage = (pageIdx == totalPages - 1);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    param.judul,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  pw.Text(
                    'Hal ${pageIdx + 1} dari $totalPages',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: pageRows,
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                headerStyle: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2.5,
                ),
              ),
              if (isLastPage) ...[
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // 1. Sudah Bayar
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Sudah Bayar',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            formatRupiah(param.sudahBayarNominal),
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '${param.sudahBayarCount} NOP (${(param.totalNominal > 0 ? param.sudahBayarNominal / param.totalNominal * 100 : 0).toStringAsFixed(1)}%)',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                      // 2. Kurang Bayar
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Kurang Bayar',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            formatRupiah(param.belumBayarNominal),
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '${param.belumBayarCount} NOP (${(param.totalNominal > 0 ? param.belumBayarNominal / param.totalNominal * 100 : 0).toStringAsFixed(1)}%)',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                      // 3. Target Pemda (Hanya Tampil)
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Target Pemda (Hanya Tampil)',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            formatRupiah(param.targetPemdaNominal),
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                          pw.Text(
                            '${param.targetPemdaCount} NOP (Dipisah)',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                      // 4. Total Keseluruhan (Bayar + Tidak Bayar)
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Total Keseluruhan (Bayar + Kurang)',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            formatRupiah(param.totalNominal),
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '${param.totalCount} NOP (Kewenangan Desa)',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      param.sendPort.send({
        'type': 'progress',
        'current': pageIdx + 1,
        'total': totalPages,
      });

      // Kecepatan diturunkan secara tenang & stabil ("pelan asal selamat")
      if (param.pacingDelayMs > 0 && totalPages > 2) {
        await Future.delayed(Duration(milliseconds: param.pacingDelayMs));
      }
    }

    final bytes = await doc.save();
    param.sendPort.send({'type': 'done', 'bytes': bytes});
  } catch (e) {
    param.sendPort.send({'type': 'error', 'error': e.toString()});
  }
}

List<List<String>> _sanitizeRecordsToRows(List<BlokRecord> records) {
  return [
    for (final r in records)
      [
        r.blok,
        r.wilayah,
        _cleanPdfText(r.namaWajibPajak),
        r.nop,
        r.tahunBayar,
        r.tanggalBayar,
        r.jumlahPbb,
        _cleanPdfText(r.statusBayar),
        r.isTargetPemda ? 'Ya' : '-',
        _cleanPdfText(r.catatan),
      ],
  ];
}

/// Membuat PDF laporan data blok. [records] harus sudah diurutkan sebelum
/// dipanggil (laporan selalu urut blok lalu nomor wilayah menaik).
///
/// Menggunakan seluruh core CPU yang tersedia di perangkat secara paralel
/// serta memproses di background isolate agar antarmuka (UI) bebas dari lag.
class BlokReportPdf {
  static Future<Uint8List> build(
    List<BlokRecord> records, {
    String? tahun,
    String? blokTitle,
    int totalPbb = 0,
    Future<void> Function(int current, int total)? onProgress,
    int pacingDelayMs = 120,
  }) async {
    final blokPart = (blokTitle != null && blokTitle.isNotEmpty)
        ? ' - $blokTitle'
        : '';
    final tahunPart = (tahun == null || tahun.isEmpty)
        ? 'Semua Tahun'
        : 'Tahun $tahun';
    final judul = 'Laporan Data Blok$blokPart ($tahunPart)';
    final effectiveTotalPbb = totalPbb != 0
        ? totalPbb
        : records.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

    if (records.isEmpty) {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                judul,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Tidak ada data yang tersedia.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
      );
      return doc.save();
    }

    // 1. Pra-pemrosesan data secara cepat & aman di memori lokal (bebas dari penangkapan closure UI)
    final allRows = _sanitizeRecordsToRows(records);

    // 2. PENYUSUNAN & KOMPRESI PDF DI BACKGROUND ISOLATE DENGAN JEDA STABIL
    final receivePort = ReceivePort();
    final completer = Completer<Uint8List>();

    receivePort.listen((dynamic message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;
        if (type == 'progress') {
          final cur = message['current'] as int;
          final tot = message['total'] as int;
          if (onProgress != null) {
            onProgress(cur, tot);
          }
        } else if (type == 'done') {
          completer.complete(message['bytes'] as Uint8List);
          receivePort.close();
        } else if (type == 'error') {
          completer.completeError(Exception(message['error']));
          receivePort.close();
        }
      }
    });

    final m = DhkpSummaryMetrics.compute(records);
    final param = _PdfIsolateParam(
      sendPort: receivePort.sendPort,
      rows: allRows,
      judul: judul,
      totalPbb: effectiveTotalPbb,
      pacingDelayMs: pacingDelayMs,
      sudahBayarCount: m.sudahBayarCount,
      sudahBayarNominal: m.sudahBayarNominal,
      belumBayarCount: m.belumBayarCount,
      belumBayarNominal: m.belumBayarNominal,
      targetPemdaCount: m.targetPemdaCount,
      targetPemdaNominal: m.targetPemdaNominal,
      totalCount: m.totalCount,
      totalNominal: m.totalNominal,
    );

    await Isolate.spawn(_pdfWorkerEntry, param);
    return completer.future;
  }
}
