import 'package:cek_pbb_app/feature_tour/feature_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeatureTourController.dismissActiveTour();
  });

  tearDown(() {
    FeatureTourController.dismissActiveTour();
  });

  test('FeatureTourStore persists, resets single tour, and resets all tours', () async {
    expect(await FeatureTourStore.hasSeenTour('test_widget_1'), isFalse);
    expect(await FeatureTourStore.hasSeenTour('test_widget_2'), isFalse);

    await FeatureTourStore.markTourSeen('test_widget_1');
    await FeatureTourStore.markTourSeen('test_widget_2');
    expect(await FeatureTourStore.hasSeenTour('test_widget_1'), isTrue);
    expect(await FeatureTourStore.hasSeenTour('test_widget_2'), isTrue);

    await FeatureTourStore.resetTour('test_widget_1');
    expect(await FeatureTourStore.hasSeenTour('test_widget_1'), isFalse);
    expect(await FeatureTourStore.hasSeenTour('test_widget_2'), isTrue);

    await FeatureTourStore.resetAllTours();
    expect(await FeatureTourStore.hasSeenTour('test_widget_2'), isFalse);
  });

  testWidgets(
    'FeatureTourController displays contextual steps, advances, goes back, and completes',
    (tester) async {
      final key1 = GlobalKey(debugLabel: 'btn_1');
      final key2 = GlobalKey(debugLabel: 'btn_2');
      final unmountedKey = GlobalKey(debugLabel: 'unmounted_btn');
      late BuildContext savedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Halaman Uji'),
              actions: [
                Builder(
                  builder: (ctx) {
                    savedContext = ctx;
                    return FeatureTourHelpButton(
                      onPressed: () {
                        FeatureTourController.showTour(
                          context: ctx,
                          tourId: 'test_tour',
                          tourTitle: 'Panduan Uji',
                          steps: [
                            FeatureTourStep(
                              targetKey: key1,
                              title: 'Tombol Pertama',
                              description: 'Penjelasan ramah pengguna untuk tombol pertama.',
                              actionHint: 'Ketuk sekali untuk mulai',
                              icon: Icons.search,
                            ),
                            FeatureTourStep(
                              targetKey: unmountedKey,
                              title: 'Tombol Tersembunyi',
                              description: 'Tidak boleh tampil karena tidak ada di layar.',
                            ),
                            FeatureTourStep(
                              targetKey: key2,
                              title: 'Tombol Kedua',
                              description: 'Penjelasan ramah pengguna untuk tombol kedua.',
                              icon: Icons.check_circle_outline,
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                ElevatedButton(
                  key: key1,
                  onPressed: () {},
                  child: const Text('Aksi 1'),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  key: key2,
                  onPressed: () {},
                  child: const Text('Aksi 2'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(FeatureTourController.isShowing, isFalse);

      // Tap the help button (?) to launch the tour
      await tester.tap(find.byType(FeatureTourHelpButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(FeatureTourController.isShowing, isTrue);
      // Only the 2 mounted keys should be included (Langkah 1 dari 2)
      expect(find.text('Tombol Pertama'), findsOneWidget);
      expect(find.text('Penjelasan ramah pengguna untuk tombol pertama.'), findsOneWidget);
      expect(find.text('Ketuk sekali untuk mulai'), findsOneWidget);
      expect(find.text('Langkah 1 dari 2'), findsOneWidget);

      // Advance to step 2
      await tester.tap(find.text('Lanjut'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Tombol Kedua'), findsOneWidget);
      expect(find.text('Penjelasan ramah pengguna untuk tombol kedua.'), findsOneWidget);
      expect(find.text('Langkah 2 dari 2'), findsOneWidget);

      // Go back to step 1
      await tester.tap(find.text('Sebelumnya'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Tombol Pertama'), findsOneWidget);

      // Advance again and finish
      await tester.tap(find.text('Lanjut'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Selesai'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(FeatureTourController.isShowing, isFalse);
      expect(await FeatureTourStore.hasSeenTour('test_tour'), isTrue);
      expect(savedContext.mounted, isTrue);
    },
  );
}
