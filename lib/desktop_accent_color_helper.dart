import 'dart:io';
import 'package:flutter/material.dart';

class DesktopAccentColorHelper {
  DesktopAccentColorHelper._();

  static Color? _cachedColor;
  static bool _hasQueried = false;

  static const Map<String, Color> _gnomeColors = {
    'blue': Color(0xFF3584E4),
    'teal': Color(0xFF26A269),
    'green': Color(0xFF33D17A),
    'yellow': Color(0xFFE5A50A),
    'orange': Color(0xFFE95420),
    'red': Color(0xFFD62F4D),
    'purple': Color(0xFF9141AC),
    'pink': Color(0xFFD56199),
    'slate': Color(0xFF5E5C64),
  };

  /// Mendeteksi warna aksen sistem desktop (Windows & Linux).
  static Future<Color?> getDesktopAccentColor() async {
    if (_hasQueried) return _cachedColor;
    _hasQueried = true;

    if (Platform.isLinux) {
      _cachedColor = await _getLinuxAccentColor();
    } else if (Platform.isWindows) {
      _cachedColor = await _getWindowsAccentColor();
    }

    return _cachedColor;
  }

  static Future<Color?> _getLinuxAccentColor() async {
    // 1. Coba baca nama accent-color dari GNOME desktop interface
    try {
      final gsettingsResult = await Process.run('gsettings', [
        'get',
        'org.gnome.desktop.interface',
        'accent-color',
      ]);
      if (gsettingsResult.exitCode == 0) {
        final raw = gsettingsResult.stdout.toString().trim().replaceAll(
          "'",
          "",
        );
        if (_gnomeColors.containsKey(raw)) {
          return _gnomeColors[raw];
        }
      }
    } catch (_) {}

    // 2. Coba baca dari GTK3 theme_selected_bg_color via python3
    try {
      final pyResult = await Process.run('python3', [
        '-c',
        "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk; w=Gtk.Window(); f,c=w.get_style_context().lookup_color('theme_selected_bg_color'); print(f'{int(c.red*255)},{int(c.green*255)},{int(c.blue*255)}' if f else '')",
      ]);
      if (pyResult.exitCode == 0) {
        final text = pyResult.stdout.toString().trim();
        final parts = text.split(',');
        if (parts.length == 3) {
          final r = int.tryParse(parts[0]);
          final g = int.tryParse(parts[1]);
          final b = int.tryParse(parts[2]);
          if (r != null && g != null && b != null) {
            return Color.fromARGB(255, r, g, b);
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<Color?> _getWindowsAccentColor() async {
    try {
      // 1. Coba baca AccentColorMenu dari Windows 10/11 Registry
      final res = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
        '/v',
        'AccentColorMenu',
      ]);
      if (res.exitCode == 0) {
        final color = _parseRegDword(res.stdout.toString(), isAbgr: true);
        if (color != null) return color;
      }
    } catch (_) {}

    try {
      // 2. Fallback baca DWM ColorizationColor (Windows 7/8/10/11)
      final resDwm = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\DWM',
        '/v',
        'ColorizationColor',
      ]);
      if (resDwm.exitCode == 0) {
        final color = _parseRegDword(resDwm.stdout.toString(), isAbgr: false);
        if (color != null) return color;
      }
    } catch (_) {}

    return null;
  }

  static Color? _parseRegDword(String output, {required bool isAbgr}) {
    final match = RegExp(r'0x([0-9a-fA-F]+)').firstMatch(output);
    if (match != null) {
      final hex = match.group(1)!;
      final val = int.tryParse(hex, radix: 16);
      if (val != null) {
        if (isAbgr) {
          final a = (val >> 24) & 0xFF;
          final b = (val >> 16) & 0xFF;
          final g = (val >> 8) & 0xFF;
          final r = val & 0xFF;
          return Color.fromARGB(a == 0 ? 255 : a, r, g, b);
        } else {
          return Color(val | 0xFF000000);
        }
      }
    }
    return null;
  }
}
