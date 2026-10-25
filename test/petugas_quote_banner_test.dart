import 'package:cek_pbb_app/petugas_quote_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PetugasQuoteRepository Tests', () {
    test('memiliki daftar kata-kata pengingat dan motivasi', () {
      expect(PetugasQuoteRepository.quotes.isNotEmpty, isTrue);
      expect(PetugasQuoteRepository.quotes.length, equals(100));
    });

    test('getRandomQuote mengembalikan quote yang valid', () {
      final quote = PetugasQuoteRepository.getRandomQuote();
      expect(quote.text.isNotEmpty, isTrue);
      expect(quote.category.isNotEmpty, isTrue);
    });

    test('getRandomQuote dengan excludeIndex mengembalikan quote yang berbeda', () {
      final quote1 = PetugasQuoteRepository.quotes[0];
      final quote2 = PetugasQuoteRepository.getRandomQuote(excludeIndex: 0);
      expect(quote2.text != quote1.text || PetugasQuoteRepository.quotes.length == 1, isTrue);
    });

    test('getRandomQuote mengembalikan quote secara acak bukan berurutan', () {
      final indices = <int>{};
      for (var i = 0; i < 40; i++) {
        final quote = PetugasQuoteRepository.getRandomQuote();
        indices.add(PetugasQuoteRepository.quotes.indexOf(quote));
      }
      // Dari 40 kali pengambilan acak dari 100 quote, variasi indeks acak harus tinggi (>20)
      expect(indices.length, greaterThan(20));
    });
  });

  group('PetugasQuoteBanner Widget Tests', () {
    testWidgets('menampilkan teks quote secara alami tanpa judul atau tombol refresh/tutup', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PetugasQuoteBanner(
              typewriterSpeed: Duration(milliseconds: 5),
              dwellDuration: Duration(seconds: 7),
            ),
          ),
        ),
      );
      // Animasi panel slide down
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PetugasQuoteBanner), findsOneWidget);
      // Memastikan bebas dari tombol refresh atau close (bersih dan alami)
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      // Memastikan kartu quote dirender
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsOneWidget);
    });

    testWidgets('animasi ketik per-huruf dan auto-dismiss bertahan 12 detik lalu menghilang alami', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PetugasQuoteBanner(
              typewriterSpeed: Duration(milliseconds: 10),
              dwellDuration: Duration(seconds: 12),
            ),
          ),
        ),
      );
      // Slide-down animation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsOneWidget);

      // Typewriter sedang berjalan
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsOneWidget);

      // Selesaikan pengetikan
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsOneWidget);

      // Saat dwell 12 detik berlangsung (misal detik ke-6), banner masih ada
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsOneWidget);

      // Melewati sisa 12 detik (misal tambah 7 detik)
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      // Banner telah otomatis menghilang
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsNothing);
    });

    testWidgets('triggerNonce memicu siklus banner baru saat kembali ke halaman', (tester) async {
      int nonce = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    PetugasQuoteBanner(
                      triggerNonce: nonce,
                      typewriterSpeed: const Duration(milliseconds: 5),
                      dwellDuration: const Duration(seconds: 12),
                    ),
                    ElevatedButton(
                      onPressed: () => setState(() => nonce++),
                      child: const Text('BackToPage'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // Biarkan siklus pertama selesai dan menghilang setelah 12 detik
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsNothing);

      // Pengguna kembali ke halaman (nonce berubah)
      await tester.tap(find.text('BackToPage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Banner muncul kembali dengan teks alami
      expect(find.byKey(const ValueKey('petugas_quote_card')), findsOneWidget);
    });
  });
}
