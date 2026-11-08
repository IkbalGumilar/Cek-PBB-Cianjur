import 'package:cek_pbb_app/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SplashScreen Widget Tests', () {
    testWidgets('renders all splash branding elements and text', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            nextScreen: Scaffold(body: Text('Next Screen Target')),
            displayDuration: Duration(seconds: 10),
          ),
        ),
      );

      // Verify branding texts
      expect(find.text('Cek PBB Cianjur'), findsOneWidget);
      expect(
        find.text('Layanan Informasi & Pemantauan PBB-P2'),
        findsOneWidget,
      );
      expect(find.text('Kabupaten Cianjur'), findsOneWidget);
      expect(
        find.text('Badan Pendapatan Daerah Kabupaten Cianjur'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Next Screen Target'), findsNothing);
    });

    testWidgets('transitions automatically after displayDuration', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            nextScreen: Scaffold(body: Text('Next Screen Target')),
            displayDuration: Duration(milliseconds: 500),
          ),
        ),
      );

      expect(find.text('Cek PBB Cianjur'), findsOneWidget);
      expect(find.text('Next Screen Target'), findsNothing);

      // Advance clock past displayDuration and animation duration
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Next Screen Target'), findsOneWidget);
    });

    testWidgets('tap on screen skips splash immediately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            nextScreen: Scaffold(body: Text('Next Screen Target')),
            displayDuration: Duration(seconds: 10),
          ),
        ),
      );

      expect(find.text('Next Screen Target'), findsNothing);

      // Tap on the splash screen
      await tester.tap(find.text('Cek PBB Cianjur'));
      await tester.pumpAndSettle();

      expect(find.text('Next Screen Target'), findsOneWidget);
    });

    testWidgets('isPreview pops back when tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SplashScreen(
                          isPreview: true,
                          displayDuration: Duration(seconds: 10),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Splash Preview'),
                ),
              );
            },
          ),
        ),
      );

      // Tap to open preview
      await tester.tap(find.text('Open Splash Preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Cek PBB Cianjur'), findsOneWidget);

      // Tap to dismiss preview
      await tester.tap(find.text('Cek PBB Cianjur'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Open Splash Preview'), findsOneWidget);
    });

    testWidgets('routes to StartupSetupScreen on first run when setup is not completed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            displayDuration: Duration(milliseconds: 100),
          ),
        ),
      );

      expect(find.text('Cek PBB Cianjur'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Should land on StartupSetupScreen greeting
      expect(find.text('Sampurasun!'), findsOneWidget);
      expect(find.text('Selamat Datang di Cek PBB Cianjur'), findsOneWidget);
    });
  });
}
