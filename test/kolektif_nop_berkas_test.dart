import 'dart:convert';
import 'dart:typed_data';

import 'package:cek_pbb_app/kolektif_nop_berkas.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kelurahan contoh: BOBOJONG, Kecamatan Mande (kode wilayah 10 digit yang
/// dipakai grup kolektif di layar Kelola Anggota).
const kel = '3205200004';

Uint8List teks(String isi) => Uint8List.fromList(utf8.encode(isi));

void main() {
  group('uraikanSatuNop', () {
    test('NOP lengkap 18 angka dipakai apa adanya', () {
      final h = uraikanSatuNop('320520000401701540', kelurahanCode: kel);
      expect(h.nop, '320520000401701540');
      expect(h.dariSingkatan, isFalse);
    });

    test('pemisah titik/strip di NOP lengkap diabaikan', () {
      final h = uraikanSatuNop('32.05.200.004.017-0154.0', kelurahanCode: kel);
      expect(h.nop, '320520000401701540');
    });

    test('singkatan 5-7 angka dilengkapi awalan kelurahan grup', () {
      expect(uraikanSatuNop('17154', kelurahanCode: kel).nop, '${kel}0170154' '0');
      expect(uraikanSatuNop('172836', kelurahanCode: kel).nop, '${kel}0172836' '0');
      expect(uraikanSatuNop('0172836', kelurahanCode: kel).nop, '${kel}0172836' '0');
      expect(uraikanSatuNop('17154', kelurahanCode: kel).dariSingkatan, isTrue);
    });

    test('4 angka ditolak karena bloknya belum ketahuan', () {
      final h = uraikanSatuNop('2836', kelurahanCode: kel);
      expect(h.nop, isNull);
      expect(h.alasan, contains('4 angka'));
    });

    test('sel kosong atau tanpa angka ditolak, bukan jadi NOP kosong', () {
      expect(uraikanSatuNop('', kelurahanCode: kel).nop, isNull);
      expect(uraikanSatuNop('NOP', kelurahanCode: kel).nop, isNull);
      expect(uraikanSatuNop('-', kelurahanCode: kel).nop, isNull);
    });

    test('tanpa kode kelurahan, singkatan ditolak — bukan diteruskan setengah jadi', () {
      // Awalan kosong berarti NOP-nya tidak bisa dilengkapi. Meloloskannya
      // sama dengan mengirim NOP milik entah siapa.
      expect(uraikanSatuNop('17154', kelurahanCode: '').nop, isNull);
    });
  });

  group('uraikanNopKolektif', () {
    test('beberapa NOP dipisah koma', () {
      final h = uraikanNopKolektif('172836, 172850', kelurahanCode: kel);
      expect(h.error, isNull);
      expect(h.nop, ['${kel}0172836' '0', '${kel}0172850' '0']);
    });

    test('satu entri salah membatalkan seluruh isian', () {
      final h = uraikanNopKolektif('172836,2850', kelurahanCode: kel);
      expect(h.nop, isEmpty);
      expect(h.error, contains('2850'));
    });

    test('isian tanpa angka sama sekali ditolak', () {
      expect(uraikanNopKolektif(' , ,', kelurahanCode: kel).error, isNotNull);
    });
  });

  group('tebakKolomNop', () {
    test('kolom berjudul NOP menang', () {
      final baris = [
        ['NO', 'NOP', 'NAMA'],
        ['1', '320520000401701540', 'ASEP'],
      ];
      expect(tebakKolomNop(baris, kelurahanCode: kel), 1);
    });

    test('judul yang mengandung "nop" tetap terbaca', () {
      final baris = [
        ['No Urut', 'NOP SPPT', 'Nama WP'],
        ['1', '320520000401701540', 'ASEP'],
      ];
      expect(tebakKolomNop(baris, kelurahanCode: kel), 1);
    });

    test('tanpa judul, kolom NOP 18 angka menang atas kolom nominal', () {
      // Kolom nominal (87453, 63767, ...) panjangnya 5 angka, jadi kalau
      // bobotnya sama ia ikut "terbaca" sebagai singkatan NOP dan bisa
      // terpilih. Bobot 18-angka harus menang telak.
      final baris = [
        ['320520000401701540', '87453'],
        ['320520000401702850', '63767'],
        ['320520000401702836', '51425'],
      ];
      expect(tebakKolomNop(baris, kelurahanCode: kel), 0);
    });

    test('tahun pajak 4 angka tidak pernah terbaca sebagai NOP', () {
      final baris = [
        ['2025', '320520000401701540'],
        ['2025', '320520000401702850'],
      ];
      expect(tebakKolomNop(baris, kelurahanCode: kel), 1);
    });

    test('tidak ada kolom yang masuk akal menghasilkan -1', () {
      final baris = [
        ['ASEP', '2025'],
        ['OPIK', '2024'],
      ];
      expect(tebakKolomNop(baris, kelurahanCode: kel), -1);
    });
  });

  group('bacaBerkasNop — CSV', () {
    test('berjudul NOP, baris judul masuk "tidak terbaca" bukan terkirim', () {
      final hasil = bacaBerkasNop(
        namaBerkas: 'daftar.csv',
        bytes: teks('NOP,NAMA\n320520000401701540,ASEP\n320520000401702850,OPIK\n'),
        kelurahanCode: kel,
      );
      expect(hasil.errorMessage, isNull);
      expect(hasil.kolomNop, 0);
      expect([for (final b in hasil.terbaca) b.nop], [
        '320520000401701540',
        '320520000401702850',
      ]);
      expect(hasil.tidakTerbaca.single.asli, 'NOP');
    });

    test('BOM dari Excel tidak merusak pencocokan judul kolom', () {
      // Excel selalu menaruh BOM UTF-8 di awal CSV. Kalau tidak dibuang, sel
      // pertama jadi "﻿NOP" dan judulnya tidak pernah cocok.
      final hasil = bacaBerkasNop(
        namaBerkas: 'excel.csv',
        bytes: teks('﻿NOP,NAMA\n320520000401701540,ASEP\n'),
        kelurahanCode: kel,
      );
      expect(hasil.kolomNop, 0);
      expect(hasil.terbaca.single.nop, '320520000401701540');
    });

    test('pemisah titik koma (CSV Excel Indonesia) ikut terbaca', () {
      final hasil = bacaBerkasNop(
        namaBerkas: 'idn.csv',
        bytes: teks('NOP;NAMA\n320520000401701540;ASEP\n320520000401702850;OPIK\n'),
        kelurahanCode: kel,
      );
      expect(hasil.kolomNop, 0);
      expect(hasil.terbaca.length, 2);
    });

    test('kolom bisa dipaksa kalau tebakannya keliru', () {
      final hasil = bacaBerkasNop(
        namaBerkas: 'daftar.csv',
        bytes: teks('NOP,CADANGAN\n320520000401701540,320520000401709990\n'),
        kelurahanCode: kel,
        kolomPaksa: 1,
      );
      expect(hasil.terbaca.single.nop, '320520000401709990');
    });

    test('singkatan di berkas ditandai supaya awalannya bisa diperiksa', () {
      final hasil = bacaBerkasNop(
        namaBerkas: 'singkat.csv',
        bytes: teks('NOP\n172836\n172850\n'),
        kelurahanCode: kel,
      );
      expect(hasil.terbaca.every((b) => b.dariSingkatan), isTrue);
      expect(hasil.terbaca.first.nop, '${kel}0172836' '0');
    });

    test('nomor baris menunjuk baris asli di berkas', () {
      final hasil = bacaBerkasNop(
        namaBerkas: 'daftar.csv',
        bytes: teks('NOP\n320520000401701540\n2836\n320520000401702850\n'),
        kelurahanCode: kel,
      );
      expect(hasil.tidakTerbaca.map((b) => b.nomorBaris), [1, 3]);
      expect(hasil.terbaca.map((b) => b.nomorBaris), [2, 4]);
    });

    test('berkas kosong dilaporkan, bukan menghasilkan daftar kosong diam-diam', () {
      final hasil = bacaBerkasNop(namaBerkas: 'kosong.csv', bytes: teks(''), kelurahanCode: kel);
      expect(hasil.errorMessage, isNotNull);
    });

    test('format berkas yang tidak didukung ditolak dengan jelas', () {
      final hasil = bacaBerkasNop(namaBerkas: 'daftar.pdf', bytes: teks('apa saja'), kelurahanCode: kel);
      expect(hasil.errorMessage, contains('belum didukung'));
    });
  });

  group('bacaBerkasNop — teks polos', () {
    test('satu NOP per baris', () {
      final hasil = bacaBerkasNop(
        namaBerkas: 'daftar.txt',
        bytes: teks('320520000401701540\n320520000401702850\n'),
        kelurahanCode: kel,
      );
      expect(hasil.terbaca.length, 2);
      expect(hasil.namaKolom.first, 'Kolom 1');
    });
  });

  group('klasifikasiHasilTambahNop', () {
    test('sukses berarti masuk grup', () {
      expect(
        klasifikasiHasilTambahNop(success: true, pesan: 'Berhasil'),
        StatusImporNop.ditambahkan,
      );
    });

    test('pesan lunas digolongkan sudah bayar', () {
      for (final p in [
        'NOP sudah bayar',
        'Tagihan sudah dibayar',
        'SPPT sudah lunas',
        'Tagihan telah dibayar',
      ]) {
        expect(klasifikasiHasilTambahNop(success: false, pesan: p), StatusImporNop.sudahBayar, reason: p);
      }
    });

    test('pesan tidak ketemu digolongkan tidak ditemukan', () {
      for (final p in ['NOP tidak ditemukan', 'Data tidak terdaftar', 'NOP tidak valid']) {
        expect(klasifikasiHasilTambahNop(success: false, pesan: p), StatusImporNop.tidakDitemukan, reason: p);
      }
    });

    test('pesan asing TIDAK dipaksa masuk golongan yang ada', () {
      // Menebak di sini berarti memberi tahu staf sesuatu yang belum tentu
      // benar tentang data pajak orang. Lebih baik ditampilkan apa adanya.
      expect(
        klasifikasiHasilTambahNop(success: false, pesan: 'Group sudah difinalkan'),
        StatusImporNop.perluDiperiksa,
      );
      expect(klasifikasiHasilTambahNop(success: false, pesan: null), StatusImporNop.perluDiperiksa);
      expect(klasifikasiHasilTambahNop(success: false, pesan: ''), StatusImporNop.perluDiperiksa);
    });
  });

  group('HasilImporNop', () {
    test('memilah item per golongan', () {
      const hasil = HasilImporNop(item: [
        ItemImporNop(nop: '1', status: StatusImporNop.ditambahkan),
        ItemImporNop(nop: '2', status: StatusImporNop.sudahBayar),
        ItemImporNop(nop: '3', status: StatusImporNop.ditambahkan),
        ItemImporNop(nop: '4', status: StatusImporNop.tidakDitemukan),
      ]);
      expect(hasil.ditambahkan.length, 2);
      expect(hasil.sudahBayar.single.nop, '2');
      expect(hasil.tidakDitemukan.single.nop, '4');
      expect(hasil.perluDiperiksa, isEmpty);
    });
  });
}
