import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/update_checker.dart';

void main() {
  test('mendeteksi alpha3 sebagai pembaruan dari alpha2', () {
    expect(
      UpdateChecker.isNewerVersion('0.1.0-alpha.3', '0.1.0-alpha.2'),
      isTrue,
    );
  });

  test('menganggap versi stabil lebih baru daripada prerelease', () {
    expect(UpdateChecker.isNewerVersion('0.1.0', '0.1.0-alpha.3'), isTrue);
  });

  test('tidak menganggap alpha2 lebih baru daripada alpha3', () {
    expect(
      UpdateChecker.isNewerVersion('0.1.0-alpha.2', '0.1.0-alpha.3'),
      isFalse,
    );
  });
}
