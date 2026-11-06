import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dhkp/blok_csv_codec.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/dusun_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('dat_report_test_');
    BlokDataStore.instance.resetForTesting();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('unpackDkhp on .dat file matches existing records and adds new NOP without overwriting dusun scope', () async {
    // 1. Set initial dusun scope (Desa)
    await DusunData.instance.setScope(
      const DusunScope(role: 'desa', allowedBloks: ['001', '002', '003', '032']),
    );

    // 2. Initial existing records in BlokDataStore
    final existingRecords = [
      const BlokRecord(
        nop: '320520000403200010',
        namaWajibPajak: 'AGUS ASLI',
        tahunBayar: '2026',
        tanggalBayar: '',
        jumlahPbb: 'Rp 20.000',
        statusBayar: 'Belum Bayar',
        alamatObjek: 'Kp Serang',
      ),
      const BlokRecord(
        nop: '320520000403200010',
        namaWajibPajak: 'AGUS ASLI',
        tahunBayar: '2025',
        tanggalBayar: '2025-08-10 10:00:00',
        jumlahPbb: 'Rp 20.000',
        statusBayar: 'Sudah Bayar',
        alamatObjek: 'Kp Serang',
      ),
    ];
    await BlokDataStore.instance.upsertAll(existingRecords);

    // 3. Create a .dat report package containing:
    //    - An update for 320520000403200010 for year 2026 (now paid!)
    //    - A brand new NOP: 320520000403200990 (year 2026)
    //    - Manifest containing a restricted dusun scope (e.g. Dusun 4 only)
    final reportRecords = [
      const BlokRecord(
        nop: '320520000403200010',
        namaWajibPajak: 'AGUS ASLI',
        tahunBayar: '2026',
        tanggalBayar: '2026-09-15 14:00:00',
        jumlahPbb: 'Rp 20.000',
        statusBayar: 'Sudah Bayar',
        catatan: 'Lunas di petugas',
      ),
      const BlokRecord(
        nop: '320520000403200990',
        namaWajibPajak: 'WARGA BARU',
        tahunBayar: '2026',
        tanggalBayar: '2026-09-16 09:30:00',
        jumlahPbb: 'Rp 50.000',
        statusBayar: 'Sudah Bayar',
      ),
    ];

    final archive = Archive();
    final manifestMap = {
      'format': 'laporan_dat_v1',
      'scope': {'role': 'dusun', 'dusunNumber': 4, 'allowedBloks': ['032']},
    };
    final manifestBytes = utf8.encode(jsonEncode(manifestMap));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    final csvString = BlokCsvCodec.encodeRecords(reportRecords);
    final csvBytes = utf8.encode(csvString);
    archive.addFile(ArchiveFile('data.csv', csvBytes.length, csvBytes));

    final zipBytes = ZipEncoder().encode(archive)!;
    final datFile = File('${tempDir.path}/Laporan_Uji.dat');
    await datFile.writeAsBytes(zipBytes);

    // 4. Unpack the .dat file
    final unpacked = await DhkpPackageHelper.unpackDkhp(datFile.path);
    expect(unpacked.length, 2);

    // 5. Verify DusunData scope was NOT overwritten by the .dat report
    expect(DusunData.instance.scope.role, 'desa');

    // 6. Verify existing 2026 record was updated with 2026 payment date
    final stored = await BlokDataStore.instance.loadAll();
    final agus2026 = stored.firstWhere((r) => r.nop == '320520000403200010' && r.tahunBayar == '2026');
    expect(agus2026.isPaid, isTrue);
    expect(agus2026.tanggalBayar, '2026-09-15 14:00:00');
    expect(agus2026.catatan, 'Lunas di petugas');
    expect(agus2026.alamatObjek, 'Kp Serang'); // Preserved from base

    // 7. Verify existing 2025 record remained untouched
    final agus2025 = stored.firstWhere((r) => r.nop == '320520000403200010' && r.tahunBayar == '2025');
    expect(agus2025.tanggalBayar, '2025-08-10 10:00:00');

    // 8. Verify new NOP was added
    final wargaBaru = stored.firstWhere((r) => r.nop == '320520000403200990');
    expect(wargaBaru.namaWajibPajak, 'WARGA BARU');
    expect(wargaBaru.tahunBayar, '2026');
  });
}
