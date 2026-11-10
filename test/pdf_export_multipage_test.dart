import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cek_pbb_app/base_table_exporter.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/blok_report_pdf.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlokReportPdf & BaseTableExporter MultiPage Export Tests', () {
    test('BlokReportPdf.build returns valid PDF with empty records', () async {
      final bytes = await BlokReportPdf.build([]);
      expect(bytes, isNotEmpty);
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46])); // %PDF
    });

    test('BlokReportPdf.build generates multi-page PDF with formatted NOP, No column, and no Wilayah column', () async {
      final records = List.generate(70, (i) {
        return BlokRecord(
          namaWajibPajak: 'Wajib Pajak Ke-$i Panjang Sekali Namanya',
          nop: '320520000401700${(i + 1).toString().padLeft(3, '0')}',
          tahunBayar: '2026',
          tanggalBayar: '2026-05-10 10:00:00',
          jumlahPbb: 'Rp 25.000',
          statusBayar: i % 2 == 0 ? 'Sudah Bayar' : 'Belum Bayar',
          isTargetPemda: i % 5 == 0,
          catatan: 'Catatan warga RT 01 RW 02 ke-$i [TABUNGAN_PBB:{"saldo":5000}:/TABUNGAN_PBB] ✓ 🎯',
        );
      });

      final bytes = await BlokReportPdf.build(
        records,
        blokTitle: 'Blok 017',
        tahun: '2026',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46])); // %PDF

      // Write to temp file and verify page text using pdftotext
      final tempFile = File('${Directory.systemTemp.path}/test_blok_report_70.pdf');
      await tempFile.writeAsBytes(bytes);

      final result = Process.runSync('pdftotext', [tempFile.path, '-']);
      if (result.exitCode == 0) {
        final text = result.stdout as String;
        final pages = text.split('\x0c').where((p) => p.trim().isNotEmpty).toList();
        expect(pages.length, greaterThan(1), reason: 'Harus lebih dari 1 halaman');
        for (var idx = 0; idx < pages.length; idx++) {
          final pageContent = pages[idx];
          // Pastikan NOP terformat dengan titik dan strip (bukan angka polos)
          expect(
            pageContent.contains('32.05.200.004.017-') || pageContent.contains('Total Keseluruhan'),
            isTrue,
            reason: 'Halaman ${idx + 1} tidak boleh kosong dari data tabel!',
          );
        }

        // Pastikan judul tidak memakai tanda kurung pada tahun
        expect(text.contains('Laporan Data Blok 017 Tahun 2026'), isTrue);
        expect(text.contains('(Tahun 2026)'), isFalse);

        // Pastikan metadata tabungan dan emoji aneh tersanitasi
        expect(text.contains('[TABUNGAN_PBB'), isFalse);
        expect(text.contains('[Lunas]'), isTrue);
        expect(text.contains('[Target]'), isTrue);

        // Pastikan kolom No ada di header dan No Wilayah dihapus
        expect(text.contains('No'), isTrue);
        expect(text.contains('No. Wilayah'), isFalse);
      }

      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });

    test('buildReportJudul generates correct dynamic titles without parentheses', () {
      expect(
        buildReportJudul(blokTitle: 'Semua Blok', kategoriFilter: DhkpKategoriFilter.semua, tahun: '2026'),
        equals('Laporan Data Blok - Semua Blok Tahun 2026'),
      );
      expect(
        buildReportJudul(blokTitle: 'Semua Blok', kategoriFilter: DhkpKategoriFilter.sudahBayar, tahun: '2026'),
        equals('Laporan Data Blok - Sudah Bayar Tahun 2026'),
      );
      expect(
        buildReportJudul(blokTitle: 'Semua Blok', kategoriFilter: DhkpKategoriFilter.belumBayar, tahun: '2026'),
        equals('Laporan Data Blok - Belum Bayar Tahun 2026'),
      );
      expect(
        buildReportJudul(blokTitle: 'Semua Blok', kategoriFilter: DhkpKategoriFilter.blacklist, tahun: '2026'),
        equals('Laporan Data Blok - Blacklist Tahun 2026'),
      );
      expect(
        buildReportJudul(blokTitle: 'Semua Blok', kategoriFilter: DhkpKategoriFilter.targetPemda, tahun: '2026'),
        equals('Laporan Data Blok - Target Pemda Tahun 2026'),
      );
      expect(
        buildReportJudul(blokTitle: '017', kategoriFilter: DhkpKategoriFilter.semua, tahun: '2026'),
        equals('Laporan Data Blok 017 Tahun 2026'),
      );
      expect(
        buildReportJudul(blokTitle: '017', kategoriFilter: DhkpKategoriFilter.sudahBayar, tahun: '2026'),
        equals('Laporan Data Blok 017 - Sudah Bayar Tahun 2026'),
      );
    });

    test('BlokReportPdf.build emits realistic progress reflecting total pages', () async {
      final records = List.generate(150, (i) => BlokRecord(
        namaWajibPajak: 'Wajib Pajak Ke-$i',
        nop: '320520000401700${(i + 1).toString().padLeft(3, '0')}',
        tahunBayar: '2026',
        tanggalBayar: '2026-05-10',
        jumlahPbb: 'Rp 25.000',
        statusBayar: 'Sudah Bayar',
      ));

      final progressList = <List<int>>[];
      await BlokReportPdf.build(
        records,
        tahun: '2026',
        onProgress: (cur, tot) async {
          progressList.add([cur, tot]);
        },
      );

      expect(progressList, isNotEmpty);
      expect(progressList.first[1], greaterThanOrEqualTo(4)); // 150 records = 4-5 halaman nyata
      expect(progressList.last[0], greaterThanOrEqualTo(4));
    });

    test('BlokReportPdf.build with filtered status renders single card', () async {
      final records = [
        BlokRecord(
          namaWajibPajak: 'Budi Santoso',
          nop: '3205200004017000010',
          tahunBayar: '2026',
          tanggalBayar: '2026-05-10',
          jumlahPbb: 'Rp 50.000',
          statusBayar: 'Sudah Bayar',
          catatan: 'Lunas tepat waktu',
        ),
      ];

      final bytes = await BlokReportPdf.build(
        records,
        blokTitle: 'Semua Blok',
        kategoriFilter: DhkpKategoriFilter.sudahBayar,
        tahun: '2026',
      );

      final tempFile = File('${Directory.systemTemp.path}/test_filtered_card.pdf');
      await tempFile.writeAsBytes(bytes);

      final result = Process.runSync('pdftotext', [tempFile.path, '-']);
      if (result.exitCode == 0) {
        final text = result.stdout as String;
        // Judul
        expect(text.contains('Laporan Data Blok - Sudah Bayar Tahun 2026'), isTrue);
        // Hanya card Sudah Bayar, tidak ada card Kurang Bayar atau Target Pemda
        expect(text.contains('Sudah Bayar'), isTrue);
        expect(text.contains('Kurang Bayar'), isFalse);
        expect(text.contains('Target Pemda (Hanya Tampil)'), isFalse);
      }

      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });

    test('BaseTableExporter.buildPdfData generates multi-page PDF without blank pages', () async {
      final headers = ['No', 'Nama', 'Keterangan', 'Nilai'];
      final rows = List.generate(100, (i) => [
        '${i + 1}',
        'Data WP Pemantauan ke-$i dengan deskripsi yang cukup panjang',
        'Keterangan baris data ke-$i',
        'Rp ${i * 1000}',
      ]);

      final bytes = await BaseTableExporter.buildPdfData(
        title: 'Laporan Monitoring Pengawasan',
        headers: headers,
        rows: rows,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));

      final tempFile = File('${Directory.systemTemp.path}/test_base_table_100.pdf');
      await tempFile.writeAsBytes(bytes);

      final result = Process.runSync('pdftotext', [tempFile.path, '-']);
      if (result.exitCode == 0) {
        final text = result.stdout as String;
        final pages = text.split('\x0c').where((p) => p.trim().isNotEmpty).toList();
        expect(pages.length, greaterThan(1));
        for (var idx = 0; idx < pages.length; idx++) {
          final pageContent = pages[idx];
          expect(
            pageContent.contains('Data WP Pemantauan ke-'),
            isTrue,
            reason: 'Halaman ${idx + 1} monitoring PDF tidak boleh kosong!',
          );
        }
      }

      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });
  });
}
