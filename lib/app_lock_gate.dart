import 'package:flutter/material.dart';

import 'app_lock_screen.dart';
import 'app_security_service.dart';

/// Gerbang Kunci Aplikasi (App Lock Gate).
/// Membungkus UI utama aplikasi dan memantau siklus hidup aplikasi (Lifecycle).
/// Jika kunci aktif dan waktu jeda terlampaui, menampilkan [AppLockScreen] secara otomatis.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final AppSecurityService _securityService = AppSecurityService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cek status kunci saat pembukaan awal aplikasi (cold start)
    _securityService.onAppResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _securityService.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _securityService.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _securityService.isAppLockedNotifier,
      builder: (context, isLocked, child) {
        if (isLocked) {
          return AppLockScreen(
            onUnlocked: () => _securityService.unlock(),
          );
        }
        return widget.child;
      },
    );
  }
}
