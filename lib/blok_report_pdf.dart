import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'blok_record.dart';
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

  const _PdfIsolateParam({
    required this.sendPort,
    required this.rows,
    required this.judul,
    required this.totalPbb,
    required this.pacingDelayMs,
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
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Total Keseluruhan: ${formatRupiah(param.totalPbb)} (${param.rows.length} data)',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
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

    final param = _PdfIsolateParam(
      sendPort: receivePort.sendPort,
      rows: allRows,
      judul: judul,
      totalPbb: effectiveTotalPbb,
      pacingDelayMs: pacingDelayMs,
    );

    await Isolate.spawn(_pdfWorkerEntry, param);
    return completer.future;
  }
}
