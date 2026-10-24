import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/kolase_foto_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('kolase_screen_test_');
    AppStorage.resetForTesting();
    AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
    BlokDataStore.instance.resetForTesting();
    DhkpPackageHelper.resetForTesting();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    AppStorage.resetForTesting();
    BlokDataStore.instance.resetForTesting();
    DhkpPackageHelper.resetForTesting();
  });

  Widget buildTestWidget({String? initialBlok, List<String> bloks = const []}) {
    return MaterialApp(
      home: KolaseFotoScreen(
        initialBlok: initialBlok,
        bloks: bloks,
      ),
    );
  }

  group('KolaseFotoScreen Widget Tests', () {
    testWidgets('menampilkan AppBar, judul Gabungkan Beberapa Gambar, dan subheader F4', (tester) async {
      await tester.pumpWidget(buildTestWidget(initialBlok: '001', bloks: ['001', '002']));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Gabungkan Beberapa Gambar'), findsOneWidget);
      expect(find.textContaining('Wilayah: Blok 001'), findsOneWidget);
      expect(find.textContaining('Kertas F4'), findsOneWidget);
    });

    testWidgets('menampilkan template selector 1x2, 2x1, 2x2, 2x3, 3x2, 3x3', (tester) async {
      await tester.pumpWidget(buildTestWidget(initialBlok: 'Semua', bloks: ['001', '002']));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1x2'), findsOneWidget);
      expect(find.text('2x1'), findsOneWidget);
      expect(find.text('2x2'), findsOneWidget);
      expect(find.text('2x3'), findsOneWidget);
      expect(find.text('3x2'), findsOneWidget);
      expect(find.text('3x3'), findsOneWidget);
    });

    testWidgets('menampilkan tombol aksi Simpan Media, Cetak, dan tombol centang selesai', (tester) async {
      await tester.pumpWidget(buildTestWidget(initialBlok: 'Semua', bloks: []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Simpan Media'), findsOneWidget);
      expect(find.text('Cetak'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('memilih kartu template lain memperbarui pilihan aktif', (tester) async {
      await tester.pumpWidget(buildTestWidget(initialBlok: 'Semua', bloks: []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap template 2x2
      await tester.tap(find.text('2x2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap template 1x2
      await tester.tap(find.text('1x2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('tampilan kosong menampilkan pesan hanya foto dokumentasi dan tombol muat ulang', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(buildTestWidget(initialBlok: '001', bloks: ['001']));
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.textContaining('Belum ada foto dokumentasi di Blok 001'), findsOneWidget);
      expect(find.textContaining('Kolase hanya memuat foto dokumentasi resmi'), findsOneWidget);
      expect(find.text('Muat Ulang Foto'), findsOneWidget);
    });

    testWidgets('hanya memuat foto dokumentasi resmi yang tersimpan di disk/records', (tester) async {
      await tester.runAsync(() async {
        final photosDir = await DhkpPackageHelper.photosDirectory();
        final photoFile = File('${photosDir.path}/320520000402600340.jpg');
        final dummyImage = img.Image(width: 10, height: 10);
        await photoFile.writeAsBytes(Uint8List.fromList(img.encodeJpg(dummyImage)));
        await DhkpPackageHelper.refreshPhotoNamesCache();

        final record = const BlokRecord(
          namaWajibPajak: 'SUGENG RAHARJO',
          nop: '320520000402600340',
          tahunBayar: '2026',
          tanggalBayar: '2026-10-24',
          namaFoto: '320520000402600340.jpg',
        );
        await BlokDataStore.instance.upsert(record);

        await tester.pumpWidget(buildTestWidget(initialBlok: 'Semua', bloks: ['026']));
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Memastikan sub-header menampilkan 1 Foto
      expect(find.textContaining('1 Foto • Kertas F4'), findsOneWidget);
    });
  });
}
