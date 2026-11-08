import 'package:cek_pbb_app/check_form_view.dart';
import 'package:cek_pbb_app/check_mode.dart';
import 'package:cek_pbb_app/nop_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetNopPrefix();
  });

  group('CheckFormView Quick Wilayah Switcher Tests', () {
    testWidgets('renders active wilayah bar in Cek Tagihan and switches desa via bottom sheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckFormView(
              mode: CheckMode.tagihan,
              onImportPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify active wilayah bar renders default Mande and Bobojong
      expect(find.text('Ganti Desa'), findsOneWidget);
      expect(find.textContaining('MANDE'), findsAtLeastNWidgets(1));
      expect(find.textContaining('BOBOJONG'), findsAtLeastNWidgets(1));
      expect(find.textContaining('3205200004'), findsAtLeastNWidgets(1));

      // Tap "Ganti Desa" button to open bottom sheet
      await tester.tap(find.text('Ganti Desa'));
      await tester.pumpAndSettle();

      // Bottom sheet is displayed
      expect(find.text('Pilih Desa untuk Cek Pajak'), findsOneWidget);
      expect(find.textContaining('Ingin mengganti Kecamatan'), findsOneWidget);

      // Select 'Desa JAMALI (009)'
      final jamaliTile = find.textContaining('JAMALI');
      expect(jamaliTile, findsOneWidget);
      await tester.tap(jamaliTile);
      await tester.pumpAndSettle();

      // Bottom sheet closed and active desa updated
      expect(find.textContaining('JAMALI'), findsAtLeastNWidgets(1));
      expect(find.textContaining('3205200009'), findsAtLeastNWidgets(1));
      expect(activeNopPrefix, equals('3205200009'));
      expect(activeDesaName, equals('JAMALI'));
    });
  });
}
