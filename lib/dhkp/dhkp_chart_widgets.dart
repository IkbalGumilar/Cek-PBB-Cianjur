import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
          final isSelected = selectedItemLabel == g.label;
          final val = valueExtractor(g);
          final heightRatio = (val / effectiveMax).clamp(0.0, 1.0);
          final chartHeight = math.max(10.0, 255.0 - topOffset - bottomOffset);
          final barHeight = math.max(
            3.0,
            chartHeight * heightRatio * animationValue,
          );

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
                                        topLabelExtractor(g),
                                        style: const TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                      ),
                                    )
                                  : Text(
                                      topLabelExtractor(g),
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

/// Painter grafik kombinasi Diagram Batang (Histogram) dengan Garis Tren Poligon Puncak
/// (seperti diagram frekuensi / poligon frekuensi pada buku statistik/Brainly).
/// Menggantikan visual kurva rumput khusus untuk Tren Pembayaran.
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

  ComboBarLineTrendPainter({
    required this.data,
    required this.counts,
    required this.monthNames,
    required this.maxVal,
    required this.progress,
    required this.barColor1,
    required this.barColor2,
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

    const leftMargin = 52.0;
    const rightMargin = 16.0;
    const topMargin = 28.0;
    const bottomMargin = 26.0;

    final chartWidth = math.max(0.0, w - leftMargin - rightMargin);
    final chartHeight = math.max(0.0, h - topMargin - bottomMargin);
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final slotWidth = chartWidth / n;
    final barWidth = (slotWidth * 0.58).clamp(10.0, 34.0);
    final effectiveMax = maxVal > 0 ? maxVal : 1;

    // 1. Garis Grid Horizontal & Label Sumbu Y (0 sampai Max)
    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.black12
      ..strokeWidth = 0.8;

    for (int k = 0; k <= 3; k++) {
      final ratio = k / 3.0;
      final gy = topMargin + chartHeight * (1.0 - ratio);
      canvas.drawLine(
        Offset(leftMargin, gy),
        Offset(w - rightMargin, gy),
        gridPaint,
      );

      final val = (effectiveMax * ratio).round();
      final label = k == 0 ? '0' : formatShortRupiah(val);
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 9.0,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftMargin - 6);
      tp.paint(canvas, Offset(leftMargin - 6 - tp.width, gy - tp.height / 2));
    }

    // 2. Hitung Titik Puncak Batang (Peak Points)
    final peakPoints = <Offset>[];
    for (int i = 0; i < n; i++) {
      final centerX = leftMargin + (i + 0.5) * slotWidth;
      final ratio = (data[i] / effectiveMax).clamp(0.0, 1.0);
      final barHeight = ratio * chartHeight * progress;
      final barTop = topMargin + chartHeight - barHeight;
      peakPoints.add(Offset(centerX, barTop));
    }

    // 3. Gambar Diagram Batang (Vertical Bars)
    for (int i = 0; i < n; i++) {
      final isSelected = selectedIndex == i;
      final centerX = peakPoints[i].dx;
      final barTop = peakPoints[i].dy;
      final barBottom = topMargin + chartHeight;
      final left = centerX - barWidth / 2;
      final right = centerX + barWidth / 2;

      if (data[i] > 0) {
        final rrect = RRect.fromRectAndCorners(
          Rect.fromLTRB(left, barTop, right, barBottom),
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
        );

        if (isSelected) {
          final glowPaint = Paint()
            ..color = barColor1.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawRRect(rrect.inflate(2), glowPaint);
        }

        final fillPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isSelected
                ? [barColor1, barColor2]
                : [
                    barColor1.withValues(alpha: isDark ? 0.85 : 0.95),
                    barColor2.withValues(alpha: isDark ? 0.90 : 1.0),
                  ],
          ).createShader(rrect.outerRect);
        canvas.drawRRect(rrect, fillPaint);

        final strokePaint = Paint()
          ..color = isSelected
              ? Colors.amber.shade400
              : (isDark ? Colors.white24 : barColor2.withValues(alpha: 0.4))
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.8 : 0.8;
        canvas.drawRRect(rrect, strokePaint);
      } else {
        // Tanda dasar jika belum ada uang masuk pada bulan tersebut
        final zeroRect = Rect.fromLTRB(left, barBottom - 2, right, barBottom);
        canvas.drawRect(
          zeroRect,
          Paint()..color = isDark ? Colors.white12 : Colors.grey.shade300,
        );
      }
    }

    // 4. Gambar Garis Poligon Puncak Batang (Line connecting top centers - seperti Brainly)
    final linePath = Path()..moveTo(peakPoints.first.dx, peakPoints.first.dy);
    for (int i = 1; i < peakPoints.length; i++) {
      linePath.lineTo(peakPoints[i].dx, peakPoints[i].dy);
    }

    final trendLinePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, trendLinePaint);

    // 5. Gambar Titik Puncak (Vertex Dots) & Panduan Seleksi
    for (int i = 0; i < peakPoints.length; i++) {
      final p = peakPoints[i];
      final isSelected = selectedIndex == i;

      if (isSelected) {
        // Garis pandu vertikal
        final guidePaint = Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1.2;
        canvas.drawLine(
          Offset(p.dx, topMargin),
          Offset(p.dx, topMargin + chartHeight),
          guidePaint,
        );

        // Lingkaran halo luar
        canvas.drawCircle(
          p,
          10.5,
          Paint()..color = lineColor.withValues(alpha: 0.25),
        );
        // Titik terluar
        canvas.drawCircle(p, 5.5, Paint()..color = lineColor);
        // Titik dalam putih
        canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(p, 4.2, Paint()..color = lineColor);
        canvas.drawCircle(
          p,
          2.0,
          Paint()..color = isDark ? Colors.grey.shade900 : Colors.white,
        );
      }
    }

    // 6. Label Sumbu X (Bulan: Jan, Feb, Mar, ...)
    for (int i = 0; i < n; i++) {
      final isSelected = selectedIndex == i;
      final mSpan = TextSpan(
        text: monthNames[i],
        style: TextStyle(
          fontSize: 10.0,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected
              ? lineColor
              : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
        ),
      );
      final mPainter = TextPainter(
        text: mSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      mPainter.paint(
        canvas,
        Offset(
          peakPoints[i].dx - mPainter.width / 2,
          topMargin + chartHeight + 6,
        ),
      );
    }

    // 7. Nilai Nominal di Atas Puncak / Balon Seleksi
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < n) {
      final selP = peakPoints[selectedIndex!];
      final val = data[selectedIndex!];
      final count = counts[selectedIndex!];
      final badgeText = val > 0
          ? 'Rp ${formatShortRupiah(val)} ($count objek)'
          : 'Rp 0 (Belum ada)';

      final bSpan = TextSpan(
        text: badgeText,
        style: const TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
      final bPainter = TextPainter(
        text: bSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeW = bPainter.width + 12;
      final badgeH = bPainter.height + 6;
      final badgeX = (selP.dx - badgeW / 2).clamp(
        leftMargin,
        w - rightMargin - badgeW,
      );
      final badgeY = math.max(2.0, selP.dy - badgeH - 8);

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH),
        const Radius.circular(6),
      );
      canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF0F172A));
      canvas.drawRRect(
        badgeRect,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      bPainter.paint(canvas, Offset(badgeX + 6, badgeY + 3));
    }
  }

  @override
  bool shouldRepaint(covariant ComboBarLineTrendPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.data != data ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.maxVal != maxVal;
  }
}

/// Helper pembangun widget grafik kombinasi batang & garis tren bulanan (Jan–Des)
Widget renderDhkpComboBarLineTrend({
  required List<DhkpGroupInfo> monthGroups,
  required int maxMonthVal,
  required double animationValue,
  required bool isDark,
  required String? selectedItemLabel,
  required ValueChanged<String?> onSelectLabel,
}) {
  const monthNames = DhkpGrafikAnalytics.monthNames;
  final monthlyNominal = monthGroups.map((g) => g.lunasNominal).toList();
  final monthlyCounts = monthGroups.map((g) => g.lunasNop).toList();

  final selIndex = selectedItemLabel != null
      ? monthNames.indexOf(selectedItemLabel)
      : null;

  return Column(
    children: [
      LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          const leftMargin = 52.0;
          const rightMargin = 16.0;
          final chartW = math.max(0.0, w - leftMargin - rightMargin);
          final slotW = monthGroups.isNotEmpty
              ? chartW / monthGroups.length
              : 1.0;

          void onTouch(Offset localPos) {
            if (monthGroups.isEmpty || slotW <= 0) return;
            final relX = localPos.dx - leftMargin;
            final idx = (relX / slotW).floor().clamp(0, monthGroups.length - 1);
            final label = monthNames[idx];
            if (selectedItemLabel != label) {
              HapticFeedback.selectionClick();
              onSelectLabel(label);
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onTouch(d.localPosition),
            onPanUpdate: (d) => onTouch(d.localPosition),
            child: SizedBox(
              height: 220,
              child: CustomPaint(
                size: Size(w, 220),
                painter: ComboBarLineTrendPainter(
                  data: monthlyNominal,
                  counts: monthlyCounts,
                  monthNames: monthNames,
                  maxVal: maxMonthVal > 0 ? maxMonthVal : 1,
                  progress: animationValue,
                  barColor1: isDark
                      ? Colors.blue.shade400
                      : Colors.blue.shade600,
                  barColor2: isDark
                      ? Colors.blue.shade700
                      : Colors.blue.shade900,
                  lineColor: const Color(
                    0xFFDC2626,
                  ), // Garis merah poligon seperti Brainly
                  isDark: isDark,
                  selectedIndex: selIndex != null && selIndex >= 0
                      ? selIndex
                      : null,
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      // Legenda indikator visual seperti gambar Brainly
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 14,
              height: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [Colors.blue.shade400, Colors.blue.shade700]
                      : [Colors.blue.shade600, Colors.blue.shade900],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Batang: Uang Masuk',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Garis: Tren Puncak (Jan - Des)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Fallback kompatibilitas nama lama (deprecated alias)
@Deprecated(
  'Gunakan ComboBarLineTrendPainter yang mengombinasikan batang dan garis poligon',
)
typedef GrassLineAreaPainter = ComboBarLineTrendPainter;
