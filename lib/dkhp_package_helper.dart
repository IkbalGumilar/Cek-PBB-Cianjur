import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:csv/csv.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'app_storage.dart';
import 'backup_crypto.dart';
import 'backup_password_store.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'nop_helper.dart';

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
    if (password.length < 12) {
      throw const FormatException(
        'Kata sandi backup harus terdiri dari minimal 12 karakter.',
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

/// Pengelola berkas paket `.dkhp` — format arsip terenkripsi khusus aplikasi Cek PBB Cianjur.
///
/// Paket `.dkhp` berisi:
/// 1. `data.csv`: tabel data NOP, Nama WP, Status Bayar, Target Pemda, Catatan Petugas, dsb.
/// 2. Folder `foto/`: foto lembaran SPPT / DHKP per NOP (misal `320520000402600340.jpg`).
class DhkpPackageHelper {
  static const extensionName = 'dkhp';

  static Set<String>? _cachedPhotoNames;

  static void resetForTesting() {
    _cachedPhotoNames = null;
  }

  /// Memperbarui cache nama-nama file foto yang ada di photosDirectory.
  static Future<Set<String>> refreshPhotoNamesCache() async {
    final dir = await photosDirectory();
    final names = <String>{};
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          names.add(entity.uri.pathSegments.last.toLowerCase());
        }
      }
    }
    _cachedPhotoNames = names;
    return names;
  }

  /// Hapus cache foto di memori agar sinkron ulang dengan berkas fisik baru.
  static void invalidatePhotoCache() {
    _cachedPhotoNames = null;
  }

  /// Folder lokal aplikasi untuk menyimpan foto-foto dokumen DHKP (publik media).
  static Future<Directory> photosDirectory() async {
    return AppStorage.getPhotosDirectory();
  }

  /// Cari file foto untuk sebuah NOP jika sudah tersimpan lokal.
  static Future<File?> findPhotoForNop(
    String nop, {
    String? customFileName,
  }) async {
    final dir = await photosDirectory();
    final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');
    var cached = _cachedPhotoNames;
    cached ??= await refreshPhotoNamesCache();

    if (customFileName != null && customFileName.isNotEmpty) {
      if (cached.contains(customFileName.toLowerCase())) {
        return File('${dir.path}/$customFileName');
      }
    }

    final candidates = [
      '$cleanNop.jpg',
      '$cleanNop.jpeg',
      '$cleanNop.png',
      '${nopBlok(cleanNop)}_${nopWilayah(cleanNop)}.jpg',
      '${nopBlok(cleanNop)}_${nopWilayah(cleanNop)}.png',
    ];

    for (final name in candidates) {
      if (cached.contains(name.toLowerCase())) {
        return File('${dir.path}/$name');
      }
    }
    return null;
  }

  /// Versi sinkron dari pencarian foto yang memakai cache set nama file di memori.
  /// Sangat cepat (O(1)) tanpa I/O disk, aman dipanggil di dalam widget build/DataCell.
  static File? findPhotoForNopSync(
    String nop, {
    String? customFileName,
    required Directory photosDir,
    required Set<String> cachedNames,
  }) {
    final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');

    if (customFileName != null && customFileName.isNotEmpty) {
      if (cachedNames.contains(customFileName.toLowerCase())) {
        return File('${photosDir.path}/$customFileName');
      }
    }

    final candidates = [
      '$cleanNop.jpg',
      '$cleanNop.jpeg',
      '$cleanNop.png',
      '${nopBlok(cleanNop)}_${nopWilayah(cleanNop)}.jpg',
      '${nopBlok(cleanNop)}_${nopWilayah(cleanNop)}.png',
    ];

    for (final name in candidates) {
      if (cachedNames.contains(name.toLowerCase())) {
        return File('${photosDir.path}/$name');
      }
    }
    return null;
  }

  /// Buka dan ekstrak berkas `.dkhp` (terenkripsi maupun tidak) atau `.zip`, lalu simpan datanya ke
  /// [BlokDataStore] dan foto-fotonya ke folder lokal aplikasi.
  static Future<List<BlokRecord>> unpackDkhp(
    String filePath, {
    String? password,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Berkas .dkhp tidak ditemukan', filePath);
    }

    final rawBytes = await file.readAsBytes();
    Uint8List zipBytes;

    if (DhkpCrypto.isEncrypted(rawBytes)) {
      final decrypted = await DhkpCrypto.decryptBytes(
        rawBytes,
        password: password,
      );
      if (decrypted == null) {
        throw const FormatException(
          'Gagal mendekripsi berkas .dkhp: Kunci atau format enkripsi tidak cocok.',
        );
      }
      zipBytes = decrypted;
    } else {
      // Periksa jika berkas dibungkus dengan BackupCrypto lama
      final backupIdentities = [
        'operator',
        'unassigned',
        for (var i = 1; i <= 5; i++) 'dusun-$i',
      ];
      final cpbbDecrypted = BackupCrypto.tryDecrypt(rawBytes, backupIdentities);
      if (cpbbDecrypted != null) {
        zipBytes = cpbbDecrypted;
      } else {
        // Berkas ZIP standar / tidak terenkripsi
        zipBytes = rawBytes;
      }
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final photosDir = await photosDirectory();

    ArchiveFile? dataFile;
    final photoFiles = <ArchiveFile>[];

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final nameLower = entry.name.toLowerCase();
      if (nameLower.endsWith('.csv') || nameLower.endsWith('.json')) {
        dataFile = entry;
      } else if (nameLower.endsWith('.jpg') ||
          nameLower.endsWith('.jpeg') ||
          nameLower.endsWith('.png') ||
          nameLower.endsWith('.webp')) {
        photoFiles.add(entry);
      }
    }

    // Ekstrak semua foto ke folder lokal
    for (final p in photoFiles) {
      final baseName = p.name.split('/').last;
      final targetFile = File('${photosDir.path}/$baseName');
      await targetFile.writeAsBytes(p.content as List<int>);
    }

    final records = <BlokRecord>[];
    final currentYear = '${DateTime.now().year}';

    if (dataFile != null) {
      final content = utf8.decode(dataFile.content as List<int>);
      if (dataFile.name.toLowerCase().endsWith('.csv')) {
        final rows = Csv().decode(content);
        for (final row in rows.skip(1)) {
          if (row.length < 2) continue;
          final rawNop = row[1].toString().trim();
          final nopDigits = rawNop.replaceAll(RegExp(r'[^0-9]'), '');
          if (nopDigits.length != 18) continue;

          final nama = row[0].toString().trim();
          final tahun = row.length > 2 && row[2].toString().trim().isNotEmpty
              ? row[2].toString().trim()
              : currentYear;
          final tanggal = row.length > 3 ? row[3].toString().trim() : '';
          final pokok = row.length > 4 ? row[4].toString().trim() : '';
          final status = row.length > 5 && row[5].toString().trim().isNotEmpty
              ? row[5].toString().trim()
              : (tanggal.isNotEmpty ? 'Sudah Bayar' : 'Belum Bayar');
          final namaFoto = row.length > 6 && row[6].toString().trim().isNotEmpty
              ? row[6].toString().trim()
              : null;
          final rawTargetPemda = row.length > 7
              ? row[7].toString().trim().toLowerCase()
              : '';
          final isTargetPemda =
              rawTargetPemda == '1' ||
              rawTargetPemda == 'true' ||
              rawTargetPemda == 'ya' ||
              rawTargetPemda == 'yes' ||
              rawTargetPemda.contains('target') ||
              rawTargetPemda.contains('pemda');
          final catatan = row.length > 8 ? row[8].toString().trim() : '';
          final luasBumi = row.length > 9 ? row[9].toString().trim() : '';
          final luasBangunan = row.length > 10 ? row[10].toString().trim() : '';
          final njopBumi = row.length > 11 ? row[11].toString().trim() : '';
          final njopBangunan = row.length > 12 ? row[12].toString().trim() : '';
          final kecamatan =
              row.length > 13 && row[13].toString().trim().isNotEmpty
              ? row[13].toString().trim()
              : 'MANDE';
          final kelurahan =
              row.length > 14 && row[14].toString().trim().isNotEmpty
              ? row[14].toString().trim()
              : 'BOBOJONG';
          final alamatObjek = row.length > 15 ? row[15].toString().trim() : '';
          final alamatWp = row.length > 16 ? row[16].toString().trim() : '';
          final rtObjek = row.length > 17 ? row[17].toString().trim() : '';

          records.add(
            BlokRecord(
              namaWajibPajak: nama.isEmpty
                  ? 'WP ${nopBlok(nopDigits)}/${nopWilayah(nopDigits)}'
                  : nama,
              nop: nopDigits,
              tahunBayar: tahun,
              tanggalBayar: tanggal,
              jumlahPbb: pokok,
              statusBayar: status,
              namaFoto: namaFoto,
              isTargetPemda: isTargetPemda,
              catatan: catatan,
              luasBumi: luasBumi,
              luasBangunan: luasBangunan,
              njopBumi: njopBumi,
              njopBangunan: njopBangunan,
              kecamatan: kecamatan,
              kelurahan: kelurahan,
              alamatObjek: alamatObjek,
              alamatWp: alamatWp,
              rtObjek: rtObjek,
            ),
          );
        }
      }
    }

    // Kalau di dalam arsip tidak ada data.csv tapi ada kumpulan foto dengan nama NOP
    if (records.isEmpty && photoFiles.isNotEmpty) {
      for (final p in photoFiles) {
        final baseName = p.name.split('/').last;
        final digits = baseName.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 18) {
          records.add(
            BlokRecord(
              namaWajibPajak:
                  'WP Blok ${nopBlok(digits)} No ${nopWilayah(digits)}',
              nop: digits,
              tahunBayar: currentYear,
              tanggalBayar: '',
              jumlahPbb: '',
              statusBayar: 'Belum Bayar',
              namaFoto: baseName,
            ),
          );
        }
      }
    }

    if (records.isNotEmpty) {
      await BlokDataStore.instance.upsertAll(records);
    }

    return records;
  }

  /// Membungkus daftar record dan file foto menjadi paket terenkripsi `.dkhp`.
  /// Bila [includePhotos] bernilai false, hanya tabel data yang dipaketkan (hemat memori).
  static Future<File> packDkhp({
    required String outputPath,
    required List<BlokRecord> records,
    Directory? photosDir,
    bool encrypt = true,
    bool includePhotos = true,
    String? password,
  }) async {
    final archive = Archive();

    // 1. Buat data.csv
    final csvRows = <List<String>>[
      [
        'Nama WP',
        'NOP',
        'Tahun Bayar',
        'Tanggal Bayar',
        'Jumlah PBB',
        'Status Bayar',
        'Foto',
        'Target Pemda',
        'Catatan',
        'Luas Bumi',
        'Luas Bangunan',
        'NJOP Bumi',
        'NJOP Bangunan',
        'Kecamatan',
        'Kelurahan',
        'Alamat Objek',
        'Alamat WP',
        'RT Objek',
      ],
      for (final r in records)
        [
          r.namaWajibPajak,
          r.nop,
          r.tahunBayar,
          r.tanggalBayar,
          r.jumlahPbb,
          r.statusBayar,
          r.namaFoto ?? '',
          r.isTargetPemda ? '1' : '0',
          r.catatan,
          r.luasBumi,
          r.luasBangunan,
          r.njopBumi,
          r.njopBangunan,
          r.kecamatan,
          r.kelurahan,
          r.alamatObjek,
          r.alamatWp,
          r.rtObjek,
        ],
    ];
    final csvString = Csv().encode(csvRows);
    final csvBytes = utf8.encode(csvString);
    archive.addFile(ArchiveFile('data.csv', csvBytes.length, csvBytes));

    // 2. Tambahkan foto jika diminta dan ada
    if (includePhotos) {
      final sourcePhotosDir = photosDir ?? await photosDirectory();
      if (await sourcePhotosDir.exists()) {
        for (final r in records) {
          final photoName = r.namaFoto;
          if (photoName != null && photoName.isNotEmpty) {
            final photoFile = File('${sourcePhotosDir.path}/$photoName');
            if (await photoFile.exists()) {
              final photoBytes = await photoFile.readAsBytes();
              archive.addFile(
                ArchiveFile('foto/$photoName', photoBytes.length, photoBytes),
              );
            }
          }
        }
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Gagal mengompresi data ke arsip ZIP.');
    }

    final effectivePassword =
        password ?? await BackupPasswordStore.instance.read();
    if (encrypt && (effectivePassword == null || effectivePassword.isEmpty)) {
      throw const DkhpPasswordException(
        'Atur kata sandi backup sebelum membuat berkas .dkhp terenkripsi.',
      );
    }
    final outputBytes = encrypt
        ? await DhkpCrypto.encryptBytes(
            Uint8List.fromList(zipBytes),
            password: effectivePassword!,
          )
        : Uint8List.fromList(zipBytes);

    final file = File(outputPath);
    file.writeAsBytesSync(outputBytes);
    return file;
  }
}
