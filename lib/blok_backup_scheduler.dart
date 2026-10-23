import 'base_preferences_store.dart';

/// Backup harian otomatis: dijalankan sekali tiap aplikasi dibuka. Hanya
/// benar-benar menulis backup kalau (a) belum pernah backup hari ini DAN
/// (b) ada data baru/berubah sejak backup terakhir (ditandai lewat
/// [markDirty], dipanggil dari BlokDataStore.upsert setiap ada catatan baru
/// atau berubah). Kalau tidak ada data baru, dilewati begitu saja.
///
/// Tidak pakai [exportCsv] dari BlokDataStore langsung sebagai import supaya
/// tidak terjadi import melingkar (BlokDataStore juga perlu memanggil
/// [markDirty] balik) — fungsi ekspornya dioper sebagai parameter dari
/// pemanggil (lihat main.dart).
class BlokBackupScheduler extends BasePreferencesStore {
  BlokBackupScheduler._();
  static final instance = BlokBackupScheduler._();

  static const _lastBackupDateKey = 'blok_last_backup_date';
  static const _dirtyKey = 'blok_data_dirty';

  Future<void> markDirty() async {
    await setBool(_dirtyKey, true);
  }

  String _dateKey(DateTime date) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${pad2(date.month)}-${pad2(date.day)}';
  }

  Future<void> runIfNeeded({
    required Future<String> Function(String fileName) exportCsv,
  }) async {
    final today = _dateKey(DateTime.now());

    if (await getString(_lastBackupDateKey) == today) return;

    final isDirty = await getBool(_dirtyKey, defaultValue: false);
    if (!isDirty) {
      await setString(_lastBackupDateKey, today);
      return;
    }

    try {
      await exportCsv('backup_harian_$today');
      await setString(_lastBackupDateKey, today);
      await setBool(_dirtyKey, false);
    } catch (_) {
      // Gagal (mis. penyimpanan belum siap saat startup) — coba lagi di
      // kesempatan buka aplikasi berikutnya, jangan tandai tanggal ini
      // sudah backup.
    }
  }
}
