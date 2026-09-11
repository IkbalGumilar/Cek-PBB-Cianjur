import 'package:cek_pbb_app/desil/bansos_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parser membaca hasil NIK Kemensos tanpa menyimpan NIK', () {
    final result = BansosResult.fromHtml('''
      <span class="badge">DTSEN TRIWULAN 3.1 2026</span>
      <table><tbody><tr>
        <td>S***I P*****A</td><td>3</td><td>TIDAK</td><td>-</td>
        <td>TIDAK</td><td>-</td><td>YA</td><td>PBI JKN DESEMBER 2025</td>
        <td>-</td><td>TIDAK</td>
      </tr></tbody></table>
    ''');

    expect(result.nama, 'S***I P*****A');
    expect(result.desil, '3');
    expect(result.pbiJkStatus, 'YA');
    expect(result.periodeDtsen, 'DTSEN TRIWULAN 3.1 2026');
  });

  test('parser menolak halaman hasil tanpa tabel layanan', () {
    expect(
      () => BansosResult.fromHtml('<div>Captcha salah, silakan ulangi.</div>'),
      throwsA(
        isA<BansosException>().having(
          (error) => error.kind,
          'kind',
          BansosErrorKind.captcha,
        ),
      ),
    );
  });

  test('parser membedakan data penerima yang tidak ditemukan', () {
    expect(
      () => BansosResult.fromHtml('<div>Data tidak ditemukan.</div>'),
      throwsA(
        isA<BansosException>().having(
          (error) => error.kind,
          'kind',
          BansosErrorKind.notFound,
        ),
      ),
    );
  });

  test('parser memberi pesan aman ketika struktur halaman berubah', () {
    expect(
      () => BansosResult.fromHtml('<main>Gangguan layanan</main>'),
      throwsA(
        isA<BansosException>()
            .having(
              (error) => error.message,
              'message',
              'Hasil dari layanan belum dapat diproses. Silakan coba lagi nanti.',
            )
            .having((error) => error.kind, 'kind', BansosErrorKind.service),
      ),
    );
  });
}
