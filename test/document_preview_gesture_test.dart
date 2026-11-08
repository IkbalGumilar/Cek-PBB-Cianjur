import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cek_pbb_app/document_preview_screen.dart';

void main() {
  group('DesktopPdfScrollPhysics Tests', () {
    test('shouldAcceptUserOffset returns true when Ctrl/Meta is NOT pressed', () {
      const physics = DesktopPdfScrollPhysics();
      // By default in test environment, no keys are pressed
      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 0,
        viewportDimension: 500,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      expect(physics.shouldAcceptUserOffset(metrics), isTrue);
    });

    testWidgets('shouldAcceptUserOffset returns false when Ctrl is pressed', (tester) async {
      const physics = DesktopPdfScrollPhysics();
      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 0,
        viewportDimension: 500,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(physics.shouldAcceptUserOffset(metrics), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(physics.shouldAcceptUserOffset(metrics), isTrue);
    });
  });

  group('PDF Viewer Desktop Gesture & Zoom Tests', () {
    testWidgets(
      'Mouse wheel scroll without Ctrl scrolls document and does not zoom',
      (tester) async {
        final transformController = TransformationController();
        final scrollController = ScrollController();
        bool ctrlPressed = false;

        void handlePointerSignal(PointerSignalEvent event) {
          if (event is PointerScrollEvent && ctrlPressed) {
            final double zoomDelta = -event.scrollDelta.dy;
            final double scaleMultiplier = math.exp(zoomDelta / 300.0);
            final Matrix4 currentMatrix = transformController.value;
            final double currentScale = currentMatrix.getMaxScaleOnAxis();
            final double targetScale = (currentScale * scaleMultiplier).clamp(0.8, 6.0);
            final double factor = targetScale / currentScale;

            final Offset scenePointBefore = transformController.toScene(event.localPosition);
            final Matrix4 scaledMatrix = currentMatrix.clone()..scaleByDouble(factor, factor, 1.0, 1.0);
            transformController.value = scaledMatrix;
            final Offset scenePointAfter = transformController.toScene(event.localPosition);
            final Offset translationDelta = scenePointAfter - scenePointBefore;
            transformController.value = scaledMatrix
              ..translateByDouble(translationDelta.dx, translationDelta.dy, 0.0, 1.0);
          }
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: handlePointerSignal,
                child: InteractiveViewer(
                  transformationController: transformController,
                  scaleFactor: double.maxFinite,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    physics: const DesktopPdfScrollPhysics(),
                    child: Column(
                      children: List.generate(
                        10,
                        (i) => Container(
                          height: 200,
                          width: 400,
                          color: i.isEven ? Colors.blue : Colors.amber,
                          child: Text('Halaman ${i + 1}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(scrollController.offset, 0.0);
        expect(transformController.value.getMaxScaleOnAxis(), 1.0);

        // 1. Normal mouse wheel scroll (wheel down)
        final center = tester.getCenter(find.text('Halaman 1'));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(center));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
        await tester.pump();

        // Must scroll down, but scale must remain 1.0 (no zooming!)
        expect(scrollController.offset, greaterThan(0.0));
        expect(transformController.value.getMaxScaleOnAxis(), 1.0);
        final offsetAfterScroll = scrollController.offset;

        // 2. Ctrl + scroll (wheel up -> zoom in)
        ctrlPressed = true;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -80)));
        await tester.pump();

        // Must zoom in, but scroll offset must remain unchanged!
        expect(transformController.value.getMaxScaleOnAxis(), greaterThan(1.0));
        expect(scrollController.offset, equals(offsetAfterScroll));

        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      },
    );

    testWidgets(
      'InteractiveViewer panEnabled is disabled when scale is 1.0 to prevent jitter',
      (tester) async {
        final isZoomedNotifier = ValueNotifier<bool>(false);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: isZoomedNotifier,
                builder: (context, isZoomed, _) {
                  return InteractiveViewer(
                    boundaryMargin: EdgeInsets.zero,
                    panEnabled: isZoomed,
                    child: Container(
                      width: 300,
                      height: 300,
                      color: Colors.red,
                    ),
                  );
                },
              ),
            ),
          ),
        );

        InteractiveViewer iv = tester.widget(find.byType(InteractiveViewer));
        expect(iv.panEnabled, isFalse);
        expect(iv.boundaryMargin, equals(EdgeInsets.zero));

        // When zoomed, pan is enabled
        isZoomedNotifier.value = true;
        await tester.pump();

        iv = tester.widget(find.byType(InteractiveViewer));
        expect(iv.panEnabled, isTrue);
      },
    );

    testWidgets(
      'Search text highlight renders correctly at scaled coordinates with active and inactive colors',
      (tester) async {
        // Page render size: 400 width x 600 height
        // Normalized bounds: left: 0.1, top: 0.2, width: 0.3, height: 0.05
        const normRect = Rect.fromLTWH(0.1, 0.2, 0.3, 0.05);
        const renderWidth = 400.0;
        const renderHeight = 600.0;

        Widget buildHighlightBox({
          required bool isActive,
        }) {
          final left = normRect.left * renderWidth;
          final top = normRect.top * renderHeight;
          final width = normRect.width * renderWidth;
          final height = normRect.height * renderHeight;

          return Positioned(
            left: left - 2,
            top: top - 1,
            width: width + 4,
            height: height + 2,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.amber.withValues(alpha: 0.65)
                      : Colors.yellow.withValues(alpha: 0.35),
                  border: Border.all(
                    color: isActive ? Colors.deepOrange : Colors.amber.shade700,
                    width: isActive ? 2.0 : 1.0,
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: renderWidth,
                height: renderHeight,
                child: Stack(
                  children: [
                    Container(width: renderWidth, height: renderHeight, color: Colors.white),
                    buildHighlightBox(isActive: false),
                  ],
                ),
              ),
            ),
          ),
        );

        // Verify Positioned dimensions:
        // left: 40 - 2 = 38
        // top: 120 - 1 = 119
        // width: 120 + 4 = 124
        // height: 30 + 2 = 32
        final positionedFinder = find.byType(Positioned);
        expect(positionedFinder, findsOneWidget);
        final Positioned positioned = tester.widget(positionedFinder);
        expect(positioned.left, closeTo(38.0, 0.01));
        expect(positioned.top, closeTo(119.0, 0.01));
        expect(positioned.width, closeTo(124.0, 0.01));
        expect(positioned.height, closeTo(32.0, 0.01));

        // Check border of inactive match
        AnimatedContainer container = tester.widget(find.byType(AnimatedContainer));
        BoxDecoration deco = container.decoration as BoxDecoration;
        expect((deco.border as Border).top.color, Colors.amber.shade700);

        // Check active match
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: renderWidth,
                height: renderHeight,
                child: Stack(
                  children: [
                    Container(width: renderWidth, height: renderHeight, color: Colors.white),
                    buildHighlightBox(isActive: true),
                  ],
                ),
              ),
            ),
          ),
        );

        container = tester.widget(find.byType(AnimatedContainer));
        deco = container.decoration as BoxDecoration;
        expect((deco.border as Border).top.color, Colors.deepOrange);
      },
    );
  });
}
