import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_storage.dart';
import 'base_preferences_store.dart';
import 'blok_data_store.dart';
import 'dkhp_package_helper.dart';
import 'google_drive_backup_policy.dart';

/// Pengelola & penjadwal cadangan data DHKP ala WhatsApp.
///
/// Fitur utama:
/// 1. Pilihan frekuensi otomatis: 0 (Manual/Jangan Pernah), 1 (Harian setiap 24 jam / pk 02:00),
///    7 (Mingguan), 14 (Setiap 14 hari), 30 (Bulanan).
/// 2. Kebijakan Retensi Maksimal 3 Berkas: Jika berkas cadangan lokal sudah mencapai batas retensi
///    (3 berkas), berkas cadangan paling lama otomatis dihapus agar tidak menghabiskan penyimpanan perangkat.
/// 3. Opsi cadangan khusus data DHKP saja (tanpa menyertakan foto lembaran SPPT) agar sangat hemat kuota & memori.
/// 4. Opsi sinkronisasi akun Google (Google Drive) dengan pembatasan keamanan ketat (hanya folder khusus aplikasi).
/// 5. Pengaturan jaringan (Wi-Fi saja atau Seluler).
class BlokBackupScheduler extends BasePreferencesStore {
  BlokBackupScheduler._();
  static final instance = BlokBackupScheduler._();

  static const int maxRetainedBackups = 3;

  Future<String?> _readSecureToken(String key) async {
    final val = await readSecure(key);
    if (val != null) {
      await remove(key);
      return val;
    }
    return getString(key);
  }

  Future<void> _writeSecureToken(String key, String value) async {
    await writeSecure(key, value);
    await remove(key);
  }

  Future<void> _deleteSecureToken(String key) async {
    await deleteSecure(key);
    await remove(key);
  }

  /// Folder khusus terisolasi di Google Drive (aplikasi dilarang mengakses folder lain).
  String get googleDriveDedicatedFolder =>
      GoogleDriveBackupPolicy.dedicatedFolderName;

  /// Scope Google Drive yang diizinkan (Least-Privilege).
  List<String> get googleDriveAllowedScopes =>
      GoogleDriveBackupPolicy.allowedScopes;

  @visibleForTesting
  void resetForTesting() {
    resetPrefsForTesting();
  }

  static const _frequencyDaysKey = 'blok_backup_frequency_days';
  static const _onlyDkhpKey = 'blok_backup_only_dkhp_data';
  static const _googleAccountKey = 'blok_backup_google_account';
  static const _googleDisplayNameKey = 'blok_backup_google_display_name';
  static const _googlePhotoUrlKey = 'blok_backup_google_photo_url';
  static const _googleDriveFolderLinkKey = 'blok_backup_google_drive_folder_link';
  static const _googleDriveFolderIdKey = 'blok_backup_google_drive_folder_id';
  static const _googleDesktopAccessTokenKey = 'blok_backup_google_desktop_access_token';
  static const _googleDesktopRefreshTokenKey = 'blok_backup_google_desktop_refresh_token';
  static const _overCellularKey = 'blok_backup_over_cellular';
  static const _lastBackupTimeKey = 'blok_backup_last_time_millis';
  static const _lastBackupSizeKey = 'blok_backup_last_size_bytes';
  static const _lastBackupPathKey = 'blok_backup_last_path';
  static const _dirtyKey = 'blok_data_dirty';

  /// Mendapatkan preferensi frekuensi cadangan dalam satuan hari.
  /// 0 = Jangan pernah / Manual
  /// 1 = Harian (24 jam / pk 02:00)
  /// 7 = Mingguan (7 hari)
  /// 14 = Setiap 14 hari
  /// 30 = Bulanan (30 hari)
  Future<int> getFrequencyDays() async {
    return (await getInt(_frequencyDaysKey)) ?? 1;
  }

  Future<void> setFrequencyDays(int days) async {
    await setInt(_frequencyDaysKey, days);
  }

  /// Preferensi cadangan hanya data DHKP (tanpa foto). Default: true (hemat memori & cepat).
  Future<bool> getOnlyDkhpData() async {
    return getBool(_onlyDkhpKey, defaultValue: true);
  }

  Future<void> setOnlyDkhpData(bool value) async {
    await setBool(_onlyDkhpKey, value);
  }

  /// Akun Google yang terhubung untuk sinkronisasi cadangan.
  Future<String> getGoogleAccount() async {
    return (await getString(_googleAccountKey)) ?? '';
  }

  Future<void> setGoogleAccount(String email) async {
    final trimmed = email.trim();
    await setString(_googleAccountKey, trimmed);
    if (trimmed.isEmpty) {
      // Jika akun Google dilepas, otomatis bersihkan juga link folder bersama, info profil, & token desktop
      await remove(_googleDisplayNameKey);
      await remove(_googlePhotoUrlKey);
      await remove(_googleDriveFolderLinkKey);
      await remove(_googleDriveFolderIdKey);
      await _deleteSecureToken(_googleDesktopAccessTokenKey);
      await _deleteSecureToken(_googleDesktopRefreshTokenKey);
    }
  }

  Future<String> getGoogleDisplayName() async {
    return (await getString(_googleDisplayNameKey)) ?? '';
  }

  Future<String> getGooglePhotoUrl() async {
    return (await getString(_googlePhotoUrlKey)) ?? '';
  }

  Future<String> getGoogleDesktopAccessToken() async {
    return (await _readSecureToken(_googleDesktopAccessTokenKey)) ?? '';
  }

  Future<String> getGoogleDesktopRefreshToken() async {
    return (await _readSecureToken(_googleDesktopRefreshTokenKey)) ?? '';
  }

  Future<void> setGoogleDesktopTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _writeSecureToken(_googleDesktopAccessTokenKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _writeSecureToken(_googleDesktopRefreshTokenKey, refreshToken);
    }
  }

  Future<void> setGoogleAccountDetails({
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    await setGoogleAccount(email);
    if (email.trim().isNotEmpty) {
      if (displayName != null && displayName.isNotEmpty) {
        await setString(_googleDisplayNameKey, displayName);
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        await setString(_googlePhotoUrlKey, photoUrl);
      }
    }
  }

  /// Mendapatkan link folder bersama Google Drive yang dikonfigurasi pengguna.
  /// Bila belum terhubung ke akun Google, selalu mengembalikan string kosong.
  Future<String> getGoogleDriveFolderLink() async {
    final account = await getGoogleAccount();
    if (account.isEmpty) return '';
    return (await getString(_googleDriveFolderLinkKey)) ?? '';
  }

  /// Mendapatkan folder atau folder ID tujuan cadangan di Google Drive.
  /// Jika folder bersama diatur dan valid, mengembalikan ID folder bersama tersebut.
  /// Jika tidak, default ke folder khusus aplikasi [GoogleDriveBackupPolicy.dedicatedFolderName].
  Future<String> getEffectiveGoogleDriveFolder() async {
    final account = await getGoogleAccount();
    if (account.isEmpty) return GoogleDriveBackupPolicy.dedicatedFolderName;

    final folderId = await getString(_googleDriveFolderIdKey);
    if (folderId != null && folderId.trim().isNotEmpty) {
      return folderId.trim();
    }
    return GoogleDriveBackupPolicy.dedicatedFolderName;
  }

  /// Mengatur link folder bersama Google Drive.
  /// Syarat mutlak: akun Google harus sudah terhubung terlebih dahulu.
  /// Mengembalikan true bila berhasil disimpan, atau false bila gagal/belum login.
  Future<bool> setGoogleDriveFolderLink(String link) async {
    final account = await getGoogleAccount();
    if (account.isEmpty) {
      return false; // Syarat harus terhubung ke akun Google dulu
    }

    final trimmed = link.trim();
    if (trimmed.isEmpty) {
      await remove(_googleDriveFolderLinkKey);
      await remove(_googleDriveFolderIdKey);
      return true;
    }

    final folderId = GoogleDriveBackupPolicy.extractFolderId(trimmed);
    if (folderId != null && folderId.isNotEmpty) {
      await setString(_googleDriveFolderLinkKey, trimmed);
      await setString(_googleDriveFolderIdKey, folderId);
      return true;
    }
    return false;
  }

  /// Mendapatkan ID folder Google Drive yang tersimpan (baik folder bersama maupun folder khusus).
  Future<String?> getGoogleDriveFolderId() async {
    return getString(_googleDriveFolderIdKey);
  }

  /// Menyimpan ID folder Google Drive (folder khusus atau folder bersama).
  Future<void> setGoogleDriveFolderId(String folderId) async {
    final trimmed = folderId.trim();
    if (trimmed.isEmpty) {
      await remove(_googleDriveFolderIdKey);
    } else {
      await setString(_googleDriveFolderIdKey, trimmed);
    }
  }

  /// Izinkan pencadangan melalui data seluler atau hanya Wi-Fi. Default: false (Wi-Fi saja).
  Future<bool> getOverCellular() async {
    return getBool(_overCellularKey, defaultValue: false);
  }

  Future<void> setOverCellular(bool value) async {
    await setBool(_overCellularKey, value);
  }

  /// Timestamp cadangan terakhir (dalam DateTime).
  Future<DateTime?> getLastBackupTime() async {
    final millis = await getInt(_lastBackupTimeKey);
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Ukuran berkas cadangan terakhir dalam byte.
  Future<int?> getLastBackupSize() async {
    return getInt(_lastBackupSizeKey);
  }

  /// Path berkas cadangan terakhir.
  Future<String?> getLastBackupPath() async {
    return getString(_lastBackupPathKey);
  }

  /// Tandai ada data DHKP yang baru atau diubah.
  Future<void> markDirty() async {
    await setBool(_dirtyKey, true);
  }

  /// Reset status perubahan data.
  Future<void> clearDirty() async {
    await setBool(_dirtyKey, false);
  }

  /// Cek apakah status data sedang dirty.
  Future<bool> isDirty() async {
    return getBool(_dirtyKey, defaultValue: false);
  }

  /// Logika evaluasi apakah jadwal cadangan sudah jatuh tempo.
  bool isBackupDue({
    required DateTime now,
    required DateTime? lastBackupTime,
    required int frequencyDays,
  }) {
    if (frequencyDays <= 0) return false;
    if (lastBackupTime == null) return true;

    if (frequencyDays == 1) {
      final isSameDay = now.year == lastBackupTime.year &&
          now.month == lastBackupTime.month &&
          now.day == lastBackupTime.day;

      if (isSameDay) return false;

      // Checkpoint pk 02:00 pagi ala WhatsApp
      if (now.hour >= 2) return true;

      final diff = now.difference(lastBackupTime);
      return diff.inHours >= 24;
    }

    final diff = now.difference(lastBackupTime);
    return diff.inDays >= frequencyDays;
  }

  /// Ambil daftar semua berkas cadangan lokal (.dkhp) yang ada di direktori cadangan,
  /// terurut dari yang paling baru ke yang paling lama.
  Future<List<File>> getLocalBackups() async {
    final dir = await AppStorage.getBackupsDirectory();
    if (!dir.existsSync()) return [];

    final list = <File>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.dkhp') ||
            lower.endsWith('.dhkp') ||
            lower.endsWith('.bak')) {
          list.add(entity);
        }
      }
    }

    list.sort((a, b) {
      DateTime aTime;
      DateTime bTime;
      try {
        aTime = a.lastModifiedSync();
      } catch (_) {
        aTime = DateTime.fromMillisecondsSinceEpoch(0);
      }
      try {
        bTime = b.lastModifiedSync();
      } catch (_) {
        bTime = DateTime.fromMillisecondsSinceEpoch(0);
      }
      return bTime.compareTo(aTime);
    });

    return list;
  }

  /// Memangkas berkas cadangan lokal lama agar jumlahnya tidak melebihi [maxFiles] (default: 3).
  /// Sesuai aturan: jika berkas cadangan > 3, berkas paling lama otomatis dihapus.
  Future<List<File>> pruneOldBackups({int maxFiles = maxRetainedBackups}) async {
    final dir = await AppStorage.getBackupsDirectory();
    if (!dir.existsSync()) return [];

    final files = <File>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.dkhp') ||
            lower.endsWith('.dhkp') ||
            lower.endsWith('.bak')) {
          files.add(entity);
        }
      }
    }

    // Urutkan dari yang terlama ke terbaru (ascending)
    files.sort((a, b) {
      DateTime aTime;
      DateTime bTime;
      try {
        aTime = a.lastModifiedSync();
      } catch (_) {
        aTime = DateTime.fromMillisecondsSinceEpoch(0);
      }
      try {
        bTime = b.lastModifiedSync();
      } catch (_) {
        bTime = DateTime.fromMillisecondsSinceEpoch(0);
      }
      return aTime.compareTo(bTime);
    });

    final deleted = <File>[];
    while (files.length > maxFiles) {
      final oldest = files.removeAt(0);
      try {
        if (oldest.existsSync()) {
          oldest.deleteSync();
          deleted.add(oldest);
        }
      } catch (_) {}
    }

    return files;
  }

  /// Eksekusi pembuatan cadangan perubahan (baik manual maupun otomatis).
  /// Menyimpan file .dkhp baru yang memuat sidik jari berkas DHKP dasar (`dhkpFingerprint`)
  /// beserta data perubahan & gambar dokumentasi, merotasi maksimal 3 file, dan mereset dirty status.
  Future<File?> performBackup({
    bool? onlyDkhpData,
    String? customPrefix,
    Future<String> Function(String fileName)? customExporter,
    bool enforcePreviousDhkpMatch = false,
  }) async {
    final onlyData = onlyDkhpData ?? await getOnlyDkhpData();
    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final dateStr =
        '${now.year}${pad2(now.month)}${pad2(now.day)}_${pad2(now.hour)}${pad2(now.minute)}${pad2(now.second)}';
    final prefix = customPrefix ??
        (onlyData ? 'cadangan_dkhp_data' : 'cadangan_dkhp_lengkap');
    final fileName = '${prefix}_$dateStr';

    String filePath;
    if (customExporter != null) {
      filePath = await customExporter(fileName);
    } else {
      final currentRecords = await BlokDataStore.instance.loadAll();
      if (currentRecords.isEmpty) {
        throw const DhkpBackupValidationException(
          'Tidak dapat membuat cadangan: Belum ada berkas DHKP yang dimuat di aplikasi.',
        );
      }

      if (enforcePreviousDhkpMatch) {
        final existingBackups = await getLocalBackups();
        if (existingBackups.isNotEmpty) {
          final prevManifest = await DhkpPackageHelper.readBackupManifest(
            existingBackups.first.path,
          );
          final prevFp =
              (prevManifest?['dhkpFingerprint'] as String?)?.trim() ?? '';
          final currentFp = DhkpPackageHelper.computeDhkpFingerprint(
            currentRecords,
          );
          if (prevFp.isNotEmpty &&
              currentFp.isNotEmpty &&
              prevFp != currentFp) {
            throw const DhkpBackupValidationException(
              'Tidak dapat membuat cadangan: Berkas DHKP saat ini berbeda dengan berkas DHKP pada cadangan sebelumnya.',
            );
          }
        }
      }

      filePath = await BlokDataStore.instance.exportDkhp(
        fileName: fileName,
        includePhotos: !onlyData,
        deltaOnly: true,
      );
    }

    final file = File(filePath);
    if (file.existsSync()) {
      final size = file.lengthSync();
      await setInt(_lastBackupTimeKey, now.millisecondsSinceEpoch);
      await setInt(_lastBackupSizeKey, size);
      await setString(_lastBackupPathKey, file.path);
      await clearDirty();

      // Pangkas berkas cadangan agar maksimal 3 berkas tersimpan
      await pruneOldBackups(maxFiles: maxRetainedBackups);

      return file;
    }
    return null;
  }

  /// Pengecekan startup aplikasi: dijalankan otomatis saat aplikasi dibuka.
  /// Hanya melakukan ekspor jika jadwal terpenuhi dan ada perubahan data
  /// (atau belum ada cadangan) tanpa memerlukan kata sandi manual.
  Future<bool> runIfNeeded({
    DateTime? now,
    Future<String> Function(String fileName)? exportCsv,
  }) async {
    final current = now ?? DateTime.now();
    final frequency = await getFrequencyDays();
    if (frequency <= 0) return false;

    final lastTime = await getLastBackupTime();
    final due = isBackupDue(
      now: current,
      lastBackupTime: lastTime,
      frequencyDays: frequency,
    );
    if (!due) return false;

    final dirty = await isDirty();
    final existingBackups = await getLocalBackups();
    if (!dirty && existingBackups.isNotEmpty) {
      return false;
    }

    try {
      final result = await performBackup(customExporter: exportCsv);
      return result != null;
    } catch (_) {
      return false;
    }
  }
}
