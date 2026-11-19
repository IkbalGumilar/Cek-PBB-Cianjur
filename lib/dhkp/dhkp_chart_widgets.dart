import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../tagihan_result.dart' show formatRupiah;
import '../ui/app_design_system.dart';
import '../unity_lerp_widgets.dart' show UnityAnimationCurve, unityLerp;
import 'dhkp_grafik_analytics.dart';

Widget _buildResponsiveKpiCards(
  BuildContext context,
  List<DhkpStatItem> items,
  bool isDark, {
  required double maxWidth,
  bool wrapInIntrinsicHeight = true,
}) {
  final isVeryNarrow = maxWidth < 500 && items.length == 3;
  if (isVeryNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildKpiStatCard(context, items[0], isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildKpiStatCard(context, items[1], isDark)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildKpiStatCard(
          context,
          items[2],
          isDark,
          horizontalWideLayout: true,
        ),
      ],
    );
  }

  final row = Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: _buildKpiStatCard(context, items[i], isDark)),
      ],
    ],
  );
  return wrapInIntrinsicHeight ? IntrinsicHeight(child: row) : row;
}

Widget buildDhkpStatRow(List<DhkpStatItem> items, bool isDark) {
  return LayoutBuilder(
    builder: (context, constraints) => _buildResponsiveKpiCards(
      context,
      items,
      isDark,
      maxWidth: constraints.maxWidth,
    ),
  );
}

/// Gabungan Kartu Semi-Circular Gauge Realisasi + 3 Kartu KPI Mini Sparkline
/// dengan tata letak adaptif untuk Desktop (>= 820dp), Tablet, dan Mobile (360dp).
Widget buildDhkpKpiWithGaugeOverview({
  required List<DhkpStatItem> items,
  required DhkpGaugeSummary gauge,
  required bool isDark,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width >= 820) {
        final gaugeW = width >= 1040 ? 286.0 : 256.0;
        const gap = 10.0;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: gaugeW,
                child: DhkpSemiCircularGaugeCard(
                  summary: gauge,
                  isDark: isDark,
                  compactHorizontal: false,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: _buildResponsiveKpiCards(
                  context,
                  items,
                  isDark,
                  maxWidth: width - gaugeW - gap,
                  wrapInIntrinsicHeight: false,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DhkpSemiCircularGaugeCard(
            summary: gauge,
            isDark: isDark,
            compactHorizontal: true,
          ),
          const SizedBox(height: 8),
          _buildResponsiveKpiCards(
            context,
            items,
            isDark,
            maxWidth: width,
          ),
        ],
      );
    },
  );
}

Widget _buildDeltaTrendPill(
  BuildContext context, {
  required String? deltaText,
  required bool isFavorable,
  required bool isDark,
  double fontSize = 9,
}) {
  if (deltaText == null || deltaText.isEmpty) {
    return const SizedBox.shrink();
  }
  final palette = AppSemanticColors.of(
    context,
    isFavorable ? AppBadgeTone.paid : AppBadgeTone.unpaid,
  );
  final isNegativeTxt = deltaText.startsWith('-');
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: palette.background.withValues(alpha: isDark ? 0.65 : 0.90),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: palette.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isNegativeTxt ? Icons.south_east_rounded : Icons.north_east_rounded,
          size: fontSize + 1,
          color: palette.foreground,
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            deltaText,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: palette.foreground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

const Duration _kGaugeSweepDuration = Duration(milliseconds: 1500);
const Duration _kSparklineAnimDuration = Duration(milliseconds: 1600);
const Duration _kKpiTransitionDuration = Duration(milliseconds: 1500);
const Curve _kSilkySmoothCurve = UnityAnimationCurve();

/// Base state untuk kartu/grafik DHKP yang selalu memulai animasi dari 0
/// dengan durasi terukur ([animationDuration]) dan kurva smooth-step saat data berubah.
abstract class _ZeroOriginAnimState<T extends StatefulWidget>
    extends State<T>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curved;
  bool _initialized = false;
  String? _lastSignature;

  Duration get animationDuration;
  String computeDataSignature();
  bool get forceComplete => false;

  (AnimationController, CurvedAnimation) _ensureInitialized() {
    var ctrl = _controller;
    var anim = _curved;
    if (ctrl == null || anim == null) {
      _lastSignature ??= computeDataSignature();
      ctrl ??= AnimationController(vsync: this, duration: animationDuration);
      anim ??= CurvedAnimation(parent: ctrl, curve: _kSilkySmoothCurve);
      _controller = ctrl;
      _curved = anim;
    }
    return (ctrl, anim);
  }

  AnimationController get controller => _ensureInitialized().$1;
  Animation<double> get curved => _ensureInitialized().$2;

  @override
  void initState() {
    super.initState();
    _ensureInitialized();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final (ctrl, _) = _ensureInitialized();
    final reducedMotion = AppMotion.isReducedMotion(context);
    ctrl.duration = reducedMotion ? Duration.zero : animationDuration;
    if (!_initialized) {
      _initialized = true;
      if (reducedMotion || forceComplete) {
        ctrl.value = 1.0;
      } else {
        ctrl.forward(from: 0.0);
      }
    } else if ((reducedMotion || forceComplete) && ctrl.value < 1.0) {
      ctrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final (ctrl, _) = _ensureInitialized();
    final newSig = computeDataSignature();
    final dataChanged = _lastSignature != null && newSig != _lastSignature;
    _lastSignature = newSig;
    if (forceComplete) {
      ctrl.value = 1.0;
      return;
    }
    if (dataChanged) {
      if (AppMotion.isReducedMotion(context)) {
        ctrl.value = 1.0;
      } else {
        ctrl.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _curved?.dispose();
    _curved = null;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

Widget _buildSmoothValueText({
  required String keyId,
  required String text,
  required TextStyle style,
  required Duration duration,
}) {
  return AnimatedSwitcher(
    duration: duration,
    switchInCurve: _kSilkySmoothCurve,
    switchOutCurve: AppMotion.exitCurve,
    layoutBuilder: (currentChild, previousChildren) => Stack(
      alignment: Alignment.centerLeft,
      children: [...previousChildren, ?currentChild],
    ),
    transitionBuilder: (child, anim) {
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.14),
        end: Offset.zero,
      ).animate(anim);
      return FadeTransition(
        opacity: anim,
        child: SlideTransition(position: slide, child: child),
      );
    },
    child: Align(
      key: ValueKey(keyId),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

Widget _buildKpiStatCard(
  BuildContext context,
  DhkpStatItem item,
  bool isDark, {
  bool horizontalWideLayout = false,
}) {
  return _AnimatedKpiStatCard(
    item: item,
    isDark: isDark,
    horizontalWideLayout: horizontalWideLayout,
  );
}

class _AnimatedKpiStatCard extends StatefulWidget {
  final DhkpStatItem item;
  final bool isDark;
  final bool horizontalWideLayout;

  const _AnimatedKpiStatCard({
    required this.item,
    required this.isDark,
    this.horizontalWideLayout = false,
  });

  @override
  State<_AnimatedKpiStatCard> createState() => _AnimatedKpiStatCardState();
}

class _AnimatedKpiStatCardState
    extends _ZeroOriginAnimState<_AnimatedKpiStatCard> {
  @override
  Duration get animationDuration => _kKpiTransitionDuration;

  @override
  String computeDataSignature() {
    final item = widget.item;
    final sparkSig = item.sparklinePoints?.join(',') ?? '';
    return '${item.label}|${item.value}|${item.numericValue ?? ""}|$sparkSig';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = widget.isDark;
    final colorDuration = AppMotion.resolve(context, AppMotion.complex);
    final reducedMotion = AppMotion.isReducedMotion(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isAmoled = isDark && colorScheme.surface == Colors.black;

    final accent = isDark ? item.color.shade300 : item.color.shade700;
    final valueColor = isDark ? Colors.white : item.color.shade900;
    final cardBg = isAmoled
        ? item.color.withValues(alpha: 0.14)
        : item.color.withValues(alpha: isDark ? 0.16 : 0.075);
    final borderColor = item.color.withValues(alpha: isDark ? 0.34 : 0.24);
    final hasSpark =
        item.sparklinePoints != null && item.sparklinePoints!.length >= 2;
    final sparkSig = computeDataSignature();

    Widget buildDeltaBadge() => _buildDeltaTrendPill(
      context,
      deltaText: item.deltaText,
      isFavorable: item.deltaIsFavorable ?? true,
      isDark: isDark,
      fontSize: 9,
    );

    Widget buildSpark({required double height}) {
      if (!hasSpark) return const SizedBox.shrink();
      return _AnimatedMiniSparkline(
        points: item.sparklinePoints!,
        animationSignature: sparkSig,
        color: accent,
        height: height,
        isDark: isDark,
      );
    }

    Widget buildAnimatedValue({required double fontSize}) {
      final textStyle = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: valueColor,
      );
      final numVal = item.numericValue;
      final builder = item.animatedValueBuilder;
      if (numVal == null || builder == null) {
        return _buildSmoothValueText(
          keyId:
              '${widget.horizontalWideLayout ? "wide:" : ""}${item.label}:${item.value}',
          text: item.value,
          duration: colorDuration,
          style: textStyle,
        );
      }
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = reducedMotion ? 1.0 : curved.value.clamp(0.0, 1.0);
          final lerped = unityLerp(0.0, numVal, t);
          final display = t >= 0.9999 ? item.value : builder(lerped);
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              display,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    }

    return AnimatedContainer(
      duration: colorDuration,
      curve: _kSilkySmoothCurve,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor),
      ),
      child: widget.horizontalWideLayout
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(item.icon, size: 14, color: accent),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(child: buildAnimatedValue(fontSize: 15)),
                          if (item.deltaText != null) ...[
                            const SizedBox(width: 6),
                            Flexible(child: buildDeltaBadge()),
                          ],
                        ],
                      ),
                      Text(
                        item.sub,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hasSpark) ...[
                  const SizedBox(width: 10),
                  SizedBox(width: 92, child: buildSpark(height: 34)),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(item.icon, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    buildAnimatedValue(fontSize: 14.5),
                    if (item.deltaText != null) ...[
                      const SizedBox(height: 4),
                      buildDeltaBadge(),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      item.sub,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (hasSpark)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: buildSpark(height: 24),
                  ),
              ],
            ),
    );
  }
}

class DhkpSemiCircularGaugeCard extends StatefulWidget {
  final DhkpGaugeSummary summary;
  final bool isDark;
  final bool compactHorizontal;

  const DhkpSemiCircularGaugeCard({
    super.key,
    required this.summary,
    required this.isDark,
    this.compactHorizontal = false,
  });

  @override
  State<DhkpSemiCircularGaugeCard> createState() =>
      _DhkpSemiCircularGaugeCardState();
}

class _DhkpSemiCircularGaugeCardState
    extends _ZeroOriginAnimState<DhkpSemiCircularGaugeCard> {
  @override
  Duration get animationDuration => _kGaugeSweepDuration;

  @override
  String computeDataSignature() {
    final s = widget.summary;
    return '${s.scopeTitle}|${s.tahun}|${s.achievedPct.toStringAsFixed(4)}|'
        '${s.paidNominal}|${s.targetNominal}|${s.paidCount}|${s.totalCount}';
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final isDark = widget.isDark;
    final compactHorizontal = widget.compactHorizontal;
    final colorScheme = Theme.of(context).colorScheme;
    final paidTone = AppSemanticColors.of(context, AppBadgeTone.paid);
    final warnTone = AppSemanticColors.of(context, AppBadgeTone.warning);
    final isAmoled = isDark && colorScheme.surface == Colors.black;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final containerDuration = AppMotion.resolve(context, AppMotion.complex);

    final gaugeColor = summary.achievedPct >= 80
        ? paidTone.foreground
        : (summary.achievedPct >= 45
              ? (isDark
                    ? summary.accentColor.shade300
                    : summary.accentColor.shade600)
              : warnTone.foreground);

    final cardBg = isAmoled
        ? const Color(0xFF0E1117)
        : (isDark ? colorScheme.surfaceContainerLow : Colors.white);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.grey.shade200;

    Widget buildGaugeWidget({
      required double width,
      required double height,
      required double displayPct,
    }) {
      return SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _SemiCircularGaugePainter(
            displayPct: displayPct,
            accentColor: gaugeColor,
            isDark: isDark,
          ),
          child: Align(
            alignment: const Alignment(0, 0.34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${displayPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: compactHorizontal ? 16 : 20,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDark ? Colors.white : Colors.grey.shade900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'REALISASI',
                  style: TextStyle(
                    fontSize: compactHorizontal ? 7.5 : 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: gaugeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildDeltaChip() => _buildDeltaTrendPill(
      context,
      deltaText: summary.deltaText,
      isFavorable: summary.deltaIsFavorable,
      isDark: isDark,
      fontSize: 9.5,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = reducedMotion ? 1.0 : curved.value.clamp(0.0, 1.0);
        final displayPct = unityLerp(0.0, summary.achievedPct, t);
        final displayPaidNominal = unityLerp(
          0.0,
          summary.paidNominal.toDouble(),
          t,
        ).round();
        final displayTargetNominal = unityLerp(
          0.0,
          summary.targetNominal.toDouble(),
          t,
        ).round();
        final displayPaidCount = unityLerp(
          0.0,
          summary.paidCount.toDouble(),
          t,
        ).round();
        final displayTotalCount = unityLerp(
          0.0,
          summary.totalCount.toDouble(),
          t,
        ).round();

        return AnimatedContainer(
          duration: containerDuration,
          curve: _kSilkySmoothCurve,
          padding: EdgeInsets.symmetric(
            horizontal: compactHorizontal ? 12 : 14,
            vertical: compactHorizontal ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: borderColor),
          ),
          child: compactHorizontal
              ? Row(
                  children: [
                    buildGaugeWidget(
                      width: 116,
                      height: 78,
                      displayPct: displayPct,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  summary.scopeTitle,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.grey.shade200
                                        : Colors.grey.shade800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (summary.tahun.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: gaugeColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    summary.tahun,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: gaugeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatRupiah(displayPaidNominal),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: isDark
                                  ? Colors.white
                                  : Colors.grey.shade900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Target: Rp ${formatShortRupiah(displayTargetNominal)} • $displayPaidCount/$displayTotalCount objek',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (summary.deltaText != null) ...[
                            const SizedBox(height: 5),
                            buildDeltaChip(),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.speed_rounded, size: 15, color: gaugeColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            summary.scopeTitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.grey.shade200
                                  : Colors.grey.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (summary.tahun.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: gaugeColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              summary.tahun,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: gaugeColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    buildGaugeWidget(
                      width: 170,
                      height: 96,
                      displayPct: displayPct,
                    ),
                    if (summary.deltaText != null) ...[
                      const SizedBox(height: 2),
                      buildDeltaChip(),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Masuk: Rp ${formatShortRupiah(displayPaidNominal)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$displayPaidCount/$displayTotalCount SPPT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

bool _doubleListEquals(List<double> a, List<double> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-6) return false;
  }
  return true;
}

class _AnimatedMiniSparkline extends StatefulWidget {
  final List<double> points;
  final String animationSignature;
  final Color color;
  final double height;
  final bool isDark;

  const _AnimatedMiniSparkline({
    required this.points,
    this.animationSignature = '',
    required this.color,
    required this.height,
    required this.isDark,
  });

  @override
  State<_AnimatedMiniSparkline> createState() => _AnimatedMiniSparklineState();
}

class _AnimatedMiniSparklineState
    extends _ZeroOriginAnimState<_AnimatedMiniSparkline> {
  @override
  Duration get animationDuration => _kSparklineAnimDuration;

  @override
  String computeDataSignature() =>
      '${widget.animationSignature}|${widget.points.join(",")}';

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.isReducedMotion(context);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = reducedMotion ? 1.0 : curved.value.clamp(0.0, 1.0);
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _MiniSparklinePainter(
              points: widget.points,
              color: widget.color,
              progress: t,
              isDark: widget.isDark,
            ),
          ),
        );
      },
    );
  }
}

class _MiniSparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  final double progress;
  final bool isDark;

  _MiniSparklinePainter({
    required this.points,
    required this.color,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (points.length < 2 || size.width <= 8 || size.height <= 6 || p <= 0.001) {
      return;
    }

    var minVal = points.first;
    var maxVal = points.first;
    for (final v in points) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }

    final span = (maxVal - minVal).abs();
    const hPad = 3.5;
    const topPad = 4.0;
    const bottomPad = 3.0;
    final usableW = size.width - hPad * 2;
    final usableH = size.height - topPad - bottomPad;
    if (usableW <= 0 || usableH <= 0) return;

    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final tX = i / (points.length - 1);
      final tY = span > 1e-6 ? ((points[i] - minVal) / span) : 0.5;
      final x = hPad + usableW * tX;
      final y = topPad + usableH * (1.0 - tY);
      offsets.add(Offset(x, y));
    }

    final linePath = _buildMonotoneCubicPath(
      offsets,
      minY: topPad,
      maxY: size.height - bottomPad,
    );

    final areaPath = Path.from(linePath)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();

    final areaAlphaScale = unityLerp(0.0, 1.0, p);
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: (isDark ? 0.28 : 0.20) * areaAlphaScale),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset tip = offsets.last;
    if (p >= 0.999) {
      canvas.drawPath(areaPath, areaPaint);
      canvas.drawPath(linePath, linePaint);
    } else {
      final sliced = _slicePathToProgress(linePath, p);
      tip = sliced.tip ?? offsets.first;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(0, 0, tip.dx + 0.5, size.height),
      );
      canvas.drawPath(areaPath, areaPaint);
      canvas.restore();
      canvas.drawPath(sliced.path, linePaint);
    }

    final dotAlpha = unityLerp(0.0, 1.0, (p * 3.0).clamp(0.0, 1.0));
    canvas.drawCircle(
      tip,
      4.2,
      Paint()
        ..color = color.withValues(alpha: (isDark ? 0.30 : 0.22) * dotAlpha),
    );
    canvas.drawCircle(
      tip,
      2.2,
      Paint()..color = color.withValues(alpha: dotAlpha),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) {
    return !_doubleListEquals(oldDelegate.points, points) ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark;
  }
}

class _SemiCircularGaugePainter extends CustomPainter {
  final double displayPct;
  final Color accentColor;
  final bool isDark;

  _SemiCircularGaugePainter({
    required this.displayPct,
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.77);
    final radius = math.min(size.width * 0.43, size.height * 0.65) - 4;
    if (radius <= 12) return;

    const startAngle = math.pi * 0.92;
    const totalSweep = math.pi * 1.16;
    final ratio = (displayPct / 100.0).clamp(0.0, 1.0);
    final activeSweep = totalSweep * ratio;
    final strokeW = radius >= 54 ? 9.5 : 7.5;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // Segmented inner ticks ala performance dashboard gauge
    const tickCount = 24;
    final innerR = radius - strokeW * 0.78;
    final outerTickR = innerR - 4.5;
    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = startAngle + totalSweep * t;
      final isMajor = i % 4 == 0;
      final len = isMajor ? 5.0 : 3.0;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      // Transisi opasitas tick di sekitar ujung jarum agar tidak berkedip kasar
      final fillDelta = ((ratio - t) / (1.0 / tickCount)).clamp(0.0, 1.0);
      final baseTickAlpha = isDark ? 0.14 : 0.12;
      final activeTickAlpha = isDark ? 0.78 : 0.68;
      final tickColor = Color.lerp(
        (isDark ? Colors.white : Colors.black).withValues(alpha: baseTickAlpha),
        accentColor.withValues(alpha: activeTickAlpha),
        fillDelta,
      )!;
      final tickPaint = Paint()
        ..color = tickColor
        ..strokeWidth = isMajor ? 1.5 : 1.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(
          center.dx + (outerTickR + len) * cosA,
          center.dy + (outerTickR + len) * sinA,
        ),
        Offset(center.dx + outerTickR * cosA, center.dy + outerTickR * sinA),
        tickPaint,
      );
    }

    // Track arc
    final trackPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, startAngle, totalSweep, false, trackPaint);

    // Active progress arc + subtle halo + terminal knob
    if (activeSweep > 0.008) {
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: isDark ? 0.22 : 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW + 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, startAngle, activeSweep, false, glowPaint);

      final hsl = HSLColor.fromColor(accentColor);
      final startShade = hsl
          .withLightness((hsl.lightness + 0.08).clamp(0.25, 0.80))
          .toColor();
      final activePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [startShade, accentColor],
        ).createShader(arcRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, startAngle, activeSweep, false, activePaint);
    }

    final tipAngle = startAngle + activeSweep;
    final tipPos = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    final knobR = strokeW * 0.56;
    canvas.drawCircle(tipPos, knobR + 1.5, Paint()..color = accentColor);
    canvas.drawCircle(
      tipPos,
      knobR * 0.65,
      Paint()..color = isDark ? const Color(0xFF0E1117) : Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SemiCircularGaugePainter oldDelegate) {
    return (oldDelegate.displayPct - displayPct).abs() > 1e-4 ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark;
  }
}

Widget buildDhkpEmptyCard() {
  return const Card(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: Text('Tidak ada data catatan blok untuk ditampilkan.'),
      ),
    ),
  );
}

/// Painter untuk menggambar garis grid horizontal dan label skala sumbu Y (ala Word / Excel)
class ColumnChartGridPainter extends CustomPainter {
  final double maxVal;
  final bool isDark;
  final double topOffset;
  final double bottomOffset;
  final double leftMargin;
  final double rightMargin;
  final String Function(double)? yAxisFormatter;

  ColumnChartGridPainter({
    required this.maxVal,
    required this.isDark,
    required this.topOffset,
    required this.bottomOffset,
    required this.leftMargin,
    required this.rightMargin,
    this.yAxisFormatter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartHeight = size.height - topOffset - bottomOffset;
    if (chartHeight <= 0) return;

    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 0.8;

    const divisions = 4;
    for (int k = 0; k <= divisions; k++) {
      final ratio = k / divisions;
      final y = topOffset + chartHeight * (1.0 - ratio);

      final isBaseline = k == 0;
      final linePaint = isBaseline
          ? (Paint()
              ..color = isDark ? Colors.white24 : Colors.black26
              ..strokeWidth = 1.0)
          : gridPaint;

      // Garis grid horizontal
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        linePaint,
      );

      // Label sumbu Y di sebelah kiri
      if (leftMargin >= 28.0) {
        final val = maxVal * ratio;
        String label;
        if (yAxisFormatter != null) {
          label = yAxisFormatter!(val);
        } else if (maxVal <= 100.0) {
          label = '${val.round()}%';
        } else if (k == 0) {
          label = '0';
        } else {
          label = formatShortRupiah(val.round());
        }

        final textSpan = TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        );
        final tp = TextPainter(
          text: textSpan,
          textAlign: TextAlign.right,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: leftMargin - 6);
        tp.paint(canvas, Offset(leftMargin - 6 - tp.width, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant ColumnChartGridPainter oldDelegate) {
    return oldDelegate.maxVal != maxVal ||
        oldDelegate.isDark != isDark ||
        oldDelegate.topOffset != topOffset ||
        oldDelegate.bottomOffset != bottomOffset ||
        oldDelegate.leftMargin != leftMargin ||
        oldDelegate.rightMargin != rightMargin;
  }
}

/// Painter untuk menggambar label sumbu X yang presisi 100% simetris di garis tengah batang
class SlantedLabelPainter extends CustomPainter {
  final String label;
  final bool rotate;
  final bool isSelected;
  final bool isDark;
  final Color color1;
  final double fontSize;

  SlantedLabelPainter({
    required this.label,
    required this.rotate,
    required this.isSelected,
    required this.isDark,
    required this.color1,
    required this.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2.0;
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected
            ? color1
            : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
      ),
    );

    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    )..layout();

    if (rotate) {
      canvas.save();
      // Posisikan origin tepat di sumbu tengah batang vertikal, 6px di bawah garis dasar
      canvas.translate(centerX - 1.0, 6.0);
      canvas.rotate(-math.pi / 4); // Rotasi -45 derajat ala Word / Excel
      // Gambar teks agar ujung kanan (huruf/angka terakhir) berakhir tepat di tengah batang
      tp.paint(canvas, Offset(-tp.width, -tp.height / 2));
      canvas.restore();
    } else {
      // Tepat di tengah batang secara horizontal
      tp.paint(canvas, Offset(centerX - tp.width / 2.0, 5.0));
    }
  }

  @override
  bool shouldRepaint(covariant SlantedLabelPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.rotate != rotate ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.isDark != isDark ||
        oldDelegate.color1 != color1 ||
        oldDelegate.fontSize != fontSize;
  }
}

/// Kontainer gulir horizontal khusus diagram yang mendukung:
/// 1. Sentuhan layar sentuh (mobile/tablet)
/// 2. Drag / seret mouse (desktop)
/// 3. Roda putar mouse (mouse wheel) horizontal di desktop
/// 4. Scrollbar interaktif yang terlihat jelas
class DhkpScrollableBars extends StatefulWidget {
  final Widget child;

  const DhkpScrollableBars({super.key, required this.child});

  @override
  State<DhkpScrollableBars> createState() => _DhkpScrollableBarsState();
}

class _DhkpScrollableBarsState extends State<DhkpScrollableBars> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _scrollController.hasClients) {
      final double delta = event.scrollDelta.dy != 0
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
      if (delta != 0) {
        final newOffset = (_scrollController.offset + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(newOffset);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          thickness: 4.5,
          radius: const Radius.circular(3),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

Widget renderDhkpColumnBars({
  required List<DhkpGroupInfo> groups,
  required double Function(DhkpGroupInfo) valueExtractor,
  required double maxVal,
  required String Function(DhkpGroupInfo) topLabelExtractor,
  required String Function(DhkpGroupInfo) subLabelExtractor,
  required Color color1,
  required Color color2,
  required bool isDark,
  required String? selectedItemLabel,
  required double animationValue,
  required ValueChanged<String?> onSelectLabel,
  String Function(double)? yAxisFormatter,
  String Function(DhkpGroupInfo group, double t)? animatedTopLabelBuilder,
  bool fitScreen = true,
}) {
  if (groups.isEmpty) return buildDhkpEmptyCard();

  final effectiveMax = maxVal > 0 ? maxVal : 1.0;
  final n = groups.length;

  return SizedBox(
    height: 255,
    child: LayoutBuilder(
      builder: (context, constraints) {
        const leftMargin = 42.0;
        const rightMargin = 20.0;
        const topOffset = 28.0;

        // Jika jumlah data > 7 atau lebar slot per item < 48 px, miringkan label sumbu X 45 derajat (seperti Word/Excel)
        final totalWidth = constraints.maxWidth;
        final chartAvailableWidth = math.max(
          0.0,
          totalWidth - leftMargin - rightMargin,
        );
        final rawSlotWidth = n > 0
            ? (chartAvailableWidth / n)
            : chartAvailableWidth;
        final rotateLabels = n > 7 || rawSlotWidth < 48.0;
        final bottomOffset = rotateLabels ? 54.0 : 26.0;

        // Batas kenyamanan visual:
        // Jika data sedikit (<= 7 seperti Dusun), selalu muat 100% penuh tanpa scroll.
        // Jika fitScreen == true:
        //   - Pada layar Desktop/Tablet (rawSlotWidth >= 16.0 px), otomatis pas 100% layar (dirapatkan).
        //   - Pada layar sempit HP (rawSlotWidth < 16.0 px), otomatis scrollable agar tidak berdempetan.
        // Jika fitScreen == false:
        //   - Selalu scrollable dengan lebar slot lega (46 px) agar batang tebal & nyaman di-scroll.
        final bool isScrollable;
        final double slotWidth;
        if (n <= 7) {
          isScrollable = false;
          slotWidth = rawSlotWidth;
        } else if (fitScreen) {
          if (rawSlotWidth >= 16.0) {
            isScrollable = false;
            slotWidth = rawSlotWidth;
          } else {
            isScrollable = true;
            slotWidth = 44.0;
          }
        } else {
          isScrollable = rawSlotWidth < 46.0;
          slotWidth = isScrollable ? 46.0 : rawSlotWidth;
        }

        // Batang proporsional & nyaman disentuh
        final double barWidth;
        if (n <= 7) {
          barWidth = math.min(28.0, math.max(16.0, slotWidth * 0.45));
        } else {
          barWidth = (slotWidth * 0.46).clamp(8.0, 24.0);
        }

        // Tampilkan label angka di atas batang jika ruang mencukupi
        final canShowTopLabels = slotWidth >= 22.0;

        // Widget baris item diagram batang
        Widget buildBarItem(DhkpGroupInfo g, int idx) {
          final t = animationValue.clamp(0.0, 1.0);
          final isSelected = selectedItemLabel == g.label;
          final val = valueExtractor(g);
          final heightRatio = (val / effectiveMax).clamp(0.0, 1.0);
          final chartHeight = math.max(10.0, 255.0 - topOffset - bottomOffset);
          final lerpedRatio = unityLerp(0.0, heightRatio, t);
          final barHeight = heightRatio <= 0.0
              ? 0.0
              : math.max(3.0 * t, chartHeight * lerpedRatio);
          final displayTopLabel = animatedTopLabelBuilder != null
              ? animatedTopLabelBuilder(g, t)
              : topLabelExtractor(g);

          final subLabel = subLabelExtractor(g);
          final tooltipMessage =
              '${g.label}\n${topLabelExtractor(g)}${subLabel.isNotEmpty ? '\n$subLabel' : ''}';

          return Tooltip(
            message: tooltipMessage,
            waitDuration: const Duration(milliseconds: 250),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelectLabel(isSelected ? null : g.label);
              },
              borderRadius: BorderRadius.circular(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: isScrollable ? slotWidth : null,
                decoration: BoxDecoration(
                  color: isSelected
                      ? color1.withValues(alpha: isDark ? 0.22 : 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isSelected
                      ? Border.all(color: color1, width: 1.2)
                      : null,
                ),
                child: Column(
                  children: [
                    // 1. Area Label Atas (Nilai / Persentase)
                    SizedBox(
                      height: topOffset,
                      child: Center(
                        child: (canShowTopLabels || isSelected)
                            ? (isSelected && !canShowTopLabels
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color1,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        displayTopLabel,
                                        style: const TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                      ),
                                    )
                                  : Text(
                                      displayTopLabel,
                                      style: TextStyle(
                                        fontSize: isSelected
                                            ? 10.0
                                            : (slotWidth < 28
                                                  ? 7.5
                                                  : (slotWidth < 46
                                                        ? 8.5
                                                        : 9.5)),
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? color1
                                            : (isDark ? Colors.white : color2),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ))
                            : const SizedBox.shrink(),
                      ),
                    ),

                    // 2. Batang Vertikal (Align Bottom)
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: barWidth,
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isSelected
                                  ? [color1, color2]
                                  : [
                                      color1.withValues(
                                        alpha: isDark ? 0.85 : 0.95,
                                      ),
                                      color2.withValues(
                                        alpha: isDark ? 0.90 : 1.0,
                                      ),
                                    ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color2.withValues(
                                  alpha: isSelected ? 0.45 : 0.20,
                                ),
                                blurRadius: isSelected ? 6 : 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 3. Area Label Sumbu X (Bawah) - 100% Simetris dengan sumbu tengah batang
                    SizedBox(
                      height: bottomOffset,
                      child: CustomPaint(
                        painter: SlantedLabelPainter(
                          label: g.label,
                          rotate: rotateLabels,
                          isSelected: isSelected,
                          isDark: isDark,
                          color1: color1,
                          fontSize: n > 25
                              ? (slotWidth < 26.0 ? 8.0 : 8.5)
                              : 9.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final barsRow = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < n; i++) ...[
              if (!isScrollable)
                Expanded(child: buildBarItem(groups[i], i))
              else
                SizedBox(width: slotWidth, child: buildBarItem(groups[i], i)),
            ],
          ],
        );

        return Stack(
          children: [
            // Layer 1: Garis Grid Horizontal & Sumbu Y (ala Word)
            Positioned.fill(
              child: CustomPaint(
                painter: ColumnChartGridPainter(
                  maxVal: effectiveMax,
                  isDark: isDark,
                  topOffset: topOffset,
                  bottomOffset: bottomOffset,
                  leftMargin: leftMargin,
                  rightMargin: rightMargin,
                  yAxisFormatter: yAxisFormatter,
                ),
              ),
            ),

            // Layer 2: Batang Diagram
            Positioned(
              left: leftMargin,
              right: rightMargin,
              top: 0,
              bottom: 0,
              child: isScrollable
                  ? DhkpScrollableBars(child: barsRow)
                  : barsRow,
            ),
          ],
        );
      },
    ),
  );
}

Widget renderDhkpHorizontalBars({
  required List<DhkpGroupInfo> groups,
  required double Function(DhkpGroupInfo) valueExtractor,
  required double maxVal,
  required String Function(DhkpGroupInfo) labelRight,
  required String Function(DhkpGroupInfo) subRight,
  required Color color1,
  required Color color2,
  required bool isDark,
  required String? selectedItemLabel,
  required double animationValue,
  required GrafikSortMode sortMode,
  required ValueChanged<String?> onSelectLabel,
  bool useSemanticPercentageColor = false,
  bool showRankNumber = true,
  String Function(DhkpGroupInfo group, double t)? animatedLabelRightBuilder,
}) {
  final effectiveMax = maxVal > 0 ? maxVal : 1.0;
  final t = animationValue.clamp(0.0, 1.0);
  return Column(
    children: [
      for (int idx = 0; idx < groups.length; idx++) ...[
        Builder(
          builder: (context) {
            final g = groups[idx];
            final isSelected = selectedItemLabel == g.label;

            Color barC1 = color1;
            Color barC2 = color2;
            if (useSemanticPercentageColor) {
              if (g.lunasPct >= 75) {
                barC1 = Colors.green.shade400;
                barC2 = Colors.green.shade700;
              } else if (g.lunasPct >= 50) {
                barC1 = Colors.teal.shade400;
                barC2 = Colors.teal.shade700;
              } else if (g.lunasPct >= 25) {
                barC1 = Colors.amber.shade500;
                barC2 = Colors.orange.shade700;
              } else {
                barC1 = Colors.orange.shade400;
                barC2 = Colors.red.shade600;
              }
            }

            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelectLabel(isSelected ? null : g.label);
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  vertical: 7.5,
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? barC1.withValues(alpha: isDark ? 0.18 : 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (showRankNumber &&
                        sortMode != GrafikSortMode.wilayah) ...[
                      Container(
                        width: 22,
                        height: 20,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: idx < 3
                              ? barC2.withValues(alpha: 0.2)
                              : (isDark
                                    ? Colors.white10
                                    : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '#${idx + 1}',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: idx < 3 ? barC2 : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(
                      width: 68,
                      child: Text(
                        g.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 18,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final val = valueExtractor(g);
                              final widthRatio = (val / effectiveMax).clamp(
                                0.0,
                                1.0,
                              );
                              final barW =
                                  constraints.maxWidth *
                                  unityLerp(0.0, widthRatio, t);
                              return Container(
                                height: 18,
                                width: math.max(0, barW),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [barC1, barC2],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 98,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            animatedLabelRightBuilder != null
                                ? animatedLabelRightBuilder(g, t)
                                : labelRight(g),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subRight(g),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ],
  );
}

Widget renderDhkpPieChart({
  required List<DhkpPieSliceInfo> slices,
  required String centerLabel,
  required String centerSub,
  required MaterialColor centerColor,
  required bool isDark,
  required String? selectedItemLabel,
  required double animationValue,
  required ValueChanged<String?> onSelectLabel,
  String Function(double t)? animatedCenterLabelBuilder,
}) {
  if (slices.isEmpty) {
    return const SizedBox(
      height: 150,
      child: Center(child: Text('Belum ada data untuk ditampilkan.')),
    );
  }

  final t = animationValue.clamp(0.0, 1.0);
  final selectedSlice = slices
      .where((s) => s.label == selectedItemLabel)
      .firstOrNull;
  final activeCenterLabel = selectedSlice != null
      ? '${unityLerp(0.0, selectedSlice.ratio * 100, t).toStringAsFixed(1)}%'
      : (animatedCenterLabelBuilder != null
            ? animatedCenterLabelBuilder(t)
            : centerLabel);
  final activeCenterSub = selectedSlice != null
      ? selectedSlice.label.toUpperCase()
      : centerSub;

  return Row(
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final center = const Offset(75, 75);
          final dx = details.localPosition.dx - center.dx;
          final dy = details.localPosition.dy - center.dy;
          final dist = math.sqrt(dx * dx + dy * dy);

          if (dist <= 75) {
            if (dist < 26) {
              HapticFeedback.selectionClick();
              onSelectLabel(null);
              return;
            }

            final tapAngle = math.atan2(dy, dx);
            double angleFromTop = (tapAngle - (-math.pi / 2)) % (2 * math.pi);
            if (angleFromTop < 0) angleFromTop += 2 * math.pi;

            double accumulated = 0;
            for (final s in slices) {
              final sweep = 2 * math.pi * s.ratio;
              if (angleFromTop >= accumulated &&
                  angleFromTop < accumulated + sweep) {
                HapticFeedback.selectionClick();
                onSelectLabel(selectedItemLabel == s.label ? null : s.label);
                return;
              }
              accumulated += sweep;
            }
          }
        },
        child: SizedBox(
          width: 150,
          height: 150,
          child: CustomPaint(
            painter: ContributionPiePainter(
              slices: slices,
              selectedLabel: selectedItemLabel,
              progress: animationValue,
              isDark: isDark,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeCenterLabel,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: selectedSlice?.color ?? centerColor.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      activeCenterSub,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in slices.take(8)) ...[
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelectLabel(selectedItemLabel == s.label ? null : s.label);
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4.5,
                    horizontal: 6,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selectedItemLabel == s.label
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${unityLerp(0.0, s.ratio * 100, t).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${formatShortRupiah(unityLerp(0.0, s.nominal.toDouble(), t).round())})',
                        style: TextStyle(
                          fontSize: 9,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (slices.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  '+ ${slices.length - 8} wilayah lainnya (lihat tabel di bawah)',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

Widget renderDhkpDonutTwoSlice({
  required double achievedPct,
  required String achievedLabel,
  required String remainingLabel,
  required Color achievedColor,
  required Color remainingColor,
  required String centerLabel,
  required String centerSub,
  required bool isDark,
  required String? selectedItemLabel,
  required double animationValue,
  required ValueChanged<String?> onSelectLabel,
  String Function(double animatedPct)? animatedCenterLabelBuilder,
}) {
  final t = animationValue.clamp(0.0, 1.0);
  final safePct = achievedPct.clamp(0.0, 100.0);
  final lerpedPct = unityLerp(0.0, safePct, t);
  final lerpedRemPct = unityLerp(0.0, 100.0 - safePct, t);
  final activeCenterLabel = animatedCenterLabelBuilder != null
      ? animatedCenterLabelBuilder(lerpedPct)
      : centerLabel;
  final ratio = safePct / 100.0;
  final slices = [
    DhkpPieSliceInfo(
      label: achievedLabel,
      nominal: safePct,
      ratio: ratio,
      color: achievedColor,
    ),
    DhkpPieSliceInfo(
      label: remainingLabel,
      nominal: 100.0 - safePct,
      ratio: 1.0 - ratio,
      color: remainingColor,
    ),
  ];

  return Row(
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final center = const Offset(75, 75);
          final dx = details.localPosition.dx - center.dx;
          final dy = details.localPosition.dy - center.dy;
          final dist = math.sqrt(dx * dx + dy * dy);

          if (dist <= 75) {
            if (dist < 26) {
              HapticFeedback.selectionClick();
              onSelectLabel(null);
              return;
            }

            final tapAngle = math.atan2(dy, dx);
            double angleFromTop = (tapAngle - (-math.pi / 2)) % (2 * math.pi);
            if (angleFromTop < 0) angleFromTop += 2 * math.pi;

            final achievedSweep = 2 * math.pi * ratio;
            HapticFeedback.selectionClick();
            if (angleFromTop < achievedSweep) {
              onSelectLabel(
                selectedItemLabel == achievedLabel ? null : achievedLabel,
              );
            } else {
              onSelectLabel(
                selectedItemLabel == remainingLabel ? null : remainingLabel,
              );
            }
          }
        },
        child: SizedBox(
          width: 150,
          height: 150,
          child: CustomPaint(
            painter: ContributionPiePainter(
              slices: slices,
              selectedLabel: selectedItemLabel,
              progress: animationValue,
              isDark: isDark,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    activeCenterLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: achievedColor,
                    ),
                  ),
                  Text(
                    centerSub,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTwoSliceLegend(
              color: achievedColor,
              label: achievedLabel,
              pct: '${lerpedPct.toStringAsFixed(1)}%',
              desc: 'Sudah lunas dibayarkan',
              isDark: isDark,
              selectedItemLabel: selectedItemLabel,
              onSelectLabel: onSelectLabel,
            ),
            const SizedBox(height: 12),
            _buildTwoSliceLegend(
              color: remainingColor,
              label: remainingLabel,
              pct: '${lerpedRemPct.toStringAsFixed(1)}%',
              desc: 'Target yang belum tercapai',
              isDark: isDark,
              selectedItemLabel: selectedItemLabel,
              onSelectLabel: onSelectLabel,
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildTwoSliceLegend({
  required Color color,
  required String label,
  required String pct,
  required String desc,
  required bool isDark,
  required String? selectedItemLabel,
  required ValueChanged<String?> onSelectLabel,
}) {
  final isSelected = selectedItemLabel == label;
  return InkWell(
    onTap: () {
      HapticFeedback.selectionClick();
      onSelectLabel(isSelected ? null : label);
    },
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected ? color : null,
                      ),
                    ),
                    Text(
                      pct,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildDhkpDetailTableContent({
  required List<DhkpGroupInfo> groups,
  required String col1,
  required String col2,
  required String col3,
  required String col4,
  required String Function(DhkpGroupInfo) col2Val,
  required String Function(DhkpGroupInfo) col3Val,
  required String Function(DhkpGroupInfo) col4Val,
  required bool isDark,
  required String? selectedItemLabel,
  required MaterialColor accentColor,
  required ValueChanged<String?> onSelectLabel,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                col1,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                col2,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                col3,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                col4,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      for (int i = 0; i < groups.length; i++) ...[
        Builder(
          builder: (context) {
            final g = groups[i];
            final isSelected = selectedItemLabel == g.label;
            return InkWell(
              onTap: () {
                onSelectLabel(isSelected ? null : g.label);
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 7,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: isDark ? 0.2 : 0.1)
                      : (i.isOdd
                            ? (isDark
                                  ? Colors.white.withValues(alpha: 0.02)
                                  : Colors.grey.shade50)
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        g.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        col2Val(g),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        col3Val(g),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        col4Val(g),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ],
  );
}

class ContributionPiePainter extends CustomPainter {
  final List<DhkpPieSliceInfo> slices;
  final String? selectedLabel;
  final double progress;
  final bool isDark;

  ContributionPiePainter({
    required this.slices,
    this.selectedLabel,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    const baseStrokeWidth = 22.0;

    final bgPaint = Paint()
      ..color = isDark ? Colors.grey.shade800 : Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStrokeWidth;
    canvas.drawCircle(center, radius - baseStrokeWidth / 2, bgPaint);

    double startAngle = -math.pi / 2;
    for (final slice in slices) {
      final isSelected = selectedLabel != null && selectedLabel == slice.label;
      final strokeW = isSelected ? baseStrokeWidth + 5.0 : baseStrokeWidth;
      final sweepAngle = 2 * math.pi * slice.ratio * progress;

      final paint = Paint()
        ..color = selectedLabel == null || isSelected
            ? slice.color
            : slice.color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - baseStrokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant ContributionPiePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.slices != slices ||
        oldDelegate.selectedLabel != selectedLabel;
  }
}

/// Painter grafik garis tren bulanan halus (kurva monotone area gaya dashboard saham)
/// yang mendukung mode garis tunggal maupun multi-seri perbandingan (termasuk garis putus-putus).
class ComboBarLineTrendPainter extends CustomPainter {
  final List<int> data;
  final List<int> counts;
  final List<String> monthNames;
  final int maxVal;
  final double progress;
  final Color barColor1;
  final Color barColor2;
  final Color lineColor;
  final bool isDark;
  final int? selectedIndex;
  final int? hoveredIndex;
  final double? hoverY;
  final double? selectedY;
  final String? tahunLabel;
  final List<DhkpTrendSeries>? seriesList;
  final String? focusedSeriesId;
  final Set<String>? hiddenSeriesIds;

  ComboBarLineTrendPainter({
    required this.data,
    required this.counts,
    required this.monthNames,
    required this.maxVal,
    required this.progress,
    this.barColor1 = const Color(0xFF8B5CF6),
    this.barColor2 = const Color(0xFF7C3AED),
    required this.lineColor,
    required this.isDark,
    this.selectedIndex,
    this.hoveredIndex,
    this.hoverY,
    this.selectedY,
    this.tahunLabel,
    this.seriesList,
    this.focusedSeriesId,
    this.hiddenSeriesIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final customSeries = seriesList;
    final hasCustomSeries = customSeries != null && customSeries.isNotEmpty;
    final rawSeries = hasCustomSeries
        ? customSeries
        : (data.isEmpty
              ? const <DhkpTrendSeries>[]
              : [
                  DhkpTrendSeries(
                    id: 'primary',
                    label: (tahunLabel != null && tahunLabel!.isNotEmpty)
                        ? 'Tahun $tahunLabel'
                        : 'Penerimaan',
                    monthlyNominal: data,
                    monthlyCounts: counts,
                    totalNominal: data.fold<int>(0, (s, v) => s + v),
                    totalCount: counts.fold<int>(0, (s, v) => s + v),
                    color: lineColor,
                    isPrimary: true,
                    isDashed: false,
                  ),
                ]);
    if (rawSeries.isEmpty) return;

    final n = monthNames.isNotEmpty
        ? monthNames.length
        : rawSeries.first.monthlyNominal.length;
    if (n == 0) return;

    final w = size.width;
    final h = size.height;

    const leftMargin = 54.0;
    const rightMargin = 16.0;
    const topMargin = 24.0;
    const bottomMargin = 28.0;

    final chartWidth = math.max(0.0, w - leftMargin - rightMargin);
    final chartHeight = math.max(0.0, h - topMargin - bottomMargin);
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final baselineY = topMargin + chartHeight;
    final slotWidth = chartWidth / n;
    final p = progress.clamp(0.0, 1.0);

    final hidden = hiddenSeriesIds ?? const <String>{};
    final visibleSeries = rawSeries
        .where((s) => !hidden.contains(s.id))
        .toList();

    var effectiveMax = maxVal > 0 ? maxVal : 1;
    if (hasCustomSeries) {
      var peak = 0;
      for (final s in visibleSeries) {
        for (int i = 0; i < n && i < s.monthlyNominal.length; i++) {
          if (s.monthlyNominal[i] > peak) peak = s.monthlyNominal[i];
        }
      }
      effectiveMax = peak > 0 ? peak : (maxVal > 0 ? maxVal : 1);
    }

    double slotCenterX(int index) => n == 1
        ? leftMargin + chartWidth / 2
        : leftMargin + (index + 0.5) * slotWidth;

    // 1. Garis Grid Horizontal & Label Sumbu Y (0 sampai Max)
    for (int k = 0; k <= 3; k++) {
      final ratio = k / 3.0;
      final gy = topMargin + chartHeight * (1.0 - ratio);
      final gridPaint = Paint()
        ..color = k == 0
            ? (isDark ? Colors.white24 : Colors.black12)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06))
        ..strokeWidth = k == 0 ? 1.0 : 0.8;
      canvas.drawLine(
        Offset(leftMargin, gy),
        Offset(w - rightMargin, gy),
        gridPaint,
      );

      final val = (effectiveMax * ratio).round();
      final label = k == 0 ? '0' : formatShortRupiah(val);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftMargin - 8);
      tp.paint(canvas, Offset(leftMargin - 8 - tp.width, gy - tp.height / 2));
    }

    // 2. Bangun geometri kurva setiap seri yang terlihat
    final hasFocus =
        focusedSeriesId != null &&
        visibleSeries.any((s) => s.id == focusedSeriesId);
    final isDenseMode = !hasFocus && visibleSeries.length > 6;
    final topSeriesIds = <String>{};
    if (isDenseMode) {
      final ranked = [...visibleSeries]
        ..sort((a, b) => b.totalNominal.compareTo(a.totalNominal));
      for (final s in ranked.take(5)) {
        topSeriesIds.add(s.id);
      }
    }

    final rendered =
        <
          ({
            DhkpTrendSeries series,
            List<Offset> pts,
            Path linePath,
            Path areaPath,
            bool isFocused,
            bool isDimmed,
            bool showArea,
            double strokeWidth,
            double strokeAlpha,
            int priority,
          })
        >[];

    for (final s in visibleSeries) {
      final pts = <Offset>[];
      for (int i = 0; i < n; i++) {
        final cx = slotCenterX(i);
        final val = i < s.monthlyNominal.length ? s.monthlyNominal[i] : 0;
        final ratio = (val / effectiveMax).clamp(0.0, 1.0);
        final y = baselineY - (ratio * chartHeight);
        pts.add(Offset(cx, y));
      }

      final fullLinePath = _buildMonotoneCubicPath(
        pts,
        minY: topMargin,
        maxY: baselineY,
      );
      final fullAreaPath = Path()
        ..addPath(fullLinePath, Offset.zero)
        ..lineTo(pts.last.dx, baselineY)
        ..lineTo(pts.first.dx, baselineY)
        ..close();

      final isSingle = visibleSeries.length == 1;
      final isFocused = hasFocus && s.id == focusedSeriesId;
      final isDimmed = hasFocus && !isFocused;
      final isSecondaryDense = isDenseMode && !topSeriesIds.contains(s.id);

      final showArea = isSingle || isFocused || (s.isPrimary && !hasFocus);
      final strokeWidth = isFocused
          ? 3.1
          : isDimmed
          ? 1.4
          : isSecondaryDense
          ? 1.65
          : (s.isPrimary ? 2.75 : (s.isDashed ? 2.1 : 2.35));
      final strokeAlpha = isFocused
          ? 1.0
          : isDimmed
          ? 0.16
          : isSecondaryDense
          ? 0.44
          : (s.isDashed ? 0.86 : 0.96);
      final priority = isFocused
          ? 4
          : (s.isPrimary ? 3 : (isSecondaryDense ? 0 : (isDimmed ? 0 : 2)));

      rendered.add((
        series: s,
        pts: pts,
        linePath: fullLinePath,
        areaPath: fullAreaPath,
        isFocused: isFocused,
        isDimmed: isDimmed,
        showArea: showArea,
        strokeWidth: strokeWidth,
        strokeAlpha: strokeAlpha,
        priority: priority,
      ));
    }

    // Urutkan agar garis sekunder/redup digambar lebih dulu dan garis utama/fokus di atas.
    final drawOrder = [...rendered]
      ..sort((a, b) => a.priority.compareTo(b.priority));

    // 3. Garis Referensi Rata-rata Bulanan (khusus mode 1 garis agar tidak penuh)
    if (visibleSeries.length == 1 && n > 1 && p > 0.05) {
      final only = visibleSeries.first;
      if (only.totalNominal > 0) {
        final avgVal = only.totalNominal / n;
        final avgRatio = (avgVal / effectiveMax).clamp(0.0, 1.0);
        final avgY = baselineY - (avgRatio * chartHeight);
        final avgPaint = Paint()
          ..color = only.color.withValues(alpha: (isDark ? 0.34 : 0.26) * p)
          ..strokeWidth = 1.0;
        _drawDashedLine(
          canvas,
          Offset(leftMargin, avgY),
          Offset(w - rightMargin, avgY),
          avgPaint,
          dashLength: 4.5,
          gapLength: 4.0,
        );
      }
    }

    // 4. Animasi Penarikan Garis Halus dari Jan ke Des
    double? primaryTipDx;
    if (n >= 2 && p > 0.001 && drawOrder.isNotEmpty) {
      final areaOpacity = Curves.easeOut.transform((p * 1.15).clamp(0.0, 1.0));
      final leadSeriesId = drawOrder.last.series.id;

      for (final item in drawOrder) {
        final s = item.series;
        final c = s.color;
        final lighter = Color.lerp(c, Colors.white, isDark ? 0.18 : 0.12)!;
        final useGradient =
            !s.isDashed &&
            !item.isDimmed &&
            item.pts.last.dx > item.pts.first.dx;

        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (useGradient) {
          strokePaint.shader =
              LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  lighter.withValues(alpha: item.strokeAlpha),
                  c.withValues(alpha: item.strokeAlpha),
                ],
              ).createShader(
                Rect.fromLTRB(
                  item.pts.first.dx,
                  topMargin,
                  item.pts.last.dx,
                  baselineY,
                ),
              );
        } else {
          strokePaint.color = c.withValues(alpha: item.strokeAlpha);
        }

        Paint? areaPaint;
        if (item.showArea) {
          final isStrongArea = visibleSeries.length == 1 || item.isFocused;
          final topA = isStrongArea
              ? (isDark ? 0.30 : 0.22)
              : (isDark ? 0.14 : 0.10);
          final midA = isStrongArea
              ? (isDark ? 0.09 : 0.06)
              : (isDark ? 0.04 : 0.03);
          areaPaint = Paint()
            ..shader =
                LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.withValues(alpha: topA * areaOpacity),
                    c.withValues(alpha: midA * areaOpacity),
                    c.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.58, 1.0],
                ).createShader(
                  Rect.fromLTRB(
                    leftMargin,
                    topMargin,
                    w - rightMargin,
                    baselineY,
                  ),
                )
            ..style = PaintingStyle.fill;
        }

        Paint? glowPaint;
        final showGlow =
            !item.isDimmed &&
            !s.isDashed &&
            (visibleSeries.length == 1 || item.isFocused || s.isPrimary);
        if (showGlow) {
          glowPaint = Paint()
            ..color = c.withValues(alpha: isDark ? 0.22 : 0.14)
            ..style = PaintingStyle.stroke
            ..strokeWidth = item.strokeWidth + 3.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.2);
        }

        if (p >= 0.9999) {
          if (s.id == leadSeriesId) primaryTipDx = item.pts.last.dx;
          if (areaPaint != null) canvas.drawPath(item.areaPath, areaPaint);
          if (glowPaint != null) canvas.drawPath(item.linePath, glowPaint);
          final strokePath = s.isDashed
              ? _extractDashedPath(item.linePath)
              : item.linePath;
          canvas.drawPath(strokePath, strokePaint);
        } else {
          final sliced = _slicePathToProgress(item.linePath, p);
          final tipPos = sliced.tip;
          if (s.id == leadSeriesId && tipPos != null) {
            primaryTipDx = tipPos.dx;
          }
          if (areaPaint != null && tipPos != null) {
            canvas.save();
            canvas.clipRect(
              Rect.fromLTRB(
                item.pts.first.dx - 1.0,
                0.0,
                tipPos.dx + 0.5,
                baselineY + 2.0,
              ),
            );
            canvas.drawPath(item.areaPath, areaPaint);
            canvas.restore();
          }
          if (glowPaint != null) {
            canvas.drawPath(sliced.path, glowPaint);
          }
          final strokePath = s.isDashed
              ? _extractDashedPath(sliced.path)
              : sliced.path;
          canvas.drawPath(strokePath, strokePaint);

          // Kilau ujung penarik garis sementara hanya untuk seri terdepan
          if (s.id == leadSeriesId && tipPos != null) {
            final tipFade = p < 0.90
                ? 1.0
                : ((0.99 - p) / 0.09).clamp(0.0, 1.0);
            if (tipFade > 0.02) {
              canvas.drawCircle(
                tipPos,
                8.0,
                Paint()..color = c.withValues(alpha: 0.25 * tipFade),
              );
              canvas.drawCircle(
                tipPos,
                3.2,
                Paint()..color = c.withValues(alpha: tipFade),
              );
              canvas.drawCircle(
                tipPos,
                1.5,
                Paint()..color = Colors.white.withValues(alpha: tipFade),
              );
            }
          }
        }
      }
    } else if (n == 1 && p > 0.001 && drawOrder.isNotEmpty) {
      primaryTipDx = slotCenterX(0);
      for (final item in drawOrder) {
        canvas.drawCircle(
          item.pts.first,
          item.isFocused ? 5.0 : 4.0,
          Paint()
            ..color = item.series.color.withValues(alpha: item.strokeAlpha * p),
        );
      }
    }

    final activeIdx = hoveredIndex ?? selectedIndex;
    final activeAccent = hasFocus
        ? visibleSeries.firstWhere((s) => s.id == focusedSeriesId).color
        : (visibleSeries.isNotEmpty ? visibleSeries.first.color : lineColor);

    // 5. Label Sumbu X (Bulan: Jan, Feb, ..., Des)
    for (int i = 0; i < n; i++) {
      final monthText = i < monthNames.length ? monthNames[i] : '${i + 1}';
      final cx = slotCenterX(i);
      final isActive =
          activeIdx == i &&
          (p >= 0.98 ||
              (primaryTipDx != null && primaryTipDx >= cx - slotWidth * 0.25));
      final mPainter = TextPainter(
        text: TextSpan(
          text: monthText,
          style: TextStyle(
            fontSize: 10.0,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            color: isActive
                ? activeAccent
                : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      mPainter.paint(canvas, Offset(cx - mPainter.width / 2, baselineY + 7));
    }

    // 6. Penanda Titik, Crosshair Vertikal + Garis Lurus Horizontal & Tooltip saat Hover / Dipilih
    if (activeIdx != null &&
        activeIdx >= 0 &&
        activeIdx < n &&
        visibleSeries.isNotEmpty &&
        p > 0.02) {
      final guideX = slotCenterX(activeIdx);
      final focusOpacity = p >= 0.99
          ? 1.0
          : (((primaryTipDx ?? guideX) - (guideX - slotWidth * 0.35)) /
                    (slotWidth * 0.7))
                .clamp(0.0, 1.0);
      if (focusOpacity > 0.05) {
        final pointerY = (hoveredIndex != null && hoveredIndex == activeIdx)
            ? hoverY
            : (selectedIndex == activeIdx ? selectedY : null);

        final targetItem = () {
          if (visibleSeries.length == 1) return rendered.first;
          if (hasFocus) {
            return rendered.firstWhere((e) => e.isFocused);
          }
          if (pointerY != null) {
            var best = drawOrder.last;
            var bestDist = double.infinity;
            for (final item in rendered) {
              final d = (item.pts[activeIdx].dy - pointerY).abs();
              if (d < bestDist - 0.5 ||
                  ((d - bestDist).abs() <= 0.5 &&
                      item.priority > best.priority)) {
                bestDist = d;
                best = item;
              }
            }
            return best;
          }
          return drawOrder.last;
        }();

        final guideColor = targetItem.series.color;
        final guideY = targetItem.pts[activeIdx].dy.clamp(topMargin, baselineY);

        // Garis bantu vertikal pada sumbu X bulan aktif
        final verticalGuidePaint = Paint()
          ..color = guideColor.withValues(alpha: 0.42 * focusOpacity)
          ..strokeWidth = 1.15;
        _drawDashedLine(
          canvas,
          Offset(guideX, topMargin),
          Offset(guideX, baselineY),
          verticalGuidePaint,
          dashLength: 4.0,
          gapLength: 3.0,
        );

        // Garis lurus horizontal sejajar sumbu X tepat melewati titik (X, Y) yang dipilih
        final horizontalGuidePaint = Paint()
          ..color = guideColor.withValues(
            alpha: (isDark ? 0.72 : 0.60) * focusOpacity,
          )
          ..strokeWidth = 1.25;
        canvas.drawLine(
          Offset(leftMargin, guideY),
          Offset(w - rightMargin, guideY),
          horizontalGuidePaint,
        );

        // Label nilai Y aktif menempel di sumbu kiri sejajar garis lurus horizontal
        final targetVal = activeIdx < targetItem.series.monthlyNominal.length
            ? targetItem.series.monthlyNominal[activeIdx]
            : 0;
        final yBadgeText = targetVal > 0 ? formatShortRupiah(targetVal) : '0';
        final yBadgePainter = TextPainter(
          text: TextSpan(
            text: yBadgeText,
            style: TextStyle(
              fontSize: 9.0,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: Colors.white.withValues(alpha: focusOpacity),
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: leftMargin - 12);

        final yPillW = math.min(leftMargin - 6, yBadgePainter.width + 8);
        final yPillH = yBadgePainter.height + 4;
        final yPillLeft = math.max(2.0, leftMargin - yPillW - 3.0);
        final yPillTop = (guideY - yPillH / 2).clamp(
          topMargin - 6.0,
          baselineY - yPillH + 4.0,
        );
        final yPillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(yPillLeft, yPillTop, yPillW, yPillH),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          yPillRect,
          Paint()..color = guideColor.withValues(alpha: 0.94 * focusOpacity),
        );
        yBadgePainter.paint(
          canvas,
          Offset(
            yPillLeft + (yPillW - yBadgePainter.width) / 2,
            yPillTop + (yPillH - yBadgePainter.height) / 2,
          ),
        );

        final monthLabel = activeIdx < monthNames.length
            ? monthNames[activeIdx]
            : 'Bln ${activeIdx + 1}';

        if (visibleSeries.length == 1) {
          final only = visibleSeries.first;
          final selP = rendered.first.pts[activeIdx];
          canvas.drawCircle(
            selP,
            9.5,
            Paint()..color = only.color.withValues(alpha: 0.24 * focusOpacity),
          );
          canvas.drawCircle(
            selP,
            5.0,
            Paint()..color = only.color.withValues(alpha: focusOpacity),
          );
          canvas.drawCircle(
            selP,
            2.2,
            Paint()
              ..color = (isDark ? const Color(0xFF0F172A) : Colors.white)
                  .withValues(alpha: focusOpacity),
          );

          final val = activeIdx < only.monthlyNominal.length
              ? only.monthlyNominal[activeIdx]
              : 0;
          final count = activeIdx < only.monthlyCounts.length
              ? only.monthlyCounts[activeIdx]
              : 0;
          final title = (tahunLabel != null && tahunLabel!.isNotEmpty)
              ? '$monthLabel $tahunLabel'
              : '$monthLabel • ${only.label}';
          final pct = only.totalNominal > 0
              ? (val / only.totalNominal * 100.0)
              : 0.0;

          _drawTrendTooltip(
            canvas: canvas,
            anchor: selP,
            title: title,
            nominalText: val > 0 ? formatRupiah(val) : 'Rp 0',
            detailText: count > 0
                ? '$count objek • ${pct.toStringAsFixed(1)}%'
                : 'Belum ada pembayaran',
            accentColor: only.color,
            opacity: focusOpacity,
            minX: leftMargin,
            maxX: w - rightMargin,
            minY: 4.0,
            maxY: baselineY - 4.0,
          );
        } else {
          final activeSeriesHighlightId = hasFocus
              ? focusedSeriesId
              : (pointerY != null ? targetItem.series.id : null);

          for (final item in drawOrder) {
            if (item.isDimmed) continue;
            final pt = item.pts[activeIdx];
            final isTarget = item.series.id == targetItem.series.id;
            final rOuter = (item.isFocused || isTarget) ? 9.0 : 6.0;
            final rInner = (item.isFocused || isTarget) ? 4.8 : 3.4;
            canvas.drawCircle(
              pt,
              rOuter,
              Paint()
                ..color = item.series.color.withValues(
                  alpha: (isTarget ? 0.28 : 0.20) * focusOpacity,
                ),
            );
            canvas.drawCircle(
              pt,
              rInner,
              Paint()
                ..color = item.series.color.withValues(alpha: focusOpacity),
            );
            canvas.drawCircle(
              pt,
              1.8,
              Paint()
                ..color = (isDark ? const Color(0xFF0F172A) : Colors.white)
                    .withValues(alpha: focusOpacity),
            );
          }

          final sortedRows = [...visibleSeries]
            ..sort((a, b) {
              if (activeSeriesHighlightId != null) {
                if (a.id == activeSeriesHighlightId &&
                    b.id != activeSeriesHighlightId) {
                  return -1;
                }
                if (b.id == activeSeriesHighlightId &&
                    a.id != activeSeriesHighlightId) {
                  return 1;
                }
              }
              final va = activeIdx < a.monthlyNominal.length
                  ? a.monthlyNominal[activeIdx]
                  : 0;
              final vb = activeIdx < b.monthlyNominal.length
                  ? b.monthlyNominal[activeIdx]
                  : 0;
              final cmp = vb.compareTo(va);
              return cmp != 0 ? cmp : b.totalNominal.compareTo(a.totalNominal);
            });

          final isYearComparison = visibleSeries.any((s) => s.isDashed);
          final tooltipTitle =
              !isYearComparison && tahunLabel != null && tahunLabel!.isNotEmpty
              ? '$monthLabel $tahunLabel'
              : monthLabel;

          _drawMultiSeriesTooltip(
            canvas: canvas,
            guideX: guideX,
            anchorY: guideY,
            title: tooltipTitle,
            rows: sortedRows,
            monthIndex: activeIdx,
            focusedSeriesId: activeSeriesHighlightId,
            accentColor: guideColor,
            opacity: focusOpacity,
            minX: leftMargin,
            maxX: w - rightMargin,
            minY: 4.0,
            maxY: baselineY - 4.0,
            chartMidX: leftMargin + chartWidth * 0.52,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ComboBarLineTrendPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        !_intListEquals(oldDelegate.data, data) ||
        !_intListEquals(oldDelegate.counts, counts) ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.hoverY != hoverY ||
        oldDelegate.selectedY != selectedY ||
        oldDelegate.maxVal != maxVal ||
        oldDelegate.isDark != isDark ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.tahunLabel != tahunLabel ||
        oldDelegate.focusedSeriesId != focusedSeriesId ||
        !_stringSetEquals(oldDelegate.hiddenSeriesIds, hiddenSeriesIds) ||
        !_trendSeriesListEquals(oldDelegate.seriesList, seriesList);
  }
}

bool _intListEquals(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _stringSetEquals(Set<String>? a, Set<String>? b) {
  if (identical(a, b)) return true;
  final emptyA = a == null || a.isEmpty;
  final emptyB = b == null || b.isEmpty;
  if (emptyA && emptyB) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool _trendSeriesListEquals(
  List<DhkpTrendSeries>? a,
  List<DhkpTrendSeries>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final sa = a[i];
    final sb = b[i];
    if (sa.id != sb.id ||
        sa.label != sb.label ||
        sa.color != sb.color ||
        sa.isPrimary != sb.isPrimary ||
        sa.isDashed != sb.isDashed ||
        !_intListEquals(sa.monthlyNominal, sb.monthlyNominal) ||
        !_intListEquals(sa.monthlyCounts, sb.monthlyCounts)) {
      return false;
    }
  }
  return true;
}

/// Memotong path kurva sesuai progress animasi [0..1] dan mengembalikan posisi ujung penarikan garis.
({Path path, Offset? tip}) _slicePathToProgress(
  Path fullPath,
  double progress,
) {
  final metrics = fullPath.computeMetrics().toList();
  final totalLen = metrics.fold<double>(0.0, (sum, m) => sum + m.length);
  if (totalLen <= 0) return (path: Path(), tip: null);
  var remaining = totalLen * progress;
  final drawnPath = Path();
  Offset? tip;
  for (final metric in metrics) {
    if (remaining <= 0) break;
    if (remaining >= metric.length) {
      drawnPath.addPath(metric.extractPath(0.0, metric.length), Offset.zero);
      tip = metric.getTangentForOffset(metric.length)?.position ?? tip;
      remaining -= metric.length;
    } else {
      drawnPath.addPath(metric.extractPath(0.0, remaining), Offset.zero);
      tip = metric.getTangentForOffset(remaining)?.position ?? tip;
      remaining = 0.0;
    }
  }
  return (path: drawnPath, tip: tip);
}

/// Mengubah path kurva solid menjadi segmen putus-putus untuk seri pembanding historis.
Path _extractDashedPath(
  Path source, {
  double dashLength = 6.0,
  double gapLength = 4.5,
}) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var dist = 0.0;
    while (dist < metric.length) {
      final segEnd = math.min(dist + dashLength, metric.length);
      dashed.addPath(metric.extractPath(dist, segEnd), Offset.zero);
      dist += dashLength + gapLength;
    }
  }
  return dashed;
}

/// Kurva Fritsch-Carlson Monotone Cubic Hermite agar naik-turun mulus tanpa overshoot di baseline 0.
Path _buildMonotoneCubicPath(
  List<Offset> points, {
  required double minY,
  required double maxY,
}) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }

  final n = points.length;
  final dx = List<double>.filled(n - 1, 0.0);
  final slopes = List<double>.filled(n - 1, 0.0);
  for (int i = 0; i < n - 1; i++) {
    final deltaX = points[i + 1].dx - points[i].dx;
    dx[i] = deltaX;
    slopes[i] = deltaX.abs() > 1e-6
        ? (points[i + 1].dy - points[i].dy) / deltaX
        : 0.0;
  }

  final tangents = List<double>.filled(n, 0.0);
  tangents[0] = slopes[0];
  tangents[n - 1] = slopes[n - 2];
  for (int i = 1; i < n - 1; i++) {
    final prev = slopes[i - 1];
    final next = slopes[i];
    if (prev == 0.0 || next == 0.0 || (prev > 0) != (next > 0)) {
      tangents[i] = 0.0;
    } else {
      tangents[i] = (prev + next) * 0.5;
    }
  }

  for (int i = 0; i < n - 1; i++) {
    final s = slopes[i];
    if (s.abs() < 1e-9) {
      tangents[i] = 0.0;
      tangents[i + 1] = 0.0;
    } else {
      final a = tangents[i] / s;
      final b = tangents[i + 1] / s;
      final sq = a * a + b * b;
      if (sq > 9.0) {
        final scale = 3.0 / math.sqrt(sq);
        tangents[i] = scale * a * s;
        tangents[i + 1] = scale * b * s;
      }
    }
  }

  for (int i = 0; i < n - 1; i++) {
    final p0 = points[i];
    final p1 = points[i + 1];
    final h = dx[i];
    final cp1x = p0.dx + h / 3.0;
    final cp1y = (p0.dy + tangents[i] * h / 3.0).clamp(minY, maxY);
    final cp2x = p1.dx - h / 3.0;
    final cp2y = (p1.dy - tangents[i + 1] * h / 3.0).clamp(minY, maxY);
    path.cubicTo(cp1x, cp1y, cp2x, cp2y, p1.dx, p1.dy);
  }
  return path;
}

void _drawDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  double dashLength = 5.0,
  double gapLength = 4.0,
}) {
  final delta = end - start;
  final totalLen = delta.distance;
  if (totalLen <= 0) return;
  final dir = delta / totalLen;
  var dist = 0.0;
  while (dist < totalLen) {
    final segEnd = math.min(dist + dashLength, totalLen);
    canvas.drawLine(start + dir * dist, start + dir * segEnd, paint);
    dist += dashLength + gapLength;
  }
}

void _drawTrendTooltip({
  required Canvas canvas,
  required Offset anchor,
  required String title,
  required String nominalText,
  required String detailText,
  required Color accentColor,
  required double opacity,
  required double minX,
  required double maxX,
  required double minY,
  required double maxY,
}) {
  final titlePainter = TextPainter(
    text: TextSpan(
      text: title,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF94A3B8).withValues(alpha: opacity),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final valPainter = TextPainter(
    text: TextSpan(
      text: nominalText,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Colors.white.withValues(alpha: opacity),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final subPainter = TextPainter(
    text: TextSpan(
      text: detailText,
      style: TextStyle(
        fontSize: 9.0,
        fontWeight: FontWeight.w500,
        color: accentColor.withValues(alpha: 0.9 * opacity),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  const hPad = 10.0;
  const vPad = 6.0;
  final contentW = math.max(
    titlePainter.width,
    math.max(valPainter.width, subPainter.width),
  );
  final pillW = contentW + hPad * 2;
  final pillH =
      titlePainter.height +
      valPainter.height +
      subPainter.height +
      vPad * 2 +
      2;

  final maxLeft = math.max(minX, maxX - pillW);
  final pillX = (anchor.dx - pillW / 2).clamp(minX, maxLeft);

  var pillY = anchor.dy - pillH - 12.0;
  if (pillY < minY) {
    pillY = math.min(maxY - pillH, anchor.dy + 12.0);
  }
  pillY = math.max(minY, pillY);

  final rect = Rect.fromLTWH(pillX, pillY, pillW, pillH);
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

  canvas.drawRRect(
    rrect.shift(const Offset(0, 3)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.22 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawRRect(
    rrect,
    Paint()..color = const Color(0xFF141824).withValues(alpha: 0.95 * opacity),
  );
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = accentColor.withValues(alpha: 0.55 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0,
  );

  var dy = pillY + vPad;
  titlePainter.paint(canvas, Offset(pillX + hPad, dy));
  dy += titlePainter.height + 1;
  valPainter.paint(canvas, Offset(pillX + hPad, dy));
  dy += valPainter.height + 1;
  subPainter.paint(canvas, Offset(pillX + hPad, dy));
}

void _drawMultiSeriesTooltip({
  required Canvas canvas,
  required double guideX,
  required double anchorY,
  required String title,
  required List<DhkpTrendSeries> rows,
  required int monthIndex,
  required String? focusedSeriesId,
  required Color accentColor,
  required double opacity,
  required double minX,
  required double maxX,
  required double minY,
  required double maxY,
  required double chartMidX,
}) {
  const maxRows = 5;
  final visibleRows = rows.take(maxRows).toList();
  final extraCount = rows.length - visibleRows.length;

  final titlePainter = TextPainter(
    text: TextSpan(
      text: title,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF94A3B8).withValues(alpha: opacity),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final rowPainters =
      <({DhkpTrendSeries series, TextPainter label, TextPainter value})>[];

  var maxLabelW = 0.0;
  var maxValW = 0.0;
  for (final s in visibleRows) {
    final nom = monthIndex < s.monthlyNominal.length
        ? s.monthlyNominal[monthIndex]
        : 0;
    final isFocused = focusedSeriesId == s.id;
    final lp = TextPainter(
      text: TextSpan(
        text: s.label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
          color: (isFocused ? Colors.white : const Color(0xFFE2E8F0))
              .withValues(alpha: opacity),
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 105);

    final vp = TextPainter(
      text: TextSpan(
        text: nom > 0 ? formatShortRupiah(nom) : 'Rp 0',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    maxLabelW = math.max(maxLabelW, lp.width);
    maxValW = math.max(maxValW, vp.width);
    rowPainters.add((series: s, label: lp, value: vp));
  }

  TextPainter? extraPainter;
  if (extraCount > 0) {
    extraPainter = TextPainter(
      text: TextSpan(
        text: '+$extraCount lainnya (ketuk legend untuk fokus)',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF94A3B8).withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  const hPad = 10.0;
  const vPad = 7.0;
  const swatchW = 14.0;
  const gapAfterSwatch = 6.0;
  const gapLabelToVal = 12.0;

  final rowsWidth =
      swatchW + gapAfterSwatch + maxLabelW + gapLabelToVal + maxValW;
  final contentW = math.max(
    titlePainter.width,
    math.max(rowsWidth, extraPainter?.width ?? 0.0),
  );
  final availW = math.max(120.0, maxX - minX);
  final pillW = math.min(availW, contentW + hPad * 2);

  var rowsH = 0.0;
  for (final r in rowPainters) {
    rowsH += math.max(r.label.height, r.value.height) + 3.0;
  }
  final pillH =
      titlePainter.height +
      4.0 +
      rowsH +
      (extraPainter != null ? extraPainter.height + 2.0 : 0.0) +
      vPad * 2;

  final maxLeft = math.max(minX, maxX - pillW);
  final preferredX = guideX > chartMidX ? guideX - pillW - 12.0 : guideX + 12.0;
  final pillX = preferredX.clamp(minX, maxLeft);

  var pillY = anchorY - pillH / 2;
  if (pillY < minY) pillY = minY;
  if (pillY + pillH > maxY) pillY = math.max(minY, maxY - pillH);

  final rect = Rect.fromLTWH(pillX, pillY, pillW, pillH);
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

  canvas.drawRRect(
    rrect.shift(const Offset(0, 3)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.25 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );
  canvas.drawRRect(
    rrect,
    Paint()..color = const Color(0xFF141824).withValues(alpha: 0.95 * opacity),
  );
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = accentColor.withValues(alpha: 0.45 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0,
  );

  var dy = pillY + vPad;
  titlePainter.paint(canvas, Offset(pillX + hPad, dy));
  dy += titlePainter.height + 4.0;

  for (final r in rowPainters) {
    final rowH = math.max(r.label.height, r.value.height);
    final midY = dy + rowH / 2;
    final swPaint = Paint()
      ..color = r.series.color.withValues(alpha: opacity)
      ..strokeWidth = r.series.isDashed ? 2.0 : 2.6
      ..strokeCap = StrokeCap.round;
    if (r.series.isDashed) {
      _drawDashedLine(
        canvas,
        Offset(pillX + hPad, midY),
        Offset(pillX + hPad + swatchW, midY),
        swPaint,
        dashLength: 4.0,
        gapLength: 2.5,
      );
    } else {
      canvas.drawLine(
        Offset(pillX + hPad, midY),
        Offset(pillX + hPad + swatchW, midY),
        swPaint,
      );
    }
    r.label.paint(canvas, Offset(pillX + hPad + swatchW + gapAfterSwatch, dy));
    r.value.paint(canvas, Offset(pillX + pillW - hPad - r.value.width, dy));
    dy += rowH + 3.0;
  }

  if (extraPainter != null) {
    extraPainter.paint(canvas, Offset(pillX + hPad, dy + 1.0));
  }
}

/// Widget grafik garis tren bulanan beranimasi halus dari titik awal hingga akhir,
/// mendukung garis tunggal maupun multi-seri perbandingan dengan legend interaktif.
class DhkpTrendLineChart extends StatefulWidget {
  final List<DhkpGroupInfo> monthGroups;
  final int maxMonthVal;
  final bool isDark;
  final String? selectedItemLabel;
  final ValueChanged<String?> onSelectLabel;
  final String? tahun;
  final bool forceCompleteAnimation;
  final List<DhkpTrendSeries>? seriesList;
  final Widget? footerTrailing;

  const DhkpTrendLineChart({
    super.key,
    required this.monthGroups,
    required this.maxMonthVal,
    required this.isDark,
    required this.selectedItemLabel,
    required this.onSelectLabel,
    this.tahun,
    this.forceCompleteAnimation = false,
    this.seriesList,
    this.footerTrailing,
  });

  @override
  State<DhkpTrendLineChart> createState() => _DhkpTrendLineChartState();
}

class _DhkpTrendLineChartState extends State<DhkpTrendLineChart>
    with SingleTickerProviderStateMixin {
  static const _drawDuration = Duration(milliseconds: 1600);

  late AnimationController _controller;
  late Animation<double> _drawAnimation;
  bool _initialized = false;
  int? _hoveredIndex;
  double? _hoveredLocalY;
  double? _selectedLocalY;
  String? _focusedSeriesId;
  String? _hoveredSeriesId;
  final Set<String> _hiddenSeriesIds = {};
  String? _lastDataSignature;

  List<DhkpTrendSeries>? get _customSeries =>
      (widget.seriesList != null && widget.seriesList!.isNotEmpty)
      ? widget.seriesList
      : null;

  String _computeDataSignature() {
    final series = _customSeries;
    if (series != null) {
      final body = series
          .map(
            (s) =>
                '${s.id}:${s.isPrimary}:${s.isDashed}:${s.monthlyNominal.join(",")}',
          )
          .join('|');
      return 'multi|${widget.tahun ?? ""}|$body';
    }
    return 'single|${widget.tahun ?? ""}|${widget.maxMonthVal}|${widget.monthGroups.map((g) => g.lunasNominal).join(",")}';
  }

  @override
  void initState() {
    super.initState();
    _lastDataSignature = _computeDataSignature();
    _controller = AnimationController(vsync: this, duration: _drawDuration);
    _drawAnimation = CurvedAnimation(
      parent: _controller,
      curve: _kSilkySmoothCurve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = AppMotion.isReducedMotion(context);
    _controller.duration = reducedMotion ? Duration.zero : _drawDuration;
    if (!_initialized) {
      _initialized = true;
      if (reducedMotion || widget.forceCompleteAnimation) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void didUpdateWidget(covariant DhkpTrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedItemLabel == null && _selectedLocalY != null) {
      _selectedLocalY = null;
    }

    final validIds =
        _customSeries?.map((s) => s.id).toSet() ?? const <String>{};
    if (_focusedSeriesId != null && !validIds.contains(_focusedSeriesId)) {
      _focusedSeriesId = null;
    }
    if (_hoveredSeriesId != null && !validIds.contains(_hoveredSeriesId)) {
      _hoveredSeriesId = null;
    }
    _hiddenSeriesIds.removeWhere((id) => !validIds.contains(id));

    final newSig = _computeDataSignature();
    final dataChanged =
        _lastDataSignature != null && newSig != _lastDataSignature;
    _lastDataSignature = newSig;

    if (widget.forceCompleteAnimation) {
      _controller.value = 1.0;
      return;
    }

    if (dataChanged) {
      if (AppMotion.isReducedMotion(context)) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? _indexForOffset(Offset localPos, double width, int count) {
    if (count <= 0) return null;
    const leftMargin = 54.0;
    const rightMargin = 16.0;
    if (localPos.dx < leftMargin - 14 ||
        localPos.dx > width - rightMargin + 14) {
      return null;
    }
    final chartW = math.max(0.0, width - leftMargin - rightMargin);
    if (chartW <= 0) return null;
    final slotW = chartW / count;
    final relX = localPos.dx - leftMargin;
    return (relX / slotW).floor().clamp(0, count - 1);
  }

  void _selectIndex(int? idx, {required bool toggleSame, double? pointerY}) {
    if (idx == null || idx < 0 || idx >= widget.monthGroups.length) return;
    final label = idx < DhkpGrafikAnalytics.monthNames.length
        ? DhkpGrafikAnalytics.monthNames[idx]
        : widget.monthGroups[idx].label;
    if (widget.selectedItemLabel == label) {
      if (toggleSame) {
        HapticFeedback.selectionClick();
        setState(() => _selectedLocalY = null);
        widget.onSelectLabel(null);
      } else if (pointerY != null &&
          (_selectedLocalY == null ||
              (pointerY - _selectedLocalY!).abs() >= 2.0)) {
        setState(() => _selectedLocalY = pointerY);
      }
    } else {
      HapticFeedback.selectionClick();
      setState(() => _selectedLocalY = pointerY);
      widget.onSelectLabel(label);
    }
  }

  void _toggleFocusSeries(String id) {
    if (_hiddenSeriesIds.contains(id)) {
      setState(() {
        _hiddenSeriesIds.remove(id);
        _focusedSeriesId = id;
      });
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _focusedSeriesId = _focusedSeriesId == id ? null : id;
    });
  }

  void _toggleHideSeries(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_hiddenSeriesIds.contains(id)) {
        _hiddenSeriesIds.remove(id);
      } else {
        _hiddenSeriesIds.add(id);
        if (_focusedSeriesId == id) _focusedSeriesId = null;
        if (_hoveredSeriesId == id) _hoveredSeriesId = null;
      }
    });
  }

  Widget _buildLegendChip(DhkpTrendSeries s) {
    final isHidden = _hiddenSeriesIds.contains(s.id);
    final isFocused = !isHidden && _focusedSeriesId == s.id;
    final hasAnyFocus = _focusedSeriesId != null;
    final isMuted = isHidden || (hasAnyFocus && !isFocused);

    return MouseRegion(
      onEnter: (_) {
        if (!isHidden && _hoveredSeriesId != s.id) {
          setState(() => _hoveredSeriesId = s.id);
        }
      },
      onExit: (_) {
        if (_hoveredSeriesId == s.id) {
          setState(() => _hoveredSeriesId = null);
        }
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _toggleFocusSeries(s.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isFocused
                  ? s.color.withValues(alpha: widget.isDark ? 0.24 : 0.14)
                  : (widget.isDark
                        ? Colors.white.withValues(alpha: isHidden ? 0.02 : 0.05)
                        : Colors.black.withValues(
                            alpha: isHidden ? 0.02 : 0.04,
                          )),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isFocused
                    ? s.color
                    : (isHidden
                          ? (widget.isDark ? Colors.white12 : Colors.black12)
                          : s.color.withValues(
                              alpha: widget.isDark ? 0.42 : 0.35,
                            )),
                width: isFocused ? 1.4 : 1.0,
              ),
            ),
            child: Opacity(
              opacity: isMuted ? 0.52 : 1.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SeriesLineSwatch(color: s.color, isDashed: s.isDashed),
                  const SizedBox(width: 6),
                  Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
                      decoration: isHidden ? TextDecoration.lineThrough : null,
                      color: widget.isDark
                          ? Colors.grey.shade200
                          : Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    formatShortRupiah(s.totalNominal),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: widget.isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _toggleHideSeries(s.id),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        isHidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 13,
                        color: isHidden
                            ? Colors.grey.shade500
                            : s.color.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const monthNames = DhkpGrafikAnalytics.monthNames;
    final customSeries = _customSeries;
    final monthlyNominal = widget.monthGroups
        .map((g) => g.lunasNominal)
        .toList();
    final monthlyCounts = widget.monthGroups.map((g) => g.lunasNop).toList();
    final hasAnyData = customSeries != null
        ? customSeries.any((s) => s.totalNominal > 0)
        : monthlyNominal.any((v) => v > 0);
    final trendColor = customSeries != null && customSeries.length == 1
        ? customSeries.first.color
        : (widget.isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED));

    final selIndex = widget.selectedItemLabel != null
        ? monthNames.indexOf(widget.selectedItemLabel!)
        : null;
    final effectiveFocus = _focusedSeriesId ?? _hoveredSeriesId;
    final slotCount = widget.monthGroups.isNotEmpty
        ? widget.monthGroups.length
        : (customSeries != null && customSeries.isNotEmpty
              ? customSeries.first.monthlyNominal.length
              : 12);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return RepaintBoundary(
              child: MouseRegion(
                cursor: _hoveredIndex != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onHover: (event) {
                  final idx = _indexForOffset(
                    event.localPosition,
                    w,
                    slotCount,
                  );
                  final nextY = idx != null ? event.localPosition.dy : null;
                  final yMoved = nextY == null
                      ? _hoveredLocalY != null
                      : (_hoveredLocalY == null ||
                            (nextY - _hoveredLocalY!).abs() >= 2.0);
                  if (idx != _hoveredIndex || yMoved) {
                    setState(() {
                      _hoveredIndex = idx;
                      _hoveredLocalY = nextY;
                    });
                  }
                },
                onExit: (_) {
                  if (_hoveredIndex != null || _hoveredLocalY != null) {
                    setState(() {
                      _hoveredIndex = null;
                      _hoveredLocalY = null;
                    });
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _selectIndex(
                    _indexForOffset(d.localPosition, w, slotCount),
                    toggleSame: true,
                    pointerY: d.localPosition.dy,
                  ),
                  onHorizontalDragUpdate: (d) {
                    final idx = _indexForOffset(d.localPosition, w, slotCount);
                    final nextY = idx != null ? d.localPosition.dy : null;
                    final yMoved = nextY == null
                        ? _hoveredLocalY != null
                        : (_hoveredLocalY == null ||
                              (nextY - _hoveredLocalY!).abs() >= 2.0);
                    if (idx != _hoveredIndex || yMoved) {
                      setState(() {
                        _hoveredIndex = idx;
                        _hoveredLocalY = nextY;
                      });
                    }
                    _selectIndex(
                      idx,
                      toggleSame: false,
                      pointerY: d.localPosition.dy,
                    );
                  },
                  onHorizontalDragEnd: (_) {
                    if (_hoveredIndex != null || _hoveredLocalY != null) {
                      setState(() {
                        _hoveredIndex = null;
                        _hoveredLocalY = null;
                      });
                    }
                  },
                  child: SizedBox(
                    height: 236,
                    width: w,
                    child: AnimatedBuilder(
                      animation: _drawAnimation,
                      builder: (context, _) {
                        final p = widget.forceCompleteAnimation
                            ? 1.0
                            : _drawAnimation.value;
                        return CustomPaint(
                          size: Size(w, 236),
                          painter: ComboBarLineTrendPainter(
                            data: monthlyNominal,
                            counts: monthlyCounts,
                            monthNames: monthNames,
                            maxVal: widget.maxMonthVal > 0
                                ? widget.maxMonthVal
                                : 1,
                            progress: p,
                            lineColor: trendColor,
                            isDark: widget.isDark,
                            selectedIndex: selIndex != null && selIndex >= 0
                                ? selIndex
                                : null,
                            hoveredIndex: _hoveredIndex,
                            hoverY: _hoveredLocalY,
                            selectedY: _selectedLocalY,
                            tahunLabel: widget.tahun,
                            seriesList: customSeries,
                            focusedSeriesId: effectiveFocus,
                            hiddenSeriesIds: _hiddenSeriesIds,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Builder(
            builder: (context) {
              final footerTrailing = widget.footerTrailing;
              Widget buildLegend({required bool alignStart}) {
                if (customSeries != null && customSeries.length > 1) {
                  return Column(
                    crossAxisAlignment: alignStart
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Wrap(
                        alignment: alignStart
                            ? WrapAlignment.start
                            : WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final s in customSeries) _buildLegendChip(s),
                          if (_focusedSeriesId != null ||
                              _hiddenSeriesIds.isNotEmpty)
                            ActionChip(
                              avatar: const Icon(
                                Icons.refresh_rounded,
                                size: 14,
                              ),
                              label: Text(
                                _hiddenSeriesIds.isNotEmpty
                                    ? 'Tampilkan Semua'
                                    : 'Reset Fokus',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _focusedSeriesId = null;
                                  _hiddenSeriesIds.clear();
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ketuk item legend untuk fokus 1 garis • Ikon mata untuk sembunyikan/tampilkan',
                        textAlign: alignStart
                            ? TextAlign.start
                            : TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: widget.isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  );
                }

                return Wrap(
                  alignment: alignStart
                      ? WrapAlignment.start
                      : WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 20,
                          height: 3.2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(trendColor, Colors.white, 0.25)!,
                                trendColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          customSeries != null && customSeries.length == 1
                              ? 'Garis Tren: ${customSeries.first.label} (Jan - Des)'
                              : 'Garis Tren: Penerimaan Bulanan (Jan - Des)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    if (hasAnyData)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (int i = 0; i < 3; i++)
                                  Container(
                                    width: 4,
                                    height: 1.5,
                                    color: trendColor.withValues(alpha: 0.65),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Rata-rata Bulanan',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              }

              if (footerTrailing == null) {
                return buildLegend(alignStart: false);
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 520) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: buildLegend(alignStart: true)),
                        const SizedBox(width: 12),
                        footerTrailing,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: buildLegend(alignStart: false)),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: footerTrailing,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeriesLineSwatch extends StatelessWidget {
  final Color color;
  final bool isDashed;

  const _SeriesLineSwatch({required this.color, required this.isDashed});

  @override
  Widget build(BuildContext context) {
    if (!isDashed) {
      return Container(
        width: 14,
        height: 3.0,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return SizedBox(
      width: 15,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (int i = 0; i < 3; i++)
            Container(
              width: 3.8,
              height: 2.2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Helper pembangun widget grafik garis tren bulanan halus (Jan–Des)
/// yang mendukung perbandingan multi-seri.
Widget renderDhkpComboBarLineTrend({
  required List<DhkpGroupInfo> monthGroups,
  required int maxMonthVal,
  required double animationValue,
  required bool isDark,
  required String? selectedItemLabel,
  required ValueChanged<String?> onSelectLabel,
  String? tahun,
  bool forceCompleteAnimation = false,
  List<DhkpTrendSeries>? seriesList,
  Widget? footerTrailing,
}) {
  return DhkpTrendLineChart(
    monthGroups: monthGroups,
    maxMonthVal: maxMonthVal,
    isDark: isDark,
    selectedItemLabel: selectedItemLabel,
    onSelectLabel: onSelectLabel,
    tahun: tahun,
    forceCompleteAnimation: forceCompleteAnimation,
    seriesList: seriesList,
    footerTrailing: footerTrailing,
  );
}

/// Fallback kompatibilitas nama lama (deprecated alias)
@Deprecated(
  'Gunakan ComboBarLineTrendPainter yang merender grafik garis tren halus',
)
typedef GrassLineAreaPainter = ComboBarLineTrendPainter;
