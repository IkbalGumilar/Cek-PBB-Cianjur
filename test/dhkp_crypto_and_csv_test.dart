import 'dart:convert';
import 'dart:typed_data';

import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_csv_codec.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlokCsvCodec', () {
    test('encodeRecords and decodeDatabaseCsv preserve all 18 columns', () {
      const sample = [
        BlokRecord(
          nop: '320520000401701540',
          namaWajibPajak: 'AHMAD SULAEMAN',
          tahunBayar: '2026',
          tanggalBayar: '2026-04-10',
          jumlahPbb: 'Rp. 125.000',
          statusBayar: 'Sudah Bayar',
          namaFoto: 'foto_017_0154.jpg',
          isTargetPemda: false,
          catatan: 'Lunas lewat RT',
          luasBumi: '120',
          luasBangunan: '45',
          njopBumi: '6000000',
          njopBangunan: '9000000',
          kecamatan: 'MANDE',
          kelurahan: 'BOBOJONG',
          alamatObjek: 'KP. BOBOJONG',
          alamatWp: 'JL. RAYA MANDE',
          rtObjek: '002',
        ),
        BlokRecord(
          nop: '320520000403005840',
          namaWajibPajak: 'PT PERKEBUNAN NUSANTARA',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: 'Rp. 2.500.000',
          statusBayar: 'Belum Bayar',
          isTargetPemda: true,
          catatan: 'Target Pemda',
        ),
      ];

      final csv = BlokCsvCodec.encodeRecords(sample);
      final decoded = BlokCsvCodec.decodeDatabaseCsv(csv);

      expect(decoded, hasLength(2));
      expect(decoded[0].nop, '320520000401701540');
      expect(decoded[0].namaWajibPajak, 'AHMAD SULAEMAN');
      expect(decoded[0].tahunBayar, '2026');
      expect(decoded[0].tanggalBayar, '2026-04-10');
      expect(decoded[0].jumlahPbb, 'Rp. 125.000');
      expect(decoded[0].statusBayar, 'Sudah Bayar');
      expect(decoded[0].namaFoto, 'foto_017_0154.jpg');
      expect(decoded[0].isTargetPemda, isFalse);
      expect(decoded[0].catatan, 'Lunas lewat RT');
      expect(decoded[0].luasBumi, '120');
      expect(decoded[0].luasBangunan, '45');
      expect(decoded[0].njopBumi, '6000000');
      expect(decoded[0].njopBangunan, '9000000');
      expect(decoded[0].kecamatan, 'MANDE');
      expect(decoded[0].kelurahan, 'BOBOJONG');
      expect(decoded[0].alamatObjek, 'KP. BOBOJONG');
      expect(decoded[0].alamatWp, 'JL. RAYA MANDE');
      expect(decoded[0].rtObjek, '002');

      expect(decoded[1].nop, '320520000403005840');
      expect(decoded[1].isTargetPemda, isTrue);
      expect(decoded[1].statusBayar, 'Belum Bayar');
    });

    test('decodeDatabaseCsv supports legacy 4-column CSV', () {
      const legacyCsv =
          'Nama WP,NOP,Tahun Bayar,Tanggal Bayar\r\n'
          'BUDI SANTOSO,320520000401701540,2025,2025-05-01\r\n';
      final decoded = BlokCsvCodec.decodeDatabaseCsv(legacyCsv);
      expect(decoded, hasLength(1));
      expect(decoded.first.namaWajibPajak, 'BUDI SANTOSO');
      expect(decoded.first.nop, '320520000401701540');
      expect(decoded.first.statusBayar, 'Sudah Bayar');
    });

    test(
      'decodeArchiveCsv auto-marks records >= 1,500,000 as Target Pemda when column is empty',
      () {
        const archiveCsv =
            'Nama WP,NOP,Tahun Bayar,Tanggal Bayar,Jumlah PBB,Status Bayar,Foto,Target Pemda\r\n'
            'WARGA BIASA,320520000401701540,2026,,50000,Belum Bayar,,\r\n'
            'WAJIB PAJAK BESAR,320520000403005840,2026,,1500000,Belum Bayar,,\r\n';
        final decoded = BlokCsvCodec.decodeArchiveCsv(archiveCsv);
        expect(decoded, hasLength(2));
        expect(decoded[0].isTargetPemda, isFalse);
        expect(decoded[1].isTargetPemda, isTrue);
      },
    );

    test('tryDecodeLegacyPlainCsv detects plain CSV starting with Nama WP', () {
      final validBytes = Uint8List.fromList(
        utf8.encode('Nama WP,NOP,Tahun Bayar,Tanggal Bayar\n'),
      );
      final invalidBytes = Uint8List.fromList([0x44, 0x4B, 0x48, 0x32, 0x00]);
      expect(BlokCsvCodec.tryDecodeLegacyPlainCsv(validBytes), isNotNull);
      expect(BlokCsvCodec.tryDecodeLegacyPlainCsv(invalidBytes), isNull);
    });
  });

  group('DhkpCrypto & DkhpPackageHelper', () {
    test(
      'encryptBytes and decryptBytes (DKH2 AES-256-GCM) roundtrip and reject wrong password',
      () async {
        final plain = Uint8List.fromList(
          utf8.encode('Data DHKP Rahasia Desa Bobojong 2026'),
        );
        final encrypted = await DhkpCrypto.encryptBytes(
          plain,
          password: 'PasswordKuat123!',
        );

        expect(DhkpCrypto.isEncrypted(encrypted), isTrue);
        expect(DhkpCrypto.isPasswordProtected(encrypted), isTrue);

        final decrypted = await DhkpCrypto.decryptBytes(
          encrypted,
          password: 'PasswordKuat123!',
        );
        expect(decrypted, equals(plain));

        await expectLater(
          () => DhkpCrypto.decryptBytes(encrypted, password: 'SalahPassword99'),
          throwsA(isA<DkhpPasswordException>()),
        );

        await expectLater(
          () => DhkpCrypto.decryptBytes(encrypted),
          throwsA(isA<DkhpPasswordException>()),
        );
      },
    );

    test(
      'encryptLegacyBytes and decryptBytes (DKHP AES-256-CBC) roundtrip',
      () async {
        final plain = Uint8List.fromList(utf8.encode('Legacy Paket DHKP v1'));
        final encrypted = DhkpCrypto.encryptLegacyBytes(plain);

        expect(DhkpCrypto.isEncrypted(encrypted), isTrue);
        expect(DhkpCrypto.isPasswordProtected(encrypted), isFalse);

        final decrypted = await DhkpCrypto.decryptBytes(encrypted);
        expect(decrypted, equals(plain));
      },
    );

    test(
      'DkhpPackageHelper.computeRecordsFingerprint is deterministic regardless of record order',
      () {
        const recA = BlokRecord(
          nop: '320520000401701540',
          namaWajibPajak: 'A',
          tahunBayar: '2026',
          tanggalBayar: '',
        );
        const recB = BlokRecord(
          nop: '320520000403005840',
          namaWajibPajak: 'B',
          tahunBayar: '2026',
          tanggalBayar: '',
        );

        final fp1 = DhkpPackageHelper.computeDhkpFingerprint([recA, recB]);
        final fp2 = DhkpPackageHelper.computeDhkpFingerprint([recB, recA]);
        expect(fp1, isNotEmpty);
        expect(fp1, equals(fp2));
      },
    );
  });
}
