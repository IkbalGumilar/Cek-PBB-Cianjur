import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/base_preferences_store.dart';
import 'package:cek_pbb_app/blok_backup_scheduler.dart';
import 'package:cek_pbb_app/cloud_sync/google_account_sync_service.dart';
import 'package:cek_pbb_app/cloud_sync/google_drive_service.dart';
import 'package:cek_pbb_app/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BaseSecureStore.clearTestMemoryStore();
    BlokBackupScheduler.instance.resetForTesting();
    GoogleAccountSyncService.instance.resetPrefsForTesting();
    GoogleDriveService.resetForTesting();
    GoogleDriveService.mockAppDataStore = <String, Map<String, dynamic>>{};
  });

  tearDown(() {
    GoogleDriveService.resetForTesting();
    BaseSecureStore.clearTestMemoryStore();
  });

  group('GoogleAccountSyncService', () {
    test('returns null master key when no Google account is connected', () async {
      final key = await GoogleAccountSyncService.instance
          .getOrCreateBackupMasterKey();
      expect(key, isNull);
    });

    test(
      'creates 256-bit master key, stores in appDataFolder + SecureStorage, and syncs to a second device',
      () async {
        await BlokBackupScheduler.instance.setGoogleAccount(
          'petugas@example.com',
        );

        final firstKey = await GoogleAccountSyncService.instance
            .getOrCreateBackupMasterKey();
        expect(firstKey, isNotNull);
        expect(firstKey!.length, greaterThanOrEqualTo(43));

        // Tersimpan di cloud appDataFolder & cache lokal SecureStorage
        expect(
          GoogleDriveService
              .mockAppDataStore![GoogleAccountSyncService.backupMasterKeyFileName]
              ?['masterKey'],
          firstKey,
        );
        expect(
          await GoogleAccountSyncService.instance.getLocalBackupMasterKey(),
          firstKey,
        );

        // Simulasikan perangkat baru (hapus cache lokal, cloud tetap ada)
        await GoogleAccountSyncService.instance.clearLocalBackupMasterKey();
        expect(
          await GoogleAccountSyncService.instance.getLocalBackupMasterKey(),
          isNull,
        );

        final restoredKey = await GoogleAccountSyncService.instance
            .getOrCreateBackupMasterKey();
        expect(restoredKey, firstKey);
        expect(
          await GoogleAccountSyncService.instance.getLocalBackupMasterKey(),
          firstKey,
        );
      },
    );

    test(
      'self-heals missing cloud master key from local SecureStorage cache',
      () async {
        await BlokBackupScheduler.instance.setGoogleAccount(
          'petugas@example.com',
        );
        final key = await GoogleAccountSyncService.instance
            .getOrCreateBackupMasterKey();

        // Hapus salinan di cloud, pastikan cache lokal memulihkannya ke cloud
        GoogleDriveService.mockAppDataStore!.clear();
        final healed = await GoogleAccountSyncService.instance
            .getOrCreateBackupMasterKey();
        expect(healed, key);
        expect(
          GoogleDriveService
              .mockAppDataStore![GoogleAccountSyncService.backupMasterKeyFileName]
              ?['masterKey'],
          key,
        );
      },
    );

    test(
      'syncs theme and backup preferences via appDataFolder without storing wilayah',
      () async {
        await BlokBackupScheduler.instance.setGoogleAccount(
          'petugas@example.com',
        );
        final themeController = ThemeController();
        addTearDown(themeController.dispose);

        await themeController.setMode(AppThemeMode.dark, syncCloud: false);
        await themeController.setAccentColor(
          const Color(0xFF1565C0),
          syncCloud: false,
        );
        await themeController.setUseMaterialYou(true, syncCloud: false);
        await BlokBackupScheduler.instance.setFrequencyDays(
          7,
          syncCloud: false,
        );
        await BlokBackupScheduler.instance.setOverCellular(
          true,
          syncCloud: false,
        );

        final pushed = await GoogleAccountSyncService.instance
            .pushPreferencesToCloud();
        expect(pushed, isTrue);

        final cloudPrefs = GoogleDriveService
            .mockAppDataStore![GoogleAccountSyncService.appPreferencesFileName];
        expect(cloudPrefs, isNotNull);
        expect(cloudPrefs!.containsKey('wilayah'), isFalse);
        expect((cloudPrefs['theme'] as Map)['mode'], 'dark');
        expect((cloudPrefs['theme'] as Map)['useMaterialYou'], isTrue);
        expect((cloudPrefs['backup'] as Map)['frequencyDays'], 7);
        expect((cloudPrefs['backup'] as Map)['overCellular'], isTrue);

        // Simulasikan perangkat baru dengan preferensi default & timestamp 0
        await themeController.setMode(AppThemeMode.light, syncCloud: false);
        await themeController.setUseMaterialYou(false, syncCloud: false);
        await BlokBackupScheduler.instance.setFrequencyDays(
          1,
          syncCloud: false,
        );
        await BlokBackupScheduler.instance.setOverCellular(
          false,
          syncCloud: false,
        );
        await GoogleAccountSyncService.instance
            .resetPreferencesTimestampForTesting();

        await GoogleAccountSyncService.instance.syncPreferences();
        expect(themeController.mode, AppThemeMode.dark);
        expect(themeController.accentColor.toARGB32(), 0xFF1565C0);
        expect(themeController.useMaterialYou, isTrue);
        expect(await BlokBackupScheduler.instance.getFrequencyDays(), 7);
        expect(await BlokBackupScheduler.instance.getOverCellular(), isTrue);
      },
    );
  });
}
