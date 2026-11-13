import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/kelola_anggota_screen.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeKolektifPortalClient extends StaffPortalClient {
  final Map<String, KolektifMemberListResult> groupResults;
  int fetchMembersCallCount = 0;

  _FakeKolektifPortalClient({required this.groupResults});

  @override
  Future<KolektifMemberListResult> fetchKolektifMembers({
    required String groupId,
    required String status,
    int length = 1000,
  }) async {
    fetchMembersCallCount++;
    return groupResults[groupId] ??
        const KolektifMemberListResult(members: <KolektifMember>[]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'feature_tour_completed_kelola_anggota_screen': true,
    });
    AppStorage.resetForTesting();
    BlokDataStore.instance.resetForTesting();
    await BlokDataStore.instance.clearAll();
    KelolaAnggotaScreen.resetSyncedGroupsForTesting();
  });

  testWidgets(
    'Membuka KelolaAnggotaScreen ke-1 kali memuat seluruh anggota dan otomatis mengubah status menjadi Sudah Bayar di DHKP, namun pembukaan ke-2 tidak menyinkronkan ulang',
    (tester) async {
      // Siapkan data awal di BlokDataStore (Belum Bayar)
      await BlokDataStore.instance.upsertAll(const [
        BlokRecord(
          nop: '320520000400100340',
          namaWajibPajak: 'ENOH',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: 'Rp 41.409',
          statusBayar: 'Belum Bayar',
          alamatObjek: 'KP. BOBOJONG',
          rtObjek: '001',
        ),
        BlokRecord(
          nop: '320520000400100600',
          namaWajibPajak: 'YUSUP SUFIANDI',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: 'Rp 37.954',
          statusBayar: 'Belum Bayar',
          alamatObjek: 'KP. BOBOJONG',
          rtObjek: '002',
        ),
      ]);

      final members = <KolektifMember>[
        const KolektifMember(
          nop: '320520000400100340',
          tahunPajak: '2026',
          jatuhTempo: '2026-09-30',
          namaWp: 'ENOH',
          kecamatan: 'MANDE',
          kelurahan: 'BOBOJONG',
          pokok: '41,409',
          denda: '828',
          total: '42,237',
        ),
        const KolektifMember(
          nop: '320520000400100600',
          tahunPajak: '2026',
          jatuhTempo: '2026-09-30',
          namaWp: 'YUSUP SUFIANDI',
          kecamatan: 'MANDE',
          kelurahan: 'BOBOJONG',
          pokok: '37,954',
          denda: '759',
          total: '38,713',
        ),
        const KolektifMember(
          nop: '320520000400300130',
          tahunPajak: '2024',
          jatuhTempo: '2024-09-30',
          namaWp: 'MIMIN MINTARSIH',
          kecamatan: 'MANDE',
          kelurahan: 'BOBOJONG',
          pokok: '21,852',
          denda: '5,244',
          total: '27,096',
        ),
      ];

      final client = _FakeKolektifPortalClient(
        groupResults: {
          'grp-kadus-1': KolektifMemberListResult(members: members),
        },
      );

      const group = KolektifGroup(
        id: 'grp-kadus-1',
        namaGroup: 'KADUS I NU KASEP',
        namaKolektor: 'KADUS I',
        hpKolektor: '08123456789',
        anggota: '3',
        kodeBayar: '32052026001',
        status: 'Final - Siap Dibayar',
        kecamatan: 'MANDE',
        kelurahan: 'BOBOJONG',
        kelurahanCode: '3205200004',
        keterangan: '',
        tanggalKadaluarsa: '2026-12-31',
        statusCode: '1',
        canDelete: false,
        canEdit: false,
        canPrintSurat: true,
      );

      // 1. Buka KelolaAnggotaScreen pertama kali
      await tester.pumpWidget(
        MaterialApp(
          home: KelolaAnggotaScreen(client: client, group: group),
        ),
      );
      await tester.pumpAndSettle();

      // Pastikan seluruh anggota (3) tampil di layar dan telah tersinkron ke BlokDataStore
      expect(find.text('Anggota (3)'), findsOneWidget);
      expect(find.text('320520000400100340'), findsOneWidget);
      expect(find.text('320520000400100600'), findsOneWidget);
      expect(find.text('320520000400300130'), findsOneWidget);

      final allAfterFirstOpen = await BlokDataStore.instance.loadAll();
      expect(allAfterFirstOpen.length, 3);

      final rec1 = allAfterFirstOpen.firstWhere(
        (r) => r.nop == '320520000400100340' && r.tahunBayar == '2026',
      );
      expect(rec1.isPaid, isTrue);
      expect(rec1.statusBayar, 'Sudah Bayar');
      expect(rec1.jumlahPbbValue, 41409);
      expect(rec1.alamatObjek, 'KP. BOBOJONG');
      expect(
        rec1.catatan.toLowerCase(),
        startsWith('sudah bayar pada tanggal'),
      );

      final rec3 = allAfterFirstOpen.firstWhere(
        (r) => r.nop == '320520000400300130' && r.tahunBayar == '2024',
      );
      expect(rec3.isPaid, isTrue);
      expect(rec3.namaWajibPajak, 'MIMIN MINTARSIH');
      expect(rec3.jumlahPbbValue, 21852);

      // 2. Simulasikan perubahan manual kembali ke Belum Bayar, lalu buka KelolaAnggotaScreen ke-2 kali
      await BlokDataStore.instance.upsert(
        rec1.copyWith(
          statusBayar: 'Belum Bayar',
          tanggalBayar: '',
          catatan: '',
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Buka halaman KelolaAnggotaScreen untuk ke-2 kalinya pada grup yang sama
      await tester.pumpWidget(
        MaterialApp(
          home: KelolaAnggotaScreen(client: client, group: group),
        ),
      );
      await tester.pumpAndSettle();

      // Karena sudah pernah disinkronkan 1x, pembukaan ke-2 TIDAK boleh mengubah rec1 kembali ke Sudah Bayar
      final allAfterSecondOpen = await BlokDataStore.instance.loadAll();
      final rec1Second = allAfterSecondOpen.firstWhere(
        (r) => r.nop == '320520000400100340' && r.tahunBayar == '2026',
      );
      expect(rec1Second.isPaid, isFalse);
      expect(rec1Second.statusBayar, 'Belum Bayar');
    },
  );
}
