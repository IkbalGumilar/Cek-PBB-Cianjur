import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_catatan_models.dart';
import 'package:cek_pbb_app/dhkp/dhkp_grafik_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('parsePaymentDate parses ISO and DD-MM-YYYY dates', () {
      expect(parsePaymentDate('2026-04-16 14:59:06')?.month, 4);
      expect(parsePaymentDate('16-08-2026')?.month, 8);
      expect(parsePaymentDate('2026'), isNull);
      expect(parsePaymentDate(''), isNull);
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
  });
}
