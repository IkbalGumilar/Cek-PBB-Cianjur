import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/blok_backup_scheduler.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/blok_sync_service.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory mockDriveDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('sync_test_');
    mockDriveDir = Directory('${tempDir.path}/mock_shared_drive');
    await mockDriveDir.create(recursive: true);

    AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
    BlokDataStore.instance.resetForTesting();
    BlokBackupScheduler.instance.resetForTesting();
    BlokSyncService.instance.resetForTesting();
    BlokSyncService.instance.setMockSyncDirectory(mockDriveDir);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    AppStorage.resetForTesting();
    BlokDataStore.instance.resetForTesting();
    BlokBackupScheduler.instance.resetForTesting();
    BlokSyncService.instance.resetForTesting();
  });

  group('BlokChangeRecord - Serialisasi & Enkripsi AES-256-CBC', () {
    test('toJson dan fromJson roundtrip berhasil mempertahankan data', () {
      const record = BlokChangeRecord(
        id: 'change_1001',
        blok: '001',
        nop: '320520000400100010',
        tahunBayar: '2026',
        petugas: 'ahmad_petugas',
        timestamp: 1770000000,
        statusBayar: 'Sudah Bayar',
        tanggalBayar: '2026-05-12',
        catatan: 'Lunas via Bank BJB',
        namaFoto: '320520000400100010.jpg',
        petugasFolder: 'petugas_ahmad_petugas',
        namaWajibPajak: 'Budi Santoso',
        alamatObjek: 'Jl. Raya No. 10',
        alamatWp: 'Kp. Sukamaju',
      );

      final json = record.toJson();
      final fromJson = BlokChangeRecord.fromJson(json);

      expect(fromJson.id, record.id);
      expect(fromJson.blok, record.blok);
      expect(fromJson.nop, record.nop);
      expect(fromJson.tahunBayar, record.tahunBayar);
      expect(fromJson.petugas, record.petugas);
      expect(fromJson.timestamp, record.timestamp);
      expect(fromJson.statusBayar, record.statusBayar);
      expect(fromJson.tanggalBayar, record.tanggalBayar);
      expect(fromJson.catatan, record.catatan);
      expect(fromJson.namaFoto, record.namaFoto);
      expect(fromJson.petugasFolder, record.petugasFolder);
      expect(fromJson.namaWajibPajak, record.namaWajibPajak);
      expect(fromJson.alamatObjek, record.alamatObjek);
      expect(fromJson.alamatWp, record.alamatWp);
    });

    test('toEncryptedBytes menghasilkan magic header CPBB dan IV 16-byte', () {
      const record = BlokChangeRecord(
        id: 'chg_1',
        blok: '002',
        nop: '320520000400200020',
        tahunBayar: '2026',
        petugas: 'siti',
        timestamp: 1770000000,
      );

      final bytes = record.toEncryptedBytes();
      expect(bytes.length, greaterThan(20));
      // Magic bytes: 'C', 'P', 'B', 'B' (0x43, 0x50, 0x42, 0x42)
      expect(bytes[0], 0x43);
      expect(bytes[1], 0x50);
      expect(bytes[2], 0x42);
      expect(bytes[3], 0x42);
    });

    test('fromEncryptedBytes berhasil mendekripsi data yang dienkripsi', () {
      const record = BlokChangeRecord(
        id: 'chg_2',
        blok: '003',
        nop: '320520000400300030',
        tahunBayar: '2026',
        petugas: 'asep',
        timestamp: 1770005000,
        statusBayar: 'Sudah Bayar',
        catatan: 'Catatan rahasia Wajib Pajak',
      );

      final encrypted = record.toEncryptedBytes();
      final decrypted = BlokChangeRecord.fromEncryptedBytes(encrypted);

      expect(decrypted, isNotNull);
      expect(decrypted!.id, 'chg_2');
      expect(decrypted.blok, '003');
      expect(decrypted.nop, '320520000400300030');
      expect(decrypted.statusBayar, 'Sudah Bayar');
      expect(decrypted.catatan, 'Catatan rahasia Wajib Pajak');
    });

    test('fromEncryptedBytes menolak berkas rusak atau tanpa magic header', () {
      // 1. Berkas terlalu pendek
      expect(BlokChangeRecord.fromEncryptedBytes(Uint8List.fromList([1, 2, 3])), isNull);

      // 2. Magic header salah
      final fakeBytes = Uint8List(32);
      fakeBytes[0] = 0x00;
      expect(BlokChangeRecord.fromEncryptedBytes(fakeBytes), isNull);

      // 3. Magic header benar tapi ciphertext invalid
      final broken = Uint8List.fromList([0x43, 0x50, 0x42, 0x42, ...List.filled(28, 0xFF)]);
      expect(BlokChangeRecord.fromEncryptedBytes(broken), isNull);
    });
  });

  group('BlokSyncService - Helper & Sanitasi', () {
    test('sanitizePetugasFolderName membersihkan email menjadi nama folder aman', () {
      final sync = BlokSyncService.instance;
      expect(sync.sanitizePetugasFolderName(''), 'petugas_umum');
      expect(sync.sanitizePetugasFolderName('   '), 'petugas_umum');
      expect(sync.sanitizePetugasFolderName('Ahmad.Petugas@gmail.com'), 'ahmad.petugas');
      expect(sync.sanitizePetugasFolderName('budi+testing@cianjur.go.id'), 'budi_testing');
      expect(sync.sanitizePetugasFolderName('petugas_01'), 'petugas_01');
    });
  });

  group('BlokSyncService - Record & Sync Flow', () {
    test('recordChange membuat file .bin terenkripsi di folder perubahan per-blok dan menyalin foto', () async {
      final sync = BlokSyncService.instance;
      await BlokBackupScheduler.instance.setGoogleAccount('petugas.lapangan@gmail.com');

      // Buat file foto sampel
      final samplePhoto = File('${tempDir.path}/sample_selfie.jpg');
      await samplePhoto.writeAsBytes(utf8.encode('image-bytes-mock-photo'));

      const testRecord = BlokRecord(
        nop: '320520000400500120',
        namaWajibPajak: 'H. Suherman',
        tahunBayar: '2026',
        tanggalBayar: '',
        statusBayar: 'Sudah Bayar',
        catatan: 'Bukti bayar lunas',
      );

      final logFile = await sync.recordChange(
        record: testRecord,
        statusBayar: 'Sudah Bayar',
        catatan: 'Bukti bayar lunas',
        namaFoto: '320520000400500120.jpg',
        sourcePhotoFile: samplePhoto,
      );

      expect(await logFile.exists(), true);
      // File tersimpan di mock_shared_drive/perubahan/blok_005/<id>.bin
      expect(logFile.path, contains('perubahan/blok_005'));
      expect(logFile.path.endsWith('.bin'), true);

      // Pastikan berkas .bin terenkripsi dan dapat didekripsi
      final logBytes = await logFile.readAsBytes();
      final decrypted = BlokChangeRecord.fromEncryptedBytes(logBytes);
      expect(decrypted, isNotNull);
      expect(decrypted!.nop, '320520000400500120');
      expect(decrypted.petugas, 'petugas.lapangan');
      expect(decrypted.petugasFolder, 'petugas_petugas.lapangan');

      // Pastikan foto tersalin ke folder petugas
      final copiedPhoto = File(
        '${mockDriveDir.path}/petugas_petugas.lapangan/photos/320520000400500120.jpg',
      );
      expect(await copiedPhoto.exists(), true);
      expect(await copiedPhoto.readAsString(), 'image-bytes-mock-photo');

      // Pastikan changeId ditandai processed sehingga tidak di-reapply di HP sendiri
      final processed = await sync.getProcessedChangeIds();
      expect(processed.contains(decrypted.id), true);
    });

    test('syncCurrentScope mengunduh perubahan delta terenkripsi dan foto dari folder petugas', () async {
      final sync = BlokSyncService.instance;

      // 1. Simulasikan data awal di BlokDataStore lokal HP penerima
      const initialRecord = BlokRecord(
        nop: '320520000400700010',
        namaWajibPajak: 'Ibu Ratna',
        tahunBayar: '2026',
        tanggalBayar: '',
        statusBayar: 'Belum Bayar',
        catatan: '',
      );
      await BlokDataStore.instance.upsert(initialRecord);

      // 2. Simulasikan petugas lain (petugas_budi) membuat log perubahan di folder Drive bersama
      final blok007Dir = Directory('${mockDriveDir.path}/perubahan/blok_007');
      await blok007Dir.create(recursive: true);

      final budiPhotosDir = Directory('${mockDriveDir.path}/petugas_budi/photos');
      await budiPhotosDir.create(recursive: true);

      // Buat file foto dari petugas budi
      final remotePhoto = File('${budiPhotosDir.path}/320520000400700010.jpg');
      await remotePhoto.writeAsBytes(utf8.encode('budi-photo-evidence-123'));

      // Buat delta record terenkripsi dari petugas budi
      const budiChange = BlokChangeRecord(
        id: 'change_remote_999_320520000400700010_budi',
        blok: '007',
        nop: '320520000400700010',
        tahunBayar: '2026',
        petugas: 'budi',
        timestamp: 1770008888,
        statusBayar: 'Sudah Bayar',
        tanggalBayar: '2026-10-23',
        catatan: 'Diserahkan langsung tunai ke petugas Budi',
        namaFoto: '320520000400700010.jpg',
        petugasFolder: 'petugas_budi',
        namaWajibPajak: 'Ibu Ratna (Updated)',
      );

      final binFile = File('${blok007Dir.path}/${budiChange.id}.bin');
      await binFile.writeAsBytes(budiChange.toEncryptedBytes());

      // 3. Jalankan syncCurrentScope untuk blok 007
      final appliedCount = await sync.syncCurrentScope(blok: '007');
      expect(appliedCount, 1);

      // 4. Verifikasi bahwa data di BlokDataStore lokal terupdate seketika
      final localRecords = await BlokDataStore.instance.loadAll();
      final updated = localRecords.firstWhere((r) => r.nop == '320520000400700010');
      expect(updated.statusBayar, 'Sudah Bayar');
      expect(updated.tanggalBayar, '2026-10-23');
      expect(updated.catatan, 'Diserahkan langsung tunai ke petugas Budi');
      expect(updated.namaFoto, '320520000400700010.jpg');
      expect(updated.namaWajibPajak, 'Ibu Ratna (Updated)');

      // 5. Verifikasi bahwa foto otomatis ditarik dari folder petugas budi ke lokal photosDirectory
      final localPhotosDir = await DhkpPackageHelper.photosDirectory();
      final localFetchedPhoto = File('${localPhotosDir.path}/320520000400700010.jpg');
      expect(await localFetchedPhoto.exists(), true);
      expect(await localFetchedPhoto.readAsString(), 'budi-photo-evidence-123');

      // 6. Jalankan sync kedua kali; hasilnya harus 0 karena changeId sudah diproses
      final secondRunCount = await sync.syncCurrentScope(blok: '007');
      expect(secondRunCount, 0);
    });

    test('syncCurrentScope partisi per blok hanya memindai blok yang diminta', () async {
      final sync = BlokSyncService.instance;

      // Buat log perubahan untuk blok 001 dan blok 002
      final dirBlok1 = Directory('${mockDriveDir.path}/perubahan/blok_001');
      final dirBlok2 = Directory('${mockDriveDir.path}/perubahan/blok_002');
      await dirBlok1.create(recursive: true);
      await dirBlok2.create(recursive: true);

      const chg1 = BlokChangeRecord(
        id: 'chg_blok_1',
        blok: '001',
        nop: '320520000400100099',
        tahunBayar: '2026',
        petugas: 'siti',
        timestamp: 1770001111,
        catatan: 'Catatan Blok 1',
      );
      const chg2 = BlokChangeRecord(
        id: 'chg_blok_2',
        blok: '002',
        nop: '320520000400200099',
        tahunBayar: '2026',
        petugas: 'siti',
        timestamp: 1770002222,
        catatan: 'Catatan Blok 2',
      );

      await File('${dirBlok1.path}/chg_blok_1.bin').writeAsBytes(chg1.toEncryptedBytes());
      await File('${dirBlok2.path}/chg_blok_2.bin').writeAsBytes(chg2.toEncryptedBytes());

      // Sync hanya blok 001
      final applied = await sync.syncCurrentScope(blok: '001');
      expect(applied, 1);

      // Blok 1 sudah diproses, Blok 2 belum diproses
      final processed = await sync.getProcessedChangeIds();
      expect(processed.contains('chg_blok_1'), true);
      expect(processed.contains('chg_blok_2'), false);

      // Sekarang sync semua blok (atau blok 'Semua')
      final appliedAll = await sync.syncCurrentScope(blok: 'Semua');
      expect(appliedAll, 1); // Hanya chg_blok_2 yang baru diproses
    });
  });
}
