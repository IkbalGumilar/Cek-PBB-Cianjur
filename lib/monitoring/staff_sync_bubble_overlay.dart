import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../batch_check_manager.dart';
import '../batch_notification_service.dart';
import 'staff_dhkp_sync_manager.dart';

/// Floating Bubble Overlay terpadu (seperti chat head) yang melayang di atas
/// layar saat proses Sinkronisasi DHKP atau Cek Massal disembunyikan oleh
/// pengguna agar aplikasi tetap dapat dipakai sambil proses berjalan di latar
/// belakang.
class StaffSyncBubbleOverlay extends StatelessWidget {
  const StaffSyncBubbleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        StaffDhkpSyncManager.instance,
        BatchCheckManager.instance,
      ]),
      builder: (context, _) {
        final syncMgr = StaffDhkpSyncManager.instance;
        final batchMgr = BatchCheckManager.instance;
        final showSync = syncMgr.shouldShowBubble;
        final showBatch = batchMgr.shouldShowBubble;

        if (!showSync && !showBatch) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            if (showSync)
              _DraggableTaskBubble(
                key: const ValueKey('staff_sync_floating_bubble'),
                initialBottomOffset: 70.0,
                isPaused: syncMgr.isPaused,
                isCompleted: syncMgr.isCompleted,
                ratio: syncMgr.progress?.ratio ?? 0.0,
                activeColor: const Color(0xFF00796B),
                activeProgressColor: Colors.tealAccent,
                activeIcon: Icons.sync_rounded,
                onTap: () {
                  if (syncMgr.isCompleted && syncMgr.outcome != null) {
                    BatchNotificationService.instance.openDhkpWithSyncReport(
                      syncMgr.outcome,
                    );
                  } else {
                    final ctx = rootNavigatorKey.currentContext ?? context;
                    syncMgr.openSheet(ctx);
                  }
                },
                onDismiss: () => syncMgr.dismiss(),
              ),
            if (showBatch)
              _DraggableTaskBubble(
                key: const ValueKey('batch_check_floating_bubble'),
                initialBottomOffset: showSync ? 166.0 : 70.0,
                isPaused: batchMgr.isPaused,
                isCompleted: batchMgr.isCompleted,
                ratio: batchMgr.progressRatio,
                activeColor: const Color(0xFF1565C0),
                activeProgressColor: Colors.lightBlueAccent,
                activeIcon: Icons.fact_check_rounded,
                onTap: () {
                  if (batchMgr.isCompleted) {
                    BatchNotificationService.instance.openDhkpWithBatchResult(
                      batchMgr.records,
                    );
                  } else {
                    BatchNotificationService.instance.openActiveBatchCheck();
                  }
                },
                onDismiss: () => batchMgr.dismiss(),
              ),
          ],
        );
      },
    );
  }
}

/// Widget gelembung mengambang tunggal yang dapat digeser (drag) & menempel ke
/// tepi layar, dipakai bersama oleh Sinkronisasi DHKP dan Cek Massal.
class _DraggableTaskBubble extends StatefulWidget {
  final double initialBottomOffset;
  final bool isPaused;
  final bool isCompleted;
  final double ratio;
  final Color activeColor;
  final Color activeProgressColor;
  final IconData activeIcon;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _DraggableTaskBubble({
    super.key,
    required this.initialBottomOffset,
    required this.isPaused,
    required this.isCompleted,
    required this.ratio,
    required this.activeColor,
    required this.activeProgressColor,
    required this.activeIcon,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_DraggableTaskBubble> createState() => _DraggableTaskBubbleState();
}

class _DraggableTaskBubbleState extends State<_DraggableTaskBubble>
    with TickerProviderStateMixin {
  Offset? _offset;
  late final AnimationController _spinController;
  late final AnimationController _snapController;
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
    _syncLifecycleEffects();
  }

  @override
  void didUpdateWidget(covariant _DraggableTaskBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLifecycleEffects();
  }

  void _syncLifecycleEffects() {
    final shouldSpin = !widget.isPaused && !widget.isCompleted;
    if (shouldSpin) {
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else if (_spinController.isAnimating) {
      _spinController.stop();
    }

    if (widget.isCompleted) {
      if (_autoDismissTimer == null || !_autoDismissTimer!.isActive) {
        _autoDismissTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && widget.isCompleted) {
            widget.onDismiss();
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
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    if (_offset == null) {
      final initX = size.width - _bubbleSize - _margin;
      final initY =
          size.height - padding.bottom - _totalHeight - widget.initialBottomOffset;
      _offset = _clampOffset(Offset(initX, initY), size, padding);
    } else {
      _offset = _clampOffset(_offset!, size, padding);
    }

    final percent = (widget.ratio * 100).toInt();
    final Color bubbleColor = widget.isCompleted
        ? const Color(0xFF2E7D32)
        : (widget.isPaused ? const Color(0xFFE65100) : widget.activeColor);
    final Color progressColor = widget.isCompleted
        ? Colors.white
        : (widget.isPaused ? Colors.amberAccent : widget.activeProgressColor);

    return Positioned(
      left: _offset!.dx,
      top: _offset!.dy,
      child: GestureDetector(
        onPanStart: (_) => _snapController.stop(),
        onPanUpdate: (details) {
          setState(() {
            _offset = _clampOffset(_offset! + details.delta, size, padding);
          });
        },
        onPanEnd: (_) => _snapToEdge(size, padding),
        onTap: () {
          _autoDismissTimer?.cancel();
          widget.onTap();
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
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(3.0),
                          child: CircularProgressIndicator(
                            value: widget.isCompleted
                                ? 1.0
                                : (widget.ratio > 0 ? widget.ratio : null),
                            strokeWidth: 3.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progressColor,
                            ),
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      if (widget.isCompleted)
                        const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 28,
                        )
                      else if (widget.isPaused)
                        const Icon(
                          Icons.pause_rounded,
                          color: Colors.white,
                          size: 26,
                        )
                      else if (widget.activeIcon == Icons.sync_rounded)
                        RotationTransition(
                          turns: _spinController,
                          child: Icon(
                            widget.activeIcon,
                            color: Colors.white,
                            size: 26,
                          ),
                        )
                      else
                        Icon(
                          widget.activeIcon,
                          color: Colors.white,
                          size: 25,
                        ),
                    ],
                  ),
                ),
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
                      widget.isCompleted
                          ? 'Selesai'
                          : (widget.isPaused
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
                if (widget.isCompleted)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: widget.onDismiss,
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
      ),
    );
  }
}
