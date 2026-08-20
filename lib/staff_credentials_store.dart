import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simpan username & password Portal Staf secara terenkripsi (Android
/// Keystore / libsecret di Linux — lewat `flutter_secure_storage`, BUKAN
/// SharedPreferences biasa) supaya form login bisa terisi otomatis mulai
/// login yang kedua dan seterusnya. Login pertama tetap harus diketik manual
/// (memang belum ada yang tersimpan) — begitu berhasil, langsung disimpan
/// untuk login berikutnya.
class StaffCredentialsStore {
  StaffCredentialsStore._();
  static final instance = StaffCredentialsStore._();

  static const _usernameKey = 'staff_portal_username';
  static const _passwordKey = 'staff_portal_password';

  final _storage = const FlutterSecureStorage();

  Future<void> save({required String username, required String password}) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<({String username, String password})?> read() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
