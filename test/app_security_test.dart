import 'package:cek_pbb_app/app_lock_gate.dart';
import 'package:cek_pbb_app/app_lock_screen.dart';
import 'package:cek_pbb_app/app_security_service.dart';
import 'package:cek_pbb_app/settings_screen.dart';
import 'package:cek_pbb_app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLocalAuthentication implements LocalAuthentication {
  bool shouldAuthenticate = true;
  bool mockCanCheckBiometrics = true;
  bool mockIsDeviceSupported = true;
  List<BiometricType> mockAvailableBiometrics = [
    BiometricType.fingerprint,
    BiometricType.face,
  ];

  int authenticateCallCount = 0;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    authenticateCallCount++;
    return shouldAuthenticate;
  }

  @override
  Future<bool> get canCheckBiometrics async => mockCanCheckBiometrics;

  @override
  Future<bool> isDeviceSupported() async => mockIsDeviceSupported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      mockAvailableBiometrics;

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocalAuthentication fakeAuth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeAuth = FakeLocalAuthentication();
    AppSecurityService.instance.resetForTesting();
    AppSecurityService.instance.setLocalAuthForTesting(fakeAuth);
  });

  tearDown(() {
    AppSecurityService.instance.resetForTesting();
  });

  group('AppSecurityService - Preferensi & Pengaturan', () {
    test('nilai default preferensi keamanan sesuai spesifikasi', () async {
      final service = AppSecurityService.instance;

      expect(await service.isLockEnabled(), isFalse); // Opsional / default nonaktif
      expect(await service.getLockType(), AppLockType.device); // Default sama kayak HP
      expect(await service.getTimeoutSeconds(), 0); // Default segera
      expect(service.isAppLocked, isFalse);
    });

    test('mengubah status aktif dan jenis kunci tersimpan permanen', () async {
      final service = AppSecurityService.instance;

      await service.setLockEnabled(true);
      expect(await service.isLockEnabled(), isTrue);

      await service.setLockType(AppLockType.pin);
      expect(await service.getLockType(), AppLockType.pin);

      await service.setTimeoutSeconds(60);
      expect(await service.getTimeoutSeconds(), 60);

      await service.setLockType(AppLockType.password);
      expect(await service.getLockType(), AppLockType.password);
    });

    test('deteksi ringkasan kapabilitas biometrik perangkat', () async {
      final service = AppSecurityService.instance;

      // Fingerprint + Face
      fakeAuth.mockAvailableBiometrics = [
        BiometricType.fingerprint,
        BiometricType.face,
      ];
      expect(
        await service.getBiometricCapabilitiesSummary(),
        'Mendukung Sidik Jari & Pengenalan Wajah',
      );

      // Hanya Fingerprint
      fakeAuth.mockAvailableBiometrics = [BiometricType.fingerprint];
      expect(
        await service.getBiometricCapabilitiesSummary(),
        'Mendukung Sidik Jari (Fingerprint)',
      );

      // Hanya Face Unlock
      fakeAuth.mockAvailableBiometrics = [BiometricType.face];
      expect(
        await service.getBiometricCapabilitiesSummary(),
        'Mendukung Pengenalan Wajah (Face Unlock)',
      );

      // Kunci Layar HP tanpa biometrik
      fakeAuth.mockAvailableBiometrics = [];
      expect(
        await service.getBiometricCapabilitiesSummary(),
        'Mendukung Kunci Layar HP (PIN / Pola / Sandi)',
      );

      // Perangkat tidak mendukung sama sekali
      fakeAuth.mockIsDeviceSupported = false;
      expect(
        await service.getBiometricCapabilitiesSummary(),
        'Perangkat tidak mendukung biometrik atau kunci layar',
      );
    });
  });

  group('AppSecurityService - Kustom PIN & Password (SHA-256 + Salt)', () {
    test('pembuatan dan verifikasi PIN 6 digit kustom', () async {
      final service = AppSecurityService.instance;

      expect(await service.hasCustomPin(), isFalse);

      await service.setCustomPin('123456');
      expect(await service.hasCustomPin(), isTrue);

      // PIN benar -> true
      expect(await service.verifyCustomPin('123456'), isTrue);

      // PIN salah -> false
      expect(await service.verifyCustomPin('654321'), isFalse);
      expect(await service.verifyCustomPin('123457'), isFalse);
    });

    test('pembuatan dan verifikasi kata sandi kustom', () async {
      final service = AppSecurityService.instance;

      expect(await service.hasCustomPassword(), isFalse);

      await service.setCustomPassword('PBB#Cianjur2026');
      expect(await service.hasCustomPassword(), isTrue);

      // Password benar -> true
      expect(await service.verifyCustomPassword('PBB#Cianjur2026'), isTrue);

      // Password salah -> false
      expect(await service.verifyCustomPassword('SalahPassword'), isFalse);
    });
  });

  group('AppSecurityService - Autentikasi Perangkat (Sama Kayak HP)', () {
    test('authenticateWithDevice memanggil local_auth dan membuka kunci saat berhasil', () async {
      final service = AppSecurityService.instance;
      service.lock();
      expect(service.isAppLocked, isTrue);

      fakeAuth.shouldAuthenticate = true;
      final result = await service.authenticateWithDevice();

      expect(result, isTrue);
      expect(fakeAuth.authenticateCallCount, 1);
      expect(service.isAppLocked, isFalse);
    });

    test('authenticateWithDevice tidak membuka kunci saat gagal atau dibatalkan', () async {
      final service = AppSecurityService.instance;
      service.lock();
      expect(service.isAppLocked, isTrue);

      fakeAuth.shouldAuthenticate = false;
      final result = await service.authenticateWithDevice();

      expect(result, isFalse);
      expect(service.isAppLocked, isTrue);
    });
  });

  group('AppSecurityService - Siklus Hidup & Kunci Otomatis (Lifecycle)', () {
    test('tidak mengunci jika fitur kunci dinonaktifkan', () async {
      final service = AppSecurityService.instance;
      await service.setLockEnabled(false);

      service.onAppPaused();
      await service.onAppResumed();

      expect(service.isAppLocked, isFalse);
    });

    test('mengunci aplikasi saat diaktifkan dan waktu timeout terlampaui', () async {
      final service = AppSecurityService.instance;
      await service.setLockEnabled(true);
      await service.setTimeoutSeconds(0); // Segera

      service.onAppPaused();
      await service.onAppResumed();

      expect(service.isAppLocked, isTrue);

      // Buka kunci
      service.unlock();
      expect(service.isAppLocked, isFalse);
    });
  });

  group('AppLockGate & AppLockScreen - Tampilan & Interaksi UI', () {
    testWidgets('AppLockGate menampilkan child saat tidak terkunci', (tester) async {
      final service = AppSecurityService.instance;
      await service.setLockEnabled(false);

      await tester.pumpWidget(
        const MaterialApp(
          home: AppLockGate(
            child: Scaffold(
              body: Text('Konten Aplikasi Terbuka'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Konten Aplikasi Terbuka'), findsOneWidget);
      expect(find.byType(AppLockScreen), findsNothing);
    });

    testWidgets('AppLockGate menampilkan AppLockScreen saat terkunci', (tester) async {
      fakeAuth.shouldAuthenticate = false;
      final service = AppSecurityService.instance;
      await service.setLockEnabled(true);
      service.lock();

      await tester.pumpWidget(
        const MaterialApp(
          home: AppLockGate(
            child: Scaffold(
              body: Text('Konten Aplikasi Terbuka'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('Cek PBB Cianjur'), findsOneWidget);
      expect(find.text('Buka dengan Biometrik / Kunci HP'), findsOneWidget);
    });

    testWidgets('AppLockScreen dengan PIN numerik mendukung input keypad dan verifikasi', (tester) async {
      final service = AppSecurityService.instance;
      await service.setLockEnabled(true);
      await service.setLockType(AppLockType.pin);
      await service.setCustomPin('123456');

      bool unlockedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockScreen(
            onUnlocked: () => unlockedCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Masukkan 6 Digit PIN Keamanan'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      // Masukkan PIN 123456
      await tester.tap(find.widgetWithText(OutlinedButton, '1'));
      await tester.tap(find.widgetWithText(OutlinedButton, '2'));
      await tester.tap(find.widgetWithText(OutlinedButton, '3'));
      await tester.tap(find.widgetWithText(OutlinedButton, '4'));
      await tester.tap(find.widgetWithText(OutlinedButton, '5'));
      await tester.tap(find.widgetWithText(OutlinedButton, '6'));
      await tester.pumpAndSettle();

      expect(unlockedCalled, isTrue);
    });

    testWidgets('SettingsScreen menampilkan section Keamanan Aplikasi dan komponen pengaturannya', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      // Section Keamanan Aplikasi tampil
      final securityTile = find.text('Keamanan Aplikasi');
      await tester.ensureVisible(securityTile);
      expect(securityTile, findsOneWidget);
      expect(find.text('Kunci Aplikasi (App Lock)'), findsOneWidget);
      expect(find.textContaining('Nonaktif • Aplikasi dapat langsung dibuka'), findsOneWidget);

      controller.dispose();
    });
  });
}
