import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Enkripsi paket `.dkhp` menggunakan PBKDF2-HMAC-SHA256 dan AES-256-GCM.
class DhkpCrypto {
  DhkpCrypto._();

  static const magic = [0x44, 0x4B, 0x48, 0x50]; // Legacy "DKHP"
  static const _passwordMagic = [0x44, 0x4B, 0x48, 0x32]; // "DKH2"
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _iterations = 600000;
  static const _legacySecret = 'CekPBBCianjur-DKHP-Package-Secret-v1';
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  static final _aesGcm = AesGcm.with256bits();

  static Future<Uint8List> encryptBytes(
    Uint8List plainBytes, {
    required String password,
  }) async {
    if (password.length < 8) {
      throw const FormatException(
        'Kata sandi backup harus terdiri dari minimal 8 karakter.',
      );
    }
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => Random.secure().nextInt(256)),
    );
    final nonce = _aesGcm.newNonce();
    final header = Uint8List.fromList([..._passwordMagic, ...salt, ...nonce]);
    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
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

  /// Enkripsi bawaan AES-256-CBC (`DKHP`) saat pengguna belum mengatur kata sandi kustom.
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

  static Future<Uint8List?> decryptBytes(
    Uint8List fileBytes, {
    String? password,
  }) async {
    if (_hasMagic(fileBytes, _passwordMagic)) {
      final headerLength = _passwordMagic.length + _saltLength + _nonceLength;
      if (fileBytes.length < headerLength + _tagLength) {
        throw const FormatException('Berkas backup terenkripsi tidak lengkap.');
      }
      if (password == null || password.isEmpty) {
        throw const DkhpPasswordException(
          'Kata sandi diperlukan untuk membuka backup ini.',
        );
      }

      final salt = fileBytes.sublist(
        _passwordMagic.length,
        _passwordMagic.length + _saltLength,
      );
      final nonce = fileBytes.sublist(
        _passwordMagic.length + _saltLength,
        headerLength,
      );
      final header = fileBytes.sublist(0, headerLength);
      final body = fileBytes.sublist(headerLength);
      final cipherText = body.sublist(0, body.length - _tagLength);
      final tag = body.sublist(body.length - _tagLength);
      final key = await _pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
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
        throw const DkhpPasswordException(
          'Kata sandi salah atau berkas backup telah berubah/rusak.',
        );
      }
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
