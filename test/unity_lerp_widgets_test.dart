import 'package:cek_pbb_app/unity_lerp_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mathf.Lerp Unit Tests', () {
    test('unityLerp menginterpolasi nilai linier secara matematis presisi', () {
      // t = 0.0 -> a
      expect(unityLerp(0, 100, 0.0), 0.0);
      expect(unityLerp(40, 80, 0.0), 40.0);

      // t = 0.5 -> nilai tengah
      expect(unityLerp(0, 100, 0.5), 50.0);
      expect(unityLerp(20, 60, 0.5), 40.0);

      // t = 1.0 -> b
      expect(unityLerp(0, 100, 1.0), 100.0);
      expect(unityLerp(50, 200, 1.0), 200.0);

      // Nilai turun (a > b)
      expect(unityLerp(100, 0, 0.25), 75.0);
      expect(unityLerp(100, 0, 0.5), 50.0);
      expect(unityLerp(100, 0, 1.0), 0.0);
    });
  });

  group('LerpAnimatedCounter Widget Tests', () {
    testWidgets('menggelindingkan angka dari nilai awal ke target dengan Lerp', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LerpAnimatedCounter(
              value: 100,
              duration: Duration(milliseconds: 300),
            ),
          ),
        ),
      );

      // Awal frame
      await tester.pump();

      // Di tengah-tengah durasi animasi (150ms)
      await tester.pump(const Duration(milliseconds: 150));
      // Nilai harus sedang bertransisi di antara 0 dan 100
      final textFinder = find.byType(Text);
      expect(textFinder, findsOneWidget);
      final textMiddle = tester.widget<Text>(textFinder).data!;
      final numMiddle = int.parse(textMiddle);
      expect(numMiddle, greaterThan(0));
      expect(numMiddle, lessThan(100));

      // Tunggu hingga selesai
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('memperbarui angka saat widget di-rebuild dengan nilai baru', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LerpAnimatedCounter(
              value: 50,
              duration: Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);

      // Rebuild dengan nilai 250
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LerpAnimatedCounter(
              value: 250,
              duration: Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final textMiddle = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(textMiddle, greaterThan(50));
      expect(textMiddle, lessThan(250));

      await tester.pumpAndSettle();
      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('mendukung custom formatter (misal mata uang / unit)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LerpAnimatedCounter(
              value: 5,
              duration: const Duration(milliseconds: 100),
              formatter: (v) => 'Sisa: ${v.round()} NOP',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sisa: 5 NOP'), findsOneWidget);
    });
  });

  group('LerpAnimatedProgress Widget Tests', () {
    testWidgets('mentransisikan progress bar secara halus', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LerpAnimatedProgress(
              value: 0.8,
              duration: Duration(milliseconds: 200),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, greaterThan(0.0));
      expect(indicator.value, lessThan(0.8));

      await tester.pumpAndSettle();
      final indicatorFinal = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicatorFinal.value, 0.8);
    });
  });

  group('LerpPressable Widget Tests', () {
    testWidgets('mengecilkan skala pada tap down dan memantul kembali serta memanggil onTap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LerpPressable(
                onTap: () => tapped = true,
                pressedScale: 0.9,
                duration: const Duration(milliseconds: 100),
                child: const SizedBox(
                  width: 100,
                  height: 50,
                  child: Text('Click Me'),
                ),
              ),
            ),
          ),
        ),
      );

      final targetFinder = find.text('Click Me');
      expect(targetFinder, findsOneWidget);

      // Simulasikan gesture tekan (tap down)
      final gesture = await tester.startGesture(tester.getCenter(targetFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final transformFinder = find.descendant(
        of: find.byType(LerpPressable),
        matching: find.byType(Transform),
      );

      // Verifikasi scale X berkurang (kurang dari 1.0)
      final transformDown = tester.widget<Transform>(transformFinder);
      final scaleDown = transformDown.transform.entry(0, 0);
      expect(scaleDown, lessThan(1.0));

      // Lepaskan gesture (tap up)
      await gesture.up();
      await tester.pumpAndSettle();

      // Verifikasi callback onTap terpanggil dan scale kembali ke 1.0
      expect(tapped, isTrue);
      final transformUp = tester.widget<Transform>(transformFinder);
      expect(transformUp.transform.entry(0, 0), closeTo(1.0, 0.001));
    });
  });
}
