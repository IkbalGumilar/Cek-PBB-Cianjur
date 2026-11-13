import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eksepsi khusus ketika operasi pada penyimpanan aman ([FlutterSecureStorage]) gagal.
class SecureStorageException implements Exception {
  final String message;
  final Object? cause;

  const SecureStorageException(this.message, {this.cause});

  @override
  String toString() => 'SecureStorageException: $message';
}

/// Kelas dasar abstrak (inheritance) untuk penyimpanan data terenkripsi berbasis
/// [FlutterSecureStorage].
///
/// Menyediakan operasi aman untuk baca, tulis, dan hapus token / kredensial
/// sensitif di Android Keystore / Linux libsecret / Windows DPAPI tanpa pernah
/// menyalin rahasia ke penyimpanan plaintext.
abstract class BaseSecureStore {
  FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static final Map<String, String> _testMemoryStore = <String, String>{};

  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Membersihkan penyimpanan memori sementara saat pengujian unit/widget.
  @visibleForTesting
  static void clearTestMemoryStore() {
    _testMemoryStore.clear();
  }

  @protected
  @visibleForTesting
  void setSecureStorageForTesting(FlutterSecureStorage storage) {
    _secureStorage = storage;
  }

  @protected
  Future<String?> readSecure(String key, {bool throwOnError = false}) async {
    try {
      return await _secureStorage.read(key: key);
    } on MissingPluginException catch (e) {
      if (_isFlutterTest) {
        return _testMemoryStore[key];
      }
      if (throwOnError) {
        throw SecureStorageException(
          'Plugin penyimpanan aman tidak tersedia saat membaca "$key".',
          cause: e,
        );
      }
      debugPrint('BaseSecureStore: Gagal membaca key "$key": $e');
      return null;
    } catch (e) {
      if (_isFlutterTest) {
        return _testMemoryStore[key];
      }
      if (throwOnError) {
        throw SecureStorageException(
          'Gagal membaca data keamanan untuk "$key".',
          cause: e,
        );
      }
      debugPrint('BaseSecureStore: Gagal membaca key "$key": $e');
      return null;
    }
  }

  @protected
  Future<void> writeSecure(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } on MissingPluginException catch (e) {
      if (_isFlutterTest) {
        _testMemoryStore[key] = value;
        return;
      }
      throw SecureStorageException(
        'Plugin penyimpanan aman tidak tersedia saat menyimpan "$key".',
        cause: e,
      );
    } catch (e) {
      if (_isFlutterTest) {
        _testMemoryStore[key] = value;
        return;
      }
      throw SecureStorageException(
        'Gagal menyimpan data keamanan untuk "$key".',
        cause: e,
      );
    }
  }

  @protected
  Future<void> deleteSecure(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException catch (e) {
      if (_isFlutterTest) {
        _testMemoryStore.remove(key);
        return;
      }
      throw SecureStorageException(
        'Plugin penyimpanan aman tidak tersedia saat menghapus "$key".',
        cause: e,
      );
    } catch (e) {
      if (_isFlutterTest) {
        _testMemoryStore.remove(key);
        return;
      }
      throw SecureStorageException(
        'Gagal menghapus data keamanan untuk "$key".',
        cause: e,
      );
    }
  }
}

/// Kelas dasar untuk penyimpanan preferensi lokal berbasis [SharedPreferences]
/// dan [FlutterSecureStorage].
///
/// Mewarisi [BaseSecureStore] agar kelas turunan memiliki akses terpusat ke operasi
/// preferensi umum maupun penyimpanan terenkripsi beserta migrasi satu arah dari
/// data lama di [SharedPreferences] ke [FlutterSecureStorage].
abstract class BasePreferencesStore extends BaseSecureStore {
  @protected
  Future<SharedPreferences> getPrefs() {
    return SharedPreferences.getInstance();
  }

  @protected
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await getPrefs();
    return prefs.getBool(key) ?? defaultValue;
  }

  @protected
  Future<void> setBool(String key, bool value) async {
    final prefs = await getPrefs();
    await prefs.setBool(key, value);
  }

  @protected
  Future<int?> getInt(String key) async {
    final prefs = await getPrefs();
    return prefs.getInt(key);
  }

  @protected
  Future<void> setInt(String key, int? value) async {
    final prefs = await getPrefs();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, value);
    }
  }

  @protected
  Future<String?> getString(String key) async {
    final prefs = await getPrefs();
    return prefs.getString(key);
  }

  @protected
  Future<void> setString(String key, String? value) async {
    final prefs = await getPrefs();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  @protected
  Future<void> remove(String key) async {
    final prefs = await getPrefs();
    await prefs.remove(key);
  }

  /// Membaca nilai sensitif dari [FlutterSecureStorage].
  ///
  /// Jika nilai sudah ada di secure storage namun salinan lama masih tertinggal
  /// di [SharedPreferences], salinan plaintext tersebut langsung dihapus.
  /// Jika belum ada di secure storage tetapi ditemukan data lama di [SharedPreferences],
  /// nilai tersebut dimigrasikan ke secure storage, diverifikasi hasil bacanya,
  /// lalu dihapus dari [SharedPreferences] hanya setelah migrasi terbukti berhasil.
  @protected
  Future<String?> readSecureWithMigration(String key) async {
    final prefs = await getPrefs();
    final secureVal = await readSecure(key);
    if (secureVal != null) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
      return secureVal;
    }

    if (!prefs.containsKey(key)) {
      return null;
    }

    final rawLegacy = prefs.get(key);
    final legacyVal = rawLegacy?.toString();
    if (legacyVal == null) {
      return null;
    }

    try {
      await writeSecure(key, legacyVal);
      final verified = await readSecure(key, throwOnError: true);
      if (verified == legacyVal) {
        await prefs.remove(key);
        return verified;
      }
    } catch (e) {
      debugPrint(
        'BasePreferencesStore: Migrasi key "$key" ke secure storage belum berhasil: $e',
      );
    }

    // Jangan hapus data lama jika migrasi ke secure storage belum berhasil
    return legacyVal;
  }

  /// Menulis data rahasia HANYA ke [FlutterSecureStorage] (tanpa menyalin ke
  /// [SharedPreferences]), memverifikasi hasil penulisan, dan menghapus sisa data
  /// plaintext lama di [SharedPreferences] apabila ada.
  @protected
  Future<void> writeSecureOnly(String key, String value) async {
    await writeSecure(key, value);
    final verified = await readSecure(key, throwOnError: true);
    if (verified != value) {
      throw SecureStorageException(
        'Verifikasi penulisan ke penyimpanan aman gagal untuk "$key".',
      );
    }
    final prefs = await getPrefs();
    if (prefs.containsKey(key)) {
      await prefs.remove(key);
    }
  }

  /// Menghapus data rahasia dari [FlutterSecureStorage] sekaligus membersihkan
  /// sisa key lama di [SharedPreferences] apabila ada.
  @protected
  Future<void> deleteSecureOnly(String key) async {
    await deleteSecure(key);
    final prefs = await getPrefs();
    if (prefs.containsKey(key)) {
      await prefs.remove(key);
    }
  }

  @protected
  @visibleForTesting
  void resetPrefsForTesting() {}
}
