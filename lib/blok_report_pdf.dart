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
  final withoutTabungan = text
      .replaceAll(
        RegExp(r'\[TABUNGAN_PBB:.*?:\/TABUNGAN_PBB\]', dotAll: true),
        '',
      )
      .trim();
  final replaced = withoutTabungan
      .replaceAll('✓', '[Lunas]')
      .replaceAll('✔', '[Lunas]')
      .replaceAll('🎯', '[Target]')
      .replaceAll('⛔', '[Blacklist]')
      .replaceAll('⏳', '[Belum Bayar]')
      .replaceAll('≥', '>=')
      .replaceAll('≤', '<=')
      .replaceAll('≠', '!=')
      .replaceAll('±', '+/-')
      .replaceAll('•', '-')
      .replaceAll('◦', '-')
      .replaceAll('▪', '-')
      .replaceAll('▫', '-')
      .replaceAll('►', '-')
      .replaceAll('▸', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('…', '...')
      .replaceAll('⭐', '*')
      .replaceAll('❌', '[X]')
      .replaceAll('☑', '[v]')
      .replaceAll('☐', '[ ]')
      .replaceAll('💰', '[Rp]')
      .replaceAll('💳', '[Bayar]')
      .replaceAll('🏠', '[Rumah]')
      .replaceAll('📍', '[Lokasi]')
      .replaceAll('⚠️', '[!]')
      .replaceAll('\u00A0', ' ');

  // Sanitasi karakter agar selalu aman di font WinAnsi (Type 1 Helvetica standar PDF)
  final buffer = StringBuffer();
  for (final rune in replaced.runes) {
    if (rune == 10 || rune == 13 || rune == 9) {
      buffer.writeCharCode(rune);
    } else if ((rune >= 32 && rune <= 126) || (rune >= 160 && rune <= 255)) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

/// Menghasilkan format judul dinamis sesuai filter yang dipilih:
/// - Jika Semua Blok & Semua Data: "Laporan Data Blok - Semua Blok Tahun 2026"
/// - Jika Semua Blok & Sudah Bayar: "Laporan Data Blok - Sudah Bayar Tahun 2026"
/// - Jika Semua Blok & Belum Bayar: "Laporan Data Blok - Belum Bayar Tahun 2026"
/// - Jika Semua Blok & Blacklist: "Laporan Data Blok - Blacklist Tahun 2026"
/// - Jika Semua Blok & Target Pemda: "Laporan Data Blok - Target Pemda Tahun 2026"
/// - Jika Blok tertentu (misal 017) & Sudah Bayar: "Laporan Data Blok 017 - Sudah Bayar Tahun 2026"
/// - Tahun tidak dibungkus tanda kurung, namun tetap dinamis sesuai filter.
String buildReportJudul({
  String? blokTitle,
  DhkpKategoriFilter? kategoriFilter,
  String? tahun,
}) {
  final isSemuaBlok =
      blokTitle == null ||
      blokTitle.isEmpty ||
      blokTitle == 'Semua Blok' ||
      blokTitle == semuaBlokValue;

  String filterLabel = '';
  if (kategoriFilter != null && kategoriFilter != DhkpKategoriFilter.semua) {
    switch (kategoriFilter) {
      case DhkpKategoriFilter.sudahBayar:
        filterLabel = 'Sudah Bayar';
        break;
      case DhkpKategoriFilter.belumBayar:
        filterLabel = 'Belum Bayar';
        break;
      case DhkpKategoriFilter.blacklist:
        filterLabel = 'Blacklist';
        break;
      case DhkpKategoriFilter.targetPemda:
        filterLabel = 'Target Pemda';
        break;
      case DhkpKategoriFilter.semua:
        filterLabel = '';
        break;
    }
  }

  String middlePart = '';
  if (isSemuaBlok) {
    if (filterLabel.isNotEmpty) {
      middlePart = ' - $filterLabel';
    } else {
      middlePart = ' - Semua Blok';
    }
  } else {
    final cleanBlok = blokTitle
        .replaceFirst(RegExp(r'^Blok\s+', caseSensitive: false), '')
        .trim();
    if (filterLabel.isNotEmpty) {
      middlePart = ' $cleanBlok - $filterLabel';
    } else {
      middlePart = ' $cleanBlok';
    }
  }

  final tahunPart = (tahun == null || tahun.trim().isEmpty)
      ? 'Semua Tahun'
      : 'Tahun ${tahun.trim()}';

  return 'Laporan Data Blok$middlePart $tahunPart';
}

class _PdfIsolateParam {
  final SendPort sendPort;
  final List<List<String>> rows;
  final String judul;
  final int totalPbb;
  final int pacingDelayMs;
  final String? kategoriFilter;
  final int sudahBayarCount;
  final int sudahBayarNominal;
  final int belumBayarCount;
  final int belumBayarNominal;
  final int targetPemdaCount;
  final int targetPemdaNominal;
  final int blacklistCount;
  final int blacklistNominal;
  final int totalCount;
  final int totalNominal;

  const _PdfIsolateParam({
    required this.sendPort,
    required this.rows,
    required this.judul,
    required this.totalPbb,
    required this.pacingDelayMs,
    this.kategoriFilter,
    required this.sudahBayarCount,
    required this.sudahBayarNominal,
    required this.belumBayarCount,
    required this.belumBayarNominal,
    required this.targetPemdaCount,
    required this.targetPemdaNominal,
    required this.blacklistCount,
    required this.blacklistNominal,
    required this.totalCount,
    required this.totalNominal,
  });
}

pw.Widget _buildCard({
  required String title,
  required int nominal,
  required String subtitle,
  required PdfColor titleColor,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: titleColor,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        formatRupiah(nominal),
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        subtitle,
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
      ),
    ],
  );
}

pw.Widget _buildSummarySection(_PdfIsolateParam param) {
  final filter = param.kategoriFilter;
  final isFiltered = filter != null && filter.isNotEmpty && filter != 'semua';

  if (!isFiltered) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        color: PdfColors.grey100,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildCard(
            title: 'Sudah Bayar',
            nominal: param.sudahBayarNominal,
            subtitle:
                '${param.sudahBayarCount} NOP (${(param.totalNominal > 0 ? param.sudahBayarNominal / param.totalNominal * 100 : 0).toStringAsFixed(1)}%)',
            titleColor: PdfColors.green800,
          ),
          _buildCard(
            title: 'Kurang Bayar',
            nominal: param.belumBayarNominal,
            subtitle:
                '${param.belumBayarCount} NOP (${(param.totalNominal > 0 ? param.belumBayarNominal / param.totalNominal * 100 : 0).toStringAsFixed(1)}%)',
            titleColor: PdfColors.orange800,
          ),
          _buildCard(
            title: 'Target Pemda (Hanya Tampil)',
            nominal: param.targetPemdaNominal,
            subtitle: '${param.targetPemdaCount} NOP (Dipisah)',
            titleColor: PdfColors.red800,
          ),
          _buildCard(
            title: 'Total Keseluruhan (Bayar + Kurang)',
            nominal: param.totalNominal,
            subtitle: '${param.totalCount} NOP (Kewenangan Desa)',
            titleColor: PdfColors.blue800,
          ),
        ],
      ),
    );
  }

  // Tampilkan HANYA 1 kartu saja, dan posisikan di PALING KANAN (di tempat Total Keseluruhan)
  pw.Widget card;
  if (filter == 'sudahBayar') {
    card = _buildCard(
      title: 'Sudah Bayar',
      nominal: param.sudahBayarNominal,
      subtitle: '${param.sudahBayarCount} NOP',
      titleColor: PdfColors.green800,
    );
  } else if (filter == 'belumBayar') {
    card = _buildCard(
      title: 'Kurang Bayar',
      nominal: param.belumBayarNominal,
      subtitle: '${param.belumBayarCount} NOP',
      titleColor: PdfColors.orange800,
    );
  } else if (filter == 'blacklist') {
    // Sesuai permintaan: blacklist masuknya ke kurang bayar
    final nominal = param.blacklistNominal > 0
        ? param.blacklistNominal
        : param.belumBayarNominal;
    final count = param.blacklistCount > 0
        ? param.blacklistCount
        : param.belumBayarCount;
    card = _buildCard(
      title: 'Kurang Bayar (Blacklist)',
      nominal: nominal,
      subtitle: '$count NOP',
      titleColor: PdfColors.orange800,
    );
  } else if (filter == 'targetPemda') {
    card = _buildCard(
      title: 'Target Pemda (Hanya Tampil)',
      nominal: param.targetPemdaNominal,
      subtitle: '${param.targetPemdaCount} NOP (Dipisah)',
      titleColor: PdfColors.red800,
    );
  } else {
    card = _buildCard(
      title: 'Total Terfilter',
      nominal: param.totalNominal,
      subtitle: '${param.totalCount} NOP',
      titleColor: PdfColors.blue800,
    );
  }

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      color: PdfColors.grey100,
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [card],
    ),
  );
}

void _pdfWorkerEntry(_PdfIsolateParam param) async {
  try {
    final doc = pw.Document();
    const headers = [
      'No',
      'Blok',
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

    final totalHalaman = param.rows.isEmpty
        ? 1
        : (param.rows.length <= 24
              ? 1
              : 1 + ((param.rows.length - 24) / 26).ceil());

    param.sendPort.send({
      'type': 'progress',
      'current': 1,
      'total': totalHalaman,
    });

    doc.addPage(
      pw.MultiPage(
        maxPages: 10000,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        header: (context) => pw.Column(
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
                  'Hal ${context.pageNumber} dari ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: param.rows,
            columnWidths: const {
              0: pw.FixedColumnWidth(26), // No
              1: pw.FixedColumnWidth(28), // Blok (017)
              2: pw.FlexColumnWidth(2.0), // Nama WP
              3: pw.FixedColumnWidth(94), // NOP (32.05.200.004.017-0006.0)
              4: pw.FixedColumnWidth(28), // Tahun (2026)
              5: pw.FixedColumnWidth(54), // Tanggal Bayar
              6: pw.FixedColumnWidth(58), // Jumlah PBB (Rp 51.425)
              7: pw.FixedColumnWidth(
                52,
              ), // Status Bayar (Sudah / Belum / Blacklist)
              8: pw.FixedColumnWidth(36), // Target Pemda (Ya / -)
              9: pw.FlexColumnWidth(3.0), // Catatan
            },
            cellStyle: const pw.TextStyle(fontSize: 6.8),
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.center,
              8: pw.Alignment.center,
              9: pw.Alignment.centerLeft,
            },
            headerAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.center,
              8: pw.Alignment.center,
              9: pw.Alignment.centerLeft,
            },
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 2.5,
              vertical: 2,
            ),
          ),
          pw.SizedBox(height: 10),
          _buildSummarySection(param),
        ],
      ),
    );

    final bytes = await doc.save();
    final actualPages = doc.document.pdfPageList.pages.length;
    final finalPages = actualPages > 0 ? actualPages : totalHalaman;
    param.sendPort.send({
      'type': 'done',
      'bytes': bytes,
      'totalPages': finalPages,
    });
  } catch (e) {
    param.sendPort.send({'type': 'error', 'error': e.toString()});
  }
}

List<List<String>> _sanitizeRecordsToRows(List<BlokRecord> records) {
  return [
    for (var i = 0; i < records.length; i++)
      [
        '${i + 1}',
        records[i].blok,
        _cleanPdfText(records[i].namaWajibPajak),
        records[i].formattedNop,
        records[i].tahunBayar,
        records[i].tanggalBayar,
        records[i].jumlahPbbValue > 0
            ? formatRupiah(records[i].jumlahPbbValue)
            : (records[i].jumlahPbb.isEmpty
                  ? '-'
                  : formatRupiah(records[i].jumlahPbb)),
        _cleanPdfText(records[i].statusBayar),
        records[i].isTargetPemda ? 'Ya' : '-',
        _cleanPdfText(records[i].catatan),
      ],
  ];
}

/// Pengecualian ketika pengguna membatalkan proses pembuatan dokumen cetak DHKP.
class BlokPrintCancelledException implements Exception {
  final String message;
  const BlokPrintCancelledException([
    this.message = 'Proses penyusunan dokumen cetak DHKP dibatalkan.',
  ]);

  @override
  String toString() => message;
}

/// Token pembatalan kooperatif untuk menghentikan isolate pembuatan PDF DHKP
/// seketika jika pengguna menekan Batal Cetak.
class BlokPrintCancelToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final snapshot = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
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
    DhkpKategoriFilter? kategoriFilter,
    String? customJudul,
    int totalPbb = 0,
    Future<void> Function(int current, int total)? onProgress,
    int pacingDelayMs = 120,
    BlokPrintCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw const BlokPrintCancelledException();
    }

    final judul =
        customJudul ??
        buildReportJudul(
          blokTitle: blokTitle,
          kategoriFilter: kategoriFilter,
          tahun: tahun,
        );

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
      if (cancelToken?.isCancelled == true) {
        throw const BlokPrintCancelledException();
      }
      return doc.save();
    }

    // 1. Pra-pemrosesan data secara cepat & aman di memori lokal (bebas dari penangkapan closure UI)
    final allRows = _sanitizeRecordsToRows(records);

    final totalHalaman = records.isEmpty
        ? 1
        : (records.length <= 24 ? 1 : 1 + ((records.length - 24) / 26).ceil());

    Timer? progressTimer;
    var currentHalaman = 1;
    if (onProgress != null) {
      if (cancelToken?.isCancelled == true) {
        throw const BlokPrintCancelledException();
      }
      onProgress(1, totalHalaman);
      if (totalHalaman > 1) {
        final intervalMs = pacingDelayMs.clamp(60, 250);
        progressTimer = Timer.periodic(Duration(milliseconds: intervalMs), (
          timer,
        ) {
          if (cancelToken?.isCancelled == true) {
            timer.cancel();
            return;
          }
          if (currentHalaman < totalHalaman) {
            currentHalaman++;
            onProgress(currentHalaman, totalHalaman);
          } else {
            timer.cancel();
          }
        });
      }
    }

    final receivePort = ReceivePort();
    final completer = Completer<Uint8List>();
    // Hindari unhandled async error jika cancel() dipanggil sebelum `await completer.future`
    // tercapai (misalnya saat `Isolate.spawn` masih dalam antrean).
    completer.future.ignore();
    Isolate? spawnedIsolate;

    void onCancelRequested() {
      progressTimer?.cancel();
      spawnedIsolate?.kill(priority: Isolate.immediate);
      spawnedIsolate = null;
      receivePort.close();
      if (!completer.isCompleted) {
        completer.completeError(const BlokPrintCancelledException());
      }
    }

    cancelToken?.addListener(onCancelRequested);

    receivePort.listen((dynamic message) {
      if (cancelToken?.isCancelled == true) {
        onCancelRequested();
        return;
      }
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;
        if (type == 'progress') {
          final cur = message['current'] as int;
          final tot = message['total'] as int;
          if (onProgress != null &&
              cur > currentHalaman &&
              cancelToken?.isCancelled != true) {
            currentHalaman = cur;
            onProgress(cur, tot);
          }
        } else if (type == 'done') {
          progressTimer?.cancel();
          final finalTotal = message['totalPages'] as int? ?? totalHalaman;
          if (onProgress != null && cancelToken?.isCancelled != true) {
            onProgress(finalTotal, finalTotal);
          }
          if (!completer.isCompleted) {
            completer.complete(message['bytes'] as Uint8List);
          }
          receivePort.close();
        } else if (type == 'error') {
          progressTimer?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(Exception(message['error']));
          }
          receivePort.close();
        }
      }
    });

    final m = DhkpSummaryMetrics.compute(records);
    int blCount = 0;
    int blNom = 0;
    for (final r in records) {
      if (r.isBlacklist) {
        blCount++;
        blNom += r.jumlahPbbValue;
      }
    }

    final param = _PdfIsolateParam(
      sendPort: receivePort.sendPort,
      rows: allRows,
      judul: judul,
      totalPbb: effectiveTotalPbb,
      pacingDelayMs: pacingDelayMs,
      kategoriFilter: kategoriFilter?.name,
      sudahBayarCount: m.sudahBayarCount > 0
          ? m.sudahBayarCount
          : (kategoriFilter == DhkpKategoriFilter.sudahBayar
                ? records.length
                : 0),
      sudahBayarNominal: m.sudahBayarNominal > 0
          ? m.sudahBayarNominal
          : (kategoriFilter == DhkpKategoriFilter.sudahBayar
                ? effectiveTotalPbb
                : 0),
      belumBayarCount: m.belumBayarCount > 0
          ? m.belumBayarCount
          : (kategoriFilter == DhkpKategoriFilter.belumBayar
                ? records.length
                : 0),
      belumBayarNominal: m.belumBayarNominal > 0
          ? m.belumBayarNominal
          : (kategoriFilter == DhkpKategoriFilter.belumBayar
                ? effectiveTotalPbb
                : 0),
      targetPemdaCount: m.targetPemdaCount > 0
          ? m.targetPemdaCount
          : (kategoriFilter == DhkpKategoriFilter.targetPemda
                ? records.length
                : 0),
      targetPemdaNominal: m.targetPemdaNominal > 0
          ? m.targetPemdaNominal
          : (kategoriFilter == DhkpKategoriFilter.targetPemda
                ? effectiveTotalPbb
                : 0),
      blacklistCount: blCount > 0
          ? blCount
          : (kategoriFilter == DhkpKategoriFilter.blacklist
                ? records.length
                : 0),
      blacklistNominal: blNom > 0
          ? blNom
          : (kategoriFilter == DhkpKategoriFilter.blacklist
                ? effectiveTotalPbb
                : 0),
      totalCount: m.totalCount > 0 ? m.totalCount : records.length,
      totalNominal: m.totalNominal > 0 ? m.totalNominal : effectiveTotalPbb,
    );

    try {
      spawnedIsolate = await Isolate.spawn(_pdfWorkerEntry, param);
      if (cancelToken?.isCancelled == true) {
        onCancelRequested();
      }
      return await completer.future;
    } finally {
      progressTimer?.cancel();
      cancelToken?.removeListener(onCancelRequested);
    }
  }
}
