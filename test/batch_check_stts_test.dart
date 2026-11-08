import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/batch_check_screen.dart';
import 'package:cek_pbb_app/pbb_client.dart';
import 'package:cek_pbb_app/tax_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends PbbClient {
  final List<String> sttsRequests = [];

  @override
  Future<PbbResult> checkStatusViaDocument(String nop, {String? tahun}) async {
    // NOP berakhiran 1 = sudah bayar, selain itu belum bayar.
    return nop.endsWith('1')
        ? PbbResult('Sudah Bayar', 'LUNAS', tanggalBayar: '2026-05-05')
        : PbbResult('Belum Bayar', 'Tunggakan');
  }

  @override
  Future<Uint8List?> fetchSttsPdfIfIssued({
    required String nop,
    required String tahun,
  }) async {
    sttsRequests.add(nop);
    return Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }
}

Future<void> _runScreen(
  WidgetTester tester,
  _FakeClient client,
  List<TaxRecord> records, {
  required bool downloadStts,
  Directory? sttsTargetDirectory,
  String? sttsBlokNumber,
}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2026',
          client: client,
          pacingDelay: Duration.zero,
          cooldownBatchSize: 0,
          downloadStts: downloadStts,
          sttsTargetDirectory: sttsTargetDirectory,
          sttsBlokNumber: sttsBlokNumber,
        ),
      ),
    );
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (records.every((r) => r.isChecked)) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
}

void main() {
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('stts_test_');
    AppStorage.setMockDirectories(dataDir: tmp, mediaDir: tmp);
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('opsi unduh STTS aktif: hanya NOP sudah bayar yang diunduh', (
    tester,
  ) async {
    final client = _FakeClient();
    final records = [
      TaxRecord(nop: '320520000402200011', namaWajibPajak: 'PAID'),
      TaxRecord(nop: '320520000402200050', namaWajibPajak: 'UNPAID'),
    ];
    await _runScreen(tester, client, records, downloadStts: true);

    expect(client.sttsRequests, ['320520000402200011']);
    expect(records[0].buktiBayarDownloaded, isTrue);
    expect(records[1].buktiBayarDownloaded, isNull);
  });

  testWidgets('opsi unduh STTS mati: tidak ada STTS yang diunduh', (
    tester,
  ) async {
    final client = _FakeClient();
    final records = [
      TaxRecord(nop: '320520000402200011', namaWajibPajak: 'PAID'),
    ];
    await _runScreen(tester, client, records, downloadStts: false);

    expect(client.sttsRequests, isEmpty);
    expect(records[0].buktiBayarDownloaded, isNull);
  });

  testWidgets('unduh STTS dengan folder blok: PDF dan file info txt tersimpan langsung', (
    tester,
  ) async {
    final client = _FakeClient();
    final blokFolder = Directory('${tmp.path}/STTS Blok 001 - Minggu, 08-11-2026')
      ..createSync(recursive: true);

    final records = [
      TaxRecord(
        nop: '320520000402200011',
        namaWajibPajak: 'FULAN',
        jumlahPbb: '50.000',
      ),
      TaxRecord(
        nop: '320520000402200050',
        namaWajibPajak: 'FOO',
        jumlahPbb: '25.000',
      ),
    ];

    await _runScreen(
      tester,
      client,
      records,
      downloadStts: true,
      sttsTargetDirectory: blokFolder,
      sttsBlokNumber: '001',
    );

    // File STTS PDF tersimpan langsung di blokFolder
    final pdfFiles = blokFolder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList();
    expect(pdfFiles.length, 1);
    expect(pdfFiles.first.path, contains('FULAN'));

    // File info txt tersimpan dan berisi rangkuman
    final infoFile = File('${blokFolder.path}/INFORMASI_BLOK_001.txt');
    expect(infoFile.existsSync(), isTrue);
    final content = infoFile.readAsStringSync();
    expect(content, contains('INFORMASI REKAPITULASI PENGECEKAN BLOK'));
    expect(content, contains('Nomor Blok        : Blok 001'));
    expect(content, contains('320520000402200011'));
    expect(content, contains('Status Pengecekan : Selesai'));
  });
}
