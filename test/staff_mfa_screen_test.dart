import 'package:cek_pbb_app/staff_mfa_screen.dart';
import 'package:cek_pbb_app/staff_portal/staff_authenticator_store.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:cek_pbb_app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMfaClient extends StaffPortalClient {
  StaffMfaResult nextResult = const StaffMfaResult(success: true);
  String? lastSubmittedOtp;

  _FakeMfaClient();

  @override
  Future<StaffMfaResult> verifyMfa(String otp) async {
    lastSubmittedOtp = otp;
    return nextResult;
  }
}

void main() {
  group('StaffMfaScreen Widget & Auto-Verify Tests', () {
    late _FakeMfaClient fakeClient;
    late ThemeController themeController;
    late StaffAuthenticatorStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      fakeClient = _FakeMfaClient();
      themeController = ThemeController();
      store = StaffAuthenticatorStore();
    });

    testWidgets('Tampilan awal saat belum terhubung: tampil kartu promosi & dialog', (tester) async {
      await store.setAutoVerifyEnabled(false);
      await tester.pumpWidget(
        MaterialApp(
          home: StaffMfaScreen(
            client: fakeClient,
            themeController: themeController,
            authenticatorStore: store,
            enablePeriodicTimer: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan kartu promosi tampil
      expect(find.text('Hubungkan Google Authenticator'), findsOneWidget);
      expect(find.text('Hubungkan Kunci (Copas)'), findsOneWidget);
      expect(find.text('Impor Gambar QR'), findsOneWidget);

      // Memastikan field kode verifikasi & tombol submit tampil
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Verifikasi & Masuk'), findsOneWidget);

      // Buka dialog hubungkan kunci
      await tester.tap(find.text('Hubungkan Kunci (Copas)'));
      await tester.pumpAndSettle();

      expect(find.text('Hubungkan Authenticator'), findsOneWidget);
      expect(find.text('Simpan Kunci'), findsOneWidget);

      final dialogKeyField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ).first;

      // Input secret key tidak valid
      await tester.enterText(dialogKeyField, '12345');
      await tester.pumpAndSettle();

      // Tombol simpan nonaktif untuk kunci invalid
      final saveBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Simpan Kunci'));
      expect(saveBtn.onPressed, isNull);

      // Input secret key valid (Base32)
      await tester.enterText(dialogKeyField, 'JBSWY3DPEHPK3PXP');
      await tester.pumpAndSettle();

      // Muncul pratinjau kunci valid
      expect(find.textContaining('Kunci Valid'), findsOneWidget);

      // Klik Simpan Kunci
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan Kunci'));
      await tester.pumpAndSettle();

      // Dialog tertutup, status berubah menjadi terhubung
      expect(find.text('Google Authenticator Terhubung'), findsOneWidget);
      expect(await store.hasSecret(), isTrue);
    });

    testWidgets('Tampilan saat sudah terhubung: kartu token aktif, countdown, dan isi ke kolom', (tester) async {
      // Setup secret key terlebih dahulu (auto-verify false agar tidak langsung auto-login di test ini)
      await store.saveSecret('JBSWY3DPEHPK3PXP', accountName: 'petugas_bobojong', issuer: 'BAPENDA');
      await store.setAutoVerifyEnabled(false);

      await tester.pumpWidget(
        MaterialApp(
          home: StaffMfaScreen(
            client: fakeClient,
            themeController: themeController,
            authenticatorStore: store,
            enablePeriodicTimer: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan kartu token terhubung muncul dengan nama akun
      expect(find.text('Google Authenticator Terhubung'), findsOneWidget);
      expect(find.text('BAPENDA (petugas_bobojong)'), findsOneWidget);
      expect(find.text('KODE 2FA AKTIF'), findsOneWidget);

      // Cek tombol 'Isi ke Kolom'
      expect(find.text('Isi ke Kolom'), findsOneWidget);
      await tester.tap(find.text('Isi ke Kolom'));
      await tester.pumpAndSettle();

      // Textfield terisi 6 digit
      final tf = tester.widget<TextField>(find.byType(TextField).first);
      expect(tf.controller?.text.length, equals(6));

      // Toggle auto-login switch
      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(await store.isAutoVerifyEnabled(), isTrue);
    });

    testWidgets('Auto-Fill & Auto-Verify otomatis memicu login jika aktif', (tester) async {
      await store.saveSecret('JBSWY3DPEHPK3PXP');
      await store.setAutoVerifyEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
          home: StaffMfaScreen(
            client: fakeClient,
            themeController: themeController,
            authenticatorStore: store,
            enablePeriodicTimer: false,
          ),
        ),
      );

      // Initial pump triggers postFrameCallback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // verifyMfa pada client harus sudah terpanggil dengan kode 6 digit
      expect(fakeClient.lastSubmittedOtp, isNotNull);
      expect(fakeClient.lastSubmittedOtp!.length, equals(6));

      // Dialog Login Berhasil muncul
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Login Berhasil'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('Menampilkan error saat kode verifikasi salah dan tidak looping', (tester) async {
      fakeClient.nextResult = const StaffMfaResult(
        success: false,
        errorMessage: 'Kode MFA tidak valid atau kedaluwarsa.',
      );

      await store.saveSecret('JBSWY3DPEHPK3PXP');
      await store.setAutoVerifyEnabled(false);

      await tester.pumpWidget(
        MaterialApp(
          home: StaffMfaScreen(
            client: fakeClient,
            themeController: themeController,
            authenticatorStore: store,
            enablePeriodicTimer: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Isi manual kode yang salah
      await tester.enterText(find.byType(TextField).first, '111222');
      await tester.tap(find.widgetWithText(FilledButton, 'Verifikasi & Masuk'));
      await tester.pumpAndSettle();

      // Muncul pesan error
      expect(find.text('Kode MFA tidak valid atau kedaluwarsa.'), findsOneWidget);
      expect(fakeClient.lastSubmittedOtp, equals('111222'));
    });
  });
}
