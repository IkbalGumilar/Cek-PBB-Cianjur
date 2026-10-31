import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:csv/csv.dart';

import 'app_storage.dart';
import 'backup_crypto.dart';
import 'backup_password_store.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'dhkp/blok_csv_codec.dart';
import 'dhkp/dhkp_crypto.dart';
import 'dusun_data.dart';
import 'nop_helper.dart';

export 'dhkp/dhkp_crypto.dart';

/// Pengelola berkas paket `.dkhp` / `.dhkp` — format arsip terenkripsi khusus aplikasi Cek PBB Cianjur.
///
/// Paket cadangan `.dkhp` / `.dhkp` berisi:
/// 1. `manifest.json`: sidik jari (SHA-256) dari berkas DHKP dasar (`dhkpFingerprint`) serta daftar perubahan blok & nomor NOP.
/// 2. `data.csv`: baris data NOP yang mengalami perubahan (status bayar, catatan petugas, gambar dokumentasi).
/// 3. Folder `foto/`: gambar dokumentasi petugas per NOP (misal `320520000402600340.jpg`).
class DhkpPackageHelper {
  static const extensionName = 'dkhp';
  static const altExtensionName = 'dhkp';

  static const _fallbackBackupIdentities = [
    'operator',
    'unassigned',
    'dusun-1',
    'dusun-2',
    'dusun-3',
    'dusun-4',
    'dusun-5',
  ];

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
    final sortedNops =
        records
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

  static Future<Uint8List> _resolveArchiveZipBytes(
    Uint8List rawBytes, {
    String? password,
    required String errorMsgOnNull,
  }) async {
    if (DhkpCrypto.isEncrypted(rawBytes)) {
      final effectivePassword =
          password ?? await BackupPasswordStore.instance.read();
      final decrypted = await DhkpCrypto.decryptBytes(
        rawBytes,
        password: effectivePassword,
      );
      if (decrypted == null) {
        throw FormatException(errorMsgOnNull);
      }
      return decrypted;
    }

    final cpbbDecrypted = BackupCrypto.tryDecrypt(
      rawBytes,
      _fallbackBackupIdentities,
    );
    return cpbbDecrypted ?? rawBytes;
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

  /// Membaca data pratinjau (headers, baris data, dan manifest) dari berkas `.dkhp`, `.dhkp`, atau `.dat`
  /// secara aman tanpa langsung menyimpannya ke database aplikasi.
  static Future<DhkpPreviewResult> extractPreviewData(
    String filePath, {
    String? password,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Berkas tidak ditemukan', filePath);
    }

    final rawBytes = await file.readAsBytes();
    final isEncrypted = DhkpCrypto.isEncrypted(rawBytes);
    final zipBytes = await _resolveArchiveZipBytes(
      rawBytes,
      password: password,
      errorMsgOnNull:
          'Gagal mendekripsi berkas: format atau kunci enkripsi tidak cocok.',
    );

    final archive = ZipDecoder().decodeBytes(zipBytes);
    Map<String, dynamic>? manifest;
    List<String> headers = [];
    List<List<String>> rows = [];

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final nameLower = entry.name.toLowerCase();
      if (nameLower.endsWith('manifest.json')) {
        try {
          final text = utf8.decode(entry.content as List<int>);
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) {
            manifest = decoded;
          }
        } catch (_) {}
      } else if (nameLower.endsWith('.csv')) {
        try {
          final content = utf8.decode(entry.content as List<int>);
          final rawRows = Csv().decode(content);
          if (rawRows.isNotEmpty) {
            headers = rawRows.first.map((e) => e.toString().trim()).toList();
            rows = rawRows
                .skip(1)
                .map((r) => r.map((c) => c.toString().trim()).toList())
                .toList();
          }
        } catch (_) {}
      }
    }

    // Jika tidak ada berkas CSV tapi terdapat rincian perubahan pada manifest
    if (rows.isEmpty && manifest != null && manifest['changes'] is List) {
      headers = [
        'No',
        'Blok',
        'Nomor',
        'NOP',
        'Tahun',
        'Status Bayar',
        'Tanggal Bayar',
      ];
      final changes = manifest['changes'] as List;
      for (var i = 0; i < changes.length; i++) {
        final c = changes[i];
        if (c is Map) {
          rows.add([
            '${i + 1}',
            (c['blok'] ?? '').toString(),
            (c['nomor'] ?? '').toString(),
            (c['nop'] ?? '').toString(),
            (c['tahunBayar'] ?? '').toString(),
            (c['statusBayar'] ?? '').toString(),
            (c['tanggalBayar'] ?? '').toString(),
          ]);
        }
      }
    }

    if (headers.isEmpty) {
      headers = ['Data'];
    }

    return DhkpPreviewResult(
      manifest: manifest,
      headers: headers,
      rows: rows,
      isEncrypted: isEncrypted,
    );
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
    var cached = _cachedPhotoNames;
    cached ??= await refreshPhotoNamesCache();
    return findPhotoForNopSync(
      nop,
      customFileName: customFileName,
      photosDir: dir,
      cachedNames: cached,
    );
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
    bool requireBaseDhkp = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Berkas .dkhp tidak ditemukan', filePath);
    }

    final rawBytes = await file.readAsBytes();
    final zipBytes = await _resolveArchiveZipBytes(
      rawBytes,
      password: password,
      errorMsgOnNull:
          'Gagal mendekripsi berkas .dkhp: Kunci atau format enkripsi tidak cocok.',
    );

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
            final scopeMap = Map<String, dynamic>.from(
              manifest['scope'] as Map,
            );
            await DusunData.instance.setScope(DusunScope.fromJson(scopeMap));
          }
        }
      } catch (_) {}
    }

    final records = <BlokRecord>[];
    final currentYear = '${DateTime.now().year}';

    if (dataFile != null && dataFile.name.toLowerCase().endsWith('.csv')) {
      final content = utf8.decode(dataFile.content as List<int>);
      records.addAll(
        BlokCsvCodec.decodeArchiveCsv(content, fallbackYear: currentYear),
      );
    }

    // Validasi kecocokan berkas DHKP dasar sebelum mengekstrak foto & menerapkan perubahan
    final existingRecords = await BlokDataStore.instance.loadAll();
    final isDeltaArchive =
        manifest != null && (manifest['isDeltaOnly'] == true);
    final isDatReport =
        filePath.toLowerCase().endsWith('.dat') ||
        (manifest != null && manifest['format'] == 'laporan_dat_v1');

    _validateArchiveCompatibility(
      isDatReport: isDatReport,
      requireBaseDhkp: requireBaseDhkp,
      isDeltaArchive: isDeltaArchive,
      records: records,
      existingRecords: existingRecords,
      manifest: manifest,
    );

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
      records.addAll(
        _recordsFromManifestChanges(
          changesList: manifest['changes'] as List,
          existingRecords: existingRecords,
          existingByNop: existingByNop,
          existingByBlokNomor: existingByBlokNomor,
          currentYear: currentYear,
        ),
      );
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
        mergedRecords.add(_mergeDeltaWithBase(r, base));
      } else {
        mergedRecords.add(r);
      }
    }

    if (mergedRecords.isNotEmpty) {
      await BlokDataStore.instance.upsertAll(mergedRecords);
    }

    return mergedRecords;
  }

  static void _validateArchiveCompatibility({
    required bool isDatReport,
    required bool requireBaseDhkp,
    required bool isDeltaArchive,
    required List<BlokRecord> records,
    required List<BlokRecord> existingRecords,
    required Map<String, dynamic>? manifest,
  }) {
    if (isDatReport) {
      final incomingBloks = <String>{};
      for (final r in records) {
        final b =
            int.tryParse(r.blok)?.toString() ??
            r.blok.replaceAll(RegExp(r'[^0-9]'), '');
        if (b.isNotEmpty) incomingBloks.add(b);
      }
      if (manifest != null && manifest['changes'] is List) {
        for (final item in manifest['changes'] as List) {
          if (item is Map) {
            final rawB = (item['blok'] ?? '').toString();
            final b =
                int.tryParse(rawB)?.toString() ??
                rawB.replaceAll(RegExp(r'[^0-9]'), '');
            if (b.isNotEmpty) incomingBloks.add(b);
          }
        }
      }

      final localBloks = existingRecords
          .map(
            (r) =>
                int.tryParse(r.blok)?.toString() ??
                r.blok.replaceAll(RegExp(r'[^0-9]'), ''),
          )
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
  }

  static List<BlokRecord> _recordsFromManifestChanges({
    required List<dynamic> changesList,
    required List<BlokRecord> existingRecords,
    required Map<String, BlokRecord> existingByNop,
    required Map<String, BlokRecord> existingByBlokNomor,
    required String currentYear,
  }) {
    final records = <BlokRecord>[];
    for (final item in changesList) {
      if (item is! Map) continue;
      final rawBlok = (item['blok'] ?? '').toString().trim().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final rawNomor = (item['nomor'] ?? '').toString().trim().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final rawNop = (item['nop'] ?? '').toString().trim().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      BlokRecord? baseRecord;
      if (rawBlok.isNotEmpty && rawNomor.isNotEmpty) {
        final key = '${rawBlok.padLeft(3, '0')}_${rawNomor.padLeft(4, '0')}';
        baseRecord = existingByBlokNomor[key];
      }
      if (baseRecord == null && rawNop.length == 18) {
        baseRecord = existingByNop[rawNop];
      }

      if (baseRecord != null) {
        final tglStr = (item['tanggalBayar'] ?? baseRecord.tanggalBayar)
            .toString()
            .trim();
        final rawSt = (item['statusBayar'] ?? baseRecord.statusBayar)
            .toString()
            .trim();
        final effectiveSt = (tglStr.isNotEmpty && tglStr != '0')
            ? 'Sudah Bayar'
            : (rawSt.isNotEmpty ? rawSt : 'Belum Bayar');
        records.add(
          baseRecord.copyWith(
            tahunBayar: (item['tahunBayar'] ?? baseRecord.tahunBayar)
                .toString(),
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
    return records;
  }

  static BlokRecord _mergeDeltaWithBase(BlokRecord r, BlokRecord base) {
    return base.copyWith(
      statusBayar: r.statusBayar,
      tanggalBayar: r.tanggalBayar.isNotEmpty
          ? r.tanggalBayar
          : base.tanggalBayar,
      catatan: r.catatan.isNotEmpty ? r.catatan : base.catatan,
      namaFoto: (r.namaFoto != null && r.namaFoto!.isNotEmpty)
          ? r.namaFoto
          : base.namaFoto,
      isTargetPemda: r.isTargetPemda,
      namaWajibPajak:
          (r.namaWajibPajak.isNotEmpty && !r.namaWajibPajak.startsWith('WP '))
          ? r.namaWajibPajak
          : base.namaWajibPajak,
      alamatObjek: r.alamatObjek.isNotEmpty ? r.alamatObjek : base.alamatObjek,
      alamatWp: r.alamatWp.isNotEmpty ? r.alamatWp : base.alamatWp,
      rtObjek: r.rtObjek.isNotEmpty ? r.rtObjek : base.rtObjek,
      luasBumi: r.luasBumi.isNotEmpty ? r.luasBumi : base.luasBumi,
      luasBangunan: r.luasBangunan.isNotEmpty
          ? r.luasBangunan
          : base.luasBangunan,
      njopBumi: r.njopBumi.isNotEmpty ? r.njopBumi : base.njopBumi,
      njopBangunan: r.njopBangunan.isNotEmpty
          ? r.njopBangunan
          : base.njopBangunan,
      jumlahPbb: r.jumlahPbb.isNotEmpty ? r.jumlahPbb : base.jumlahPbb,
    );
  }

  /// Membungkus data perubahan DHKP dan gambar dokumentasi menjadi paket terenkripsi `.dkhp`.
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

    // 1. Buat manifest.json
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
    if (!deltaOnly || isDatReport) {
      final csvString = BlokCsvCodec.encodeRecords(targetRecords);
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
      outputBytes = DhkpCrypto.encryptLegacyBytes(Uint8List.fromList(zipBytes));
    }

    final file = File(outputPath);
    file.writeAsBytesSync(outputBytes);
    return file;
  }
}
