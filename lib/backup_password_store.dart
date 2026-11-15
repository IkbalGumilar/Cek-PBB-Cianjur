import 'dart:math';

import 'base_preferences_store.dart';

/// Penyimpanan kata sandi dan kunci pemulihan (Recovery Key) backup DHKP terenkripsi —
/// mewarisi [BaseSecureStore] untuk operasi baca-tulis aman ke Android Keystore /
/// libsecret / Windows DPAPI tanpa pernah menggunakan hardcoded shared secret.
class BackupPasswordStore extends BaseSecureStore {
  BackupPasswordStore._();
  static final instance = BackupPasswordStore._();

  static const _passwordKey = 'dhkp_backup_password';
  static const _recoveryKeyStorageKey = 'dhkp_backup_recovery_key';
  static const _recoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Membaca kata sandi kustom yang diatur oleh pengguna (jika ada).
  Future<String?> read() => readSecure(_passwordKey);

  Future<bool> hasPassword() async =>
      ((await read())?.trim().length ?? 0) >= 8;

  Future<void> save(String password) {
    final trimmed = password.trim();
    if (trimmed.length < 8) {
      throw const FormatException(
        'Kata sandi backup harus terdiri dari minimal 8 karakter.',
      );
    }
    return writeSecure(_passwordKey, trimmed);
  }

  Future<void> clear() => deleteSecure(_passwordKey);

  /// Membaca Kunci Pemulihan (Recovery Key) acak unik milik instalasi ini dari Secure Storage.
  Future<String?> readRecoveryKey() => readSecure(_recoveryKeyStorageKey);

  /// Menghasilkan Kunci Pemulihan (Recovery Key) kriptografis 160-bit (32 karakter Base32)
  /// berformat `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX` menggunakan CSPRNG.
  static String generateRandomRecoveryKey() {
    final rng = Random.secure();
    final groups = List<String>.generate(8, (_) {
      final chars = List<String>.generate(
        4,
        (_) => _recoveryAlphabet[rng.nextInt(_recoveryAlphabet.length)],
      );
      return chars.join();
    });
    return groups.join('-');
  }

  /// Mengambil Kunci Pemulihan instalasi saat ini, atau membuat dan menyimpannya
  /// secara aman ke [FlutterSecureStorage] jika belum ada.
  Future<String> ensureRecoveryKey() async {
    final existing = (await readRecoveryKey())?.trim();
    if (existing != null && existing.length >= 8) {
      return existing;
    }
    final generated = generateRandomRecoveryKey();
    await writeSecure(_recoveryKeyStorageKey, generated);
    return generated;
  }

  /// Mengambil rahasia aktif untuk mengenkripsi backup `.dkhp` baru:
  /// 1. Kata sandi kustom pengguna (jika sudah diatur, minimal 8 karakter).
  /// 2. Kunci Pemulihan (Recovery Key) kriptografis unik per instalasi di Secure Storage.
  Future<String> getOrCreateActiveSecret() async {
    final customPassword = (await read())?.trim();
    if (customPassword != null && customPassword.length >= 8) {
      return customPassword;
    }
    return ensureRecoveryKey();
  }

  /// Mengambil daftar kandidat rahasia yang tersimpan di perangkat ini untuk mencoba
  /// mendekripsi backup sebelum meminta input manual dari pengguna.
  /// Aman terhadap kegagalan Secure Storage (mengembalikan daftar kosong bila gagal).
  Future<List<String>> readCandidateSecrets() async {
    final candidates = <String>[];
    final customPassword = (await read())?.trim();
    if (customPassword != null && customPassword.length >= 8) {
      candidates.add(customPassword);
    }
    final recoveryKey = (await readRecoveryKey())?.trim();
    if (recoveryKey != null &&
        recoveryKey.length >= 8 &&
        !candidates.contains(recoveryKey)) {
      candidates.add(recoveryKey);
    }
    return candidates;
  }
}
