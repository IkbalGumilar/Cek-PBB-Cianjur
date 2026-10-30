import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kelas dasar abstrak (inheritance) untuk penyimpanan data terenkripsi berbasis
/// [FlutterSecureStorage].
///
/// Menyediakan operasi aman (try-catch tersanitasi) untuk baca, tulis, dan hapus
/// token / kredensial sensitif di Android Keystore / Linux libsecret / Windows DPAPI.
abstract class BaseSecureStore {
  FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @protected
  @visibleForTesting
  void setSecureStorageForTesting(FlutterSecureStorage storage) {
    _secureStorage = storage;
  }

  @protected
  Future<String?> readSecure(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @protected
  Future<void> writeSecure(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (_) {}
  }

  @protected
  Future<void> deleteSecure(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}
  }
}

/// Kelas dasar untuk penyimpanan preferensi lokal berbasis [SharedPreferences]
/// dan [FlutterSecureStorage].
///
/// Mewarisi [BaseSecureStore] agar kelas turunan memiliki akses terpusat ke operasi
/// preferensi umum maupun penyimpanan terenkripsi lewat pewarisan tanpa duplikasi kode.
abstract class BasePreferencesStore extends BaseSecureStore {
  SharedPreferences? _prefs;

  @protected
  Future<SharedPreferences> getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
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

  /// Membaca dari secure storage; jika belum ada atau gagal, fallback membaca
  /// dari [SharedPreferences].
  @protected
  Future<String?> readSecureWithFallback(String key) async {
    final val = await readSecure(key);
    if (val != null) return val;
    return getString(key);
  }

  /// Menulis ke secure storage dan menyinkronkan dengan [SharedPreferences].
  @protected
  Future<void> writeSecureWithFallback(String key, String value) async {
    await writeSecure(key, value);
    await setString(key, value);
  }

  /// Menghapus key dari kedua penyimpanan (secure storage & [SharedPreferences]).
  @protected
  Future<void> deleteSecureWithFallback(String key) async {
    await deleteSecure(key);
    await remove(key);
  }

  @protected
  @visibleForTesting
  void resetPrefsForTesting() {
    _prefs = null;
  }
}
