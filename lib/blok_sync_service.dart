import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'app_storage.dart';
import 'base_preferences_store.dart';
import 'blok_backup_scheduler.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'dkhp_package_helper.dart';

/// Satu tiket log perubahan data DHKP (Delta Change Record).
///
/// Menyimpan informasi perubahan granular per NOP (status bayar, catatan, foto)
/// tanpa perlu mengunggah ulang seluruh DHKP desa.
class BlokChangeRecord {
  final String id;
  final String blok;
  final String nop;
  final String tahunBayar;
  final String petugas;
  final int timestamp;
  final String? statusBayar;
  final String? tanggalBayar;
  final String? catatan;
  final String? namaFoto;
  final String? petugasFolder;
  final String? namaWajibPajak;
  final String? alamatObjek;
  final String? alamatWp;
  final String? dhkpFingerprint;

  const BlokChangeRecord({
    required this.id,
    required this.blok,
    required this.nop,
    required this.tahunBayar,
    required this.petugas,
    required this.timestamp,
    this.statusBayar,
    this.tanggalBayar,
    this.catatan,
    this.namaFoto,
    this.petugasFolder,
    this.namaWajibPajak,
    this.alamatObjek,
    this.alamatWp,
    this.dhkpFingerprint,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'blok': blok,
      'nop': nop,
      'tahunBayar': tahunBayar,
      'petugas': petugas,
      'timestamp': timestamp,
      if (statusBayar != null) 'statusBayar': statusBayar,
      if (tanggalBayar != null) 'tanggalBayar': tanggalBayar,
      if (catatan != null) 'catatan': catatan,
      if (namaFoto != null) 'namaFoto': namaFoto,
      if (petugasFolder != null) 'petugasFolder': petugasFolder,
      if (namaWajibPajak != null) 'namaWajibPajak': namaWajibPajak,
      if (alamatObjek != null) 'alamatObjek': alamatObjek,
      if (alamatWp != null) 'alamatWp': alamatWp,
      if (dhkpFingerprint != null && dhkpFingerprint!.isNotEmpty)
        'dhkpFingerprint': dhkpFingerprint,
    };
  }

  factory BlokChangeRecord.fromJson(Map<String, dynamic> json) {
    return BlokChangeRecord(
      id: json['id'] as String? ?? '',
      blok: json['blok'] as String? ?? '',
      nop: json['nop'] as String? ?? '',
      tahunBayar: json['tahunBayar'] as String? ?? '',
      petugas: json['petugas'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
      statusBayar: json['statusBayar'] as String?,
      tanggalBayar: json['tanggalBayar'] as String?,
      catatan: json['catatan'] as String?,
      namaFoto: json['namaFoto'] as String?,
      petugasFolder: json['petugasFolder'] as String?,
      namaWajibPajak: json['namaWajibPajak'] as String?,
      alamatObjek: json['alamatObjek'] as String?,
      alamatWp: json['alamatWp'] as String?,
      dhkpFingerprint: json['dhkpFingerprint'] as String?,
    );
  }

  // --- Enkripsi AES-256-CBC untuk File Perubahan (.bin / .dat) ---

  static const List<int> magic = [0x43, 0x50, 0x42, 0x42]; // "CPBB"
  static const String _defaultSecret = 'CekPBBCianjur-PerubahanLog-kunci-v1';
  static String? _configuredSecret;

  @visibleForTesting
  static void setSecretForTesting(String? secret) {
    _configuredSecret = secret;
  }

  static enc.Key _deriveKey(String secret) {
    final digest = sha256.convert(utf8.encode(secret));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  /// Mengenkripsi payload JSON menjadi berkas biner `.bin` dengan dynamic IV 16-byte acak.
  Uint8List toEncryptedBytes({String? secret}) {
    final jsonStr = jsonEncode(toJson());
    final plainBytes = utf8.encode(jsonStr);

    final effectiveSecret = (secret != null && secret.isNotEmpty)
        ? secret
        : (_configuredSecret ?? _defaultSecret);
    final key = _deriveKey(effectiveSecret);

    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    return Uint8List.fromList([...magic, ...iv.bytes, ...encrypted.bytes]);
  }

  /// Mendekripsi berkas biner `.bin` dan mengembalikannya ke objek [BlokChangeRecord].
  /// Mencoba kunci rahasia aktif (atau kata sandi cadangan pengguna), lalu fallback
  /// ke kunci default agar tetap kompatibel dengan berkas lama.
  static BlokChangeRecord? fromEncryptedBytes(Uint8List fileBytes, {String? secret}) {
    if (fileBytes.length < magic.length + 16) return null;
    for (var i = 0; i < magic.length; i++) {
      if (fileBytes[i] != magic[i]) return null;
    }

    final iv = enc.IV(fileBytes.sublist(magic.length, magic.length + 16));
    final encrypted = enc.Encrypted(fileBytes.sublist(magic.length + 16));

    final candidates = <String>{
      if (secret != null && secret.isNotEmpty) secret,
      if (_configuredSecret != null && _configuredSecret!.isNotEmpty) _configuredSecret!,
      _defaultSecret,
    };

    for (final cand in candidates) {
      try {
        final key = _deriveKey(cand);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
        final jsonStr = utf8.decode(decrypted);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return BlokChangeRecord.fromJson(map);
      } catch (_) {
        // Coba kandidat berikutnya
      }
    }
    return null;
  }
}

/// Layanan sinkronisasi otomatis DHKP berbasis partisi blok & delta perubahan terenkripsi.
///
/// Fitur utama:
/// 1. Berkas log perubahan dienkripsi penuh (AES-256-CBC) berekstensi `.bin` agar aman di Drive bersama.
/// 2. Dipecah per blok (`perubahan/blok_<nomor>/`) sehingga saat membuka DHKP, aplikasi hanya
///    mengunduh perubahan blok tersebut tanpa menyedot seluruh desa.
/// 3. Foto selfie/bukti tersimpan di folder petugas masing-masing (`<petugasFolder>/photos/`).
/// 4. Saat ada perubahan foto, aplikasi langsung mengambil/mengunduh foto dari folder petugas terkait
///    dan memperbarui data DHKP lokal seketika.
class BlokSyncService extends BasePreferencesStore {
  BlokSyncService._();
  static final instance = BlokSyncService._();

  static const String _keyProcessedChanges = 'blok_sync_processed_change_ids';
  static const String _keyLastSyncMillis = 'blok_sync_last_millis';

  Directory? _mockSyncDirectory;

  @visibleForTesting
  void setMockSyncDirectory(Directory? dir) {
    _mockSyncDirectory = dir;
  }

  /// Mendapatkan direktori pusat sinkronisasi Drive bersama.
  Future<Directory> getSyncRootDirectory() async {
    if (_mockSyncDirectory != null) return _mockSyncDirectory!;

    // Secara default diletakkan di Android/media/id.cianjur.pbb/shared_drive
    final mediaDir = await AppStorage.getMediaDirectory();
    final syncDir = Directory('${mediaDir.path}/shared_drive');
    if (!await syncDir.exists()) {
      await syncDir.create(recursive: true);
    }
    return syncDir;
  }

  /// Membersihkan email untuk nama folder petugas yang rapi (misal: "budi.santoso").
  String sanitizePetugasFolderName(String email) {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return 'petugas_umum';
    final username = trimmed.split('@').first;
    return username.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  }

  /// Mendapatkan daftar ID perubahan yang sudah pernah diproses di HP ini.
  Future<Set<String>> getProcessedChangeIds() async {
    final raw = await getString(_keyProcessedChanges);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Menandai satu atau lebih ID perubahan telah berhasil diterapkan.
  Future<void> markChangesProcessed(Iterable<String> ids) async {
    final current = await getProcessedChangeIds();
    current.addAll(ids);
    // Batasi cache ID perubahan terakhir agar SharedPreferences tidak membengkak
    final trimmed = current.length > 5000 ? current.skip(current.length - 5000).toSet() : current;
    await setString(_keyProcessedChanges, jsonEncode(trimmed.toList()));
  }

  /// Mencatat dan mengekspor satu perubahan lokal ke berkas `.bin` terenkripsi di folder perubahan Drive.
  Future<File> recordChange({
    required BlokRecord record,
    String? statusBayar,
    String? tanggalBayar,
    String? catatan,
    String? namaFoto,
    File? sourcePhotoFile,
  }) async {
    final scheduler = BlokBackupScheduler.instance;
    final account = await scheduler.getGoogleAccount();
    final petugas = sanitizePetugasFolderName(account);
    final petugasFolder = 'petugas_$petugas';

    final now = DateTime.now();
    final cleanNop = record.nop.replaceAll(RegExp(r'[^0-9]'), '');
    final changeId = 'change_${now.millisecondsSinceEpoch}_${cleanNop}_$petugas';

    final allRecords = await BlokDataStore.instance.loadAll();
    final dhkpFingerprint = DhkpPackageHelper.computeDhkpFingerprint(
      allRecords.isEmpty ? [record] : allRecords,
    );

    final change = BlokChangeRecord(
      id: changeId,
      blok: record.blok,
      nop: record.nop,
      tahunBayar: record.tahunBayar,
      petugas: petugas,
      timestamp: now.millisecondsSinceEpoch,
      statusBayar: statusBayar ?? record.statusBayar,
      tanggalBayar: tanggalBayar ?? record.tanggalBayar,
      catatan: catatan ?? record.catatan,
      namaFoto: namaFoto ?? record.namaFoto,
      petugasFolder: petugasFolder,
      namaWajibPajak: record.namaWajibPajak,
      alamatObjek: record.alamatObjek,
      alamatWp: record.alamatWp,
      dhkpFingerprint: dhkpFingerprint,
    );

    final syncRoot = await getSyncRootDirectory();

    // 1. Simpan foto ke folder pribadi petugas di Drive jika ada foto baru
    if (sourcePhotoFile != null && await sourcePhotoFile.exists() && change.namaFoto != null) {
      final officerPhotosDir = Directory('${syncRoot.path}/$petugasFolder/photos');
      if (!await officerPhotosDir.exists()) {
        await officerPhotosDir.create(recursive: true);
      }
      final destPhoto = File('${officerPhotosDir.path}/${change.namaFoto}');
      await sourcePhotoFile.copy(destPhoto.path);
    }

    // 2. Simpan file log perubahan terenkripsi ke folder perubahan per-blok
    final blokFolder = change.blok.isEmpty ? 'umum' : change.blok;
    final changesDir = Directory('${syncRoot.path}/perubahan/blok_$blokFolder');
    if (!await changesDir.exists()) {
      await changesDir.create(recursive: true);
    }

    final encryptedBytes = change.toEncryptedBytes();
    final logFile = File('${changesDir.path}/$changeId.bin');
    await logFile.writeAsBytes(encryptedBytes);

    // Tandai ID ini sudah diproses di lokal agar tidak di-reapply
    await markChangesProcessed([changeId]);

    return logFile;
  }

  /// Sinkronisasi otomatis saat membuka DHKP untuk blok tertentu (atau seluruh blok).
  ///
  /// Membaca semua file `.bin` terenkripsi di folder `perubahan/blok_<blok>/`,
  /// mendekripsi datanya, memperbarui [BlokDataStore], dan langsung mengambil foto dari folder
  /// petugas jika ada foto baru.
  Future<int> syncCurrentScope({
    String? blok,
    Directory? customSyncRoot,
  }) async {
    final syncRoot = customSyncRoot ?? await getSyncRootDirectory();
    final changesBase = Directory('${syncRoot.path}/perubahan');
    if (!await changesBase.exists()) {
      return 0;
    }

    final targetFolders = <Directory>[];
    if (blok != null && blok.isNotEmpty && blok != 'Semua' && blok != 'Semua Blok') {
      final cleanBlok = blok.replaceAll(RegExp(r'[^0-9]'), '');
      final dir = Directory('${changesBase.path}/blok_$cleanBlok');
      if (await dir.exists()) {
        targetFolders.add(dir);
      }
    } else {
      // Ambil seluruh folder blok yang ada di dalam folder perubahan
      for (final entity in changesBase.listSync(followLinks: false)) {
        if (entity is Directory) {
          targetFolders.add(entity);
        }
      }
    }

    if (targetFolders.isEmpty) return 0;

    final processedIds = await getProcessedChangeIds();
    final newlyProcessedIds = <String>[];
    int appliedCount = 0;

    final localPhotosDir = await DhkpPackageHelper.photosDirectory();

    for (final folder in targetFolders) {
      final files = folder.listSync(followLinks: false).whereType<File>();
      for (final file in files) {
        final ext = file.path.toLowerCase();
        if (!ext.endsWith('.bin') && !ext.endsWith('.dat')) continue;

        final bytes = await file.readAsBytes();
        final change = BlokChangeRecord.fromEncryptedBytes(bytes);
        if (change == null) continue;

        if (processedIds.contains(change.id)) {
          continue; // Sudah pernah diproses
        }

        // Ambil record yang cocok di BlokDataStore lokal
        final existingRecords = await BlokDataStore.instance.loadAll();
        final cleanChangeNop = change.nop.replaceAll(RegExp(r'[^0-9]'), '');

        BlokRecord? targetRecord;
        for (final r in existingRecords) {
          final cleanR = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
          if (cleanR == cleanChangeNop) {
            targetRecord = r;
            break;
          }
        }

        // Validasi sidik jari berkas DHKP:
        // Jika berkas DHKP lokal sudah dimuat tetapi memiliki sidik jari berbeda
        // dan NOP perubahan tidak ada di berkas DHKP lokal, tolak perubahan tersebut.
        if (existingRecords.isNotEmpty &&
            change.dhkpFingerprint != null &&
            change.dhkpFingerprint!.isNotEmpty) {
          final localFp = DhkpPackageHelper.computeDhkpFingerprint(existingRecords);
          if (localFp != change.dhkpFingerprint && targetRecord == null) {
            continue;
          }
        }

        // Terapkan perubahan data langsung
        final updatedRecord = (targetRecord ??
                BlokRecord(
                  nop: change.nop,
                  namaWajibPajak: change.namaWajibPajak ?? 'Wajib Pajak (Sync)',
                  tahunBayar: change.tahunBayar.isEmpty ? '2026' : change.tahunBayar,
                  tanggalBayar: change.tanggalBayar ?? '',
                ))
            .copyWith(
          statusBayar: change.statusBayar,
          tanggalBayar: change.tanggalBayar,
          catatan: change.catatan,
          namaFoto: change.namaFoto,
          namaWajibPajak: change.namaWajibPajak,
          alamatObjek: change.alamatObjek,
          alamatWp: change.alamatWp,
        );

        // Jika ada foto dan belum ada di memori lokal, ambil langsung dari folder petugas
        if (change.namaFoto != null && change.namaFoto!.isNotEmpty) {
          final localPhoto = File('${localPhotosDir.path}/${change.namaFoto}');
          if (!await localPhoto.exists()) {
            final officerFolder = change.petugasFolder ?? 'petugas_${change.petugas}';
            final sourcePhoto = File('${syncRoot.path}/$officerFolder/photos/${change.namaFoto}');
            if (await sourcePhoto.exists()) {
              await sourcePhoto.copy(localPhoto.path);
            }
          }
        }

        await BlokDataStore.instance.upsert(updatedRecord);
        newlyProcessedIds.add(change.id);
        appliedCount++;
      }
    }

    if (newlyProcessedIds.isNotEmpty) {
      await markChangesProcessed(newlyProcessedIds);
      await DhkpPackageHelper.refreshPhotoNamesCache();
      await setInt(_keyLastSyncMillis, DateTime.now().millisecondsSinceEpoch);
    }

    return appliedCount;
  }

  /// Reset preferensi untuk keperluan pengujian.
  @visibleForTesting
  void resetForTesting() {
    resetPrefsForTesting();
    _mockSyncDirectory = null;
  }
}
