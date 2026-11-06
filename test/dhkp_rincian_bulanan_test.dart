import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/dhkp_grafik_analytics.dart';
import 'package:cek_pbb_app/dhkp/dhkp_rincian_bulanan_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DhkpGrafikAnalytics Monthly Helpers Tests', () {
    final records = [
      BlokRecord(
        nop: '320520000402200010',
        namaWajibPajak: 'AHMAD',
        tahunBayar: '2026',
        tanggalBayar: '2026-07-15 14:30:00',
        jumlahPbb: 'Rp 50.000',
        statusBayar: 'Sudah Bayar',
      ),
      BlokRecord(
        nop: '320520000402200020',
        namaWajibPajak: 'BUDI',
        tahunBayar: '2026',
        tanggalBayar: '2026-07-20 09:15:22',
        jumlahPbb: 'Rp 100.000',
        statusBayar: 'Sudah Bayar',
      ),
      BlokRecord(
        nop: '320520000402200030',
        namaWajibPajak: 'CECEP',
        tahunBayar: '2026',
        tanggalBayar: '2026-08-01 10:00:00',
        jumlahPbb: 'Rp 75.000',
        statusBayar: 'Sudah Bayar',
      ),
      BlokRecord(
        nop: '320520000402200040',
        namaWajibPajak: 'DEDI',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 25.000',
        statusBayar: 'Belum Bayar', // Belum bayar tidak boleh masuk
      ),
    ];

    test('getPaidRecordsForMonth correctly filters and sorts paid records (default terlama)', () {
      final julyPaid = DhkpGrafikAnalytics.getPaidRecordsForMonth(records, 7);
      expect(julyPaid.length, 2);
      // Urutan default terlama: AHMAD (15 Juli) duluan, baru BUDI (20 Juli)
      expect(julyPaid[0].namaWajibPajak, 'AHMAD');
      expect(julyPaid[1].namaWajibPajak, 'BUDI');

      final augustPaid = DhkpGrafikAnalytics.getPaidRecordsForMonth(records, 8);
      expect(augustPaid.length, 1);
      expect(augustPaid[0].namaWajibPajak, 'CECEP');

      final januaryPaid = DhkpGrafikAnalytics.getPaidRecordsForMonth(records, 1);
      expect(januaryPaid, isEmpty);
    });

    test('getPaidRecordsForMonth and buildMonthGroups exclude cross-year payment dates', () {
      final mixedRecords = [
        ...records,
        BlokRecord(
          nop: '320520000402200050',
          namaWajibPajak: 'EKO (2025 date)',
          tahunBayar: '2026',
          tanggalBayar: '2025-07-10 11:00:00', // Anomaly: payment date in 2025
          jumlahPbb: 'Rp 60.000',
          statusBayar: 'Sudah Bayar',
        ),
      ];

      final julyPaid2026 = DhkpGrafikAnalytics.getPaidRecordsForMonth(
        mixedRecords,
        7,
        tahun: '2026',
      );
      // EKO should NOT be included in July 2026!
      expect(julyPaid2026.length, 2);
      expect(julyPaid2026.any((r) => r.namaWajibPajak == 'EKO (2025 date)'), isFalse);

      final monthGroups2026 = DhkpGrafikAnalytics.buildMonthGroups(
        mixedRecords,
        tahun: '2026',
      );
      // July total: 50.000 + 100.000 = 150.000 (excluding 60.000 from 2025)
      expect(monthGroups2026[6].lunasNominal, 150000);
      expect(monthGroups2026[6].totalNop, 2);
    });

    test('formatTanggalJamBayar formats dates with time and date without time', () {
      final withTime = DhkpGrafikAnalytics.formatTanggalJamBayar('2026-07-15 14:30:00');
      expect(withTime, '15 Juli 2026, 14:30:00 WIB');

      final withoutTime = DhkpGrafikAnalytics.formatTanggalJamBayar('2026-07-15');
      expect(withoutTime, '15 Juli 2026');

      final slashFormat = DhkpGrafikAnalytics.formatTanggalJamBayar('15/07/2026 09:10:00');
      expect(slashFormat, '15 Juli 2026, 09:10:00 WIB');
    });
  });

  group('DhkpRincianBulananSheet Widget Tests', () {
    final records = [
      BlokRecord(
        nop: '320520000402200010',
        namaWajibPajak: 'SITI AMINAH',
        tahunBayar: '2026',
        tanggalBayar: '2026-07-15 14:30:00',
        jumlahPbb: 'Rp 50.000',
        statusBayar: 'Sudah Bayar',
      ),
      BlokRecord(
        nop: '320520000402200020',
        namaWajibPajak: 'RUDI HERMAWAN',
        tahunBayar: '2026',
        tanggalBayar: '2026-07-20 09:15:22',
        jumlahPbb: 'Rp 100.000',
        statusBayar: 'Sudah Bayar',
      ),
    ];

    testWidgets('renders monthly sheet with headers, buttons, sort button, and filtered cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DhkpRincianBulananSheet(
              allRecords: records,
              monthIndex: 7,
              tahun: '2026',
              isDark: false,
            ),
          ),
        ),
      );

      // Pastikan judul bulan dan tahun tampil
      expect(find.text('Rincian Pembayaran Bulan Juli 2026'), findsOneWidget);
      expect(find.text('2 Objek Pajak • Total Rp. 150.000'), findsOneWidget);

      // Pastikan 3 tombol aksi ada
      expect(find.text('Unduh'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
      expect(find.text('Cetak'), findsOneWidget);

      // Pastikan tombol urutkan ada dengan default 'Terlama'
      expect(find.text('Terlama'), findsOneWidget);

      // Pastikan kedua nama wajib pajak muncul
      expect(find.text('SITI AMINAH'), findsOneWidget);
      expect(find.text('RUDI HERMAWAN'), findsOneWidget);

      // Buka menu pengurutan
      await tester.tap(find.text('Terlama'));
      await tester.pumpAndSettle();

      expect(find.text('Terlama (Awal Bulan)'), findsOneWidget);
      expect(find.text('Terbaru (Akhir Bulan)'), findsOneWidget);
      expect(find.text('Nominal Terbanyak'), findsOneWidget);
      expect(find.text('Nominal Tersedikit'), findsOneWidget);
      expect(find.text('Nomor NOP'), findsOneWidget);
      expect(find.text('Nama WP (A–Z)'), findsOneWidget);

      // Pilih Nominal Terbanyak
      await tester.tap(find.text('Nominal Terbanyak'));
      await tester.pumpAndSettle();

      expect(find.text('Terbanyak'), findsOneWidget);

      // Test fitur pencarian
      await tester.enterText(find.byType(TextField), 'RUDI');
      await tester.pumpAndSettle();

      expect(find.text('RUDI HERMAWAN'), findsOneWidget);
      expect(find.text('SITI AMINAH'), findsNothing);
    });
  });
}
