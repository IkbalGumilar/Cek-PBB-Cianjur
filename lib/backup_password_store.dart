import 'base_preferences_store.dart';

/// Penyimpanan kata sandi backup DHKP terenkripsi — mewarisi [BaseSecureStore]
/// untuk operasi baca-tulis aman ke Android Keystore / libsecret / Windows DPAPI.
class BackupPasswordStore extends BaseSecureStore {
  BackupPasswordStore._();
  static final instance = BackupPasswordStore._();

  static const _passwordKey = 'dhkp_backup_password';

  Future<String?> read() => readSecure(_passwordKey);

  Future<bool> hasPassword() async => (await read())?.isNotEmpty ?? false;

  Future<void> save(String password) => writeSecure(_passwordKey, password);

  Future<void> clear() => deleteSecure(_passwordKey);
}
