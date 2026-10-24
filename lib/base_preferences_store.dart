import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kelas dasar untuk penyimpanan preferensi lokal berbasis [SharedPreferences].
///
/// Menyediakan instance [SharedPreferences] ter-cache serta helper tersanitasi
/// untuk operasi baca-tulis boolean, int, string, dan penghapusan key.
abstract class BasePreferencesStore {
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

  @protected
  @visibleForTesting
  void resetPrefsForTesting() {
    _prefs = null;
  }
}
