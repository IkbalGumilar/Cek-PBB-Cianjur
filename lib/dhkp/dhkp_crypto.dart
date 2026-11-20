import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Enkripsi paket `.dkhp` menggunakan PBKDF2-HMAC-SHA256 dan AES-256-GCM.
///
/// Struktur Biner Format `DKH2` (Header 32 Byte):
/// - `[0..3]`     (4 B)  : Magic ASCII `"DKH2"` (`0x44, 0x4B, 0x48, 0x32`)
/// - `[4..19]`    (16 B) : Salt acak CSPRNG untuk `PBKDF2-HMAC-SHA256`
/// - `[20..31]`   (12 B) : Nonce acak CSPRNG untuk `AES-256-GCM`
/// - `[32..N-17]` (Var)  : Ciphertext `AES-256-GCM` dengan `AAD = header[0..31]`
/// - `[N-16..N-1]`(16 B) : GCM Authentication Tag (MAC)
class DhkpCrypto {
  DhkpCrypto._();

  static bool get _canUseIsolate {
    try {
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      return !bindingName.contains('Test');
    } catch (_) {
      return true;
    }
  }

  static const magic = [0x44, 0x4B, 0x48, 0x50]; // Legacy "DKHP" (AES-256-CBC)
  static const dkh2Magic = [0x44, 0x4B, 0x48, 0x32]; // Default "DKH2" (AES-256-GCM)
  static const _passwordMagic = dkh2Magic;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int saltOffset = 4;
  static const int nonceOffset = saltOffset + saltLength; // 20
  static const int headerLength = nonceOffset + nonceLength; // 32
  static const int ciphertextOffset = headerLength; // 32
  static const int minPasswordLength = 8;
  static const int pbkdf2Iterations = 600000;
  static const _legacySecret = 'CekPBBCianjur-DKHP-Package-Secret-v1';
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: pbkdf2Iterations,
    bits: 256,
  );
  static final _aesGcm = AesGcm.with256bits();

  /// Memvalidasi kata sandi enkripsi opsional dari input form atau parameter layanan.
  ///
  /// Mengembalikan pesan error berbahasa Indonesia jika kata sandi diisi namun kurang
  /// dari [minPasswordLength] karakter, atau `null` jika kosong/valid.
  static String? validateOptionalPassword(String? rawPassword) {
    final trimmed = rawPassword?.trim() ?? '';
    if (trimmed.isNotEmpty && trimmed.length < minPasswordLength) {
      return 'Kata sandi enkripsi .dkhp minimal $minPasswordLength karakter '
          '(saat ini ${trimmed.length}/$minPasswordLength), atau kosongkan untuk memakai Kunci Pemulihan aktif.';
    }
    return null;
  }

  static Future<Uint8List> _encryptBytesInternal(
    Uint8List plainBytes,
    String trimmedPassword,
  ) async {
    final salt = Uint8List.fromList(
      List<int>.generate(saltLength, (_) => Random.secure().nextInt(256)),
    );
    final nonce = _aesGcm.newNonce();
    final header = Uint8List.fromList([..._passwordMagic, ...salt, ...nonce]);
    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(trimmedPassword)),
      nonce: salt,
    );
    final box = await _aesGcm.encrypt(
      plainBytes,
      secretKey: key,
      nonce: nonce,
      aad: header,
    );
    return Uint8List.fromList([...header, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Mengenkripsi data paket `.dkhp` menggunakan format `DKH2` (`PBKDF2-HMAC-SHA256` + `AES-256-GCM`).
  ///
  /// Setiap berkas `.dkhp` memiliki tepat satu kunci enkripsi yang diturunkan dari [password]
  /// (baik Kata Sandi Backup kustom pengguna maupun Recovery Key unik instalasi) yang aktif
  /// saat backup dibuat. Tidak pernah menggunakan hardcoded shared secret.
  static Future<Uint8List> encryptBytes(
    Uint8List plainBytes, {
    required String password,
  }) async {
    final trimmedPassword = password.trim();
    if (trimmedPassword.length < minPasswordLength) {
      throw const FormatException(
        'Kata sandi backup harus terdiri dari minimal $minPasswordLength karakter.',
      );
    }

    if (_canUseIsolate) {
      return Isolate.run(
        () => _encryptBytesInternal(plainBytes, trimmedPassword),
      );
    }
    return _encryptBytesInternal(plainBytes, trimmedPassword);
  }

  /// Enkripsi warisan AES-256-CBC (`DKHP`) — HANYA untuk pengujian regresi pembacaan backup lama.
  /// Dilarang digunakan untuk membuat backup baru di kode produksi.
  @visibleForTesting
  static Uint8List encryptLegacyBytes(Uint8List plainBytes) {
    final digest = legacy_crypto.sha256.convert(utf8.encode(_legacySecret));
    final key = enc.Key(Uint8List.fromList(digest.bytes));
    final ivBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
    return Uint8List.fromList([...magic, ...ivBytes, ...encrypted.bytes]);
  }

  static Future<Uint8List?> _tryDecryptDkh2WithSecret(
    Uint8List fileBytes,
    String secret,
  ) async {
    final salt = fileBytes.sublist(saltOffset, nonceOffset);
    final nonce = fileBytes.sublist(nonceOffset, headerLength);
    final header = fileBytes.sublist(0, headerLength);
    final body = fileBytes.sublist(ciphertextOffset);
    final cipherText = body.sublist(0, body.length - tagLength);
    final tag = body.sublist(body.length - tagLength);
    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
    try {
      final plainBytes = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
        aad: header,
      );
      return Uint8List.fromList(plainBytes);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Future<Uint8List?> decryptBytes(
    Uint8List fileBytes, {
    String? password,
  }) async {
    if (_hasMagic(fileBytes, _passwordMagic)) {
      if (fileBytes.length < headerLength + tagLength) {
        throw const FormatException('Berkas backup terenkripsi tidak lengkap.');
      }

      final trimmedPassword = password?.trim();
      if (trimmedPassword == null || trimmedPassword.isEmpty) {
        throw const DkhpPasswordException(
          'Kata sandi atau kunci pemulihan diperlukan untuk membuka backup ini.',
        );
      }

      final decrypted = _canUseIsolate
          ? await Isolate.run(
              () => _tryDecryptDkh2WithSecret(fileBytes, trimmedPassword),
            )
          : await _tryDecryptDkh2WithSecret(fileBytes, trimmedPassword);
      if (decrypted != null) return decrypted;

      throw const DkhpPasswordException(
        'Kata sandi salah atau berkas backup telah berubah/rusak.',
      );
    }

    if (!_hasMagic(fileBytes, magic) || fileBytes.length < magic.length + 16) {
      return null;
    }
    return _decryptLegacyCbc(fileBytes);
  }

  static Uint8List? _decryptLegacyCbc(Uint8List fileBytes) {
    final digest = legacy_crypto.sha256.convert(utf8.encode(_legacySecret));
    final key = enc.Key(Uint8List.fromList(digest.bytes));
    final iv = enc.IV(fileBytes.sublist(magic.length, magic.length + 16));
    final encrypted = enc.Encrypted(fileBytes.sublist(magic.length + 16));
    try {
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (_) {
      return null;
    }
  }

  static bool _hasMagic(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool isEncrypted(List<int> bytes) {
    return _hasMagic(bytes, magic) || _hasMagic(bytes, _passwordMagic);
  }

  static bool isDkh2Format(List<int> bytes) => _hasMagic(bytes, _passwordMagic);

  static bool isLegacyCbcFormat(List<int> bytes) => _hasMagic(bytes, magic);

  static bool isPasswordProtected(List<int> bytes) =>
      _hasMagic(bytes, _passwordMagic);

  static Future<bool> isPasswordProtectedFile(String path) async {
    final handle = await File(path).open();
    try {
      return isPasswordProtected(await handle.read(4));
    } finally {
      await handle.close();
    }
  }
}

class DkhpPasswordException implements Exception {
  final String message;
  const DkhpPasswordException(this.message);

  @override
  String toString() => message;
}

/// Dilempar ketika berkas cadangan perubahan tidak cocok dengan sidik jari DHKP dasar
/// atau ketika berkas DHKP dasar belum dimuat di aplikasi.
class DhkpBackupValidationException extends FormatException {
  const DhkpBackupValidationException(super.message);
}

/// Hasil ekstraksi pratinjau berkas paket DHKP / DAT tanpa memodifikasi penyimpanan lokal.
class DhkpPreviewResult {
  final Map<String, dynamic>? manifest;
  final List<String> headers;
  final List<List<String>> rows;
  final bool isEncrypted;

  const DhkpPreviewResult({
    this.manifest,
    required this.headers,
    required this.rows,
    this.isEncrypted = false,
  });
}
