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
