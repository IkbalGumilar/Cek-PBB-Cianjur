import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/calculator/pbb_calculator_models.dart';
import 'package:cek_pbb_app/dhkp/dhkp_nop_kalkulator_dialog.dart';
import 'package:cek_pbb_app/dhkp/dhkp_target_pacing_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PbbCalculatorHelper Pure Logic Unit Tests', () {
    test('calculateTarget returns correct gap and NOP estimates', () {
      // Pagu 100jt, realisasi 40jt (40%), target 50% (50jt)
      final res = PbbCalculatorHelper.calculateTarget(
        totalKetetapan: 100000000,
        realisasiSaatIni: 40000000,
        targetPersen: 50.0,
        rataRataNominalPerNop: 50000,
      );

      expect(res.targetNominal, equals(50000000));
      expect(res.targetSudahTercapai, isFalse);
      expect(res.kekuranganNominal, equals(10000000));
      expect(res.persenSaatIni, closeTo(40.0, 0.01));
      // 10jt / 50rb = 200 NOP
      expect(res.estimasiNopDibutuhkan, equals(200));
      expect(res.kelebihanNominal, equals(0));
    });

    test('calculateTarget handles already achieved targets', () {
      final res = PbbCalculatorHelper.calculateTarget(
        totalKetetapan: 100000000,
        realisasiSaatIni: 75000000,
        targetPersen: 60.0,
      );

      expect(res.targetSudahTercapai, isTrue);
      expect(res.kekuranganNominal, equals(0));
      expect(res.kelebihanNominal, equals(15000000));
      expect(res.estimasiNopDibutuhkan, equals(0));
    });

    test('calculatePacing computes daily and weekly pacing properly', () {
      final start = DateTime(2026, 8, 1);
      final tempo = DateTime(2026, 8, 31); // 30 hari

      final pacing = PbbCalculatorHelper.calculatePacing(
        sisaNominal: 30000000,
        jatuhTempo: tempo,
        tanggalMulai: start,
      );

      expect(pacing.sudahLewatJatuhTempo, isFalse);
      expect(pacing.sisaHari, equals(30));
      expect(pacing.targetHarian, equals(1000000)); // 30jt / 30 = 1jt
      expect(pacing.targetMingguan, equals(7000000));
    });

    test('calculatePacing flags overdue correctly', () {
      final start = DateTime(2026, 9, 10);
      final tempo = DateTime(2026, 8, 31);

      final pacing = PbbCalculatorHelper.calculatePacing(
        sisaNominal: 10000000,
        jatuhTempo: tempo,
        tanggalMulai: start,
      );

      expect(pacing.sudahLewatJatuhTempo, isTrue);
      expect(pacing.sisaHari, lessThanOrEqualTo(0));
    });

    test('calculateDenda calculates on-time payment (no penalty)', () {
      final tempo = DateTime(2026, 8, 31);
      final bayar = DateTime(2026, 8, 25);

      final denda = PbbCalculatorHelper.calculateDenda(
        pokokPbb: 100000,
        jatuhTempo: tempo,
        rencanaBayar: bayar,
      );

      expect(denda.tepatWaktu, isTrue);
      expect(denda.bulanKeterlambatan, equals(0));
      expect(denda.nominalDenda, equals(0));
      expect(denda.totalBayar, equals(100000));
    });

    test('calculateDenda calculates 1 month penalty when passing deadline', () {
      final tempo = DateTime(2026, 8, 31);
      final bayar = DateTime(2026, 9, 5); // lewat 5 hari -> 1 bulan

      final denda = PbbCalculatorHelper.calculateDenda(
        pokokPbb: 100000,
        jatuhTempo: tempo,
        rencanaBayar: bayar,
        tarifBungaPerBulan: 1.0,
      );

      expect(denda.tepatWaktu, isFalse);
      expect(denda.bulanKeterlambatan, equals(1));
      expect(denda.totalPersenDenda, equals(1.0));
      expect(denda.nominalDenda, equals(1000)); // 1% of 100k
      expect(denda.totalBayar, equals(101000));
    });

    test('calculateDenda respects max 24 months cap', () {
      final tempo = DateTime(2022, 1, 1);
      final bayar = DateTime(2026, 1, 1); // 48 bulan

      final denda = PbbCalculatorHelper.calculateDenda(
        pokokPbb: 50000,
        jatuhTempo: tempo,
        rencanaBayar: bayar,
        tarifBungaPerBulan: 2.0,
        maxBulan: 24,
      );

      expect(denda.bulanKeterlambatan, equals(24));
      expect(denda.totalPersenDenda, equals(48.0)); // 24 * 2% = 48%
      expect(denda.nominalDenda, equals(24000)); // 48% of 50k
      expect(denda.totalBayar, equals(74000));
    });

    test('calculateCicilan computes installments properly for different frequencies', () {
      // 300rb dalam 6 bulan mingguan (6 * 4 = 24x) -> 300rb / 24 = 12.500
      final mingguan = PbbCalculatorHelper.calculateCicilan(
        totalTagihan: 300000,
        frekuensi: 'Mingguan',
        durasiBulan: 6,
      );
      expect(mingguan.jumlahKaliSetoran, equals(24));
      expect(mingguan.nominalPerSetoran, equals(12500));

      // 300rb dalam 3 bulan bulanan (3x) -> 100rb per bulan
      final bulanan = PbbCalculatorHelper.calculateCicilan(
        totalTagihan: 300000,
        frekuensi: 'Bulanan',
        durasiBulan: 3,
      );
      expect(bulanan.jumlahKaliSetoran, equals(3));
      expect(bulanan.nominalPerSetoran, equals(100000));

      // 60rb dalam 1 bulan harian (30x) -> 2.000 per hari
      final harian = PbbCalculatorHelper.calculateCicilan(
        totalTagihan: 60000,
        frekuensi: 'Harian',
        durasiBulan: 1,
      );
      expect(harian.jumlahKaliSetoran, equals(30));
      expect(harian.nominalPerSetoran, equals(2000));
    });

    test('calculateAjb calculates transaction taxes with BPHTB when >= 80 Juta', () {
      // 100m² * 1.000.000 = 100.000.000 (>= 80 jt)
      // PPh 2.5% = 2.500.000
      // PPN 2.5% = 2.500.000
      // BPHTB 5% = 5.000.000
      // Total Biaya Pajak = 10.000.000
      final ajb = PbbCalculatorHelper.calculateAjb(
        luas: 100.0,
        njopPerM2: 1000000,
      );

      expect(ajb.totalNilai, equals(100000000));
      expect(ajb.pph, equals(2500000));
      expect(ajb.ppn, equals(2500000));
      expect(ajb.kenaBphtb, isTrue);
      expect(ajb.bphtb, equals(5000000));
      expect(ajb.totalBiayaPajak, equals(10000000));
    });

    test('calculateAjb calculates transaction taxes without BPHTB when < 80 Juta', () {
      // 50m² * 1.000.000 = 50.000.000 (< 80 jt)
      // PPh 2.5% = 1.250.000
      // PPN 2.5% = 1.250.000
      // BPHTB 5% = 0 (bebas / nihil)
      // Total Biaya Pajak = 2.500.000
      final ajb = PbbCalculatorHelper.calculateAjb(
        luas: 50.0,
        njopPerM2: 1000000,
      );

      expect(ajb.totalNilai, equals(50000000));
      expect(ajb.pph, equals(1250000));
      expect(ajb.ppn, equals(1250000));
      expect(ajb.kenaBphtb, isFalse);
      expect(ajb.bphtb, equals(0));
      expect(ajb.totalBiayaPajak, equals(2500000));
    });

    test('calculateAjb handles exact 80.000.000 boundary', () {
      // 80m² * 1.000.000 = 80.000.000 (tepat 80 jt)
      // PPh 2.5% = 2.000.000
      // PPN 2.5% = 2.000.000
      // BPHTB 5% = 4.000.000
      final ajb = PbbCalculatorHelper.calculateAjb(
        luas: 80.0,
        njopPerM2: 1000000,
      );

      expect(ajb.totalNilai, equals(80000000));
      expect(ajb.kenaBphtb, isTrue);
      expect(ajb.bphtb, equals(4000000));
      expect(ajb.totalBiayaPajak, equals(8000000));
    });

    test('formatWhatsAppAjb generates structured text', () {
      final ajb = PbbCalculatorHelper.calculateAjb(
        luas: 100.0,
        njopPerM2: 1000000,
      );
      final text = PbbCalculatorHelper.formatWhatsAppAjb(
        nop: '32.03.010.001.001-0001.0',
        namaWp: 'Ahmad Subardjo',
        ajbResult: ajb,
      );

      expect(text, contains('SIMULASI BIAYA AKTA JUAL BELI (AJB)'));
      expect(text, contains('32.03.010.001.001-0001.0'));
      expect(text, contains('Ahmad Subardjo'));
      expect(text, contains('PPh'));
      expect(text, contains('PPN'));
      expect(text, contains('BPHTB'));
    });

    test('formatWhatsAppCicilan generates structured text', () {
      final cicilan = PbbCalculatorHelper.calculateCicilan(
        totalTagihan: 120000,
        frekuensi: 'Bulanan',
        durasiBulan: 4,
      );
      final text = PbbCalculatorHelper.formatWhatsAppCicilan(
        nop: '32.03.010.001.001-0002.0',
        namaWp: 'Budi Santoso',
        cicilanResult: cicilan,
      );

      expect(text, contains('SKEMA TABUNGAN / CICILAN PBB-P2'));
      expect(text, contains('Budi Santoso'));
      expect(text, contains('Besaran per Setoran'));
    });

    test('formatWhatsAppTarget generates structured text', () {
      final target = PbbCalculatorHelper.calculateTarget(
        totalKetetapan: 50000000,
        realisasiSaatIni: 20000000,
        targetPersen: 50.0,
      );
      final text = PbbCalculatorHelper.formatWhatsAppTarget(
        namaWilayah: 'Desa Bobojong',
        targetResult: target,
      );

      expect(text, contains('Desa Bobojong'));
      expect(text, contains('Target Sasaran'));
      expect(text, contains('Kekurangan Target'));
    });

    test('PbbTabunganModel handles setor, tarik, and status lunas', () {
      final initial = const PbbTabunganModel(target: 100000);
      expect(initial.isLunas, isFalse);
      expect(initial.sisaKekurangan, equals(100000));
      expect(initial.persentase, equals(0.0));

      final setor1 = initial.setor(
        40000,
        mutasi: const PbbTabunganMutasi(
          nominal: 40000,
          tanggal: '09/11/2026 10:00',
          keterangan: 'Titip panen pertama',
        ),
      );
      expect(setor1.saldo, equals(40000));
      expect(setor1.sisaKekurangan, equals(60000));
      expect(setor1.persentase, equals(40.0));
      expect(setor1.isLunas, isFalse);
      expect(setor1.riwayat.length, equals(1));

      // Tarik dana
      final tarik1 = setor1.tarik(
        10000,
        mutasi: const PbbTabunganMutasi(
          nominal: -10000,
          tanggal: '09/11/2026 12:00',
          keterangan: 'Butuh uang darurat',
        ),
      );
      expect(tarik1.saldo, equals(30000));
      expect(tarik1.sisaKekurangan, equals(70000));
      expect(tarik1.riwayat.length, equals(2));

      // Setor sisa sampai lunas
      final setor2 = tarik1.setor(70000);
      expect(setor2.saldo, equals(100000));
      expect(setor2.sisaKekurangan, equals(0));
      expect(setor2.persentase, equals(100.0));
      expect(setor2.isLunas, isTrue);
    });

    test('PbbTabunganHelper encodes and cleans notes with tabungan tag safely', () {
      const originalHuman = 'Pemilik sering ke luar kota. Rumah dekat pohon beringin.';
      final tabungan = const PbbTabunganModel(
        saldo: 50000,
        target: 100000,
        catatan: 'Cicilan 2x',
      );

      final encoded = PbbTabunganHelper.encodeCatatanWithTabungan(originalHuman, tabungan);
      expect(encoded, contains(originalHuman));
      expect(encoded, contains('[TABUNGAN_PBB:'));
      expect(encoded, contains(':/TABUNGAN_PBB]'));

      // Ekstraksi tabungan dari catatan terenkode
      final extracted = PbbTabunganHelper.extractTabungan(encoded);
      expect(extracted.saldo, equals(50000));
      expect(extracted.target, equals(100000));
      expect(extracted.catatan, equals('Cicilan 2x'));

      // Pembersihan catatan untuk tampilan manusia
      final cleaned = PbbTabunganHelper.cleanCatatan(encoded);
      expect(cleaned, equals(originalHuman));
      expect(cleaned, isNot(contains('[TABUNGAN_PBB:')));

      // Format WhatsApp Tabungan
      final wa = PbbTabunganHelper.formatWhatsAppTabungan(
        nop: '32.03.010.001.001-0001.0',
        namaWp: 'Pak Asep',
        tabungan: extracted,
      );
      expect(wa, contains('BUKTI TABUNGAN / CICILAN PBB-P2'));
      expect(wa, contains('Pak Asep'));
      expect(wa, contains('50%'));
    });
  });

  group('Target & Pacing Dialog Widget Tests', () {
    testWidgets('renders Target & Pacing dialog correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showTargetPacingDialog(
                  ctx,
                  totalKetetapan: 100000000,
                  realisasi: 40000000,
                  totalNop: 500,
                  wilayahTitle: 'Blok 001',
                ),
                child: const Text('Buka Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Dialog'));
      await tester.pumpAndSettle();

      // Memeriksa judul dialog
      expect(find.text('TARGET & PACING REALISASI'), findsOneWidget);
      expect(find.text('Blok 001'), findsOneWidget);

      // Memeriksa persentase chips
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Memeriksa kontrol target & pacing
      expect(find.text('Pilih Target Realisasi:'), findsOneWidget);
      expect(find.text('Pacing Kecepatan Penagihan'), findsOneWidget);

      // Memeriksa tombol aksi
      expect(find.text('Salin Pesan WA'), findsOneWidget);

      // Tutup dialog via icon close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('TARGET & PACING REALISASI'), findsNothing);
    });
  });

  group('DHKP NOP Kalkulator Dialog Widget Tests', () {
    final sampleRecord = BlokRecord(
      nop: '32.03.010.001.001-0001.0',
      namaWajibPajak: 'H. Suherman',
      tahunBayar: '2026',
      tanggalBayar: '-',
      statusBayar: 'Belum Bayar',
      jumlahPbb: 'Rp 150.000',
      luasBumi: '200',
      njopBumi: '500.000',
    );

    testWidgets('renders 3 tabs (Denda, Cicilan, AJB) and switches between them', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showNopKalkulatorDialog(
                  ctx,
                  record: sampleRecord,
                ),
                child: const Text('Buka Kalkulator NOP'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Kalkulator NOP'));
      await tester.pumpAndSettle();

      // Memeriksa judul dialog dan NOP
      expect(find.text('KALKULATOR PAJAK & AKSI DHKP'), findsOneWidget);
      expect(find.textContaining('32.03.010.001.001-0001.0'), findsOneWidget);

      // Memeriksa 3 Tab
      expect(find.text('Denda Pajak'), findsOneWidget);
      expect(find.text('Cicilan Warga'), findsOneWidget);
      expect(find.text('Kalkulator AJB'), findsOneWidget);

      // Tab Denda aktif
      expect(find.text('Pokok Ketetapan PBB (Rp)'), findsOneWidget);

      // Switch ke Tab Cicilan Warga
      await tester.tap(find.text('Cicilan Warga'));
      await tester.pumpAndSettle();
      expect(find.text('CELENGAN / TABUNGAN PBB WARGA'), findsOneWidget);
      expect(find.text('Kelola Setoran & Penarikan Tabungan:'), findsOneWidget);
      expect(find.text('Setor (+)'), findsOneWidget);
      expect(find.text('Tarik (-)'), findsOneWidget);

      // Switch ke Tab Kalkulator AJB
      await tester.tap(find.text('Kalkulator AJB'));
      await tester.pumpAndSettle();
      expect(find.text('Luas Tanah (m²)'), findsOneWidget);
      expect(find.text('NJOP Tanah / m² (Rp)'), findsOneWidget);
      expect(find.text('TOTAL ESTIMASI PAJAK AJB:'), findsOneWidget);
      expect(find.text('PPh (2.5%):'), findsOneWidget);
      expect(find.text('PPN (2.5%):'), findsOneWidget);

      // Tutup dialog
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('KALKULATOR PAJAK & AKSI DHKP'), findsNothing);
    });

    testWidgets('tabungan warga flow: setor, penarikan, dan tombol bayar menyala saat lunas', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool cekTagihanCalled = false;
      BlokRecord? updatedRecord;

      final record = const BlokRecord(
        nop: '320301000100100010',
        namaWajibPajak: 'Ahmad Subardjo',
        tahunBayar: '2026',
        tanggalBayar: '-',
        jumlahPbb: '50.000',
        statusBayar: 'Belum Bayar',
        catatan: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showNopKalkulatorDialog(
                  ctx,
                  record: record,
                  initialTab: 1, // Langsung buka tab Cicilan & Tabungan
                  onCekTagihan: () => cekTagihanCalled = true,
                  onRecordUpdated: (r) => updatedRecord = r,
                ),
                child: const Text('Buka Tabungan'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Tabungan'));
      await tester.pumpAndSettle();

      expect(find.text('CELENGAN / TABUNGAN PBB WARGA'), findsOneWidget);
      // Saldo awal 0, target 50.000
      expect(find.text('Kurang: Rp. 50.000'), findsOneWidget);
      // Tombol bayar belum menyala
      expect(find.text('Buka Cek Tagihan PBB'), findsOneWidget);

      // Setor 25.000 menggunakan chip +25 rb
      await tester.tap(find.text('+25 rb'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Setor (+)'));
      await tester.pumpAndSettle();

      expect(find.text('Kurang: Rp. 25.000'), findsOneWidget);
      expect(updatedRecord, isNotNull);
      expect(updatedRecord!.catatan, contains('[TABUNGAN_PBB:'));

      // Tarik 10.000
      final nominalInput = find.widgetWithText(TextField, 'Nominal Tabungan (Rp)');
      await tester.enterText(nominalInput, '10000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tarik (-)'));
      await tester.pumpAndSettle();

      expect(find.text('Kurang: Rp. 35.000'), findsOneWidget);

      // Setor sisa sampai lunas
      await tester.enterText(nominalInput, '35000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Setor (+)'));
      await tester.pumpAndSettle();

      // Sekarang LUNAS! Tombol bayar menyala
      expect(find.text('LUNAS (100%)'), findsOneWidget);
      expect(find.text('BAYAR PBB SEKARANG (CEK TAGIHAN)'), findsOneWidget);

      // Tekan tombol bayar menyala
      await tester.tap(find.text('BAYAR PBB SEKARANG (CEK TAGIHAN)'));
      await tester.pumpAndSettle();

      expect(cekTagihanCalled, isTrue);
    });

    testWidgets('renders Standalone AJB dialog and updates calculation', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showStandaloneAjbDialog(
                  ctx,
                  initialLuas: 100,
                  initialNjop: 1000000,
                ),
                child: const Text('Buka Standalone AJB'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Standalone AJB'));
      await tester.pumpAndSettle();

      expect(find.text('KALKULATOR AJB & SIMULASI NJOP'), findsOneWidget);
      expect(find.text('Luas Tanah (m²)'), findsOneWidget);
      expect(find.text('NJOP Tanah / m² (Rp)'), findsOneWidget);
      expect(find.text('TOTAL ESTIMASI PAJAK AJB:'), findsOneWidget);
      expect(find.text('Salin Rincian AJB'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('KALKULATOR AJB & SIMULASI NJOP'), findsNothing);
    });
  });
}
