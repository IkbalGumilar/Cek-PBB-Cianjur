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

  group('SettingsScreen Theme Section UI', () {
    testWidgets(
      'menampilkan dropdown tema, switch Material You, dan slider RGB saat Material You didukung dan nonaktif',
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

        // Cek judul tema & tampilan
        expect(find.text('Tema & Tampilan'), findsOneWidget);

        // Cek dropdown mode tema
        expect(find.text('Mode Tema'), findsOneWidget);
        expect(find.text('Ikuti Sistem'), findsOneWidget);

        // Cek switch Material You tampil
        expect(find.text('Warna Dinamis (Material You)'), findsOneWidget);
        expect(find.byType(Switch), findsOneWidget);

        // Cek bagian Aksen Warna & RGB tampil
        expect(find.text('Aksen Warna (RGB)'), findsOneWidget);
        expect(find.text('#2E7D32'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(3)); // R, G, B slider

        controller.dispose();
      },
    );

    testWidgets(
      'menyembunyikan opsi Material You saat perangkat/Android tidak mendukung',
      (tester) async {
        final controller = ThemeController();

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              themeController: controller,
              isMaterialYouSupported: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch Material You tidak boleh muncul
        expect(find.text('Warna Dinamis (Material You)'), findsNothing);
        expect(find.byType(Switch), findsNothing);

        // Bagian Aksen Warna & RGB tetap langsung tampil
        expect(find.text('Aksen Warna (RGB)'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(3));

        controller.dispose();
      },
    );

    testWidgets(
      'menyembunyikan slider RGB saat Material You didukung dan diaktifkan',
      (tester) async {
        final controller = ThemeController();
        await controller.setUseMaterialYou(true);

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              themeController: controller,
              isMaterialYouSupported: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch Material You tampil
        expect(find.text('Warna Dinamis (Material You)'), findsOneWidget);
        expect(find.byType(Switch), findsOneWidget);

        // Bagian Aksen Warna & slider tersembunyi
        expect(find.text('Aksen Warna (RGB)'), findsNothing);
        expect(find.byType(Slider), findsNothing);

        // Saat switch dimatikan, opsi aksen warna muncul
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(find.text('Aksen Warna (RGB)'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(3));

        controller.dispose();
      },
    );

    testWidgets(
      'animasi Lerp (Linear Interpolation) ala Unity mentransisikan nilai slider dengan halus saat memilih preset',
      (tester) async {
        final controller = ThemeController();
        // Awal: Hijau PBB #2E7D32 -> R: 46, G: 125, B: 50
        await controller.setAccentColor(const Color(0xFF2E7D32));

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              themeController: controller,
              isMaterialYouSupported: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Target: Biru Cianjur 0xFF1565C0 -> R: 21, G: 101, B: 192 (Preset index 1)
        final bluePresetFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFF1565C0),
        );
        expect(bluePresetFinder, findsOneWidget);

        // Tap preset biru
        await tester.tap(bluePresetFinder);
        await tester.pump(); // dispatch tap event
        await tester.pump(const Duration(milliseconds: 190)); // Maju 190ms (setengah durasi animasi 380ms)

        // Nilai R harus sedang bertransisi antara 46 dan 21
        final rSlider = tester.widget<Slider>(find.byType(Slider).first);
        expect(rSlider.value, lessThan(46));
        expect(rSlider.value, greaterThan(21));

        // Tunggu animasi lerp selesai
        await tester.pumpAndSettle();

        // Cek nilai akhir sudah mencapai target Biru Cianjur
        expect(controller.accentColor, const Color(0xFF1565C0));
        final finalRSlider = tester.widget<Slider>(find.byType(Slider).first);
        expect(finalRSlider.value.round(), 21);

        controller.dispose();
      },
    );
  });
}
