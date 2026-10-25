import 'package:cek_pbb_app/settings_screen.dart';
import 'package:cek_pbb_app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeController', () {
    test('nilai default controller sesuai spesifikasi', () {
      final controller = ThemeController();
      expect(controller.mode, AppThemeMode.system);
      expect(controller.accentColor, ThemeController.defaultAccentColor);
      expect(controller.useMaterialYou, false);
      controller.dispose();
    });

    test('setMode mengubah mode dan tersimpan di SharedPreferences', () async {
      final controller = ThemeController();
      await controller.setMode(AppThemeMode.amoled);
      expect(controller.mode, AppThemeMode.amoled);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'amoled');
      controller.dispose();
    });

    test('setAccentColor mengubah warna dan tersimpan di SharedPreferences', () async {
      final controller = ThemeController();
      const testColor = Color(0xFF1565C0);
      await controller.setAccentColor(testColor);
      expect(controller.accentColor, testColor);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('theme_accent_color'), testColor.toARGB32());
      controller.dispose();
    });

    test('setUseMaterialYou mengubah status Material You', () async {
      final controller = ThemeController();
      await controller.setUseMaterialYou(true);
      expect(controller.useMaterialYou, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('theme_material_you'), true);
      controller.dispose();
    });

    test('resetToDefault mengembalikan aksen ke hijau PBB dan Material You nonaktif', () async {
      final controller = ThemeController();
      await controller.setAccentColor(const Color(0xFFE53935));
      await controller.setUseMaterialYou(true);

      await controller.resetToDefault();
      expect(controller.accentColor, ThemeController.defaultAccentColor);
      expect(controller.useMaterialYou, false);
      controller.dispose();
    });
  });

  group('SettingsScreen & ThemeSettingsScreen UI', () {
    testWidgets(
      'SettingsScreen membuka menu Tema & Tampilan terpisah dengan dropdown tema, switch wallpaper, dan slider warna',
      (tester) async {
        final controller = ThemeController();

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              themeController: controller,
              isMaterialYouSupported: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Cek kartu menu di SettingsScreen
        expect(find.text('Tema & Tampilan'), findsOneWidget);
        expect(find.text('Keamanan Aplikasi'), findsOneWidget);
        expect(find.text('Pencadangan Data'), findsOneWidget);
        expect(find.text('Tentang & Bagikan Aplikasi'), findsOneWidget);

        // Buka menu Tema & Tampilan
        await tester.tap(find.text('Tema & Tampilan'));
        await tester.pumpAndSettle();

        // Cek dropdown mode tema
        expect(find.text('Mode Tema'), findsOneWidget);
        expect(find.text('Ikuti Sistem'), findsOneWidget);

        // Cek switch Ikuti Warna Wallpaper tampil
        expect(
          find.widgetWithText(SwitchListTile, 'Ikuti Warna Wallpaper'),
          findsOneWidget,
        );

        // Cek bagian Warna Aplikasi & slider tampil
        expect(find.text('Warna Aplikasi'), findsOneWidget);
        expect(find.text('#2E7D32'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(3));

        controller.dispose();
      },
    );

    testWidgets(
      'menyembunyikan opsi Ikuti Warna Wallpaper saat perangkat tidak mendukung',
      (tester) async {
        final controller = ThemeController();

        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSettingsScreen(
              themeController: controller,
              isMaterialYouSupported: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(SwitchListTile, 'Ikuti Warna Wallpaper'),
          findsNothing,
        );

        expect(find.text('Warna Aplikasi'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(3));

        controller.dispose();
      },
    );

    testWidgets(
      'menyembunyikan slider warna saat Ikuti Warna Wallpaper diaktifkan',
      (tester) async {
        final controller = ThemeController();
        await controller.setUseMaterialYou(true);

        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSettingsScreen(
              themeController: controller,
              isMaterialYouSupported: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final wallpaperTile = find.widgetWithText(
          SwitchListTile,
          'Ikuti Warna Wallpaper',
        );
        expect(wallpaperTile, findsOneWidget);

        // Slider dan pilihan warna sendiri tersembunyi
        expect(find.text('Atur Warna Sendiri'), findsNothing);
        expect(find.byType(Slider), findsNothing);

        // Saat switch dimatikan, opsi warna muncul
        await tester.tap(wallpaperTile);
        await tester.pumpAndSettle();

        expect(find.text('Atur Warna Sendiri'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(3));

        controller.dispose();
      },
    );

    testWidgets(
      'animasi Lerp mentransisikan nilai slider dengan halus saat memilih preset',
      (tester) async {
        final controller = ThemeController();
        await controller.setAccentColor(const Color(0xFF2E7D32));

        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSettingsScreen(
              themeController: controller,
              isMaterialYouSupported: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final bluePresetFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFF1565C0),
        );
        expect(bluePresetFinder, findsOneWidget);

        await tester.tap(bluePresetFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 190));

        final rSlider = tester.widget<Slider>(find.byType(Slider).first);
        expect(rSlider.value, lessThan(46));
        expect(rSlider.value, greaterThan(21));

        await tester.pumpAndSettle();

        expect(controller.accentColor, const Color(0xFF1565C0));
        final finalRSlider = tester.widget<Slider>(find.byType(Slider).first);
        expect(finalRSlider.value.round(), 21);

        controller.dispose();
      },
    );
  });
}
