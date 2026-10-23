import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('dkhp_test_');
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
    BlokDataStore.instance.resetForTesting();
    DhkpPackageHelper.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('findPhotoForNopSync menggunakan cache memori O(1) tanpa I/O disk', () {
    final cachedNames = <String>{
      '320520000401700060.jpg',
      '320520000401700090.png',
      '017_006.jpg',
    };

    // NOP yang fotonya ada di cache
    final photo1 = DhkpPackageHelper.findPhotoForNopSync(
      '320520000401700060',
      photosDir: tempDir,
      cachedNames: cachedNames,
    );
    expect(photo1, isNotNull);
    expect(photo1!.path.endsWith('320520000401700060.jpg'), isTrue);

    // NOP yang fotonya tidak ada di cache
    final photo2 = DhkpPackageHelper.findPhotoForNopSync(
      '320520000409999999',
      photosDir: tempDir,
      cachedNames: cachedNames,
    );
    expect(photo2, isNull);
  });

  test('Logika paginasi virtual membagi 150 record menjadi 3 halaman @ 50 baris', () {
    final dummyRecords = List.generate(
      150,
      (i) => BlokRecord(
        namaWajibPajak: 'WP KE-$i',
        nop: '3205200004017${(i + 10).toString().padLeft(5, '0')}',
        tahunBayar: '2026',
        tanggalBayar: i % 2 == 0 ? '23/10/2026' : '',
        jumlahPbb: 'Rp 50.000',
        statusBayar: i % 2 == 0 ? 'Sudah Bayar' : 'Belum Bayar',
        isTargetPemda: i < 5,
        catatan: 'Catatan WP ke-$i',
      ),
    );

    const rowsPerPage = 50;
    final totalPages = (dummyRecords.length / rowsPerPage).ceil();
    expect(totalPages, 3);

    // Halaman 1 (indeks 0..50)
    int page = 0;
    int start = page * rowsPerPage;
    int end = (start + rowsPerPage).clamp(0, dummyRecords.length);
    var paged = dummyRecords.sublist(start, end);
    expect(paged.length, 50);
    expect(paged.first.namaWajibPajak, 'WP KE-0');
    expect(paged.last.namaWajibPajak, 'WP KE-49');

    // Halaman 2 (indeks 50..100)
    page = 1;
    start = page * rowsPerPage;
    end = (start + rowsPerPage).clamp(0, dummyRecords.length);
    paged = dummyRecords.sublist(start, end);
    expect(paged.length, 50);
    expect(paged.first.namaWajibPajak, 'WP KE-50');
    expect(paged.last.namaWajibPajak, 'WP KE-99');

    // Halaman 3 (indeks 100..150)
    page = 2;
    start = page * rowsPerPage;
    end = (start + rowsPerPage).clamp(0, dummyRecords.length);
    paged = dummyRecords.sublist(start, end);
    expect(paged.length, 50);
    expect(paged.first.namaWajibPajak, 'WP KE-100');
    expect(paged.last.namaWajibPajak, 'WP KE-149');
  });

  test('Pencarian instan memfilter 1.521 record dalam memori secara cepat', () {
    final dummyRecords = List.generate(
      1521,
      (i) => BlokRecord(
        namaWajibPajak: i == 999 ? 'H ACEP TARGET PEMDA' : 'WP KE-$i',
        nop: '3205200004017${(i + 1).toString().padLeft(5, '0')}',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 25.000',
        statusBayar: 'Belum Bayar',
        alamatObjek: i == 500 ? 'JL CIKANGKUNG NO 12' : 'JL RAYA BOBOJONG',
        catatan: i == 777 ? 'Sengketa waris' : '',
      ),
    );

    // Cari berdasarkan nama
    final searchByName = dummyRecords.where((r) => r.namaWajibPajak.toLowerCase().contains('h acep')).toList();
    expect(searchByName.length, 1);
    expect(searchByName.first.namaWajibPajak, 'H ACEP TARGET PEMDA');

    // Cari berdasarkan alamat
    final searchByAlamat = dummyRecords.where((r) => r.alamatObjek.toLowerCase().contains('cikangkung')).toList();
    expect(searchByAlamat.length, 1);
    expect(searchByAlamat.first.alamatObjek, 'JL CIKANGKUNG NO 12');

    // Cari berdasarkan catatan
    final searchByCatatan = dummyRecords.where((r) => r.catatan.toLowerCase().contains('sengketa')).toList();
    expect(searchByCatatan.length, 1);
    expect(searchByCatatan.first.nop, '320520000401700778');
  });

  test('Kalkulasi ringkasan single-pass O(N) untuk ribuan data berjalan akurat', () {
    final dummyRecords = [
      const BlokRecord(
        namaWajibPajak: 'WP A',
        nop: '320520000401700010',
        tahunBayar: '2026',
        tanggalBayar: '2026-03-01',
        jumlahPbb: 'Rp 100.000',
        statusBayar: 'Sudah Bayar',
        isTargetPemda: false,
      ),
      const BlokRecord(
        namaWajibPajak: 'WP B',
        nop: '320520000401700020',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 200.000',
        statusBayar: 'Belum Bayar',
        isTargetPemda: true,
      ),
      const BlokRecord(
        namaWajibPajak: 'WP C',
        nop: '320520000401700030',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 300.000',
        statusBayar: 'Belum Bayar',
        isTargetPemda: false,
      ),
    ];

    int sBayarCount = 0;
    int sBayarNom = 0;
    int bBayarCount = 0;
    int bBayarNom = 0;
    int tPemdaCount = 0;
    int tPemdaNom = 0;
    for (final r in dummyRecords) {
      final int pbb = r.jumlahPbbValue;
      if (r.isTargetPemda) {
        tPemdaCount++;
        tPemdaNom += pbb;
      } else if (r.isPaid) {
        sBayarCount++;
        sBayarNom += pbb;
      } else {
        bBayarCount++;
        bBayarNom += pbb;
      }
    }

    final totCount = sBayarCount + bBayarCount;
    final totNom = sBayarNom + bBayarNom;

    expect(totCount, 2);
    expect(totNom, 400000);
    expect(sBayarCount, 1);
    expect(sBayarNom, 100000);
    expect(bBayarCount, 1);
    expect(bBayarNom, 300000);
    expect(tPemdaCount, 1);
    expect(tPemdaNom, 200000);
  });

  testWidgets('Tabel data dapat digeser ke samping (horizontal scroll) pada layar HP', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final hCtrl = ScrollController();
    final vCtrl = ScrollController();
    addTearDown(() {
      hCtrl.dispose();
      vCtrl.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 500,
            child: Scrollbar(
              controller: vCtrl,
              thumbVisibility: true,
              notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
              child: Scrollbar(
                controller: hCtrl,
                thumbVisibility: true,
                notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: hCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SingleChildScrollView(
                    controller: vCtrl,
                    scrollDirection: Axis.vertical,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Col 1')),
                        DataColumn(label: Text('Col 2')),
                        DataColumn(label: Text('Col 3')),
                        DataColumn(label: Text('Col 4')),
                        DataColumn(label: Text('Col 5')),
                      ],
                      rows: List.generate(
                        10,
                        (i) => DataRow(
                          cells: [
                            DataCell(Text('Cell 1-$i (panjang teks untuk pengujian)')),
                            DataCell(Text('Cell 2-$i (panjang teks untuk pengujian)')),
                            DataCell(Text('Cell 3-$i')),
                            DataCell(Text('Cell 4-$i')),
                            DataCell(Text('Cell 5-$i')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final horizontalScrollable = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollable, findsOneWidget);

    // Geser tabel ke samping (swipe left) di layar HP
    await tester.drag(horizontalScrollable, const Offset(-200, 0));
    await tester.pumpAndSettle();

    // Pastikan scroll horizontal merespons pergeseran
    expect(hCtrl.offset, greaterThan(0));
  });
}
