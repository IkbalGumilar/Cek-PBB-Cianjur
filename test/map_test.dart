import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dusun_data.dart';
import 'package:cek_pbb_app/map/dhkp_map_screen.dart';
import 'package:cek_pbb_app/map/kml_parser.dart';
import 'package:cek_pbb_app/map/map_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Map Models & KML Parser Tests', () {
    test('MapCoordinate and MapBounds calculate properly', () {
      const c1 = MapCoordinate(-6.772, 107.165);
      const c2 = MapCoordinate(-6.774, 107.167);

      expect(c1.distanceTo(c2), greaterThan(0));
      expect(c1 == const MapCoordinate(-6.772, 107.165), isTrue);

      final bounds = MapBounds.fromCoordinates([c1, c2]);
      expect(bounds.minLat, equals(-6.774));
      expect(bounds.maxLat, equals(-6.772));
      expect(bounds.contains(c1), isTrue);
      expect(bounds.contains(c2), isTrue);
      expect(bounds.contains(const MapCoordinate(-6.700, 107.100)), isFalse);
    });

    test('KmlParser parse and export roundtrip', () {
      const sampleKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Peta Uji</name>
    <Placemark>
      <name>BAPAK AHMAD (0001)</name>
      <description><![CDATA[NOP: 320520000400100010<br/>Status: Lunas]]></description>
      <ExtendedData>
        <Data name="NOP"><value>320520000400100010</value></Data>
        <Data name="BLOK"><value>001</value></Data>
        <Data name="STATUS"><value>Sudah Bayar</value></Data>
        <Data name="ALAMAT_OBJ"><value>KP BOBOJONG</value></Data>
        <Data name="ALAMAT_WP"><value>KP BOBOJONG</value></Data>
      </ExtendedData>
      <Point>
        <coordinates>107.165421,-6.772341,0</coordinates>
      </Point>
    </Placemark>
    <Placemark>
      <name>Zona Dusun 1</name>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              107.160,-6.770,0
              107.170,-6.770,0
              107.170,-6.780,0
              107.160,-6.780,0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
  </Document>
</kml>''';

      final res = KmlParser.parse(sampleKml);
      expect(res.dots.length, equals(1));
      expect(res.dusunZones.length, equals(1));

      final dot = res.dots.first;
      expect(dot.nop, equals('320520000400100010'));
      expect(dot.namaWajibPajak, contains('AHMAD'));
      expect(dot.blok, equals('001'));
      expect(dot.status, equals(MapDotStatus.lunas));
      expect(dot.isOwnerAddressSame, isTrue);

      // Export test
      final exported = KmlParser.exportToKml(
        villageName: 'BOBOJONG',
        dots: res.dots,
      );
      expect(exported, contains('<kml'));
      expect(exported, contains('320520000400100010'));
      expect(exported, contains('AHMAD'));
    });

    test('generateSampleBobojongMap populates realistic dots & zones', () {
      final sampleRecords = [
        const BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'HAJI SULAEMAN',
          tahunBayar: '2026',
          tanggalBayar: '2026-03-01 10:00:00',
          jumlahPbb: 'Rp 45.000',
          statusBayar: 'Sudah Bayar',
          alamatObjek: 'KP BOBOJONG RT 01',
          alamatWp: 'KP BOBOJONG RT 01',
        ),
        const BlokRecord(
          nop: '320520000400100020',
          namaWajibPajak: 'BU ENI',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: 'Rp 32.000',
          statusBayar: 'Belum Bayar',
          alamatObjek: 'KP BOBOJONG RT 02',
          alamatWp: 'KP KADUMANDU RT 05', // Terpisah
        ),
      ];

      final sample = KmlParser.generateSampleBobojongMap(sampleRecords);
      expect(sample.dusunZones.length, equals(5));
      // Titik WP statis/dummy sudah dihapus, menunggu data KML/GeoJSON fisik asli
      expect(sample.dots.isEmpty, isTrue);
    });
  });

  group('DhkpMapScreen Widget Tests', () {
    setUp(() async {
      await DusunData.instance.clearKantorDesaLocation();
    });

    testWidgets('renders Map HUD, controls, and selects dot when coordinates provided', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleRecords = [
        BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'RAHMAT SUBUR',
          tahunBayar: '2026',
          tanggalBayar: '2026-03-10 00:00:00',
          jumlahPbb: 'Rp 50.000',
          statusBayar: 'Sudah Bayar',
          alamatObjek: 'KP SERANG RT 01',
          alamatWp: 'KP SERANG RT 01',
        ),
      ];

      final sample = KmlParser.generateSampleBobojongMap(sampleRecords);
      const testDots = <MapTaxDot>[
        MapTaxDot(
          id: '1',
          nop: '320520000400100010',
          namaWajibPajak: 'RAHMAT SUBUR',
          blok: '001',
          nomorUrut: '0001',
          dusunNumber: 1,
          status: MapDotStatus.lunas,
          coordinate: MapCoordinate(-6.753, 107.260),
        ),
      ];

      // Set kantor desa agar tombol fokus muncul
      await DusunData.instance.setKantorDesaLocation(-6.7535, 107.2601);

      await tester.pumpWidget(
        MaterialApp(
          home: DhkpMapScreen(
            initialRecords: sampleRecords,
            initialDusun: 1,
            initialBlok: '001',
            initialDots: testDots,
            initialZones: sample.dusunZones,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Title & Subtitle
      expect(find.textContaining('Peta Objek Pajak: Dusun 1'), findsOneWidget);

      // Verify Dusun & Blok Chips
      expect(find.textContaining('Dusun 1'), findsWidgets);
      expect(find.textContaining('Dusun 2'), findsWidgets);
      expect(find.text('Semua Blok'), findsOneWidget);

      // Verify HUD Status Bar
      expect(find.textContaining('TOTAL:'), findsOneWidget);

      // Tap Dusun 2 chip
      await tester.tap(find.textContaining('Dusun 2').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Peta Objek Pajak: Dusun 2'), findsOneWidget);

      // Verify Layer Switch Button
      expect(find.byKey(const ValueKey('btn_switch_layer_map')), findsOneWidget);

      // Verify Fit Boundary Button
      expect(find.byKey(const ValueKey('btn_fit_desa_boundary')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('btn_fit_desa_boundary')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Fokuskan ke Kantor Desa Button
      expect(find.byKey(const ValueKey('btn_fokus_kantor_desa')), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_rounded), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('btn_fokus_kantor_desa')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Experimental Badge
      expect(find.text('EKSPERIMENTAL'), findsOneWidget);

      // Open Layer Switch Menu
      await tester.tap(find.byKey(const ValueKey('btn_switch_layer_map')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('Peta Rupabumi Indonesia (BIG)'), findsOneWidget);
      expect(find.textContaining('Batas Desa'), findsOneWidget);
      expect(find.textContaining('Layer Putih Wilayah Sekitar'), findsOneWidget);
      expect(find.textContaining('Bangunan & Rumah Warga (OSM)'), findsOneWidget);

      // Tap Bangunan OSM option - sheet must NOT close automatically
      await tester.tap(find.textContaining('Bangunan & Rumah Warga (OSM)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify sheet is still open ("biarkan user yg tutup")
      expect(find.text('Tutup Panel Layer'), findsOneWidget);

      // Tap RBI BIG option
      await tester.tap(find.textContaining('Peta Rupabumi Indonesia (BIG)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // User manually closes sheet
      await tester.tap(find.text('Tutup Panel Layer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Verify sheet is closed
      expect(find.text('Tutup Panel Layer'), findsNothing);
    });

    testWidgets('renders clean empty map without dusun 1 or focus buttons when data is empty',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: DhkpMapScreen(
            initialRecords: [],
            initialDusun: 1,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Title must be 'Peta Wilayah' and NOT 'Dusun 1'
      expect(find.text('Peta Wilayah'), findsOneWidget);
      expect(find.textContaining('Dusun 1'), findsNothing);
      expect(find.textContaining('Dusun 2'), findsNothing);

      // Subtitle indicates no DHKP loaded
      expect(
        find.textContaining('Peta Dasar Satelit (Belum ada berkas DHKP dimuat)'),
        findsOneWidget,
      );

      // Focus buttons must NOT be rendered when data is empty
      expect(find.byKey(const ValueKey('btn_fit_desa_boundary')), findsNothing);
      expect(find.byKey(const ValueKey('btn_fokus_kantor_desa')), findsNothing);

      // Only zoom controls should exist
      expect(find.byKey(const ValueKey('btn_zoom_in')), findsNothing); // heroTag only
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);

      // Bottom bar shows empty prompt with Unggah KML button
      expect(find.textContaining('Peta Belum Memuat Koordinat'), findsOneWidget);
      expect(find.text('Unggah KML'), findsOneWidget);
    });
  });
}

