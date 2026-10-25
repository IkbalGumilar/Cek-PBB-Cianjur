import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/backup_password_store.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';

const _backupPassword = 'test-password-for-backups';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final secureStorageValues = <String, String>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStorageValues.clear();
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return secureStorageValues[arguments['key']];
        case 'write':
          secureStorageValues[arguments['key'] as String] =
              arguments['value'] as String;
          return null;
        case 'delete':
          secureStorageValues.remove(arguments['key']);
          return null;
        case 'containsKey':
          return secureStorageValues.containsKey(arguments['key']);
        case 'deleteAll':
          secureStorageValues.clear();
          return null;
      }
      return null;
    });
    await BackupPasswordStore.instance.save(_backupPassword);
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

  test('unpackDkhp mendukung berkas .dkhp terenkripsi AES-256-CBC, Target Pemda, Blacklist, dan Catatan', () async {
    // 1. Buat records dengan metadata lengkap
    const recordsToPack = [
      BlokRecord(
        namaWajibPajak: 'HJ. ETI ROHAETI',
        nop: '320520000402600380',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 320.000',
        statusBayar: 'Belum Bayar',
        namaFoto: '320520000402600380.jpg',
        isTargetPemda: true,
        catatan: 'Prioritas Penagihan Target Pemda 2026.',
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
        catatan: 'Nunggak 6 tahun sejak 2020.',
      ),
    ];

    // Buat foto dummy di direktori temp
    final photosDir = Directory('${tempDir.path}/input_photos');
    await photosDir.create();
    final photoFile1 = File('${photosDir.path}/320520000402600380.jpg');
    await photoFile1.writeAsBytes([10, 20, 30, 40]);
    final photoFile2 = File('${photosDir.path}/320520000402600360.jpg');
    await photoFile2.writeAsBytes([50, 60, 70, 80]);

    // 2. Pack ke berkas .dkhp terenkripsi
    final packagePath = '${tempDir.path}/paket_rahasia.dkhp';
    final packedFile = await DhkpPackageHelper.packDkhp(
      outputPath: packagePath,
      records: recordsToPack,
      photosDir: photosDir,
      encrypt: true,
      password: _backupPassword,
    );

    expect(await packedFile.exists(), isTrue);
    final packedBytes = await packedFile.readAsBytes();
    expect(DhkpCrypto.isEncrypted(packedBytes), isTrue);

    // 3. Unpack dan verifikasi data
    final unpackedRecords = await DhkpPackageHelper.unpackDkhp(
      packagePath,
      password: _backupPassword,
    );

    expect(unpackedRecords.length, 2);

    // Record 1: Target Pemda
    final r1 = unpackedRecords[0];
    expect(r1.nop, '320520000402600380');
    expect(r1.namaWajibPajak, 'HJ. ETI ROHAETI');
    expect(r1.isTargetPemda, isTrue);
    expect(r1.catatan, 'Prioritas Penagihan Target Pemda 2026.');
    expect(r1.isPaid, isFalse);
    expect(r1.namaFoto, '320520000402600380.jpg');

    // Record 2: Blacklist
    final r2 = unpackedRecords[1];
    expect(r2.nop, '320520000402600360');
    expect(r2.namaWajibPajak, 'SITI ROHMAH');
    expect(r2.isTargetPemda, isFalse);
    expect(r2.isBlacklist, isTrue);
    expect(r2.catatan, 'Nunggak 6 tahun sejak 2020.');

    // Verifikasi foto tersimpan di folder lokal dhkp_photos
    final photoFound = await DhkpPackageHelper.findPhotoForNop('320520000402600380');
    expect(photoFound, isNotNull);
    expect(await photoFound!.exists(), isTrue);
  });

  test('unpackDkhp tetap kompatibel dengan berkas .dkhp atau .zip lama (tanpa enkripsi)', () async {
    final archive = Archive();

    const csvContent = '''Nama WP,NOP,Tahun Bayar,Tanggal Bayar,Jumlah PBB,Status Bayar,Foto,Target Pemda,Catatan
SUGENG RAHARJO,320520000402600340,2026,,Rp 102.378,Belum Bayar,320520000402600340.jpg,0,
AHMAD SUHADA,320520000402600350,2026,2026-03-15,Rp 45.000,Sudah Bayar,320520000402600350.jpg,0,Lunas transfer
''';
    final csvBytes = utf8.encode(csvContent);
    archive.addFile(ArchiveFile('data.csv', csvBytes.length, csvBytes));

    final zipBytes = ZipEncoder().encode(archive)!;
    final packageFile = File('${tempDir.path}/legacy.dkhp');
    await packageFile.writeAsBytes(zipBytes);

    expect(DhkpCrypto.isEncrypted(zipBytes), isFalse);

    final records = await DhkpPackageHelper.unpackDkhp(packageFile.path);
    expect(records.length, 2);
    expect(records[0].nop, '320520000402600340');
    expect(records[1].catatan, 'Lunas transfer');
  });

  test(
    'interoperabilitas: paket .dkhp AES-GCM dari Python dapat dibuka aplikasi',
    () async {
      final csvFile = File('${tempDir.path}/cli_data.csv');
      await csvFile.writeAsString(
        '''Nama WP,NOP,Tahun Bayar,Tanggal Bayar,Jumlah PBB,Status Bayar,Foto,Target Pemda,Catatan
KUSNADI,320520000402600390,2026,,Rp 210.000,Belum Bayar,,1,Anomali batas tanah
''',
      );
      final outDkhp = '${tempDir.path}/from_python.dkhp';
      final process = await Process.start('python3', [
        'tool/make_dkhp_package.py',
        '--data',
        csvFile.path,
        '--output',
        outDkhp,
        '--password-stdin',
      ]);
      process.stdin.writeln(_backupPassword);
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      expect(exitCode, 0, reason: '$stdout\n$stderr');

      final fileBytes = await File(outDkhp).readAsBytes();
      expect(DhkpCrypto.isEncrypted(fileBytes), isTrue);

      final records = await DhkpPackageHelper.unpackDkhp(
        outDkhp,
        password: _backupPassword,
      );
      expect(records.length, 1);
      expect(records[0].namaWajibPajak, 'KUSNADI');
      expect(records[0].nop, '320520000402600390');
      expect(records[0].isTargetPemda, isTrue);
      expect(records[0].catatan, 'Anomali batas tanah');
    },
  );
  test('BlokDataStore.instance.exportDkhp mengekspor data perubahan ke paket .dkhp dan importCsv memvalidasi sidik jari DHKP dasar', () async {
    await BlokDataStore.instance.clearAll();
    await BlokDataStore.instance.upsertAll(const [
      BlokRecord(
        namaWajibPajak: 'WAJIB PAJAK 1 (BELUM DIUBAH)',
        nop: '320520000402600010',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 50.000',
        statusBayar: 'Belum Bayar',
      ),
      BlokRecord(
        namaWajibPajak: 'WAJIB PAJAK 2 (SUDAH DIUBAH)',
        nop: '320520000402600020',
        tahunBayar: '2026',
        tanggalBayar: '2026-08-17',
        jumlahPbb: 'Rp 75.000',
        statusBayar: 'Sudah Bayar',
        catatan: 'Lunas kolektif RT 02',
      ),
    ]);

    final exportPath = await BlokDataStore.instance.exportDkhp(fileName: 'test_export_backup');
    expect(exportPath, endsWith('.dkhp'));
    expect(File(exportPath).existsSync(), isTrue);

    final rawBytes = await File(exportPath).readAsBytes();
    expect(DhkpCrypto.isEncrypted(rawBytes), isTrue);
    expect(DhkpCrypto.isPasswordProtected(rawBytes), isFalse);

    // Periksa manifest di dalam berkas cadangan: hanya menyimpan 1 perubahan dari 2 NOP dasar
    final manifest = await DhkpPackageHelper.readBackupManifest(exportPath);
    expect(manifest, isNotNull);
    expect(manifest!['isDeltaOnly'], isTrue);
    expect(manifest['baseTotalNop'], 2);
    expect(manifest['changedCount'], 1);
    final changes = manifest['changes'] as List<dynamic>;
    expect(changes.length, 1);
    final firstChange = changes.first as Map<String, dynamic>;
    expect(firstChange['blok'], '026');
    expect(firstChange['nomor'], '0002');
    expect(firstChange.containsKey('nop'), isFalse);

    // Simulasi ganti HP dengan berkas DHKP dasar yang sama (belum ada perubahan di HP baru)
    await BlokDataStore.instance.clearAll();
    await BlokDataStore.instance.upsertAll(const [
      BlokRecord(
        namaWajibPajak: 'WAJIB PAJAK 1 (BELUM DIUBAH)',
        nop: '320520000402600010',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 50.000',
        statusBayar: 'Belum Bayar',
      ),
      BlokRecord(
        namaWajibPajak: 'WAJIB PAJAK 2 (AWAL)',
        nop: '320520000402600020',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 75.000',
        statusBayar: 'Belum Bayar',
      ),
    ]);

    final count = await BlokDataStore.instance.importCsv(
      exportPath,
      requireBaseDhkp: true,
    );
    expect(count, 1);

    final records = await BlokDataStore.instance.loadAll();
    expect(records.length, 2);
    final updatedWp2 = records.firstWhere((r) => r.nop == '320520000402600020');
    expect(updatedWp2.statusBayar, 'Sudah Bayar');
    expect(updatedWp2.catatan, 'Lunas kolektif RT 02');
  });

  test('unpackDkhp menolak pemulihan jika berkas DHKP dasar belum dimuat atau berasal dari desa/berkas DHKP yang berbeda', () async {
    await BlokDataStore.instance.clearAll();
    await BlokDataStore.instance.upsertAll(const [
      BlokRecord(
        namaWajibPajak: 'WP DUSUN 4 A',
        nop: '320520000402600110',
        tahunBayar: '2026',
        tanggalBayar: '2026-04-01',
        jumlahPbb: 'Rp 100.000',
        statusBayar: 'Sudah Bayar',
        catatan: 'Bukti lunas',
      ),
      BlokRecord(
        namaWajibPajak: 'WP DUSUN 4 B',
        nop: '320520000402600120',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 80.000',
        statusBayar: 'Belum Bayar',
      ),
    ]);

    final backupPath = await BlokDataStore.instance.exportDkhp(fileName: 'delta_dusun4');

    // 1. Jika belum ada berkas DHKP sama sekali -> ditolak
    await BlokDataStore.instance.clearAll();
    expect(
      () => BlokDataStore.instance.importCsv(backupPath, requireBaseDhkp: true),
      throwsA(isA<DhkpBackupValidationException>()),
    );

    // 2. Jika berkas DHKP yang dimuat berbeda (sidik jari NOP tidak cocok) -> ditolak
    await BlokDataStore.instance.upsertAll(const [
      BlokRecord(
        namaWajibPajak: 'WP DESA LAIN',
        nop: '320520000900100010',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 120.000',
        statusBayar: 'Belum Bayar',
      ),
    ]);
    expect(
      () => BlokDataStore.instance.importCsv(backupPath, requireBaseDhkp: true),
      throwsA(isA<DhkpBackupValidationException>()),
    );
  });

  test(
    'enkripsi AES-GCM menolak kata sandi salah dan perubahan data',
    () async {
      final encrypted = await DhkpCrypto.encryptBytes(
        Uint8List.fromList([1, 2, 3, 4]),
        password: _backupPassword,
      );

      expect(DhkpCrypto.isPasswordProtected(encrypted), isTrue);
      expect(
        await DhkpCrypto.decryptBytes(encrypted, password: _backupPassword),
        [1, 2, 3, 4],
      );
      expect(
        () => DhkpCrypto.decryptBytes(
          encrypted,
          password: 'different-backup-password',
        ),
        throwsA(isA<DkhpPasswordException>()),
      );

      encrypted[encrypted.length - 1] ^= 0x01;
      expect(
        () => DhkpCrypto.decryptBytes(encrypted, password: _backupPassword),
        throwsA(isA<DkhpPasswordException>()),
      );
    },
  );
}