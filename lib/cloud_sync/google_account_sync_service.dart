import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../base_preferences_store.dart';
import '../blok_backup_scheduler.dart';
import '../theme_controller.dart';
import 'google_drive_service.dart';

/// Layanan sinkronisasi data tersembunyi akun Google (`appDataFolder`):
/// 1. `backup_master_key.json`: Master Key acak 256-bit untuk enkripsi/dekripsi
///    cadangan pribadi DHKP (disimpan sinkron antara `appDataFolder` + `FlutterSecureStorage`).
/// 2. `app_preferences.json`: Preferensi aplikasi lintas perangkat (Tema & Jadwal Backup;
///    wilayah tetap mengikuti berkas DHKP yang terpasang).
class GoogleAccountSyncService extends BasePreferencesStore {
  GoogleAccountSyncService._();
  static final instance = GoogleAccountSyncService._();

  static const String backupMasterKeyFileName = 'backup_master_key.json';
  static const String appPreferencesFileName = 'app_preferences.json';
  static const String customEmergencyContactsPrefsKey =
      'custom_emergency_contacts_v1';

  static const String _secureMasterKeyKey = 'google_backup_master_key_v1';
  static const String _prefsUpdatedAtKey = 'google_sync_prefs_updated_at_ms';
  static const int _schemaVersion = 1;

  bool _isApplyingCloudPreferences = false;
  Future<String?>? _pendingMasterKeyFuture;

  /// Menghasilkan kunci acak 256-bit (32 byte, Base64URL tanpa padding)
  /// menggunakan CSPRNG [Random.secure].
  @visibleForTesting
  static String generateMasterKey() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Membaca Master Key lokal dari penyimpanan aman perangkat (`FlutterSecureStorage`).
  Future<String?> getLocalBackupMasterKey() async {
    final key = await readSecureWithMigration(_secureMasterKeyKey);
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  /// Menghapus cache Master Key lokal (dipanggil saat Sign Out akun Google).
  /// Kunci di `appDataFolder` akun Google tetap aman untuk login berikutnya.
  Future<void> clearLocalBackupMasterKey() async {
    await deleteSecureOnly(_secureMasterKeyKey);
  }

  /// Mengambil atau membuat Master Key 256-bit untuk akun Google aktif.
  ///
  /// - Jika akun Google belum terhubung: mengembalikan `null` (cadangan lokal
  ///   non-Google tetap berjalan seperti biasa).
  /// - Jika akun Google terhubung & [allowCloudSync] aktif:
  ///   1. Cek `backup_master_key.json` di `appDataFolder` (sumber utama lintas perangkat).
  ///   2. Jika ada di cloud $\rightarrow$ sinkronkan ke `FlutterSecureStorage` lokal.
  ///   3. Jika belum ada di cloud tapi ada di lokal $\rightarrow$ unggah ke cloud (self-healing).
  ///   4. Jika belum ada di keduanya $\rightarrow$ buat kunci baru 256-bit, simpan lokal & cloud.
  /// - Jika sedang offline: tetap mengembalikan cache kunci dari `FlutterSecureStorage`.
  Future<String?> getOrCreateBackupMasterKey({bool allowCloudSync = true}) {
    final existing = _pendingMasterKeyFuture;
    if (existing != null) return existing;
    final future = _resolveBackupMasterKey(allowCloudSync: allowCloudSync)
        .whenComplete(() {
          _pendingMasterKeyFuture = null;
        });
    _pendingMasterKeyFuture = future;
    return future;
  }

  Future<String?> _resolveBackupMasterKey({
    required bool allowCloudSync,
  }) async {
    final account = await BlokBackupScheduler.instance.getGoogleAccount();
    if (account.isEmpty) {
      return null;
    }

    final localKey = await getLocalBackupMasterKey();
    if (!allowCloudSync) {
      return localKey;
    }

    try {
      final cloudJson = await GoogleDriveService.instance.readAppDataJson(
        backupMasterKeyFileName,
      );
      final cloudKey = (cloudJson?['masterKey'] as String?)?.trim() ?? '';
      if (cloudKey.length >= 32) {
        if (localKey != cloudKey) {
          await writeSecureOnly(_secureMasterKeyKey, cloudKey);
        }
        return cloudKey;
      }

      if (localKey != null && localKey.length >= 32) {
        await GoogleDriveService.instance.writeAppDataJson(
          backupMasterKeyFileName,
          <String, dynamic>{
            'schemaVersion': _schemaVersion,
            'masterKey': localKey,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
        );
        return localKey;
      }

      final freshKey = generateMasterKey();
      await writeSecureOnly(_secureMasterKeyKey, freshKey);
      await GoogleDriveService.instance.writeAppDataJson(
        backupMasterKeyFileName,
        <String, dynamic>{
          'schemaVersion': _schemaVersion,
          'masterKey': freshKey,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return freshKey;
    } catch (e) {
      debugPrint('GoogleAccountSyncService master key sync error: $e');
      return localKey;
    }
  }

  /// Mencatat waktu perubahan preferensi lokal terbaru (ms sejak epoch UTC).
  Future<int> touchLocalPreferencesTimestamp() async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await setInt(_prefsUpdatedAtKey, nowMs);
    return nowMs;
  }

  @visibleForTesting
  Future<void> resetPreferencesTimestampForTesting() async {
    await setInt(_prefsUpdatedAtKey, 0);
  }

  Future<int> _getLocalPreferencesTimestamp() async {
    return (await getInt(_prefsUpdatedAtKey)) ?? 0;
  }

  /// Membangun payload JSON `app_preferences.json` dari pengaturan lokal saat ini
  /// (Tema & Preferensi Pencadangan — tidak menyertakan Wilayah DHKP).
  Future<Map<String, dynamic>> buildLocalPreferencesPayload({
    int? updatedAtMs,
  }) async {
    final ts = updatedAtMs ?? await _getLocalPreferencesTimestamp();
    final effectiveTs = ts > 0 ? ts : DateTime.now().toUtc().millisecondsSinceEpoch;

    final themeState = ThemeController.current?.value;
    final modeName = themeState?.mode.name ??
        (await getString('theme_mode')) ??
        AppThemeMode.system.name;
    final accentColor = themeState?.accentColor.toARGB32() ??
        (await getInt('theme_accent_color')) ??
        ThemeController.defaultAccentColor.toARGB32();
    final useMaterialYou =
        themeState?.useMaterialYou ?? await getBool('theme_material_you');

    final scheduler = BlokBackupScheduler.instance;
    final frequencyDays = await scheduler.getFrequencyDays();
    final overCellular = await scheduler.getOverCellular();

    final rawContacts = await getString(customEmergencyContactsPrefsKey);
    List<dynamic> emergencyContacts = const [];
    if (rawContacts != null && rawContacts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawContacts);
        if (decoded is List) {
          emergencyContacts = decoded;
        }
      } catch (_) {}
    }

    return <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'updatedAtMs': effectiveTs,
      'updatedAt': DateTime.fromMillisecondsSinceEpoch(
        effectiveTs,
        isUtc: true,
      ).toIso8601String(),
      'theme': <String, dynamic>{
        'mode': modeName,
        'accentColor': accentColor,
        'useMaterialYou': useMaterialYou,
      },
      'backup': <String, dynamic>{
        'frequencyDays': frequencyDays,
        'overCellular': overCellular,
      },
      'emergencyContacts': emergencyContacts,
    };
  }

  /// Menerapkan payload JSON `app_preferences.json` ke pengaturan lokal.
  @visibleForTesting
  Future<void> applyPreferencesPayload(Map<String, dynamic> payload) async {
    _isApplyingCloudPreferences = true;
    try {
      final themeMap = payload['theme'];
      if (themeMap is Map) {
        final modeStr = themeMap['mode'] as String?;
        final accentInt = (themeMap['accentColor'] as num?)?.toInt();
        final materialYou = themeMap['useMaterialYou'] as bool?;

        final controller = ThemeController.current;
        if (controller != null) {
          if (modeStr != null) {
            final parsedMode = AppThemeMode.values.firstWhere(
              (m) => m.name == modeStr,
              orElse: () => AppThemeMode.system,
            );
            await controller.setMode(parsedMode, syncCloud: false);
          }
          if (accentInt != null) {
            await controller.setAccentColor(
              Color(accentInt),
              saveToPrefs: true,
              syncCloud: false,
            );
          }
          if (materialYou != null) {
            await controller.setUseMaterialYou(materialYou, syncCloud: false);
          }
        } else {
          if (modeStr != null) await setString('theme_mode', modeStr);
          if (accentInt != null) await setInt('theme_accent_color', accentInt);
          if (materialYou != null) {
            await setBool('theme_material_you', materialYou);
          }
        }
      }

      final backupMap = payload['backup'];
      if (backupMap is Map) {
        final freq = (backupMap['frequencyDays'] as num?)?.toInt();
        final overCell = backupMap['overCellular'] as bool?;
        if (freq != null) {
          await BlokBackupScheduler.instance.setFrequencyDays(
            freq,
            syncCloud: false,
          );
        }
        if (overCell != null) {
          await BlokBackupScheduler.instance.setOverCellular(
            overCell,
            syncCloud: false,
          );
        }
      }

      final rawEmergencyContacts = payload['emergencyContacts'];
      if (rawEmergencyContacts is List) {
        final validContacts = rawEmergencyContacts
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .where(
              (m) =>
                  (m['name']?.toString().trim().isNotEmpty ?? false) &&
                  (m['phone']?.toString().trim().isNotEmpty ?? false),
            )
            .toList();
        await setString(
          customEmergencyContactsPrefsKey,
          jsonEncode(validContacts),
        );
      }

      final cloudTs = _extractTimestampMs(payload);
      if (cloudTs > 0) {
        await setInt(_prefsUpdatedAtKey, cloudTs);
      }
    } finally {
      _isApplyingCloudPreferences = false;
    }
  }

  static int _extractTimestampMs(Map<String, dynamic> payload) {
    final rawMs = payload['updatedAtMs'];
    if (rawMs is num) return rawMs.toInt();
    final iso = payload['updatedAt'];
    if (iso is String && iso.isNotEmpty) {
      return DateTime.tryParse(iso)?.toUtc().millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  /// Mengunggah preferensi lokal saat ini ke `appDataFolder` secara aman (non-blocking).
  Future<bool> pushPreferencesToCloud() async {
    if (_isApplyingCloudPreferences) return false;
    final account = await BlokBackupScheduler.instance.getGoogleAccount();
    if (account.isEmpty) return false;
    try {
      final ts = await touchLocalPreferencesTimestamp();
      final payload = await buildLocalPreferencesPayload(updatedAtMs: ts);
      return await GoogleDriveService.instance.writeAppDataJson(
        appPreferencesFileName,
        payload,
      );
    } catch (e) {
      debugPrint('GoogleAccountSyncService pushPreferences error: $e');
      return false;
    }
  }

  /// Menyinkronkan preferensi antara lokal dan cloud berdasarkan timestamp terbaru.
  Future<void> syncPreferences() async {
    final account = await BlokBackupScheduler.instance.getGoogleAccount();
    if (account.isEmpty) return;

    try {
      final cloudJson = await GoogleDriveService.instance.readAppDataJson(
        appPreferencesFileName,
      );
      final localTs = await _getLocalPreferencesTimestamp();

      if (cloudJson != null) {
        final cloudTs = _extractTimestampMs(cloudJson);
        if (cloudTs > localTs) {
          await applyPreferencesPayload(cloudJson);
          return;
        }
      }

      final payload = await buildLocalPreferencesPayload(
        updatedAtMs: localTs > 0 ? localTs : null,
      );
      await GoogleDriveService.instance.writeAppDataJson(
        appPreferencesFileName,
        payload,
      );
    } catch (e) {
      debugPrint('GoogleAccountSyncService syncPreferences error: $e');
    }
  }

  /// Menjalankan sinkronisasi penuh (Master Key + Preferensi) setelah login Google
  /// atau saat startup jika akun Google sudah terhubung.
  Future<void> syncAllAfterSignIn() async {
    await getOrCreateBackupMasterKey(allowCloudSync: true);
    await syncPreferences();
  }
}
