import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui/app_design_system.dart';

/// Linear Interpolation persis seperti formula `Mathf.Lerp(a, b, t)` di Unity Engine:
///
/// $$\text{result} = a + (b - a) \times t$$
///
/// Mentransisikan nilai dari [a] ke [b] secara kontinu berdasarkan parameter [t]
/// yang ternormalisasi (0.0 s.d 1.0).
double unityLerp(double a, double b, double t) {
  return a + (b - a) * t;
}

/// Inverse Linear Interpolation persis seperti `Mathf.InverseLerp(a, b, value)` di Unity Engine:
/// Menghasilkan nilai normalisasi $t \in [0.0, 1.0]$ dari posisi [value] di antara [a] dan [b].
double unityInverseLerp(double a, double b, double value) {
  if ((b - a).abs() < 1e-9) return 0.0;
  return ((value - a) / (b - a)).clamp(0.0, 1.0);
}

/// Hermite SmoothStep Interpolation persis seperti `Mathf.SmoothStep(from, to, t)` di Unity Engine:
///
/// $$t' = t^2 (3 - 2t)$$
///
/// Memberikan percepatan lembut di awal dan perlambatan halus di akhir tanpa patahan kecepatan.
double unitySmoothStep(double from, double to, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final smoothed = clamped * clamped * (3.0 - 2.0 * clamped);
  return unityLerp(from, to, smoothed);
}

/// Critically-Damped Spring Smoothing persis seperti `Mathf.SmoothDamp` di Unity Engine.
///
/// Mengembalikan pasangan `(value, velocity)` baru untuk langkah waktu `deltaTime` (detik).
({double value, double velocity}) unitySmoothDamp({
  required double current,
  required double target,
  required double currentVelocity,
  required double smoothTime,
  required double deltaTime,
  double maxSpeed = double.infinity,
}) {
  final effectiveSmoothTime = math.max(0.0001, smoothTime);
  final omega = 2.0 / effectiveSmoothTime;
  final x = omega * deltaTime;
  final exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x);

  var change = current - target;
  final originalTo = target;

  final maxChange = maxSpeed * effectiveSmoothTime;
  change = change.clamp(-maxChange, maxChange);
  final adjustedTarget = current - change;

  final temp = (currentVelocity + omega * change) * deltaTime;
  var newVelocity = (currentVelocity - omega * temp) * exp;
  var output = adjustedTarget + (change + temp) * exp;

  if ((originalTo - current > 0.0) == (output > originalTo)) {
    output = originalTo;
    newVelocity = deltaTime > 0 ? (output - originalTo) / deltaTime : 0.0;
  }

  return (value: output, velocity: newVelocity);
}

/// Kurva animasi kustom bergaya `AnimationCurve` di Unity Engine.
/// Mendukung mode Hermite SmoothStep dengan opsi overshoot tipis yang terkontrol.
class UnityAnimationCurve extends Curve {
  final double overshoot;

  const UnityAnimationCurve({this.overshoot = 0.0});

  @override
  double transformInternal(double t) {
    final base = t * t * (3.0 - 2.0 * t);
    if (overshoot == 0.0) return base;
    return base + math.sin(t * math.pi) * overshoot * (1.0 - t);
  }
}

/// Widget angka atau nilai nominal yang bertransisi halus menggunakan formula `Mathf.Lerp` ala Unity.
///
/// Setiap kali [value] diperbarui, angka akan "menggelinding" secara halus dari nilai sebelumnya
/// ke nilai target baru. Menghormati preferensi Reduced Motion OS secara otomatis.
class LerpAnimatedCounter extends StatefulWidget {
  final num value;
  final Duration duration;
  final Curve curve;
  final TextStyle? style;
  final String Function(num value)? formatter;
  final TextAlign? textAlign;
  final bool resetToZeroOnUpdate;

  const LerpAnimatedCounter({
    super.key,
    required this.value,
    this.duration = AppMotion.complex,
    this.curve = AppMotion.enterCurve,
    this.style,
    this.formatter,
    this.textAlign,
    this.resetToZeroOnUpdate = false,
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

    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _controller.addListener(_onTick);

    // Animasi roll-up saat pertama kali dirender jika nilai > 0
    if (_targetValue > 0) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.isReducedMotion(context) && _controller.isAnimating) {
      _controller.stop();
      _displayValue = _targetValue;
    }
  }

  @override
  void didUpdateWidget(LerpAnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _startValue = widget.resetToZeroOnUpdate ? 0.0 : _displayValue;
      _targetValue = widget.value.toDouble();
      if (AppMotion.isReducedMotion(context)) {
        _controller.stop();
        _displayValue = _targetValue;
      } else {
        if (widget.resetToZeroOnUpdate) {
          _displayValue = 0.0;
        }
        _controller.duration = widget.duration;
        _controller.forward(from: 0.0);
      }
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
    final effectiveValue = AppMotion.isReducedMotion(context)
        ? _targetValue
        : _displayValue;
    final text = widget.formatter != null
        ? widget.formatter!(effectiveValue)
        : effectiveValue.round().toString();

    return Text(text, style: widget.style, textAlign: widget.textAlign);
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
    this.duration = AppMotion.complex,
    this.curve = AppMotion.enterCurve,
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

    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _controller.addListener(_onTick);

    if (_targetValue > 0) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.isReducedMotion(context) && _controller.isAnimating) {
      _controller.stop();
      _displayValue = _targetValue;
    }
  }

  @override
  void didUpdateWidget(LerpAnimatedProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _startValue = _displayValue;
      _targetValue = widget.value.clamp(0.0, 1.0);
      if (AppMotion.isReducedMotion(context)) {
        _controller.stop();
        _displayValue = _targetValue;
      } else {
        _controller.duration = widget.duration;
        _controller.forward(from: 0.0);
      }
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
    final effectiveValue = AppMotion.isReducedMotion(context)
        ? _targetValue
        : _displayValue;
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: effectiveValue.clamp(0.0, 1.0),
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
  final double pressedScale; // Default 0.97 (squash 3% saat ditekan)
  final Duration duration;

  const LerpPressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.duration = AppMotion.micro,
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
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _controller, curve: AppMotion.enterCurve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (widget.onTap != null && !AppMotion.isReducedMotion(context)) {
      _controller.forward();
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    if (widget.onTap != null && !AppMotion.isReducedMotion(context)) {
      _controller.reverse();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (widget.onTap != null && !AppMotion.isReducedMotion(context)) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      );
    }
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
            return Transform.scale(scale: scale, child: child);
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
    final switchDuration = AppMotion.resolve(context, AppMotion.component);

    return AppAnimatedSize(
      duration: AppMotion.component,
      curve: AppMotion.enterCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: switchDuration,
        switchInCurve: AppMotion.enterCurve,
        switchOutCurve: AppMotion.exitCurve,
        transitionBuilder: (child, animation) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, -0.08),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offsetAnimation, child: child),
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
                  border: Border.all(color: color.withValues(alpha: 0.3)),
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
                                  backgroundColor: color.withValues(
                                    alpha: 0.18,
                                  ),
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
    final primary =
        accentColor ?? (isDarkCanvas ? Colors.tealAccent : colorScheme.primary);
    final reducedMotion = AppMotion.isReducedMotion(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reducedMotion ? 1.0 : 0.94, end: 1.0),
      duration: AppMotion.resolve(context, AppMotion.dialog),
      curve: AppMotion.enterCurve,
      builder: (context, scale, child) {
        final opacity = ((scale - 0.94) / 0.06).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
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
                        Icon(icon, size: 30, color: primary),
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

/// Widget efek memantul elastis bergaya `DOPunchScale` (DOTween / Unity).
///
/// Saat [trigger] bertambah atau widget diketuk (bila [punchOnTap] aktif),
/// skala widget berdenyut halus mengikuti gelombang sinus teredam:
/// $$\text{scale}(t) = 1.0 + \text{punch} \cdot (1 - t) \cdot \sin(2\pi \cdot \text{vibrato} \cdot t)$$
class LerpPunchScale extends StatefulWidget {
  final Widget child;
  final int trigger;
  final double punch;
  final int vibrato;
  final Duration duration;
  final bool punchOnTap;
  final VoidCallback? onTap;

  const LerpPunchScale({
    super.key,
    required this.child,
    this.trigger = 0,
    this.punch = 0.06,
    this.vibrato = 2,
    this.duration = AppMotion.dialog,
    this.punchOnTap = false,
    this.onTap,
  });

  @override
  State<LerpPunchScale> createState() => _LerpPunchScaleState();
}

class _LerpPunchScaleState extends State<LerpPunchScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didUpdateWidget(LerpPunchScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger &&
        !AppMotion.isReducedMotion(context)) {
      _controller.duration = widget.duration;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.punchOnTap && !AppMotion.isReducedMotion(context)) {
      _controller.forward(from: 0.0);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (t <= 0.0 || t >= 1.0 || AppMotion.isReducedMotion(context)) {
          return child!;
        }
        final damping = 1.0 - t;
        final wave = math.sin(t * math.pi * 2 * widget.vibrato);
        final scale = 1.0 + widget.punch * damping * wave;
        return Transform.scale(scale: scale, child: child);
      },
    );

    if (widget.punchOnTap || widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: content,
      );
    }
    return content;
  }
}

/// Widget getaran horizontal halus bergaya `DOShakePosition` (DOTween / Unity).
///
/// Digunakan untuk memberi umpan balik visual yang lembut ketika validasi input
/// gagal tanpa mengaburkan fokus pengguna. Setiap kali [shakeTrigger] bertambah,
/// widget berosilasi ke kiri/kanan dengan amplitudo yang meluruh ke nol.
class LerpShakePosition extends StatefulWidget {
  final Widget child;
  final int shakeTrigger;
  final double strength;
  final int vibrato;
  final Duration duration;

  const LerpShakePosition({
    super.key,
    required this.child,
    required this.shakeTrigger,
    this.strength = 6.0,
    this.vibrato = 3,
    this.duration = AppMotion.dialog,
  });

  @override
  State<LerpShakePosition> createState() => _LerpShakePositionState();
}

class _LerpShakePositionState extends State<LerpShakePosition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didUpdateWidget(LerpShakePosition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shakeTrigger != widget.shakeTrigger &&
        widget.shakeTrigger > 0 &&
        !AppMotion.isReducedMotion(context)) {
      _controller.duration = widget.duration;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (t <= 0.0 || t >= 1.0 || AppMotion.isReducedMotion(context)) {
          return child!;
        }
        final damping = 1.0 - t;
        final dx =
            math.sin(t * math.pi * 2 * widget.vibrato) *
            widget.strength *
            damping;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Kemunculan berurutan (staggered sequence) bergaya `DOTween.Sequence` di Unity.
///
/// Mengatur transisi fade + slide ringan untuk daftar kartu/komponen secara
/// berurutan menggunakan satu `AnimationController` terpusat yang hemat memori.
class SequenceStaggerReveal extends StatefulWidget {
  final List<Widget> children;
  final Duration totalDuration;
  final double slideOffsetY;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  const SequenceStaggerReveal({
    super.key,
    required this.children,
    this.totalDuration = AppMotion.complex,
    this.slideOffsetY = 10.0,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
  });

  @override
  State<SequenceStaggerReveal> createState() => _SequenceStaggerRevealState();
}

class _SequenceStaggerRevealState extends State<SequenceStaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.totalDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty || AppMotion.isReducedMotion(context)) {
      return Column(
        mainAxisSize: widget.mainAxisSize,
        crossAxisAlignment: widget.crossAxisAlignment,
        children: widget.children,
      );
    }

    final count = widget.children.length;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: widget.mainAxisSize,
          crossAxisAlignment: widget.crossAxisAlignment,
          children: List<Widget>.generate(count, (index) {
            final start = (index / count) * 0.5;
            final end = (start + 0.5).clamp(0.0, 1.0);
            final localT = Interval(
              start,
              end,
              curve: AppMotion.enterCurve,
            ).transform(_controller.value);
            return Opacity(
              opacity: localT,
              child: Transform.translate(
                offset: Offset(0, unityLerp(widget.slideOffsetY, 0.0, localT)),
                child: widget.children[index],
              ),
            );
          }),
        );
      },
    );
  }
}

