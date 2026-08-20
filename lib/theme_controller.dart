import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system('Ikuti Sistem'),
  light('Terang'),
  dark('Gelap'),
  amoled('Hitam AMOLED');

  final String label;
  const AppThemeMode(this.label);
}

class ThemeController extends ValueNotifier<AppThemeMode> {
  static const _prefsKey = 'theme_mode';

  ThemeController() : super(AppThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    value = AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
