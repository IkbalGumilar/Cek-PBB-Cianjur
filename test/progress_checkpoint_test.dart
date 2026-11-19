import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/batch_check_manager.dart';
import 'package:cek_pbb_app/progress_checkpoint_store.dart';
import 'package:cek_pbb_app/tax_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ProgressCheckpointStore.instance.resetForTesting();
    BatchCheckManager.instance.reset();
  });

  tearDown(() async {
    BatchCheckManager.instance.reset();
    await ProgressCheckpointStore.instance.resetForTesting();
  });

  group('ProgressCheckpointStore (24-hour rule)', () {
    test('loads batch checkpoint when paused < 24 hours and expires at >= 24 hours', () async {
      final t0 = DateTime.utc(2026, 11, 19, 10, 0, 0);
      final scopeKey = ProgressCheckpointStore.buildBatchScopeKey(
        tahun: '2026',
        scopeTitle: 'Blok 001',
        blokNumber: '001',
        totalCount: 50,
        firstNop: '320301000100100010',
        lastNop: '320301000100100500',
      );

      await ProgressCheckpointStore.instance.saveBatchCheckpoint(
        BatchCheckCheckpoint(
          scopeKey: scopeKey,
          currentIndex: 17,
          totalCount: 50,
          savedAtMs: t0.millisecondsSinceEpoch,
        ),
      );

      // 23 jam 59 menit kemudian -> masih valid, lanjutkan dari 17
      final validCp = await ProgressCheckpointStore.instance
          .loadValidBatchCheckpoint(
            scopeKey,
            now: t0.add(const Duration(hours: 23, minutes: 59)),
          );
      expect(validCp, isNotNull);
      expect(validCp!.currentIndex, 17);

      // 24 jam kemudian -> kedaluwarsa, otomatis dihapus & mulai dari awal
      final expiredCp = await ProgressCheckpointStore.instance
          .loadValidBatchCheckpoint(
            scopeKey,
            now: t0.add(const Duration(hours: 24)),
          );
      expect(expiredCp, isNull);
    });

    test('loads staff sync checkpoint when paused < 24 hours and expires at >= 24 hours', () async {
      final t0 = DateTime.utc(2026, 11, 19, 10, 0, 0);
      final scopeKey = ProgressCheckpointStore.buildStaffSyncScopeKey(
        tahun: '2026',
        kecamatan: '010',
        kelurahan: '005',
        modeName: 'full',
        bloks: const ['002', '001'],
      );

      await ProgressCheckpointStore.instance.saveStaffSyncCheckpoint(
        StaffSyncCheckpoint(
          scopeKey: scopeKey,
          nextPageBb: 4,
          nextPageSb: 2,
          bbCompleted: true,
          savedAtMs: t0.millisecondsSinceEpoch,
        ),
      );

      final valid = await ProgressCheckpointStore.instance
          .loadValidStaffSyncCheckpoint(
            scopeKey,
            now: t0.add(const Duration(hours: 12)),
          );
      expect(valid, isNotNull);
      expect(valid!.nextPageBb, 4);
      expect(valid.nextPageSb, 2);
      expect(valid.bbCompleted, isTrue);

      final expired = await ProgressCheckpointStore.instance
          .loadValidStaffSyncCheckpoint(
            scopeKey,
            now: t0.add(const Duration(hours: 24, minutes: 1)),
          );
      expect(expired, isNull);
    });

    test('BatchCheckManager restores < 24h saved index on startBatch and resets to 0 if paused >= 24h on resume', () async {
      final records = List<TaxRecord>.generate(
        5,
        (i) => TaxRecord(
          nop: '3203010001001000${i}0',
          namaWajibPajak: 'WP $i',
        ),
      );
      final scopeKey = ProgressCheckpointStore.buildBatchScopeKey(
        tahun: '2026',
        scopeTitle: 'Blok 001',
        blokNumber: '001',
        totalCount: records.length,
        firstNop: records.first.nop,
        lastNop: records.last.nop,
      );

      // Simpan checkpoint 2 jam lalu di indeks 3
      final twoHoursAgo = DateTime.now().toUtc().subtract(
        const Duration(hours: 2),
      );
      await ProgressCheckpointStore.instance.saveBatchCheckpoint(
        BatchCheckCheckpoint(
          scopeKey: scopeKey,
          currentIndex: 3,
          totalCount: records.length,
          savedAtMs: twoHoursAgo.millisecondsSinceEpoch,
        ),
      );

      await BatchCheckManager.instance.startBatch(
        records: records,
        tahun: '2026',
        scopeTitle: 'Blok 001',
        sttsBlokNumber: '001',
        autoStart: false,
      );
      expect(BatchCheckManager.instance.currentIndex, 3);

      // Simulasikan pause sekarang lalu resume 25 jam kemudian -> reset ke indeks 0
      final pauseTime = DateTime.utc(2026, 11, 19, 8, 0);
      BatchCheckManager.instance.markPausedForTesting(pauseTime);
      BatchCheckManager.instance.resume(
        now: pauseTime.add(const Duration(hours: 25)),
        autoStartLoop: false,
      );
      expect(BatchCheckManager.instance.currentIndex, 0);
    });
  });
}
