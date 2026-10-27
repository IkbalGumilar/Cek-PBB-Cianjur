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
import 'dusun_data.dart';
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

/// Pengelola berkas paket `.dkhp` / `.dhkp` — format arsip terenkripsi khusus aplikasi Cek PBB Cianjur.
///
/// Paket cadangan `.dkhp` / `.dhkp` berisi:
/// 1. `manifest.json`: sidik jari (SHA-256) dari berkas DHKP dasar (`dhkpFingerprint`) serta daftar perubahan blok & nomor NOP.
/// 2. `data.csv`: baris data NOP yang mengalami perubahan (status bayar, catatan petugas, gambar dokumentasi).
/// 3. Folder `foto/`: gambar dokumentasi petugas per NOP (misal `320520000402600340.jpg`).
class DhkpPackageHelper {
  static const extensionName = 'dkhp';
  static const altExtensionName = 'dhkp';

  /// Memeriksa apakah nama/path berkas merupakan paket DHKP (`.dkhp`, `.dhkp`, atau `.zip`).
  static bool isDkhpArchivePath(String path) {
    final lower = path.trim().toLowerCase();
    return lower.endsWith('.dkhp') ||
        lower.endsWith('.dhkp') ||
        lower.endsWith('.dat') ||
        lower.endsWith('.zip');
  }

  /// Menghitung sidik jari (SHA-256 fingerprint) langsung dari daftar NOP di dalam berkas DHKP.
  /// Murni dihitung dari isi berkas DHKP (bukan ID perangkat/HP), sehingga tetap cocok 100%
  /// saat berpindah HP selama berkas DHKP dasarnya sama, dan otomatis menolak jika berkas DHKP berbeda.
  static String computeDhkpFingerprint(Iterable<BlokRecord> records) {
    final sortedNops = records
        .map((r) => r.nop.replaceAll(RegExp(r'[^0-9]'), ''))
        .where((n) => n.length == 18)
        .toSet()
        .toList()
      ..sort();
    if (sortedNops.isEmpty) return '';
    return legacy_crypto.sha256
        .convert(utf8.encode(sortedNops.join('\n')))
        .toString();
  }

  /// Memeriksa apakah satu baris DHKP memiliki perubahan dari petugas
  /// (status bayar lunas, tanggal bayar, catatan, gambar dokumentasi, target pemda, atau blacklist).
  static bool isChangedRecord(BlokRecord r) {
    return r.isPaid ||
        r.catatan.trim().isNotEmpty ||
        r.hasPhoto ||
        r.isTargetPemda ||
        r.isBlacklist;
  }

  /// Mengambil daftar baris DHKP yang mengalami perubahan saja.
  static List<BlokRecord> extractChangedRecords(Iterable<BlokRecord> records) {
    return records.where(isChangedRecord).toList();
  }

  /// Membaca metadata `manifest.json` dari berkas `.dkhp` (termasuk `dhkpFingerprint`) jika ada.
  static Future<Map<String, dynamic>?> readBackupManifest(
    String filePath, {
    String? password,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      final rawBytes = await file.readAsBytes();
      Uint8List zipBytes;
      if (DhkpCrypto.isEncrypted(rawBytes)) {
        final effectivePass =
            password ?? await BackupPasswordStore.instance.read();
        final decrypted = await DhkpCrypto.decryptBytes(
          rawBytes,
          password: effectivePass,
        );
        if (decrypted == null) return null;
        zipBytes = decrypted;
      } else {
        zipBytes = rawBytes;
      }
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name.toLowerCase().endsWith('manifest.json')) {
          final text = utf8.decode(entry.content as List<int>);
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

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
  ///
  /// Bila berkas merupakan cadangan perubahan (`manifest.json` dengan `isDeltaOnly == true` atau
  /// [requireBaseDhkp] bernilai `true`), aplikasi memvalidasi bahwa sidik jari DHKP (`dhkpFingerprint`)
  /// cocok dengan data DHKP yang sudah ada di aplikasi.
  static Future<List<BlokRecord>> unpackDkhp(
    String filePath, {
    String? password,
    bool requireBaseDhkp = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Berkas .dkhp tidak ditemukan', filePath);
    }

    final rawBytes = await file.readAsBytes();
    Uint8List zipBytes;

    if (DhkpCrypto.isEncrypted(rawBytes)) {
      final effectivePassword =
          password ?? await BackupPasswordStore.instance.read();
      final decrypted = await DhkpCrypto.decryptBytes(
        rawBytes,
        password: effectivePassword,
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

    ArchiveFile? manifestFile;
    ArchiveFile? dataFile;
    final photoFiles = <ArchiveFile>[];

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final nameLower = entry.name.toLowerCase();
      if (nameLower.endsWith('manifest.json')) {
        manifestFile = entry;
      } else if (nameLower.endsWith('.csv') || nameLower.endsWith('.json')) {
        dataFile = entry;
      } else if (nameLower.endsWith('.jpg') ||
          nameLower.endsWith('.jpeg') ||
          nameLower.endsWith('.png') ||
          nameLower.endsWith('.webp')) {
        photoFiles.add(entry);
      }
    }

    Map<String, dynamic>? manifest;
    if (manifestFile != null) {
      try {
        final manifestContent = utf8.decode(manifestFile.content as List<int>);
        final decoded = jsonDecode(manifestContent);
        if (decoded is Map<String, dynamic>) {
          manifest = decoded;
          if (manifest['dusuns'] is List) {
            final rawList = manifest['dusuns'] as List;
            final parsedDusuns = <Dusun>[];
            for (final item in rawList) {
              if (item is Map) {
                parsedDusuns.add(
                  Dusun.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            }
            if (parsedDusuns.isNotEmpty) {
              await DusunData.instance.setDusuns(parsedDusuns);
            }
          }
          if (manifest['scope'] is Map) {
            final scopeMap = Map<String, dynamic>.from(manifest['scope'] as Map);
            await DusunData.instance.setScope(DusunScope.fromJson(scopeMap));
          }
        }
      } catch (_) {}
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
          final rawStatus = row.length > 5 ? row[5].toString().trim() : '';
          final status = (tanggal.isNotEmpty && tanggal != '0')
              ? 'Sudah Bayar'
              : (rawStatus.isNotEmpty
                  ? rawStatus
                  : 'Belum Bayar');
          final namaFoto = row.length > 6 && row[6].toString().trim().isNotEmpty
              ? row[6].toString().trim()
              : null;
          final rawTargetPemda = row.length > 7
              ? row[7].toString().trim().toLowerCase()
              : '';
          final pokokDigits = pokok.replaceAll(RegExp(r'[^0-9]'), '');
          final pokokVal = int.tryParse(pokokDigits) ?? 0;
          final isTargetPemda =
              rawTargetPemda == '1' ||
              rawTargetPemda == 'true' ||
              rawTargetPemda == 'ya' ||
              rawTargetPemda == 'yes' ||
              rawTargetPemda.contains('target') ||
              rawTargetPemda.contains('pemda') ||
              (rawTargetPemda.isEmpty && pokokVal >= 1500000);
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

    // Validasi kecocokan berkas DHKP dasar sebelum mengekstrak foto & menerapkan perubahan
    final existingRecords = await BlokDataStore.instance.loadAll();
    final isDeltaArchive =
        manifest != null && (manifest['isDeltaOnly'] == true);
    final isDatReport = filePath.toLowerCase().endsWith('.dat') ||
        (manifest != null && manifest['format'] == 'laporan_dat_v1');

    if (isDatReport) {
      final incomingBloks = <String>{};
      for (final r in records) {
        final b = int.tryParse(r.blok)?.toString() ?? r.blok.replaceAll(RegExp(r'[^0-9]'), '');
        if (b.isNotEmpty) incomingBloks.add(b);
      }
      if (manifest != null && manifest['changes'] is List) {
        for (final item in manifest['changes'] as List) {
          if (item is Map) {
            final rawB = (item['blok'] ?? '').toString();
            final b = int.tryParse(rawB)?.toString() ?? rawB.replaceAll(RegExp(r'[^0-9]'), '');
            if (b.isNotEmpty) incomingBloks.add(b);
          }
        }
      }

      final localBloks = existingRecords
          .map((r) => int.tryParse(r.blok)?.toString() ?? r.blok.replaceAll(RegExp(r'[^0-9]'), ''))
          .where((b) => b.isNotEmpty)
          .toSet();

      if (existingRecords.isEmpty ||
          incomingBloks.isEmpty ||
          !incomingBloks.every((b) => localBloks.contains(b))) {
        throw const DhkpBackupValidationException('Data tidak sesuai');
      }
    } else if (requireBaseDhkp || isDeltaArchive) {
      if (requireBaseDhkp && existingRecords.isEmpty) {
        throw const DhkpBackupValidationException(
          'Berkas DHKP dasar belum dimuat. Muat berkas DHKP terlebih dahulu sebelum menggunakan berkas cadangan perubahan.',
        );
      }

      if (existingRecords.isNotEmpty && manifest != null) {
        final backupFingerprint =
            (manifest['dhkpFingerprint'] as String?)?.trim() ?? '';
        final localFingerprint = computeDhkpFingerprint(existingRecords);
        if (backupFingerprint.isNotEmpty &&
            localFingerprint.isNotEmpty &&
            localFingerprint != backupFingerprint) {
          throw const DhkpBackupValidationException(
            'Berkas cadangan ditolak: Data perubahan ini berasal dari berkas DHKP yang berbeda dengan data DHKP di aplikasi.',
          );
        }
      }
    }

    final existingByNop = <String, BlokRecord>{
      for (final r in existingRecords)
        r.nop.replaceAll(RegExp(r'[^0-9]'), ''): r,
    };
    final existingByBlokNomor = <String, BlokRecord>{
      for (final r in existingRecords)
        '${r.blok.replaceAll(RegExp(r'[^0-9]'), '').padLeft(3, '0')}_${r.wilayah.replaceAll(RegExp(r'[^0-9]'), '').padLeft(4, '0')}':
            r,
    };

    // Kalau di dalam arsip tidak ada data.csv tapi ada manifest changes (hanya blok & nomor)
    if (records.isEmpty && manifest != null && manifest['changes'] is List) {
      final changesList = manifest['changes'] as List;
      for (final item in changesList) {
        if (item is! Map) continue;
        final rawBlok = (item['blok'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'[^0-9]'), '');
        final rawNomor = (item['nomor'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'[^0-9]'), '');
        final rawNop = (item['nop'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'[^0-9]'), '');

        BlokRecord? baseRecord;
        if (rawBlok.isNotEmpty && rawNomor.isNotEmpty) {
          final key = '${rawBlok.padLeft(3, '0')}_${rawNomor.padLeft(4, '0')}';
          baseRecord = existingByBlokNomor[key];
        }
        if (baseRecord == null && rawNop.length == 18) {
          baseRecord = existingByNop[rawNop];
        }

        if (baseRecord != null) {
          final tglStr = (item['tanggalBayar'] ?? baseRecord.tanggalBayar).toString().trim();
          final rawSt = (item['statusBayar'] ?? baseRecord.statusBayar).toString().trim();
          final effectiveSt = (tglStr.isNotEmpty && tglStr != '0')
              ? 'Sudah Bayar'
              : (rawSt.isNotEmpty ? rawSt : 'Belum Bayar');
          records.add(
            baseRecord.copyWith(
              tahunBayar: (item['tahunBayar'] ?? baseRecord.tahunBayar).toString(),
              tanggalBayar: tglStr,
              statusBayar: effectiveSt,
              namaFoto: item['namaFoto']?.toString() ?? baseRecord.namaFoto,
              isTargetPemda: item['isTargetPemda'] is bool
                  ? item['isTargetPemda'] as bool
                  : baseRecord.isTargetPemda,
              catatan: (item['catatan'] ?? baseRecord.catatan).toString(),
            ),
          );
          continue;
        }

        // Fallback apabila berkas DHKP dasar memiliki prefix desa atau kompatibilitas mundur
        String resolvedNop = rawNop;
        if (resolvedNop.length != 18 &&
            rawBlok.isNotEmpty &&
            rawNomor.isNotEmpty &&
            existingRecords.isNotEmpty) {
          final sampleNop = existingRecords.first.nop.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
          if (sampleNop.length == 18) {
            final prefix = sampleNop.substring(0, 10);
            final suffix = sampleNop.substring(17);
            resolvedNop =
                '$prefix${rawBlok.padLeft(3, '0')}${rawNomor.padLeft(4, '0')}$suffix';
          }
        }
        if (resolvedNop.length != 18) continue;

        records.add(
          BlokRecord(
            namaWajibPajak:
                (item['namaWajibPajak'] ??
                        'WP ${nopBlok(resolvedNop)}/${nopWilayah(resolvedNop)}')
                    .toString(),
            nop: resolvedNop,
            tahunBayar: (item['tahunBayar'] ?? currentYear).toString(),
            tanggalBayar: (item['tanggalBayar'] ?? '').toString(),
            jumlahPbb: (item['jumlahPbb'] ?? '').toString(),
            statusBayar: (item['statusBayar'] ?? 'Belum Bayar').toString(),
            namaFoto: item['namaFoto']?.toString(),
            isTargetPemda: item['isTargetPemda'] == true,
            catatan: (item['catatan'] ?? '').toString(),
          ),
        );
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

    // Ekstrak semua foto dokumentasi ke folder lokal setelah validasi lulus
    for (final p in photoFiles) {
      final baseName = p.name.split('/').last;
      final targetFile = File('${photosDir.path}/$baseName');
      await targetFile.writeAsBytes(p.content as List<int>);
    }
    invalidatePhotoCache();

    // Gabungkan data perubahan ke data DHKP dasar bila data dasar sudah ada
    final mergedRecords = <BlokRecord>[];
    for (final r in records) {
      final cleanNop = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
      final base = existingByNop[cleanNop];
      if (base != null && (isDeltaArchive || isDatReport)) {
        mergedRecords.add(
          base.copyWith(
            statusBayar: r.statusBayar,
            tanggalBayar: r.tanggalBayar.isNotEmpty ? r.tanggalBayar : base.tanggalBayar,
            catatan: r.catatan.isNotEmpty ? r.catatan : base.catatan,
            namaFoto: (r.namaFoto != null && r.namaFoto!.isNotEmpty) ? r.namaFoto : base.namaFoto,
            isTargetPemda: r.isTargetPemda,
            namaWajibPajak: (r.namaWajibPajak.isNotEmpty && !r.namaWajibPajak.startsWith('WP '))
                ? r.namaWajibPajak
                : base.namaWajibPajak,
            alamatObjek: r.alamatObjek.isNotEmpty ? r.alamatObjek : base.alamatObjek,
            alamatWp: r.alamatWp.isNotEmpty ? r.alamatWp : base.alamatWp,
            rtObjek: r.rtObjek.isNotEmpty ? r.rtObjek : base.rtObjek,
            luasBumi: r.luasBumi.isNotEmpty ? r.luasBumi : base.luasBumi,
            luasBangunan: r.luasBangunan.isNotEmpty ? r.luasBangunan : base.luasBangunan,
            njopBumi: r.njopBumi.isNotEmpty ? r.njopBumi : base.njopBumi,
            njopBangunan: r.njopBangunan.isNotEmpty ? r.njopBangunan : base.njopBangunan,
            jumlahPbb: r.jumlahPbb.isNotEmpty ? r.jumlahPbb : base.jumlahPbb,
          ),
        );
      } else {
        mergedRecords.add(r);
      }
    }

    if (mergedRecords.isNotEmpty) {
      await BlokDataStore.instance.upsertAll(mergedRecords);
    }

    return mergedRecords;
  }

  /// Membungkus data perubahan DHKP dan gambar dokumentasi menjadi paket terenkripsi `.dkhp`.
  ///
  /// Secara bawaan menggunakan enkripsi sederhana otomatis (`DhkpCrypto.encryptLegacyBytes`)
  /// tanpa memerlukan kata sandi manual, serta menyematkan sidik jari berkas DHKP dasar
  /// (`dhkpFingerprint`) di dalam `manifest.json`.
  static Future<File> packDkhp({
    required String outputPath,
    required List<BlokRecord> records,
    List<BlokRecord>? baseRecords,
    Directory? photosDir,
    bool encrypt = true,
    bool includePhotos = true,
    bool deltaOnly = false,
    String? password,
    List<Dusun>? dusuns,
    DusunScope? scope,
  }) async {
    final archive = Archive();
    final isDatReport = outputPath.toLowerCase().endsWith('.dat');
    final effectiveBase = baseRecords ?? records;
    final dhkpFingerprint = computeDhkpFingerprint(effectiveBase);
    final changedList = extractChangedRecords(records);
    final targetRecords = (deltaOnly && changedList.isNotEmpty && !isDatReport)
        ? changedList
        : records;

    // 1. Buat manifest.json dengan sidik jari berkas DHKP dasar, daftar dusun dinamis, pembatas wilayah (scope), dan daftar perubahan
    if (effectiveBase.isNotEmpty || isDatReport) {
      final effectiveDusuns = dusuns ?? DusunData.instance.allDusuns;
      final effectiveScope = scope ?? DusunData.instance.scope;
      final manifestMap = <String, dynamic>{
        'format': isDatReport ? 'laporan_dat_v1' : 'dhkp_delta_v1',
        'isDeltaOnly': isDatReport ? false : deltaOnly,
        'dhkpFingerprint': dhkpFingerprint,
        'baseTotalNop': effectiveBase.length,
        'changedCount': changedList.length,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (effectiveDusuns.isNotEmpty)
          'dusuns': effectiveDusuns.map((d) => d.toJson()).toList(),
        'scope': effectiveScope.toJson(),
        'changes': [
          for (final r in targetRecords)
            {
              'blok': r.blok,
              'nomor': r.wilayah,
              'tahunBayar': r.tahunBayar,
              'statusBayar': r.statusBayar,
              'tanggalBayar': r.tanggalBayar,
              'catatan': r.catatan,
              if (r.namaFoto != null && r.namaFoto!.isNotEmpty)
                'namaFoto': r.namaFoto,
              'isTargetPemda': r.isTargetPemda,
            },
        ],
      };
      final manifestBytes = utf8.encode(jsonEncode(manifestMap));
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );
    }

    // 2. Buat data.csv jika bukan deltaOnly atau jika berkas merupakan laporan .dat.
    // Saat deltaOnly == true (bukan .dat), berkas cadangan tidak menyimpan rincian objek.
    if (!deltaOnly || isDatReport) {
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
        for (final r in targetRecords)
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
    }

    // 3. Tambahkan gambar dokumentasi jika diminta dan ada
    if (includePhotos) {
      final sourcePhotosDir = photosDir ?? await photosDirectory();
      if (await sourcePhotosDir.exists()) {
        for (final r in targetRecords) {
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

    final explicitPassword = password?.trim();
    final Uint8List outputBytes;
    if (!encrypt) {
      outputBytes = Uint8List.fromList(zipBytes);
    } else if (explicitPassword != null && explicitPassword.length >= 8) {
      outputBytes = await DhkpCrypto.encryptBytes(
        Uint8List.fromList(zipBytes),
        password: explicitPassword,
      );
    } else {
      outputBytes = DhkpCrypto.encryptLegacyBytes(
        Uint8List.fromList(zipBytes),
      );
    }

    final file = File(outputPath);
    file.writeAsBytesSync(outputBytes);
    return file;
  }
}
