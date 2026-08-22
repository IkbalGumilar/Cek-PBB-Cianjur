import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Angka-angka contoh di bawah diambil apa adanya dari tabel anggota grup
/// "IKBAL 4" pada halaman Pembayaran Kolektif yang dikirim pengguna, termasuk
/// total di kaki tabelnya. Ini perhitungan uang, jadi dikunci lewat test.
void main() {
  group('parseAngkaServer', () {
    test('angka dengan pemisah ribuan', () {
      expect(parseAngkaServer('87,453'), 87453);
      expect(parseAngkaServer('51,425'), 51425);
      expect(parseAngkaServer('12,342'), 12342);
      expect(parseAngkaServer('0'), 0);
    });

    test('angka berdesimal tidak ikut terkali seratus', () {
      // Kaki tabel aslinya menulis "( Rp 590,540.00 )". Kalau titik & koma
      // dibuang mentah-mentah, hasilnya 59054000 — seratus kali lipat.
      expect(parseAngkaServer('590,540.00'), 590540);
      expect(parseAngkaServer('Rp 590,540.00'), 590540);
      expect(parseAngkaServer('1,234,567.89'), 1234567);
    });

    test('isian kosong atau bukan angka jadi nol, bukan error', () {
      expect(parseAngkaServer(''), 0);
      expect(parseAngkaServer('-'), 0);
      expect(parseAngkaServer('  '), 0);
    });

    test('total satu grup nyata sesuai kaki tabel aslinya', () {
      // 10 baris pertama grup "IKBAL 4" beserta totalnya (Rp 590,540.00).
      const totalPerBaris = [
        '87,453',
        '63,767',
        '63,767',
        '51,425',
        '63,767',
        '76,109',
        '81,900',
        '29,520',
        '59,400',
        '13,432',
      ];
      final jumlah = totalPerBaris.fold<int>(
        0,
        (a, b) => a + parseAngkaServer(b),
      );
      expect(jumlah, parseAngkaServer('590,540.00'));
    });
  });
}
