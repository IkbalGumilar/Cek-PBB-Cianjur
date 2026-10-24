import 'package:cek_pbb_app/app_header.dart';
import 'package:cek_pbb_app/check_mode.dart';
import 'package:cek_pbb_app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeController themeController;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    themeController = ThemeController();
  });

  tearDown(() {
    themeController.dispose();
  });

  Widget buildTestHeader({
    required Color primaryColor,
    required Color onPrimary,
    CheckMode activeMode = CheckMode.tagihan,
    bool desilSelected = false,
    bool kendaraanSelected = false,
    ValueChanged<CheckMode>? onModeChanged,
    VoidCallback? onMonitoringPressed,
    VoidCallback? onDesilPressed,
    VoidCallback? onKendaraanPressed,
  }) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
      ).copyWith(
        primary: primaryColor,
        onPrimary: onPrimary,
      ),
    );

    return MaterialApp(
      theme: theme,
      home: Scaffold(
        appBar: AppHeader(
          activeMode: activeMode,
          onModeChanged: onModeChanged ?? (_) {},
          themeController: themeController,
          onMonitoringPressed: onMonitoringPressed ?? () {},
          onDesilPressed: onDesilPressed ?? () {},
          onKendaraanPressed: onKendaraanPressed ?? () {},
          desilSelected: desilSelected,
          kendaraanSelected: kendaraanSelected,
        ),
      ),
    );
  }

  group('AppHeader Contrast & Theming Tests', () {
    testWidgets(
      'Light mode: chips have clean white background, unselected text is dark ("jika terang jadi gelap")',
      (tester) async {
        const magenta = Color(0xFFE000B0);

        await tester.pumpWidget(
          buildTestHeader(
            primaryColor: magenta,
            onPrimary: Colors.white,
            activeMode: CheckMode.tagihan,
          ),
        );
        await tester.pumpAndSettle();

        final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
        expect(chips.length, 5); // Tagihan, Status Bayar, Monitoring, Kendaraan, Desil

        // 1. Selected chip (Cek Tagihan)
        final selectedChip = chips[0];
        expect(selectedChip.selected, isTrue);

        // Background adalah putih bersih (bukan abu-abu)
        final selectedColor = selectedChip.color?.resolve({WidgetState.selected});
        expect(selectedColor, Colors.white);

        // Teks terpilih memakai warna aksen (magenta) yang kontras di atas putih
        expect(selectedChip.labelStyle?.color, magenta);

        // 2. Unselected chips (Cek Status Bayar, Monitoring, Cek Kendaraan, Cek Desil)
        for (var i = 1; i < chips.length; i++) {
          final unselectedChip = chips[i];
          expect(unselectedChip.selected, isFalse);

          // Background tetap putih bersih (bukan abu-abu)
          final unselectedColor = unselectedChip.color?.resolve({});
          expect(unselectedColor, Colors.white);

          // Teks gelap kontras tinggi (jika terang jadi gelap)
          expect(unselectedChip.labelStyle?.color, const Color(0xFF1F1F1F));
        }
      },
    );

    testWidgets(
      'Dark mode: chips have dark background, unselected text is white ("jika kelam jadi terang")',
      (tester) async {
        const primaryColor = Color(0xFF2E7D32);

        final darkTheme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            brightness: Brightness.dark,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              appBar: AppHeader(
                activeMode: CheckMode.tagihan,
                onModeChanged: (_) {},
                themeController: themeController,
                onMonitoringPressed: () {},
                onDesilPressed: () {},
                onKendaraanPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();

        // Di mode gelap: background gelap/kelam
        for (final chip in chips) {
          final chipColor = chip.color?.resolve({});
          expect(chipColor, const Color(0xFF2C2C2C));
        }

        // Unselected chips: teks terang ("jika kelam jadi terang")
        for (var i = 1; i < chips.length; i++) {
          expect(chips[i].labelStyle?.color, Colors.white);
        }
      },
    );

    testWidgets(
      'Chip callbacks fire accurately when tapped',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        CheckMode? switchedMode;
        var monitoringClicked = false;
        var kendaraanClicked = false;
        var desilClicked = false;

        await tester.pumpWidget(
          buildTestHeader(
            primaryColor: const Color(0xFF2E7D32),
            onPrimary: Colors.white,
            activeMode: CheckMode.tagihan,
            onModeChanged: (m) => switchedMode = m,
            onMonitoringPressed: () => monitoringClicked = true,
            onKendaraanPressed: () => kendaraanClicked = true,
            onDesilPressed: () => desilClicked = true,
          ),
        );
        await tester.pumpAndSettle();

        // Tap "Cek Status Bayar"
        await tester.ensureVisible(find.text('Cek Status Bayar'));
        await tester.tap(find.text('Cek Status Bayar'));
        await tester.pumpAndSettle();
        expect(switchedMode, CheckMode.statusBayar);

        // Tap "Monitoring"
        await tester.ensureVisible(find.text('Monitoring'));
        await tester.tap(find.text('Monitoring'));
        await tester.pumpAndSettle();
        expect(monitoringClicked, isTrue);

        // Tap "Cek Kendaraan"
        await tester.ensureVisible(find.text('Cek Kendaraan'));
        await tester.tap(find.text('Cek Kendaraan'));
        await tester.pumpAndSettle();
        expect(kendaraanClicked, isTrue);

        // Tap "Cek Desil"
        await tester.ensureVisible(find.text('Cek Desil'));
        await tester.tap(find.text('Cek Desil'));
        await tester.pumpAndSettle();
        expect(desilClicked, isTrue);
      },
    );
  });
}
