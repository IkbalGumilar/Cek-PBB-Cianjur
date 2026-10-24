import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/download_helper.dart';
import 'package:cek_pbb_app/kolase_foto_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  // Minimal 1x1 transparent PNG bytes
  final samplePngBytes = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
    0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
    13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
  ]);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('kolase_test_');
    AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    AppStorage.resetForTesting();
  });

  group('KolaseGridTemplate', () {
    test('menghitung kapasitas grid sesuai spesifikasi', () {
      expect(KolaseGridTemplate.grid1x2.capacity, 2);
      expect(KolaseGridTemplate.grid2x1.capacity, 2);
      expect(KolaseGridTemplate.grid2x2.capacity, 4);
      expect(KolaseGridTemplate.grid2x3.capacity, 6);
      expect(KolaseGridTemplate.grid3x2.capacity, 6);
      expect(KolaseGridTemplate.grid3x3.capacity, 9);
    });
  });

  group('KolaseFotoExporter - Aturan Judul', () {
    test('judul jika filter Semua Blok menghasilkan judul umum penyerahan SPPT', () {
      expect(
        KolaseFotoExporter.formatJudul(),
        'Foto dokumentasi penyerahan SPPT kepada masyarakat',
      );
      expect(
        KolaseFotoExporter.formatJudul(blok: 'Semua'),
        'Foto dokumentasi penyerahan SPPT kepada masyarakat',
      );
      expect(
        KolaseFotoExporter.formatJudul(blok: 'Semua Blok'),
        'Foto dokumentasi penyerahan SPPT kepada masyarakat',
      );
      expect(
        KolaseFotoExporter.formatJudul(blok: '   '),
        'Foto dokumentasi penyerahan SPPT kepada masyarakat',
      );
    });

    test('judul jika memilih blok tertentu menyertakan nomor blok', () {
      expect(
        KolaseFotoExporter.formatJudul(blok: '001'),
        'Foto dokumentasi penyerahan SPPT kepada masyarakat - Blok 001',
      );
      expect(
        KolaseFotoExporter.formatJudul(blok: '005'),
        'Foto dokumentasi penyerahan SPPT kepada masyarakat - Blok 005',
      );
    });
  });

  group('KolaseFotoExporter - Dokumen PDF F4', () {
    test('buildPdf menghasilkan berkas PDF valid untuk template 3x3 dan kertas F4', () async {
      final images = List.generate(5, (_) => samplePngBytes);

      final pdfBytes = await KolaseFotoExporter.buildPdf(
        imageBytesList: images,
        template: KolaseGridTemplate.grid3x3,
        blok: '002',
        pageFormat: KolaseFotoExporter.f4PageFormat,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
      // PDF header standard %PDF-
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), '%PDF');
    });

    test('buildPdf memecah foto ke beberapa halaman jika melebihi kapasitas template', () async {
      // 10 foto dengan template 2x2 (kapasitas 4) -> 3 halaman
      final images = List.generate(10, (_) => samplePngBytes);

      final pdfBytes = await KolaseFotoExporter.buildPdf(
        imageBytesList: images,
        template: KolaseGridTemplate.grid2x2,
        blok: 'Semua',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), '%PDF');
    });

    test('buildPdf menangani daftar gambar kosong secara aman', () async {
      final pdfBytes = await KolaseFotoExporter.buildPdf(
        imageBytesList: [],
        template: KolaseGridTemplate.grid3x3,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), '%PDF');
    });

    test('simpan ke folder media/files berhasil menggunakan DownloadHelper', () async {
      final images = [samplePngBytes];
      final pdfBytes = await KolaseFotoExporter.buildPdf(
        imageBytesList: images,
        template: KolaseGridTemplate.grid1x2,
        blok: '003',
      );

      final savedPath = await DownloadHelper.saveBytes(
        pdfBytes,
        'Dokumentasi_SPPT_test.pdf',
        subfolder: 'files',
      );

      final savedFile = File(savedPath);
      expect(await savedFile.exists(), true);
      expect(savedPath, contains('files'));
      expect(await savedFile.length(), pdfBytes.length);
    });
  });
}
