import 'package:cek_pbb_app/settings/user_guide_data.dart';
import 'package:cek_pbb_app/settings/user_guide_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'UserGuideScreen renders hero, search, categories, topics, and FAQs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: UserGuideScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Buku Panduan & Bantuan'), findsOneWidget);
      expect(find.text('Panduan Visual Interaktif'), findsOneWidget);
      expect(find.text('Cek Tagihan PBB'), findsOneWidget);

      // Search by typing into the search field
      await tester.enterText(find.byType(TextField), 'Saweria');
      await tester.pump();

      expect(find.text('Tentang & Bagikan Aplikasi'), findsOneWidget);
      expect(find.text('Cek Tagihan PBB'), findsNothing);

      // Clear search and filter by category
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      await tester.tap(find.text('Portal Petugas'));
      await tester.pump();

      expect(find.text('Login Portal Staf Bapenda'), findsOneWidget);
      expect(find.text('Cek Tagihan PBB'), findsNothing);
    },
  );

  testWidgets(
    'GuideTopicDetailScreen renders interactive pins and steps through them',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2246);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: GuideTopicDetailScreen(
            topics: UserGuideRepository.topics,
            initialTopicIndex: 0,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Titik #1 dari 8'), findsOneWidget);
      expect(find.text('Baris Menu Fitur (Cek Tagihan)'), findsWidgets);

      // Advance to next pin
      await tester.tap(find.byTooltip('Titik Berikutnya'));
      await tester.pump();

      expect(find.text('Titik #2 dari 8'), findsOneWidget);
      expect(find.text('Kolom Blok'), findsWidgets);
    },
  );
}
