import 'base_preferences_store.dart';

/// Status "Mode Operator" — dipakai kepala desa/koordinator yang menerima
/// laporan dari semua dusun sekaligus, bukan cuma satu wilayah kerja.
///
/// Sengaja tidak ada login: aplikasi ini tidak punya server akun, jadi mode
/// ini hanya diaktifkan lewat 2 saklar tersembunyi di layar Lisensi Open
/// Source (lihat license_screen.dart). Statusnya murni lokal — tersimpan di
/// SharedPreferences perangkat ini saja, tidak pernah ikut ke berkas APK
/// yang dibagikan maupun ke pembaruan aplikasi, jadi membagikan/memperbarui
/// aplikasi ke perangkat lain tidak pernah ikut memberi akses operator.
class OperatorModeStore extends BasePreferencesStore {
  OperatorModeStore._();
  static final instance = OperatorModeStore._();

  static const _enabledKey = 'operator_mode_enabled';
  static const _justEnabledKey = 'operator_mode_just_enabled';

  bool? _enabled;

  Future<bool> isEnabled() async {
    if (_enabled != null) return _enabled!;
    _enabled = await getBool(_enabledKey, defaultValue: false);
    return _enabled!;
  }

  Future<void> enable() async {
    await setBool(_enabledKey, true);
    await setBool(_justEnabledKey, true);
    _enabled = true;
  }

  /// Baca sekali lalu langsung dihapus — dipakai supaya notif "Selamat
  /// Datang Operator" cuma muncul sekali, tepat setelah mode operator baru
  /// diaktifkan & aplikasi restart, tidak muncul lagi di pembukaan berikutnya.
  Future<bool> consumeJustEnabledFlag() async {
    final flag = await getBool(_justEnabledKey, defaultValue: false);
    if (flag) await remove(_justEnabledKey);
    return flag;
  }
}
