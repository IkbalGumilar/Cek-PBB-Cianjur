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
  bool _isCheckingInitialLock = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cek status kunci saat pembukaan awal aplikasi (cold start) secara aman
    _checkInitialLock();
  }

  Future<void> _checkInitialLock() async {
    await _securityService.onColdStart();
    if (mounted) {
      setState(() {
        _isCheckingInitialLock = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PENTING: Hanya tanggapi 'paused' (saat aplikasi benar-benar ke background).
    // Abaikan 'inactive' karena event ini muncul saat prompt biometrik sistem,
    // Google Sign-In, atau notifikasi sistem sedang tampil di atas aplikasi.
    if (state == AppLifecycleState.paused) {
      _securityService.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _securityService.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingInitialLock) {
      // Tampilkan latar kosong aman selama status kunci async belum selesai dibaca
      // untuk mencegah layar utama muncul sekilas (frame flashing / UI flicker).
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: _securityService.isAppLockedNotifier,
          builder: (context, isLocked, child) {
            if (!isLocked) return const SizedBox.shrink();
            return AppLockScreen(
              onUnlocked: () => _securityService.unlock(),
            );
          },
        ),
      ],
    );
  }
}
