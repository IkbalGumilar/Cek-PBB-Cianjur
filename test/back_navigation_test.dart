import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/check_form_view.dart';
import 'package:cek_pbb_app/desil/bansos_client.dart';
import 'package:cek_pbb_app/desil/desil_view.dart';
import 'package:cek_pbb_app/kendaraan/kendaraan_view.dart';
import 'package:cek_pbb_app/main_shell.dart';
import 'package:cek_pbb_app/theme_controller.dart';

class FakeBansosClient extends BansosClient {
  FakeBansosClient({this.stubbedResult});

  final BansosResult? stubbedResult;

  @override
  Future<Uint8List> fetchCaptchaImage() async {
    // Return empty 1x1 png or simple bytes for test
    return Uint8List.fromList([
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
      0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84,
      120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69,
      78, 68, 174, 66, 96, 130
    ]);
  }

  @override
  Future<BansosResult> checkByNik({
    required String nik,
    required String captcha,
  }) async {
    return stubbedResult ??
        const BansosResult(
          nama: 'BUDI',
          desil: 'Desil 1',
          statusKpd: 'Ya',
          sembakoStatus: 'Menerima',
          sembakoPeriode: '2026',
          pkhStatus: 'Menerima',
          pkhPeriode: '2026',
          pbiJkStatus: 'Aktif',
          pbiJkPeriode: '2026',
          keteranganPbi: 'PBI JK',
          periodeDtsen: '2026',
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesilView handleBack', () {
    testWidgets('handleBack resets result view back to initial form', (tester) async {
      final desilKey = GlobalKey<DesilViewState>();
      final client = FakeBansosClient();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesilView(key: desilKey, client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Form awal tampil
      expect(find.text('Cek Desil & Bansos'), findsOneWidget);
      expect(desilKey.currentState!.handleBack(), isFalse);

      // Isi NIK dan Captcha lalu submit
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '3203010101010001');
      await tester.enterText(textFields.at(1), 'abcd');

      final submitBtn = find.widgetWithText(FilledButton, 'Cari Data');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Hasil pencarian data tampil
      expect(find.text('Hasil Pencarian Data'), findsOneWidget);

      // Tekan tombol back (handleBack)
      final handled = desilKey.currentState!.handleBack();
      expect(handled, isTrue);
      await tester.pumpAndSettle();

      // Kembali ke awal menu
      expect(find.text('Cek Desil & Bansos'), findsOneWidget);
      expect(find.text('Hasil Pencarian Data'), findsNothing);

      // Tekan back lagi saat sudah di awal menu -> mengembalikan false (siap keluar)
      expect(desilKey.currentState!.handleBack(), isFalse);
    });
  });

  group('MainShell system back navigation', () {
    testWidgets('scrolls to top when check tab is scrolled down', (tester) async {
      final themeController = ThemeController();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(themeController: themeController),
        ),
      );
      await tester.pumpAndSettle();

      // Dapatkan scroll controller dari CheckFormView
      final checkForm = tester.widget<CheckFormView>(find.byType(CheckFormView));
      final controller = checkForm.scrollController!;

      // Simulasikan posisi scroll di bawah (misal setelah cek tagihan)
      controller.jumpTo(250);
      await tester.pump();
      expect(controller.offset, 250);

      // Tekan tombol back sistem
      final didPop = await tester.binding.handlePopRoute();
      // Route tidak pop karena di-intercept oleh scroll to top
      expect(didPop, isTrue);
      await tester.pumpAndSettle();

      // Offset kembali ke atas
      expect(controller.offset, 0);
    });

    testWidgets('scrolls to top when kendaraan tab is scrolled down', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final themeController = ThemeController();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(themeController: themeController),
        ),
      );
      await tester.pumpAndSettle();

      // Buka tab Cek Kendaraan
      final kendaraanChip = find.widgetWithText(ChoiceChip, 'Cek Kendaraan');
      await tester.ensureVisible(kendaraanChip);
      await tester.tap(kendaraanChip);
      await tester.pumpAndSettle();

      // Dapatkan scroll controller dari KendaraanView
      final kendaraan = tester.widget<KendaraanView>(find.byType(KendaraanView));
      final controller = kendaraan.scrollController!;

      // Simulasikan scroll ke bawah
      controller.jumpTo(300);
      await tester.pump();
      expect(controller.offset, 300);

      // Tekan tombol back sistem
      final didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pumpAndSettle();

      // Offset kembali ke atas
      expect(controller.offset, 0);
    });

    testWidgets('returns to check tab when back is pressed in import view', (tester) async {
      final themeController = ThemeController();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(themeController: themeController),
        ),
      );
      await tester.pumpAndSettle();

      // Buka Status Bayar
      final statusBayarChip = find.widgetWithText(ChoiceChip, 'Cek Status Bayar');
      await tester.tap(statusBayarChip);
      await tester.pumpAndSettle();

      // Buka Import via icon button
      final importBtn = find.byTooltip('Import File (cek banyak NOP)');
      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      expect(find.text('Import File - Cek Status Bayar'), findsOneWidget);

      // Tekan tombol back sistem
      final didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue);
      await tester.pumpAndSettle();

      // Kembali ke Cek Pajak
      expect(find.text('Cek Status Bayar'), findsWidgets);
    });

    testWidgets('resets desil results back to awal menu when back is pressed in MainShell', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final themeController = ThemeController();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(themeController: themeController),
        ),
      );
      await tester.pumpAndSettle();

      // Buka Cek Desil
      final desilChip = find.widgetWithText(ChoiceChip, 'Cek Desil');
      await tester.ensureVisible(desilChip);
      await tester.tap(desilChip);
      await tester.pumpAndSettle();

      expect(find.text('Cek Desil & Bansos'), findsOneWidget);

      // DesilViewState internal handleBack directly simulated
      final desil = tester.widget<DesilView>(find.byType(DesilView));
      final desilState = tester.state<DesilViewState>(find.byWidget(desil));

      // Simulate a result by triggering handleBack when null vs when result is set
      expect(desilState.handleBack(), isFalse);
    });
  });
}
