import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'dusun_data.dart';
import 'operator_mode_store.dart';
import 'wilayah_kerja_store.dart';

/// Backup/restore Buku Catatan Blok dienkripsi (AES-256-CBC) dengan kunci
/// yang diturunkan otomatis per identitas (Dusun 1-5, Operator, atau belum
/// pilih wilayah) — tidak ada password yang diketik manual, semuanya
/// dihitung dari identitas perangkat saat ekspor/impor terjadi. Efeknya:
/// berkas backup satu wilayah tidak bisa dibuka perangkat wilayah lain
/// (kuncinya beda), dan hanya perangkat Mode Operator yang bisa membuka
/// laporan dari semua dusun (operator mencoba semua kunci dusun + kuncinya
/// sendiri saat restore, lihat [allowedRestoreIdentities]).
class BackupCrypto {
  BackupCrypto._();

  static const _appSecret = 'CekPBBCianjur-BukuCatatanBlok-kunci-v1';
  static const _magic = [0x43, 0x50, 0x42, 0x42]; // "CPBB"
  static const _plaintextMarker = 'CPBBOK1;';

  static String operatorIdentity() => 'operator';
  static String dusunIdentity(int number) => 'dusun-$number';
  static const _unassignedIdentity = 'unassigned';

  /// Identitas perangkat ini sekarang — dipakai untuk memilih kunci enkripsi
  /// saat ekspor.
  static Future<String> currentIdentity() async {
    if (await OperatorModeStore.instance.isEnabled()) return operatorIdentity();
    final dusun = await WilayahKerjaStore.instance.selectedDusun();
    return dusun == null ? _unassignedIdentity : dusunIdentity(dusun);
  }

  /// Semua identitas yang boleh dicoba saat restore, sesuai mode perangkat
  /// ini. Operator menerima laporan dari SEMUA dusun (+ bisa restore backup
  /// miliknya sendiri); petugas wilayah hanya bisa restore berkas miliknya
  /// sendiri — berkas wilayah lain atau berkas Operator otomatis gagal.
  static Future<List<String>> allowedRestoreIdentities() async {
    if (await OperatorModeStore.instance.isEnabled()) {
      return [
        operatorIdentity(),
        for (final d in dusunList) dusunIdentity(d.number),
      ];
    }
    final dusun = await WilayahKerjaStore.instance.selectedDusun();
    return [dusun == null ? _unassignedIdentity : dusunIdentity(dusun)];
  }

  static enc.Key _keyFor(String identity) {
    final digest = sha256.convert(utf8.encode('$_appSecret::$identity'));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  static Uint8List encryptForIdentity(String identity, Uint8List plainBytes) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(
      enc.AES(_keyFor(identity), mode: enc.AESMode.cbc),
    );
    final marked = Uint8List.fromList([
      ...utf8.encode(_plaintextMarker),
      ...plainBytes,
    ]);
    final encrypted = encrypter.encryptBytes(marked, iv: iv);
    return Uint8List.fromList([..._magic, ...iv.bytes, ...encrypted.bytes]);
  }

  /// Coba dekripsi [fileBytes] dengan tiap identitas di [identities] secara
  /// urut sampai ada yang cocok — kecocokan dipastikan lewat [_plaintextMarker]
  /// yang harus muncul lagi persis setelah didekripsi (bukan cuma "tidak
  /// error saat decrypt", karena CBC dengan kunci salah kadang tetap
  /// menghasilkan padding yang valid secara kebetulan). Null kalau tidak ada
  /// satupun identitas yang cocok.
  static Uint8List? tryDecrypt(Uint8List fileBytes, List<String> identities) {
    if (fileBytes.length < _magic.length + 16) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (fileBytes[i] != _magic[i]) return null;
    }
    final iv = enc.IV(fileBytes.sublist(_magic.length, _magic.length + 16));
    final encrypted = enc.Encrypted(fileBytes.sublist(_magic.length + 16));
    final markerBytes = utf8.encode(_plaintextMarker);

    for (final identity in identities) {
      try {
        final encrypter = enc.Encrypter(
          enc.AES(_keyFor(identity), mode: enc.AESMode.cbc),
        );
        final decrypted = Uint8List.fromList(
          encrypter.decryptBytes(encrypted, iv: iv),
        );
        if (decrypted.length < markerBytes.length) continue;
        var matches = true;
        for (var i = 0; i < markerBytes.length; i++) {
          if (decrypted[i] != markerBytes[i]) {
            matches = false;
            break;
          }
        }
        if (matches) return decrypted.sublist(markerBytes.length);
      } catch (_) {
        // Kunci salah untuk identitas ini (padding tidak valid) — coba yang lain.
      }
    }
    return null;
  }
}

/// Dilempar saat berkas restore tidak bisa didekripsi oleh identitas
/// (wilayah/Operator) perangkat ini — berarti berkas itu bukan milik
/// wilayah ini, atau backup Operator dibuka dari perangkat bukan Operator.
class BackupAccessDeniedException implements Exception {
  final String message;
  const BackupAccessDeniedException(this.message);

  @override
  String toString() => message;
}
