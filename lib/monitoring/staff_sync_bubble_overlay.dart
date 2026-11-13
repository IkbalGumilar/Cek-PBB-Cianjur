import 'dart:async';

import 'package:flutter/material.dart';

import '../batch_notification_service.dart';
import '../staff_portal_client.dart';
import '../theme_controller.dart';
import 'monitoring_wilayah_screen.dart';
import 'staff_dhkp_sync_dialog.dart';
import 'staff_dhkp_sync_manager.dart';

/// Floating Bubble Chat (seperti chat head) yang melayang di atas layar
/// saat proses sinkronisasi DHKP disembunyikan oleh pengguna.
///
/// Pengguna dapat menggeser (drag) bubble ke posisi mana pun di tepi layar,
/// dan mengetuknya (tap) untuk memunculkan kembali dialog/lembaran sinkronisasi.
class StaffSyncBubbleOverlay extends StatefulWidget {
  const StaffSyncBubbleOverlay({super.key});

  @override
  State<StaffSyncBubbleOverlay> createState() => _StaffSyncBubbleOverlayState();
}

class _StaffSyncBubbleOverlayState extends State<StaffSyncBubbleOverlay>
    with TickerProviderStateMixin {
  Offset? _offset;
  late AnimationController _spinController;
  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  Timer? _autoDismissTimer;

  static const double _bubbleSize = 58.0;
  static const double _badgeHeight = 20.0;
  static const double _totalHeight = _bubbleSize + _badgeHeight + 4.0;
  static const double _margin = 12.0;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  void _updateSpinAnimation(StaffDhkpSyncManager mgr) {
    final shouldSpin =
        mgr.shouldShowBubble && !mgr.isPaused && !mgr.isCompleted;
    if (shouldSpin) {
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else {
      if (_spinController.isAnimating) {
        _spinController.stop();
      }
    }
  }

  void _checkAutoDismiss(StaffDhkpSyncManager mgr) {
    if (mgr.isCompleted && mgr.shouldShowBubble) {
      if (_autoDismissTimer == null || !_autoDismissTimer!.isActive) {
        _autoDismissTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && StaffDhkpSyncManager.instance.isCompleted) {
            StaffDhkpSyncManager.instance.dismiss();
          }
        });
      }
    } else {
      _autoDismissTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _spinController.dispose();
    _snapController.dispose();
    super.dispose();
  }

  Offset _clampOffset(Offset raw, Size size, EdgeInsets padding) {
    final minX = _margin;
    final maxX = (size.width - _bubbleSize - _margin).clamp(
      minX,
      double.infinity,
    );
    final minY = padding.top + _margin;
    final maxY = (size.height - padding.bottom - _totalHeight - _margin).clamp(
      minY,
      double.infinity,
    );

    return Offset(raw.dx.clamp(minX, maxX), raw.dy.clamp(minY, maxY));
  }

  void _snapToEdge(Size size, EdgeInsets padding) {
    if (_offset == null) return;
    final minX = _margin;
    final maxX = (size.width - _bubbleSize - _margin).clamp(
      minX,
      double.infinity,
    );

    final targetX = (_offset!.dx < size.width / 2) ? minX : maxX;
    final targetOffset = Offset(targetX, _offset!.dy);

    _snapAnimation =
        Tween<Offset>(begin: _offset, end: targetOffset).animate(
          CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
        )..addListener(() {
          if (mounted) {
            setState(() => _offset = _snapAnimation!.value);
          }
        });

    _snapController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffDhkpSyncManager.instance,
      builder: (context, _) {
        final mgr = StaffDhkpSyncManager.instance;
        _updateSpinAnimation(mgr);
        _checkAutoDismiss(mgr);
        if (!mgr.shouldShowBubble) {
          return const SizedBox.shrink();
        }

        final size = MediaQuery.of(context).size;
        final padding = MediaQuery.of(context).padding;

        // Inisialisasi posisi awal (kanan bawah, di atas bottom bar)
        if (_offset == null) {
          final initX = size.width - _bubbleSize - _margin;
          final initY = size.height - padding.bottom - _totalHeight - 70.0;
          _offset = _clampOffset(Offset(initX, initY), size, padding);
        } else {
          _offset = _clampOffset(_offset!, size, padding);
        }

        return Positioned(
          left: _offset!.dx,
          top: _offset!.dy,
          child: _buildBubbleWidget(context, mgr, size, padding),
        );
      },
    );
  }

  Widget _buildBubbleWidget(
    BuildContext context,
    StaffDhkpSyncManager mgr,
    Size size,
    EdgeInsets padding,
  ) {
    final isPaused = mgr.isPaused;
    final isCompleted = mgr.isCompleted;
    final progress = mgr.progress;
    final ratio = progress?.ratio ?? 0.0;
    final percent = (ratio * 100).toInt();

    // Palet warna status
    final Color bubbleColor = isCompleted
        ? const Color(0xFF2E7D32)
        : (isPaused ? const Color(0xFFE65100) : const Color(0xFF00796B));
    final Color progressColor = isCompleted
        ? Colors.white
        : (isPaused ? Colors.amberAccent : Colors.tealAccent);

    return GestureDetector(
      onPanStart: (_) {
        _snapController.stop();
      },
      onPanUpdate: (details) {
        setState(() {
          _offset = _clampOffset(_offset! + details.delta, size, padding);
        });
      },
      onPanEnd: (_) {
        _snapToEdge(size, padding);
      },
      onTap: () {
        _autoDismissTimer?.cancel();
        final ctx = rootNavigatorKey.currentContext ?? context;
        if (mgr.isCompleted && mgr.outcome != null) {
          final outcome = mgr.outcome!;
          mgr.dismiss();
          if (!MonitoringWilayahScreen.isCurrentlyOpen) {
            final nav = rootNavigatorKey.currentState;
            if (nav != null) {
              nav.push(
                MaterialPageRoute(
                  settings: const RouteSettings(
                    name: 'MonitoringWilayahScreen',
                  ),
                  builder: (_) => MonitoringWilayahScreen(
                    client: mgr.client ?? StaffPortalClient(),
                    themeController: ThemeController.current,
                    initialReportOutcome: outcome,
                  ),
                ),
              );
              return;
            }
          }
          showStaffDhkpSyncReportDialog(ctx, outcome);
        } else {
          mgr.openSheet(ctx);
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: _bubbleSize,
          height: _totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // 1. Avatar Utama Berbentuk Lingkaran
              Container(
                width: _bubbleSize,
                height: _bubbleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bubbleColor,
                  boxShadow: [
                    BoxShadow(
                      color: bubbleColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Cincin Progres Melingkar
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: CircularProgressIndicator(
                          value: isCompleted ? 1.0 : (ratio > 0 ? ratio : null),
                          strokeWidth: 3.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progressColor,
                          ),
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),

                    // Ikon Status di Tengah
                    if (isCompleted)
                      const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 28,
                      )
                    else if (isPaused)
                      const Icon(
                        Icons.pause_rounded,
                        color: Colors.white,
                        size: 26,
                      )
                    else
                      RotationTransition(
                        turns: _spinController,
                        child: const Icon(
                          Icons.sync_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                  ],
                ),
              ),

              // 2. Chip Badge Keterangan Persentase / Status di Bawah
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    isCompleted
                        ? 'Selesai'
                        : (isPaused
                              ? 'Jeda'
                              : (percent >= 100 ? '99%' : '$percent%')),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),

              // 3. Tombol Tutup (X) Kecil Saat Selesai
              if (isCompleted)
                Positioned(
                  top: -2,
                  right: -2,
                  child: GestureDetector(
                    onTap: () => mgr.dismiss(),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
