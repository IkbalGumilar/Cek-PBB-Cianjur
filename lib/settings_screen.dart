import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apk_share_helper.dart';
import 'desktop_accent_color_helper.dart';
import 'license_screen.dart';
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
    if (_githubUsername.isEmpty) {
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
