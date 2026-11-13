import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'app_storage.dart';
import 'backup_password_store.dart';
import 'base_preferences_store.dart';
import 'blok_backup_scheduler.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'dkhp_package_helper.dart';

/// Eksepsi keamanan ketika enkripsi/dekripsi atau validasi [BlokChangeRecord] gagal.
class BlokSyncSecurityException implements Exception {
  final String message;
  const BlokSyncSecurityException(this.message);

  @override
  String toString() => 'BlokSyncSecurityException: $message';
}

/// Hasil dekripsi dan validasi berkas perubahan `.bin`.
class BlokChangeDecryptResult {
  final BlokChangeRecord? record;
  final bool isLegacyFormat;
  final String? warningMessage;

  const BlokChangeDecryptResult({
    required this.record,
    this.isLegacyFormat = false,
    this.warningMessage,
  });
}

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

  static const Set<String> _allowedJsonKeys = {
    'id',
    'blok',
    'nop',
    'tahunBayar',
    'petugas',
    'timestamp',
    'statusBayar',
    'tanggalBayar',
    'catatan',
    'namaFoto',
    'petugasFolder',
    'namaWajibPajak',
    'alamatObjek',
    'alamatWp',
    'dhkpFingerprint',
  };

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
      id: json['id']?.toString() ?? '',
      blok: json['blok']?.toString() ?? '',
      nop: json['nop']?.toString() ?? '',
      tahunBayar: json['tahunBayar']?.toString() ?? '',
      petugas: json['petugas']?.toString() ?? '',
      timestamp: json['timestamp'] is int ? json['timestamp'] as int : 0,
      statusBayar: json['statusBayar']?.toString(),
      tanggalBayar: json['tanggalBayar']?.toString(),
      catatan: json['catatan']?.toString(),
      namaFoto: json['namaFoto']?.toString(),
      petugasFolder: json['petugasFolder']?.toString(),
      namaWajibPajak: json['namaWajibPajak']?.toString(),
      alamatObjek: json['alamatObjek']?.toString(),
      alamatWp: json['alamatWp']?.toString(),
      dhkpFingerprint: json['dhkpFingerprint']?.toString(),
    );
  }

  /// Memvalidasi struktur, skema, dan keamanan isi data record perubahan.
  bool validateSchema({Map<String, dynamic>? rawMap}) {
    if (rawMap != null) {
      for (final key in rawMap.keys) {
        if (!_allowedJsonKeys.contains(key)) return false;
      }
      if (rawMap['timestamp'] is! int) return false;
    }

    if (id.isEmpty || id.length > 128) return false;
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id)) return false;

    final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNop.length != 18) return false;

    if (blok.length > 16 || !RegExp(r'^[0-9]*$').hasMatch(blok)) return false;

    if (tahunBayar.isNotEmpty) {
      final year = int.tryParse(tahunBayar);
      if (year == null || year < 1990 || year > 2100) return false;
    }

    // Timestamp harus masuk akal (>= tahun 2000 dan tidak lebih dari +24 jam ke depan)
    const minTimestamp = 946684800000;
    final maxTimestamp =
        DateTime.now().millisecondsSinceEpoch +
        const Duration(days: 1).inMilliseconds;
    if (timestamp < minTimestamp || timestamp > maxTimestamp) return false;

    if (petugas.isEmpty ||
        petugas.length > 64 ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(petugas)) {
      return false;
    }

    if (petugasFolder != null && petugasFolder!.isNotEmpty) {
      if (petugasFolder!.length > 80 ||
          petugasFolder!.contains('..') ||
          !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(petugasFolder!)) {
        return false;
      }
    }

    if (namaFoto != null && namaFoto!.isNotEmpty) {
      if (namaFoto!.length > 128 ||
          namaFoto!.contains('..') ||
          namaFoto!.contains('/') ||
          namaFoto!.contains(r'\') ||
          !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(namaFoto!)) {
        return false;
      }
    }

    if (dhkpFingerprint != null && dhkpFingerprint!.isNotEmpty) {
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(dhkpFingerprint!)) {
        return false;
      }
    }

    return true;
  }

  // --- Format Berversi v2: AEAD AES-256-GCM + PBKDF2-HMAC-SHA256 ---
  //
  // Layout Biner Format v2:
  // - [0..3]   Magic identifier : "CPBB" (4 byte: 0x43, 0x50, 0x42, 0x42)
  // - [4]      Format version   : 0x02 (1 byte)
  // - [5]      KDF identifier   : 0x01 = PBKDF2-HMAC-SHA256 (1 byte)
  // - [6..9]   KDF iterations   : uint32 Big-Endian (4 byte)
  // - [10..25] Salt             : 16 byte acak kriptografis
  // - [26..37] Nonce            : 12 byte acak kriptografis
  // - [38..N-17] Ciphertext     : Payload terenkripsi AES-256-GCM (AAD = header [0..37])
  // - [N-16..N-1] Auth Tag (MAC): 16 byte GCM authentication tag

  static const List<int> magic = [0x43, 0x50, 0x42, 0x42]; // "CPBB"
  static const int formatVersionV2 = 0x02;
  static const int kdfIdPbkdf2Sha256 = 0x01;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _v2HeaderLength =
      4 + 1 + 1 + 4 + _saltLength + _nonceLength; // 38 bytes

  static int pbkdf2Iterations = 100000;

  @visibleForTesting
  static void setPbkdf2IterationsForTesting(int iterations) {
    pbkdf2Iterations = iterations.clamp(1000, 2000000);
  }

  /// Hanya digunakan untuk kompatibilitas pembacaan migrasi berkas legacy v1 (AES-CBC).
  /// Dilarang digunakan untuk mengenkripsi berkas baru di produksi.
  static const String _legacyV1FallbackKey =
      'CekPBBCianjur-PerubahanLog-kunci-v1';

  static String? _configuredSecret;

  @visibleForTesting
  static void setSecretForTesting(String? secret) {
    _configuredSecret = secret;
  }

  static final AesGcm _aesGcm = AesGcm.with256bits();

  static Future<SecretKey> _deriveAesGcmKey({
    required String secret,
    required List<int> salt,
    required int iterations,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
  }

  static String _resolveEncryptionSecret(String? secret) {
    final candidate = (secret != null && secret.trim().isNotEmpty)
        ? secret.trim()
        : (_configuredSecret?.trim() ?? '');
    if (candidate.isEmpty) {
      throw const BlokSyncSecurityException(
        'Kunci rahasia sinkronisasi bersama belum dikonfigurasi. '
        'Atur kata sandi sinkronisasi/cadangan terlebih dahulu.',
      );
    }
    return candidate;
  }

  /// Mengenkripsi payload JSON menjadi berkas biner `.bin` Format v2
  /// menggunakan PBKDF2-HMAC-SHA256 (256-bit key, 16-byte random salt) dan
  /// AES-256-GCM (12-byte random nonce, 16-byte authentication tag).
  Future<Uint8List> toEncryptedBytes({String? secret}) async {
    final effectiveSecret = _resolveEncryptionSecret(secret);
    final jsonStr = jsonEncode(toJson());
    final plainBytes = utf8.encode(jsonStr);

    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
    final nonce = Uint8List.fromList(_aesGcm.newNonce());
    final iterations = pbkdf2Iterations.clamp(1000, 2000000);

    final iterBytes = ByteData(4)..setUint32(0, iterations, Endian.big);
    final header = Uint8List.fromList([
      ...magic,
      formatVersionV2,
      kdfIdPbkdf2Sha256,
      ...iterBytes.buffer.asUint8List(),
      ...salt,
      ...nonce,
    ]);

    final secretKey = await _deriveAesGcmKey(
      secret: effectiveSecret,
      salt: salt,
      iterations: iterations,
    );

    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: nonce,
      aad: header,
    );

    return Uint8List.fromList([
      ...header,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// Memeriksa apakah byte diawali header Format v2 yang valid.
  static bool isV2Format(Uint8List fileBytes) {
    if (fileBytes.length < _v2HeaderLength + _tagLength + 2) return false;
    for (var i = 0; i < magic.length; i++) {
      if (fileBytes[i] != magic[i]) return false;
    }
    if (fileBytes[4] != formatVersionV2) return false;
    if (fileBytes[5] != kdfIdPbkdf2Sha256) return false;
    final iterations = ByteData.sublistView(
      fileBytes,
      6,
      10,
    ).getUint32(0, Endian.big);
    return iterations >= 1000 && iterations <= 2000000;
  }

  /// Mendekripsi berkas biner `.bin` dengan verifikasi integritas AEAD (Format v2)
  /// atau jalur migrasi tervalidasi ketat untuk berkas legacy v1 apabila [allowLegacy] aktif.
  static Future<BlokChangeDecryptResult> decryptWithDetails(
    Uint8List fileBytes, {
    String? secret,
    List<String> additionalSecrets = const [],
    bool allowLegacy = false,
  }) async {
    if (fileBytes.length < magic.length + 16) {
      return const BlokChangeDecryptResult(
        record: null,
        warningMessage: 'Ukuran berkas perubahan terlalu pendek atau rusak.',
      );
    }
    for (var i = 0; i < magic.length; i++) {
      if (fileBytes[i] != magic[i]) {
        return const BlokChangeDecryptResult(
          record: null,
          warningMessage: 'Header magic berkas perubahan tidak dikenali.',
        );
      }
    }

    final secretCandidates = <String>{
      if (secret != null && secret.trim().isNotEmpty) secret.trim(),
      for (final s in additionalSecrets)
        if (s.trim().isNotEmpty) s.trim(),
      if (_configuredSecret != null && _configuredSecret!.trim().isNotEmpty)
        _configuredSecret!.trim(),
    };

    // 1. Jalur utama: Format v2 (AES-256-GCM + PBKDF2-HMAC-SHA256)
    if (isV2Format(fileBytes)) {
      if (secretCandidates.isEmpty) {
        return const BlokChangeDecryptResult(
          record: null,
          warningMessage:
              'Kunci rahasia sinkronisasi belum dikonfigurasi untuk membuka berkas v2.',
        );
      }

      final iterations = ByteData.sublistView(
        fileBytes,
        6,
        10,
      ).getUint32(0, Endian.big);
      final salt = fileBytes.sublist(10, 10 + _saltLength);
      final nonce = fileBytes.sublist(10 + _saltLength, _v2HeaderLength);
      final header = fileBytes.sublist(0, _v2HeaderLength);
      final cipherAndTag = fileBytes.sublist(_v2HeaderLength);
      final cipherText = cipherAndTag.sublist(
        0,
        cipherAndTag.length - _tagLength,
      );
      final tag = cipherAndTag.sublist(cipherAndTag.length - _tagLength);

      for (final cand in secretCandidates) {
        try {
          final key = await _deriveAesGcmKey(
            secret: cand,
            salt: salt,
            iterations: iterations,
          );
          final decryptedBytes = await _aesGcm.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
            secretKey: key,
            aad: header,
          );
          final jsonStr = utf8.decode(decryptedBytes);
          final decoded = jsonDecode(jsonStr);
          if (decoded is! Map<String, dynamic>) {
            return const BlokChangeDecryptResult(
              record: null,
              warningMessage: 'Format JSON berkas perubahan v2 tidak valid.',
            );
          }
          final record = BlokChangeRecord.fromJson(decoded);
          if (!record.validateSchema(rawMap: decoded)) {
            return const BlokChangeDecryptResult(
              record: null,
              warningMessage:
                  'Skema data berkas perubahan v2 tidak memenuhi standar keamanan.',
            );
          }
          return BlokChangeDecryptResult(record: record, isLegacyFormat: false);
        } on SecretBoxAuthenticationError {
          // Coba kandidat secret berikutnya
        } catch (_) {
          // Coba kandidat secret berikutnya
        }
      }

      return const BlokChangeDecryptResult(
        record: null,
        warningMessage:
            'Verifikasi autentikasi integritas (GCM tag) gagal atau kunci rahasia tidak cocok.',
      );
    }

    // 2. Jalur kompatibilitas terbatas: Format Legacy v1 (AES-256-CBC tanpa MAC)
    if (!allowLegacy) {
      return const BlokChangeDecryptResult(
        record: null,
        isLegacyFormat: true,
        warningMessage:
            'Berkas perubahan menggunakan format lama (v1) tanpa autentikasi integritas.',
      );
    }

    final payloadLength = fileBytes.length - magic.length;
    if (payloadLength < 32 || payloadLength % 16 != 0) {
      return const BlokChangeDecryptResult(
        record: null,
        isLegacyFormat: true,
        warningMessage: 'Ukuran blok cipher berkas legacy v1 tidak valid.',
      );
    }

    final iv = enc.IV(fileBytes.sublist(magic.length, magic.length + 16));
    final encrypted = enc.Encrypted(fileBytes.sublist(magic.length + 16));
    final legacyCandidates = <String>{
      ...secretCandidates,
      _legacyV1FallbackKey,
    };

    for (final cand in legacyCandidates) {
      try {
        final digest = legacy_crypto.sha256.convert(utf8.encode(cand));
        final key = enc.Key(Uint8List.fromList(digest.bytes));
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
        final jsonStr = utf8.decode(decrypted);
        final decoded = jsonDecode(jsonStr);
        if (decoded is! Map<String, dynamic>) continue;

        final record = BlokChangeRecord.fromJson(decoded);
        if (!record.validateSchema(rawMap: decoded)) {
          return const BlokChangeDecryptResult(
            record: null,
            isLegacyFormat: true,
            warningMessage:
                'Berkas perubahan legacy v1 ditolak karena struktur/skema data tidak valid.',
          );
        }

        return BlokChangeDecryptResult(
          record: record,
          isLegacyFormat: true,
          warningMessage:
              'Berkas perubahan format lama (v1) berhasil divalidasi dan dimigrasikan ke format v2.',
        );
      } catch (_) {
        // Coba kandidat berikutnya
      }
    }

    return const BlokChangeDecryptResult(
      record: null,
      isLegacyFormat: true,
      warningMessage:
          'Berkas perubahan format lama (v1) tidak dapat diverifikasi atau didekripsi.',
    );
  }

  /// Mendekripsi berkas biner `.bin` dan mengembalikannya ke objek [BlokChangeRecord].
  static Future<BlokChangeRecord?> fromEncryptedBytes(
    Uint8List fileBytes, {
    String? secret,
    List<String> additionalSecrets = const [],
    bool allowLegacy = false,
  }) async {
    final result = await decryptWithDetails(
      fileBytes,
      secret: secret,
      additionalSecrets: additionalSecrets,
      allowLegacy: allowLegacy,
    );
    return result.record;
  }

  /// Helper pembuat berkas legacy v1 khusus pengujian migrasi.
  @visibleForTesting
  Uint8List toLegacyV1EncryptedBytesForTesting({String? secret}) {
    final jsonStr = jsonEncode(toJson());
    final plainBytes = utf8.encode(jsonStr);
    final effectiveSecret = (secret != null && secret.isNotEmpty)
        ? secret
        : _legacyV1FallbackKey;
    final digest = legacy_crypto.sha256.convert(utf8.encode(effectiveSecret));
    final key = enc.Key(Uint8List.fromList(digest.bytes));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
    return Uint8List.fromList([...magic, ...iv.bytes, ...encrypted.bytes]);
  }
}

/// Layanan sinkronisasi otomatis DHKP berbasis partisi blok & delta perubahan terenkripsi.
///
/// Fitur utama:
/// 1. Berkas log perubahan dienkripsi penuh menggunakan AEAD AES-256-GCM + PBKDF2-HMAC-SHA256
///    (Format v2) berekstensi `.bin` agar aman dari penyadapan maupun pemalsuan di Drive bersama.
/// 2. Dipecah per blok (`perubahan/blok_<nomor>/`) sehingga saat membuka DHKP, aplikasi hanya
///    mengunduh perubahan blok tersebut tanpa menyedot seluruh desa.
/// 3. Foto selfie/bukti tersimpan di folder petugas masing-masing (`<petugasFolder>/photos/`).
/// 4. Mendukung migrasi tervalidasi dari berkas legacy v1 ke Format v2 secara otomatis.
class BlokSyncService extends BasePreferencesStore {
  BlokSyncService._();
  static final instance = BlokSyncService._();

  static const String _keyProcessedChanges = 'blok_sync_processed_change_ids';
  static const String _keyLastSyncMillis = 'blok_sync_last_millis';
  static const String _keySharedSyncSecret = 'blok_sync_shared_secret';

  Directory? _mockSyncDirectory;
  final List<String> _lastSyncWarnings = <String>[];

  /// Daftar peringatan dari proses sinkronisasi terakhir (misal berkas legacy tidak terverifikasi).
  List<String> get lastSyncWarnings => List.unmodifiable(_lastSyncWarnings);

  @visibleForTesting
  void setMockSyncDirectory(Directory? dir) {
    _mockSyncDirectory = dir;
  }

  /// Menyimpan kunci rahasia bersama (shared secret) tim ke [FlutterSecureStorage].
  Future<void> setSharedSecret(String secret) async {
    final trimmed = secret.trim();
    if (trimmed.length < 8) {
      throw const FormatException(
        'Kunci rahasia sinkronisasi harus terdiri dari minimal 8 karakter.',
      );
    }
    await writeSecureOnly(_keySharedSyncSecret, trimmed);
  }

  /// Mengambil kunci rahasia bersama yang dikonfigurasi di [FlutterSecureStorage].
  Future<String?> getSharedSecret() async {
    final stored = await readSecureWithMigration(_keySharedSyncSecret);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return null;
  }

  /// Menghapus kunci rahasia bersama dari [FlutterSecureStorage].
  Future<void> clearSharedSecret() async {
    await deleteSecureOnly(_keySharedSyncSecret);
  }

  /// Memeriksa apakah kunci rahasia sinkronisasi sudah tersedia (baik melalui
  /// kunci sinkronisasi khusus maupun kata sandi cadangan DHKP di secure storage).
  Future<bool> hasConfiguredSecret() async {
    final resolved = await resolveSyncSecret();
    return resolved != null && resolved.isNotEmpty;
  }

  /// Menentukan kunci rahasia aktif untuk operasi enkripsi/dekripsi sinkronisasi.
  /// Urutan prioritas:
  /// 1. Kunci sinkronisasi bersama di [FlutterSecureStorage] (`blok_sync_shared_secret`).
  /// 2. Kata sandi cadangan DHKP di [BackupPasswordStore] (`dhkp_backup_password`).
  /// 3. Secret pengujian (`BlokChangeRecord._configuredSecret`) jika diatur pada unit test.
  Future<String?> resolveSyncSecret() async {
    final dedicated = await getSharedSecret();
    if (dedicated != null && dedicated.isNotEmpty) {
      return dedicated;
    }
    final backupPass = await BackupPasswordStore.instance.read();
    if (backupPass != null && backupPass.trim().isNotEmpty) {
      return backupPass.trim();
    }
    final testSecret = BlokChangeRecord._configuredSecret;
    if (testSecret != null && testSecret.trim().isNotEmpty) {
      return testSecret.trim();
    }
    return null;
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
    final sanitized = username.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'petugas_umum' : sanitized;
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
    final trimmed = current.length > 5000
        ? current.skip(current.length - 5000).toSet()
        : current;
    await setString(_keyProcessedChanges, jsonEncode(trimmed.toList()));
  }

  /// Mencatat dan mengekspor satu perubahan lokal ke berkas `.bin` terenkripsi (Format v2)
  /// di folder perubahan Drive.
  ///
  /// Apabila kunci rahasia bersama belum dikonfigurasi dan [requireSecret] bernilai `false`
  /// (default untuk pemanggilan latar belakang), fungsi ini tidak akan menulis berkas
  /// dengan kunci statis dan mengembalikan `null`. Jika [requireSecret] bernilai `true`,
  /// akan melempar [BlokSyncSecurityException].
  Future<File?> recordChange({
    required BlokRecord record,
    String? statusBayar,
    String? tanggalBayar,
    String? catatan,
    String? namaFoto,
    File? sourcePhotoFile,
    String? secret,
    bool requireSecret = false,
  }) async {
    final effectiveSecret = secret?.trim().isNotEmpty == true
        ? secret!.trim()
        : await resolveSyncSecret();
    if (effectiveSecret == null || effectiveSecret.isEmpty) {
      if (requireSecret) {
        throw const BlokSyncSecurityException(
          'Tidak dapat menulis log perubahan: kunci rahasia sinkronisasi bersama belum dikonfigurasi.',
        );
      }
      debugPrint(
        'BlokSyncService: Melewati penulisan berkas .bin karena kunci rahasia sinkronisasi belum dikonfigurasi.',
      );
      return null;
    }

    final scheduler = BlokBackupScheduler.instance;
    final account = await scheduler.getGoogleAccount();
    final petugas = sanitizePetugasFolderName(account);
    final petugasFolder = 'petugas_$petugas';

    final now = DateTime.now();
    final cleanNop = record.nop.replaceAll(RegExp(r'[^0-9]'), '');
    final changeId =
        'change_${now.millisecondsSinceEpoch}_${cleanNop}_$petugas';

    final allRecords = await BlokDataStore.instance.loadAll();
    final dhkpFingerprint = DhkpPackageHelper.computeDhkpFingerprint(
      allRecords.isEmpty ? [record] : allRecords,
    );

    final rawPhotoName = namaFoto ?? record.namaFoto;
    final safePhotoName = (rawPhotoName != null && rawPhotoName.isNotEmpty)
        ? rawPhotoName
              .split(RegExp(r'[/\\]'))
              .last
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        : rawPhotoName;

    final change = BlokChangeRecord(
      id: changeId,
      blok: record.blok.replaceAll(RegExp(r'[^0-9]'), ''),
      nop: record.nop,
      tahunBayar: record.tahunBayar,
      petugas: petugas,
      timestamp: now.millisecondsSinceEpoch,
      statusBayar: statusBayar ?? record.statusBayar,
      tanggalBayar: tanggalBayar ?? record.tanggalBayar,
      catatan: catatan ?? record.catatan,
      namaFoto: safePhotoName,
      petugasFolder: petugasFolder,
      namaWajibPajak: record.namaWajibPajak,
      alamatObjek: record.alamatObjek,
      alamatWp: record.alamatWp,
      dhkpFingerprint: dhkpFingerprint,
    );

    final syncRoot = await getSyncRootDirectory();

    // 1. Simpan foto ke folder pribadi petugas di Drive jika ada foto baru
    if (sourcePhotoFile != null &&
        await sourcePhotoFile.exists() &&
        change.namaFoto != null &&
        change.namaFoto!.isNotEmpty) {
      final officerPhotosDir = Directory(
        '${syncRoot.path}/$petugasFolder/photos',
      );
      if (!await officerPhotosDir.exists()) {
        await officerPhotosDir.create(recursive: true);
      }
      final destPhoto = File('${officerPhotosDir.path}/${change.namaFoto}');
      await sourcePhotoFile.copy(destPhoto.path);
    }

    // 2. Simpan file log perubahan terenkripsi Format v2 ke folder perubahan per-blok
    final blokFolder = change.blok.isEmpty ? 'umum' : change.blok;
    final changesDir = Directory('${syncRoot.path}/perubahan/blok_$blokFolder');
    if (!await changesDir.exists()) {
      await changesDir.create(recursive: true);
    }

    final encryptedBytes = await change.toEncryptedBytes(
      secret: effectiveSecret,
    );
    final logFile = File('${changesDir.path}/$changeId.bin');
    await logFile.writeAsBytes(encryptedBytes, flush: true);

    // Tandai ID ini sudah diproses di lokal agar tidak di-reapply
    await markChangesProcessed([changeId]);

    return logFile;
  }

  /// Sinkronisasi otomatis saat membuka DHKP untuk blok tertentu (atau seluruh blok).
  ///
  /// Membaca semua file `.bin` terenkripsi di folder `perubahan/blok_<blok>/`,
  /// memverifikasi integritasnya, memperbarui [BlokDataStore], mengambil foto dari folder
  /// petugas jika ada foto baru, serta memigrasikan berkas legacy v1 yang valid ke Format v2.
  Future<int> syncCurrentScope({
    String? blok,
    Directory? customSyncRoot,
    String? secret,
    bool allowLegacyMigration = true,
  }) async {
    _lastSyncWarnings.clear();

    final syncRoot = customSyncRoot ?? await getSyncRootDirectory();
    final changesBase = Directory('${syncRoot.path}/perubahan');
    if (!await changesBase.exists()) {
      return 0;
    }

    final targetFolders = <Directory>[];
    if (blok != null &&
        blok.isNotEmpty &&
        blok != 'Semua' &&
        blok != 'Semua Blok') {
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

    final dedicatedSecret = await getSharedSecret();
    final backupPassword = await BackupPasswordStore.instance.read();
    final effectiveSecret = (secret != null && secret.trim().isNotEmpty)
        ? secret.trim()
        : await resolveSyncSecret();
    final extraSecrets = <String>[
      if (dedicatedSecret != null && dedicatedSecret.isNotEmpty)
        dedicatedSecret,
      if (backupPassword != null && backupPassword.trim().isNotEmpty)
        backupPassword.trim(),
    ];

    final processedIds = await getProcessedChangeIds();
    final newlyProcessedIds = <String>[];
    int appliedCount = 0;

    final localPhotosDir = await DhkpPackageHelper.photosDirectory();

    for (final folder in targetFolders) {
      final files = folder.listSync(followLinks: false).whereType<File>();
      for (final file in files) {
        final ext = file.path.toLowerCase();
        if (!ext.endsWith('.bin') && !ext.endsWith('.dat')) continue;

        final fileName = file.uri.pathSegments.last;
        final bytes = await file.readAsBytes();
        final decryptResult = await BlokChangeRecord.decryptWithDetails(
          bytes,
          secret: effectiveSecret,
          additionalSecrets: extraSecrets,
          allowLegacy: allowLegacyMigration,
        );

        final change = decryptResult.record;
        if (change == null) {
          final reason =
              decryptResult.warningMessage ?? 'Gagal memverifikasi berkas.';
          _lastSyncWarnings.add('$fileName: $reason');
          continue;
        }

        if (processedIds.contains(change.id)) {
          // Jika berkas masih format legacy v1 dan kita sudah punya secret v2, tetap migrasikan berkasnya
          if (decryptResult.isLegacyFormat &&
              effectiveSecret != null &&
              effectiveSecret.isNotEmpty) {
            try {
              final reEncrypted = await change.toEncryptedBytes(
                secret: effectiveSecret,
              );
              await file.writeAsBytes(reEncrypted, flush: true);
            } catch (_) {}
          }
          continue;
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

        // Pembatasan risiko khusus berkas legacy v1:
        // Berkas legacy v1 tidak memiliki AEAD tag, sehingga dilarang menambahkan NOP baru
        // yang belum ada di BlokDataStore lokal apabila data lokal sudah dimuat.
        if (decryptResult.isLegacyFormat &&
            existingRecords.isNotEmpty &&
            targetRecord == null) {
          _lastSyncWarnings.add(
            '$fileName: Berkas legacy v1 ditolak karena NOP ${change.nop} tidak terdaftar di DHKP lokal.',
          );
          continue;
        }

        // Validasi sidik jari berkas DHKP:
        // Jika berkas DHKP lokal sudah dimuat tetapi memiliki sidik jari berbeda
        // dan NOP perubahan tidak ada di berkas DHKP lokal, tolak perubahan tersebut.
        if (existingRecords.isNotEmpty &&
            change.dhkpFingerprint != null &&
            change.dhkpFingerprint!.isNotEmpty) {
          final localFp = DhkpPackageHelper.computeDhkpFingerprint(
            existingRecords,
          );
          if (localFp != change.dhkpFingerprint && targetRecord == null) {
            _lastSyncWarnings.add(
              '$fileName: Sidik jari DHKP tidak cocok dengan data lokal.',
            );
            continue;
          }
        }

        // Jika berkas berasal dari format legacy v1 dan berhasil divalidasi,
        // langsung enkripsi ulang (upgrade) ke Format v2 jika secret tersedia.
        if (decryptResult.isLegacyFormat) {
          if (decryptResult.warningMessage != null) {
            _lastSyncWarnings.add('$fileName: ${decryptResult.warningMessage}');
          }
          if (effectiveSecret != null && effectiveSecret.isNotEmpty) {
            try {
              final upgradedBytes = await change.toEncryptedBytes(
                secret: effectiveSecret,
              );
              await file.writeAsBytes(upgradedBytes, flush: true);
            } catch (e) {
              debugPrint(
                'BlokSyncService: Gagal mengenkripsi ulang berkas legacy $fileName ke v2: $e',
              );
            }
          }
        }

        // Terapkan perubahan data langsung
        final updatedRecord =
            (targetRecord ??
                    BlokRecord(
                      nop: change.nop,
                      namaWajibPajak:
                          change.namaWajibPajak ?? 'Wajib Pajak (Sync)',
                      tahunBayar: change.tahunBayar.isEmpty
                          ? '2026'
                          : change.tahunBayar,
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
        // (namaFoto dan petugasFolder sudah divalidasi bebas path traversal di validateSchema).
        if (change.namaFoto != null && change.namaFoto!.isNotEmpty) {
          final safePhoto = change.namaFoto!
              .split(RegExp(r'[/\\]'))
              .last
              .replaceAll('..', '');
          final rawOfficerFolder =
              change.petugasFolder ?? 'petugas_${change.petugas}';
          final safeOfficerFolder = rawOfficerFolder
              .split(RegExp(r'[/\\]'))
              .last
              .replaceAll('..', '');
          if (safePhoto.isNotEmpty && safeOfficerFolder.isNotEmpty) {
            final localPhoto = File('${localPhotosDir.path}/$safePhoto');
            if (!await localPhoto.exists()) {
              final sourcePhoto = File(
                '${syncRoot.path}/$safeOfficerFolder/photos/$safePhoto',
              );
              if (await sourcePhoto.exists()) {
                await sourcePhoto.copy(localPhoto.path);
              }
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
    _lastSyncWarnings.clear();
    BlokChangeRecord.pbkdf2Iterations = 100000;
    BlokChangeRecord.setSecretForTesting(null);
  }
}
