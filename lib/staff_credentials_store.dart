import 'base_preferences_store.dart';

/// Simpan username & password Portal Staf secara terenkripsi — mewarisi
/// [BaseSecureStore] untuk operasi penyimpanan aman ke Android Keystore / libsecret.
class StaffCredentialsStore extends BaseSecureStore {
  StaffCredentialsStore._();
  static final instance = StaffCredentialsStore._();

  static const _usernameKey = 'staff_portal_username';
  static const _passwordKey = 'staff_portal_password';

  Future<void> save({
    required String username,
    required String password,
  }) async {
    await writeSecure(_usernameKey, username);
    await writeSecure(_passwordKey, password);
  }

  Future<({String username, String password})?> read() async {
    final username = await readSecure(_usernameKey);
    final password = await readSecure(_passwordKey);
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  Future<void> clear() async {
    await deleteSecure(_usernameKey);
    await deleteSecure(_passwordKey);
  }
}
