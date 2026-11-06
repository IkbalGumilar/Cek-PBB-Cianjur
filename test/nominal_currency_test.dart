import 'package:flutter_test/flutter_test.dart';
import 'package:cek_pbb_app/currency_format.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_csv_codec.dart';

void main() {
  group('parseNominalRupiah & cleanNominalRupiah tests', () {
    test('parseNominalRupiah handles Indonesian decimal comma and dot correctly', () {
      expect(parseNominalRupiah('51.245,00'), 51245);
      expect(parseNominalRupiah('51.245.00'), 51245);
      expect(parseNominalRupiah('52.453,00'), 52453);
      expect(parseNominalRupiah('Rp 51.245,00'), 51245);
      expect(parseNominalRupiah('Rp. 52.453,00'), 52453);
      expect(parseNominalRupiah('51245.00'), 51245);
      expect(parseNominalRupiah('51245,00'), 51245);
    });

    test('parseNominalRupiah preserves regular rupiah without decimals', () {
      expect(parseNominalRupiah('52.453'), 52453);
      expect(parseNominalRupiah('Rp 51.425'), 51425);
      expect(parseNominalRupiah('Rp. 51.425'), 51425);
      expect(parseNominalRupiah('10.000'), 10000);
      expect(parseNominalRupiah('1.000.000'), 1000000);
      expect(parseNominalRupiah('Rp 50.000,-'), 50000);
      expect(parseNominalRupiah('150000'), 150000);
      expect(parseNominalRupiah(52453), 52453);
      expect(parseNominalRupiah(0), 0);
      expect(parseNominalRupiah('0'), 0);
      expect(parseNominalRupiah(''), 0);
      expect(parseNominalRupiah('-'), 0);
      expect(parseNominalRupiah(null), 0);
    });

    test('cleanNominalRupiah strips decimal sen and standardizes to Rp XX.XXX', () {
      expect(cleanNominalRupiah('51.245,00'), 'Rp 51.245');
      expect(cleanNominalRupiah('51.245.00'), 'Rp 51.245');
      expect(cleanNominalRupiah('52.453,00'), 'Rp 52.453');
      expect(cleanNominalRupiah('Rp 51.425'), 'Rp 51.425');
      expect(cleanNominalRupiah('150000'), '150000');
      expect(cleanNominalRupiah('0'), '0');
      expect(cleanNominalRupiah(''), '');
      expect(cleanNominalRupiah(null), '');
    });

    test('formatRupiah handles decimal sen without inflating value', () {
      expect(formatRupiah('51.245,00'), 'Rp. 51.245');
      expect(formatRupiah('51.245.00'), 'Rp. 51.245');
      expect(formatRupiah('52.453,00'), 'Rp. 52.453');
      expect(formatRupiah(52453), 'Rp. 52.453');
      expect(formatRupiah('Rp 51.425'), 'Rp. 51.425');
      expect(formatRupiah('-'), '-');
      expect(formatRupiah(''), '-');
    });

    test('BlokRecord.jumlahPbbValue correctly handles decimal sen', () {
      const recWithSenComma = BlokRecord(
        nop: '320520000401701610',
        namaWajibPajak: 'HAWIGYO',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: '51.245,00',
      );
      expect(recWithSenComma.jumlahPbbValue, 51245);

      const recWithSenDot = BlokRecord(
        nop: '320520000401701610',
        namaWajibPajak: 'HAWIGYO',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: '51.245.00',
      );
      expect(recWithSenDot.jumlahPbbValue, 51245);

      const recActual = BlokRecord(
        nop: '320520000401701610',
        namaWajibPajak: 'HAWIGYO',
        tahunBayar: '2026',
        tanggalBayar: '2026-11-06 10:00:13',
        jumlahPbb: '52.453,00',
      );
      expect(recActual.jumlahPbbValue, 52453);
    });

    test('BlokCsvCodec sanitizes decimal sen upon decoding', () {
      const csv = '''Nama WP,NOP,Tahun Bayar,Tanggal Bayar,Jumlah PBB,Status Bayar,Nama Foto,Target Pemda,Catatan
HAWIGYO,320520000401701610,2026,2026-11-06 10:00:13,"52.453,00",Sudah Bayar,,0,Sudah bayar''';

      final records = BlokCsvCodec.decodeDatabaseCsv(csv);
      expect(records.length, 1);
      final r = records.first;
      expect(r.jumlahPbb, 'Rp 52.453');
      expect(r.jumlahPbbValue, 52453);
      expect(r.isTargetPemda, false); // must NOT be target pemda (>= 1.5M)
    });
  });
}
