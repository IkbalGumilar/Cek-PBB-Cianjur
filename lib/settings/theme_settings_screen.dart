import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../desktop_accent_color_helper.dart';
import '../theme_controller.dart';
import '../unity_lerp_widgets.dart';

/// Halaman terpisah untuk pengaturan Tema & Tampilan.
class ThemeSettingsScreen extends StatelessWidget {
  final ThemeController themeController;
  final bool? isMaterialYouSupported;

  const ThemeSettingsScreen({
    super.key,
    required this.themeController,
    this.isMaterialYouSupported,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tema & Tampilan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ThemeSettingsSection(
              controller: themeController,
              isMaterialYouSupported: isMaterialYouSupported,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget terpisah untuk pengaturan Tema & Tampilan.
class ThemeSettingsSection extends StatefulWidget {
  final ThemeController controller;
  final bool? isMaterialYouSupported;

  const ThemeSettingsSection({
    super.key,
    required this.controller,
    this.isMaterialYouSupported,
  });

  static String modeLabel(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => 'Ikuti Sistem',
    AppThemeMode.light => 'Terang',
    AppThemeMode.dark => 'Gelap',
    AppThemeMode.amoled => 'Hitam Pekat',
  };

  static IconData modeIcon(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => Icons.brightness_auto_outlined,
    AppThemeMode.light => Icons.light_mode_outlined,
    AppThemeMode.dark => Icons.dark_mode_outlined,
    AppThemeMode.amoled => Icons.contrast_outlined,
  };

  @override
  State<ThemeSettingsSection> createState() => _ThemeSettingsSectionState();
}

class _ThemeSettingsSectionState extends State<ThemeSettingsSection>
    with SingleTickerProviderStateMixin {
  late double _r;
  late double _g;
  late double _b;

  late final AnimationController _lerpController;
  double _startR = 0;
  double _startG = 0;
  double _startB = 0;
  double _targetR = 0;
  double _targetG = 0;
  double _targetB = 0;

  bool _materialYouSupported = false;

  static const List<({String name, Color color})> _presets = [
    (name: 'Hijau PBB', color: Color(0xFF2E7D32)),
    (name: 'Biru', color: Color(0xFF1565C0)),
    (name: 'Toska', color: Color(0xFF00695C)),
    (name: 'Ungu', color: Color(0xFF4527A0)),
    (name: 'Merah', color: Color(0xFFC62828)),
    (name: 'Oranye', color: Color(0xFFEF6C00)),
    (name: 'Merah Muda', color: Color(0xFFAD1457)),
    (name: 'Emas', color: Color(0xFF8D6E00)),
  ];

  @override
  void initState() {
    super.initState();
    _syncRgbFromColor(widget.controller.accentColor);

    _lerpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addListener(_onLerpTick);

    widget.controller.addListener(_onControllerChanged);
    _checkMaterialYouSupport();
  }

  void _onLerpTick() {
    final t = Curves.easeOutCubic.transform(_lerpController.value);
    setState(() {
      _r = _lerpDouble(_startR, _targetR, t);
      _g = _lerpDouble(_startG, _targetG, t);
      _b = _lerpDouble(_startB, _targetB, t);
    });
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  void _animateToColor(Color target) {
    _startR = _r;
    _startG = _g;
    _startB = _b;
    _targetR = (target.r * 255.0).roundToDouble();
    _targetG = (target.g * 255.0).roundToDouble();
    _targetB = (target.b * 255.0).roundToDouble();
    _lerpController.forward(from: 0.0);
    widget.controller.setAccentColor(target);
  }

  Future<void> _checkMaterialYouSupport() async {
    if (widget.isMaterialYouSupported != null) {
      if (mounted) {
        setState(() => _materialYouSupported = widget.isMaterialYouSupported!);
      }
      return;
    }

    bool supported = false;
    try {
      if (Platform.isLinux || Platform.isWindows) {
        final desktopColor =
            await DesktopAccentColorHelper.getDesktopAccentColor();
        supported = desktopColor != null;
      } else {
        final palette = await DynamicColorPlugin.getCorePalette();
        supported = palette != null;
      }
    } catch (_) {
      supported = false;
    }

    if (mounted) {
      setState(() => _materialYouSupported = supported);
    }
  }

  @override
  void didUpdateWidget(covariant ThemeSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _syncRgbFromColor(widget.controller.accentColor);
    }
    if (oldWidget.isMaterialYouSupported != widget.isMaterialYouSupported) {
      _checkMaterialYouSupport();
    }
  }

  @override
  void dispose() {
    _lerpController.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      if (!_lerpController.isAnimating) {
        _syncRgbFromColor(widget.controller.accentColor);
      }
    });
  }

  void _syncRgbFromColor(Color c) {
    _r = (c.r * 255.0).roundToDouble();
    _g = (c.g * 255.0).roundToDouble();
    _b = (c.b * 255.0).roundToDouble();
  }

  Color get _currentRgbColor =>
      Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  void _applyRgb() {
    if (_lerpController.isAnimating) {
      _lerpController.stop();
    }
    widget.controller.setAccentColor(_currentRgbColor);
  }

  String _hexString(Color c) {
    final r = (c.r * 255.0).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255.0).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255.0).round().toRadixString(16).padLeft(2, '0');
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  static String modeLabel(AppThemeMode mode) =>
      ThemeSettingsSection.modeLabel(mode);

  static IconData modeIcon(AppThemeMode mode) =>
      ThemeSettingsSection.modeIcon(mode);

  @override
  Widget build(BuildContext context) {
    final currentMode = widget.controller.mode;
    final useMaterialYou =
        _materialYouSupported && widget.controller.useMaterialYou;
    final currentColor = _currentRgbColor;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Mode Tema',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pilih tampilan layar yang paling nyaman dilihat.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<AppThemeMode>(
                  key: ValueKey(currentMode),
                  initialValue: currentMode,
                  decoration: InputDecoration(
                    labelText: 'Tampilan Layar',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: AppThemeMode.values.map((mode) {
                    return DropdownMenuItem<AppThemeMode>(
                      value: mode,
                      child: Row(
                        children: [
                          Icon(modeIcon(mode), size: 20),
                          const SizedBox(width: 10),
                          Text(modeLabel(mode)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (mode) {
                    if (mode != null) {
                      widget.controller.setMode(mode);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Warna Aplikasi',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!useMaterialYou)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: currentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: currentColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: currentColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _hexString(currentColor),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (_materialYouSupported) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Ikuti Warna Wallpaper'),
                    subtitle: const Text(
                      'Sesuaikan warna aplikasi otomatis dengan gambar latar HP',
                    ),
                    value: useMaterialYou,
                    onChanged: (val) {
                      widget.controller.setUseMaterialYou(val);
                    },
                  ),
                ],
                if (!useMaterialYou) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Pilihan Warna Cepat',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _presets.map((preset) {
                      final isSelected =
                          preset.color.toARGB32() == currentColor.toARGB32();
                      return Tooltip(
                        message: preset.name,
                        child: LerpPressable(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _animateToColor(preset.color);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: preset.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? scheme.onSurface
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: preset.color.withValues(
                                    alpha: isSelected ? 0.55 : 0.25,
                                  ),
                                  blurRadius: isSelected ? 8 : 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Atur Warna Sendiri',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _animateToColor(ThemeController.defaultAccentColor);
                          widget.controller.setUseMaterialYou(false);
                        },
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                  _RgbSliderRow(
                    label: 'Merah',
                    value: _r,
                    activeColor: Colors.red.shade600,
                    onChanged: (v) {
                      setState(() => _r = v);
                      _applyRgb();
                    },
                  ),
                  _RgbSliderRow(
                    label: 'Hijau',
                    value: _g,
                    activeColor: Colors.green.shade600,
                    onChanged: (v) {
                      setState(() => _g = v);
                      _applyRgb();
                    },
                  ),
                  _RgbSliderRow(
                    label: 'Biru',
                    value: _b,
                    activeColor: Colors.blue.shade600,
                    onChanged: (v) {
                      setState(() => _b = v);
                      _applyRgb();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RgbSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _RgbSliderRow({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: activeColor,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: activeColor,
              thumbColor: activeColor,
              inactiveTrackColor: activeColor.withValues(alpha: 0.2),
              overlayColor: activeColor.withValues(alpha: 0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
