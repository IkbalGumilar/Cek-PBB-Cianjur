import 'dart:async';
import 'dart:io';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/base_preferences_store.dart';
import 'package:cek_pbb_app/batch_check_manager.dart';
import 'package:cek_pbb_app/batch_check_screen.dart';
import 'package:cek_pbb_app/batch_notification_service.dart';
import 'package:cek_pbb_app/blok_batch_check_tracker.dart';
import 'package:cek_pbb_app/blok_catatan_screen.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_dialogs.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_widgets.dart';
import 'package:cek_pbb_app/dhkp_grafik_view.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/dusun_data.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_sync_manager.dart';
import 'package:cek_pbb_app/monitoring/staff_sync_bubble_overlay.dart';
import 'package:cek_pbb_app/pbb_client.dart';
import 'package:cek_pbb_app/result_screen.dart';
import 'package:cek_pbb_app/settings/user_guide_data.dart';
import 'package:cek_pbb_app/tax_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControllableBatchClient extends PbbClient {
  final Map<int, Completer<PbbResult>> gates = {};
  int callIndex = 0;

  @override
  Future<PbbResult> checkStatusViaDocument(String nop, {String? tahun}) async {
    final idx = callIndex++;
    if (gates.containsKey(idx)) {
      return gates[idx]!.future;
    }
    return idx.isEven
        ? PbbResult('Sudah Bayar', 'LUNAS', tanggalBayar: '2026-06-01')
        : PbbResult('Belum Bayar', 'Belum lunas');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'feature_tour_seen_dhkp_table_view': true,
      'feature_tour_seen_dhkp_grafik_view': true,
    });
    BaseSecureStore.clearTestMemoryStore();
    tempDir = Directory.systemTemp.createTempSync('release_v1_fixes_test_');
    AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
    BlokDataStore.instance.resetForTesting();
    await BlokBatchCheckTracker.instance.clearHistory();
    await DusunData.instance.init();
    await DusunData.instance.clearScope();
    BatchCheckManager.instance.reset();
    StaffDhkpSyncManager.instance.reset();
    BatchNotificationService.instance.resetTapDeduplication();
    BlokCatatanScreen.isCurrentlyOpen = false;
    ResultScreen.isCurrentlyOpen = false;
  });

  tearDown(() async {
    BatchCheckManager.instance.reset();
    StaffDhkpSyncManager.instance.reset();
    BatchNotificationService.instance.resetTapDeduplication();
    await BlokBatchCheckTracker.instance.clearHistory();
    BlokCatatanScreen.isCurrentlyOpen = false;
    ResultScreen.isCurrentlyOpen = false;
    await DusunData.instance.clearScope();
    AppStorage.resetForTesting();
    BlokDataStore.instance.resetForTesting();
    BaseSecureStore.clearTestMemoryStore();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Fix #1 & #5: BatchCheckScreen icons, centered auto-scroll, and background hide', () {
    testWidgets(
      'shows distinct pending/active/paid/unpaid icons and centers active NOP via auto-scroll',
      (tester) async {
        tester.view.physicalSize = const Size(420, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final client = _ControllableBatchClient();
        final gate15 = Completer<PbbResult>();
        client.gates[15] = gate15;

        final records = List<TaxRecord>.generate(
          30,
          (i) => TaxRecord(
            nop: '3205200004001${(i + 1).toString().padLeft(4, '0')}0',
            namaWajibPajak: 'WAJIB PAJAK ${i + 1}',
            status: '',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: rootNavigatorKey,
            builder: (context, child) => Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const StaffSyncBubbleOverlay(),
              ],
            ),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        settings: const RouteSettings(
                          name: BatchCheckScreen.routeName,
                        ),
                        builder: (_) => BatchCheckScreen(
                          records: records,
                          tahun: '2026',
                          client: client,
                          pacingDelay: Duration.zero,
                          cooldownBatchSize: 0,
                        ),
                      ),
                    );
                  },
                  child: const Text('Buka Cek Massal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Cek Massal'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        await tester.runAsync(() async {
          for (var step = 0; step < 60; step++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (BatchCheckManager.instance.currentIndex == 15) break;
          }
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(BatchCheckManager.instance.currentIndex, 15);
        expect(find.byIcon(Icons.autorenew_rounded), findsAtLeastNWidgets(1));
        expect(find.byIcon(Icons.hourglass_empty_rounded), findsWidgets);

        final activeRowFinder = find.descendant(
          of: find.byType(ListView),
          matching: find.text('WAJIB PAJAK 16'),
        );
        expect(activeRowFinder, findsOneWidget);
        final listRect = tester.getRect(find.byType(ListView));
        final activeRect = tester.getRect(activeRowFinder);
        final listCenterY = listRect.top + listRect.height / 2;
        final activeCenterY = activeRect.top + activeRect.height / 2;
        expect(
          (activeCenterY - listCenterY).abs(),
          lessThan(90.0),
          reason:
              'NOP aktif (indeks 15) harus berada di tengah viewport daftar, bukan tertinggal',
        );

        // Uji tombol Sembunyikan: kembali tanpa menghentikan proses + bubble tampil!
        await tester.tap(
          find.byKey(const ValueKey('batch_hide_action_btn')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(BatchCheckManager.instance.isActiveSession, isTrue);
        expect(BatchCheckManager.instance.shouldShowBubble, isTrue);
        expect(
          find.byKey(const ValueKey('batch_check_floating_bubble')),
          findsOneWidget,
        );

        await tester.runAsync(() async {
          gate15.complete(PbbResult('Sudah Bayar', 'LUNAS'));
          for (var step = 0; step < 60; step++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (BatchCheckManager.instance.isCompleted) break;
          }
        });
        await tester.pump();
        expect(BatchCheckManager.instance.isCompleted, isTrue);
        BatchCheckManager.instance.dismiss();
        await tester.pump();
      },
    );
  });

  group('Fix #3: DhkpGrafikView Kedusunan scope tabs', () {
    List<BlokRecord> buildKedusunanRecords({required List<String> years}) {
      return [
        for (final y in years) ...[
          BlokRecord(
            nop: '320520000400100010',
            namaWajibPajak: 'WP BLOK 1 $y',
            tahunBayar: y,
            tanggalBayar: '$y-03-10',
            jumlahPbb: '100000',
            statusBayar: 'Sudah Bayar',
          ),
          BlokRecord(
            nop: '320520000400200010',
            namaWajibPajak: 'WP BLOK 2 $y',
            tahunBayar: y,
            tanggalBayar: '',
            jumlahPbb: '150000',
            statusBayar: 'Belum Bayar',
          ),
        ],
      ];
    }

    testWidgets(
      'Kedusunan scope shows ONLY 2 tabs (Se-Kedusunan and Semua Blok) without Se-Desa or Dusun chip',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await DusunData.instance.setScope(
          const DusunScope(
            role: 'dusun',
            dusunNumber: 1,
            dusunName: 'Dusun 1',
            allowedBloks: ['001', '002'],
          ),
        );

        final records = buildKedusunanRecords(years: const ['2026', '2025']);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(
                records: records,
                selectedBlok: semuaBlokValue,
                selectedWilayah: 1,
                selectedTahun: '2026',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Se-Kedusunan'), findsOneWidget);
        expect(find.text('Semua Blok'), findsOneWidget);
        expect(find.text('Se-Desa'), findsNothing);
        expect(find.text('Per Desa'), findsNothing);
        expect(find.text('Per Blok'), findsNothing);
        expect(find.text('Dusun 1'), findsNothing);
      },
    );

    testWidgets(
      'scope tabs disappear completely once a specific block filter is selected (even with multi-year data)',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await DusunData.instance.setScope(
          const DusunScope(
            role: 'dusun',
            dusunNumber: 1,
            dusunName: 'Dusun 1',
            allowedBloks: ['001', '002'],
          ),
        );

        final singleBlokRecords = buildKedusunanRecords(
          years: const ['2026', '2025'],
        ).where((r) => r.blok == '001').toList();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(
                records: singleBlokRecords,
                selectedBlok: '001',
                selectedWilayah: 1,
                selectedTahun: '2026',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Se-Kedusunan'), findsNothing);
        expect(find.text('Semua Blok'), findsNothing);
        expect(find.text('Se-Desa'), findsNothing);
        expect(find.text('Wilayah:'), findsNothing);
      },
    );
  });

  group('Fix #4: Cancellable DHKP print dialog (single loading modal + cancel)', () {
    testWidgets(
      'runCancellableDhkpPrint displays single progress dialog and cancels cleanly when Batal Cetak is tapped',
      (tester) async {
        final cancelToken = BlokPrintCancelToken();
        final taskGate = Completer<void>();
        String? printResult = 'NOT_DONE';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    printResult = await runCancellableDhkpPrint<String>(
                      context: ctx,
                      cancelToken: cancelToken,
                      title: 'Menyiapkan Cetakan DHKP',
                      initialMessage: 'Menyiapkan dokumen cetak PDF...',
                      task: (_) async {
                        await taskGate.future;
                        if (cancelToken.isCancelled) {
                          throw const BlokPrintCancelledException();
                        }
                        return 'DONE';
                      },
                    );
                  },
                  child: const Text('Cetak'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Cetak'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(find.text('Menyiapkan Cetakan DHKP'), findsOneWidget);
        expect(find.text('Batal Cetak'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        await tester.tap(find.text('Batal Cetak'));
        taskGate.complete();
        await tester.pumpAndSettle();

        expect(cancelToken.isCancelled, isTrue);
        expect(printResult, isNull);
      },
    );
  });

  group('Fix #5 addition: Seluruh Blok check ONLY for Kedusunan, disabled for Desa+', () {
    final recordsByBlok = <String, List<BlokRecord>>{
      '001': const [
        BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'WP 1',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: '50000',
          statusBayar: 'Belum Bayar',
        ),
      ],
      '002': const [
        BlokRecord(
          nop: '320520000400200010',
          namaWajibPajak: 'WP 2',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: '75000',
          statusBayar: 'Belum Bayar',
        ),
      ],
    };

    testWidgets(
      'Kedusunan scope enables Seluruh Blok option and returns records across all blocks',
      (tester) async {
        List<BlokRecord>? picked;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    picked = await showPilihBlokCekMassalDialog(
                      ctx,
                      availableBloks: const ['001', '002'],
                      recordsByBlok: recordsByBlok,
                      selectedWilayah: 1,
                      allowAllBlocks: true,
                    );
                  },
                  child: const Text('Buka Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Dialog'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        final allBlocksText = find.text('Seluruh Blok (2 Blok)');
        expect(allBlocksText, findsWidgets);
        await tester.tap(allBlocksText.last, warnIfMissed: false);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mulai Cek (2 NOP)'));
        await tester.pumpAndSettle();

        expect(picked, isNotNull);
        expect(picked!.length, 2);
      },
    );

    testWidgets(
      'Desa level and above disables Seluruh Blok option',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    showPilihBlokCekMassalDialog(
                      ctx,
                      availableBloks: const ['001', '002'],
                      recordsByBlok: recordsByBlok,
                      selectedWilayah: null,
                      allowAllBlocks: false,
                    );
                  },
                  child: const Text('Buka Dialog Desa'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Dialog Desa'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('dinonaktifkan untuk tingkat Desa ke atas'),
          findsOneWidget,
        );

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<String> &&
                w.value == semuaBlokCekMassalValue,
          ),
          findsNothing,
        );
        expect(find.text('Blok 1'), findsWidgets);
        expect(find.text('Blok 2'), findsWidgets);
      },
    );
  });

  group('Fix #6: Year-aware .dkhp installation (empty / new year / same year overwrite)', () {
    Future<File> buildSampleDkhp(String name, List<BlokRecord> records) async {
      final path = '${tempDir.path}/$name';
      return DhkpPackageHelper.packDkhp(
        outputPath: path,
        records: records,
        baseRecords: records,
        deltaOnly: false,
        includePhotos: false,
        encrypt: false,
        tahunPajak: records.first.tahunBayar,
      );
    }

    testWidgets(
      'empty DB installs directly without confirmation; 2026 -> 2027 updates without confirmation preserving 2026; 2026 -> 2026 requires confirmation and overwrites only 2026',
      (tester) async {
        late File dkhp2026A;
        late File dkhp2026B;
        late File dkhp2027;
        await tester.runAsync(() async {
          dkhp2026A = await buildSampleDkhp('dhkp_2026_a.dkhp', const [
            BlokRecord(
              nop: '320520000400100010',
              namaWajibPajak: 'WP 2026 LAMA',
              tahunBayar: '2026',
              tanggalBayar: '',
              jumlahPbb: '50000',
              statusBayar: 'Belum Bayar',
            ),
          ]);
          dkhp2026B = await buildSampleDkhp('dhkp_2026_b.dkhp', const [
            BlokRecord(
              nop: '320520000400100020',
              namaWajibPajak: 'WP 2026 BARU',
              tahunBayar: '2026',
              tanggalBayar: '2026-04-01',
              jumlahPbb: '75000',
              statusBayar: 'Sudah Bayar',
            ),
          ]);
          dkhp2027 = await buildSampleDkhp('dhkp_2027.dkhp', const [
            BlokRecord(
              nop: '320520000400100010',
              namaWajibPajak: 'WP 2027 BARU',
              tahunBayar: '2027',
              tanggalBayar: '',
              jumlahPbb: '60000',
              statusBayar: 'Belum Bayar',
            ),
          ]);
        });

        late BuildContext hostCtx;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  hostCtx = ctx;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        // 1. DB kosong + DHKP 2026 -> langsung diisi TANPA dialog konfirmasi!
        late DhkpInstallPlan planEmpty;
        await tester.runAsync(() async {
          planEmpty = await DhkpPackageHelper.inspectInstallPlan(
            dkhp2026A.path,
          );
        });
        expect(planEmpty.isExistingEmpty, isTrue);
        expect(planEmpty.willOverwriteSameYear, isFalse);
        final okEmpty = await confirmDhkpInstallPlanIfNeeded(
          hostCtx,
          planEmpty,
        );
        expect(okEmpty, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.runAsync(() async {
          await DhkpPackageHelper.unpackDkhp(dkhp2026A.path);
        });

        // 2. DB berisi 2026 + DHKP 2027 -> memperbarui (menambah 2027) TANPA konfirmasi & TANPA menghapus 2026!
        late DhkpInstallPlan plan2027;
        await tester.runAsync(() async {
          plan2027 = await DhkpPackageHelper.inspectInstallPlan(dkhp2027.path);
        });
        expect(plan2027.isYearUpdateOnly, isTrue);
        expect(plan2027.willOverwriteSameYear, isFalse);
        final ok2027 = await confirmDhkpInstallPlanIfNeeded(hostCtx, plan2027);
        expect(ok2027, isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        late List<BlokRecord> after2027;
        await tester.runAsync(() async {
          await DhkpPackageHelper.unpackDkhp(dkhp2027.path);
          after2027 = await BlokDataStore.instance.loadAll();
        });
        expect(after2027.length, 2);
        expect(after2027.any((r) => r.tahunBayar == '2026'), isTrue);
        expect(after2027.any((r) => r.tahunBayar == '2027'), isTrue);

        // 3. DB berisi 2026 & 2027 + DHKP 2026 baru -> WAJIB dialog konfirmasi timpa!
        late DhkpInstallPlan planSameYear;
        await tester.runAsync(() async {
          planSameYear = await DhkpPackageHelper.inspectInstallPlan(
            dkhp2026B.path,
          );
        });
        expect(planSameYear.willOverwriteSameYear, isTrue);
        expect(planSameYear.overlappingYears, contains('2026'));

        bool? confirmedSameYear;
        final confirmFuture = confirmDhkpInstallPlanIfNeeded(
          hostCtx,
          planSameYear,
          fileName: 'dhkp_2026_b.dkhp',
        ).then((v) => confirmedSameYear = v);
        await tester.pumpAndSettle();

        expect(find.text('Konfirmasi Timpa Data Tahun 2026'), findsOneWidget);
        await tester.tap(find.text('Ya, Timpa Tahun 2026'));
        await tester.pumpAndSettle();
        await confirmFuture;
        expect(confirmedSameYear, isTrue);

        late List<BlokRecord> afterOverwrite2026;
        await tester.runAsync(() async {
          await DhkpPackageHelper.unpackDkhp(dkhp2026B.path);
          afterOverwrite2026 = await BlokDataStore.instance.loadAll();
        });
        // Data 2026 lama (WP 2026 LAMA) tertimpa oleh WP 2026 BARU, sedangkan data 2027 TETAP AMAN!
        expect(afterOverwrite2026.length, 2);
        expect(
          afterOverwrite2026.any((r) => r.namaWajibPajak == 'WP 2026 LAMA'),
          isFalse,
        );
        expect(
          afterOverwrite2026.any((r) => r.namaWajibPajak == 'WP 2026 BARU'),
          isTrue,
        );
        expect(
          afterOverwrite2026.any((r) => r.namaWajibPajak == 'WP 2027 BARU'),
          isTrue,
        );
      },
    );
  });

  group('Fix #2: Updated user guide content covers all new workflows', () {
    test('UserGuideRepository documents background check, Kedusunan 2-tab Grafik, and year-aware .dkhp install', () {
      final allText = [
        for (final t in UserGuideRepository.topics) ...[
          t.title,
          t.subtitle,
          t.summary,
          for (final p in t.pins) '${p.title} ${p.description}',
        ],
        for (final f in UserGuideRepository.faqs) '${f.question} ${f.answer}',
      ].join('\n');

      expect(allText, contains('Se-Kedusunan'));
      expect(allText, contains('Semua Blok'));
      expect(allText, contains('Sembunyikan'));
      expect(allText, contains('Seluruh Blok'));
      expect(allText, contains('konfirmasi timpa'));
    });
  });
}
