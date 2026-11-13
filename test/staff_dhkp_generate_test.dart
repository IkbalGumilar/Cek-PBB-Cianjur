import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dusun_data.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_generate_dialog.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_generate_service.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGenerateStaffPortalClient extends StaffPortalClient {
  final Map<int, MonitoringTableResult> belumBayarPages;
  final Map<int, MonitoringTableResult> sudahBayarPages;

  FakeGenerateStaffPortalClient({
    this.belumBayarPages = const {},
    this.sudahBayarPages = const {},
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
    if (belumBayarPages.containsKey(page)) {
      return belumBayarPages[page]!;
    }
    return const MonitoringTableResult(
      headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Alamat OP'],
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
    if (sudahBayarPages.containsKey(page)) {
      return sudahBayarPages[page]!;
    }
    return const MonitoringTableResult(
      headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar', 'Alamat OP'],
      rows: [],
      hasNextPage: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DusunData.instance.init();
  });

  group('StaffDhkpGenerateService.generateAndApply', () {
    test(
      'overwrites local database, applies 2Juta Pemda threshold, updates dusuns, and sets catatan tanggal jam',
      () async {
        // 1. Seed existing data that will be overwritten
        await BlokDataStore.instance.upsertAll([
          const BlokRecord(
            nop: '320520000400100010',
            namaWajibPajak: 'DATA LAMA DITIMPA',
            tahunBayar: '2025',
            tanggalBayar: '',
            jumlahPbb: '50000',
            statusBayar: 'Belum Bayar',
          ),
        ]);

        // 2. Mock portal data:
        // Belum Bayar:
        // - Blok 001 (50rb, 2026)
        // - Blok 001 (2.5jt -> Target Pemda, 2026)
        // Sudah Bayar:
        // - Blok 002 (100rb, 2026-03-01 14:20:00)
        final client = FakeGenerateStaffPortalClient(
          belumBayarPages: {
            1: const MonitoringTableResult(
              headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Alamat OP'],
              rows: [
                [
                  '1',
                  '320520000400100020',
                  'WARGA REGULER',
                  '50.000',
                  'KP. DUKUH',
                ],
                [
                  '2',
                  '320520000400100030',
                  'PT TARGET BESAR',
                  '2.500.000',
                  'JL. RAYA',
                ],
              ],
              hasNextPage: false,
            ),
          },
          sudahBayarPages: {
            1: const MonitoringTableResult(
              headers: [
                'No',
                'NOP',
                'Nama WP',
                'Pokok',
                'Tgl Bayar',
                'Alamat OP',
              ],
              rows: [
                [
                  '1',
                  '320520000400200010',
                  'WARGA SUDAH BAYAR',
                  '100.000',
                  '2026-03-01 14:20:00',
                  'KP. RAWA',
                ],
              ],
              hasNextPage: false,
            ),
          },
        );

        final dusuns = [
          const Dusun(
            number: 1,
            name: 'Dusun I Babakan',
            focusLat: -6.7810,
            focusLng: 107.1640,
            bloks: ['001', '002'],
          ),
        ];

        final outcome = await StaffDhkpGenerateService.instance
            .generateAndApply(
              client: client,
              tahunAwal: '2026',
              tahunAkhir: '2026',
              kelurahanCode: '3205200004',
              kecamatanCode: '3205200',
              desaName: 'BOBOJONG',
              kecamatanName: 'MANDE',
              dusuns: dusuns,
              filterByDusunBlocks: true,
              kantorDesaLat: -6.7820,
              kantorDesaLng: 107.1650,
              targetPemdaThreshold: 2000000,
              pacingDelay: Duration.zero,
            );

        expect(outcome.success, isTrue);
        expect(outcome.totalRecords, 3);
        expect(outcome.belumBayarCount, 1);
        expect(outcome.sudahBayarCount, 1);
        expect(outcome.targetPemdaCount, 1);

        // Verify database in store
        final loaded = await BlokDataStore.instance.loadAll();
        expect(loaded.length, 3);
        // Data lama harus terhapus/ditimpa
        expect(
          loaded.any((r) => r.namaWajibPajak == 'DATA LAMA DITIMPA'),
          isFalse,
        );

        final targetPemda = loaded.firstWhere(
          (r) => r.nop == '320520000400100030',
        );
        expect(targetPemda.isTargetPemda, isTrue);
        expect(targetPemda.isPaid, isFalse);

        final reguler = loaded.firstWhere((r) => r.nop == '320520000400100020');
        expect(reguler.isTargetPemda, isFalse);

        final lunas = loaded.firstWhere((r) => r.nop == '320520000400200010');
        expect(lunas.isPaid, isTrue);
        expect(lunas.tanggalBayar, '2026-03-01 14:20:00');
        expect(
          lunas.catatan,
          'Sudah bayar pada tanggal 1 bulan Maret 2026 jam 14:20:00',
        );

        // Verify DusunData updated
        expect(DusunData.instance.kantorDesaLat, closeTo(-6.7820, 0.0001));
        expect(DusunData.instance.kantorDesaLng, closeTo(107.1650, 0.0001));
        final allDusuns = DusunData.instance.allDusuns;
        expect(allDusuns.length, 1);
        expect(allDusuns.first.name, 'Dusun I Babakan');
        expect(allDusuns.first.bloks, ['001', '002']);
      },
    );

    test(
      'filters records to only Dusun 1 blocks when Dusun 1 is configured and filterByDusunBlocks is true',
      () async {
        final client = FakeGenerateStaffPortalClient(
          belumBayarPages: {
            1: const MonitoringTableResult(
              headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Alamat OP'],
              rows: [
                [
                  '1',
                  '320520000400100020',
                  'WARGA BLOK 1',
                  '50.000',
                  'KP. DUKUH',
                ],
                [
                  '2',
                  '320520000400200030',
                  'WARGA BLOK 2',
                  '75.000',
                  'KP. MEKAR',
                ],
                [
                  '3',
                  '320520000401500040',
                  'WARGA BLOK 15 (DUSUN LAIN)',
                  '100.000',
                  'KP. LAIN',
                ],
              ],
              hasNextPage: false,
            ),
          },
        );

        final dusun1Only = [
          const Dusun(
            number: 1,
            name: 'Dusun 1 Bobojong',
            bloks: ['001', '002'],
          ),
        ];

        final outcome = await StaffDhkpGenerateService.instance
            .generateAndApply(
              client: client,
              tahunAwal: '2026',
              tahunAkhir: '2026',
              kelurahanCode: '3205200004',
              kecamatanCode: '3205200',
              desaName: 'BOBOJONG',
              kecamatanName: 'MANDE',
              dusuns: dusun1Only,
              filterByDusunBlocks: true,
              pacingDelay: Duration.zero,
            );

        expect(outcome.success, isTrue);
        // Hanya 2 record dari blok 001 dan 002 yang diambil, blok 015 disaring keluar
        expect(outcome.totalRecords, 2);
        final loaded = await BlokDataStore.instance.loadAll();
        expect(loaded.length, 2);
        expect(loaded.any((r) => r.nop == '320520000401500040'), isFalse);
      },
    );

    test(
      'supports multi-year range (e.g. 2015 s/d 2026) and parses respective years',
      () async {
        final client = FakeGenerateStaffPortalClient(
          belumBayarPages: {
            1: const MonitoringTableResult(
              headers: ['No', 'NOP', 'Nama WP', 'Thn', 'Pokok', 'Alamat OP'],
              rows: [
                [
                  '1',
                  '320520000400100010',
                  'WARGA 2018',
                  '2018',
                  '35.000',
                  'KP. DUKUH',
                ],
                [
                  '2',
                  '320520000400100010',
                  'WARGA 2026',
                  '2026',
                  '50.000',
                  'KP. DUKUH',
                ],
              ],
              hasNextPage: false,
            ),
          },
        );

        final outcome = await StaffDhkpGenerateService.instance
            .generateAndApply(
              client: client,
              tahunAwal: '2015',
              tahunAkhir: '2026',
              kelurahanCode: '3205200004',
              kecamatanCode: '3205200',
              desaName: 'BOBOJONG',
              kecamatanName: 'MANDE',
              dusuns: [
                const Dusun(number: 1, name: 'Dusun 1', bloks: ['001']),
              ],
              filterByDusunBlocks: false,
              pacingDelay: Duration.zero,
            );

        expect(outcome.success, isTrue);
        expect(outcome.totalRecords, 2);
        final loaded = await BlokDataStore.instance.loadAll();
        expect(loaded.any((r) => r.tahunBayar == '2018'), isTrue);
        expect(loaded.any((r) => r.tahunBayar == '2026'), isTrue);
      },
    );
  });

  group('StaffDhkpGenerateDialog UI', () {
    testWidgets(
      'renders dialog with multi-year inputs, Kecamatan, Desa, Dusun, and filter option',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showStaffDhkpGenerateDialog(
                    ctx,
                    client: FakeGenerateStaffPortalClient(),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Generate DHKP Baru (Timpa)'), findsOneWidget);
        expect(find.text('Tahun Awal'), findsOneWidget);
        expect(find.text('Tahun Akhir'), findsOneWidget);
        expect(find.text('Kecamatan'), findsOneWidget);
        expect(find.textContaining('Buku 1, 2, 3'), findsOneWidget);
        expect(
          find.textContaining('Target Pemda (>= Rp 2.000.000)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Hanya ambil blok yang terdaftar'),
          findsOneWidget,
        );
        expect(find.text('Tambah Dusun'), findsOneWidget);
        expect(find.text('Mulai Generate & Timpa DHKP'), findsOneWidget);
      },
    );
  });
}
