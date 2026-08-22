import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nama-nama di bawah ini diambil apa adanya dari dropdown Kelurahan pada
/// halaman Pembayaran Kolektif yang dikirim pengguna — jadi yang diuji di sini
/// adalah data sungguhan, bukan contoh karangan.
void main() {
  group('rapikanNamaWilayah', () {
    test('nama yang dieja per huruf dirapatkan', () {
      expect(rapikanNamaWilayah('M A N D E'), 'MANDE');
      expect(rapikanNamaWilayah('J A M A L I'), 'JAMALI');
    });

    test('nama biasa tidak diubah', () {
      expect(rapikanNamaWilayah('BOBOJONG'), 'BOBOJONG');
      expect(rapikanNamaWilayah('CIKIDANGBAYABANG'), 'CIKIDANGBAYABANG');
      expect(rapikanNamaWilayah('KUTAWARINGIN'), 'KUTAWARINGIN');
      expect(rapikanNamaWilayah('MEKARJAYA'), 'MEKARJAYA');
    });

    test('nama bersuku kata banyak tidak ikut dirapatkan', () {
      // Cuma dirapatkan kalau SEMUA potongannya satu huruf; kalau ada satu saja
      // yang lebih panjang, spasinya memang bagian dari namanya.
      expect(rapikanNamaWilayah('PASIR SARONGGE'), 'PASIR SARONGGE');
      expect(rapikanNamaWilayah('J A M A L I RAYA'), 'J A M A L I RAYA');
    });

    test('spasi berlebih di tepi dibuang', () {
      expect(rapikanNamaWilayah('  BOBOJONG  '), 'BOBOJONG');
      expect(rapikanNamaWilayah(''), '');
    });
  });
}
