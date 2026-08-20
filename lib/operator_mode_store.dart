import 'package:shared_preferences/shared_preferences.dart';

/// Status "Mode Operator" — dipakai kepala desa/koordinator yang menerima
/// laporan dari semua dusun sekaligus, bukan cuma satu wilayah kerja.
///
/// Sengaja tidak ada login: aplikasi ini tidak punya server akun, jadi mode
/// ini hanya diaktifkan lewat 2 saklar tersembunyi di layar Lisensi Open
/// Source (lihat license_screen.dart). Statusnya murni lokal — tersimpan di
/// SharedPreferences perangkat ini saja, tidak pernah ikut ke berkas APK
/// yang dibagikan maupun ke pembaruan aplikasi, jadi membagikan/memperbarui
/// aplikasi ke perangkat lain tidak pernah ikut memberi akses operator.
class OperatorModeStore {
  OperatorModeStore._();
  static final instance = OperatorModeStore._();

  static const _enabledKey = 'operator_mode_enabled';
  static const _justEnabledKey = 'operator_mode_just_enabled';

  bool? _enabled;

  Future<bool> isEnabled() async {
    if (_enabled != null) return _enabled!;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    return _enabled!;
  }

  Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    await prefs.setBool(_justEnabledKey, true);
    _enabled = true;
  }

  /// Baca sekali lalu langsung dihapus — dipakai supaya notif "Selamat
  /// Datang Operator" cuma muncul sekali, tepat setelah mode operator baru
  /// diaktifkan & aplikasi restart, tidak muncul lagi di pembukaan berikutnya.
  Future<bool> consumeJustEnabledFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool(_justEnabledKey) ?? false;
    if (flag) await prefs.remove(_justEnabledKey);
    return flag;
  }
}
