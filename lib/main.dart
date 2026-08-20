import 'dart:async';

import 'package:flutter/material.dart';

import 'app_header.dart';
import 'blok_backup_scheduler.dart';
import 'blok_data_store.dart';
import 'connectivity_monitor.dart';
import 'main_shell.dart';
import 'network_status_overlay.dart';
import 'theme_controller.dart';

void main() {
  runApp(const RestartWidget(child: CekPbbApp()));
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
  const CekPbbApp({super.key});

  @override
  State<CekPbbApp> createState() => _CekPbbAppState();
}

class _CekPbbAppState extends State<CekPbbApp> with WidgetsBindingObserver {
  final _themeController = ThemeController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectivityMonitor.instance.start();
    unawaited(BlokBackupScheduler.instance.runIfNeeded(
      exportCsv: (fileName) => BlokDataStore.instance.exportCsv(fileName: fileName),
    ));
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
      ConnectivityMonitor.instance.checkNow();
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

  ThemeData _amoledTheme() {
    final base = ThemeData(colorSchemeSeed: kHeaderGreen, useMaterial3: true, brightness: Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      cardColor: const Color(0xFF0A0A0A),
      colorScheme: base.colorScheme.copyWith(surface: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: _themeController,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Cek PBB Cianjur',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: kHeaderGreen, useMaterial3: true, brightness: Brightness.light),
          darkTheme: mode == AppThemeMode.amoled
              ? _amoledTheme()
              : ThemeData(colorSchemeSeed: kHeaderGreen, useMaterial3: true, brightness: Brightness.dark),
          themeMode: _flutterThemeMode(mode),
          home: MainShell(themeController: _themeController),
          builder: (context, child) {
            return Stack(
              children: [
                ?child,
                const NetworkStatusOverlay(),
              ],
            );
          },
        );
      },
    );
  }
}
