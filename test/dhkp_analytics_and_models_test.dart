import 'dart:ui';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_models.dart';
import 'package:cek_pbb_app/dhkp/dhkp_chart_widgets.dart';
import 'package:cek_pbb_app/dhkp_grafik_view.dart';
import 'package:cek_pbb_app/dusun_data.dart';
import 'package:cek_pbb_app/nop_helper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sampleRecords = [
    BlokRecord(
      nop: '320520000400100010',
      namaWajibPajak: 'ASEP SUNANDAR',
      tahunBayar: '2026',
      tanggalBayar: '2026-03-15',
      jumlahPbb: '100000',
      statusBayar: 'Sudah Bayar',
      alamatObjek: 'KP. SUKAMAJU',
      catatan: 'Bayar kolektif',
    ),
    BlokRecord(
      nop: '320520000400100020',
      namaWajibPajak: 'DEDI KUSNADI',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: '300000',
      statusBayar: 'Belum Bayar',
      alamatObjek: 'KP. SUKAMAJU',
    ),
    BlokRecord(
      nop: '320520000401700010',
      namaWajibPajak: 'PT PABRIK TEKSTIL',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: '2000000',
      statusBayar: 'Belum Bayar',
      isTargetPemda: true,
    ),
  ];

  group('DhkpSummaryMetrics', () {
    test('compute separates Target Pemda from village totals', () {
      final metrics = DhkpSummaryMetrics.compute(sampleRecords);
      expect(metrics.sudahBayarCount, 1);
      expect(metrics.sudahBayarNominal, 100000);
      expect(metrics.belumBayarCount, 1);
      expect(metrics.belumBayarNominal, 300000);
      expect(metrics.targetPemdaCount, 1);
      expect(metrics.targetPemdaNominal, 2000000);
      expect(metrics.totalCount, 2);
      expect(metrics.totalNominal, 400000);
      expect(metrics.pctSudah, '25%');
      expect(metrics.pctBelum, '75%');
    });

    test('filterByKategori and filterBySearch filter accurately', () {
      expect(
        DhkpSummaryMetrics.filterByKategori(
          sampleRecords,
          DhkpKategoriFilter.sudahBayar,
        ),
        hasLength(1),
      );
      expect(
        DhkpSummaryMetrics.filterByKategori(
          sampleRecords,
          DhkpKategoriFilter.belumBayar,
        ),
        hasLength(1),
      );
      expect(
        DhkpSummaryMetrics.filterByKategori(
          sampleRecords,
          DhkpKategoriFilter.targetPemda,
        ),
        hasLength(1),
      );

      final searched = DhkpSummaryMetrics.filterBySearch(
        sampleRecords,
        'kolektif',
      );
      expect(searched, hasLength(1));
      expect(searched.first.namaWajibPajak, 'ASEP SUNANDAR');
    });
  });

  group('DhkpGrafikAnalytics', () {
    test('formatShortRupiah formats Rb, Jt, and M suffixes', () {
      expect(formatShortRupiah(500), '500');
      expect(formatShortRupiah(15000), '15 Rb');
      expect(formatShortRupiah(2500000), '2.5 Jt');
      expect(formatShortRupiah(1200000000), '1.2 M');
    });

    test(
      'parsePaymentDate parses ISO and DD-MM-YYYY dates and rejects standalone years',
      () {
        expect(parsePaymentDate('2026-04-16 14:59:06')?.month, 4);
        expect(parsePaymentDate('16-08-2026')?.month, 8);
        expect(parsePaymentDate('2024'), isNull);
        expect(parsePaymentDate('2025'), isNull);
        expect(parsePaymentDate('2026'), isNull);
        expect(parsePaymentDate('2027'), isNull);
        expect(parsePaymentDate('-'), isNull);
        expect(parsePaymentDate('0'), isNull);
        expect(parsePaymentDate(''), isNull);
      },
    );

    test(
      'BlokRecord.isPaid strictly evaluates payment status and excludes Belum Bayar with date placeholders',
      () {
        const unpaidWithDash = BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'TEST',
          tahunBayar: '2026',
          tanggalBayar: '-',
          statusBayar: 'Belum Bayar',
        );
        expect(unpaidWithDash.isPaid, isFalse);

        const unpaidWithYearOnly = BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'TEST',
          tahunBayar: '2026',
          tanggalBayar: '2026',
          statusBayar: 'Belum Bayar',
        );
        expect(unpaidWithYearOnly.isPaid, isFalse);

        const paidWithDate = BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'TEST',
          tahunBayar: '2026',
          tanggalBayar: '2026-05-10',
          statusBayar: 'Sudah Bayar',
        );
        expect(paidWithDate.isPaid, isTrue);

        const paidLunas = BlokRecord(
          nop: '320520000400100010',
          namaWajibPajak: 'TEST',
          tahunBayar: '2026',
          tanggalBayar: '',
          statusBayar: 'Lunas',
        );
        expect(paidLunas.isPaid, isTrue);
      },
    );

    test(
      'isValidNop and NOP region segment helpers accurately validate and extract parts',
      () {
        expect(isValidNop('320520000401701540'), isTrue);
        expect(isValidNop('32.05.200.004.017-0154.0'), isTrue);
        expect(isValidNop('32052000040170154'), isFalse); // 17 digits
        expect(isValidNop('17154'), isFalse); // shorthand

        const nop = '320520000401701540';
        expect(nopPropinsi(nop), '32');
        expect(nopKabupaten(nop), '05');
        expect(nopKecamatan(nop), '200');
        expect(nopKelurahan(nop), '004');
        expect(nopBlok(nop), '017');
        expect(nopWilayah(nop), '0154');
      },
    );

    test('buildMonthGroups aggregates payments into 12 months', () {
      final murni = sampleRecords.where((r) => !r.isTargetPemda).toList();
      final months = DhkpGrafikAnalytics.buildMonthGroups(murni);
      expect(months, hasLength(12));
      // March (index 2) has 100,000
      expect(months[2].label, 'Mar');
      expect(months[2].lunasNominal, 100000);
      expect(months[2].lunasPct, 100.0);
    });

    test('groupData groups by Blok when groupByDusun is false and sorts', () {
      final records = [
        sampleRecords[0], // Blok 001, paid 100,000
        sampleRecords[1], // Blok 001, unpaid 300,000
        const BlokRecord(
          nop: '320520000400200010',
          namaWajibPajak: 'WAWAN',
          tahunBayar: '2026',
          tanggalBayar: '2026-05-10',
          jumlahPbb: '500000',
          statusBayar: 'Sudah Bayar',
        ),
      ];

      final groupsDesc = DhkpGrafikAnalytics.groupData(
        records,
        hasMultiDusun: false,
        groupByDusun: false,
        sortMode: GrafikSortMode.tertinggi,
        sortValueFn: (g) => g.lunasNominal.toDouble(),
      );

      expect(groupsDesc, hasLength(2));
      expect(groupsDesc.first.label, 'Blok 2');
      expect(groupsDesc.first.lunasNominal, 500000);
      expect(groupsDesc.last.label, 'Blok 1');
      expect(groupsDesc.last.lunasNominal, 100000);
    });

    test(
      'ComboBarLineTrendPainter paints bars and trend line without error',
      () {
        final painter = ComboBarLineTrendPainter(
          data: List.filled(12, 100000),
          counts: List.filled(12, 5),
          monthNames: DhkpGrafikAnalytics.monthNames,
          maxVal: 200000,
          progress: 1.0,
          barColor1: Colors.blue.shade600,
          barColor2: Colors.blue.shade900,
          lineColor: const Color(0xFFDC2626),
          isDark: false,
          selectedIndex: 2,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        expect(
          () => painter.paint(canvas, const Size(400, 220)),
          returnsNormally,
        );
        final picture = recorder.endRecording();
        picture.dispose();
      },
    );

    test(
      'ColumnChartGridPainter paints gridlines and Y-axis scale without error',
      () {
        final painter = ColumnChartGridPainter(
          maxVal: 100.0,
          isDark: false,
          topOffset: 28.0,
          bottomOffset: 48.0,
          leftMargin: 42.0,
          rightMargin: 8.0,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        expect(
          () => painter.paint(canvas, const Size(800, 250)),
          returnsNormally,
        );
        final picture = recorder.endRecording();
        picture.dispose();
      },
    );

    test(
      'SlantedLabelPainter paints rotated and horizontal label without error',
      () {
        final painter = SlantedLabelPainter(
          label: 'Blok 1',
          rotate: true,
          isSelected: false,
          isDark: false,
          color1: Colors.green,
          fontSize: 9.0,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        expect(
          () => painter.paint(canvas, const Size(24, 52)),
          returnsNormally,
        );
        final picture = recorder.endRecording();
        picture.dispose();

        final painterHorizontal = SlantedLabelPainter(
          label: 'Dusun 1',
          rotate: false,
          isSelected: true,
          isDark: true,
          color1: Colors.teal,
          fontSize: 10.0,
        );
        final recorder2 = PictureRecorder();
        final canvas2 = Canvas(recorder2);
        expect(
          () => painterHorizontal.paint(canvas2, const Size(120, 26)),
          returnsNormally,
        );
        final picture2 = recorder2.endRecording();
        picture2.dispose();
      },
    );

    testWidgets(
      'renderDhkpColumnBars renders 41 blocks without overflow in fitScreen mode',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final groups41 = List.generate(41, (i) {
          final lunas = (i * 2) % 50;
          return DhkpGroupInfo(
            label: 'Blok ${i + 1}',
            totalNop: 50,
            lunasNop: lunas,
            belumBayarNop: 50 - lunas,
            totalNominal: 1000000,
            lunasNominal: lunas * 20000,
            belumBayarNominal: (50 - lunas) * 20000,
            lunasPct: (lunas / 50.0) * 100.0,
            lunasNopPct: (lunas / 50.0) * 100.0,
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 900,
                  child: renderDhkpColumnBars(
                    groups: groups41,
                    valueExtractor: (g) => g.lunasPct,
                    maxVal: 100.0,
                    topLabelExtractor: (g) =>
                        '${g.lunasPct.toStringAsFixed(1)}%',
                    subLabelExtractor: (g) => '${g.lunasNop}/${g.totalNop}',
                    color1: Colors.green.shade400,
                    color2: Colors.green.shade700,
                    isDark: false,
                    selectedItemLabel: 'Blok 6',
                    animationValue: 1.0,
                    onSelectLabel: (_) {},
                    fitScreen: true,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Tooltip), findsNWidgets(41));
        expect(find.byType(CustomPaint), findsWidgets);
        // In fitScreen mode on 900px, it fits without horizontal scrolling
        expect(find.byType(DhkpScrollableBars), findsNothing);
      },
    );

    testWidgets(
      'renderDhkpColumnBars renders DhkpScrollableBars with scrollbar and supports mouse dragging',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final groups41 = List.generate(
          41,
          (i) => DhkpGroupInfo(
            label: 'Blok ${i + 1}',
            totalNop: 50,
            lunasNop: 25,
            belumBayarNop: 25,
            totalNominal: 1000000,
            lunasNominal: 500000,
            belumBayarNominal: 500000,
            lunasPct: 50.0,
            lunasNopPct: 50.0,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 900,
                  child: renderDhkpColumnBars(
                    groups: groups41,
                    valueExtractor: (g) => g.lunasPct,
                    maxVal: 100.0,
                    topLabelExtractor: (g) =>
                        '${g.lunasPct.toStringAsFixed(1)}%',
                    subLabelExtractor: (g) => '${g.lunasNop}/${g.totalNop}',
                    color1: Colors.green.shade400,
                    color2: Colors.green.shade700,
                    isDark: false,
                    selectedItemLabel: null,
                    animationValue: 1.0,
                    onSelectLabel: (_) {},
                    fitScreen: false, // Explicit scrollable mode
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(DhkpScrollableBars), findsOneWidget);
        expect(find.byType(Scrollbar), findsOneWidget);

        // Verify dragging with mouse gesture
        await tester.drag(
          find.byType(DhkpScrollableBars),
          const Offset(-200, 0),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Tooltip), findsWidgets);
      },
    );

    testWidgets(
      'DhkpGrafikView updates data immediately when year changes without switching views',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const records2026 = [
          BlokRecord(
            nop: '320520000400100010',
            namaWajibPajak: 'WARGA 2026',
            tahunBayar: '2026',
            tanggalBayar: '2026-01-01',
            jumlahPbb: '100000',
            statusBayar: 'Sudah Bayar',
            alamatObjek: 'KP. SUKAMAJU',
          ),
        ];

        const records2025 = [
          BlokRecord(
            nop: '320520000400100020',
            namaWajibPajak: 'WARGA 2025 A',
            tahunBayar: '2025',
            tanggalBayar: '2025-01-01',
            jumlahPbb: '200000',
            statusBayar: 'Sudah Bayar',
            alamatObjek: 'KP. SUKAMAJU',
          ),
          BlokRecord(
            nop: '320520000400100030',
            namaWajibPajak: 'WARGA 2025 B',
            tahunBayar: '2025',
            tanggalBayar: '',
            jumlahPbb: '200000',
            statusBayar: 'Belum Bayar',
            alamatObjek: 'KP. SUKAMAJU',
          ),
        ];

        var changedYear = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(
                records: records2026,
                selectedTahun: '2026',
                onTahunChanged: (y) => changedYear = y,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Total 1 NOP (100% lunas) for 2026
        expect(find.text('1 dari 1 objek'), findsWidgets);
        expect(find.text('100.0%'), findsWidgets);

        // Rebuild with 2025 records and selectedTahun: '2025'
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(
                records: records2025,
                selectedTahun: '2025',
                onTahunChanged: (y) => changedYear = y,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Data 2025 must immediately display 2 NOP (50% lunas) without requiring view toggle
        expect(find.text('1 dari 2 objek'), findsWidgets);
        expect(find.text('50.0%'), findsWidgets);
        expect(changedYear, isEmpty);
      },
    );

    test(
      'groupData falls back to lunasNopPct when belumNominal is 0 but unpaid records exist',
      () {
        final mixedRecords = [
          const BlokRecord(
            nop: '320520000400100010',
            namaWajibPajak: 'LUNAS',
            tahunBayar: '2026',
            tanggalBayar: '2026-03-01',
            jumlahPbb: '50000',
            statusBayar: 'Sudah Bayar',
          ),
          const BlokRecord(
            nop: '320520000400100020',
            namaWajibPajak: 'BELUM 1',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: '0',
            statusBayar: 'Belum Bayar',
          ),
          const BlokRecord(
            nop: '320520000400100030',
            namaWajibPajak: 'BELUM 2',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: '0',
            statusBayar: 'Belum Bayar',
          ),
        ];

        final groups = DhkpGrafikAnalytics.groupData(
          mixedRecords,
          hasMultiDusun: false,
          groupByDusun: false,
        );

        expect(groups, hasLength(1));
        final g = groups.first;
        expect(g.totalNop, 3);
        expect(g.lunasNop, 1);
        expect(g.belumBayarNop, 2);
        expect(g.lunasNominal, 50000);
        expect(g.belumBayarNominal, 0);
        expect(g.lunasPct, closeTo(33.33, 0.1));
        expect(g.lunasNopPct, closeTo(33.33, 0.1));
      },
    );

    test(
      'ComboBarLineTrendPainter paints smoothly across progressive animation steps and edge cases',
      () {
        final data = <int>[
          0,
          150000,
          420000,
          80000,
          0,
          500000,
          310000,
          0,
          220000,
          640000,
          480000,
          710000,
        ];
        final counts = <int>[0, 2, 4, 1, 0, 5, 3, 0, 2, 7, 5, 8];

        for (final p in [0.0, 0.25, 0.65, 1.0]) {
          final painter = ComboBarLineTrendPainter(
            data: data,
            counts: counts,
            monthNames: DhkpGrafikAnalytics.monthNames,
            maxVal: 710000,
            progress: p,
            lineColor: const Color(0xFF7C3AED),
            isDark: p == 0.65,
            selectedIndex: p >= 0.65 ? 5 : null,
            hoveredIndex: p == 0.25 ? 2 : null,
            tahunLabel: '2026',
          );
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          expect(
            () => painter.paint(canvas, const Size(480, 236)),
            returnsNormally,
          );
          recorder.endRecording().dispose();
        }

        // Edge cases: seluruh bulan bernilai 0, 1 titik, dan list kosong
        for (final edgeData in [
          List<int>.filled(12, 0),
          <int>[100000],
          <int>[],
        ]) {
          final edgePainter = ComboBarLineTrendPainter(
            data: edgeData,
            counts: List<int>.filled(edgeData.length, 0),
            monthNames: DhkpGrafikAnalytics.monthNames,
            maxVal: 0,
            progress: 0.75,
            lineColor: const Color(0xFFA78BFA),
            isDark: true,
          );
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          expect(
            () => edgePainter.paint(canvas, const Size(420, 236)),
            returnsNormally,
          );
          recorder.endRecording().dispose();
        }

        final pA = ComboBarLineTrendPainter(
          data: data,
          counts: counts,
          monthNames: DhkpGrafikAnalytics.monthNames,
          maxVal: 710000,
          progress: 0.4,
          lineColor: const Color(0xFF7C3AED),
          isDark: false,
        );
        final pB = ComboBarLineTrendPainter(
          data: data,
          counts: counts,
          monthNames: DhkpGrafikAnalytics.monthNames,
          maxVal: 710000,
          progress: 0.8,
          lineColor: const Color(0xFF7C3AED),
          isDark: false,
          hoveredIndex: 3,
        );
        expect(pB.shouldRepaint(pA), isTrue);
      },
    );

    testWidgets(
      'DhkpTrendLineChart beranimasi bertahap dari awal ke akhir dan menghormati Reduced Motion',
      (tester) async {
        final groups = List<DhkpGroupInfo>.generate(12, (i) {
          final nom = i.isEven ? (i + 1) * 100000 : (i + 1) * 45000;
          return DhkpGroupInfo(
            label: DhkpGrafikAnalytics.monthNames[i],
            totalNop: i + 1,
            lunasNop: i + 1,
            belumBayarNop: 0,
            lunasNominal: nom,
            belumBayarNominal: 0,
            totalNominal: nom,
            lunasPct: 8.3,
            lunasNopPct: 8.3,
          );
        });

        // 1. Animasi normal: mulai dari 0 lalu mengalir halus menuju 1.0
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: DhkpTrendLineChart(
                  monthGroups: groups,
                  maxMonthVal: 1200000,
                  isDark: false,
                  selectedItemLabel: null,
                  onSelectLabel: (_) {},
                  tahun: '2026',
                ),
              ),
            ),
          ),
        );

        double currentProgress() {
          final customPaint = tester.widget<CustomPaint>(
            find.descendant(
              of: find.byType(DhkpTrendLineChart),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint && w.painter is ComboBarLineTrendPainter,
              ),
            ),
          );
          return (customPaint.painter! as ComboBarLineTrendPainter).progress;
        }

        expect(currentProgress(), lessThan(0.05));
        await tester.pump(const Duration(milliseconds: 500));
        final midProgress = currentProgress();
        expect(midProgress, greaterThan(0.15));
        expect(midProgress, lessThan(0.99));

        await tester.pumpAndSettle();
        expect(currentProgress(), equals(1.0));
        expect(
          find.text('Garis Tren: Penerimaan Bulanan (Jan - Des)'),
          findsOneWidget,
        );
        expect(find.text('Batang: Uang Masuk'), findsNothing);

        // 2. Reduced Motion: langsung selesai 1.0 tanpa menunggu animasi
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: SizedBox(
                  width: 600,
                  child: DhkpTrendLineChart(
                    monthGroups: groups,
                    maxMonthVal: 1200000,
                    isDark: true,
                    selectedItemLabel: null,
                    onSelectLabel: (_) {},
                    tahun: '2026',
                  ),
                ),
              ),
            ),
          ),
        );
        expect(currentProgress(), equals(1.0));
      },
    );

    testWidgets(
      'DhkpGrafikView tab Tren menampilkan garis tren tanpa batang dan merespons sentuhan bulan',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final trendRecords = [
          const BlokRecord(
            nop: '320520000400100010',
            namaWajibPajak: 'ASEP',
            tahunBayar: '2026',
            tanggalBayar: '2026-01-12',
            jumlahPbb: '150000',
            statusBayar: 'Sudah Bayar',
          ),
          const BlokRecord(
            nop: '320520000400100020',
            namaWajibPajak: 'BUDI',
            tahunBayar: '2026',
            tanggalBayar: '2026-04-20',
            jumlahPbb: '350000',
            statusBayar: 'Sudah Bayar',
          ),
          const BlokRecord(
            nop: '320520000400100030',
            namaWajibPajak: 'CITRA',
            tahunBayar: '2026',
            tanggalBayar: '2026-09-05',
            jumlahPbb: '225000',
            statusBayar: 'Sudah Bayar',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(
                records: trendRecords,
                selectedTahun: '2026',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pindah ke tab Tren Pembayaran
        final trenTabFinder = find.text(DhkpGrafikTab.trenBulanan.label);
        await tester.ensureVisible(trenTabFinder);
        await tester.tap(trenTabFinder);
        await tester.pumpAndSettle();

        expect(
          find.text('Grafik Garis Tren Pembayaran Bulanan'),
          findsOneWidget,
        );
        expect(find.text('Garis Tren'), findsOneWidget);
        expect(find.text('Batang: Uang Masuk'), findsNothing);
        expect(find.text('Diagram Batang & Garis Tren Bulanan'), findsNothing);
        expect(find.byIcon(Icons.fit_screen_rounded), findsNothing);
        expect(find.byIcon(Icons.open_with_rounded), findsNothing);

        // Ketuk area grafik untuk memilih bulan dan membuka banner detail
        final trendChartFinder = find.byType(DhkpTrendLineChart);
        expect(trendChartFinder, findsOneWidget);
        await tester.tapAt(tester.getCenter(trendChartFinder));
        await tester.pumpAndSettle();
        expect(find.textContaining('Capaian:'), findsOneWidget);
      },
    );
  });

  group('Multi-Line Trend, Se-Desa, Anti-Spaghetti & 1-Kecamatan', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await DusunData.instance.clearScope();
      await DusunData.instance.setDusuns(DusunData.defaultBobojongDusuns);
    });

    tearDown(() async {
      await DusunData.instance.clearScope();
    });

    List<BlokRecord> buildFullVillageMultiYearRecords({
      List<String> years = const [
        '2026',
        '2025',
        '2024',
        '2023',
        '2022',
        '2021',
      ],
      String kecCode = '200',
      String kelCode = '004',
    }) {
      final list = <BlokRecord>[];
      for (int yIdx = 0; yIdx < years.length; yIdx++) {
        final year = years[yIdx];
        for (final dusun in dusunList) {
          for (int bIdx = 0; bIdx < dusun.bloks.length; bIdx++) {
            final blok = dusun.bloks[bIdx];
            final blokInt = int.tryParse(blok) ?? (bIdx + 1);
            final month = ((bIdx + yIdx) % 12) + 1;
            final nominal = (dusun.number * 100000) + (blokInt * 10000);
            list.add(
              BlokRecord(
                nop: '3205$kecCode$kelCode${blok}00010',
                namaWajibPajak: 'WP $kelCode $blok $year',
                tahunBayar: year,
                tanggalBayar: '$year-${month.toString().padLeft(2, '0')}-15',
                jumlahPbb: '$nominal',
                statusBayar: 'Sudah Bayar',
              ),
            );
          }
        }
      }
      return list;
    }

    test(
      'buildYearComparisonSeries caps at max 5 years with primary solid and dashed comparison lines',
      () {
        final recs = buildFullVillageMultiYearRecords(
          years: const ['2026', '2025', '2024', '2023', '2022', '2021', '2020'],
        );
        final series = DhkpGrafikAnalytics.buildYearComparisonSeries(
          entityRecords: recs,
          primaryYear: '2026',
          compareYears: const [
            '2026',
            '2025',
            '2024',
            '2023',
            '2022',
            '2021',
            '2020',
          ],
          isDark: false,
          maxYears: 5,
        );

        expect(series, hasLength(5));
        expect(series.map((s) => s.label).toList(), [
          '2026',
          '2025',
          '2024',
          '2023',
          '2022',
        ]);
        expect(series.first.isPrimary, isTrue);
        expect(series.first.isDashed, isFalse);
        for (final prev in series.skip(1)) {
          expect(prev.isPrimary, isFalse);
          expect(prev.isDashed, isTrue);
        }
      },
    );

    test(
      'buildMultiDusunMonthlySeries returns 5 Kadus series and buildBlokMonthlySeries caps Semua Blok while showing Dusun 3 blocks',
      () {
        final recs = buildFullVillageMultiYearRecords(years: const ['2026']);

        final dusunSeries = DhkpGrafikAnalytics.buildMultiDusunMonthlySeries(
          records: recs,
          tahun: '2026',
          isDark: false,
        );
        expect(dusunSeries, hasLength(dusunList.length));
        expect(dusunSeries.map((s) => s.label).toList(), [
          for (final d in dusunList) 'Dusun ${d.number}',
        ]);

        final top5Bloks = DhkpGrafikAnalytics.buildBlokMonthlySeries(
          records: recs,
          tahun: '2026',
          isDark: false,
          mode: DhkpAllBlokTrendMode.top5,
        );
        expect(top5Bloks, hasLength(5));
        for (int i = 0; i < top5Bloks.length - 1; i++) {
          expect(
            top5Bloks[i].totalNominal,
            greaterThanOrEqualTo(top5Bloks[i + 1].totalNominal),
          );
        }

        final bottom5Bloks = DhkpGrafikAnalytics.buildBlokMonthlySeries(
          records: recs,
          tahun: '2026',
          isDark: true,
          mode: DhkpAllBlokTrendMode.bottom5,
        );
        expect(bottom5Bloks, hasLength(5));
        for (int i = 0; i < bottom5Bloks.length - 1; i++) {
          expect(
            bottom5Bloks[i].totalNominal,
            lessThanOrEqualTo(bottom5Bloks[i + 1].totalNominal),
          );
        }

        final eightBloks = dusunByNumber(3)!.bloks.take(8).toSet();
        final customBloks = DhkpGrafikAnalytics.buildBlokMonthlySeries(
          records: recs,
          tahun: '2026',
          isDark: false,
          mode: DhkpAllBlokTrendMode.custom,
          customBloks: eightBloks,
          maxCustomBloks: 6,
        );
        expect(customBloks, hasLength(6));

        final dusun3Series = DhkpGrafikAnalytics.buildBlokMonthlySeries(
          records: recs,
          tahun: '2026',
          isDark: false,
          dusunNumber: 3,
        );
        expect(dusun3Series, hasLength(dusunByNumber(3)!.bloks.length));
      },
    );

    test(
      'resolvePrimaryKecamatanCode locks to 1 kecamatan, buildDesaMonthlySeries caps at 5 desas, and groupData supports Se-Desa & Per-Desa',
      () {
        final multiKecRecs = <BlokRecord>[];
        for (final kel in ['001', '002', '003', '004', '005', '006']) {
          for (int i = 0; i < 3; i++) {
            multiKecRecs.add(
              BlokRecord(
                nop: '3205200${kel}001000${i}0',
                namaWajibPajak: 'WP $kel $i',
                tahunBayar: '2026',
                tanggalBayar: '2026-0${i + 1}-10',
                jumlahPbb: '${(int.parse(kel)) * 100000}',
                statusBayar: 'Sudah Bayar',
              ),
            );
          }
        }
        // Tambah data kecamatan kedua yang jauh lebih sedikit
        for (final kel in ['001', '002']) {
          multiKecRecs.add(
            BlokRecord(
              nop: '3205201${kel}00100010',
              namaWajibPajak: 'WP KEC LAIN',
              tahunBayar: '2026',
              tanggalBayar: '2026-02-10',
              jumlahPbb: '999000',
              statusBayar: 'Sudah Bayar',
            ),
          );
        }

        final primaryKec = DhkpGrafikAnalytics.resolvePrimaryKecamatanCode(
          multiKecRecs,
        );
        expect(primaryKec, '200');

        final desasInPrimary = DhkpGrafikAnalytics.resolveDesaCodesInKecamatan(
          multiKecRecs,
          primaryKec,
        );
        expect(desasInPrimary, hasLength(6));

        final kecOnly = multiKecRecs
            .where((r) => nopKecamatan(r.nop) == primaryKec)
            .toList();
        final desaSeries = DhkpGrafikAnalytics.buildDesaMonthlySeries(
          records: kecOnly,
          tahun: '2026',
          isDark: false,
          maxDesas: 5,
        );
        expect(desaSeries, hasLength(5));

        final seDesaGroup = DhkpGrafikAnalytics.groupData(
          kecOnly,
          hasMultiDusun: true,
          groupByDusun: true,
          seDesaMode: true,
          singleEntityLabel: 'Se-Desa Test',
        );
        expect(seDesaGroup, hasLength(1));
        expect(seDesaGroup.first.label, 'Se-Desa Test');
        expect(seDesaGroup.first.totalNop, kecOnly.length);

        final perDesaGroups = DhkpGrafikAnalytics.groupData(
          kecOnly,
          hasMultiDusun: false,
          groupByDusun: false,
          groupByDesa: true,
        );
        expect(perDesaGroups, hasLength(6));
      },
    );

    test(
      'ComboBarLineTrendPainter paints multi-series solid+dashed, dense 12 lines, focus highlight, and hidden series cleanly',
      () {
        final multiSeries = <DhkpTrendSeries>[
          for (int i = 0; i < 12; i++)
            DhkpTrendSeries(
              id: 'blok:${i + 1}',
              label: 'Blok ${i + 1}',
              monthlyNominal: List<int>.generate(
                12,
                (m) => (12 - i) * 50000 + m * 15000,
              ),
              monthlyCounts: List<int>.filled(12, i + 1),
              totalNominal: (12 - i) * 700000,
              totalCount: 12 * (i + 1),
              color: DhkpGrafikAnalytics.trendSeriesPalette(
                isDark: false,
              )[i % 12],
              isPrimary: i == 0,
              isDashed: i > 0 && i < 4,
            ),
        ];

        for (final focused in [null, 'blok:8']) {
          for (final hidden in [
            <String>{},
            {'blok:1', 'blok:2'},
          ]) {
            final painter = ComboBarLineTrendPainter(
              data: multiSeries.first.monthlyNominal,
              counts: multiSeries.first.monthlyCounts,
              monthNames: DhkpGrafikAnalytics.monthNames,
              maxVal: 1000000,
              progress: focused == null ? 0.65 : 1.0,
              lineColor: const Color(0xFF7C3AED),
              isDark: focused != null,
              hoveredIndex: 4,
              tahunLabel: '2026',
              seriesList: multiSeries,
              focusedSeriesId: focused,
              hiddenSeriesIds: hidden,
            );
            final recorder = PictureRecorder();
            final canvas = Canvas(recorder);
            expect(
              () => painter.paint(canvas, const Size(540, 236)),
              returnsNormally,
            );
            recorder.endRecording().dispose();
          }
        }
      },
    );

    testWidgets(
      'DhkpTrendLineChart legend chips focus and toggle visibility without resetting draw progress',
      (tester) async {
        final seriesList = [
          DhkpTrendSeries(
            id: 'dusun:1',
            label: 'Dusun 1',
            monthlyNominal: List<int>.filled(12, 200000),
            monthlyCounts: List<int>.filled(12, 2),
            totalNominal: 2400000,
            totalCount: 24,
            color: Colors.purple,
            isPrimary: true,
          ),
          DhkpTrendSeries(
            id: 'dusun:2',
            label: 'Dusun 2',
            monthlyNominal: List<int>.filled(12, 350000),
            monthlyCounts: List<int>.filled(12, 3),
            totalNominal: 4200000,
            totalCount: 36,
            color: Colors.blue,
          ),
          DhkpTrendSeries(
            id: 'dusun:3',
            label: 'Dusun 3',
            monthlyNominal: List<int>.filled(12, 150000),
            monthlyCounts: List<int>.filled(12, 1),
            totalNominal: 1800000,
            totalCount: 12,
            color: Colors.teal,
            isDashed: true,
          ),
        ];

        final dummyMonths = List<DhkpGroupInfo>.generate(
          12,
          (i) => DhkpGroupInfo(
            label: DhkpGrafikAnalytics.monthNames[i],
            totalNop: 6,
            lunasNop: 6,
            belumBayarNop: 0,
            lunasNominal: 700000,
            belumBayarNominal: 0,
            totalNominal: 700000,
            lunasPct: 8.3,
            lunasNopPct: 8.3,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 640,
                child: DhkpTrendLineChart(
                  monthGroups: dummyMonths,
                  maxMonthVal: 700000,
                  isDark: false,
                  selectedItemLabel: null,
                  onSelectLabel: (_) {},
                  tahun: '2026',
                  seriesList: seriesList,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        ComboBarLineTrendPainter getPainter() {
          final cp = tester.widget<CustomPaint>(
            find.descendant(
              of: find.byType(DhkpTrendLineChart),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint && w.painter is ComboBarLineTrendPainter,
              ),
            ),
          );
          return cp.painter! as ComboBarLineTrendPainter;
        }

        expect(getPainter().progress, 1.0);
        expect(find.text('Dusun 1'), findsOneWidget);
        expect(find.text('Dusun 2'), findsOneWidget);
        expect(find.text('Dusun 3'), findsOneWidget);

        // Ketuk Dusun 2 untuk fokus tanpa memutar ulang animasi dari 0
        await tester.tap(find.text('Dusun 2'));
        await tester.pump();
        expect(getPainter().focusedSeriesId, 'dusun:2');
        expect(getPainter().progress, 1.0);
        expect(find.text('Reset Fokus'), findsOneWidget);

        // Sembunyikan Dusun 1 melalui ikon mata pertama
        await tester.tap(find.byIcon(Icons.visibility_rounded).first);
        await tester.pump();
        expect(getPainter().hiddenSeriesIds, contains('dusun:1'));
        expect(find.text('Tampilkan Semua'), findsOneWidget);

        // Pulihkan semua lewat tombol Tampilkan Semua
        await tester.tap(find.text('Tampilkan Semua'));
        await tester.pump();
        expect(getPainter().hiddenSeriesIds, isEmpty);
        expect(getPainter().focusedSeriesId, isNull);
      },
    );

    testWidgets(
      'DhkpGrafikView removes redundant year bars, enforces Single-Axis Rule, and supports 1-year bottom-right footer comparison',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({
          'dhkp_grafik_group_by_dusun': false,
        });
        final recs = buildFullVillageMultiYearRecords();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(records: recs, selectedTahun: '2026'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        ComboBarLineTrendPainter trendPainter() {
          final cp = tester.widget<CustomPaint>(
            find.descendant(
              of: find.byType(DhkpTrendLineChart),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint && w.painter is ComboBarLineTrendPainter,
              ),
            ),
          );
          return cp.painter! as ComboBarLineTrendPainter;
        }

        // Bilah tahun cepat & banner pembanding lama sudah dihapus (tahun diambil dari filter atas)
        expect(find.text('Tahun:'), findsNothing);
        expect(find.text('Pilih Tahun Pembanding:'), findsNothing);

        // Masuk ke tab Tren Pembayaran
        final trenTab = find.text(DhkpGrafikTab.trenBulanan.label);
        await tester.ensureVisible(trenTab);
        await tester.tap(trenTab);
        await tester.pumpAndSettle();

        // 1. Default: Semua Dusun menampilkan 5 garis (Dusun 1-5) & tombol Bandingkan di footer grafik
        expect(find.text('Semua Blok'), findsNothing);
        expect(
          find.text('Grafik Garis Tren per Dusun (Kadus)'),
          findsOneWidget,
        );
        expect(trendPainter().seriesList, hasLength(dusunList.length));
        final footerCompareBtn = find.descendant(
          of: find.byType(DhkpTrendLineChart),
          matching: find.text('Bandingkan'),
        );
        expect(footerCompareBtn, findsOneWidget);

        // 2. Drill-down Dusun 3: menampilkan blok di dalam Dusun 3 (12 garis)
        final dusun3Chip = find.text('Dusun 3').first;
        await tester.ensureVisible(dusun3Chip);
        await tester.tap(dusun3Chip);
        await tester.pumpAndSettle();

        expect(
          find.text('Grafik Tren Pembayaran Dusun 3 (Per Blok)'),
          findsOneWidget,
        );
        expect(
          trendPainter().seriesList,
          hasLength(dusunByNumber(3)!.bloks.length),
        );

        // 3. Aktifkan perbandingan 1 tahun via tombol Bandingkan di pojok kanan bawah grafik
        await tester.ensureVisible(footerCompareBtn);
        await tester.tap(footerCompareBtn);
        await tester.pumpAndSettle();

        expect(find.text('Tren 2026 vs 2025 (Total Dusun 3)'), findsOneWidget);
        expect(trendPainter().seriesList, hasLength(2));
        expect(trendPainter().seriesList!.first.label, '2026');
        expect(trendPainter().seriesList!.first.isPrimary, isTrue);
        expect(trendPainter().seriesList!.first.isDashed, isFalse);
        expect(trendPainter().seriesList![1].label, '2025');
        expect(trendPainter().seriesList![1].isDashed, isTrue);

        // 4. Ganti tahun pembanding (2025 -> 2022) melalui menu dropdown pojok kanan bawah
        final activeCompareSelector = find.descendant(
          of: find.byType(DhkpTrendLineChart),
          matching: find.text('vs 2025'),
        );
        await tester.ensureVisible(activeCompareSelector);
        await tester.tap(activeCompareSelector);
        await tester.pumpAndSettle();

        final pick2022 = find.text('vs 2022').last;
        await tester.tap(pick2022);
        await tester.pumpAndSettle();

        expect(find.text('Tren 2026 vs 2022 (Total Dusun 3)'), findsOneWidget);
        expect(trendPainter().seriesList, hasLength(2));
        expect(trendPainter().seriesList![1].label, '2022');

        // 5. Jika dropdown Tahun di atas berubah ke 2022 saat membandingkan, pembanding otomatis pindah ke 2021
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(records: recs, selectedTahun: '2022'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Tren 2022 vs 2021 (Total Dusun 3)'), findsOneWidget);
        expect(trendPainter().seriesList, hasLength(2));

        // Kembalikan ke tahun 2026 lalu hentikan perbandingan dengan tombol close (X)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(records: recs, selectedTahun: '2026'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final closeCompareBtn = find.byTooltip('Hentikan perbandingan tahun');
        await tester.ensureVisible(closeCompareBtn);
        await tester.tap(closeCompareBtn);
        await tester.pumpAndSettle();

        expect(
          trendPainter().seriesList,
          hasLength(dusunByNumber(3)!.bloks.length),
        );

        // 6. Kembali ke Semua Dusun lalu aktifkan Bandingkan -> otomatis beralih ke Se-Desa (Single-Axis Rule)
        final semuaDusunChip = find.text('Semua Dusun');
        await tester.ensureVisible(semuaDusunChip);
        await tester.tap(semuaDusunChip);
        await tester.pumpAndSettle();
        expect(trendPainter().seriesList, hasLength(dusunList.length));

        await tester.ensureVisible(footerCompareBtn);
        await tester.tap(footerCompareBtn);
        await tester.pumpAndSettle();

        expect(find.text('Tren 2026 vs 2025 (Se-Desa)'), findsOneWidget);
        expect(trendPainter().seriesList, hasLength(2));

        // 7. Pastikan UI Semua Blok / Pilih Blok sudah dihapus sepenuhnya
        expect(find.text('Semua Blok'), findsNothing);
        expect(find.text('Grafik Garis Tren Semua Blok'), findsNothing);
        expect(find.text('Pilih Blok (Maks. 6)'), findsNothing);
      },
    );

    testWidgets(
      'DhkpGrafikView locks multi-desa dataset to 1 Kecamatan and supports Se-Kecamatan, Per Desa & Desa drill-down',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final recs = <BlokRecord>[
          // Kecamatan 200 (mayoritas: 3 desa berbeda)
          ...buildFullVillageMultiYearRecords(
            years: const ['2026', '2025'],
            kecCode: '200',
            kelCode: '001',
          ),
          ...buildFullVillageMultiYearRecords(
            years: const ['2026', '2025'],
            kecCode: '200',
            kelCode: '002',
          ),
          ...buildFullVillageMultiYearRecords(
            years: const ['2026', '2025'],
            kecCode: '200',
            kelCode: '003',
          ),
          // Kecamatan 201 (minoritas: harus disaring oleh batas 1 kecamatan)
          const BlokRecord(
            nop: '320520100700100010',
            namaWajibPajak: 'WP KEC LAIN',
            tahunBayar: '2026',
            tanggalBayar: '2026-04-10',
            jumlahPbb: '500000',
            statusBayar: 'Sudah Bayar',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(records: recs, selectedTahun: '2026'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Maks. 1 Kec'), findsOneWidget);
        expect(find.text('Se-Kecamatan'), findsOneWidget);
        expect(find.text('Per Desa'), findsOneWidget);
        // Desa dari kecamatan 201 tidak masuk
        expect(
          find.text(DhkpGrafikAnalytics.formatDesaLabel('007')),
          findsNothing,
        );

        // Buka tab Tren Pembayaran -> Per Desa menampilkan 3 seri desa
        final trenTab = find.text(DhkpGrafikTab.trenBulanan.label);
        await tester.ensureVisible(trenTab);
        await tester.tap(trenTab);
        await tester.pumpAndSettle();

        expect(find.text('Grafik Tren Pembayaran Per Desa'), findsOneWidget);
        final cp = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(DhkpTrendLineChart),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is ComboBarLineTrendPainter,
            ),
          ),
        );
        expect(
          (cp.painter! as ComboBarLineTrendPainter).seriesList,
          hasLength(3),
        );

        // Drill-down ke desa pertama di kecamatan 200
        final desaChip = find
            .text(DhkpGrafikAnalytics.formatDesaLabel('001'))
            .first;
        await tester.ensureVisible(desaChip);
        await tester.tap(desaChip);
        await tester.pumpAndSettle();
        expect(find.text('Dalam Desa:'), findsOneWidget);
        expect(find.text('Se-Desa'), findsOneWidget);
      },
    );

    testWidgets(
      'DhkpGrafikView shows bottom-right comparison control in trenBulanan for 1-year data and alerts user when tapped',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        SharedPreferences.setMockInitialValues({});
        final recs = buildFullVillageMultiYearRecords(years: const ['2026']);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(records: recs, selectedTahun: '2026'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final trenTab = find.text(DhkpGrafikTab.trenBulanan.label);
        await tester.ensureVisible(trenTab);
        await tester.tap(trenTab);
        await tester.pumpAndSettle();

        expect(find.text('Semua Blok'), findsNothing);
        expect(find.text('Tahun:'), findsNothing);
        // Tombol Bandingkan berada di pojok kanan bawah footer grafik tren
        final comparePill = find.descendant(
          of: find.byType(DhkpTrendLineChart),
          matching: find.text('Bandingkan'),
        );
        expect(comparePill, findsOneWidget);
        await tester.ensureVisible(comparePill);
        await tester.tap(comparePill);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Data perbandingan tahun belum tersedia di database. Membutuhkan minimal 2 tahun data.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'DhkpTrendLineChart tracks hoverY & selectedY and ComboBarLineTrendPainter renders horizontal crosshair without errors',
      (tester) async {
        final seriesList = [
          DhkpTrendSeries(
            id: 'dusun:1',
            label: 'Dusun 1',
            monthlyNominal: List<int>.generate(12, (i) => (i + 1) * 100000),
            monthlyCounts: List<int>.filled(12, 2),
            totalNominal: 7800000,
            totalCount: 24,
            color: Colors.purple,
            isPrimary: true,
          ),
          DhkpTrendSeries(
            id: 'dusun:2',
            label: 'Dusun 2',
            monthlyNominal: List<int>.filled(12, 300000),
            monthlyCounts: List<int>.filled(12, 1),
            totalNominal: 3600000,
            totalCount: 12,
            color: Colors.blue,
          ),
        ];

        final dummyMonths = List<DhkpGroupInfo>.generate(
          12,
          (i) => DhkpGroupInfo(
            label: DhkpGrafikAnalytics.monthNames[i],
            totalNop: 3,
            lunasNop: 3,
            belumBayarNop: 0,
            lunasNominal: (i + 1) * 100000 + 300000,
            belumBayarNominal: 0,
            totalNominal: (i + 1) * 100000 + 300000,
            lunasPct: 8.3,
            lunasNopPct: 8.3,
          ),
        );

        String? selectedLabel;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setModalState) => SizedBox(
                  width: 640,
                  child: DhkpTrendLineChart(
                    monthGroups: dummyMonths,
                    maxMonthVal: 1500000,
                    isDark: false,
                    selectedItemLabel: selectedLabel,
                    onSelectLabel: (lbl) => setModalState(() {
                      selectedLabel = selectedLabel == lbl ? null : lbl;
                    }),
                    tahun: '2026',
                    seriesList: seriesList,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Finder chartPaintFinder() => find.descendant(
          of: find.byType(DhkpTrendLineChart),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ComboBarLineTrendPainter,
          ),
        );

        ComboBarLineTrendPainter getPainter() =>
            tester.widget<CustomPaint>(chartPaintFinder()).painter!
                as ComboBarLineTrendPainter;

        expect(getPainter().hoverY, isNull);
        expect(getPainter().selectedY, isNull);

        final rect = tester.getRect(chartPaintFinder());
        final targetPoint = Offset(
          rect.left + rect.width * 0.5,
          rect.center.dy,
        );

        // Hover mouse pada grafik -> hoverY terisi lalu bersih saat keluar
        final mouseGesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await mouseGesture.addPointer(location: Offset.zero);
        addTearDown(mouseGesture.removePointer);
        await mouseGesture.moveTo(targetPoint);
        await tester.pump();

        expect(getPainter().hoveredIndex, isNotNull);
        expect(getPainter().hoverY, isNotNull);

        await mouseGesture.moveTo(const Offset(1, 1));
        await tester.pump();
        expect(getPainter().hoverY, isNull);

        // Tap pada titik grafik -> selectedIndex & selectedY terisi
        await tester.tapAt(targetPoint);
        await tester.pump();
        expect(selectedLabel, isNotNull);
        expect(getPainter().selectedIndex, isNotNull);
        expect(getPainter().selectedY, isNotNull);

        // Gambar langsung pada Canvas untuk memastikan garis horizontal crosshair tidak melempar error
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        getPainter().paint(canvas, const Size(640, 260));
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
        picture.dispose();
      },
    );
  });

  group('Semi-Circular Gauge & Mini Sparkline KPI Cards', () {
    final multiYearRecords = <BlokRecord>[
      // 2026: 3 records across Jan, Mar, Jul (2 paid, 1 unpaid) -> 75% nominal
      const BlokRecord(
        nop: '320520000400100010',
        namaWajibPajak: 'WAJIB PAJAK A',
        tahunBayar: '2026',
        tanggalBayar: '2026-01-10',
        jumlahPbb: '150000',
        statusBayar: 'Sudah Bayar',
        alamatObjek: 'KP. SUKAMAJU',
      ),
      const BlokRecord(
        nop: '320520000400200020',
        namaWajibPajak: 'WAJIB PAJAK B',
        tahunBayar: '2026',
        tanggalBayar: '2026-03-18',
        jumlahPbb: '150000',
        statusBayar: 'Sudah Bayar',
        alamatObjek: 'KP. SUKAMAJU',
      ),
      const BlokRecord(
        nop: '320520000400500030',
        namaWajibPajak: 'WAJIB PAJAK C',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: '100000',
        statusBayar: 'Belum Bayar',
        alamatObjek: 'KP. BATULAYANG',
      ),
      // 2025: 3 records (1 paid, 2 unpaid) -> 50% nominal (150k paid / 300k target)
      const BlokRecord(
        nop: '320520000400100010',
        namaWajibPajak: 'WAJIB PAJAK A',
        tahunBayar: '2025',
        tanggalBayar: '2025-02-11',
        jumlahPbb: '150000',
        statusBayar: 'Sudah Bayar',
        alamatObjek: 'KP. SUKAMAJU',
      ),
      const BlokRecord(
        nop: '320520000400200020',
        namaWajibPajak: 'WAJIB PAJAK B',
        tahunBayar: '2025',
        tanggalBayar: '',
        jumlahPbb: '150000',
        statusBayar: 'Belum Bayar',
        alamatObjek: 'KP. SUKAMAJU',
      ),
    ];

    test(
      'computes real sparklines, YoY deltas, and domain-accurate Belum Bayar favorability',
      () {
        final recs2026 = multiYearRecords
            .where((r) => r.tahunBayar == '2026')
            .toList();
        final recs2025 = multiYearRecords
            .where((r) => r.tahunBayar == '2025')
            .toList();
        final groups2026 = DhkpGrafikAnalytics.groupData(
          recs2026,
          hasMultiDusun: true,
          groupByDusun: true,
        );

        final gauge = DhkpGrafikAnalytics.buildGaugeSummary(
          scopeTitle: 'Desa Bobojong',
          tahun: '2026',
          paidNominal: 300000,
          targetNominal: 400000,
          paidCount: 2,
          totalCount: 3,
          achievedPct: 75.0,
          objPct: 66.7,
          previousYearRecords: recs2025,
          previousYearLabel: '2025',
        );
        expect(gauge.achievedPct, 75.0);
        expect(gauge.deltaText, '+25.0% vs 2025');
        expect(gauge.deltaIsFavorable, isTrue);

        final pendapatanStats = DhkpGrafikAnalytics.buildHighlightStats(
          activeTab: DhkpGrafikTab.pendapatan,
          totalNop: 3,
          sudahBayarCount: 2,
          belumBayarCount: 1,
          sudahBayarNominal: 300000,
          belumBayarNominal: 100000,
          totalNominalTarget: 400000,
          lunasNominalPct: 75.0,
          lunasNopPct: 66.7,
          records: recs2026,
          tahun: '2026',
          previousYearRecords: recs2025,
          previousYearLabel: '2025',
          groups: groups2026,
        );
        // Pendapatan Masuk: 300k vs 150k (+100% vs 2025) + cumulative monthly sparkline
        expect(pendapatanStats[0].sparklinePoints, isNotNull);
        expect(pendapatanStats[0].sparklinePoints!.length, greaterThanOrEqualTo(2));
        expect(pendapatanStats[0].deltaText, '+100% vs 2025');
        expect(pendapatanStats[0].deltaIsFavorable, isTrue);

        // Belum Masuk: 100k vs 150k (-33.3% vs 2025) -> decrease is favorable (green)!
        expect(pendapatanStats[2].deltaText, '-33.3% vs 2025');
        expect(pendapatanStats[2].deltaIsFavorable, isTrue);
      },
    );

    testWidgets(
      'renders Semi-Circular Gauge and Sparklines without overflow across 360dp/1280dp, AMOLED dark, and Reduced Motion',
      (tester) async {
        SharedPreferences.setMockInitialValues({});

        Future<void> pumpViewport(
          Size size, {
          required Brightness brightness,
          bool amoled = false,
          bool disableAnimations = false,
        }) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          final scheme = brightness == Brightness.dark
              ? ColorScheme.fromSeed(
                  seedColor: Colors.teal,
                  brightness: Brightness.dark,
                  surface: amoled ? Colors.black : const Color(0xFF14181F),
                )
              : ColorScheme.fromSeed(
                  seedColor: Colors.teal,
                  brightness: Brightness.light,
                );

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(colorScheme: scheme, useMaterial3: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: disableAnimations,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: DhkpGrafikView(
                  records: multiYearRecords,
                  selectedTahun: '2026',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(DhkpSemiCircularGaugeCard), findsOneWidget);
          expect(find.text('REALISASI'), findsOneWidget);
          expect(find.text('75.0%'), findsWidgets);
          expect(find.text('+25.0% vs 2025'), findsWidgets);
          expect(tester.takeException(), isNull);
        }

        // Mobile 360dp Light Mode
        await pumpViewport(
          const Size(360, 780),
          brightness: Brightness.light,
        );
        // Desktop 1280dp Dark AMOLED Mode + Reduced Motion
        await pumpViewport(
          const Size(1280, 820),
          brightness: Brightness.dark,
          amoled: true,
          disableAnimations: true,
        );
      },
    );

    testWidgets(
      'restarts KPI numbers, Semi-Circular Gauge, and chart values from 0 smoothly over 1.5s when data changes',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        SharedPreferences.setMockInitialValues({});

        Widget buildHarness(String tahun) {
          return MaterialApp(
            home: Scaffold(
              body: DhkpGrafikView(
                records: multiYearRecords,
                selectedTahun: tahun,
              ),
            ),
          );
        }

        double readGaugePct() {
          final pctFinder = find.descendant(
            of: find.byType(DhkpSemiCircularGaugeCard),
            matching: find.byWidgetPredicate(
              (w) => w is Text && (w.data ?? '').endsWith('%'),
            ),
          );
          final text = tester.widget<Text>(pctFinder.first).data!;
          return double.parse(text.replaceAll('%', ''));
        }

        // 1. Render awal tahun 2026 -> mulai dari 0, pelan di awal, selesai 75.0%
        await tester.pumpWidget(buildHarness('2026'));
        expect(readGaugePct(), closeTo(0.0, 0.1));
        expect(find.text('Masuk: Rp 0'), findsOneWidget);
        expect(find.text('0.0%'), findsWidgets);

        await tester.pump(const Duration(milliseconds: 250));
        expect(readGaugePct(), lessThan(15.0));

        await tester.pump(const Duration(milliseconds: 500));
        final mid2026 = readGaugePct();
        expect(mid2026, greaterThan(25.0));
        expect(mid2026, lessThan(55.0));

        await tester.pumpAndSettle();
        expect(readGaugePct(), closeTo(75.0, 0.1));

        // 2. Ubah tahun ke 2025 -> nilai langsung reset ke 0 lagi lalu lerp halus ke 50.0%
        await tester.pumpWidget(buildHarness('2025'));
        expect(readGaugePct(), closeTo(0.0, 0.1));
        expect(find.text('Masuk: Rp 0'), findsOneWidget);
        expect(find.text('0.0%'), findsWidgets);

        await tester.pump(const Duration(milliseconds: 250));
        expect(readGaugePct(), lessThan(12.0));

        await tester.pump(const Duration(milliseconds: 500));
        final mid2025 = readGaugePct();
        expect(mid2025, greaterThan(15.0));
        expect(mid2025, lessThan(40.0));

        await tester.pumpAndSettle();
        expect(readGaugePct(), closeTo(50.0, 0.1));
      },
    );
  });
}
