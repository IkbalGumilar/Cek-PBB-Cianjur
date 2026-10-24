import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apk_share_helper.dart';
import 'app_security_service.dart';
import 'backup_password_store.dart';
import 'blok_backup_scheduler.dart';
import 'desktop_accent_color_helper.dart';
import 'google_auth_service.dart';
import 'google_drive_backup_policy.dart';
import 'license_screen.dart';
import 'native_file_helper.dart';
import 'theme_controller.dart';
import 'unity_lerp_widgets.dart';
import 'update_checker.dart';
import 'update_screen.dart';

const _githubUsername = 'IkbalGumilar';
final _githubProfileUrl = Uri.parse('https://github.com/$_githubUsername');

class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;
  final bool? isMaterialYouSupported;

  const SettingsScreen({
    super.key,
    required this.themeController,
    this.isMaterialYouSupported,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          const _DeveloperCard(),
          const Divider(height: 32),
          _ThemeSection(
            themeController: themeController,
            isMaterialYouSupported: isMaterialYouSupported,
          ),
          const Divider(height: 32),
          const _SecuritySection(),
          const Divider(height: 32),
          const _BackupSection(),
          const Divider(height: 32),
          const _ShareAppSection(),
          const Divider(height: 32),
          const _AboutSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  @override
  Widget build(BuildContext context) {
    if (_githubUsername.isEmpty ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            CircleAvatar(radius: 32, child: Icon(Icons.person, size: 32)),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Cek PBB Cianjur',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchGithubProfile(_githubUsername),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final name = data?['name'] as String? ?? _githubUsername;
        final bio = data?['bio'] as String?;
        final avatarUrl = data?['avatar_url'] as String?;

        return LerpPressable(
          onTap: () => launchUrl(
            _githubProfileUrl,
            mode: LaunchMode.externalApplication,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: avatarUrl != null
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, size: 32)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FaIcon(FontAwesomeIcons.github, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '@$_githubUsername',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      if (bio != null && bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(bio, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchGithubProfile(String username) async {
    final response = await Dio().get<Map<String, dynamic>>(
      'https://api.github.com/users/$username',
      options: Options(
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    return response.data ?? {};
  }
}

class _ThemeSection extends StatefulWidget {
  final ThemeController themeController;
  final bool? isMaterialYouSupported;

  const _ThemeSection({
    required this.themeController,
    this.isMaterialYouSupported,
  });

  @override
  State<_ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends State<_ThemeSection>
    with SingleTickerProviderStateMixin {
  // Preset warna populer
  static const _presets = <Color>[
    Color(0xFF2E7D32), // Hijau PBB (Default)
    Color(0xFF1565C0), // Biru Cianjur
    Color(0xFF6A1B9A), // Ungu
    Color(0xFFC62828), // Merah Marun
    Color(0xFFEF6C00), // Oranye
    Color(0xFF00695C), // Teal
    Color(0xFF4E342E), // Cokelat Kopi
    Color(0xFF37474F), // Slate Gray
  ];

  late final AnimationController _lerpController;
  late final Animation<double> _lerpCurve;

  bool _isMaterialYouSupported = false;

  // Nilai RGB saat ini (mendukung floating-point sub-pixel untuk animasi halus)
  double _currentR = 0;
  double _currentG = 0;
  double _currentB = 0;

  // Titik awal (a) dan target (b) untuk Linear Interpolation (Lerp ala Unity)
  double _startR = 0;
  double _startG = 0;
  double _startB = 0;
  double _targetR = 0;
  double _targetG = 0;
  double _targetB = 0;

  Color? _targetPresetColor;
  Color? _lastControllerColor;

  @override
  void initState() {
    super.initState();

    _lerpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _lerpCurve = CurvedAnimation(
      parent: _lerpController,
      curve: Curves.easeOutCubic,
    );

    _lerpController.addListener(_onLerpUpdate);
    _lerpController.addStatusListener(_onLerpStatus);

    _syncFromColor(widget.themeController.accentColor);

    if (widget.isMaterialYouSupported != null) {
      _isMaterialYouSupported = widget.isMaterialYouSupported!;
    } else {
      _checkDynamicColorSupport();
    }
  }

  Future<void> _checkDynamicColorSupport() async {
    bool supported = false;
    try {
      if (Platform.isAndroid) {
        final palette = await DynamicColorPlugin.getCorePalette();
        supported = palette != null;
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final desktopAccent =
            await DesktopAccentColorHelper.getDesktopAccentColor();
        if (desktopAccent != null) {
          supported = true;
        } else {
          final pluginAccent = await DynamicColorPlugin.getAccentColor();
          supported = pluginAccent != null;
        }
      }
    } catch (_) {
      supported = false;
    }

    if (mounted) {
      setState(() {
        _isMaterialYouSupported = supported;
      });
    }
  }

  void _syncFromColor(Color color) {
    _lastControllerColor = color;
    final argb = color.toARGB32();
    _currentR = ((argb >> 16) & 0xFF).toDouble();
    _currentG = ((argb >> 8) & 0xFF).toDouble();
    _currentB = (argb & 0xFF).toDouble();
  }

  void _animateToColor(Color targetColor) {
    final argb = targetColor.toARGB32();
    final tr = ((argb >> 16) & 0xFF).toDouble();
    final tg = ((argb >> 8) & 0xFF).toDouble();
    final tb = (argb & 0xFF).toDouble();

    _targetPresetColor = targetColor;

    // Titik awal (a) dan titik tujuan (b)
    _startR = _currentR;
    _startG = _currentG;
    _startB = _currentB;

    _targetR = tr;
    _targetG = tg;
    _targetB = tb;

    _lerpController.forward(from: 0.0);
  }

  void _onLerpUpdate() {
    final t = _lerpCurve.value;
    setState(() {
      _currentR = unityLerp(_startR, _targetR, t);
      _currentG = unityLerp(_startG, _targetG, t);
      _currentB = unityLerp(_startB, _targetB, t);
    });

    final interpolatedColor = Color.fromARGB(
      255,
      _currentR.round().clamp(0, 255),
      _currentG.round().clamp(0, 255),
      _currentB.round().clamp(0, 255),
    );
    _lastControllerColor = interpolatedColor;
    widget.themeController.setAccentColor(interpolatedColor, saveToPrefs: false);
  }

  void _onLerpStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final finalColor = Color.fromARGB(
        255,
        _targetR.round().clamp(0, 255),
        _targetG.round().clamp(0, 255),
        _targetB.round().clamp(0, 255),
      );
      _lastControllerColor = finalColor;
      widget.themeController.setAccentColor(finalColor, saveToPrefs: true);
    }
  }

  @override
  void dispose() {
    _lerpController.removeListener(_onLerpUpdate);
    _lerpController.removeStatusListener(_onLerpStatus);
    _lerpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeState>(
      valueListenable: widget.themeController,
      builder: (context, themeState, _) {
        if (!_lerpController.isAnimating &&
            themeState.accentColor != _lastControllerColor) {
          _syncFromColor(themeState.accentColor);
        }

        final rInt = _currentR.round().clamp(0, 255);
        final gInt = _currentG.round().clamp(0, 255);
        final bInt = _currentB.round().clamp(0, 255);
        final currentColor = Color.fromARGB(255, rInt, gInt, bInt);
        final hexString =
            '#${rInt.toRadixString(16).padLeft(2, '0')}${gInt.toRadixString(16).padLeft(2, '0')}${bInt.toRadixString(16).padLeft(2, '0')}'
                .toUpperCase();

        final showMaterialYouSwitch = _isMaterialYouSupported;
        final showAccentColorOptions =
            !_isMaterialYouSupported || !themeState.useMaterialYou;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tema & Tampilan',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Dropdown Mode Tema
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Mode Tema',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AppThemeMode>(
                    value: themeState.mode,
                    isExpanded: true,
                    items: AppThemeMode.values.map((mode) {
                      final icon = switch (mode) {
                        AppThemeMode.system => Icons.brightness_auto,
                        AppThemeMode.light => Icons.light_mode,
                        AppThemeMode.dark => Icons.dark_mode,
                        AppThemeMode.amoled => Icons.nightlight_round,
                      };
                      return DropdownMenuItem<AppThemeMode>(
                        value: mode,
                        child: Row(
                          children: [
                            Icon(icon, size: 20),
                            const SizedBox(width: 12),
                            Text(mode.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (newMode) {
                      if (newMode != null) {
                        widget.themeController.setMode(newMode);
                      }
                    },
                  ),
                ),
              ),

              // Switch Material You (Hanya tampil jika didukung oleh sistem/Android 12+)
              if (showMaterialYouSwitch) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.auto_awesome),
                  title: const Text('Warna Dinamis (Material You)'),
                  subtitle: const Text(
                    'Mengikuti warna wallpaper sistem (khusus Android 12+ yang mendukung)',
                  ),
                  value: themeState.useMaterialYou,
                  onChanged: (val) =>
                      widget.themeController.setUseMaterialYou(val),
                ),
              ],

              // Bagian Aksen Warna (RGB): Muncul dari bawah saat Material You nonaktif
              AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slideAnim = Tween<Offset>(
                      begin: const Offset(0.0, 0.15),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ));
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: slideAnim,
                        child: child,
                      ),
                    );
                  },
                  child: showAccentColorOptions
                      ? Column(
                          key: const ValueKey('accent_color_options_visible'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              'Aksen Warna (RGB)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pilih preset atau atur nilai Red, Green, Blue untuk warna aplikasi.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),

                            // Preview & Info Card
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: currentColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.black26),
                                      boxShadow: [
                                        BoxShadow(
                                          color: currentColor.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          hexString,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'R: $rInt  G: $gInt  B: $bInt',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (currentColor.toARGB32() !=
                                      ThemeController.defaultAccentColor
                                          .toARGB32())
                                    TextButton.icon(
                                      onPressed: () => _animateToColor(
                                        ThemeController.defaultAccentColor,
                                      ),
                                      icon: const Icon(
                                        Icons.restart_alt,
                                        size: 16,
                                      ),
                                      label: const Text('Reset'),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Presets
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _presets.map((preset) {
                                  final isSelected =
                                      (_targetPresetColor ?? currentColor)
                                              .toARGB32() ==
                                          preset.toARGB32();
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: InkWell(
                                      onTap: () => _animateToColor(preset),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: preset,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black12,
                                            width: isSelected ? 3 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: preset.withValues(
                                                      alpha: 0.5,
                                                    ),
                                                    blurRadius: 6,
                                                    spreadRadius: 1,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: isSelected
                                            ? const Icon(
                                                Icons.check,
                                                size: 20,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Slider Merah (R)
                            _buildRgbSlider(
                              label: 'R',
                              labelColor: Colors.red,
                              value: _currentR,
                              activeColor: Colors.red,
                              onChanged: (val) {
                                _lerpController.stop();
                                _targetPresetColor = null;
                                setState(() => _currentR = val);
                                final newColor = Color.fromARGB(
                                  255,
                                  _currentR.round().clamp(0, 255),
                                  gInt,
                                  bInt,
                                );
                                _lastControllerColor = newColor;
                                widget.themeController.setAccentColor(
                                  newColor,
                                  saveToPrefs: false,
                                );
                              },
                              onChangeEnd: (val) {
                                final newColor = Color.fromARGB(
                                  255,
                                  _currentR.round().clamp(0, 255),
                                  gInt,
                                  bInt,
                                );
                                _lastControllerColor = newColor;
                                widget.themeController.setAccentColor(
                                  newColor,
                                  saveToPrefs: true,
                                );
                              },
                            ),

                            // Slider Hijau (G)
                            _buildRgbSlider(
                              label: 'G',
                              labelColor: Colors.green,
                              value: _currentG,
                              activeColor: Colors.green,
                              onChanged: (val) {
                                _lerpController.stop();
                                _targetPresetColor = null;
                                setState(() => _currentG = val);
                                final newColor = Color.fromARGB(
                                  255,
                                  rInt,
                                  _currentG.round().clamp(0, 255),
                                  bInt,
                                );
                                _lastControllerColor = newColor;
                                widget.themeController.setAccentColor(
                                  newColor,
                                  saveToPrefs: false,
                                );
                              },
                              onChangeEnd: (val) {
                                final newColor = Color.fromARGB(
                                  255,
                                  rInt,
                                  _currentG.round().clamp(0, 255),
                                  bInt,
                                );
                                _lastControllerColor = newColor;
                                widget.themeController.setAccentColor(
                                  newColor,
                                  saveToPrefs: true,
                                );
                              },
                            ),

                            // Slider Biru (B)
                            _buildRgbSlider(
                              label: 'B',
                              labelColor: Colors.blue,
                              value: _currentB,
                              activeColor: Colors.blue,
                              onChanged: (val) {
                                _lerpController.stop();
                                _targetPresetColor = null;
                                setState(() => _currentB = val);
                                final newColor = Color.fromARGB(
                                  255,
                                  rInt,
                                  gInt,
                                  _currentB.round().clamp(0, 255),
                                );
                                _lastControllerColor = newColor;
                                widget.themeController.setAccentColor(
                                  newColor,
                                  saveToPrefs: false,
                                );
                              },
                              onChangeEnd: (val) {
                                final newColor = Color.fromARGB(
                                  255,
                                  rInt,
                                  gInt,
                                  _currentB.round().clamp(0, 255),
                                );
                                _lastControllerColor = newColor;
                                widget.themeController.setAccentColor(
                                  newColor,
                                  saveToPrefs: true,
                                );
                              },
                            ),
                          ],
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('accent_color_options_hidden'),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRgbSlider({
    required String label,
    required Color labelColor,
    required double value,
    required Color activeColor,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final intVal = value.round().clamp(0, 255);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 255.0),
              min: 0,
              max: 255,
              divisions: 255,
              activeColor: activeColor,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$intVal',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  final AppSecurityService _service = AppSecurityService.instance;

  bool _isLockEnabled = false;
  AppLockType _lockType = AppLockType.device;
  int _timeoutSeconds = 0;
  String _biometricSummary = 'Memeriksa dukungan perangkat...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await _service.isLockEnabled();
    final type = await _service.getLockType();
    final timeout = await _service.getTimeoutSeconds();
    final summary = await _service.getBiometricCapabilitiesSummary();

    if (mounted) {
      setState(() {
        _isLockEnabled = enabled;
        _lockType = type;
        _timeoutSeconds = timeout;
        _biometricSummary = summary;
        _isLoading = false;
      });
    }
  }

  String _timeoutLabel(int seconds) {
    switch (seconds) {
      case 0:
        return 'Segera saat aplikasi ditutup';
      case 30:
        return 'Setelah 30 detik di latar belakang';
      case 60:
        return 'Setelah 1 menit di latar belakang';
      case 300:
        return 'Setelah 5 menit di latar belakang';
      default:
        return 'Setelah $seconds detik';
    }
  }

  String _lockTypeLabel(AppLockType type) {
    switch (type) {
      case AppLockType.device:
        return 'Sama kayak HP (Biometrik / Kunci Layar)';
      case AppLockType.pin:
        return 'PIN 6 Digit Kustom';
      case AppLockType.password:
        return 'Kata Sandi Kustom';
    }
  }

  Future<void> _toggleLock(bool targetState) async {
    if (targetState) {
      // Mengaktifkan: Jika device, uji autentikasi terlebih dahulu
      if (_lockType == AppLockType.device) {
        final success = await _service.authenticateWithDevice(
          reason: 'Verifikasi biometrik / kunci HP untuk mengaktifkan kunci aplikasi',
        );
        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verifikasi dibatalkan atau gagal. Kunci aplikasi belum diaktifkan.'),
              ),
            );
          }
          return;
        }
      } else if (_lockType == AppLockType.pin) {
        final hasPin = await _service.hasCustomPin();
        if (!hasPin) {
          await _setupNewPin();
          if (!mounted) return;
          final updatedHasPin = await _service.hasCustomPin();
          if (!updatedHasPin) return;
        }
      } else if (_lockType == AppLockType.password) {
        final hasPwd = await _service.hasCustomPassword();
        if (!hasPwd) {
          await _setupNewPassword();
          if (!mounted) return;
          final updatedHasPwd = await _service.hasCustomPassword();
          if (!updatedHasPwd) return;
        }
      }

      await _service.setLockEnabled(true);
      if (mounted) {
        setState(() => _isLockEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kunci aplikasi berhasil diaktifkan.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      // Mematikan: wajib verifikasi keamanan terlebih dahulu agar tidak dimatikan orang lain
      if (_lockType == AppLockType.device) {
        final success = await _service.authenticateWithDevice(
          reason: 'Konfirmasi keamanan untuk menonaktifkan kunci aplikasi',
        );
        if (!success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verifikasi dibatalkan. Kunci aplikasi tetap aktif.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      await _service.setLockEnabled(false);
      if (mounted) {
        setState(() => _isLockEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunci aplikasi dinonaktifkan.')),
        );
      }
    }
  }

  Future<void> _showLockTypeDialog() async {
    final chosen = await showDialog<AppLockType>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Metode Kunci'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fingerprint_rounded, color: Colors.blue),
                title: const Text('Sama Kayak HP (Direkomendasikan)'),
                subtitle: const Text('Sidik Jari, Wajah, atau PIN/Pola layar HP bawaan'),
                selected: _lockType == AppLockType.device,
                onTap: () => Navigator.of(ctx).pop(AppLockType.device),
              ),
              ListTile(
                leading: const Icon(Icons.pin_rounded, color: Colors.teal),
                title: const Text('PIN 6 Digit Kustom'),
                subtitle: const Text('Keypad numerik khusus aplikasi'),
                selected: _lockType == AppLockType.pin,
                onTap: () => Navigator.of(ctx).pop(AppLockType.pin),
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded, color: Colors.deepPurple),
                title: const Text('Kata Sandi Kustom'),
                subtitle: const Text('Sandi teks bebas khusus aplikasi'),
                selected: _lockType == AppLockType.password,
                onTap: () => Navigator.of(ctx).pop(AppLockType.password),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null && chosen != _lockType) {
      if (chosen == AppLockType.pin) {
        final hasPin = await _service.hasCustomPin();
        if (!hasPin) {
          await _setupNewPin();
          if (!mounted) return;
          if (!(await _service.hasCustomPin())) return;
        }
      } else if (chosen == AppLockType.password) {
        final hasPwd = await _service.hasCustomPassword();
        if (!hasPwd) {
          await _setupNewPassword();
          if (!mounted) return;
          if (!(await _service.hasCustomPassword())) return;
        }
      }

      await _service.setLockType(chosen);
      if (mounted) {
        setState(() => _lockType = chosen);
      }
    }
  }

  Future<void> _showTimeoutDialog() async {
    const options = <int, String>{
      0: 'Segera saat aplikasi ditutup / beralih',
      30: 'Setelah 30 detik di latar belakang',
      60: 'Setelah 1 menit di latar belakang',
      300: 'Setelah 5 menit di latar belakang',
    };

    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kunci Otomatis (Timeout)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.entries.map((e) {
              return ListTile(
                title: Text(e.value),
                selected: _timeoutSeconds == e.key,
                onTap: () => Navigator.of(ctx).pop(e.key),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (chosen != null && chosen != _timeoutSeconds) {
      await _service.setTimeoutSeconds(chosen);
      if (mounted) {
        setState(() => _timeoutSeconds = chosen);
      }
    }
  }

  Future<void> _testBiometrics() async {
    final success = await _service.authenticateWithDevice(
      reason: 'Uji coba autentikasi biometrik / kunci HP',
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Autentikasi biometrik berhasil!'
              : 'Autentikasi gagal atau dibatalkan.',
        ),
        backgroundColor: success ? Colors.green[800] : Colors.red[800],
      ),
    );
  }

  Future<void> _setupNewPin() async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Buat PIN Baru (6 Digit)'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'PIN 6 Digit',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length == 6) {
                  Navigator.of(ctx).pop(controller.text);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );

      if (result != null && result.length == 6) {
        await _service.setCustomPin(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN kustom berhasil disimpan.')),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _setupNewPassword() async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Buat Kata Sandi Baru'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Kata Sandi',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.of(ctx).pop(controller.text);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );

      if (result != null && result.isNotEmpty) {
        await _service.setCustomPassword(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kata sandi kustom berhasil disimpan.')),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keamanan Aplikasi',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Kunci aplikasi ala m-Banking menggunakan Sidik Jari, Wajah, atau Kunci Layar HP untuk menjaga kerahasiaan data DHKP PBB.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.security_rounded),
            title: const Text('Kunci Aplikasi (App Lock)'),
            subtitle: Text(
              _isLockEnabled
                  ? 'Aktif • ${_lockTypeLabel(_lockType)}'
                  : 'Nonaktif • Aplikasi dapat langsung dibuka',
            ),
            value: _isLockEnabled,
            onChanged: _toggleLock,
          ),
          if (_isLockEnabled) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Metode Kunci'),
              subtitle: Text(_lockTypeLabel(_lockType)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showLockTypeDialog,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Kunci Otomatis (Timeout)'),
              subtitle: Text(_timeoutLabel(_timeoutSeconds)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showTimeoutDialog,
            ),
            if (_lockType == AppLockType.device) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fingerprint_rounded, color: Colors.blue, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Deteksi Keamanan HP',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _biometricSummary,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testBiometrics,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Uji Coba Autentikasi HP'),
                ),
              ),
            ],
            if (_lockType == AppLockType.pin)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _setupNewPin,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ubah PIN 6 Digit'),
                ),
              ),
            if (_lockType == AppLockType.password)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _setupNewPassword,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ubah Kata Sandi'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BackupSection extends StatefulWidget {
  const _BackupSection();

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _isBackingUp = false;
  DateTime? _lastBackupTime;
  int? _lastBackupSize;
  int _frequencyDays = 1;
  bool _onlyDkhpData = true;
  String _googleAccount = '';
  String _googleDisplayName = '';
  String _googlePhotoUrl = '';
  String _googleFolderLink = '';
  bool _overCellular = false;
  bool _hasBackupPassword = false;
  List<File> _localBackups = [];

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
  }

  Future<void> _loadBackupSettings() async {
    final scheduler = BlokBackupScheduler.instance;
    final time = await scheduler.getLastBackupTime();
    final size = await scheduler.getLastBackupSize();
    final freq = await scheduler.getFrequencyDays();
    final onlyData = await scheduler.getOnlyDkhpData();
    final google = await scheduler.getGoogleAccount();
    final googleName = await scheduler.getGoogleDisplayName();
    final googlePhoto = await scheduler.getGooglePhotoUrl();
    final folderLink = await scheduler.getGoogleDriveFolderLink();
    final cellular = await scheduler.getOverCellular();
    final files = await scheduler.getLocalBackups();
    final hasBackupPassword = await BackupPasswordStore.instance.hasPassword();

    if (mounted) {
      setState(() {
        _lastBackupTime = time;
        _lastBackupSize = size;
        _frequencyDays = freq;
        _onlyDkhpData = onlyData;
        _googleAccount = google;
        _googleDisplayName = googleName;
        _googlePhotoUrl = googlePhoto;
        _googleFolderLink = folderLink;
        _overCellular = cellular;
        _hasBackupPassword = hasBackupPassword;
        _localBackups = files;
      });
    }
  }

  String _formatBackupFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  String _formatBackupDate(DateTime? dt) {
    if (dt == null) return 'Belum pernah';
    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final timeStr = '${pad2(dt.hour)}:${pad2(dt.minute)}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Hari ini, $timeStr';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Kemarin, $timeStr';
    }
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}, $timeStr';
  }

  String _frequencyLabel(int days) {
    switch (days) {
      case 0:
        return 'Jangan pernah (Hanya manual)';
      case 1:
        return 'Harian (setiap 24 jam / pk 02:00)';
      case 7:
        return 'Mingguan (setiap 7 hari)';
      case 14:
        return 'Setiap 14 hari';
      case 30:
        return 'Bulanan (setiap 30 hari)';
      default:
        return 'Setiap $days hari';
    }
  }

  Future<void> _performBackup() async {
    final hasBackupPassword =
        await BackupPasswordStore.instance.hasPassword();
    if (!hasBackupPassword && !(await _setupBackupPassword())) {
      return;
    }
    if (!_hasBackupPassword) setState(() => _hasBackupPassword = true);
    setState(() => _isBackingUp = true);
    try {
      final file = await BlokBackupScheduler.instance.performBackup(
        onlyDkhpData: _onlyDkhpData,
      );
      if (!mounted) return;
      await _loadBackupSettings();
      if (!mounted) return;

      if (file != null) {
        final size = file.existsSync() ? file.lengthSync() : 0;
        final sizeText = _formatBackupFileSize(size);
        final targetFolderText = _googleFolderLink.isNotEmpty
            ? 'folder bersama Google Drive'
            : 'folder khusus "${GoogleDriveBackupPolicy.dedicatedFolderName}"';
        final googleMsg = _googleAccount.isNotEmpty
            ? '\nDisinkronkan ke $targetFolderText ($_googleAccount)'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cadangan data DHKP berhasil disimpan ($sizeText).$googleMsg',
            ),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat cadangan: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<bool> _setupBackupPassword() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var errorText = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Atur kata sandi backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kata sandi ini melindungi backup dan diperlukan untuk '
                'memulihkannya di perangkat lain. Simpan dengan aman; '
                'kata sandi yang hilang tidak dapat dipulihkan. Backup lama '
                'tetap memerlukan kata sandi lamanya.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kata sandi (minimal 12 karakter)',
                ),
              ),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Ulangi kata sandi',
                ),
              ),
              if (errorText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  errorText,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final password = passwordController.text;
                if (password.length < 12) {
                  setDialogState(
                    () => errorText = 'Kata sandi harus minimal 12 karakter.',
                  );
                  return;
                }
                if (password != confirmController.text) {
                  setDialogState(() => errorText = 'Kata sandi tidak cocok.');
                  return;
                }
                try {
                  await BackupPasswordStore.instance.save(password);
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  setDialogState(
                    () => errorText = 'Gagal menyimpan kata sandi: $e',
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    passwordController.dispose();
    confirmController.dispose();
    if (saved == true && mounted) {
      setState(() => _hasBackupPassword = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kata sandi tersimpan di secure storage perangkat.'),
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> _showFrequencyDialog() async {
    const options = <int, String>{
      0: 'Jangan pernah (Hanya manual)',
      1: 'Harian (setiap 24 jam / pk 02:00)',
      7: 'Mingguan (setiap 7 hari)',
      14: 'Setiap 14 hari',
      30: 'Bulanan (setiap 30 hari)',
    };

    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frekuensi Cadangan Otomatis'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.entries.map((e) {
              return RadioListTile<int>(
                title: Text(e.value),
                value: e.key,
                groupValue: _frequencyDays,
                onChanged: (val) => Navigator.of(ctx).pop(val),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (chosen != null && chosen != _frequencyDays) {
      await BlokBackupScheduler.instance.setFrequencyDays(chosen);
      if (mounted) setState(() => _frequencyDays = chosen);
    }
  }

  Future<void> _showGoogleAccountDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _GoogleAccountDialog(
        initialEmail: _googleAccount,
        initialDisplayName: _googleDisplayName,
        initialPhotoUrl: _googlePhotoUrl,
      ),
    );

    if (result == null || result == 'cancel') return;

    if (result == 'remove') {
      await GoogleAuthService.instance.signOut();
      if (mounted) {
        setState(() {
          _googleAccount = '';
          _googleDisplayName = '';
          _googlePhotoUrl = '';
          _googleFolderLink = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Akun Google telah dilepas.')),
        );
      }
    } else {
      final email = result;
      await BlokBackupScheduler.instance.setGoogleAccount(email);
      if (mounted) {
        setState(() => _googleAccount = email);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              email.isEmpty
                  ? 'Akun Google telah dilepas.'
                  : 'Akun Google berhasil dihubungkan ($email)',
            ),
          ),
        );
      }
      await _loadBackupSettings();
    }
  }

  Future<void> _showGoogleFolderDialog() async {
    if (_googleAccount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hubungkan akun Google terlebih dahulu sebelum mengatur link folder bersama.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _GoogleFolderDialog(
        currentAccount: _googleAccount,
        initialLink: _googleFolderLink,
      ),
    );

    if (result == null || result == 'cancel') return;

    if (result == 'reset') {
      await BlokBackupScheduler.instance.setGoogleDriveFolderLink('');
      if (mounted) {
        setState(() => _googleFolderLink = '');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Folder bersama direset. Cadangan akan diarahkan ke folder bawaan ("${GoogleDriveBackupPolicy.dedicatedFolderName}").',
            ),
          ),
        );
      }
    } else {
      final success =
          await BlokBackupScheduler.instance.setGoogleDriveFolderLink(result);
      if (!mounted) return;
      if (success) {
        setState(() => _googleFolderLink = result);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Folder bersama Google Drive berhasil disimpan.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Link Google Drive tidak valid atau akun Google belum terhubung.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showNetworkDialog() async {
    final chosen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadangkan Melalui'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              title: const Text('Hanya Wi-Fi'),
              subtitle: const Text('Hemat kuota internet data seluler'),
              value: false,
              groupValue: _overCellular,
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
            RadioListTile<bool>(
              title: const Text('Wi-Fi atau Seluler'),
              subtitle: const Text('Tetap mencadangkan saat menggunakan paket data'),
              value: true,
              groupValue: _overCellular,
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
          ],
        ),
      ),
    );

    if (chosen != null && chosen != _overCellular) {
      await BlokBackupScheduler.instance.setOverCellular(chosen);
      if (mounted) setState(() => _overCellular = chosen);
    }
  }

  Future<void> _shareBackupFile(File file) async {
    try {
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final fileName = file.uri.pathSegments.last;
      if (Platform.isAndroid) {
        await NativeFileHelper.shareBytes(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'application/octet-stream',
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berkas tersimpan di: ${file.path}'),
            action: SnackBarAction(
              label: 'Salin Path',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: file.path));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan berkas: $e')),
        );
      }
    }
  }

  Future<void> _deleteBackupFile(File file) async {
    final fileName = file.uri.pathSegments.last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Cadangan?'),
        content: Text(
          'Berkas $fileName akan dihapus permanen dari penyimpanan perangkat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
        await _loadBackupSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berkas cadangan berhasil dihapus.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus berkas: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cadangan Data DHKP',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Cadangkan data DHKP ke penyimpanan perangkat atau akun Google. '
            'Pencadangan otomatis berjalan tiap pk 02:00 pagi. Backup baru '
            'dilindungi kata sandi yang hanya tersimpan di secure storage.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password_outlined),
            title: Text(
              _hasBackupPassword
                  ? 'Kata sandi backup tersimpan'
                  : 'Atur kata sandi backup',
            ),
            subtitle: Text(
              _hasBackupPassword
                  ? 'Diperlukan untuk membuka backup di perangkat lain.'
                  : 'Wajib untuk membuat backup terenkripsi.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _setupBackupPassword,
          ),
          Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.cloud_sync_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cadangan Terakhir',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatBackupDate(_lastBackupTime),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (_lastBackupSize != null &&
                                _lastBackupSize! > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Ukuran: ${_formatBackupFileSize(_lastBackupSize!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (_googleAccount.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _googleFolderLink.isNotEmpty
                                    ? 'Google Drive: $_googleAccount (Folder Bersama)'
                                    : 'Google Drive: $_googleAccount (Folder: ${GoogleDriveBackupPolicy.dedicatedFolderName})',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isBackingUp ? null : _performBackup,
                      icon: _isBackingUp
                          ? const Icon(Icons.hourglass_top_outlined, size: 18)
                          : const Icon(Icons.backup_outlined),
                      label: Text(
                        _isBackingUp
                            ? 'Sedang Mencadangkan...'
                            : 'Cadangkan Sekarang',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Cadangkan Otomatis'),
            subtitle: Text(_frequencyLabel(_frequencyDays)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showFrequencyDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _googlePhotoUrl.isNotEmpty
                ? CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(_googlePhotoUrl),
                  )
                : const Icon(Icons.add_to_drive_outlined),
            title: Text(
              _googleDisplayName.isNotEmpty
                  ? 'Akun Google ($_googleDisplayName)'
                  : 'Akun Google (Google Drive)',
            ),
            subtitle: Text(
              _googleAccount.isEmpty
                  ? 'Belum terhubung • Dibatasi ke folder khusus "${GoogleDriveBackupPolicy.dedicatedFolderName}"'
                  : '$_googleAccount • ${_googleFolderLink.isNotEmpty ? 'Folder bersama aktif' : 'Folder khusus "${GoogleDriveBackupPolicy.dedicatedFolderName}"'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showGoogleAccountDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: _googleAccount.isNotEmpty,
            leading: Icon(
              Icons.folder_shared_outlined,
              color: _googleAccount.isNotEmpty
                  ? null
                  : Theme.of(context).disabledColor,
            ),
            title: const Text('Folder Bersama Google Drive'),
            subtitle: Text(
              _googleAccount.isEmpty
                  ? 'Hubungkan akun Google terlebih dahulu untuk mengatur folder bersama'
                  : (_googleFolderLink.isEmpty
                      ? 'Gunakan folder bawaan ("${GoogleDriveBackupPolicy.dedicatedFolderName}")'
                      : 'Folder bersama aktif: ${GoogleDriveBackupPolicy.extractFolderId(_googleFolderLink) ?? _googleFolderLink}'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _googleAccount.isEmpty ? null : _showGoogleFolderDialog,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.table_chart_outlined),
            title: const Text('Hanya Data DHKP Saja'),
            subtitle: const Text(
              'Cadangkan tanpa menyertakan foto lembaran SPPT agar berkas sangat ringkas dan menghemat memori perangkat.',
            ),
            value: _onlyDkhpData,
            onChanged: (val) async {
              await BlokBackupScheduler.instance.setOnlyDkhpData(val);
              if (mounted) setState(() => _onlyDkhpData = val);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wifi_outlined),
            title: const Text('Cadangkan Lewat'),
            subtitle: Text(_overCellular ? 'Wi-Fi atau Seluler' : 'Hanya Wi-Fi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showNetworkDialog,
          ),
          if (_localBackups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Berkas Cadangan',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            ..._localBackups.map((file) {
              final fileName = file.uri.pathSegments.last;
              final size = file.existsSync() ? file.lengthSync() : 0;
              final modTime =
                  file.existsSync() ? file.lastModifiedSync() : null;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(top: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.inventory_2_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatBackupDate(modTime)} • ${_formatBackupFileSize(size)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share_outlined, size: 20),
                        tooltip: 'Bagikan berkas cadangan',
                        onPressed: () => _shareBackupFile(file),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.red,
                        ),
                        tooltip: 'Hapus berkas ini',
                        onPressed: () => _deleteBackupFile(file),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _GoogleAccountDialog extends StatefulWidget {
  final String initialEmail;
  final String initialDisplayName;
  final String initialPhotoUrl;

  const _GoogleAccountDialog({
    required this.initialEmail,
    this.initialDisplayName = '',
    this.initialPhotoUrl = '',
  });

  @override
  State<_GoogleAccountDialog> createState() => _GoogleAccountDialogState();
}

class _GoogleAccountDialogState extends State<_GoogleAccountDialog> {
  bool _loading = false;
  String? _errorMessage;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final user = await GoogleAuthService.instance.signIn();
      if (!mounted) return;
      if (user != null) {
        Navigator.of(context).pop(user.email);
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initialEmail.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.green),
          SizedBox(width: 8),
          Text('Akun Google & Drive'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 20, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          GoogleDriveBackupPolicy.privacyNoticeTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          GoogleDriveBackupPolicy.privacyNoticeBody,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (hasInitial) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.teal.shade100,
                      backgroundImage: widget.initialPhotoUrl.isNotEmpty
                          ? NetworkImage(widget.initialPhotoUrl)
                          : null,
                      child: widget.initialPhotoUrl.isEmpty
                          ? const Icon(Icons.account_circle, color: Colors.teal, size: 28)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.initialDisplayName.isNotEmpty)
                            Text(
                              widget.initialDisplayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          Text(
                            widget.initialEmail,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Terhubung & Izin Google Drive Aktif',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cadangan data disinkronkan ke folder khusus "${GoogleDriveBackupPolicy.dedicatedFolderName}".',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.blueGrey.shade900 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.blueGrey.shade700 : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.add_to_drive_outlined,
                          size: 18,
                          color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Izin Akses Google Drive',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Menghubungkan akun Google akan meminta izin resmi Google Drive untuk:\n'
                      '• Menyimpan & memperbarui berkas cadangan DHKP secara otomatis.\n'
                      '• Menempatkan berkas ke folder "${GoogleDriveBackupPolicy.dedicatedFolderName}".\n'
                      '• Akun HANYA dapat dihubungkan melalui sistem Google Auth resmi demi keamanan token otorisasi.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _handleGoogleSignIn,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const FaIcon(
                          FontAwesomeIcons.google,
                          color: Colors.red,
                          size: 18,
                        ),
                  label: Text(
                    _loading ? 'Menghubungkan...' : 'Masuk & Izinkan Google Drive',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor: isDark ? Colors.grey.shade800 : Colors.white,
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (hasInitial)
          TextButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text('Putuskan Akun', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: Text(hasInitial ? 'Tutup' : 'Batal'),
        ),
      ],
    );
  }
}

class _GoogleFolderDialog extends StatefulWidget {
  final String currentAccount;
  final String initialLink;

  const _GoogleFolderDialog({
    required this.currentAccount,
    required this.initialLink,
  });

  @override
  State<_GoogleFolderDialog> createState() => _GoogleFolderDialogState();
}

class _GoogleFolderDialogState extends State<_GoogleFolderDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLink);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initialLink.isNotEmpty;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.folder_shared_outlined, color: Colors.blue),
          SizedBox(width: 8),
          Text('Folder Bersama'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Syarat Hak Akses Folder',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          GoogleDriveBackupPolicy.editorRequirementNotice,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Akun Google terhubung: ${widget.currentAccount}\n\n'
              'Tempel link atau ID folder Google Drive bersama tempat berkas cadangan disimpan:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link / ID Folder Google Drive',
                hintText: 'https://drive.google.com/drive/folders/...',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (hasInitial)
          TextButton(
            onPressed: () => Navigator.of(context).pop('reset'),
            child: const Text('Gunakan Bawaan'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _ShareAppSection extends StatefulWidget {
  const _ShareAppSection();

  @override
  State<_ShareAppSection> createState() => _ShareAppSectionState();
}

class _ShareAppSectionState extends State<_ShareAppSection> {
  bool _sharing = false;

  // Android: bagikan berkas APK langsung (sideload). Windows/Linux: tidak
  // ada mekanisme share-sheet berkas biner yang generik lintas platform,
  // jadi cukup salin link halaman rilis GitHub-nya — penerima unduh sendiri
  // versi yang cocok untuk sistem operasinya.
  Future<void> _shareApp() async {
    setState(() => _sharing = true);
    try {
      if (Platform.isAndroid) {
        final location = await ApkShareHelper.shareApk();
        if (!mounted) return;
        final message = location != null
            ? 'APK tersimpan di $location'
            : 'Share sheet dibuka. Gagal menyimpan salinan ke folder Dokumen.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      } else {
        await Clipboard.setData(
          const ClipboardData(text: UpdateChecker.releasesPageUrl),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Link unduhan aplikasi disalin, tinggal tempel & bagikan.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membagikan aplikasi: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bagikan Aplikasi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            Platform.isAndroid
                ? 'Aplikasi ini belum ada di Play Store, jadi diinstal manual. Berkas APK-nya akan '
                      'disimpan ke penyimpanan internal (folder Dokumen) dan bisa langsung dibagikan '
                      'lewat WhatsApp, Quick Share, Bluetooth, atau aplikasi lain.'
                : 'Bagikan link halaman unduhan aplikasi ini (bukan berkas langsung), supaya penerima '
                      'bisa mengunduh sendiri versi yang sesuai dengan sistem operasinya.',
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _sharing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Platform.isAndroid ? Icons.share : Icons.link),
            title: Text(
              Platform.isAndroid
                  ? 'Bagikan Aplikasi (APK)'
                  : 'Salin Link Aplikasi',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _sharing ? null : _shareApp,
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _checking = false;

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await UpdateChecker.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aplikasi sudah menggunakan versi terbaru.'),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UpdateScreen(info: info)),
      );
    } on UpdateCheckError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tentang Aplikasi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Cek PBB Cianjur membantu perangkat desa mengecek tagihan dan status pembayaran '
            'PBB warga secara cepat, satuan maupun massal, tanpa perlu membuka situs resmi '
            'satu per satu di browser.',
          ),
          const SizedBox(height: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              if (info == null) return const SizedBox.shrink();
              return Text(
                'Versi ${info.version} (${info.buildNumber})',
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _checking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_outlined),
            title: const Text('Periksa Pembaruan'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkForUpdate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Lisensi Open Source'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LicenseScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
