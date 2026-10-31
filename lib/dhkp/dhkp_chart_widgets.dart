import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dhkp_grafik_analytics.dart';

Widget buildDhkpStatRow(List<DhkpStatItem> items, bool isDark) {
  return Row(
    children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: items[i].color.withValues(alpha: isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: items[i].color.withValues(alpha: isDark ? 0.35 : 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      items[i].icon,
                      size: 14,
                      color: items[i].color.shade700,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: items[i].color.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  items[i].value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : items[i].color.shade900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  items[i].sub,
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
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
}) {
  final effectiveMax = maxVal > 0 ? maxVal : 1.0;
  return SizedBox(
    height: 230,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final isScrollable = groups.length > 7;
        final content = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final g in groups) ...[
              () {
                final isSelected = selectedItemLabel == g.label;
                final itemWidget = InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelectLabel(isSelected ? null : g.label);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: isScrollable
                        ? math.max(64.0, constraints.maxWidth / 7.0)
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color1.withValues(alpha: isDark ? 0.2 : 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: color1, width: 1.2)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          topLabelExtractor(g),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : color2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subLabelExtractor(g).isNotEmpty)
                          Text(
                            subLabelExtractor(g),
                            style: TextStyle(
                              fontSize: 8.5,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final val = valueExtractor(g);
                                final heightRatio = (val / effectiveMax).clamp(
                                  0.0,
                                  1.0,
                                );
                                final barHeight = math.max(
                                  4.0,
                                  c.maxHeight * heightRatio * animationValue,
                                );

                                return Container(
                                  width: isScrollable ? 26 : 28,
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [color1, color2],
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color2.withValues(
                                          alpha: isSelected ? 0.45 : 0.22,
                                        ),
                                        blurRadius: isSelected ? 6 : 3,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          g.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected ? color1 : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );

                if (!isScrollable) {
                  return Expanded(child: itemWidget);
                }
                return itemWidget;
              }(),
            ],
          ],
        );

        if (isScrollable) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: content,
          );
        }
        return content;
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
}) {
  final effectiveMax = maxVal > 0 ? maxVal : 1.0;
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
                                  widthRatio *
                                  animationValue;
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
                            labelRight(g),
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
}) {
  if (slices.isEmpty) {
    return const SizedBox(
      height: 150,
      child: Center(child: Text('Belum ada data untuk ditampilkan.')),
    );
  }

  final selectedSlice = slices
      .where((s) => s.label == selectedItemLabel)
      .firstOrNull;
  final activeCenterLabel = selectedSlice != null
      ? '${(selectedSlice.ratio * 100).toStringAsFixed(1)}%'
      : centerLabel;
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
                        '${(s.ratio * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${formatShortRupiah(s.nominal.toInt())})',
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
}) {
  final safePct = achievedPct.clamp(0.0, 100.0);
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
                    centerLabel,
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
              pct: '${safePct.toStringAsFixed(1)}%',
              desc: 'Sudah lunas dibayarkan',
              isDark: isDark,
              selectedItemLabel: selectedItemLabel,
              onSelectLabel: onSelectLabel,
            ),
            const SizedBox(height: 12),
            _buildTwoSliceLegend(
              color: remainingColor,
              label: remainingLabel,
              pct: '${(100.0 - safePct).toStringAsFixed(1)}%',
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

class GrassLineAreaPainter extends CustomPainter {
  final List<int> data;
  final int maxVal;
  final double progress;
  final Color lineColor;
  final bool isDark;
  final int? selectedIndex;

  GrassLineAreaPainter({
    required this.data,
    required this.maxVal,
    required this.progress,
    required this.lineColor,
    required this.isDark,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final n = data.length;
    final w = size.width;
    final h = size.height;
    final stepX = w / (n - 1);

    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final ratio = maxVal > 0 ? (data[i] / maxVal) : 0.0;
      final y = h - (ratio * h * 0.85 * progress) - 8;
      points.add(Offset(x, y));
    }

    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.black12
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 3; i++) {
      final gy = h * (i / 4);
      canvas.drawLine(Offset(0, gy), Offset(w, gy), gridPaint);
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cpX = (p0.dx + p1.dx) / 2;
      path.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.40 * progress),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Garis pandu & sorotan khusus saat salah satu bulan disentuh
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final sp = points[selectedIndex!];
      final guidePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(sp.dx, 0), Offset(sp.dx, h), guidePaint);

      final haloPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(sp, 11.0, haloPaint);
    }

    final dotPaint = Paint()..color = lineColor;
    final dotInner = Paint()..color = isDark ? Colors.black : Colors.white;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isPtSelected = selectedIndex == i;
      final outerR = isPtSelected ? 6.0 : 4.0;
      final innerR = isPtSelected ? 3.0 : 2.0;
      canvas.drawCircle(
        p,
        outerR,
        isPtSelected ? (Paint()..color = Colors.amber.shade400) : dotPaint,
      );
      canvas.drawCircle(p, innerR, dotInner);
    }
  }

  @override
  bool shouldRepaint(covariant GrassLineAreaPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.data != data ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
