import 'dart:typed_data';

import 'package:cek_pbb_app/captcha_ocr_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptchaOcrHelper.cleanCaptchaText', () {
    test('mengubah huruf kapital menjadi huruf kecil', () {
      expect(CaptchaOcrHelper.cleanCaptchaText('MISLED'), 'misled');
      expect(CaptchaOcrHelper.cleanCaptchaText('PugGed'), 'pugged');
    });

    test('menghilangkan spasi dan baris baru antar karakter', () {
      expect(CaptchaOcrHelper.cleanCaptchaText('m i s l e d'), 'misled');
      expect(CaptchaOcrHelper.cleanCaptchaText('p\nu\ng\ng\ne\nd'), 'pugged');
    });

    test('menghilangkan tanda baca dan simbol non-alfanumerik', () {
      expect(CaptchaOcrHelper.cleanCaptchaText('dup-ing!'), 'duping');
      expect(CaptchaOcrHelper.cleanCaptchaText('w.e_t#t@e*d'), 'wetted');
    });

    test('mempertahankan angka jika ada dalam captcha', () {
      expect(CaptchaOcrHelper.cleanCaptchaText('abc123xyz'), 'abc123xyz');
    });

    test('mengembalikan null untuk string kosong atau hanya spasi/simbol', () {
      expect(CaptchaOcrHelper.cleanCaptchaText(''), isNull);
      expect(CaptchaOcrHelper.cleanCaptchaText('   \n\t  '), isNull);
      expect(CaptchaOcrHelper.cleanCaptchaText('!@#\$%^&*()'), isNull);
    });
  });

  group('CaptchaOcrHelper.recognizeCaptcha', () {
    tearDown(() {
      CaptchaOcrHelper.ocrRunnerForTesting = null;
    });

    test('menggunakan runner pengujian dan membersihkan hasilnya', () async {
      CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => '  Mis-Led \n';

      final result = await CaptchaOcrHelper.recognizeCaptcha(Uint8List(0));
      expect(result, 'misled');
    });

    test('mengembalikan null jika runner pengujian menghasilkan string kosong', () async {
      CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => '';

      final result = await CaptchaOcrHelper.recognizeCaptcha(Uint8List(0));
      expect(result, isNull);
    });

    test('mengembalikan null secara aman di lingkungan desktop tanpa runner', () async {
      CaptchaOcrHelper.ocrRunnerForTesting = null;

      // Di linux desktop headless test, tidak melempar exception dan return null
      final result = await CaptchaOcrHelper.recognizeCaptcha(Uint8List(0));
      expect(result, isNull);
    });
  });
}
