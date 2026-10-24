import 'package:cek_pbb_app/blok_backup_scheduler.dart';
import 'package:cek_pbb_app/google_auth_service.dart';
import 'package:cek_pbb_app/google_drive_backup_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageValues = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorageValues.clear();
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return secureStorageValues[arguments['key']];
        case 'write':
          secureStorageValues[arguments['key'] as String] =
              arguments['value'] as String;
          return null;
        case 'delete':
          secureStorageValues.remove(arguments['key']);
          return null;
        case 'containsKey':
          return secureStorageValues.containsKey(arguments['key']);
        case 'deleteAll':
          secureStorageValues.clear();
          return null;
      }
      return null;
    });
    BlokBackupScheduler.instance.resetForTesting();
  });

  group('GoogleAuthService & Profile Details Tests', () {
    test('GoogleAuthUser model menyimpan atribut akun dengan benar', () {
      const user = GoogleAuthUser(
        email: 'petugas@desa.id',
        displayName: 'Petugas PBB',
        photoUrl: 'https://lh3.googleusercontent.com/photo.jpg',
        id: '1234567890',
      );

      expect(user.email, 'petugas@desa.id');
      expect(user.displayName, 'Petugas PBB');
      expect(user.photoUrl, 'https://lh3.googleusercontent.com/photo.jpg');
      expect(user.id, '1234567890');
    });

    test('BlokBackupScheduler setGoogleAccountDetails menyimpan info profil lengkap', () async {
      final scheduler = BlokBackupScheduler.instance;

      expect(await scheduler.getGoogleAccount(), isEmpty);
      expect(await scheduler.getGoogleDisplayName(), isEmpty);
      expect(await scheduler.getGooglePhotoUrl(), isEmpty);

      await scheduler.setGoogleAccountDetails(
        email: 'bapenda@cianjur.go.id',
        displayName: 'Bapenda Cianjur',
        photoUrl: 'https://avatar.google.com/bapenda.png',
      );

      expect(await scheduler.getGoogleAccount(), 'bapenda@cianjur.go.id');
      expect(await scheduler.getGoogleDisplayName(), 'Bapenda Cianjur');
      expect(await scheduler.getGooglePhotoUrl(), 'https://avatar.google.com/bapenda.png');

      // Pelepasan akun otomatis membersihkan nama dan foto profil
      await scheduler.setGoogleAccountDetails(email: '');
      expect(await scheduler.getGoogleAccount(), isEmpty);
      expect(await scheduler.getGoogleDisplayName(), isEmpty);
      expect(await scheduler.getGooglePhotoUrl(), isEmpty);
    });

    test('GoogleAuthService configure menerima client ID kustom secara aman', () {
      final service = GoogleAuthService.instance;
      expect(() => service.configure(clientId: 'test-client-id.apps.googleusercontent.com'), returnsNormally);
    });

    test('GoogleDriveBackupPolicy memastikan scopes otorisasi mematuhi Least-Privilege', () {
      expect(GoogleDriveBackupPolicy.allowedScopes, contains('https://www.googleapis.com/auth/drive.file'));
      expect(GoogleDriveBackupPolicy.allowedScopes, contains('https://www.googleapis.com/auth/drive.appdata'));
      expect(GoogleDriveBackupPolicy.isScopeAllowed('https://www.googleapis.com/auth/drive'), isFalse);
    });

    test('GoogleAuthService signIn dengan mockUser berhasil dan tersimpan di scheduler', () async {
      final service = GoogleAuthService.instance;
      GoogleAuthService.mockUser = const GoogleAuthUser(
        email: 'user@gmail.com',
        displayName: 'User Google',
        photoUrl: 'https://avatar.google.com/user.png',
        id: '998877',
      );

      final user = await service.signIn();
      expect(user, isNotNull);
      expect(user!.email, 'user@gmail.com');
      expect(user.displayName, 'User Google');

      final scheduler = BlokBackupScheduler.instance;
      expect(await scheduler.getGoogleAccount(), 'user@gmail.com');
      expect(await scheduler.getGoogleDisplayName(), 'User Google');
      expect(await scheduler.getGooglePhotoUrl(), 'https://avatar.google.com/user.png');
      expect(await service.hasDrivePermission(), isTrue);

      await service.signOut();
      expect(await scheduler.getGoogleAccount(), isEmpty);
      expect(await scheduler.getGoogleDisplayName(), isEmpty);
    });

    test('GoogleAuthService PKCE helper menghasilkan verifier dan challenge yang valid', () {
      final verifier = GoogleAuthService.generateRandomString(64);
      expect(verifier.length, 64);
      expect(RegExp(r'^[a-zA-Z0-9\-._~]+$').hasMatch(verifier), isTrue);

      final challenge = GoogleAuthService.generateCodeChallenge(verifier);
      expect(challenge, isNotEmpty);
      expect(challenge.contains('='), isFalse); // Tanpa padding base64
    });

    test('GoogleAuthService Desktop Client ID dapat dikonfigurasi dan token tersimpan', () async {
      final service = GoogleAuthService.instance;
      expect(GoogleAuthService.defaultDesktopClientId, contains('apps.googleusercontent.com'));

      service.configure(desktopClientId: 'custom-client-id.apps.googleusercontent.com');

      final scheduler = BlokBackupScheduler.instance;
      await scheduler.setGoogleDesktopTokens(
        accessToken: 'ya29.test_token_123',
        refreshToken: '1//refresh_token_xyz',
      );

      expect(await scheduler.getGoogleDesktopAccessToken(), 'ya29.test_token_123');

      // Header auth otentikasi mengembalikan Bearer token di desktop
      final headers = await service.getAuthHeaders();
      expect(headers, isNotNull);
      expect(headers!['Authorization'], 'Bearer ya29.test_token_123');

      // Saat pelepasan akun (signOut), token desktop ikut dibersihkan
      await service.signOut();
      expect(await scheduler.getGoogleDesktopAccessToken(), isEmpty);
    });
  });
}
