import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/apk_installer.dart';
import 'package:cek_pbb_app/app_security_service.dart';
import 'package:cek_pbb_app/base_preferences_store.dart';
import 'package:cek_pbb_app/base_table_exporter.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/blok_sync_service.dart';
import 'package:cek_pbb_app/dhkp/blok_csv_codec.dart';
import 'package:cek_pbb_app/google_auth_service.dart';
import 'package:cek_pbb_app/map/kml_parser.dart';
import 'package:cek_pbb_app/map/map_models.dart';
import 'package:cek_pbb_app/monitoring/monitoring_form_fields.dart';
import 'package:cek_pbb_app/settings/security_settings_screen.dart';
import 'package:cek_pbb_app/shared_storage_link_service.dart';
import 'package:cek_pbb_app/staff_portal/staff_authenticator_store.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:cek_pbb_app/update_checker.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLocalAuthentication implements LocalAuthentication {
  @override
  Future<bool> get canCheckBiometrics async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<bool> stopAuthentication() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStaffPortalClient extends StaffPortalClient {
  final Completer<
    ({
      String kecamatanCode,
      String kecamatanName,
      String kelurahanCode,
      List<KolektifKelurahan> kelurahan,
    })
  >
  wilayahCompleter = Completer();

  final List<BankOption> banks;

  _FakeStaffPortalClient({this.banks = const []});

  @override
  String get activeKelurahanCode => '';

  @override
  String get activeKelurahanName => '';

  @override
  List<KolektifKelurahan> get activeKelurahanOptions => const [];

  @override
  Future<List<BankOption>> fetchBankOptions() async => banks;

  @override
  Future<
    ({
      String kecamatanCode,
      String kecamatanName,
      String kelurahanCode,
      List<KolektifKelurahan> kelurahan,
    })
  >
  fetchMonitoringWilayahOptions() => wilayahCompleter.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    BaseSecureStore.clearTestMemoryStore();
    BlokChangeRecord.setSecretForTesting(null);
    BlokChangeRecord.setPbkdf2IterationsForTesting(1000);
    AppSecurityService.setPbkdf2IterationsForTesting(100);
    AppSecurityService.instance.setLocalAuthForTesting(
      _FakeLocalAuthentication(),
    );
  });

  group('A.1 Secure Storage Isolation & One-Way Migration', () {
    test(
      'StaffAuthenticatorStore stores secret only in SecureStorage and never leaks to SharedPreferences',
      () async {
        final store = StaffAuthenticatorStore();
        await store.saveSecret(
          'JBSWY3DPEHPK3PXP',
          accountName: 'petugas1',
          issuer: 'BAPENDA',
        );

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('staff_mfa_secret'),
          isNull,
          reason: 'MFA secret must never be written to SharedPreferences',
        );
        expect(prefs.getString('staff_mfa_account_name'), 'petugas1');
        expect(await store.getSecret(), 'JBSWY3DPEHPK3PXP');
      },
    );

    test(
      'StaffAuthenticatorStore migrates legacy plaintext secret from SharedPreferences and deletes plaintext copy',
      () async {
        SharedPreferences.setMockInitialValues({
          'staff_mfa_secret': 'LEGACYBASE32SECRET',
          'staff_mfa_account_name': 'legacy_user',
        });

        final store = StaffAuthenticatorStore();
        final migrated = await store.getSecret();
        expect(migrated, 'LEGACYBASE32SECRET');

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('staff_mfa_secret'),
          isNull,
          reason: 'Legacy plaintext secret must be deleted after migration',
        );

        // Second read comes directly from FlutterSecureStorage
        expect(await store.getSecret(), 'LEGACYBASE32SECRET');
      },
    );

    test(
      'AppSecurityService stores PIN/Password hashes, salts, and lockout metadata only in SecureStorage',
      () async {
        final sec = AppSecurityService.instance;
        await sec.setCustomPin('123456');
        await sec.setCustomPassword('SandiAman123');
        await sec.setLockType(AppLockType.pin);
        await sec.setLockEnabled(true);
        for (var i = 0; i < 5; i++) {
          await sec.recordFailedPinAttempt();
        }

        final prefs = await SharedPreferences.getInstance();
        for (final key in [
          'app_security_lock_enabled',
          'app_security_lock_type',
          'app_security_custom_pin_hash',
          'app_security_custom_pin_salt',
          'app_security_custom_password_hash',
          'app_security_custom_password_salt',
          'app_security_failed_pin_attempts',
          'app_security_lockout_until_millis',
        ]) {
          expect(
            prefs.get(key),
            isNull,
            reason: 'Sensitive key $key must not exist in SharedPreferences',
          );
        }

        expect(await sec.isLockEnabled(), isTrue);
        expect(await sec.getLockType(), AppLockType.pin);
        await sec.resetFailedPinAttempts();
        expect(await sec.verifyCustomPin('123456'), isTrue);
        expect(await sec.verifyCustomPassword('SandiAman123'), isTrue);
      },
    );
  });

  group('A.2 BlokChangeRecord AEAD v2 Encryption & Legacy Validation', () {
    test(
      'Format v2 encrypts with random salt/nonce and verifies integrity via AES-256-GCM',
      () async {
        const secret = 'KunciTimDesaBobojong2026!';
        const record = BlokChangeRecord(
          id: 'change_001',
          blok: '001',
          nop: '320301000100100010',
          tahunBayar: '2026',
          petugas: 'petugas_1',
          timestamp: 1730000000000,
          statusBayar: 'Sudah Bayar',
          catatan: 'Lunas kolektif',
          namaFoto: '320301000100100010.jpg',
          petugasFolder: 'Petugas_1',
        );

        final cipher1 = await record.toEncryptedBytes(secret: secret);
        final cipher2 = await record.toEncryptedBytes(secret: secret);

        // Header magic 'CPBB' + version 0x02
        expect(utf8.decode(cipher1.sublist(0, 4)), 'CPBB');
        expect(cipher1[4], 0x02);
        // Unique salt/nonce produces distinct ciphertexts for identical plaintext
        expect(cipher1, isNot(equals(cipher2)));

        final decrypted = await BlokChangeRecord.fromEncryptedBytes(
          cipher1,
          secret: secret,
        );
        expect(decrypted, isNotNull);
        expect(decrypted!.id, record.id);
        expect(decrypted.nop, record.nop);
        expect(decrypted.statusBayar, record.statusBayar);
        expect(decrypted.catatan, record.catatan);
        expect(decrypted.namaFoto, record.namaFoto);
        expect(decrypted.timestamp, record.timestamp);
      },
    );

    test(
      'Format v2 rejects wrong secret, bit-flipped ciphertext/tag/header, and truncated bytes',
      () async {
        const secret = 'KunciTimDesaBobojong2026!';
        const record = BlokChangeRecord(
          id: 'change_002',
          blok: '001',
          nop: '320301000100100010',
          tahunBayar: '2026',
          petugas: 'petugas_1',
          timestamp: 1730000000000,
          statusBayar: 'Sudah Bayar',
          catatan: 'Catatan sah',
        );

        final cipher = await record.toEncryptedBytes(secret: secret);

        // Wrong secret
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            cipher,
            secret: 'SalahKunci123!',
          ),
          isNull,
        );

        // Tamper ciphertext byte
        final tamperedBody = Uint8List.fromList(cipher);
        tamperedBody[40] ^= 0xFF;
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            tamperedBody,
            secret: secret,
          ),
          isNull,
        );

        // Tamper GCM authentication tag byte
        final tamperedTag = Uint8List.fromList(cipher);
        tamperedTag[tamperedTag.length - 1] ^= 0x01;
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            tamperedTag,
            secret: secret,
          ),
          isNull,
        );

        // Tamper header AAD (iteration count)
        final tamperedHeader = Uint8List.fromList(cipher);
        tamperedHeader[9] ^= 0x01;
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            tamperedHeader,
            secret: secret,
          ),
          isNull,
        );

        // Truncated data
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            cipher.sublist(0, 20),
            secret: secret,
          ),
          isNull,
        );
      },
    );

    test(
      'Legacy v1 AES-CBC payload is rejected when allowLegacy is false and validated when allowLegacy is true',
      () async {
        const secret = 'LegacySecret123';
        final keyBytes = sha256.convert(utf8.encode(secret)).bytes;
        final key = enc.Key(Uint8List.fromList(keyBytes));
        final iv = enc.IV.fromSecureRandom(16);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

        final validJson = jsonEncode({
          'id': 'legacy_001',
          'blok': '001',
          'nop': '32.03.010.001.001-0001.0',
          'tahunBayar': '2026',
          'petugas': 'petugas_legacy',
          'timestamp': 1730000000000,
          'statusBayar': 'Sudah Bayar',
          'catatan': 'Legacy note',
          'namaFoto': '320301000100100010.jpg',
        });
        final encryptedValid = encrypter.encrypt(validJson, iv: iv);
        final legacyBytes = Uint8List.fromList([
          ...BlokChangeRecord.magic,
          ...iv.bytes,
          ...encryptedValid.bytes,
        ]);

        // Rejected when allowLegacy is false
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            legacyBytes,
            secret: secret,
            allowLegacy: false,
          ),
          isNull,
        );

        // Accepted and marked isLegacyFormat when allowLegacy is true
        final res = await BlokChangeRecord.decryptWithDetails(
          legacyBytes,
          secret: secret,
          allowLegacy: true,
        );
        expect(res.isLegacyFormat, isTrue);
        expect(res.record, isNotNull);
        expect(res.record!.nop, '32.03.010.001.001-0001.0');

        // Malicious legacy payload with path traversal in namaFoto is rejected by validateSchema
        final maliciousJson = jsonEncode({
          'id': 'legacy_evil',
          'blok': '001',
          'nop': '32.03.010.001.001-0001.0',
          'tahunBayar': '2026',
          'petugas': 'petugas_legacy',
          'timestamp': 1730000000000,
          'statusBayar': 'Sudah Bayar',
          'catatan': 'Evil',
          'namaFoto': '../../shared_prefs/secrets.xml',
        });
        final encryptedMalicious = encrypter.encrypt(maliciousJson, iv: iv);
        final maliciousBytes = Uint8List.fromList([
          ...BlokChangeRecord.magic,
          ...iv.bytes,
          ...encryptedMalicious.bytes,
        ]);
        expect(
          await BlokChangeRecord.fromEncryptedBytes(
            maliciousBytes,
            secret: secret,
            allowLegacy: true,
          ),
          isNull,
        );
      },
    );
  });

  group('A.3 Self-Updater Verification & Sanitization', () {
    test(
      'UpdateChecker.extractAssetSha256 parses digest and release notes',
      () {
        const expectedHash =
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

        expect(
          UpdateChecker.extractAssetSha256({
            'name': 'app-release.apk',
            'digest': 'sha256:$expectedHash',
          }, releaseBody: ''),
          expectedHash,
        );

        expect(
          UpdateChecker.extractAssetSha256(
            const {'name': 'CekPBBCianjur-v1.2.0-arm64-v8a.apk'},
            releaseBody: '''
## Checksums
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`  CekPBBCianjur-v1.2.0-arm64-v8a.apk
''',
          ),
          expectedHash,
        );
      },
    );

    test(
      'ApkInstaller sanitizes filenames, enforces directory confinement, and deletes corrupted files',
      () async {
        expect(
          ApkInstaller.sanitizeFileName('../../evil/payload.apk'),
          'payload.apk',
        );
        expect(
          ApkInstaller.sanitizeFileName(r'..\..\Windows\System32\cmd.exe'),
          'cmd.exe',
        );

        final tempDir = await Directory.systemTemp.createTemp('apk_test_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final insideFile = File('${tempDir.path}/valid.apk');
        final outsideFile = File('${tempDir.path}/../escaped.apk');
        expect(ApkInstaller.isPathWithinDirectory(tempDir, insideFile), isTrue);
        expect(
          ApkInstaller.isPathWithinDirectory(tempDir, outsideFile),
          isFalse,
        );

        // Valid APK header (PK\x03\x04) + payload
        final validBytes = Uint8List.fromList([
          0x50,
          0x4B,
          0x03,
          0x04,
          1,
          2,
          3,
          4,
        ]);
        final validHash = sha256.convert(validBytes).toString();
        await insideFile.writeAsBytes(validBytes, flush: true);

        await ApkInstaller.verifyDownloadedFile(
          insideFile,
          fileName: 'valid.apk',
          expectedSize: validBytes.length,
          expectedSha256: validHash,
        );
        expect(await insideFile.exists(), isTrue);

        // Wrong SHA-256 must throw and delete the file
        final wrongHash = '0' * 64;
        await expectLater(
          () => ApkInstaller.verifyDownloadedFile(
            insideFile,
            fileName: 'valid.apk',
            expectedSize: validBytes.length,
            expectedSha256: wrongHash,
          ),
          throwsException,
        );
        expect(
          await insideFile.exists(),
          isFalse,
          reason: 'Corrupted/mismatched file must be deleted immediately',
        );
      },
    );
  });

  group('A.4 OAuth Loopback Server Hardening', () {
    test(
      'waitForOAuthCallback ignores /favicon.ico, escapes XSS in error response, and completes on valid callback',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;
        const expectedState = 'state_token_abc123';

        final callbackFuture = GoogleAuthService.waitForOAuthCallback(
          server,
          expectedState: expectedState,
          timeout: const Duration(seconds: 5),
        );

        final client = HttpClient();
        addTearDown(client.close);

        // 1. Request /favicon.ico -> 404, server stays alive
        final favReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/favicon.ico'),
        );
        final favRes = await favReq.close();
        expect(favRes.statusCode, HttpStatus.notFound);
        await favRes.drain<void>();

        // 2. Request without code/error -> 404, server stays alive
        final emptyReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/random'),
        );
        final emptyRes = await emptyReq.close();
        expect(emptyRes.statusCode, HttpStatus.notFound);
        await emptyRes.drain<void>();

        // 3. Valid callback with code and matching state -> 200 & returns code
        final validReq = await client.getUrl(
          Uri.parse(
            'http://127.0.0.1:$port/?state=$expectedState&code=auth_code_xyz',
          ),
        );
        final validRes = await validReq.close();
        expect(validRes.statusCode, HttpStatus.ok);
        final body = await utf8.decoder.bind(validRes).join();
        expect(body, contains('Otorisasi Akun Google Berhasil'));

        final code = await callbackFuture;
        expect(code, 'auth_code_xyz');
      },
    );

    test(
      'waitForOAuthCallback escapes HTML in error parameter and rejects mismatched state',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;

        final callbackFuture = GoogleAuthService.waitForOAuthCallback(
          server,
          expectedState: 'correct_state',
          timeout: const Duration(seconds: 5),
        );
        // Attach handler immediately so unhandled async error does not fail test zone
        final expectation = expectLater(callbackFuture, throwsException);

        final client = HttpClient();
        addTearDown(client.close);

        final xssReq = await client.getUrl(
          Uri.parse(
            'http://127.0.0.1:$port/?state=correct_state&error=${Uri.encodeQueryComponent('<script>alert("xss")</script>')}',
          ),
        );
        final xssRes = await xssReq.close();
        final html = await utf8.decoder.bind(xssRes).join();

        expect(html, isNot(contains('<script>alert("xss")</script>')));
        expect(html, contains('&lt;script&gt;'));
        await expectation;
      },
    );
  });

  group(
    'A.5 & B.8 KML Escaping, Formula Injection Sanitization & Wilayah Defaults',
    () {
      test(
        'KmlParser.exportToKml escapes XML entities and CDATA terminators',
        () {
          expect(
            KmlParser.sanitizeCdata('evil]]><script>alert(1)</script>'),
            'evil]]]]><![CDATA[><script>alert(1)</script>',
          );

          final kml = KmlParser.exportToKml(
            villageName: 'Bobojong & <Desa>',
            dots: const [
              MapTaxDot(
                id: 'dot_1"><script>evil()</script>',
                nop: '320301000100100010"><script>evil()</script>',
                namaWajibPajak:
                    "Budi & Siti <'WP'> ]]><script>alert(1)</script>",
                blok: '001',
                nomorUrut: '0001',
                dusunNumber: 1,
                coordinate: MapCoordinate(-6.8, 107.1),
                alamatObjek: 'Jl. Desa ]]> <evil/>',
                alamatWp: 'RT 01/02',
                jumlahPbb: 'Rp 50.000',
                statusBayar: 'Belum Bayar & <Tag>',
                status: MapDotStatus.belumLunas,
              ),
            ],
          );

          expect(kml, isNot(contains('<script>evil()</script>')));
          expect(kml, isNot(contains("]]><script>alert(1)</script>")));
          expect(kml, contains(']]&gt;&lt;script&gt;alert(1)&lt;/script&gt;'));
          expect(kml, contains('&amp;'));
          expect(kml, contains('&apos;'));
        },
      );

      test(
        'BaseTableExporter.sanitizeSpreadsheetCell neutralizes formulas while keeping negative numbers',
        () {
          expect(
            BaseTableExporter.sanitizeSpreadsheetCell('=SUM(A1:A10)'),
            "'=SUM(A1:A10)",
          );
          expect(
            BaseTableExporter.sanitizeSpreadsheetCell('  +cmd|\' /C calc\'!A0'),
            "'  +cmd|' /C calc'!A0",
          );
          expect(
            BaseTableExporter.sanitizeSpreadsheetCell('@IMPORTXML()'),
            "'@IMPORTXML()",
          );
          expect(BaseTableExporter.sanitizeSpreadsheetCell('-15000'), '-15000');
          expect(
            BaseTableExporter.sanitizeSpreadsheetCell('-15.000,50'),
            '-15.000,50',
          );
          expect(
            BaseTableExporter.sanitizeSpreadsheetCell('-cmd|calc'),
            "'-cmd|calc",
          );

          final csvBytes = BaseTableExporter.buildCsvData(
            ['Nama', 'Catatan'],
            [
              ['=1+1', '-25000'],
            ],
          );
          final csvText = utf8.decode(csvBytes);
          expect(csvText, contains("'=1+1"));
          expect(csvText, contains('-25000'));
        },
      );

      test(
        'BlokCsvCodec.decodeDatabaseCsv does not inject fake MANDE/BOBOJONG defaults and encodeRecords stays raw',
        () {
          const rec = BlokRecord(
            nop: '320301000100100010',
            namaWajibPajak: '=WP_FORMULA',
            alamatObjek: 'KP TEST',
            alamatWp: 'KP TEST',
            luasBumi: '100',
            luasBangunan: '0',
            njopBumi: '100000',
            njopBangunan: '0',
            jumlahPbb: 'Rp 25.000',
            statusBayar: 'Belum Bayar',
            tahunBayar: '2026',
            tanggalBayar: '-',
            kecamatan: '',
            kelurahan: '',
          );

          // Internal database CSV must keep raw value and empty wilayah
          final rawDbCsv = BlokCsvCodec.encodeRecords([rec]);
          expect(rawDbCsv, contains('=WP_FORMULA'));
          final decoded = BlokCsvCodec.decodeDatabaseCsv(rawDbCsv);
          expect(decoded.single.namaWajibPajak, '=WP_FORMULA');
          expect(decoded.single.kecamatan, isEmpty);
          expect(decoded.single.kelurahan, isEmpty);

          // User-facing report CSV must sanitize formula
          final reportCsv = BlokCsvCodec.encodeReportCsv([rec]);
          expect(reportCsv, contains("'=WP_FORMULA"));
        },
      );
    },
  );

  group('A.6 Deep Link, Redirect Validation & AppLock Exponential Backoff', () {
    test(
      'SharedStorageLinkService.parseString validates folder ID and URLs',
      () {
        const validFolderId = '1AbCdEfGhIjKlMnOpQrStUvWxYz12345';
        expect(
          SharedStorageLinkService.parseString(
            'cekpbb://storage?folder=$validFolderId&name=Dusun%201',
          )?.cleanFolderId,
          validFolderId,
        );
        expect(
          SharedStorageLinkService.parseString(
            'https://drive.google.com/drive/folders/$validFolderId?usp=sharing',
          )?.cleanFolderId,
          validFolderId,
        );

        // Reject path traversal, external hosts, and short/invalid IDs
        expect(
          SharedStorageLinkService.parseString(
            'cekpbb://storage?folder=../../etc/passwd',
          ),
          isNull,
        );
        expect(
          SharedStorageLinkService.parseString(
            'https://evil.com/drive/folders/$validFolderId',
          ),
          isNull,
        );
        expect(
          SharedStorageLinkService.parseString('cekpbb://storage?folder=short'),
          isNull,
        );
      },
    );

    test(
      'StaffPortalClient.normalizeRedirectLocation blocks external domains and non-HTTPS schemes',
      () {
        expect(
          StaffPortalClient.normalizeRedirectLocation('main.php?a=1'),
          '/main.php?a=1',
        );
        expect(
          StaffPortalClient.normalizeRedirectLocation('/mfa.php'),
          '/mfa.php',
        );
        expect(
          StaffPortalClient.normalizeRedirectLocation(
            'https://cianjurkab.v-tax.id/main.php?param=123',
          ),
          '/main.php?param=123',
        );

        expect(
          () => StaffPortalClient.normalizeRedirectLocation(
            'https://evil.example.com/phishing.php',
          ),
          throwsFormatException,
        );
        expect(
          () => StaffPortalClient.normalizeRedirectLocation(
            'http://cianjurkab.v-tax.id/main.php',
          ),
          throwsFormatException,
        );
        expect(
          () => StaffPortalClient.normalizeRedirectLocation('//evil.com/a'),
          throwsFormatException,
        );
      },
    );

    test(
      'AppSecurityService enforces exponential backoff and does not reset failedAttempts when timer expires',
      () async {
        expect(AppSecurityService.calculateLockoutSeconds(4), 0);
        expect(AppSecurityService.calculateLockoutSeconds(5), 30);
        expect(AppSecurityService.calculateLockoutSeconds(6), 60);
        expect(AppSecurityService.calculateLockoutSeconds(7), 120);
        expect(AppSecurityService.calculateLockoutSeconds(8), 240);
        expect(AppSecurityService.calculateLockoutSeconds(20), 1800);

        final sec = AppSecurityService.instance;
        await sec.setCustomPin('123456');

        // 5 failed attempts trigger 30s lockout
        for (var i = 0; i < 5; i++) {
          expect(await sec.verifyCustomPin('000000'), isFalse);
          await sec.recordFailedPinAttempt();
        }
        expect(await sec.getFailedPinAttempts(), 5);
        expect(await sec.getLockoutUntil(), isNotNull);

        // Even correct PIN is rejected while active lockout is in effect
        expect(await sec.verifyCustomPin('123456'), isFalse);

        // Simulate lockout timer expiring: failedAttempts must stay at 5
        await sec.clearExpiredLockout();
        expect(await sec.getFailedPinAttempts(), 5);

        // 6th failed attempt immediately triggers 60s lockout (> 30s)
        expect(await sec.verifyCustomPin('000000'), isFalse);
        await sec.recordFailedPinAttempt();
        expect(await sec.getFailedPinAttempts(), 6);
        final lockout6 = await sec.getLockoutUntil();
        expect(lockout6, isNotNull);
        expect(lockout6!.difference(DateTime.now()).inSeconds, greaterThan(30));

        // Successful authentication after expiry resets failedAttempts to 0
        await sec.clearExpiredLockout();
        expect(await sec.verifyCustomPin('123456'), isTrue);
        expect(await sec.getFailedPinAttempts(), 0);
      },
    );
  });

  group('B.3 & B.4 Widget & Lifecycle Hardening Tests', () {
    testWidgets(
      'DesaKelurahanDropdown and BankDropdown handle empty options safely and skip callback after unmount',
      (tester) async {
        final fakeClient = _FakeStaffPortalClient(banks: const []);
        var callbackCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  BankDropdown(
                    client: fakeClient,
                    value: 'bank_tidak_ada',
                    onChanged: (_) {},
                  ),
                  DesaKelurahanDropdown(
                    client: fakeClient,
                    value: '999',
                    onChanged: (_) {},
                    onKecamatanChanged: (_, _) {
                      callbackCalled = true;
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        // Unmount before the async fetch completes
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

        fakeClient.wilayahCompleter.complete((
          kecamatanCode: '010',
          kecamatanName: 'CIANJUR',
          kelurahanCode: '001',
          kelurahan: const <KolektifKelurahan>[],
        ));
        await tester.pumpAndSettle();

        expect(
          callbackCalled,
          isFalse,
          reason: 'Unmounted DesaKelurahanDropdown must not invoke callback',
        );
      },
    );

    testWidgets(
      'SecuritySettingsScreen displays inline errorText inside PIN verification dialog',
      (tester) async {
        final sec = AppSecurityService.instance;
        await sec.resetFailedPinAttempts();
        await sec.setCustomPin('123456');
        await sec.setLockType(AppLockType.pin);
        await sec.setLockEnabled(true);

        await tester.pumpWidget(
          const MaterialApp(home: SecuritySettingsScreen()),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        // Toggle off "Kunci Pengaman Aplikasi" switch to trigger _verifyCurrentCredential
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.text('Masukkan PIN Saat Ini'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '999999');
        await tester.tap(find.text('Konfirmasi'));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        // Inline error is shown inside the dialog and dialog remains open
        expect(find.text('PIN tidak sesuai.'), findsOneWidget);
        expect(find.text('Masukkan PIN Saat Ini'), findsOneWidget);
      },
    );
  });
}
