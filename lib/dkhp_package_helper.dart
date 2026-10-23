import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path_provider/path_provider.dart';

import 'backup_crypto.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'nop_helper.dart';

/// Enkripsi & dekripsi berkas paket `.dkhp` (AES-256-CBC) dengan header khusus "DKHP".
/// Menjaga kerahasiaan data perpajakan dan foto objek WP saat dibagikan atau disimpan.
class DhkpCrypto {
  DhkpCrypto._();

  static const magic = [0x44, 0x4B, 0x48, 0x50]; // "DKHP"
  static const secret = 'CekPBBCianjur-DKHP-Package-Secret-v1';

  static enc.Key get _key {
    final digest = sha256.convert(utf8.encode(secret));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  static Uint8List encryptBytes(Uint8List plainBytes) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
    return Uint8List.fromList([...magic, ...iv.bytes, ...encrypted.bytes]);
  }

  static Uint8List? decryptBytes(Uint8List fileBytes) {
    if (fileBytes.length < magic.length + 16) return null;
    for (var i = 0; i < magic.length; i++) {
      if (fileBytes[i] != magic[i]) return null;
    }
    final iv = enc.IV(fileBytes.sublist(magic.length, magic.length + 16));
    final encrypted = enc.Encrypted(fileBytes.sublist(magic.length + 16));
    try {
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  static bool isEncrypted(List<int> bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}

/// Pengelola berkas paket `.dkhp` — format arsip terenkripsi khusus aplikasi Cek PBB Cianjur.
///
/// Paket `.dkhp` berisi:
/// 1. `data.csv`: tabel data NOP, Nama WP, Status Bayar, Target Pemda, Catatan Petugas, dsb.
/// 2. Folder `foto/`: foto lembaran SPPT / DHKP per NOP (misal `320520000402600340.jpg`).
class DhkpPackageHelper {
  static const extensionName = 'dkhp';

  static Directory? _cachedPhotosDir;
  static Set<String>? _cachedPhotoNames;

  static void resetForTesting() {
    _cachedPhotosDir = null;
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

  /// Folder lokal aplikasi untuk menyimpan foto-foto dokumen DHKP.
  static Future<Directory> photosDirectory() async {
    if (_cachedPhotosDir != null) return _cachedPhotosDir!;
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/dhkp_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedPhotosDir = dir;
    return dir;
  }

  /// Cari file foto untuk sebuah NOP jika sudah tersimpan lokal.
  static Future<File?> findPhotoForNop(String nop, {String? customFileName}) async {
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
  static Future<List<BlokRecord>> unpackDkhp(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Berkas .dkhp tidak ditemukan', filePath);
    }

    final rawBytes = await file.readAsBytes();
    Uint8List zipBytes;

    if (DhkpCrypto.isEncrypted(rawBytes)) {
      final decrypted = DhkpCrypto.decryptBytes(rawBytes);
      if (decrypted == null) {
        throw const FormatException('Gagal mendekripsi berkas .dkhp: Kunci atau format enkripsi tidak cocok.');
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
          final rawTargetPemda = row.length > 7 ? row[7].toString().trim().toLowerCase() : '';
          final isTargetPemda = rawTargetPemda == '1' ||
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
          final kecamatan = row.length > 13 && row[13].toString().trim().isNotEmpty
              ? row[13].toString().trim()
              : 'MANDE';
          final kelurahan = row.length > 14 && row[14].toString().trim().isNotEmpty
              ? row[14].toString().trim()
              : 'BOBOJONG';
          final alamatObjek = row.length > 15 ? row[15].toString().trim() : '';
          final alamatWp = row.length > 16 ? row[16].toString().trim() : '';
          final rtObjek = row.length > 17 ? row[17].toString().trim() : '';

          records.add(
            BlokRecord(
              namaWajibPajak: nama.isEmpty ? 'WP ${nopBlok(nopDigits)}/${nopWilayah(nopDigits)}' : nama,
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
              namaWajibPajak: 'WP Blok ${nopBlok(digits)} No ${nopWilayah(digits)}',
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
  static Future<File> packDkhp({
    required String outputPath,
    required List<BlokRecord> records,
    Directory? photosDir,
    bool encrypt = true,
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

    // 2. Tambahkan foto jika ada
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

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Gagal mengompresi data ke arsip ZIP.');
    }

    final outputBytes = encrypt
        ? DhkpCrypto.encryptBytes(Uint8List.fromList(zipBytes))
        : Uint8List.fromList(zipBytes);

    final file = File(outputPath);
    await file.writeAsBytes(outputBytes);
    return file;
  }
}
