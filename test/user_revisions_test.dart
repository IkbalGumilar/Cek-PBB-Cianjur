import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/blok_catatan_screen.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/blok_report_pdf.dart';
import 'package:cek_pbb_app/check_form_view.dart';
import 'package:cek_pbb_app/check_mode.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_widgets.dart';
import 'package:cek_pbb_app/document_preview_screen.dart';
import 'package:cek_pbb_app/feature_tour/feature_tour.dart';
import 'package:cek_pbb_app/monitoring/monitoring_result_table.dart';
import 'package:cek_pbb_app/pbb/check_result_cards.dart';
import 'package:cek_pbb_app/pbb_client.dart';
import 'package:cek_pbb_app/staff_portal/kolektif_group_dialogs.dart';
import 'package:cek_pbb_app/staff_portal/staff_portal_models.dart';
import 'package:cek_pbb_app/tagihan_result.dart';
import 'package:cek_pbb_app/ui/app_design_system.dart';

final Uint8List _valid1x1Png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

class _FakePbbClient extends PbbClient {
  String? lastTagihanNop;
  String? lastTagihanCaptcha;
  String? lastStatusNop;
  String? lastStatusTahun;
  String? lastStatusCaptcha;

  @override
  Future<Uint8List> fetchCaptchaImage(CheckMode mode) async => _valid1x1Png;

  @override
  Future<TagihanResult> checkTagihan({
    required String nop,
    required String captchaCode,
  }) async {
    lastTagihanNop = nop;
    lastTagihanCaptcha = captchaCode;
    return TagihanResult(
      namaWajibPajak: 'WAJIB PAJAK UJI',
      rows: [
        TagihanYearRow(
          tahun: '2026',
          pbb: 'Rp 50.000',
          denda: 'Rp 0',
          kurangBayar: 'Rp 50.000',
          statusBayar: 'BELUM BAYAR',
        ),
      ],
      totalPbb: 'Rp 50.000',
      totalDenda: 'Rp 0',
      totalKurangBayar: 'Rp 50.000',
      notFound: false,
      rawText: 'WAJIB PAJAK UJI',
    );
  }

  @override
  Future<PbbResult> checkStatusBayar({
    required String nop,
    required String tahun,
    required String captchaCode,
  }) async {
    lastStatusNop = nop;
    lastStatusTahun = tahun;
    lastStatusCaptcha = captchaCode;
    return PbbResult(
      'Sudah Bayar',
      'PBB tahun $tahun sudah dibayar (uji)',
      namaWajibPajak: 'WAJIB PAJAK UJI',
      tanggalBayar: '2026-04-01',
      jumlahPbb: 'Rp 50.000',
    );
  }
}

Map<String, Object> _allToursSeenPrefs() => {
  for (final id in FeatureTourStore.allTourIds)
    'feature_tour_completed_v1_$id': true,
};

bool _fieldHasFocus(WidgetTester tester, String label) {
  final tf = tester.widget<TextField>(find.widgetWithText(TextField, label));
  return tf.focusNode?.hasFocus ?? false;
}

String? _fieldError(WidgetTester tester, String label) {
  final tf = tester.widget<TextField>(find.widgetWithText(TextField, label));
  return tf.decoration?.errorText;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Revisi 1 - Alur Enter & Validasi Merah CheckFormView', () {
    testWidgets(
      'Mode Cek Tagihan: Enter memindahkan Blok -> Nomor Wilayah -> Kode Verifikasi -> Submit, dan field kosong menampilkan peringatan merah',
      (tester) async {
        SharedPreferences.setMockInitialValues(_allToursSeenPrefs());
        tester.view.physicalSize = const Size(1024, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeClient = _FakePbbClient();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CheckFormView(
                mode: CheckMode.tagihan,
                onImportPressed: () {},
                client: fakeClient,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Fokus ke Blok dan tekan Enter saat masih kosong -> tetap di Blok + error merah
        final blokFinder = find.widgetWithText(TextField, 'Blok');
        await tester.tap(blokFinder);
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();

        expect(_fieldHasFocus(tester, 'Blok'), isTrue);
        expect(_fieldHasFocus(tester, 'Nomor Wilayah'), isFalse);
        expect(_fieldError(tester, 'Blok'), 'Data belum diisi');

        // 2. Isi Blok -> error hilang, tekan Enter -> fokus pindah langsung ke Nomor Wilayah
        await tester.enterText(blokFinder, '17');
        await tester.pump();
        expect(_fieldError(tester, 'Blok'), isNull);

        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Nomor Wilayah'), isTrue);

        // 3. Tekan Enter saat Nomor Wilayah kosong -> tetap di Nomor Wilayah + error merah
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Nomor Wilayah'), isTrue);
        expect(_fieldError(tester, 'Nomor Wilayah'), 'Data belum diisi');

        // 4. Isi Nomor Wilayah -> error hilang, tekan Enter -> fokus pindah langsung ke Kode Verifikasi
        final wilayahFinder = find.widgetWithText(TextField, 'Nomor Wilayah');
        await tester.enterText(wilayahFinder, '154');
        await tester.pump();
        expect(_fieldError(tester, 'Nomor Wilayah'), isNull);

        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Kode Verifikasi'), isTrue);

        // 5. Tekan Enter/Done saat Kode Verifikasi kosong -> tetap di Kode Verifikasi + error merah
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Kode Verifikasi'), isTrue);
        expect(_fieldError(tester, 'Kode Verifikasi'), 'Data belum diisi');
        expect(fakeClient.lastTagihanNop, isNull);

        // 6. Isi Kode Verifikasi -> error hilang, tekan Done -> submit sukses
        final captchaFinder = find.widgetWithText(TextField, 'Kode Verifikasi');
        await tester.enterText(captchaFinder, 'AB12');
        await tester.pump();
        expect(_fieldError(tester, 'Kode Verifikasi'), isNull);

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 300));
        expect(fakeClient.lastTagihanCaptcha, 'AB12');
        expect(fakeClient.lastTagihanNop, '320520000401701540');
      },
    );

    testWidgets(
      'Mode Cek Status Bayar: Enter memindahkan Blok -> Nomor Wilayah -> Tahun Pajak (default siap Enter) -> Kode Verifikasi -> Submit',
      (tester) async {
        SharedPreferences.setMockInitialValues(_allToursSeenPrefs());
        tester.view.physicalSize = const Size(1024, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeClient = _FakePbbClient();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CheckFormView(
                mode: CheckMode.statusBayar,
                onImportPressed: () {},
                client: fakeClient,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Submit dalam keadaan Blok/Wilayah/Captcha kosong menandai semua field kosong dengan 'Data belum diisi'
        final submitFinder = find.byType(FilledButton);
        await tester.ensureVisible(submitFinder);
        await tester.tap(submitFinder);
        await tester.pump();

        expect(_fieldError(tester, 'Blok'), 'Data belum diisi');
        expect(_fieldError(tester, 'Nomor Wilayah'), 'Data belum diisi');
        expect(
          _fieldError(tester, 'Tahun Pajak'),
          isNull,
        ); // default 2026 terisi
        expect(_fieldError(tester, 'Kode Verifikasi'), 'Data belum diisi');
        expect(_fieldHasFocus(tester, 'Blok'), isTrue);

        // Blok -> Enter -> Nomor Wilayah
        await tester.enterText(find.widgetWithText(TextField, 'Blok'), '17');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Nomor Wilayah'), isTrue);

        // Nomor Wilayah -> Enter -> Tahun Pajak
        await tester.enterText(
          find.widgetWithText(TextField, 'Nomor Wilayah'),
          '154',
        );
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Tahun Pajak'), isTrue);

        // Uji peringatan merah jika Tahun Pajak dikosongkan
        await tester.enterText(
          find.widgetWithText(TextField, 'Tahun Pajak'),
          '',
        );
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Tahun Pajak'), isTrue);
        expect(_fieldError(tester, 'Tahun Pajak'), 'Data belum diisi');

        // Isi ulang tahun default (2026), lalu tekan Enter -> langsung ke Kode Verifikasi
        await tester.enterText(
          find.widgetWithText(TextField, 'Tahun Pajak'),
          '2026',
        );
        await tester.pump();
        expect(_fieldError(tester, 'Tahun Pajak'), isNull);
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(_fieldHasFocus(tester, 'Kode Verifikasi'), isTrue);

        // Isi Kode Verifikasi dan tekan Done -> submit
        await tester.enterText(
          find.widgetWithText(TextField, 'Kode Verifikasi'),
          'XYZ9',
        );
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 300));

        expect(fakeClient.lastStatusTahun, '2026');
        expect(fakeClient.lastStatusCaptcha, 'XYZ9');
        expect(fakeClient.lastStatusNop, '320520000401701540');
      },
    );
  });

  group('Revisi 2 & 3 - Konsolidasi Menu Cetak DHKP & Opsi Batal Cetak', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues(_allToursSeenPrefs());
      tempDir = Directory.systemTemp.createTempSync('dhkp_rev_test_');
      AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
      BlokDataStore.instance.resetForTesting();
      DocumentPreviewScreen.debugIsDesktopOverride = true;
      DocumentPreviewScreen.debugPrintHandler = null;
    });

    tearDown(() {
      DocumentPreviewScreen.debugIsDesktopOverride = null;
      DocumentPreviewScreen.debugPrintHandler = null;
      BlokDataStore.instance.resetForTesting();
      AppStorage.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'BlokReportPdf.build berhenti dengan BlokPrintCancelledException saat cancelToken dibatalkan',
      () async {
        final records = List.generate(70, (i) {
          return BlokRecord(
            namaWajibPajak: 'Wajib Pajak Uji $i',
            nop: '320520000401700${(i + 1).toString().padLeft(3, '0')}',
            tahunBayar: '2026',
            tanggalBayar: '2026-05-01',
            jumlahPbb: 'Rp 25.000',
            statusBayar: 'Sudah Bayar',
          );
        });

        final cancelToken = BlokPrintCancelToken();
        Future<void>.delayed(
          const Duration(milliseconds: 10),
          cancelToken.cancel,
        );

        await expectLater(
          BlokReportPdf.build(
            records,
            blokTitle: 'Blok 017',
            tahun: '2026',
            cancelToken: cancelToken,
          ),
          throwsA(isA<BlokPrintCancelledException>()),
        );
      },
    );

    testWidgets(
      'runCancellableDhkpPrint menampilkan tombol Batal Cetak dan membatalkan proses',
      (tester) async {
        final cancelToken = BlokPrintCancelToken();
        final completer = Completer<Uint8List>();
        Uint8List? output;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    output = await runCancellableDhkpPrint<Uint8List>(
                      context: context,
                      cancelToken: cancelToken,
                      title: 'Menyiapkan Cetakan DHKP',
                      initialMessage: 'Memulai...',
                      task: (_) => completer.future,
                    );
                  },
                  child: const Text('Mulai'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Mulai'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Menyiapkan Cetakan DHKP'), findsOneWidget);
        final cancelBtn = find.byKey(const ValueKey('dhkp_cancel_print_btn'));
        expect(cancelBtn, findsOneWidget);
        expect(find.text('Batal Cetak'), findsOneWidget);

        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();

        expect(cancelToken.isCancelled, isTrue);
        expect(find.text('Menyiapkan Cetakan DHKP'), findsNothing);
        expect(output, isNull);
      },
    );

    testWidgets(
      'BlokCatatanScreen hanya punya 1 tombol cetak di menu titik 3 dan mendukung Batal Cetak via Ctrl+P serta menu titik 3',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final currentYear = '${DateTime.now().year}';
        final records = List.generate(70, (i) {
          return BlokRecord(
            namaWajibPajak: 'Wajib Pajak DHKP $i',
            nop: '320520000401700${(i + 1).toString().padLeft(3, '0')}',
            tahunBayar: currentYear,
            tanggalBayar: '$currentYear-05-01',
            jumlahPbb: 'Rp 30.000',
            statusBayar: i.isEven ? 'Sudah Bayar' : 'Belum Bayar',
          );
        });

        await tester.runAsync(() async {
          await BlokDataStore.instance.upsertAll(records);
        });

        var printHandlerCalled = false;
        DocumentPreviewScreen.debugPrintHandler = (_, _) async {
          printHandlerCalled = true;
        };

        await tester.pumpWidget(
          const MaterialApp(
            scrollBehavior: AppScrollBehavior(),
            home: BlokCatatanScreen(),
          ),
        );

        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump(const Duration(milliseconds: 50));
          if (find.textContaining('Wajib Pajak DHKP').evaluate().isNotEmpty) {
            break;
          }
        }
        expect(find.textContaining('Wajib Pajak DHKP'), findsWidgets);

        // 1. Ikon cetak di luar titik 3 sudah dihapus; cetak hanya ada di dalam menu titik 3 (+ Ctrl+P)
        expect(
          find.byKey(const ValueKey('dhkp_direct_print_btn')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.print_outlined),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.more_vert_rounded),
          ),
          findsOneWidget,
        );

        // 2. Tekan Ctrl + P -> dialog progres muncul dengan tombol Batal Cetak
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Menyiapkan Cetakan DHKP'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('dhkp_cancel_print_btn')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('dhkp_cancel_print_btn')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Proses cetak DHKP dibatalkan.'), findsOneWidget);
        expect(printHandlerCalled, isFalse);

        // Hilangkan snackbar sebelumnya sebelum menguji lewat menu titik 3
        await tester.pump(const Duration(seconds: 5));

        // 3. Buka menu titik 3 -> pilih Cetak Laporan -> Cetak Langsung -> Batal Cetak
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Cetak Laporan'), findsOneWidget);
        await tester.tap(find.text('Cetak Laporan'));
        await tester.pumpAndSettle();

        expect(find.text('Cetak Laporan DHKP'), findsOneWidget);
        await tester.tap(find.text('Cetak Langsung'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Menyiapkan Cetakan DHKP'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('dhkp_cancel_print_btn')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('dhkp_cancel_print_btn')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Proses cetak DHKP dibatalkan.'), findsOneWidget);
        expect(printHandlerCalled, isFalse);
      },
    );
  });

  group('Revisi 4 - Geser Tabel Horizontal Desktop (Mouse Drag & Scrollbar)', () {
    Future<void> verifyHorizontalMouseDrag(
      WidgetTester tester, {
      required Finder tableScope,
    }) async {
      final scrollableFinder = find.descendant(
        of: tableScope,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      expect(scrollableFinder, findsAtLeastNWidgets(1));

      final scrollableState = tester.state<ScrollableState>(
        scrollableFinder.first,
      );
      expect(
        scrollableState.position.maxScrollExtent,
        greaterThan(0),
        reason: 'Tabel harus melebar melebihi viewport untuk diuji geser',
      );
      expect(scrollableState.position.pixels, 0);

      final center = tester.getCenter(scrollableFinder.first);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-35, 0));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        scrollableState.position.pixels,
        greaterThan(50),
        reason: 'Geser drag dengan mouse di desktop harus menggeser tabel',
      );
    }

    testWidgets(
      'TagihanResultCard dapat digeser horizontal dengan mouse di viewport desktop',
      (tester) async {
        tester.view.physicalSize = const Size(640, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeClient = _FakePbbClient();
        final result = TagihanResult(
          namaWajibPajak: 'BUDI SANTOSO',
          rows: [
            TagihanYearRow(
              tahun: '2026',
              pbb: 'Rp 125.000',
              denda: 'Rp 10.000',
              kurangBayar: 'Rp 135.000',
              statusBayar: 'BELUM BAYAR',
              paymentCodeVa: '8880123456789012',
            ),
          ],
          totalPbb: 'Rp 125.000',
          totalDenda: 'Rp 10.000',
          totalKurangBayar: 'Rp 135.000',
          notFound: false,
          rawText: 'BUDI SANTOSO',
        );

        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: TagihanResultCard(
                  result: result,
                  nop: '320520000401701540',
                  client: fakeClient,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AppHorizontalTableScroll), findsOneWidget);
        expect(find.byType(Scrollbar), findsAtLeastNWidgets(1));
        await verifyHorizontalMouseDrag(
          tester,
          tableScope: find.byType(AppHorizontalTableScroll),
        );
      },
    );

    testWidgets(
      'MonitoringResultView (Portal Staf) dapat digeser horizontal dengan mouse di viewport desktop',
      (tester) async {
        tester.view.physicalSize = const Size(820, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const result = MonitoringTableResult(
          headers: [
            'NOP',
            'Nama Wajib Pajak',
            'Alamat Lengkap Objek Pajak',
            'Desa / Kelurahan',
            'Kecamatan',
            'Pokok PBB',
            'Denda',
            'Total Tagihan',
            'Tanggal Pembayaran',
          ],
          rows: [
            [
              '32.05.200.004.017-0154.0',
              'BUDI SANTOSO WIDJAJA KUSUMA',
              'KP SUKAMULYA RT 001 RW 002 DESA BOBOJONG KECAMATAN MANDE',
              'BOBOJONG',
              'MANDE',
              'Rp 150.000',
              'Rp 15.000',
              'Rp 165.000',
              '2026-04-12 09:30:00',
            ],
          ],
        );

        await tester.pumpWidget(
          const MaterialApp(
            scrollBehavior: AppScrollBehavior(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MonitoringResultView(
                  result: result,
                  loading: false,
                  reportTitle: 'Uji Portal Staf',
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AppHorizontalTableScroll), findsOneWidget);
        await verifyHorizontalMouseDrag(
          tester,
          tableScope: find.byType(AppHorizontalTableScroll),
        );
      },
    );

    testWidgets(
      'KolektifResultView (Portal Staf Kolektif) dapat digeser horizontal dengan mouse di viewport desktop',
      (tester) async {
        tester.view.physicalSize = const Size(780, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const result = KolektifListResult(
          groups: [
            KolektifGroup(
              id: 'grp-1',
              namaGroup: 'Kelompok Kolektif Dusun III Bobojong',
              namaKolektor: 'Ahmad Hidayatulloh',
              hpKolektor: '081234567890',
              anggota: '25 Anggota Wajib Pajak',
              kodeBayar: '9001234567890123',
              status: 'MENUNGGU PEMBAYARAN',
              kecamatan: 'MANDE',
              kelurahan: 'BOBOJONG',
              kelurahanCode: '004',
              keterangan: 'Pembayaran kolektif semester I tahun pajak 2026',
              tanggalKadaluarsa: '2026-12-31',
              statusCode: '1',
              canDelete: false,
              canEdit: true,
              canPrintSurat: true,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: KolektifResultView(result: result, onAksi: (_) {}),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AppHorizontalTableScroll), findsOneWidget);
        await verifyHorizontalMouseDrag(
          tester,
          tableScope: find.byType(AppHorizontalTableScroll),
        );
      },
    );
  });
}
