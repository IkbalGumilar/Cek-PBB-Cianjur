import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system('Ikuti Sistem'),
  light('Terang'),
  dark('Gelap'),
  amoled('Hitam AMOLED');

  final String label;
  const AppThemeMode(this.label);
}

class AppThemeState {
  final AppThemeMode mode;
  final Color accentColor;
  final bool useMaterialYou;

  const AppThemeState({
    this.mode = AppThemeMode.system,
    this.accentColor = const Color(0xFF2E7D32),
    this.useMaterialYou = false,
  });

  AppThemeState copyWith({
    AppThemeMode? mode,
    Color? accentColor,
    bool? useMaterialYou,
  }) {
    return AppThemeState(
      mode: mode ?? this.mode,
      accentColor: accentColor ?? this.accentColor,
      useMaterialYou: useMaterialYou ?? this.useMaterialYou,
    );
  }
}

class ThemeController extends ValueNotifier<AppThemeState> {
  static const _prefsKeyMode = 'theme_mode';
  static const _prefsKeyAccentColor = 'theme_accent_color';
  static const _prefsKeyMaterialYou = 'theme_material_you';

  static const Color defaultAccentColor = Color(0xFF2E7D32);

  bool _disposed = false;

  ThemeController() : super(const AppThemeState()) {
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  AppThemeMode get mode => value.mode;
  Color get accentColor => value.accentColor;
  bool get useMaterialYou => value.useMaterialYou;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final savedMode = prefs.getString(_prefsKeyMode);
    final savedColorInt = prefs.getInt(_prefsKeyAccentColor);
    final savedMaterialYou = prefs.getBool(_prefsKeyMaterialYou);

    final mode = savedMode != null
        ? AppThemeMode.values.firstWhere(
            (m) => m.name == savedMode,
            orElse: () => AppThemeMode.system,
          )
        : AppThemeMode.system;

    final accentColor = savedColorInt != null
        ? Color(savedColorInt)
        : defaultAccentColor;

    final useMaterialYou = savedMaterialYou ?? false;

    value = AppThemeState(
      mode: mode,
      accentColor: accentColor,
      useMaterialYou: useMaterialYou,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    value = value.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyMode, mode.name);
  }

  /// Memperbarui warna aksen di memori & UI langsung.
  /// Bila [saveToPrefs] bernilai true, simpan permanen ke SharedPreferences.
  Future<void> setAccentColor(Color color, {bool saveToPrefs = true}) async {
    value = value.copyWith(accentColor: color);
    if (saveToPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyAccentColor, color.toARGB32());
    }
  }

  Future<void> setUseMaterialYou(bool enabled) async {
    value = value.copyWith(useMaterialYou: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyMaterialYou, enabled);
  }

  Future<void> resetToDefault() async {
    value = value.copyWith(
      accentColor: defaultAccentColor,
      useMaterialYou: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyAccentColor, defaultAccentColor.toARGB32());
    await prefs.setBool(_prefsKeyMaterialYou, false);
  }
}
