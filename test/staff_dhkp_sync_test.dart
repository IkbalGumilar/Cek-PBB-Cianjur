import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_sync_dialog.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_sync_service.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStaffPortalClient extends StaffPortalClient {
  final Map<String, MonitoringTableResult> responses;
  final Map<int, MonitoringTableResult>? pageResponses;
  final Map<int, MonitoringTableResult>? belumBayarPageResponses;

  FakeStaffPortalClient({
    this.responses = const {},
    this.pageResponses,
    this.belumBayarPageResponses,
  });

  @override
  Future<MonitoringTableResult> fetchBelumBayar({
    required String tglCutoff,
    String tahunAwal = '',
    String tahunAkhir = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String bukuMin = '',
    String bukuMax = '',
    String kelurahan = '3205200004',
    String kecamatan = '3205200',
    int page = 1,
  }) async {
    if (belumBayarPageResponses != null &&
        belumBayarPageResponses!.containsKey(page)) {
      return belumBayarPageResponses![page]!;
    }
    return const MonitoringTableResult(
      headers: ['No', 'NOP', 'Nama WP', 'Pokok'],
      rows: [],
      hasNextPage: false,
    );
  }

  @override
  Future<MonitoringTableResult> fetchSudahBayar({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    String tahunAwal = '',
    String tahunAkhir = '',
    String bukuMin = '',
    String bukuMax = '',
    String bank = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String kodeBayarKolektif = '',
    String va = '',
    String qris = '',
    String operator = '',
    String tglPelimpahanAwal = '',
    String tglPelimpahanAkhir = '',
    String kelurahan = '3205200004',
    String kecamatan = '3205200',
    int page = 1,
  }) async {
    if (pageResponses != null && pageResponses!.containsKey(page)) {
      return pageResponses![page]!;
    }
    return responses[nop] ??
        responses.values.firstOrNull ??
        const MonitoringTableResult(
          headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar'],
          rows: [],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StaffDhkpSyncService.parseRow', () {
    test('extracts NOP, Nama WP, Pokok, and normalized Tanggal Bayar from standard headers', () {
      final headers = ['No', 'NOP', 'Nama Wajib Pajak', 'Pokok Bayar', 'Tanggal Bayar'];
      final cells = ['1', '32.05.200.004.024-0012.0', 'HJ. SITI MARYAM', '150.000', '15-08-2025'];

      final parsed = StaffDhkpSyncService.parseRow(cells, headers, defaultTahun: '2025');
      expect(parsed, isNotNull);
      expect(parsed!.nop, '320520000402400120');
      expect(parsed.namaWp, 'HJ. SITI MARYAM');
      expect(parsed.jumlahPbb, '150000');
      expect(parsed.tanggalBayar, '2025-08-15');
    });

    test('falls back to regex cell inspection when headers do not match', () {
      final headers = ['Kolom 1', 'Kolom 2', 'Kolom 3'];
      final cells = ['Data A', '320520000402400990', 'Keterangan B'];

      final parsed = StaffDhkpSyncService.parseRow(cells, headers, defaultTahun: '2026');
      expect(parsed, isNotNull);
      expect(parsed!.nop, '320520000402400990');
    });

    test('returns null when no 18-digit NOP is found in cells', () {
      final headers = ['No', 'Nama'];
      final cells = ['1', 'Budi'];

      final parsed = StaffDhkpSyncService.parseRow(cells, headers);
      expect(parsed, isNull);
    });
  });

  group('StaffDhkpSyncService.syncBloks execution', () {
    test('updates unpaid record to paid, preserves note, and discovers new SPPT', () async {
      // Setup existing records in store
      const existingUnpaid = BlokRecord(
        nop: '320520000402400010',
        namaWajibPajak: 'WARGA LAMA',
        tahunBayar: '2025',
        tanggalBayar: '',
        jumlahPbb: '75000',
        statusBayar: 'Belum Bayar',
        catatan: 'Catatan penting kolektor',
      );

      await BlokDataStore.instance.upsert(existingUnpaid);

      // Server returns 2 rows for Blok 024:
      // 1) The existing record (now marked paid on server)
      // 2) A brand new SPPT never in DHKP before
      final fakeResponses = {
        '3205200004024': const MonitoringTableResult(
          headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar', 'Alamat OP'],
          rows: [
            ['1', '320520000402400010', 'WARGA LAMA', '75.000', '2025-06-20', 'KP. SUKAMAJU'],
            ['2', '320520000402400099', 'WARGA BARU BAPENDA', '125.000', '2025-07-10', 'KP. MEKARSARI'],
          ],
        ),
      };

      final client = FakeStaffPortalClient(responses: fakeResponses);

      final outcome = await StaffDhkpSyncService.instance.syncBloks(
        client: client,
        tahun: '2025',
        bloks: ['024'],
        kelurahanCode: '3205200004',
        kecamatanCode: '3205200',
        pacingDelay: Duration.zero,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.totalCheckedRows, 2);
      expect(outcome.updatedPaidCount, 1);
      expect(outcome.newSpptCount, 1);

      // Verify in database store
      final all = await BlokDataStore.instance.loadAll();
      final updated = all.firstWhere((r) => r.nop == '320520000402400010' && r.tahunBayar == '2025');
      expect(updated.isPaid, isTrue);
      expect(updated.tanggalBayar, '2025-06-20');
      // Existing note must be preserved!
      expect(updated.catatan, 'Catatan penting kolektor');

      final newRecord = all.firstWhere((r) => r.nop == '320520000402400099' && r.tahunBayar == '2025');
      expect(newRecord.namaWajibPajak, 'WARGA BARU BAPENDA');
      expect(newRecord.isPaid, isTrue);
      expect(newRecord.jumlahPbb, '125000');
      expect(newRecord.alamatObjek, 'KP. MEKARSARI');
    });

    test('respects shouldCancel flag during sync', () async {
      final client = FakeStaffPortalClient();
      final outcome = await StaffDhkpSyncService.instance.syncBloks(
        client: client,
        tahun: '2025',
        bloks: ['001', '002', '003'],
        kelurahanCode: '3205200004',
        kecamatanCode: '3205200',
        shouldCancel: () => true,
        pacingDelay: Duration.zero,
      );

      expect(outcome.isCancelled, isTrue);
    });

    test('fetches all paginated pages until hasNextPage is false', () async {
      final page1 = const MonitoringTableResult(
        headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar'],
        rows: [
          ['1', '320520000400100010', 'WARGA BLOK 1', '50.000', '2025-05-10'],
        ],
        totalRecords: 2,
        pageStart: 1,
        pageEnd: 1,
        hasNextPage: true,
      );

      final page2 = const MonitoringTableResult(
        headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar'],
        rows: [
          ['2', '320520000402200020', 'WARGA BLOK 22', '75.000', '2025-05-12'],
        ],
        totalRecords: 2,
        pageStart: 2,
        pageEnd: 2,
        hasNextPage: false,
      );

      final client = FakeStaffPortalClient(pageResponses: {1: page1, 2: page2});

      final outcome = await StaffDhkpSyncService.instance.syncBloks(
        client: client,
        tahun: '2025',
        bloks: ['001', '022'],
        kelurahanCode: '3205200004',
        kecamatanCode: '3205200',
        pacingDelay: Duration.zero,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.totalCheckedRows, 2);
      expect(outcome.newSpptCount, 2);

      final all = await BlokDataStore.instance.loadAll();
      expect(all.any((r) => r.nop == '320520000400100010'), isTrue);
      expect(all.any((r) => r.nop == '320520000402200020'), isTrue);
    });

    test('syncs both Belum Bayar and Sudah Bayar in full mode', () async {
      await BlokDataStore.instance.upsertAll([
        const BlokRecord(
          nop: '320520000402500010',
          namaWajibPajak: 'WARGA LAMA BB',
          tahunBayar: '2025',
          statusBayar: 'Belum Bayar',
          tanggalBayar: '',
          luasBumi: '100',
        ),
        const BlokRecord(
          nop: '320520000402500020',
          namaWajibPajak: 'WARGA LAMA SB',
          tahunBayar: '2025',
          statusBayar: 'Belum Bayar',
          tanggalBayar: '',
        ),
      ]);

      final bbPage = const MonitoringTableResult(
        headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Luas Bumi', 'NJOP Bumi', 'Alamat OP'],
        rows: [
          ['1', '320520000402500010', 'WARGA BELUM BAYAR', '80.000', '150', '20.000.000', 'KP. BARU'],
        ],
        totalRecords: 1,
        hasNextPage: false,
      );

      final sbPage = const MonitoringTableResult(
        headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar'],
        rows: [
          ['1', '320520000402500020', 'WARGA LAMA SB', '95.000', '2025-06-15'],
          ['2', '320520000402500030', 'WARGA BARU LUNAS', '110.000', '2025-07-20'],
        ],
        totalRecords: 2,
        hasNextPage: false,
      );

      final client = FakeStaffPortalClient(
        belumBayarPageResponses: {1: bbPage},
        pageResponses: {1: sbPage},
      );

      final outcome = await StaffDhkpSyncService.instance.syncBloks(
        client: client,
        tahun: '2025',
        bloks: ['025'],
        kelurahanCode: '3205200004',
        kecamatanCode: '3205200',
        mode: StaffSyncMode.full,
        pacingDelay: Duration.zero,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.totalCheckedRows, 3);
      expect(outcome.newSpptCount, 1);
      expect(outcome.updatedPaidCount, 1);

      final all = await BlokDataStore.instance.loadAll();
      final unpaid = all.firstWhere((r) => r.nop == '320520000402500010');
      expect(unpaid.isPaid, isFalse);
      expect(unpaid.namaWajibPajak, 'WARGA BELUM BAYAR');
      expect(unpaid.luasBumi, '150');

      final paid = all.firstWhere((r) => r.nop == '320520000402500020');
      expect(paid.isPaid, isTrue);
      expect(paid.tanggalBayar, '2025-06-15');

      final newRecord = all.firstWhere((r) => r.nop == '320520000402500030');
      expect(newRecord.isPaid, isTrue);
      expect(newRecord.namaWajibPajak, 'WARGA BARU LUNAS');
    });

    test('strictly ignores unknown NOPs in Belum Bayar and does not add as new SPPT', () async {
      final bbPage = const MonitoringTableResult(
        headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Luas Bumi', 'NJOP Bumi', 'Alamat OP'],
        rows: [
          ['1', '320520000402500099', 'NOP NONAKTIF MENEMPEL', '50.000', '100', '10.000.000', 'KP. LAMA'],
        ],
        totalRecords: 1,
        hasNextPage: false,
      );

      final client = FakeStaffPortalClient(
        belumBayarPageResponses: {1: bbPage},
        pageResponses: const {},
      );

      final outcome = await StaffDhkpSyncService.instance.syncBloks(
        client: client,
        tahun: '2025',
        bloks: ['025'],
        kelurahanCode: '3205200004',
        kecamatanCode: '3205200',
        mode: StaffSyncMode.full,
        pacingDelay: Duration.zero,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.newSpptCount, 0);
      expect(outcome.newRecords, isEmpty);

      final all = await BlokDataStore.instance.loadAll();
      expect(all.any((r) => r.nop == '320520000402500099'), isFalse);
    });
  });

  group('StaffDhkpSyncDialog UI', () {
    testWidgets('shows dialog with Tahun, Blok, and local DHKP status counters', (tester) async {
      await BlokDataStore.instance.upsertAll([
        const BlokRecord(
          nop: '320520000402400010',
          namaWajibPajak: 'WARGA A',
          tahunBayar: '2025',
          statusBayar: 'Sudah Bayar',
          tanggalBayar: '2025-01-01',
          jumlahPbb: '50000',
        ),
        const BlokRecord(
          nop: '320520000402400020',
          namaWajibPajak: 'WARGA B',
          tahunBayar: '2025',
          statusBayar: 'Belum Bayar',
          tanggalBayar: '',
          jumlahPbb: '50000',
        ),
      ]);

      final client = FakeStaffPortalClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showStaffDhkpSyncDialog(ctx, client: client),
                child: const Text('Buka Dialog'),
              ),
            ),
          ),
        ),
      );

      // Tap to open dialog
      await tester.tap(find.text('Buka Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Sinkronkan Status ke DHKP'), findsOneWidget);
      expect(find.text('Mulai Sinkronisasi'), findsOneWidget);
      expect(find.text('Data DHKP Tersimpan Saat Ini:'), findsOneWidget);
    });

    testWidgets('shows sync report dialog with tabs and filter', (tester) async {
      final outcome = StaffDhkpSyncOutcome(
        tahun: '2025',
        blokLabel: 'Blok 25',
        totalCheckedRows: 10,
        updatedPaidCount: 1,
        newSpptCount: 1,
        updatedNops: const ['320520000402500020'],
        newNops: const ['320520000402500030'],
        updatedRecords: const [
          BlokRecord(
            nop: '320520000402500020',
            namaWajibPajak: 'WARGA LAMA',
            tahunBayar: '2025',
            statusBayar: 'Sudah Bayar',
            tanggalBayar: '2025-06-15',
            jumlahPbb: '95000',
          ),
        ],
        newRecords: const [
          BlokRecord(
            nop: '320520000402500030',
            namaWajibPajak: 'WARGA BARU',
            tahunBayar: '2025',
            statusBayar: 'Sudah Bayar',
            tanggalBayar: '2025-07-20',
            jumlahPbb: '110000',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showStaffDhkpSyncReportDialog(ctx, outcome),
                child: const Text('Buka Laporan'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Laporan'));
      await tester.pumpAndSettle();

      expect(find.text('Laporan Hasil Sinkronisasi'), findsOneWidget);
      expect(find.text('NOP Baru Terbit (1)'), findsOneWidget);
      expect(find.text('NOP Baru Lunas (1)'), findsOneWidget);
      expect(find.text('WARGA BARU'), findsOneWidget);

      // Switch to Baru Lunas tab
      await tester.tap(find.text('NOP Baru Lunas (1)'));
      await tester.pumpAndSettle();
      expect(find.text('WARGA LAMA'), findsOneWidget);

      // Test Search Filter
      await tester.enterText(find.byType(TextField), 'TIDAK_ADA');
      await tester.pumpAndSettle();
      expect(find.text('WARGA LAMA'), findsNothing);
    });
  });
}

