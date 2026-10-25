import 'package:cek_pbb_app/legal_document_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegalDocumentScreen Widget Tests', () {
    testWidgets('Merender tab Kebijakan Privasi dengan benar secara default',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentScreen(
            initialType: LegalDocumentType.privacyPolicy,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Informasi Hukum & Privasi'), findsOneWidget);
      expect(find.text('Kebijakan Privasi'), findsWidgets);
      expect(find.text('Syarat & Ketentuan'), findsOneWidget);

      // Verifikasi isi Kebijakan Privasi
      expect(
        find.textContaining('Kebijakan Privasi (Privacy Policy)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Prinsip Akses Minimum Terisolasi:'),
        findsOneWidget,
      );
      expect(
        find.text('Buka Kebijakan Privasi Resmi di Web'),
        findsOneWidget,
      );
    });

    testWidgets('Merender tab Syarat & Ketentuan dengan benar saat dipilih',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentScreen(
            initialType: LegalDocumentType.termsOfService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifikasi isi Syarat & Ketentuan
      expect(
        find.textContaining('Syarat & Ketentuan Layanan'),
        findsOneWidget,
      );
      expect(
        find.textContaining('1. Deskripsi Layanan'),
        findsOneWidget,
      );
      expect(
        find.text('Buka Syarat & Ketentuan di Web'),
        findsOneWidget,
      );
    });

    testWidgets('Dapat berpindah antar tab dengan mulus', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentScreen(
            initialType: LegalDocumentType.privacyPolicy,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Buka Kebijakan Privasi Resmi di Web'), findsOneWidget);

      // Tap tab Syarat & Ketentuan
      await tester.tap(find.text('Syarat & Ketentuan'));
      await tester.pumpAndSettle();

      expect(find.text('Buka Syarat & Ketentuan di Web'), findsOneWidget);

      // Tap kembali ke Kebijakan Privasi
      await tester.tap(find.text('Kebijakan Privasi').first);
      await tester.pumpAndSettle();

      expect(find.text('Buka Kebijakan Privasi Resmi di Web'), findsOneWidget);
    });
  });
}
