import 'package:flutter/material.dart';

/// Linear Interpolation persis seperti formula `Mathf.Lerp(a, b, t)` di Unity Engine:
///
/// $$\text{result} = a + (b - a) \times t$$
///
/// Mentransisikan nilai dari [a] ke [b] secara kontinu berdasarkan parameter [t]
/// yang ternormalisasi (0.0 s.d 1.0).
double unityLerp(double a, double b, double t) {
  return a + (b - a) * t;
}

/// Widget angka atau nilai nominal yang bertransisi halus menggunakan formula `Mathf.Lerp` ala Unity.
///
/// Setiap kali [value] diperbarui, angka akan "menggelinding" secara halus dari nilai sebelumnya
/// ke nilai target baru.
class LerpAnimatedCounter extends StatefulWidget {
  final num value;
  final Duration duration;
  final Curve curve;
  final TextStyle? style;
  final String Function(num value)? formatter;
  final TextAlign? textAlign;

  const LerpAnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 450),
    this.curve = Curves.easeOutCubic,
    this.style,
    this.formatter,
    this.textAlign,
  });

  @override
  State<LerpAnimatedCounter> createState() => _LerpAnimatedCounterState();
}

class _LerpAnimatedCounterState extends State<LerpAnimatedCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  late double _startValue;
  late double _targetValue;
  late double _displayValue;

  @override
  void initState() {
    super.initState();
    _startValue = 0.0;
    _targetValue = widget.value.toDouble();
    _displayValue = _targetValue;

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _controller.addListener(_onTick);

    // Animasi roll-up saat pertama kali dirender jika nilai > 0
    if (_targetValue > 0) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(LerpAnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _startValue = _displayValue;
      _targetValue = widget.value.toDouble();
      _controller.duration = widget.duration;
      _controller.forward(from: 0.0);
    }
  }

  void _onTick() {
    setState(() {
      _displayValue = unityLerp(_startValue, _targetValue, _curved.value);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.formatter != null
        ? widget.formatter!(_displayValue)
        : _displayValue.round().toString();

    return Text(
      text,
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}

/// Linear Progress Indicator yang nilainya bertransisi menggunakan formula `Mathf.Lerp` ala Unity.
/// Cocok untuk bar XP / progres batch yang bergerak mulus.
class LerpAnimatedProgress extends StatefulWidget {
  final double value; // 0.0 sampai 1.0
  final Duration duration;
  final Curve curve;
  final Color? color;
  final Color? backgroundColor;
  final double minHeight;
  final BorderRadiusGeometry? borderRadius;

  const LerpAnimatedProgress({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 380),
    this.curve = Curves.easeOutCubic,
    this.color,
    this.backgroundColor,
    this.minHeight = 4.0,
    this.borderRadius,
  });

  @override
  State<LerpAnimatedProgress> createState() => _LerpAnimatedProgressState();
}

class _LerpAnimatedProgressState extends State<LerpAnimatedProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  late double _startValue;
  late double _targetValue;
  late double _displayValue;

  @override
  void initState() {
    super.initState();
    _startValue = 0.0;
    _targetValue = widget.value.clamp(0.0, 1.0);
    _displayValue = _targetValue;

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _controller.addListener(_onTick);

    if (_targetValue > 0) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(LerpAnimatedProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _startValue = _displayValue;
      _targetValue = widget.value.clamp(0.0, 1.0);
      _controller.duration = widget.duration;
      _controller.forward(from: 0.0);
    }
  }

  void _onTick() {
    setState(() {
      _displayValue = unityLerp(_startValue, _targetValue, _curved.value);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: _displayValue.clamp(0.0, 1.0),
        color: widget.color,
        backgroundColor: widget.backgroundColor,
        minHeight: widget.minHeight,
      ),
    );
  }
}

/// Widget interaktif bergaya tombol game Unity yang memantul dan mengecil lembut
/// (bounce punch scale) saat ditekan dengan `Mathf.Lerp`.
class LerpPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale; // Default 0.96 (squash 4% saat ditekan)
  final Duration duration;

  const LerpPressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<LerpPressable> createState() => _LerpPressableState();
}

class _LerpPressableState extends State<LerpPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (widget.onTap != null) {
      _controller.forward();
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _curved,
          builder: (context, child) {
            // Unity: Mathf.Lerp(1.0, pressedScale, t)
            final scale = unityLerp(1.0, widget.pressedScale, _curved.value);
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Banner indikator aktivitas (memuat data, menyimpan perubahan, mengekspor, sinkronisasi)
/// dengan transisi masuk/keluar yang mulus (`AnimatedSize` + `AnimatedSwitcher`).
class SmoothActivityBanner extends StatelessWidget {
  final bool isActive;
  final String message;
  final String? subtitle;
  final IconData icon;
  final double? progress;
  final Color? accentColor;
  final EdgeInsetsGeometry margin;

  const SmoothActivityBanner({
    super.key,
    required this.isActive,
    required this.message,
    this.subtitle,
    this.icon = Icons.sync_rounded,
    this.progress,
    this.accentColor,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accentColor ?? scheme.primary;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, -0.08),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: offsetAnimation,
              child: child,
            ),
          );
        },
        child: !isActive
            ? const SizedBox.shrink(key: ValueKey('inactive-banner'))
            : Container(
                key: ValueKey('active-banner-$message'),
                margin: margin,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 2.4,
                                  color: color,
                                  backgroundColor:
                                      color.withValues(alpha: 0.18),
                                ),
                              ),
                              Icon(icon, size: 13, color: color),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  message,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                if (subtitle != null &&
                                    subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (progress != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Kartu pemuatan data penuh dengan transisi masuk yang halus (scale + fade).
class SmoothLoadingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badgeText;
  final IconData icon;
  final Color? accentColor;
  final bool isDarkCanvas;

  const SmoothLoadingCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.badgeText = 'Memproses data...',
    this.icon = Icons.sync_rounded,
    this.accentColor,
    this.isDarkCanvas = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = accentColor ?? (isDarkCanvas ? Colors.tealAccent : colorScheme.primary);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        final opacity = ((scale - 0.94) / 0.06).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 2,
              color: isDarkCanvas ? const Color(0xFF282828) : null,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDarkCanvas
                      ? Colors.white12
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 68,
                          height: 68,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.5,
                            valueColor: AlwaysStoppedAnimation<Color>(primary),
                            backgroundColor: primary.withValues(alpha: 0.15),
                          ),
                        ),
                        Icon(
                          icon,
                          size: 30,
                          color: primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDarkCanvas ? Colors.white : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDarkCanvas
                            ? Colors.white70
                            : (theme.textTheme.bodySmall?.color ??
                                Colors.grey[600]),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDarkCanvas
                                    ? Colors.white
                                    : colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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
  }
}

