import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/backup_password_store.dart';
import 'package:cek_pbb_app/base_preferences_store.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_csv_codec.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/dusun_data.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_generate_dialog.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_generate_service.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_sync_service.dart';
import 'package:cek_pbb_app/nop_helper.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:cek_pbb_app/wilayah_kerja_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BaseSecureStore.clearTestMemoryStore();
    BaseSecureStore.simulateStorageFailureForTesting = false;
  });

  tearDown(() {
    BaseSecureStore.simulateStorageFailureForTesting = false;
    BaseSecureStore.clearTestMemoryStore();
  });

  group('BlokCsvCodec', () {
    test('encodeRecords and decodeDatabaseCsv preserve all 18 columns', () {
      const sample = [
        BlokRecord(
          nop: '320520000401701540',
          namaWajibPajak: 'AHMAD SULAEMAN',
          tahunBayar: '2026',
          tanggalBayar: '2026-04-10',
          jumlahPbb: 'Rp. 125.000',
          statusBayar: 'Sudah Bayar',
          namaFoto: 'foto_017_0154.jpg',
          isTargetPemda: false,
          catatan: 'Lunas lewat RT',
          luasBumi: '120',
          luasBangunan: '45',
          njopBumi: '6000000',
          njopBangunan: '9000000',
          kecamatan: 'MANDE',
          kelurahan: 'BOBOJONG',
          alamatObjek: 'KP. BOBOJONG',
          alamatWp: 'JL. RAYA MANDE',
          rtObjek: '002',
        ),
        BlokRecord(
          nop: '320520000403005840',
          namaWajibPajak: 'PT PERKEBUNAN NUSANTARA',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: 'Rp. 2.500.000',
          statusBayar: 'Belum Bayar',
          isTargetPemda: true,
          catatan: 'Target Pemda',
        ),
      ];

      final csv = BlokCsvCodec.encodeRecords(sample);
      final decoded = BlokCsvCodec.decodeDatabaseCsv(csv);

      expect(decoded, hasLength(2));
      expect(decoded[0].nop, '320520000401701540');
      expect(decoded[0].namaWajibPajak, 'AHMAD SULAEMAN');
      expect(decoded[0].tahunBayar, '2026');
      expect(decoded[0].tanggalBayar, '2026-04-10');
      expect(decoded[0].jumlahPbb, 'Rp. 125.000');
      expect(decoded[0].statusBayar, 'Sudah Bayar');
      expect(decoded[0].namaFoto, 'foto_017_0154.jpg');
      expect(decoded[0].isTargetPemda, isFalse);
      expect(decoded[0].catatan, 'Lunas lewat RT');
      expect(decoded[0].luasBumi, '120');
      expect(decoded[0].luasBangunan, '45');
      expect(decoded[0].njopBumi, '6000000');
      expect(decoded[0].njopBangunan, '9000000');
      expect(decoded[0].kecamatan, 'MANDE');
      expect(decoded[0].kelurahan, 'BOBOJONG');
      expect(decoded[0].alamatObjek, 'KP. BOBOJONG');
      expect(decoded[0].alamatWp, 'JL. RAYA MANDE');
      expect(decoded[0].rtObjek, '002');

      expect(decoded[1].nop, '320520000403005840');
      expect(decoded[1].isTargetPemda, isTrue);
      expect(decoded[1].statusBayar, 'Belum Bayar');
    });

    test('decodeDatabaseCsv supports legacy 4-column CSV', () {
      const legacyCsv =
          'Nama WP,NOP,Tahun Bayar,Tanggal Bayar\r\n'
          'BUDI SANTOSO,320520000401701540,2025,2025-05-01\r\n';
      final decoded = BlokCsvCodec.decodeDatabaseCsv(legacyCsv);
      expect(decoded, hasLength(1));
      expect(decoded.first.namaWajibPajak, 'BUDI SANTOSO');
      expect(decoded.first.nop, '320520000401701540');
      expect(decoded.first.statusBayar, 'Sudah Bayar');
    });

    test(
      'decodeArchiveCsv auto-marks records >= 2,000,000 as Target Pemda when column is empty',
      () {
        const archiveCsv =
            'Nama WP,NOP,Tahun Bayar,Tanggal Bayar,Jumlah PBB,Status Bayar,Foto,Target Pemda\r\n'
            'WARGA BIASA,320520000401701540,2026,,50000,Belum Bayar,,\r\n'
            'WAJIB PAJAK BESAR,320520000403005840,2026,,2000000,Belum Bayar,,\r\n';
        final decoded = BlokCsvCodec.decodeArchiveCsv(archiveCsv);
        expect(decoded, hasLength(2));
        expect(decoded[0].isTargetPemda, isFalse);
        expect(decoded[1].isTargetPemda, isTrue);
      },
    );

    test('tryDecodeLegacyPlainCsv detects plain CSV starting with Nama WP', () {
      final validBytes = Uint8List.fromList(
        utf8.encode('Nama WP,NOP,Tahun Bayar,Tanggal Bayar\n'),
      );
      final invalidBytes = Uint8List.fromList([0x44, 0x4B, 0x48, 0x32, 0x00]);
      expect(BlokCsvCodec.tryDecodeLegacyPlainCsv(validBytes), isNotNull);
      expect(BlokCsvCodec.tryDecodeLegacyPlainCsv(invalidBytes), isNull);
    });
  });

  group('DhkpCrypto & DkhpPackageHelper Security & Regression Suite', () {
    test(
      '1. Wrong password or missing password is ALWAYS rejected on DKH2 AES-256-GCM',
      () async {
        final plain = Uint8List.fromList(
          utf8.encode('Data DHKP Rahasia Desa Bobojong 2026'),
        );
        final encrypted = await DhkpCrypto.encryptBytes(
          plain,
          password: 'PasswordKuat123!',
        );

        expect(DhkpCrypto.isEncrypted(encrypted), isTrue);
        expect(DhkpCrypto.isDkh2Format(encrypted), isTrue);
        expect(DhkpCrypto.isPasswordProtected(encrypted), isTrue);

        final decrypted = await DhkpCrypto.decryptBytes(
          encrypted,
          password: 'PasswordKuat123!',
        );
        expect(decrypted, equals(plain));

        // Wrong password rejected
        await expectLater(
          () => DhkpCrypto.decryptBytes(encrypted, password: 'SalahPassword99'),
          throwsA(isA<DkhpPasswordException>()),
        );

        // Near-match password rejected
        await expectLater(
          () =>
              DhkpCrypto.decryptBytes(encrypted, password: 'PasswordKuat123?'),
          throwsA(isA<DkhpPasswordException>()),
        );

        // Missing/null password rejected
        await expectLater(
          () => DhkpCrypto.decryptBytes(encrypted),
          throwsA(isA<DkhpPasswordException>()),
        );

        // Empty password rejected
        await expectLater(
          () => DhkpCrypto.decryptBytes(encrypted, password: '   '),
          throwsA(isA<DkhpPasswordException>()),
        );
      },
    );

    test(
      '2. Modified ciphertext, GCM tag, nonce, salt, or AAD header (32-byte DKH2 header) fails verification',
      () async {
        expect(DhkpCrypto.saltOffset, equals(4));
        expect(DhkpCrypto.nonceOffset, equals(20));
        expect(DhkpCrypto.headerLength, equals(32));
        expect(DhkpCrypto.ciphertextOffset, equals(32));
        expect(DhkpCrypto.tagLength, equals(16));

        final plain = Uint8List.fromList(
          utf8.encode('Integritas AEAD AES-256-GCM Wajib Terjaga'),
        );
        const secret = 'KunciIntegritas2026!';
        final encrypted = await DhkpCrypto.encryptBytes(
          plain,
          password: secret,
        );
        expect(
          encrypted.length,
          equals(DhkpCrypto.headerLength + plain.length + DhkpCrypto.tagLength),
        );

        // (a) Tamper with GCM Authentication Tag (last byte: N-1)
        final tamperedTag = Uint8List.fromList(encrypted);
        tamperedTag[tamperedTag.length - 1] ^= 0x01;
        await expectLater(
          () => DhkpCrypto.decryptBytes(tamperedTag, password: secret),
          throwsA(isA<DkhpPasswordException>()),
        );

        // (b) Tamper with Ciphertext body (first byte right after 32-byte header)
        final tamperedCiphertext = Uint8List.fromList(encrypted);
        tamperedCiphertext[DhkpCrypto.ciphertextOffset] ^= 0x80;
        await expectLater(
          () => DhkpCrypto.decryptBytes(tamperedCiphertext, password: secret),
          throwsA(isA<DkhpPasswordException>()),
        );

        // (c) Tamper with Nonce (bytes 20..31)
        final tamperedNonce = Uint8List.fromList(encrypted);
        tamperedNonce[DhkpCrypto.nonceOffset] ^= 0x04;
        await expectLater(
          () => DhkpCrypto.decryptBytes(tamperedNonce, password: secret),
          throwsA(isA<DkhpPasswordException>()),
        );

        // (d) Tamper with Salt in AAD header (bytes 4..19)
        final tamperedSalt = Uint8List.fromList(encrypted);
        tamperedSalt[DhkpCrypto.saltOffset] ^= 0x02;
        await expectLater(
          () => DhkpCrypto.decryptBytes(tamperedSalt, password: secret),
          throwsA(isA<DkhpPasswordException>()),
        );
      },
    );

    test(
      '3 & 6. Single-key per backup: Recovery Key vs Custom Password separation, password change, key loss, and cross-installation restore',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'dkhp_cross_install_test_',
        );
        try {
          const sampleRecords = [
            BlokRecord(
              nop: '320520000401701540',
              namaWajibPajak: 'WAJIB PAJAK A',
              tahunBayar: '2026',
              tanggalBayar: '2026-06-15',
              jumlahPbb: 'Rp. 150.000',
              statusBayar: 'Sudah Bayar',
              catatan: 'Lunas di Instalasi A',
            ),
          ];

          // --- SKENARIO A: Backup dibuat dengan Recovery Key (tanpa password kustom) ---
          final recoveryKeyA = await BackupPasswordStore.instance
              .ensureRecoveryKey();
          expect(recoveryKeyA.length, greaterThanOrEqualTo(32));

          final backupWithRecoveryKey = File(
            '${tempDir.path}/backup_recovery_key.dkhp',
          );
          await DhkpPackageHelper.packDkhp(
            outputPath: backupWithRecoveryKey.path,
            records: sampleRecords,
            photosDir: tempDir,
            includePhotos: false,
            mapPins: const [],
          );

          // Instalasi A sendiri dapat membuka backup-nya secara otomatis
          final previewOnA = await DhkpPackageHelper.extractPreviewData(
            backupWithRecoveryKey.path,
          );
          expect(previewOnA.isEncrypted, isTrue);
          expect(previewOnA.rows, hasLength(1));

          // --- SKENARIO B: Pengguna mengatur Password Kustom di Instalasi A ---
          const customPassOld = 'SandiDesaBobojongLama#1';
          await BackupPasswordStore.instance.save(customPassOld);

          final backupWithCustomPass = File(
            '${tempDir.path}/backup_custom_pass.dkhp',
          );
          await DhkpPackageHelper.packDkhp(
            outputPath: backupWithCustomPass.path,
            records: sampleRecords,
            photosDir: tempDir,
            includePhotos: false,
            mapPins: const [],
          );

          // Bukti 1 kunci per backup: Recovery Key TIDAK BISA membuka backup yang dibuat dengan Password Kustom!
          await expectLater(
            () => DhkpPackageHelper.extractPreviewData(
              backupWithCustomPass.path,
              password: recoveryKeyA,
            ),
            throwsA(isA<DkhpPasswordException>()),
          );

          // Sebaliknya, Password Kustom berhasil membuka backupWithCustomPass
          final previewCustom = await DhkpPackageHelper.extractPreviewData(
            backupWithCustomPass.path,
            password: customPassOld,
          );
          expect(previewCustom.rows, hasLength(1));

          // --- SKENARIO C: Password Kustom berubah (customPassOld -> customPassNew) ---
          const customPassNew = 'SandiDesaBobojongBaru#2';
          await BackupPasswordStore.instance.save(customPassNew);

          // Backup lama (yang dienkripsi dengan customPassOld) gagal dibuka otomatis karena password aktif sudah berubah
          await expectLater(
            () => DhkpPackageHelper.extractPreviewData(
              backupWithCustomPass.path,
            ),
            throwsA(isA<DkhpPasswordException>()),
          );
          // Namun tetap berhasil dibuka jika pengguna memasukkan customPassOld secara manual
          final previewOldPassManual =
              await DhkpPackageHelper.extractPreviewData(
                backupWithCustomPass.path,
                password: customPassOld,
              );
          expect(previewOldPassManual.rows, hasLength(1));

          // --- SKENARIO D & E: Simulasi Instalasi B (Perangkat Berbeda / Recovery Key Hilang) ---
          BaseSecureStore.clearTestMemoryStore();
          final recoveryKeyB = await BackupPasswordStore.instance
              .ensureRecoveryKey();

          // Bukti tidak ada shared secret statis: Recovery Key B pasti berbeda dari A
          expect(recoveryKeyB, isNot(equals(recoveryKeyA)));

          // Jika Recovery Key A hilang (tidak diberikan), Instalasi B TIDAK BISA membuka backup Instalasi A
          await expectLater(
            () => DhkpPackageHelper.extractPreviewData(
              backupWithRecoveryKey.path,
            ),
            throwsA(isA<DkhpPasswordException>()),
          );

          // Instalasi B BERHASIL memulihkan backupWithRecoveryKey saat Recovery Key A dimasukkan
          final previewOnBWithKey = await DhkpPackageHelper.extractPreviewData(
            backupWithRecoveryKey.path,
            password: recoveryKeyA,
          );
          expect(previewOnBWithKey.rows, hasLength(1));
          expect(previewOnBWithKey.rows.first, contains('320520000401701540'));
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      '4. Legacy backup (DKHP AES-256-CBC) remains readable without breaking backward compatibility',
      () async {
        final plain = Uint8List.fromList(utf8.encode('Legacy Paket DHKP v1'));
        final encrypted = DhkpCrypto.encryptLegacyBytes(plain);

        expect(DhkpCrypto.isEncrypted(encrypted), isTrue);
        expect(DhkpCrypto.isLegacyCbcFormat(encrypted), isTrue);
        expect(DhkpCrypto.isDkh2Format(encrypted), isFalse);
        expect(DhkpCrypto.isPasswordProtected(encrypted), isFalse);

        final decrypted = await DhkpCrypto.decryptBytes(encrypted);
        expect(decrypted, equals(plain));
      },
    );

    test(
      '5. Recovery succeeds when Secure Storage fails/unavailable via manual password or Recovery Key',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'dkhp_broken_storage_test_',
        );
        try {
          const sampleRecords = [
            BlokRecord(
              nop: '320520000403005840',
              namaWajibPajak: 'WAJIB PAJAK DARURAT',
              tahunBayar: '2026',
              tanggalBayar: '2026-07-01',
              jumlahPbb: 'Rp. 300.000',
              statusBayar: 'Sudah Bayar',
            ),
          ];

          // Instalasi sehat membuat backup dan pengguna mencatat Recovery Key
          final savedRecoveryKey = await BackupPasswordStore.instance
              .ensureRecoveryKey();
          final backupFile = File('${tempDir.path}/backup_darurat.dkhp');
          await DhkpPackageHelper.packDkhp(
            outputPath: backupFile.path,
            records: sampleRecords,
            photosDir: tempDir,
            includePhotos: false,
            mapPins: const [],
          );

          // Simulasikan kerusakan total pada Secure Storage (Keystore/libsecret/DPAPI rusak)
          BaseSecureStore.clearTestMemoryStore();
          BaseSecureStore.simulateStorageFailureForTesting = true;

          // Pastikan aplikasi menolak membuat kunci lemah diam-diam saat Secure Storage rusak
          await expectLater(
            () => BackupPasswordStore.instance.getOrCreateActiveSecret(),
            throwsA(isA<SecureStorageException>()),
          );

          // Tanpa input manual, pembukaan otomatis gagal dengan DkhpPasswordException (meminta password)
          await expectLater(
            () => DhkpPackageHelper.extractPreviewData(backupFile.path),
            throwsA(isA<DkhpPasswordException>()),
          );

          // Dengan memasukkan Recovery Key secara manual, pemulihan TETAP BERHASIL
          // meskipun Secure Storage sedang gagal total!
          final recoveredPreview = await DhkpPackageHelper.extractPreviewData(
            backupFile.path,
            password: savedRecoveryKey,
          );
          expect(recoveredPreview.isEncrypted, isTrue);
          expect(recoveredPreview.rows, hasLength(1));
          expect(recoveredPreview.rows.first, contains('320520000403005840'));
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      'DkhpPackageHelper.computeDhkpFingerprint is deterministic regardless of record order',
      () {
        const recA = BlokRecord(
          nop: '320520000401701540',
          namaWajibPajak: 'A',
          tahunBayar: '2026',
          tanggalBayar: '',
        );
        const recB = BlokRecord(
          nop: '320520000403005840',
          namaWajibPajak: 'B',
          tahunBayar: '2026',
          tanggalBayar: '',
        );

        final fp1 = DhkpPackageHelper.computeDhkpFingerprint([recA, recB]);
        final fp2 = DhkpPackageHelper.computeDhkpFingerprint([recB, recA]);
        expect(fp1, isNotEmpty);
        expect(fp1, equals(fp2));
      },
    );

    test(
      'Path Traversal & Zip Slip sanitization prevents escaping target directories',
      () {
        final testCases = {
          '../../evil.pdf': 'evil.pdf',
          '..\\..\\malicious.png': 'malicious.png',
          '/etc/passwd': 'passwd',
          'C:\\Windows\\System32\\cmd.exe': 'cmd.exe',
          'normal_report.xlsx': 'normal_report.xlsx',
        };

        for (final entry in testCases.entries) {
          final sanitized = entry.key
              .split(RegExp(r'[\\/]'))
              .last
              .replaceAll('..', '')
              .trim();
          expect(sanitized, equals(entry.value));
          expect(sanitized.contains('/'), isFalse);
          expect(sanitized.contains('\\'), isFalse);
          expect(sanitized.contains('..'), isFalse);
        }
      },
    );
  });

  group('DHKP Generate, Encrypted Split per Dusun (3 & 5 Kedusunan), and Thorough Sync', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dhkp_gen_split_sync_');
      AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
      await DusunData.instance.setDusuns(DusunData.defaultBobojongDusuns);
      await DusunData.instance.clearScope();
      await WilayahKerjaStore.instance.setSelectedDusun(null);
      await BlokDataStore.instance.clearAll();
    });

    tearDown(() async {
      await DusunData.instance.clearScope();
      await DusunData.instance.setDusuns(DusunData.defaultBobojongDusuns);
      await WilayahKerjaStore.instance.setSelectedDusun(null);
      BlokDataStore.instance.resetForTesting();
      AppStorage.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      '1. Universal Wilayah Resolution supports Bapenda, Kecamatan, Desa/Kelurahan, and Manifest inputs',
      () {
        // (a) Input kode 3 digit ("200" dan "004") dinormalisasi ke kode 7 & 10 digit V-Tax
        final resShort = StaffDhkpGenerateService.resolveWilayahParameters(
          kecamatanCode: '200',
          kelurahanCode: '004',
          kecamatanName: '',
          desaName: '',
        );
        expect(resShort.kecCode3, equals('200'));
        expect(resShort.vtaxKecCode, equals('3205200'));
        expect(resShort.kecName, equals('MANDE'));
        expect(resShort.kelCode3, equals('004'));
        expect(resShort.vtaxKelCode, equals('3205200004'));
        expect(resShort.desaName, equals('BOBOJONG'));

        // (b) Input dari nama wilayah saja (mis. akun Bapenda/Kecamatan memilih nama)
        final resByName = StaffDhkpGenerateService.resolveWilayahParameters(
          kecamatanCode: '',
          kelurahanCode: '',
          kecamatanName: 'PACET',
          desaName: 'CIPENDAWA',
        );
        expect(resByName.vtaxKecCode, equals('3205140'));
        expect(resByName.kecName, equals('PACET'));
        expect(resByName.vtaxKelCode, equals('3205140003'));
        expect(resByName.desaName, equals('CIPENDAWA'));

        // (c) Input dari kode penuh V-Tax (mis. akun Desa/Kelurahan lain)
        final resFull = StaffDhkpGenerateService.resolveWilayahParameters(
          kecamatanCode: '3205010',
          kelurahanCode: '3205010001',
          kecamatanName: '',
          desaName: '',
        );
        expect(resFull.vtaxKecCode, equals('3205010'));
        expect(resFull.vtaxKelCode, equals('3205010001'));
      },
    );

    test(
      '2a. Encrypted Split .dkhp supports 3 Kedusunan (3 Dusun files + 1 Master file)',
      () async {
        const splitPass = 'SandiSplit3Dusun2026!';
        const records = [
          BlokRecord(
            nop: '320520000400200010',
            namaWajibPajak: 'WARGA DUSUN 1',
            tahunBayar: '2026',
            tanggalBayar: '2026-03-10',
            jumlahPbb: 'Rp. 100.000',
            statusBayar: 'Sudah Bayar',
          ),
          BlokRecord(
            nop: '320520000400400020',
            namaWajibPajak: 'WARGA DUSUN 2',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 150.000',
            statusBayar: 'Belum Bayar',
          ),
          BlokRecord(
            nop: '320520000400500030',
            namaWajibPajak: 'WARGA DUSUN 3A',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 200.000',
            statusBayar: 'Belum Bayar',
          ),
          BlokRecord(
            nop: '320520000401600040',
            namaWajibPajak: 'WARGA DUSUN 3B',
            tahunBayar: '2026',
            tanggalBayar: '2026-04-01',
            jumlahPbb: 'Rp. 250.000',
            statusBayar: 'Sudah Bayar',
          ),
        ];

        final threeDusuns = [
          const Dusun(
            number: 1,
            name: 'Dusun Satu',
            bloks: ['002'],
            focusLat: -6.771,
            focusLng: 107.211,
          ),
          const Dusun(
            number: 2,
            name: 'Dusun Dua',
            bloks: ['004'],
            focusLat: -6.772,
            focusLng: 107.212,
          ),
          const Dusun(
            number: 3,
            name: 'Dusun Tiga',
            bloks: ['005', '016'],
            focusLat: -6.773,
            focusLng: 107.213,
          ),
        ];

        final outDir3 = Directory('${tempDir.path}/split_3_dusun');
        final split3Result = await DhkpPackageHelper.packSplitDkhpByDusun(
          outputDirectory: outDir3,
          records: records,
          photosDir: tempDir,
          includePhotos: false,
          mapPins: const [],
          dusuns: threeDusuns,
          kecamatanCode: '3205200',
          kecamatanName: 'MANDE',
          kelurahanCode: '3205200004',
          desaName: 'DESA TIGA DUSUN',
          tahunPajak: '2026',
          includeMasterDesa: true,
          password: splitPass,
        );

        expect(split3Result.dusunEntries, hasLength(3));
        expect(split3Result.masterEntry, isNotNull);
        expect(split3Result.allEntries, hasLength(4));
        expect(split3Result.dusunEntries[0].recordCount, equals(1));
        expect(split3Result.dusunEntries[1].recordCount, equals(1));
        expect(split3Result.dusunEntries[2].recordCount, equals(2));

        for (final entry in split3Result.allEntries) {
          final rawBytes = await entry.file.readAsBytes();
          expect(DhkpCrypto.isEncrypted(rawBytes), isTrue);
          expect(DhkpCrypto.isDkh2Format(rawBytes), isTrue);
          expect(DhkpCrypto.isPasswordProtected(rawBytes), isTrue);
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      '2b. Encrypted Split .dkhp supports 5 Kedusunan (Desa Bobojong), matches manifest, locks scope, and supports 2-way delta backup',
      () async {
        const splitPass = 'SandiSplitBobojong2026!';
        const records = [
          // Dusun 1 Bobojong (blok 002)
          BlokRecord(
            nop: '320520000400200010',
            namaWajibPajak: 'WARGA DUSUN 1',
            tahunBayar: '2026',
            tanggalBayar: '2026-03-10',
            jumlahPbb: 'Rp. 100.000',
            statusBayar: 'Sudah Bayar',
            kecamatan: 'MANDE',
            kelurahan: 'BOBOJONG',
          ),
          // Dusun 2 Batulayang (blok 005)
          BlokRecord(
            nop: '320520000400500020',
            namaWajibPajak: 'WARGA DUSUN 2',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 150.000',
            statusBayar: 'Belum Bayar',
            kecamatan: 'MANDE',
            kelurahan: 'BOBOJONG',
          ),
          // Dusun 3 Cibogo (blok 017)
          BlokRecord(
            nop: '320520000401700030',
            namaWajibPajak: 'WARGA DUSUN 3',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 200.000',
            statusBayar: 'Belum Bayar',
            kecamatan: 'MANDE',
            kelurahan: 'BOBOJONG',
          ),
          // Dusun 4 Cidamar (blok 032)
          BlokRecord(
            nop: '320520000403200040',
            namaWajibPajak: 'WARGA DUSUN 4',
            tahunBayar: '2026',
            tanggalBayar: '2026-04-01',
            jumlahPbb: 'Rp. 250.000',
            statusBayar: 'Sudah Bayar',
            kecamatan: 'MANDE',
            kelurahan: 'BOBOJONG',
          ),
          // Dusun 5 Jangari (blok 034)
          BlokRecord(
            nop: '320520000403400050',
            namaWajibPajak: 'WARGA DUSUN 5',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 300.000',
            statusBayar: 'Belum Bayar',
            kecamatan: 'MANDE',
            kelurahan: 'BOBOJONG',
          ),
        ];

        final outDir5 = Directory('${tempDir.path}/split_5_bobojong');
        final split5Result = await DhkpPackageHelper.packSplitDkhpByDusun(
          outputDirectory: outDir5,
          records: records,
          photosDir: tempDir,
          includePhotos: false,
          mapPins: const [],
          dusuns: DusunData.defaultBobojongDusuns,
          kecamatanCode: '3205200',
          kecamatanName: 'MANDE',
          kelurahanCode: '3205200004',
          desaName: 'BOBOJONG',
          kantorDesaLat: -6.767652,
          kantorDesaLng: 107.219639,
          tahunPajak: '2026',
          includeMasterDesa: true,
          password: splitPass,
        );

        expect(split5Result.dusunEntries, hasLength(5));
        expect(split5Result.masterEntry, isNotNull);
        expect(split5Result.masterEntry!.recordCount, equals(5));
        for (final dEntry in split5Result.dusunEntries) {
          expect(dEntry.recordCount, equals(1));
        }

        for (final entry in split5Result.allEntries) {
          final rawBytes = await entry.file.readAsBytes();
          expect(DhkpCrypto.isEncrypted(rawBytes), isTrue);
          expect(DhkpCrypto.isDkh2Format(rawBytes), isTrue);
          expect(DhkpCrypto.isPasswordProtected(rawBytes), isTrue);
        }

        // Unpack file Dusun 4 (Cidamar, blok 032) di perangkat Kadus 4
        final dusun4Entry = split5Result.dusunEntries[3];
        expect(dusun4Entry.dusunNumber, equals(4));

        // Tanpa password harus ditolak
        await expectLater(
          () => DhkpPackageHelper.extractPreviewData(dusun4Entry.file.path),
          throwsA(isA<DkhpPasswordException>()),
        );

        await DhkpPackageHelper.unpackDkhp(
          dusun4Entry.file.path,
          password: splitPass,
        );

        // Pastikan DusunData & WilayahKerjaStore terkunci ke Dusun 4 dan hanya blok 032 yang tersimpan
        final allOnKadus4 = await BlokDataStore.instance.loadAll();
        expect(DusunData.instance.isDusunLocked, isTrue);
        expect(DusunData.instance.lockedDusunNumber, equals(4));
        expect(await WilayahKerjaStore.instance.selectedDusun(), equals(4));
        expect(allOnKadus4, hasLength(1));
        expect(allOnKadus4.first.nop, equals('320520000403200040'));
        expect(
          DusunData.instance.kantorDesaLat,
          closeTo(-6.767652, 0.00001),
        );

        // Buat delta backup dari perangkat Kadus 4 lalu pulihkan ke perangkat Master Desa
        await BlokDataStore.instance.upsert(
          allOnKadus4.first.copyWith(catatan: 'Sudah ditagih Kadus 4'),
        );
        final deltaKadus4Path = '${tempDir.path}/delta_kadus4.dkhp';
        await DhkpPackageHelper.packDkhp(
          outputPath: deltaKadus4Path,
          records: await BlokDataStore.instance.loadAll(),
          photosDir: tempDir,
          includePhotos: false,
          mapPins: const [],
          deltaOnly: true,
          scope: DusunData.instance.scope,
          password: splitPass,
        );

        // Simulasikan perangkat Master Desa (memuat file Master Desa terlebih dahulu)
        await DhkpPackageHelper.unpackDkhp(
          split5Result.masterEntry!.file.path,
          password: splitPass,
        );
        expect(DusunData.instance.isDusunLocked, isFalse);
        expect(await BlokDataStore.instance.loadAll(), hasLength(5));

        // Master Desa membuka delta backup dari Kadus 4 -> kompatibel (tidak ditolak fingerprint!)
        await DhkpPackageHelper.unpackDkhp(
          deltaKadus4Path,
          password: splitPass,
        );
        final masterAll = await BlokDataStore.instance.loadAll();
        final updatedRec = masterAll.firstWhere(
          (r) => r.nop == '320520000403200040',
        );
        expect(updatedRec.catatan, equals('Sudah ditagih Kadus 4'));
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      '3. StaffDhkpGenerateService fetches all pages with retry, preserves DB on fatal error, captures cross-year payments, and auto-splits',
      () async {
        final fakeClient = _FakeStaffPortalClient();

        // Siapkan 2 halaman Belum Bayar + 1 halaman Sudah Bayar, dengan 1x kegagalan sementara di halaman 2
        fakeClient.transientFailureOnBelumBayarPage2 = true;
        fakeClient.belumBayarPages = {
          1: const MonitoringTableResult(
            headers: [
              'NO',
              'NOP',
              'NAMA WP',
              'ALAMAT OP',
              'ALAMAT WP',
              'RT OP',
              'LUAS BUMI',
              'LUAS BANGUNAN',
              'NJOP BUMI',
              'NJOP BANGUNAN',
              'TAHUN PAJAK',
              'KETETAPAN PBB',
            ],
            rows: [
              [
                '1',
                '32.05.200.004.002-0001.0',
                'WP BELUM BAYAR 1',
                'KP. BOBOJONG',
                'JL. MANDE',
                '001',
                '100',
                '50',
                '5000000',
                '10000000',
                '2025',
                '120.000',
              ],
            ],
            totalRecords: 2,
            hasNextPage: true,
          ),
          2: const MonitoringTableResult(
            headers: [
              'NO',
              'NOP',
              'NAMA WP',
              'ALAMAT OP',
              'ALAMAT WP',
              'RT OP',
              'LUAS BUMI',
              'LUAS BANGUNAN',
              'NJOP BUMI',
              'NJOP BANGUNAN',
              'TAHUN PAJAK',
              'KETETAPAN PBB',
            ],
            rows: [
              [
                '2',
                '32.05.200.004.004-0002.0',
                'WP BELUM BAYAR 2 (TARGET PEMDA)',
                'KP. NAGROG',
                'JL. NAGROG',
                '002',
                '2000',
                '500',
                '500000000',
                '500000000',
                '2025',
                '2.500.000',
              ],
            ],
            totalRecords: 2,
            hasNextPage: false,
          ),
        };

        fakeClient.sudahBayarPages = {
          1: const MonitoringTableResult(
            headers: [
              'NO',
              'NOP',
              'NAMA WP',
              'ALAMAT OP',
              'ALAMAT WP',
              'TAHUN PAJAK',
              'POKOK PEMBAYARAN',
              'TANGGAL BAYAR',
            ],
            rows: [
              [
                '1',
                '32.05.200.004.005-0003.0',
                'WP SUDAH LUNAS LINTAS TAHUN',
                'KP. GALLERY',
                'KP. GALLERY',
                '2025',
                '175.000',
                '2026-02-15',
              ],
            ],
            totalRecords: 1,
            hasNextPage: false,
          ),
        };

        final splitOutDir = Directory('${tempDir.path}/auto_split_out');
        final genResult = await StaffDhkpGenerateService.instance.generateAndApply(
          client: fakeClient,
          tahun: '2025',
          kecamatanCode: '200',
          kecamatanName: 'MANDE',
          kelurahanCode: '004',
          desaName: 'BOBOJONG',
          dusuns: DusunData.defaultBobojongDusuns,
          pacingDelay: Duration.zero,
          retryBaseDelay: Duration.zero,
          exportSplitByDusun: true,
          splitOutputDirectory: splitOutDir,
          encryptionPassword: 'SandiAutoSplit2025!',
          includeMasterInSplit: true,
        );

        // Pastikan halaman 2 berhasil di-retry dan total 3 SPPT tersimpan utuh:
        // 1 Belum Bayar reguler + 1 Target Pemda (>= 2 Juta) + 1 Sudah Bayar = 3 SPPT
        expect(genResult.success, isTrue);
        expect(fakeClient.belumBayarPage2Attempts, equals(2));
        expect(genResult.totalRecords, equals(3));
        expect(genResult.belumBayarCount, equals(1));
        expect(genResult.sudahBayarCount, equals(1));
        expect(genResult.targetPemdaCount, equals(1));
        expect(await BlokDataStore.instance.loadAll(), hasLength(3));

        // Pastikan tglBayarAkhir untuk tahun pajak lampau (2025) diperluas hingga hari ini (lintas tahun)
        expect(
          fakeClient.lastSudahBayarEnd.compareTo('2025-12-31'),
          greaterThan(0),
        );

        // Pastikan hasil auto-split menghasilkan 5 file Dusun Bobojong + 1 Master terenkripsi
        expect(genResult.splitExportResult, isNotNull);
        expect(genResult.splitExportResult!.dusunEntries, hasLength(5));
        expect(genResult.splitExportResult!.masterEntry, isNotNull);

        // Sekarang uji Atomic Failure Guard: jika server gagal permanen di tengah jalan,
        // database lokal yang sudah berisi 3 SPPT TIDAK BOLEH terhapus!
        fakeClient.permanentFailureOnBelumBayarPage2 = true;
        final failedOutcome =
            await StaffDhkpGenerateService.instance.generateAndApply(
              client: fakeClient,
              tahun: '2025',
              kecamatanCode: '3205200',
              kecamatanName: 'MANDE',
              kelurahanCode: '3205200004',
              desaName: 'BOBOJONG',
              dusuns: DusunData.defaultBobojongDusuns,
              pacingDelay: Duration.zero,
              retryBaseDelay: Duration.zero,
            );
        expect(failedOutcome.success, isFalse);
        expect(failedOutcome.errorMessage, isNotNull);
        expect(await BlokDataStore.instance.loadAll(), hasLength(3));
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      '4. StaffDhkpSyncService.syncBloks thoroughly syncs paid & existing unpaid SPPT metadata and strictly enforces Dusun scope even with >= 10 blocks',
      () async {
        // Kunci aplikasi ke Dusun 1 Bobojong (memiliki 11 blok: 001, 002, 003, 004, 011, 012, 013, 014, 015, 016, 027)
        final dusun1 = DusunData.defaultBobojongDusuns.first;
        expect(dusun1.bloks.length, greaterThanOrEqualTo(10));
        await DusunData.instance.setScope(
          DusunScope(
            role: 'dusun',
            dusunNumber: dusun1.number,
            dusunName: dusun1.name,
            allowedBloks: dusun1.bloks,
          ),
        );

        // Isi database awal Dusun 1 dengan 2 SPPT Belum Bayar di blok 002 dan 011
        await BlokDataStore.instance.clearAll();
        await BlokDataStore.instance.upsertAll([
          const BlokRecord(
            nop: '320520000400200010',
            namaWajibPajak: 'WARGA DUSUN 1 AWAL',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 100.000',
            statusBayar: 'Belum Bayar',
          ),
          const BlokRecord(
            nop: '320520000401100050',
            namaWajibPajak: 'WARGA DUSUN 1 BELUM BAYAR',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp. 120.000',
            statusBayar: 'Belum Bayar',
          ),
        ]);

        final fakeClient = _FakeStaffPortalClient();
        // Server mengembalikan:
        // - Sudah Bayar:
        //   1. blok 002 (milik Dusun 1, ada di lokal -> diupdate jadi Sudah Bayar)
        //   2. blok 012 (milik Dusun 1, belum ada di lokal -> ditambahkan sebagai SPPT baru lunas!)
        //   3. blok 005 (milik Dusun 2 Batulayang -> diabaikan karena di luar scope Dusun 1!)
        fakeClient.sudahBayarPages = {
          1: const MonitoringTableResult(
            headers: [
              'NOP',
              'NAMA WP',
              'ALAMAT OP',
              'TAHUN PAJAK',
              'POKOK',
              'TANGGAL BAYAR',
            ],
            rows: [
              [
                '320520000400200010',
                'WARGA DUSUN 1 AWAL',
                'KP. BOBOJONG RT 01',
                '2026',
                '100000',
                '2026-08-17',
              ],
              [
                '320520000401200070',
                'WARGA DUSUN 1 BARU LUNAS',
                'KP. BOBOJONG RT 03',
                '2026',
                '140000',
                '2026-08-18',
              ],
              [
                '320520000400500990',
                'WARGA DUSUN 2 BOCOR',
                'KP. BATULAYANG',
                '2026',
                '150000',
                '2026-08-17',
              ],
            ],
            totalRecords: 3,
            hasNextPage: false,
          ),
        };

        // - Belum Bayar (untuk StaffSyncMode.full):
        //   1. blok 011 (milik Dusun 1, ada di lokal -> metadata alamat & luas diperbarui!)
        //   2. blok 032 (milik Dusun 4 Cidamar -> diabaikan!)
        fakeClient.belumBayarPages = {
          1: const MonitoringTableResult(
            headers: [
              'NOP',
              'NAMA WP',
              'ALAMAT OP',
              'LUAS BUMI',
              'TAHUN PAJAK',
              'KETETAPAN PBB',
            ],
            rows: [
              [
                '320520000401100050',
                'WARGA DUSUN 1 BELUM BAYAR',
                'KP. BOBOJONG BARU RT 02',
                '240',
                '2026',
                '180000',
              ],
              [
                '320520000403200880',
                'WARGA DUSUN 4 BOCOR',
                'KP. CIDAMAR',
                '300',
                '2026',
                '220000',
              ],
            ],
            totalRecords: 2,
            hasNextPage: false,
          ),
        };

        final syncRes = await StaffDhkpSyncService.instance.syncBloks(
          client: fakeClient,
          bloks: dusun1.bloks, // 11 blok!
          tahun: '2026',
          kecamatanCode: '200',
          kelurahanCode: '004',
          mode: StaffSyncMode.full,
          pacingDelay: Duration.zero,
          retryBaseDelay: Duration.zero,
        );

        expect(syncRes.isSuccess, isTrue);
        expect(syncRes.updatedPaidCount, equals(1));
        expect(syncRes.newSpptCount, equals(1));
        final allAfterSync = await BlokDataStore.instance.loadAll();
        expect(allAfterSync, hasLength(3));

        final paidRec = allAfterSync.firstWhere(
          (r) => r.nop == '320520000400200010',
        );
        expect(paidRec.isPaid, isTrue);
        expect(paidRec.tanggalBayar, equals('2026-08-17'));
        expect(paidRec.alamatObjek, equals('KP. BOBOJONG RT 01'));

        final enrichedUnpaidRec = allAfterSync.firstWhere(
          (r) => r.nop == '320520000401100050',
        );
        expect(enrichedUnpaidRec.isPaid, isFalse);
        expect(enrichedUnpaidRec.alamatObjek, equals('KP. BOBOJONG BARU RT 02'));
        expect(enrichedUnpaidRec.luasBumi, equals('240'));

        final newPaidRec = allAfterSync.firstWhere(
          (r) => r.nop == '320520000401200070',
        );
        expect(newPaidRec.isPaid, isTrue);
        expect(newPaidRec.namaWajibPajak, equals('WARGA DUSUN 1 BARU LUNAS'));

        // Pastikan blok 005 dan 032 dari dusun lain TIDAK masuk ke database Dusun 1
        expect(
          allAfterSync.any((r) => nopBlok(r.nop) == '005'),
          isFalse,
        );
        expect(
          allAfterSync.any((r) => nopBlok(r.nop) == '032'),
          isFalse,
        );
      },
    );

    test(
      '5. StaffDhkpGenerateService menolak kata sandi < 8 karakter sebelum memanggil Portal Staf atau menimpa CSV',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('dhkp_pwd_preflight_');
        addTearDown(() async {
          AppStorage.resetForTesting();
          await tempDir.delete(recursive: true);
        });
        AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
        await BlokDataStore.instance.clearAll();
        await BlokDataStore.instance.upsert(
          const BlokRecord(
            nop: '320520000400100010',
            namaWajibPajak: 'WARGA EKSISTING',
            tahunBayar: '2026',
            tanggalBayar: '',
            jumlahPbb: 'Rp 50.000',
            statusBayar: 'Belum Bayar',
          ),
        );

        final fakeClient = _FakeStaffPortalClient();
        final outcome = await StaffDhkpGenerateService.instance.generateAndApply(
          client: fakeClient,
          tahun: '2026',
          kecamatanCode: '200',
          kecamatanName: 'MANDE',
          kelurahanCode: '004',
          desaName: 'BOBOJONG',
          dusuns: DusunData.defaultBobojongDusuns,
          exportSplitByDusun: true,
          encryptionPassword: '1234',
        );

        expect(outcome.success, isFalse);
        expect(
          outcome.errorMessage,
          contains('minimal ${DhkpCrypto.minPasswordLength} karakter'),
        );
        expect(fakeClient.totalRequests, equals(0));
        final saved = await BlokDataStore.instance.loadAll();
        expect(saved, hasLength(1));
        expect(saved.single.namaWajibPajak, equals('WARGA EKSISTING'));
      },
    );

    testWidgets(
      '6. StaffDhkpGenerateDialog memberi tahu syarat minimal 8 karakter sejak awal dan memblokir sandi pendek sebelum unduh',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fakeClient = _FakeStaffPortalClient();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StaffDhkpGenerateDialog(client: fakeClient),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('minimal ${DhkpCrypto.minPasswordLength} karakter'),
          findsWidgets,
        );
        expect(
          find.textContaining('min. ${DhkpCrypto.minPasswordLength} karakter'),
          findsWidgets,
        );

        final pwdField = find.widgetWithText(
          TextFormField,
          'Kata Sandi Enkripsi .dkhp (Opsional, min. ${DhkpCrypto.minPasswordLength} karakter)',
        );
        expect(pwdField, findsOneWidget);

        await tester.ensureVisible(pwdField);
        await tester.enterText(pwdField, '1234');
        await tester.pump();

        expect(find.textContaining('saat ini 4/8'), findsOneWidget);

        await tester.tap(find.text('Mulai Generate & Timpa DHKP'));
        await tester.pumpAndSettle();

        expect(
          find.text('Kata Sandi Belum Memenuhi Syarat'),
          findsOneWidget,
        );
        expect(fakeClient.totalRequests, equals(0));

        await tester.tap(find.text('Perbaiki'));
        await tester.pumpAndSettle();

        await tester.enterText(pwdField, 'SandiKuat8');
        await tester.pumpAndSettle();

        expect(
          find.text('✓ Kata sandi memenuhi syarat (10 karakter).'),
          findsOneWidget,
        );
        expect(find.textContaining('saat ini'), findsNothing);
      },
    );
  });
}

class _FakeStaffPortalClient extends StaffPortalClient {
  Map<int, MonitoringTableResult> belumBayarPages = {};
  Map<int, MonitoringTableResult> sudahBayarPages = {};
  bool transientFailureOnBelumBayarPage2 = false;
  bool permanentFailureOnBelumBayarPage2 = false;
  int belumBayarPage2Attempts = 0;
  int totalRequests = 0;
  String lastSudahBayarEnd = '';

  @override
  Future<MonitoringTableResult> fetchBelumBayar({
    required String tglCutoff,
    String tahunAwal = '',
    String tahunAkhir = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String bukuMin = '',
    String bukuMax = '',
    String kelurahan = '',
    String kecamatan = '',
    int page = 1,
  }) async {
    totalRequests++;
    if (page == 2) {
      belumBayarPage2Attempts++;
      if (permanentFailureOnBelumBayarPage2) {
        return const MonitoringTableResult(
          errorMessage: 'Server V-Tax sibuk (simulasi kegagalan permanen)',
        );
      }
      if (transientFailureOnBelumBayarPage2 && belumBayarPage2Attempts == 1) {
        return const MonitoringTableResult(
          errorMessage: 'Timeout sementara pada halaman 2',
        );
      }
    }
    return belumBayarPages[page] ??
        const MonitoringTableResult(headers: [], rows: [], hasNextPage: false);
  }

  @override
  Future<MonitoringTableResult> fetchSudahBayar({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    String tahunAwal = '',
    String tahunAkhir = '',
    String bukuMin = '',
    String bukuMax = '',
    String bank = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String kodeBayarKolektif = '',
    String va = '',
    String qris = '',
    String operator = '',
    String tglPelimpahanAwal = '',
    String tglPelimpahanAkhir = '',
    String kelurahan = '',
    String kecamatan = '',
    int page = 1,
  }) async {
    totalRequests++;
    lastSudahBayarEnd = tglBayarAkhir;
    return sudahBayarPages[page] ??
        const MonitoringTableResult(headers: [], rows: [], hasNextPage: false);
  }
}


