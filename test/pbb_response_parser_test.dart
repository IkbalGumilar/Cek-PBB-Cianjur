import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/pbb_client.dart';

void main() {
  final client = PbbClient();

  test('menangkap captcha yang salah dari pesan portal', () {
    expect(
      () => client.parseTagihanResponse('''
        <div class="alert alert-danger">
          <strong>Kode Verifikasi Harus Benar</strong>
        </div>
      '''),
      throwsA(isA<CaptchaError>()),
    );
  });

  test('menangkap SPPT tidak aktif dengan tahun', () {
    final result = client.parseTagihanResponse('''
      <div class="alert alert-danger">
        NOP yang anda masukan aktif sampai dengan tahun 1999.
        Silahkan datang ke kantor bapenda untuk menerbitkan SPPT terbaru
      </div>
    ''');

    expect(result.serverMessage, contains('dari tahun 1999'));
    expect(result.notFound, isFalse);
    expect(result.inactiveUntilYear, '1999');
    expect(result.rows, isEmpty);
  });

  test('menangkap SPPT tidak aktif tanpa tahun', () {
    final result = client.parseTagihanResponse('''
      <div class="alert alert-danger">
        NOP yang anda masukan aktif sampai dengan tahun .
        Silahkan datang ke kantor bapenda untuk menerbitkan SPPT terbaru
      </div>
    ''');

    expect(result.serverMessage, contains('SPPT tidak aktif'));
    expect(result.serverMessage, isNot(contains('tahun .')));
  });

  test('menangkap SPPT tidak aktif pada cek status bayar', () {
    final result = client.classifyStatusBayarResponse('''
      <div class="alert alert-danger">
        NOP yang anda masukan aktif sampai dengan tahun 1999.
      </div>
    ''');

    expect(result.status, contains('SPPT tidak aktif'));
    expect(result.status, contains('dari tahun 1999'));
  });
}
