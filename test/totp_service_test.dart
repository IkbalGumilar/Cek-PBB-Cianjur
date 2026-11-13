import 'dart:convert';
import 'dart:typed_data';

import 'package:cek_pbb_app/staff_portal/staff_authenticator_store.dart';
import 'package:cek_pbb_app/staff_portal/totp_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  group('TotpHelper Unit Tests', () {
    test('Base32 RFC 4648 test vectors decode & encode', () {
      // RFC 4648 test vectors
      final vectors = {
        '': '',
        'f': 'MY',
        'fo': 'MZXQ',
        'foo': 'MZXW6',
        'foob': 'MZXW6YQ',
        'fooba': 'MZXW6YTB',
        'foobar': 'MZXW6YTBOI',
      };

      vectors.forEach((plain, expectedBase32) {
        final encoded = TotpHelper.base32Encode(
          Uint8List.fromList(utf8.encode(plain)),
        );
        expect(encoded, equals(expectedBase32));

        final decoded = TotpHelper.base32Decode(expectedBase32);
        expect(utf8.decode(decoded), equals(plain));
      });
    });

    test('Base32 sanitizes whitespace, dashes, and padding', () {
      const messy = ' jbsw-y3dp ehpk-3pxp== ';
      final cleaned = TotpHelper.sanitizeBase32(messy);
      expect(cleaned, equals('JBSWY3DPEHPK3PXP'));
      expect(TotpHelper.isValidBase32(messy), isTrue);

      final decoded = TotpHelper.base32Decode(messy);
      expect(decoded.length, equals(10));
    });

    test('RFC 6238 TOTP Standard Test Vectors (SHA1)', () {
      // Secret: ASCII "12345678901234567890" -> Base32 "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

      // T=59s (Counter=1): expected 8-digit "94287082" -> 6-digit "287082"
      final code1 = TotpHelper.generateTotp(
        secretBase32: secret,
        time: DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true),
        digits: 6,
      );
      expect(code1, equals('287082'));

      // T=1111111109s: expected 8-digit "07081804" -> 6-digit "081804"
      final code2 = TotpHelper.generateTotp(
        secretBase32: secret,
        time: DateTime.fromMillisecondsSinceEpoch(
          1111111109 * 1000,
          isUtc: true,
        ),
        digits: 6,
      );
      expect(code2, equals('081804'));

      // T=1234567890s: expected 8-digit "89005924" -> 6-digit "005924"
      final code3 = TotpHelper.generateTotp(
        secretBase32: secret,
        time: DateTime.fromMillisecondsSinceEpoch(
          1234567890 * 1000,
          isUtc: true,
        ),
        digits: 6,
      );
      expect(code3, equals('005924'));
    });

    test('Remaining seconds & progress ratio calculations', () {
      // 0 second into interval -> 30 remaining
      final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      expect(TotpHelper.getRemainingSeconds(time: t0), equals(30));
      expect(TotpHelper.getProgressRatio(time: t0), equals(1.0));

      // 10 seconds into interval -> 20 remaining
      final t10 = DateTime.fromMillisecondsSinceEpoch(10 * 1000, isUtc: true);
      expect(TotpHelper.getRemainingSeconds(time: t10), equals(20));
      expect(TotpHelper.getProgressRatio(time: t10), closeTo(20 / 30, 0.001));

      // 29 seconds into interval -> 1 remaining
      final t29 = DateTime.fromMillisecondsSinceEpoch(29 * 1000, isUtc: true);
      expect(TotpHelper.getRemainingSeconds(time: t29), equals(1));
    });

    test('Format code with space (123 456)', () {
      expect(TotpHelper.formatCodeWithSpace('123456'), equals('123 456'));
      expect(TotpHelper.formatCodeWithSpace('123'), equals('123'));
    });

    test('parseImportInput parses raw Base32 key', () {
      const raw = 'JBSWY3DPEHPK3PXP';
      final accounts = TotpHelper.parseImportInput(raw);
      expect(accounts.length, equals(1));
      expect(accounts.first.secret, equals(raw));
      expect(accounts.first.name, equals('Portal Staf'));
      expect(accounts.first.issuer, equals('BAPENDA'));
    });

    test('parseImportInput parses otpauth:// URI', () {
      const uri =
          'otpauth://totp/BAPENDA:petugas1?secret=JBSWY3DPEHPK3PXP&issuer=BAPENDA&digits=6';
      final accounts = TotpHelper.parseImportInput(uri);
      expect(accounts.length, equals(1));
      expect(accounts.first.secret, equals('JBSWY3DPEHPK3PXP'));
      expect(accounts.first.name, equals('BAPENDA:petugas1'));
      expect(accounts.first.issuer, equals('BAPENDA'));
      expect(accounts.first.digits, equals(6));
    });

    test(
      'parseImportInput parses otpauth-migration:// Google Authenticator export URI',
      () {
        // We can construct a minimal protobuf payload for testing:
        // OtpParameters { secret: "1234567890" (10 bytes), name: "cianjur_admin", issuer: "BAPENDA" }
        final secretBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        final nameBytes = utf8.encode('cianjur_admin');
        final issuerBytes = utf8.encode('BAPENDA');

        final otpBytes = <int>[
          // field 1 (secret, wire type 2): tag 0x0a, length 10
          0x0a, 10, ...secretBytes,
          // field 2 (name, wire type 2): tag 0x12, length
          0x12, nameBytes.length, ...nameBytes,
          // field 3 (issuer, wire type 2): tag 0x1a, length
          0x1a, issuerBytes.length, ...issuerBytes,
          // field 6 (type 2 = TOTP, wire type 0): tag 0x30, val 2
          0x30, 0x02,
        ];

        // MigrationPayload: field 1 (otp_parameters, wire type 2): tag 0x0a
        final payloadBytes = <int>[0x0a, otpBytes.length, ...otpBytes];
        final b64 = base64Encode(payloadBytes);
        final migrationUri = 'otpauth-migration://offline?data=$b64';

        final accounts = TotpHelper.parseImportInput(migrationUri);
        expect(accounts.length, equals(1));
        expect(accounts.first.name, equals('cianjur_admin'));
        expect(accounts.first.issuer, equals('BAPENDA'));
        expect(
          TotpHelper.base32Decode(accounts.first.secret),
          equals(secretBytes),
        );
      },
    );

    test('parseImportInput throws FormatException on invalid inputs', () {
      expect(() => TotpHelper.parseImportInput(''), throwsFormatException);
      expect(
        () => TotpHelper.parseImportInput('invalid!@@#'),
        throwsFormatException,
      );
    });

    test(
      'decodeQrFromImageBytes and parseQrImageBytes roundtrip with synthetic QR image',
      () {
        // 1. Buat gambar QR Code sintetis menggunakan zxing2 Encoder & package:image
        const qrPayload =
            'otpauth://totp/BAPENDA:petugas_qr?secret=JBSWY3DPEHPK3PXP&issuer=BAPENDA';
        final qr = Encoder.encode(qrPayload, ErrorCorrectionLevel.l);
        final matrix = qr.matrix!;

        const scale = 4;
        final image = img.Image(
          width: matrix.width * scale,
          height: matrix.height * scale,
        );
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            final isBlack = matrix.get(x ~/ scale, y ~/ scale) == 1;
            image.setPixelRgb(
              x,
              y,
              isBlack ? 0 : 255,
              isBlack ? 0 : 255,
              isBlack ? 0 : 255,
            );
          }
        }
        final pngBytes = Uint8List.fromList(img.encodePng(image));

        // 2. Decode teks dari bytes gambar
        final decodedText = TotpHelper.decodeQrFromImageBytes(pngBytes);
        expect(decodedText, equals(qrPayload));

        // 3. Parse langsung menjadi daftar akun TOTP
        final accounts = TotpHelper.parseQrImageBytes(pngBytes);
        expect(accounts.length, equals(1));
        expect(accounts.first.secret, equals('JBSWY3DPEHPK3PXP'));
        expect(accounts.first.name, equals('BAPENDA:petugas_qr'));
        expect(accounts.first.issuer, equals('BAPENDA'));

        // 4. Gambar kosong / bukan QR menghasilkan null / FormatException
        final blankImage = img.Image(width: 100, height: 100);
        final blankPng = Uint8List.fromList(img.encodePng(blankImage));
        expect(TotpHelper.decodeQrFromImageBytes(blankPng), isNull);
        expect(
          () => TotpHelper.parseQrImageBytes(blankPng),
          throwsFormatException,
        );
      },
    );
  });

  group('StaffAuthenticatorStore Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveSecret, hasSecret, getSecret, clearSecret roundtrip', () async {
      final store = StaffAuthenticatorStore();

      expect(await store.hasSecret(), isFalse);
      expect(await store.getSecret(), isNull);

      const secret = 'JBSWY3DPEHPK3PXP';
      await store.saveSecret(
        secret,
        accountName: 'petugas_bobojong',
        issuer: 'BAPENDA',
      );

      expect(await store.hasSecret(), isTrue);
      expect(await store.getSecret(), equals(secret));
      expect(await store.getAccountName(), equals('petugas_bobojong'));
      expect(await store.getIssuer(), equals('BAPENDA'));
      expect(
        await store.getAccountLabel(),
        equals('BAPENDA (petugas_bobojong)'),
      );

      // Code generated
      final code = await store.getCurrentCode();
      expect(code, isNotNull);
      expect(code!.length, equals(6));

      // Auto verify flag default is true
      expect(await store.isAutoVerifyEnabled(), isTrue);
      await store.setAutoVerifyEnabled(false);
      expect(await store.isAutoVerifyEnabled(), isFalse);

      // Clear
      await store.clearSecret();
      expect(await store.hasSecret(), isFalse);
      expect(await store.getSecret(), isNull);
      expect(await store.getCurrentCode(), isNull);
    });
  });
}
