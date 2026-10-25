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

  test('menganggap versi beta lebih baru daripada alpha', () {
    expect(
      UpdateChecker.isNewerVersion('0.1.0-beta', '0.1.0-alpha.5'),
      isTrue,
    );
    expect(
      UpdateChecker.isNewerVersion('0.1.0-beta.2', '0.1.0-beta.1'),
      isTrue,
    );
  });

  test('isStableRelease hanya menerima rilis resmi dan menolak pre-release maupun draft', () {
    expect(
      UpdateChecker.isStableRelease({
        'tag_name': 'v1.0.0',
        'draft': false,
        'prerelease': false,
      }),
      isTrue,
    );
    expect(
      UpdateChecker.isStableRelease({
        'tag_name': 'v0.1.0-alpha.8',
        'draft': false,
        'prerelease': true,
      }),
      isFalse,
    );
    expect(
      UpdateChecker.isStableRelease({
        'tag_name': 'v0.1.0-beta.1',
        'draft': false,
        'prerelease': false,
      }),
      isFalse,
    );
    expect(
      UpdateChecker.isStableRelease({
        'tag_name': 'v1.0.0',
        'draft': true,
        'prerelease': false,
      }),
      isFalse,
    );
  });
}
