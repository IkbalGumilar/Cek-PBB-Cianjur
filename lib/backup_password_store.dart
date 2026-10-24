import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackupPasswordStore {
  BackupPasswordStore._();
  static final instance = BackupPasswordStore._();

  static const _passwordKey = 'dhkp_backup_password';
  final _storage = const FlutterSecureStorage();

  Future<String?> read() async {
    try {
      return await _storage.read(key: _passwordKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPassword() async => (await read())?.isNotEmpty ?? false;

  Future<void> save(String password) async {
    try {
      await _storage.write(key: _passwordKey, value: password);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _passwordKey);
    } catch (_) {}
  }
}
