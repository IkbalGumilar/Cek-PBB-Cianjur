import 'package:cek_pbb_app/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StartupSetupScreen Animated Wizard Tests', () {
    testWidgets(
      'guides user step-by-step requiring wilayah and allowing dhkp to be skipped',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: StartupSetupScreen(isStandaloneSettings: false),
          ),
        );
        await tester.pumpAndSettle();

        // Step 1: Greeting / Sapaan
        expect(find.text('Sampurasun!'), findsOneWidget);
        expect(find.text('Selamat Datang di Cek PBB Cianjur'), findsOneWidget);
        expect(
          find.text('Multi-Desa & Multi-Kecamatan (32 Kecamatan)'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('btn_mulai_wizard')), findsOneWidget);

        // Verify no default button on Step 1
        expect(find.textContaining('Gunakan Data Default'), findsNothing);

        // Advance to Step 2: Wilayah Kerja
        await tester.tap(find.byKey(const ValueKey('btn_mulai_wizard')));
        await tester.pumpAndSettle();

        expect(find.text('1. Identitas Wilayah Administratif'), findsOneWidget);

        // Next button is disabled initially because wilayah is mandatory
        final nextBtn = tester.widget<FilledButton>(
          find.byKey(const ValueKey('btn_lanjut_ke_dhkp')),
        );
        expect(nextBtn.onPressed, isNull);

        // Select Kecamatan: AGRABINTA
        await tester.tap(find.byKey(const ValueKey('dropdown_kecamatan')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kec. AGRABINTA (010)').last);
        await tester.pumpAndSettle();

        // Select Desa: AGRABINTA (001)
        await tester.tap(find.byKey(const ValueKey('dropdown_desa_010')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Desa AGRABINTA (001)').last);
        await tester.pumpAndSettle();

        // Verify prefix 3205010001
        expect(find.textContaining('3205010001'), findsOneWidget);

        // Next button is now enabled
        await tester.tap(find.byKey(const ValueKey('btn_lanjut_ke_dhkp')));
        await tester.pumpAndSettle();

        // Step 3: Data Master DHKP
        expect(
          find.text('2. Data Master DHKP (Ketetapan SPPT)'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('btn_simpan_selesai')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('btn_lewati_dhkp')), findsOneWidget);
        expect(find.text('Lewati Langkah Ini & Selesaikan'), findsOneWidget);
        expect(find.textContaining('Gunakan Data Default'), findsNothing);

        // Tap Lewati Langkah Ini & Selesaikan
        await tester.tap(find.byKey(const ValueKey('btn_lewati_dhkp')));
        await tester.pumpAndSettle();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('startup_setup_completed'), isTrue);
        expect(prefs.getString('startup_desa_name'), equals('AGRABINTA'));
        expect(prefs.getString('startup_kec_code'), equals('010'));
        expect(prefs.getString('startup_kel_code'), equals('001'));
      },
    );

    testWidgets('allows manual custom desa code entry', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(home: StartupSetupScreen(isStandaloneSettings: true)),
      );
      await tester.pumpAndSettle();

      // Select Kecamatan: AGRABINTA
      await tester.tap(find.byKey(const ValueKey('dropdown_kecamatan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kec. AGRABINTA (010)').last);
      await tester.pumpAndSettle();

      // Select Custom
      await tester.tap(find.byKey(const ValueKey('dropdown_desa_010')));
      await tester.pumpAndSettle();

      final customOption = find.text('Lainnya / Masukkan Kode Manual').last;
      await tester.tap(customOption);
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(
        TextFormField,
        'Nama Desa / Kelurahan Manual',
      );
      await tester.enterText(nameField, 'DESA BARU');

      final codeField = find.widgetWithText(
        TextFormField,
        'Kode Desa (3 Digit)',
      );
      await tester.enterText(codeField, '088');
      await tester.pumpAndSettle();

      expect(find.textContaining('3205010088'), findsOneWidget);
    });
  });
}
