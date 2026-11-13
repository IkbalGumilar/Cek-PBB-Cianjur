import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'main_shell.dart';
import 'startup_setup_screen.dart';
import 'theme_controller.dart';

/// Layar pembuka (Splash Screen) aplikasi Cek PBB Cianjur.
/// Menampilkan logo Kabupaten Cianjur, identitas Bapenda, dan versi aplikasi
/// dengan animasi halus dan tata letak responsif (mobile, tablet, desktop)
/// sebelum berpindah ke layar utama [MainShell].
class SplashScreen extends StatefulWidget {
  final ThemeController? themeController;
  final Widget? nextScreen;
  final Duration displayDuration;
  final bool isPreview;

  const SplashScreen({
    super.key,
    this.themeController,
    this.nextScreen,
    this.displayDuration = const Duration(milliseconds: 1800),
    this.isPreview = false,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _textFadeAnimation;

  Timer? _transitionTimer;
  String _version = '';
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _textFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.85, curve: Curves.easeOut),
    );

    _controller.forward();
    _loadVersion();

    if (widget.displayDuration > Duration.zero) {
      _transitionTimer = Timer(widget.displayDuration, _finishSplash);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishSplash());
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = 'v${info.version}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _version = 'v2.0.0';
        });
      }
    }
  }

  Future<void> _finishSplash() async {
    if (!mounted || _navigated) return;
    _navigated = true;
    _transitionTimer?.cancel();

    if (widget.isPreview && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Widget destination;
    if (widget.nextScreen != null) {
      destination = widget.nextScreen!;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final isSetupDone = prefs.getBool('startup_setup_completed') ?? false;
      if (!isSetupDone) {
        destination = StartupSetupScreen(
          themeController: widget.themeController,
        );
      } else {
        destination = MainShell(
          themeController: widget.themeController ?? ThemeController(),
        );
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, _, _) => destination,
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finishSplash,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final isTall = constraints.maxHeight >= 650;
              final logoSize = isWide || isTall ? 140.0 : 108.0;
              final glowSize = isWide || isTall ? 180.0 : 140.0;

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Center(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isWide ? 48.0 : 28.0,
                            vertical: isTall ? 36.0 : 20.0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 12),
                              // Bagian Tengah: Logo & Identitas Aplikasi (Responsif Desktop & Mobile)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 580,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    ScaleTransition(
                                      scale: _scaleAnimation,
                                      child: FadeTransition(
                                        opacity: _fadeAnimation,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              width: glowSize,
                                              height: glowSize,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: colorScheme.primary
                                                    .withValues(alpha: 0.12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: colorScheme.primary
                                                        .withValues(
                                                          alpha: 0.22,
                                                        ),
                                                    blurRadius: isWide
                                                        ? 48
                                                        : 36,
                                                    spreadRadius: isWide
                                                        ? 12
                                                        : 8,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Image.asset(
                                              'logo/kabupaten-cianjur.png',
                                              width: logoSize,
                                              height: logoSize,
                                              fit: BoxFit.contain,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Icon(
                                                    Icons
                                                        .account_balance_rounded,
                                                    size: logoSize * 0.75,
                                                    color: colorScheme.primary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isTall ? 32 : 20),
                                    FadeTransition(
                                      opacity: _textFadeAnimation,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Cek PBB Cianjur',
                                            textAlign: TextAlign.center,
                                            style:
                                                (isWide
                                                        ? theme
                                                              .textTheme
                                                              .headlineLarge
                                                        : theme
                                                              .textTheme
                                                              .headlineMedium)
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          colorScheme.onSurface,
                                                      letterSpacing: 0.5,
                                                    ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            'Layanan Informasi & Pemantauan PBB-P2',
                                            textAlign: TextAlign.center,
                                            style:
                                                (isWide
                                                        ? theme
                                                              .textTheme
                                                              .titleMedium
                                                        : theme
                                                              .textTheme
                                                              .bodyMedium)
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isWide ? 18 : 14,
                                              vertical: isWide ? 8 : 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: 0.65),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              border: Border.all(
                                                color: colorScheme.primary
                                                    .withValues(alpha: 0.35),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.location_on_outlined,
                                                  size: isWide ? 16 : 14,
                                                  color: colorScheme.primary,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Kabupaten Cianjur',
                                                  style: TextStyle(
                                                    fontSize: isWide ? 13 : 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Bagian Bawah: Indikator & Footer Resmi
                              FadeTransition(
                                opacity: _textFadeAnimation,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 580,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: isWide ? 64 : 48,
                                        child: LinearProgressIndicator(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          backgroundColor: colorScheme
                                              .surfaceContainerHighest,
                                          color: colorScheme.primary,
                                          minHeight: isWide ? 4 : 3,
                                        ),
                                      ),
                                      SizedBox(height: isTall ? 24 : 16),
                                      Text(
                                        'Badan Pendapatan Daerah Kabupaten Cianjur',
                                        textAlign: TextAlign.center,
                                        style:
                                            (isWide
                                                    ? theme.textTheme.titleSmall
                                                    : theme
                                                          .textTheme
                                                          .labelMedium)
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _version.isNotEmpty
                                            ? _version
                                            : 'Versi 2.0.0',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.outline,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
