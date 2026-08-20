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
  runApp(const CekPbbApp());
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
