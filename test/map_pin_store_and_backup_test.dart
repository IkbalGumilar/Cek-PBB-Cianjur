import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/map/dhkp_map_screen.dart';
import 'package:cek_pbb_app/map/kml_parser.dart';
import 'package:cek_pbb_app/map/map_models.dart';
import 'package:cek_pbb_app/map/map_pin_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nopA = '320312000400100010';
  const nopB = '320312000400100020';
  const nopC = '320312000400200030';

  const recAOld = BlokRecord(
    nop: nopA,
    namaWajibPajak: 'ASEP SURYANA',
    tahunBayar: '2025',
    tanggalBayar: '2025-08-01 10:00:00',
    jumlahPbb: 'Rp 50.000',
    statusBayar: 'Sudah Bayar',
    alamatObjek: 'KP. BOBOJONG RT 01/01',
    alamatWp: 'KP. BOBOJONG RT 01/01',
  );

  const recALatest = BlokRecord(
    nop: nopA,
    namaWajibPajak: 'ASEP SURYANA',
    tahunBayar: '2026',
    tanggalBayar: '2026-06-15 09:00:00',
    jumlahPbb: 'Rp 55.000',
    statusBayar: 'Sudah Bayar',
    alamatObjek: 'KP. BOBOJONG RT 01/01',
    alamatWp: 'KP. BOBOJONG RT 01/01',
  );

  const recB = BlokRecord(
    nop: nopB,
    namaWajibPajak: 'ASEP SURYANA',
    tahunBayar: '2026',
    tanggalBayar: '',
    jumlahPbb: 'Rp 30.000',
    statusBayar: 'Belum Bayar',
    alamatObjek: 'KP. BOBOJONG RT 01/01',
    alamatWp: 'KP. BOBOJONG RT 01/01',
  );

  const recC = BlokRecord(
    nop: nopC,
    namaWajibPajak: 'SITI AMINAH',
    tahunBayar: '2026',
    tanggalBayar: '',
    jumlahPbb: 'Rp 75.000',
    statusBayar: 'Belum Bayar',
    alamatObjek: 'KP. WARUNG JAMBU',
    alamatWp: 'KP. WARUNG JAMBU',
  );

  late Directory mockPathDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockPathDir = await Directory.systemTemp.createTemp('mock_path_provider_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return mockPathDir.path;
        });
    BlokDataStore.instance.resetForTesting();
    MapPinStore.instance.resetForTesting();
    await MapPinStore.instance.clearAll();
  });

  tearDown(() async {
    await MapPinStore.instance.clearAll();
    MapPinStore.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (mockPathDir.existsSync()) {
      mockPathDir.deleteSync(recursive: true);
    }
  });

  group('MapPinStore multi-NOP & relocation logic', () {
    test('groups multiple NOPs at 1 coordinate and merges on re-tagging', () async {
      const coord1 = MapCoordinate(-6.78900, 107.18500);
      const coord2 = MapCoordinate(-6.79100, 107.18700);

      // 1. Tag NOP A di coord1
      var pins = await MapPinStore.instance.assignNopsAtCoordinate(
        coordinate: coord1,
        selectedRecords: const [recALatest],
        source: 'manual',
        timestampMs: 1000,
      );
      expect(pins.length, 1);

      // 2. Tambah NOP B di koordinat yang sama (coord1) -> harus jadi 1 titik isi 2 NOP
      pins = await MapPinStore.instance.assignNopsAtCoordinate(
        coordinate: coord1,
        selectedRecords: const [recB],
        source: 'gps',
        timestampMs: 2000,
      );
      expect(pins.length, 2);

      final grouped1 = MapPinStore.buildGroupedDots(
        pins: pins,
        dhkpRecords: const [recAOld, recALatest, recB, recC],
      );
      expect(grouped1.length, 1);
      expect(grouped1.first.spptList.length, 2);
      expect(grouped1.first.status, MapDotStatus.sebagian);
      expect(grouped1.first.jumlahPbb, 'Rp 85.000');

      // 3. Tandai ulang NOP A di coord2 -> NOP A pindah ke coord2, NOP B tetap di coord1
      pins = await MapPinStore.instance.assignNopsAtCoordinate(
        coordinate: coord2,
        selectedRecords: const [recALatest],
        source: 'manual',
        timestampMs: 3000,
      );
      final groupedSplit = MapPinStore.buildGroupedDots(
        pins: pins,
        dhkpRecords: const [recAOld, recALatest, recB, recC],
      );
      expect(groupedSplit.length, 2);

      // 4. Tandai ulang NOP B ke coord2 -> menggabungkan NOP A & NOP B di coord2
      pins = await MapPinStore.instance.assignNopsAtCoordinate(
        coordinate: coord2,
        selectedRecords: const [recB],
        source: 'manual',
        timestampMs: 4000,
      );
      final groupedMerged = MapPinStore.buildGroupedDots(
        pins: pins,
        dhkpRecords: const [recAOld, recALatest, recB, recC],
      );
      expect(groupedMerged.length, 1);
      expect(
        MapPinEntry.coordinateKey(
          groupedMerged.first.coordinate.latitude,
          groupedMerged.first.coordinate.longitude,
        ),
        MapPinEntry.coordinateKey(coord2.latitude, coord2.longitude),
      );
      expect(
        groupedMerged.first.spptList.map((e) => e.nop),
        containsAll([nopA, nopB]),
      );
    });

    test(
      'removes a single erroneous NOP without dropping sibling NOPs',
      () async {
        const coord = MapCoordinate(-6.78950, 107.18550);
        await MapPinStore.instance.assignNopsAtCoordinate(
          coordinate: coord,
          selectedRecords: const [recALatest, recB],
          timestampMs: 1000,
        );

        final afterSingleDelete = await MapPinStore.instance.removeNop(nopA);
        expect(afterSingleDelete.length, 1);
        expect(afterSingleDelete.first.nop, nopB);

        final dots = MapPinStore.buildGroupedDots(
          pins: afterSingleDelete,
          dhkpRecords: const [recALatest, recB],
        );
        expect(dots.length, 1);
        expect(dots.first.spptList.length, 1);
        expect(dots.first.nop, nopB);
        expect(dots.first.status, MapDotStatus.belumLunas);

        final afterCoordDelete = await MapPinStore.instance.removeByCoordinate(
          coord,
        );
        expect(afterCoordDelete, isEmpty);
      },
    );

    test('KML export and parse roundtrip preserves grouped multi-NOP dots', () {
      const coord = MapCoordinate(-6.78810, 107.18420);
      final dot = MapPinStore.composeDotFromRecords(
        id: 'pin_test',
        coordinate: coord,
        spptList: const [recALatest, recB],
      );

      final kml = KmlParser.exportToKml(villageName: 'Bobojong', dots: [dot]);
      expect(kml, contains('#dot_sebagian'));
      expect(kml, contains(nopA));
      expect(kml, contains(nopB));

      final parsed = KmlParser.parse(
        kml,
        dhkpRecords: const [recAOld, recALatest, recB],
      );
      expect(parsed.dots.length, 1);
      expect(parsed.dots.first.spptList.length, 2);
      expect(parsed.dots.first.status, MapDotStatus.sebagian);
    });
  });

  group('Backup .dat & .dkhp pin sync', () {
    test(
      'packDkhp embeds map_pins.json & map_pins.kml and unpackDkhp restores them',
      () async {
        const coord = MapCoordinate(-6.78750, 107.18350);
        final initialPins = await MapPinStore.instance.assignNopsAtCoordinate(
          coordinate: coord,
          selectedRecords: const [recALatest, recB],
          source: 'gps',
          timestampMs: 5000,
        );
        expect(initialPins.length, 2);

        final tmpDir = await Directory.systemTemp.createTemp(
          'pin_backup_roundtrip_',
        );
        try {
          final outDat = '${tmpDir.path}/backup_with_pins.dat';
          final packed = await DhkpPackageHelper.packDkhp(
            outputPath: outDat,
            records: const [recALatest, recB, recC],
            encrypt: false,
            includePhotos: false,
          );
          expect(await packed.exists(), isTrue);

          final zip = ZipDecoder().decodeBytes(await packed.readAsBytes());
          final fileNames = zip.files.map((f) => f.name).toSet();
          expect(fileNames, contains('map_pins.json'));
          expect(fileNames, contains('map_pins.kml'));

          // Simulasikan perangkat baru / storage kosong
          await MapPinStore.instance.clearAll();
          MapPinStore.instance.resetForTesting();
          expect(await MapPinStore.instance.loadAll(), isEmpty);

          // Unpack .dat -> harus memulihkan koordinat pin ke MapPinStore
          await DhkpPackageHelper.unpackDkhp(outDat);
          final restored = await MapPinStore.instance.loadAll();
          expect(restored.length, 2);
          expect(restored.map((p) => p.nop), containsAll([nopA, nopB]));

          // Uji proteksi konflik waktu: edit lokal yang lebih baru tidak tertimpa arsip lama
          await MapPinStore.instance.assignNopsAtCoordinate(
            coordinate: const MapCoordinate(-6.79999, 107.19999),
            selectedRecords: const [recALatest],
            source: 'manual',
            timestampMs: 99999,
          );
          await DhkpPackageHelper.unpackDkhp(outDat);
          final afterConflictCheck = await MapPinStore.instance.loadAll();
          final pinA = afterConflictCheck.firstWhere((e) => e.nop == nopA);
          expect(pinA.latitude, closeTo(-6.79999, 0.00001));
        } finally {
          if (tmpDir.existsSync()) {
            tmpDir.deleteSync(recursive: true);
          }
        }
      },
    );
  });

  group('DhkpMapScreen pin UI interactions', () {
    testWidgets(
      'renders GPS & Pin Mode controls and allows adding/removing NOP at pinned coordinate',
      (tester) async {
        // Koordinat berada di area Desa Bobojong agar otomatis masuk viewport
        const coord = MapCoordinate(-6.76360, 107.23880);
        await tester.runAsync(() async {
          await MapPinStore.instance.assignNopsAtCoordinate(
            coordinate: coord,
            selectedRecords: const [recALatest, recB],
            source: 'manual',
            timestampMs: 1000,
          );
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: DhkpMapScreen(
              initialRecords: [recAOld, recALatest, recB, recC],
            ),
          ),
        );
        Future<void> pumpUntilFound(Finder finder, {int maxTries = 30}) async {
          for (var i = 0; i < maxTries; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            if (finder.evaluate().isNotEmpty) return;
          }
        }

        final coordKey = MapPinEntry.coordinateKey(
          coord.latitude,
          coord.longitude,
        );
        final markerFinder = find.byKey(ValueKey('map_dot_pin_$coordKey'));
        await pumpUntilFound(markerFinder);

        // Tombol kontrol GPS, Pasang Pin Manual, dan Menu KML tampil
        expect(
          find.byKey(const ValueKey('btn_gps_field_location')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('btn_toggle_pin_mode')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('btn_kml_menu')), findsOneWidget);

        // Uji toggle mode pasang pin & tombol Batal
        await tester.tap(find.byKey(const ValueKey('btn_toggle_pin_mode')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('Mode Pasang Pin'), findsOneWidget);
        await tester.tap(find.text('Batal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('Mode Pasang Pin'), findsNothing);

        // Pastikan HUD terbaca & ketuk titik marker multi-NOP pada peta
        expect(find.text('TOTAL: 1'), findsOneWidget);
        expect(markerFinder, findsOneWidget);
        await tester.tap(markerFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Daftar 2 NOP pada Koordinat Ini:'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('btn_add_nop_at_dot')),
          findsOneWidget,
        );

        // Tambahkan NOP C (SITI AMINAH) ke koordinat yang sama
        await tester.ensureVisible(
          find.byKey(const ValueKey('btn_add_nop_at_dot')),
        );
        await tester.tap(find.byKey(const ValueKey('btn_add_nop_at_dot')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Tambah NOP ke Titik Peta'), findsOneWidget);
        await tester.tap(find.text('SITI AMINAH'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(find.text('Simpan (1 NOP)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final threeNopFinder = find.text('Daftar 3 NOP pada Koordinat Ini:');
        await pumpUntilFound(threeNopFinder);
        expect(threeNopFinder, findsOneWidget);

        // Hapus 1 NOP yang salah input (ikon hapus pada baris pertama daftar NOP)
        final deleteNopBtn = find
            .byTooltip('Hapus NOP ini dari koordinat')
            .first;
        await tester.ensureVisible(deleteNopBtn);
        await tester.tap(deleteNopBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Hapus NOP dari Titik Ini?'), findsOneWidget);
        await tester.tap(find.text('Hapus NOP'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final twoNopFinder = find.text('Daftar 2 NOP pada Koordinat Ini:');
        await pumpUntilFound(twoNopFinder);
        expect(twoNopFinder, findsOneWidget);
      },
    );
  });
}
