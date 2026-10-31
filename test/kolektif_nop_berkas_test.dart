import 'dart:convert';
import 'dart:typed_data';

import 'package:cek_pbb_app/kolektif_nop_berkas.dart';
import 'package:cek_pbb_app/nop_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nop_helper', () {
    test(
      'expandNop expands 5, 6, and 7 digit shorthands into 18-digit NOP',
      () {
        expect(expandNop('17154'), '320520000401701540');
        expect(expandNop('300584'), '320520000403005840');
        expect(expandNop('0170154'), '320520000401701540');
        expect(expandNop('32.05.200.004.017-0154.0'), '320520000401701540');
      },
    );

    test('buildNop, nopBlok, nopWilayah, and formatNop work consistently', () {
      final nop = buildNop(blok: '17', wilayah: '154');
      expect(nop, '320520000401701540');
      expect(nopBlok(nop), '017');
      expect(nopWilayah(nop), '0154');
      expect(formatNop(nop), '32.05.200.004.017-0154.0');
    });
  });

  group('kolektif_nop_berkas', () {
    const kelCode = '3205200004';

    test(
      'uraikanSatuNop and uraikanNopKolektif parse full and shorthand NOPs',
      () {
        final full = uraikanSatuNop(
          '32.05.200.004.017-0154.0',
          kelurahanCode: kelCode,
        );
        expect(full.nop, '320520000401701540');
        expect(full.dariSingkatan, isFalse);

        final short = uraikanSatuNop('17154', kelurahanCode: kelCode);
        expect(short.nop, '320520000401701540');
        expect(short.dariSingkatan, isTrue);

        final multi = uraikanNopKolektif(
          '17154, 300584',
          kelurahanCode: kelCode,
        );
        expect(multi.error, isNull);
        expect(multi.nop, ['320520000401701540', '320520000403005840']);

        final bad = uraikanNopKolektif('17154, 123', kelurahanCode: kelCode);
        expect(bad.error, isNotNull);
        expect(bad.nop, isEmpty);
      },
    );

    test(
      'bacaBerkasNop reads CSV with UTF-8 BOM and auto-detects NOP column',
      () {
        const csvContent =
            '\uFEFFNo,Nama,NOP SPPT,Pokok\r\n'
            '1,ASEP,320520000401701540,85000\r\n'
            '2,DEDI,300584,92000\r\n';
        final result = bacaBerkasNop(
          namaBerkas: 'daftar_nop.csv',
          bytes: Uint8List.fromList(utf8.encode(csvContent)),
          kelurahanCode: kelCode,
        );

        expect(result.errorMessage, isNull);
        expect(result.kolomNop, 2);
        expect(result.terbaca, hasLength(2));
        expect(result.terbaca[0].nop, '320520000401701540');
        expect(result.terbaca[1].nop, '320520000403005840');
      },
    );

    test(
      'klasifikasiHasilTambahNop classifies server responses accurately',
      () {
        expect(
          klasifikasiHasilTambahNop(success: true, pesan: 'OK'),
          StatusImporNop.ditambahkan,
        );
        expect(
          klasifikasiHasilTambahNop(
            success: false,
            pesan: 'Tagihan SPPT sudah lunas',
          ),
          StatusImporNop.sudahBayar,
        );
        expect(
          klasifikasiHasilTambahNop(
            success: false,
            pesan: 'Data NOP tidak ditemukan di database',
          ),
          StatusImporNop.tidakDitemukan,
        );
        expect(
          klasifikasiHasilTambahNop(
            success: false,
            pesan: 'Terjadi kesalahan koneksi database',
          ),
          StatusImporNop.perluDiperiksa,
        );
      },
    );
  });
}
