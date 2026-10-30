import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock_gate.dart';
import 'blok_backup_scheduler.dart';
import 'blok_data_store.dart';
import 'connectivity_monitor.dart';
import 'desktop_accent_color_helper.dart';
import 'dhkp_widget_sync_service.dart';
import 'document_preview_screen.dart';
import 'dusun_data.dart';
import 'main_shell.dart';
import 'network_status_overlay.dart';
import 'batch_notification_service.dart';
import 'blok_batch_check_tracker.dart';
import 'incoming_file_service.dart';
import 'spreadsheet_viewer_screen.dart';
import 'theme_controller.dart';

Widget _buildExternalViewer(String filePath) {
  final file = File(filePath);
  final fileName = file.uri.pathSegments.isNotEmpty
      ? file.uri.pathSegments.last
      : 'dokumen.pdf';
  final lower = fileName.toLowerCase();

  final isPdf = lower.endsWith('.pdf');
  if (isPdf) {
    return DocumentPreviewScreen(
      pdfFile: file,
      fileName: fileName,
      isExternal: true,
    );
  }

  final isSpreadsheet = lower.endsWith('.xlsx') ||
      lower.endsWith('.xls') ||
      lower.endsWith('.csv');
  if (isSpreadsheet) {
    return SpreadsheetViewerScreen(
      file: file,
      isDkhp: false,
      fileName: fileName,
      isExternal: true,
    );
  }

  final isDkhp = lower.endsWith('.dkhp') ||
      lower.endsWith('.dhkp') ||
      lower.endsWith('.dat');
  if (isDkhp) {
    return SpreadsheetViewerScreen(
      file: file,
      isDkhp: true,
      fileName: fileName,
      isExternal: true,
    );
  }

  return DocumentPreviewScreen(
    pdfFile: file,
    fileName: fileName,
    isExternal: true,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? initialIncomingFile;
  if (Platform.isAndroid) {
    try {
      const incomingChannel =
          MethodChannel('id.cianjur.cekpbb.cek_pbb_app/incoming_file');
      initialIncomingFile =
          await incomingChannel.invokeMethod<String>('getInitialFile');
      debugPrint('main(): initialIncomingFile = $initialIncomingFile');
    } catch (e) {
      debugPrint('main(): getInitialFile error = $e');
    }
  }
  await DusunData.instance.init();
  unawaited(DhkpWidgetSyncService.syncFromDatabase());
  await BlokBatchCheckTracker.instance.init();
  await BatchNotificationService.instance.init();
  runApp(RestartWidget(
    child: CekPbbApp(initialExternalFilePath: initialIncomingFile),
  ));
}

/// Bungkus seluruh aplikasi supaya bisa "direstart" tanpa mematikan proses
/// native — dipakai saat Mode Operator baru diaktifkan (lihat
/// license_screen.dart), supaya semua state (WilayahKerjaStore,
/// OperatorModeStore, dst) dibaca ulang dari awal seolah aplikasi baru
/// dibuka. Mengganti [_key] membuang seluruh subtree lama termasuk state-nya.
class RestartWidget extends StatefulWidget {
  final Widget child;

  const RestartWidget({super.key, required this.child});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void _restart() {
    setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

class CekPbbApp extends StatefulWidget {
  final String? initialExternalFilePath;

  const CekPbbApp({super.key, this.initialExternalFilePath});

  @override
  State<CekPbbApp> createState() => _CekPbbAppState();
}

class _CekPbbAppState extends State<CekPbbApp> with WidgetsBindingObserver {
  final _themeController = ThemeController();
  Color? _desktopAccentColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectivityMonitor.instance.start();
    unawaited(IncomingFileService.instance.init());
    unawaited(
      BlokBackupScheduler.instance.runIfNeeded(
        exportCsv: (fileName) =>
            BlokDataStore.instance.exportDkhp(fileName: fileName),
      ),
    );
    _detectDesktopAccent();
  }

  Future<void> _detectDesktopAccent() async {
    if (Platform.isLinux || Platform.isWindows) {
      final color = await DesktopAccentColorHelper.getDesktopAccentColor();
      if (color != null && mounted) {
        setState(() => _desktopAccentColor = color);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController.dispose();
    ConnectivityMonitor.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ConnectivityMonitor.instance.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      ConnectivityMonitor.instance.pause();
    }
  }

  ThemeMode _flutterThemeMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
      case AppThemeMode.amoled:
        return ThemeMode.dark;
    }
  }

  ColorScheme _buildCustomColorScheme({
    required Color accentColor,
    required Brightness brightness,
  }) {
    final base = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    );

    final isLight = brightness == Brightness.light;
    final luminance = accentColor.computeLuminance();
    final onPrimary = luminance > 0.5 ? Colors.black : Colors.white;

    return base.copyWith(
      primary: accentColor,
      onPrimary: onPrimary,
      primaryContainer: isLight
          ? Color.alphaBlend(accentColor.withValues(alpha: 0.22), Colors.white)
          : Color.alphaBlend(accentColor.withValues(alpha: 0.30), Colors.black),
      onPrimaryContainer: isLight ? Colors.black87 : Colors.white,
      surfaceTint: Colors.transparent,
    );
  }

  ThemeData _buildTheme({
    required ColorScheme colorScheme,
    bool isAmoled = false,
  }) {
    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: colorScheme.brightness,
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: colorScheme.brightness == Brightness.light
            ? colorScheme.surface
            : (isAmoled ? Colors.black : colorScheme.surface),
      ),
      cardTheme: const CardThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );

    if (isAmoled) {
      return baseTheme.copyWith(
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        cardColor: const Color(0xFF0A0A0A),
        colorScheme: colorScheme.copyWith(
          surface: Colors.black,
          surfaceTint: Colors.transparent,
        ),
      );
    }
    return baseTheme;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeState>(
      valueListenable: _themeController,
      builder: (context, themeState, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            ColorScheme lightColorScheme;
            ColorScheme darkColorScheme;

            final hasPlatformDynamic =
                lightDynamic != null && darkDynamic != null;
            final hasDesktopDynamic = _desktopAccentColor != null;

            if (themeState.useMaterialYou &&
                (hasPlatformDynamic || hasDesktopDynamic)) {
              if (hasPlatformDynamic) {
                lightColorScheme = lightDynamic.harmonized().copyWith(
                  surfaceTint: Colors.transparent,
                );
                darkColorScheme = darkDynamic.harmonized().copyWith(
                  surfaceTint: Colors.transparent,
                );
              } else {
                lightColorScheme = _buildCustomColorScheme(
                  accentColor: _desktopAccentColor!,
                  brightness: Brightness.light,
                );
                darkColorScheme = _buildCustomColorScheme(
                  accentColor: _desktopAccentColor!,
                  brightness: Brightness.dark,
                );
              }
            } else {
              lightColorScheme = _buildCustomColorScheme(
                accentColor: themeState.accentColor,
                brightness: Brightness.light,
              );
              darkColorScheme = _buildCustomColorScheme(
                accentColor: themeState.accentColor,
                brightness: Brightness.dark,
              );
            }

            final lightTheme = _buildTheme(colorScheme: lightColorScheme);
            final darkTheme = _buildTheme(
              colorScheme: darkColorScheme,
              isAmoled: themeState.mode == AppThemeMode.amoled,
            );

            return MaterialApp(
              navigatorKey: rootNavigatorKey,
              title: 'Cek PBB Cianjur',
              debugShowCheckedModeBanner: false,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: _flutterThemeMode(themeState.mode),
              onUnknownRoute: (settings) => MaterialPageRoute(
                builder: (_) => const SizedBox.shrink(),
              ),
              home: widget.initialExternalFilePath != null &&
                      widget.initialExternalFilePath!.isNotEmpty
                  ? _buildExternalViewer(widget.initialExternalFilePath!)
                  : MainShell(themeController: _themeController),
              builder: (context, child) {
                if (widget.initialExternalFilePath != null &&
                    widget.initialExternalFilePath!.isNotEmpty) {
                  return Stack(children: [?child, const NetworkStatusOverlay()]);
                }
                return AppLockGate(
                  child: Stack(children: [?child, const NetworkStatusOverlay()]),
                );
              },
            );
          },
        );
      },
    );
  }
}
