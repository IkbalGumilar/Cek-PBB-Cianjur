import 'package:cek_pbb_app/nop_helper.dart';
import 'package:cek_pbb_app/settings/wilayah_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetNopPrefix();
  });

  group('WilayahSettingsScreen Tests', () {
    testWidgets('renders current active wilayah and proper settings fields without wizard/reset elements', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: WilayahSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and labels
      expect(find.text('Wilayah Kerja & Profil Desa'), findsOneWidget);
      expect(find.text('Wilayah Aktif Saat Ini'), findsOneWidget);
      expect(find.textContaining('MANDE'), findsWidgets);
      expect(find.textContaining('BOBOJONG'), findsWidgets);
      expect(find.textContaining('32.05.200.004'), findsWidgets);

      // Verify form elements exist
      expect(find.byKey(const ValueKey('settings_dropdown_kecamatan')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_dropdown_desa_200')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_simpan_wilayah_settings')), findsOneWidget);

      // Verify it does NOT have setup wizard or DHKP upload elements
      expect(find.text('Sampurasun!'), findsNothing);
      expect(find.text('Langkah 1 dari 2'), findsNothing);
      expect(find.text('Langkah 2 dari 2'), findsNothing);
      expect(find.textContaining('Pilih Berkas DHKP'), findsNothing);
      expect(find.textContaining('Reset Aplikasi'), findsNothing);
    });

    testWidgets('saving updates activeWilayah and SharedPreferences', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WilayahSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Simpan button
      await tester.tap(find.byKey(const ValueKey('btn_simpan_wilayah_settings')));
      await tester.pumpAndSettle();

      // Verify saved in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('startup_kec_code'), '200');
      expect(prefs.getString('startup_desa_name'), 'BOBOJONG');
      expect(prefs.getString('startup_kel_code'), '004');
    });
  });
}
