import 'dart:ui';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_models.dart';
import 'package:cek_pbb_app/dhkp/dhkp_chart_widgets.dart';
import 'package:cek_pbb_app/dhkp_grafik_view.dart';
import 'package:cek_pbb_app/nop_helper.dart';
import 'package:flutter/material.dart';
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

    test('parsePaymentDate parses ISO and DD-MM-YYYY dates and rejects standalone years', () {
      expect(parsePaymentDate('2026-04-16 14:59:06')?.month, 4);
      expect(parsePaymentDate('16-08-2026')?.month, 8);
      expect(parsePaymentDate('2024'), isNull);
      expect(parsePaymentDate('2025'), isNull);
      expect(parsePaymentDate('2026'), isNull);
      expect(parsePaymentDate('2027'), isNull);
      expect(parsePaymentDate('-'), isNull);
      expect(parsePaymentDate('0'), isNull);
      expect(parsePaymentDate(''), isNull);
    });

    test('BlokRecord.isPaid strictly evaluates payment status and excludes Belum Bayar with date placeholders', () {
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
    });

    test('isValidNop and NOP region segment helpers accurately validate and extract parts', () {
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
    });

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

    test('ComboBarLineTrendPainter paints bars and trend line without error', () {
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
      expect(() => painter.paint(canvas, const Size(400, 220)), returnsNormally);
      final picture = recorder.endRecording();
      picture.dispose();
    });

    test('ColumnChartGridPainter paints gridlines and Y-axis scale without error', () {
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
      expect(() => painter.paint(canvas, const Size(800, 250)), returnsNormally);
      final picture = recorder.endRecording();
      picture.dispose();
    });

    test('SlantedLabelPainter paints rotated and horizontal label without error', () {
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
      expect(() => painter.paint(canvas, const Size(24, 52)), returnsNormally);
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
      expect(() => painterHorizontal.paint(canvas2, const Size(120, 26)), returnsNormally);
      final picture2 = recorder2.endRecording();
      picture2.dispose();
    });

    testWidgets('renderDhkpColumnBars renders 41 blocks without overflow in fitScreen mode', (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final groups41 = List.generate(
        41,
        (i) {
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
        },
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
                  topLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
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
    });

    testWidgets('renderDhkpColumnBars renders DhkpScrollableBars with scrollbar and supports mouse dragging', (tester) async {
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
                  topLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
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
      await tester.drag(find.byType(DhkpScrollableBars), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsWidgets);
    });

    testWidgets('DhkpGrafikView updates data immediately when year changes without switching views', (tester) async {
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
    });

    test('groupData falls back to lunasNopPct when belumNominal is 0 but unpaid records exist', () {
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
    });
  });
}
