import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/blok_catatan_screen.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/pbb_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  const testSampleRecords = [
    BlokRecord(
      namaWajibPajak: 'SUGENG RAHARJO',
      nop: '320520000402600340',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: 'Rp 102.378',
      statusBayar: 'Belum Bayar',
      namaFoto: '320520000402600340.jpg',
      isTargetPemda: false,
      catatan: '',
      luasBumi: '450 m2',
      luasBangunan: '120 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '350.000,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL PASIR PARAHU',
      alamatWp: 'KP PASIR PARAHU RT 02/05',
      rtObjek: '002',
    ),
    BlokRecord(
      namaWajibPajak: 'AHMAD SUHADA',
      nop: '320520000402600350',
      tahunBayar: '2026',
      tanggalBayar: '2026-03-15',
      jumlahPbb: 'Rp 45.000',
      statusBayar: 'Sudah Bayar',
      namaFoto: '320520000402600350.jpg',
      isTargetPemda: false,
      catatan: 'Lunas via Bank BJB',
      luasBumi: '210 m2',
      luasBangunan: '54 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '250.000,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL CIKANGKUNG',
      alamatWp: 'KP CIKANGKUNG',
      rtObjek: '018',
    ),
    BlokRecord(
      namaWajibPajak: 'SITI ROHMAH',
      nop: '320520000402600360',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: 'Rp 85.500',
      statusBayar: 'Blacklist',
      namaFoto: '320520000402600360.jpg',
      isTargetPemda: false,
      catatan: 'Nunggak 6 tahun sejak 2020. Pemilik tidak di lokasi.',
      luasBumi: '380 m2',
      luasBangunan: '0 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '0,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'BLOK PASIR',
      alamatWp: 'KP PASIR PARAHU',
      rtObjek: '015',
    ),
    BlokRecord(
      namaWajibPajak: 'DUDI KURNIAWAN',
      nop: '320520000402600370',
      tahunBayar: '2026',
      tanggalBayar: '2026-02-20',
      jumlahPbb: 'Rp 150.000',
      statusBayar: 'Sudah Bayar',
      namaFoto: null,
      isTargetPemda: false,
      catatan: '',
      luasBumi: '600 m2',
      luasBangunan: '150 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '400.000,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL UTAMA BOBOJONG',
      alamatWp: 'KP BOBOJONG TENGAH',
      rtObjek: '005',
    ),
    BlokRecord(
      namaWajibPajak: 'H ACEP',
      nop: '320520000402600380',
      tahunBayar: '2026',
      tanggalBayar: '',
      jumlahPbb: 'Rp 320.000',
      statusBayar: 'Belum Bayar',
      namaFoto: '320520000402600380.jpg',
      isTargetPemda: true,
      catatan: 'Prioritas Penagihan Target Pemda 2026.',
      luasBumi: '1438 m2',
      luasBangunan: '0 m2',
      njopBumi: '82.000,00/m2',
      njopBangunan: '0,00/m2',
      kecamatan: 'MANDE',
      kelurahan: 'BOBOJONG',
      alamatObjek: 'JL CIKANGKUNG',
      alamatWp: 'PASIR PARAHU',
      rtObjek: '019',
    ),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('blok_store_test_');
    AppStorage.resetForTesting();
    AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
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
    AppStorage.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BlokRecord & Data DHKP Enhanced Features', () {
    test('BlokRecord mengenali Target Pemda, Blacklist, status pembayaran, foto, catatan, dan format NOP Bapenda', () {
      const record = BlokRecord(
        namaWajibPajak: 'H ACEP',
        nop: '320520000402600380',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 320.000',
        statusBayar: 'Belum Bayar',
        namaFoto: '320520000402600380.jpg',
        isTargetPemda: true,
        catatan: 'Prioritas Penagihan Target Pemda 2026.',
        luasBumi: '1438 m2',
        luasBangunan: '0 m2',
        njopBumi: '82.000,00/m2',
        njopBangunan: '0,00/m2',
        kecamatan: 'MANDE',
        kelurahan: 'BOBOJONG',
        alamatObjek: 'JL CIKANGKUNG',
        alamatWp: 'PASIR PARAHU',
        rtObjek: '019',
      );

      expect(record.isTargetPemda, isTrue);
      expect(record.isBlacklist, isFalse);
      expect(record.isPaid, isFalse);
      expect(record.hasPhoto, isTrue);
      expect(record.catatan, 'Prioritas Penagihan Target Pemda 2026.');
      expect(record.jumlahPbbValue, 320000);
      expect(record.formattedNop, '32.05.200.004.026-0038.0');
      expect(record.luasBumi, '1438 m2');
      expect(record.alamatObjek, 'JL CIKANGKUNG');

      // Uji copyWith untuk penyesuaian nama pemilik sekarang oleh petugas
      final updated = record.copyWith(
        namaWajibPajak: 'H. ACEP (AHLI WARIS DENI)',
        catatan: 'Sudah dikunjungi petugas.',
        statusBayar: 'Sudah Bayar',
        tanggalBayar: '2026-04-01',
      );
      expect(updated.namaWajibPajak, 'H. ACEP (AHLI WARIS DENI)');
      expect(updated.catatan, 'Sudah dikunjungi petugas.');
      expect(updated.isPaid, isTrue);
      expect(updated.isTargetPemda, isTrue);
      expect(updated.formattedNop, '32.05.200.004.026-0038.0');
    });

    test('BlokDataStore saat awal kosong (0 data)', () async {
      final records = await BlokDataStore.instance.loadAll();
      expect(records, isEmpty);
      expect(BlokDataStore.instance.countNotifier.value, 0);
    });

    test('Data DHKP menyertakan data Target Pemda (H ACEP) dan Blacklist lengkap', () async {
      await BlokDataStore.instance.upsertAll(testSampleRecords);
      final records = await BlokDataStore.instance.loadAll();

      expect(records.length, 5);

      final targetPemdaRecords = records.where((r) => r.isTargetPemda).toList();
      expect(targetPemdaRecords.length, 1);
      expect(targetPemdaRecords.first.namaWajibPajak, 'H ACEP');
      expect(targetPemdaRecords.first.jumlahPbbValue, 320000);
      expect(targetPemdaRecords.first.luasBumi, '1438 m2');
      expect(targetPemdaRecords.first.formattedNop, '32.05.200.004.026-0038.0');

      final blacklistRecords = records.where((r) => r.isBlacklist).toList();
      expect(blacklistRecords.length, 1);
      expect(blacklistRecords.first.namaWajibPajak, 'SITI ROHMAH');
      expect(blacklistRecords.first.catatan, contains('Nunggak 6 tahun'));

      final paidRecords = records.where((r) => r.isPaid).toList();
      expect(paidRecords.length, 2);

      final unpaidRecords = records.where((r) => !r.isPaid).toList();
      expect(unpaidRecords.length, 3);
    });

    test('Kalkulasi ringkasan 4 metric (Sudah Bayar, Belum Bayar, Target Pemda, Total Keseluruhan)', () async {
      await BlokDataStore.instance.upsertAll(testSampleRecords);
      final records = await BlokDataStore.instance.loadAll();

      final totalData = records.length;
      final totalTargetPemdaCount = records.where((r) => r.isTargetPemda).length;
      final totalTargetPemdaNominal = records
          .where((r) => r.isTargetPemda)
          .fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

      final totalSudahBayarCount = records.where((r) => r.isPaid && !r.isTargetPemda).length;
      final totalSudahBayarNominal = records
          .where((r) => r.isPaid && !r.isTargetPemda)
          .fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

      final totalBelumBayarCount = records.where((r) => !r.isPaid && !r.isTargetPemda).length;
      final totalBelumBayarNominal = records
          .where((r) => !r.isPaid && !r.isTargetPemda)
          .fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

      // Total keseluruhan hanya menghitung Sudah Bayar dan Belum Bayar desa
      final totalKeseluruhanCount = totalSudahBayarCount + totalBelumBayarCount;
      final totalKeseluruhanNominal = totalSudahBayarNominal + totalBelumBayarNominal;

      expect(totalData, 5);
      expect(totalSudahBayarCount, 2);
      expect(totalSudahBayarNominal, 45000 + 150000); // Ahmad Suhada + Dudi Kurniawan = 195.000

      expect(totalBelumBayarCount, 2);
      expect(totalBelumBayarNominal, 102378 + 85500); // Sugeng + Siti = 187.878 (H Acep adalah Target Pemda)

      expect(totalTargetPemdaCount, 1);
      expect(totalTargetPemdaNominal, 320000); // H Acep

      expect(totalKeseluruhanCount, 4);
      expect(totalKeseluruhanNominal, 195000 + 187878); // 382.878 (tanpa Target Pemda)
    });

    test('Filter DhkpKategoriFilter memfilter kategori data secara presisi', () async {
      expect(DhkpKategoriFilter.values.length, 5);

      await BlokDataStore.instance.upsertAll(testSampleRecords);
      final records = await BlokDataStore.instance.loadAll();

      // Filter Target Pemda
      final targetPemda = records.where((r) => r.isTargetPemda).toList();
      expect(targetPemda.length, 1);
      expect(targetPemda.first.namaWajibPajak, 'H ACEP');

      // Filter Blacklist
      final blacklist = records.where((r) => r.isBlacklist).toList();
      expect(blacklist.length, 1);
      expect(blacklist.first.namaWajibPajak, 'SITI ROHMAH');

      // Filter Sudah Bayar
      final sudahBayar = records.where((r) => r.isPaid && !r.isTargetPemda).toList();
      expect(sudahBayar.length, 2);

      // Filter Belum Bayar
      final belumBayar = records.where((r) => !r.isPaid && !r.isTargetPemda).toList();
      expect(belumBayar.length, 2);
    });

    test('Pembaruan catatan petugas via upsert tersimpan permanen', () async {
      await BlokDataStore.instance.upsertAll(testSampleRecords);
      final records = await BlokDataStore.instance.loadAll();
      final target = records.firstWhere((r) => r.nop == '320520000402600340');

      expect(target.catatan, isEmpty);

      final updatedTarget = target.copyWith(catatan: 'Bangunan roboh terkena gempa');
      await BlokDataStore.instance.upsert(updatedTarget);

      BlokDataStore.instance.resetForTesting();
      final reloaded = await BlokDataStore.instance.loadAll();
      final check = reloaded.firstWhere((r) => r.nop == '320520000402600340');

      expect(check.catatan, 'Bangunan roboh terkena gempa');
    });

    test('updateStatusBayarFromCheck memperbarui data DHKP yang awalnya Belum Bayar menjadi Sudah Bayar serta mempertahankan rincian data', () async {
      await BlokDataStore.instance.upsertAll(testSampleRecords);
      final records = await BlokDataStore.instance.loadAll();
      final target = records.firstWhere((r) => r.nop == '320520000402600340'); // SUGENG RAHARJO, Belum Bayar
      expect(target.isPaid, isFalse);
      expect(target.luasBumi, '450 m2');
      expect(target.luasBangunan, '120 m2');
      expect(target.njopBumi, '82.000,00/m2');
      expect(target.alamatObjek, 'JL PASIR PARAHU');

      // Simulasi Cek Status Bayar dari Bapenda menyatakan Lunas
      final pbbResult = PbbResult(
        'Sudah Bayar (LUNAS 2026-03-20)',
        'Lunas',
        namaWajibPajak: 'SUGENG RAHARJO',
        tanggalBayar: '2026-03-20',
        jumlahPbb: 'Rp 102.378',
      );

      final outcome = await BlokDataStore.instance.updateStatusBayarFromCheck(
        nop: target.nop,
        tahun: target.tahunBayar,
        result: pbbResult,
      );

      expect(outcome, isNotNull);
      expect(outcome!.wasExisting, isTrue);
      expect(outcome.changedFromUnpaid, isTrue);
      expect(outcome.record.isPaid, isTrue);
      expect(outcome.record.tanggalBayar, '2026-03-20');
      // Pastikan seluruh metadata DHKP tetap utuh tidak terhapus
      expect(outcome.record.luasBumi, '450 m2');
      expect(outcome.record.luasBangunan, '120 m2');
      expect(outcome.record.njopBumi, '82.000,00/m2');
      expect(outcome.record.alamatObjek, 'JL PASIR PARAHU');

      // Verifikasi saat dimuat ulang dari disk
      BlokDataStore.instance.resetForTesting();
      final reloaded = await BlokDataStore.instance.loadAll();
      final updatedInDb = reloaded.firstWhere((r) => r.nop == target.nop);
      expect(updatedInDb.isPaid, isTrue);
      expect(updatedInDb.statusBayar, 'Sudah Bayar');
      expect(updatedInDb.tanggalBayar, '2026-03-20');
      expect(updatedInDb.luasBumi, '450 m2');
    });
  });
}
