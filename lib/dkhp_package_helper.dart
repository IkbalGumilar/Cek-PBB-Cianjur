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
import 'cianjur_wilayah_data.dart';
import 'dhkp/blok_csv_codec.dart';
import 'dhkp/dhkp_crypto.dart';
import 'dusun_data.dart';
import 'map/kml_parser.dart';
import 'map/map_pin_store.dart';
import 'nop_helper.dart';
import 'wilayah_kerja_store.dart';

export 'dhkp/dhkp_crypto.dart';

/// Informasi satu berkas `.dkhp` hasil pemecahan (Master Desa atau per Dusun).
class SplitDkhpExportEntry {
  final bool isMaster;
  final int? dusunNumber;
  final String label;
  final File file;
  final int recordCount;
  final List<String> blokList;

  const SplitDkhpExportEntry({
    required this.isMaster,
    this.dusunNumber,
    required this.label,
    required this.file,
    required this.recordCount,
    required this.blokList,
  });
}

/// Hasil keseluruhan proses pemecahan (split) paket `.dkhp` terenkripsi per Kedusunan.
class SplitDkhpExportResult {
  final Directory outputDirectory;
  final SplitDkhpExportEntry? masterEntry;
  final List<SplitDkhpExportEntry> dusunEntries;
  final int totalRecords;
  final int assignedRecordCount;
  final int unassignedRecordCount;
  final List<String> unassignedBloks;

  const SplitDkhpExportResult({
    required this.outputDirectory,
    this.masterEntry,
    required this.dusunEntries,
    required this.totalRecords,
    required this.assignedRecordCount,
    required this.unassignedRecordCount,
    required this.unassignedBloks,
  });

  List<SplitDkhpExportEntry> get allEntries => [
    ?masterEntry,
    ...dusunEntries,
  ];
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

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static Map<String, dynamic>? _decodeManifestEntry(ArchiveFile entry) {
    try {
      final text = utf8.decode(entry.content as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// Menghitung sidik jari (SHA-256 fingerprint) langsung dari daftar NOP di dalam berkas DHKP.
  /// Murni dihitung dari isi berkas DHKP (bukan ID perangkat/HP), sehingga tetap cocok 100%
  /// saat berpindah HP selama berkas DHKP dasarnya sama, dan otomatis menolak jika berkas DHKP berbeda.
  static String computeDhkpFingerprint(Iterable<BlokRecord> records) {
    final sortedNops =
        records
            .map((r) => _digitsOnly(r.nop))
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
      if (DhkpCrypto.isLegacyCbcFormat(rawBytes)) {
        final decrypted = await DhkpCrypto.decryptBytes(rawBytes);
        if (decrypted == null) {
          throw FormatException(errorMsgOnNull);
        }
        return decrypted;
      }

      final explicitPass = password?.trim();
      if (explicitPass != null && explicitPass.isNotEmpty) {
        final decrypted = await DhkpCrypto.decryptBytes(
          rawBytes,
          password: explicitPass,
        );
        if (decrypted == null) {
          throw FormatException(errorMsgOnNull);
        }
        return decrypted;
      }

      final candidates = await BackupPasswordStore.instance
          .readCandidateSecrets();
      for (final secret in candidates) {
        try {
          final decrypted = await DhkpCrypto.decryptBytes(
            rawBytes,
            password: secret,
          );
          if (decrypted != null) {
            return decrypted;
          }
        } on DkhpPasswordException {
          continue;
        }
      }

      throw const DkhpPasswordException(
        'Kata sandi atau kunci pemulihan diperlukan untuk membuka backup ini.',
      );
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
      final zipBytes = await _resolveArchiveZipBytes(
        rawBytes,
        password: password,
        errorMsgOnNull: '',
      );
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (entry.name.toLowerCase().endsWith('manifest.json')) {
          return _decodeManifestEntry(entry);
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
        manifest = _decodeManifestEntry(entry) ?? manifest;
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
    ArchiveFile? mapPinsJsonFile;
    ArchiveFile? mapPinsKmlFile;
    final photoFiles = <ArchiveFile>[];

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final nameLower = entry.name.toLowerCase();
      if (nameLower.endsWith('manifest.json')) {
        manifestFile = entry;
      } else if (nameLower.endsWith('map_pins.json')) {
        mapPinsJsonFile = entry;
      } else if (nameLower.endsWith('.kml')) {
        mapPinsKmlFile = entry;
      } else if (nameLower.endsWith('.csv') || nameLower.endsWith('.json')) {
        dataFile = entry;
      } else if (nameLower.endsWith('.jpg') ||
          nameLower.endsWith('.jpeg') ||
          nameLower.endsWith('.png') ||
          nameLower.endsWith('.webp')) {
        photoFiles.add(entry);
      }
    }

    final manifest = manifestFile != null
        ? _decodeManifestEntry(manifestFile)
        : null;

    final isDatReport =
        filePath.toLowerCase().endsWith('.dat') ||
        (manifest != null && manifest['format'] == 'laporan_dat_v1');

    final records = <BlokRecord>[];
    final currentYear = '${DateTime.now().year}';

    if (dataFile != null && dataFile.name.toLowerCase().endsWith('.csv')) {
      final content = utf8.decode(dataFile.content as List<int>);
      records.addAll(
        BlokCsvCodec.decodeArchiveCsv(content, fallbackYear: currentYear),
      );
    }

    // Validasi kecocokan berkas DHKP dasar sebelum mengekstrak foto & menerapkan perubahan
    // (Termasuk sebelum memodifikasi konfigurasi dusun/wilayah aktif dari manifest)
    final existingRecords = await BlokDataStore.instance.loadAll();
    final isDeltaArchive =
        manifest != null && (manifest['isDeltaOnly'] == true);

    _validateArchiveCompatibility(
      isDatReport: isDatReport,
      requireBaseDhkp: requireBaseDhkp,
      isDeltaArchive: isDeltaArchive,
      records: records,
      existingRecords: existingRecords,
      manifest: manifest,
    );

    // Pengaturan dusun & scope hanya diterapkan untuk paket DHKP dasar (.dkhp)
    // setelah validasi kompatibilitas berhasil dilalui.
    // Berkas laporan .dat TIDAK boleh menimpa scope/dusun pengguna aplikasi.
    if (!isDatReport && manifest != null) {
      final rawDusunList = manifest['dusuns'] is List
          ? manifest['dusuns'] as List
          : (manifest['kadus'] is List ? manifest['kadus'] as List : null);
      if (rawDusunList != null) {
        final parsedDusuns = <Dusun>[];
        for (final item in rawDusunList) {
          if (item is Map) {
            parsedDusuns.add(Dusun.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        if (parsedDusuns.isNotEmpty) {
          await DusunData.instance.setDusuns(parsedDusuns);
        }
      }
      if (manifest['scope'] is Map) {
        final scopeMap = Map<String, dynamic>.from(manifest['scope'] as Map);
        final parsedScope = DusunScope.fromJson(scopeMap);
        await DusunData.instance.setScope(parsedScope);
        if (parsedScope.isDusunScope && parsedScope.dusunNumber != null) {
          await WilayahKerjaStore.instance.setSelectedDusun(
            parsedScope.dusunNumber,
          );
          await WilayahKerjaStore.instance.markAsked();
        }
      }

      // Sinkronisasi wilayah & NOP aktif dari manifest
      if (manifest['desa'] is Map) {
        final desaMap = manifest['desa'] as Map;
        final kecMap = manifest['kecamatan'] as Map?;
        final rawKecCode = kecMap?['kode']?.toString() ?? activeKecamatanCode;
        final rawKelCode = desaMap['kode']?.toString() ?? activeKelurahanCode;
        final kecCode = extractKecamatanCode3(rawKecCode);
        final kelCode = extractKelurahanCode3(rawKelCode);
        final kecName = kecMap?['nama']?.toString();
        final desaName = desaMap['nama']?.toString();

        await saveActiveWilayah(
          kecCode: kecCode.isNotEmpty ? kecCode : activeKecamatanCode,
          kelCode: kelCode.isNotEmpty ? kelCode : activeKelurahanCode,
          desaName: desaName,
          kecName: kecName,
        );
      }

      // Sinkronisasi koordinat kantor desa dari manifest
      if (manifest['geospasial'] is Map || manifest['desa'] is Map) {
        final geo = manifest['geospasial'] is Map
            ? manifest['geospasial'] as Map
            : null;
        final kantor =
            geo?['kantor_desa'] as Map? ??
            (manifest['desa'] is Map
                ? (manifest['desa'] as Map)['kantor_desa'] as Map?
                : null);
        if (kantor != null) {
          final lat = (kantor['lat'] as num?)?.toDouble();
          final lng = (kantor['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            await DusunData.instance.setKantorDesaLocation(lat, lng);
          }
        }
      }
    }

    // Indeks data lokal yang sudah ada:
    // 1. Berdasarkan NOP + tahunBayar (kunci unik pasti)
    // 2. Berdasarkan NOP saja (untuk rincian objek jika NOP baru pada tahun berjalan)
    final existingByKey = <String, BlokRecord>{
      for (final r in existingRecords) '${_digitsOnly(r.nop)}|${r.tahunBayar}': r,
    };
    final existingByNopLatest = <String, BlokRecord>{
      for (final r in existingRecords) _digitsOnly(r.nop): r,
    };
    final existingByBlokNomor = <String, BlokRecord>{
      for (final r in existingRecords)
        '${_digitsOnly(r.blok).padLeft(3, '0')}_${_digitsOnly(r.wilayah).padLeft(4, '0')}':
            r,
    };

    // Kalau di dalam arsip tidak ada data.csv tapi ada manifest changes (hanya blok & nomor)
    if (records.isEmpty && manifest != null && manifest['changes'] is List) {
      records.addAll(
        _recordsFromManifestChanges(
          changesList: manifest['changes'] as List,
          existingRecords: existingRecords,
          existingByNop: existingByNopLatest,
          existingByBlokNomor: existingByBlokNomor,
          currentYear: currentYear,
        ),
      );
    }

    // Kalau di dalam arsip tidak ada data.csv tapi ada kumpulan foto dengan nama NOP
    if (records.isEmpty && photoFiles.isNotEmpty) {
      for (final p in photoFiles) {
        final baseName = p.name.split('/').last;
        final digits = _digitsOnly(baseName);
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
      final baseName = p.name
          .split(RegExp(r'[\\/]'))
          .last
          .replaceAll('..', '')
          .trim();
      if (baseName.isEmpty) continue;
      final targetFile = File('${photosDir.path}/$baseName');
      await targetFile.writeAsBytes(p.content as List<int>);
    }
    invalidatePhotoCache();

    // Gabungkan data perubahan ke data DHKP dasar:
    // - Jika NOP + Tahun sudah ada: cocokkan dan perbarui status/tanggal/foto/catatan
    // - Jika NOP sudah ada di tahun lain: gunakan rincian objek dari tahun lain, tapi buat baris baru untuk tahun ini
    // - Jika NOP belum ada sama sekali: tambahkan NOP baru ke database
    var mergedRecords = <BlokRecord>[];
    for (final r in records) {
      final cleanNop = _digitsOnly(r.nop);
      final key = '$cleanNop|${r.tahunBayar}';
      final exactBase = existingByKey[key];
      final anyBase = existingByNopLatest[cleanNop];

      if (exactBase != null && (isDeltaArchive || isDatReport)) {
        mergedRecords.add(_mergeDeltaWithBase(r, exactBase));
      } else if (anyBase != null && (isDeltaArchive || isDatReport)) {
        mergedRecords.add(
          anyBase.copyWith(
            tahunBayar: r.tahunBayar,
            jumlahPbb: r.jumlahPbb.isNotEmpty ? r.jumlahPbb : anyBase.jumlahPbb,
            statusBayar: r.statusBayar,
            tanggalBayar: r.tanggalBayar,
            catatan: r.catatan,
            namaFoto: r.namaFoto,
            isTargetPemda: r.isTargetPemda,
          ),
        );
      } else if (exactBase != null) {
        // Saat memuat berkas DHKP dasar baru, pertahankan catatan/foto lokal jika di arsip kosong
        mergedRecords.add(
          r.copyWith(
            catatan: r.catatan.isNotEmpty ? r.catatan : exactBase.catatan,
            namaFoto: (r.namaFoto != null && r.namaFoto!.isNotEmpty)
                ? r.namaFoto
                : exactBase.namaFoto,
          ),
        );
      } else {
        // NOP baru, tambahkan langsung
        mergedRecords.add(r);
      }
    }

    // Jika paket yang dibuka adalah DHKP dasar yang dikunci ke Dusun tertentu (hasil Split Dusun),
    // saring hanya blok yang diizinkan oleh Dusun tersebut dan bersihkan data dusun lain.
    final activeScope = DusunData.instance.scope;
    if (!isDatReport &&
        !isDeltaArchive &&
        activeScope.isDusunScope &&
        activeScope.allowedBloks.isNotEmpty) {
      final allowedSet = activeScope.allowedBloks
          .map((b) => _digitsOnly(b).padLeft(3, '0'))
          .toSet();
      mergedRecords = mergedRecords
          .where((r) => allowedSet.contains(_digitsOnly(r.blok).padLeft(3, '0')))
          .toList();
      await BlokDataStore.instance.clearAll();
      if (mergedRecords.isNotEmpty) {
        await BlokDataStore.instance.upsertAll(mergedRecords);
      }
    } else if (mergedRecords.isNotEmpty) {
      await BlokDataStore.instance.upsertAll(mergedRecords);
    }

    // Gabungkan data koordinat/pin peta bila tersedia di arsip backup (.dat / .dkhp)
    if (mapPinsJsonFile != null) {
      try {
        final pinsJsonStr = utf8.decode(mapPinsJsonFile.content as List<int>);
        final importedPins = MapPinStore.decodePinsJson(pinsJsonStr);
        await MapPinStore.instance.mergeImportedPins(importedPins);
      } catch (_) {}
    } else if (mapPinsKmlFile != null) {
      try {
        final kmlStr = utf8.decode(mapPinsKmlFile.content as List<int>);
        final parsed = KmlParser.parse(kmlStr, dhkpRecords: mergedRecords);
        final importedPins = MapPinStore.entriesFromDots(
          parsed.dots,
          source: 'kml_backup',
        );
        await MapPinStore.instance.mergeImportedPins(importedPins);
      } catch (_) {}
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
      // Laporan .dat diizinkan untuk mencocokkan data yang ada maupun menambahkan
      // NOP baru ke Buku Catatan tanpa ditolak sebagai "Data tidak sesuai".
      return;
    }

    if (requireBaseDhkp || isDeltaArchive) {
      if (requireBaseDhkp && existingRecords.isEmpty) {
        throw const DhkpBackupValidationException(
          'Berkas DHKP dasar belum dimuat. Muat berkas DHKP terlebih dahulu sebelum menggunakan berkas cadangan perubahan.',
        );
      }

      if (existingRecords.isNotEmpty && manifest != null) {
        final backupFingerprint =
            (manifest['dhkpFingerprint'] as String?)?.trim() ?? '';
        final masterFingerprint =
            (manifest['masterDhkpFingerprint'] as String?)?.trim() ?? '';
        final localFingerprint = computeDhkpFingerprint(existingRecords);

        if (backupFingerprint.isNotEmpty && localFingerprint.isNotEmpty) {
          var isCompatible =
              localFingerprint == backupFingerprint ||
              (masterFingerprint.isNotEmpty &&
                  localFingerprint == masterFingerprint);

          // Cek kecocokan lintas Master Desa <-> Split Dusun:
          // 1. Jika perangkat memegang Master Desa dan cadangan berasal dari salah satu Dusun
          if (!isCompatible && manifest['scope'] is Map) {
            final backupScope = DusunScope.fromJson(
              Map<String, dynamic>.from(manifest['scope'] as Map),
            );
            if (backupScope.allowedBloks.isNotEmpty) {
              final allowedSet = backupScope.allowedBloks
                  .map((b) => _digitsOnly(b).padLeft(3, '0'))
                  .toSet();
              final scopedExisting = existingRecords
                  .where(
                    (r) =>
                        allowedSet.contains(_digitsOnly(r.blok).padLeft(3, '0')),
                  )
                  .toList();
              if (scopedExisting.isNotEmpty &&
                  computeDhkpFingerprint(scopedExisting) == backupFingerprint) {
                isCompatible = true;
              }
            }
          }

          // 2. Jika perangkat memegang salah satu Split Dusun dan cadangan memuat peta dusunFingerprints
          if (!isCompatible && manifest['dusunFingerprints'] is Map) {
            final fpMap = manifest['dusunFingerprints'] as Map;
            for (final val in fpMap.values) {
              if (val?.toString().trim() == localFingerprint) {
                isCompatible = true;
                break;
              }
            }
          }

          if (!isCompatible) {
            throw const DhkpBackupValidationException(
              'Berkas cadangan ditolak: Data perubahan ini berasal dari berkas DHKP yang berbeda dengan data DHKP di aplikasi.',
            );
          }
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
      final rawBlok = _digitsOnly((item['blok'] ?? '').toString());
      final rawNomor = _digitsOnly((item['nomor'] ?? '').toString());
      final rawNop = _digitsOnly((item['nop'] ?? '').toString());

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
        final sampleNop = _digitsOnly(existingRecords.first.nop);
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
    final sameYear = r.tahunBayar == base.tahunBayar;
    return base.copyWith(
      tahunBayar: r.tahunBayar,
      statusBayar: r.statusBayar,
      tanggalBayar: r.tanggalBayar.isNotEmpty
          ? r.tanggalBayar
          : (sameYear ? base.tanggalBayar : ''),
      catatan: r.catatan.isNotEmpty
          ? r.catatan
          : (sameYear ? base.catatan : ''),
      namaFoto: (r.namaFoto != null && r.namaFoto!.isNotEmpty)
          ? r.namaFoto
          : (sameYear ? base.namaFoto : null),
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
    List<MapPinEntry>? mapPins,
    String? kecamatanCode,
    String? kecamatanName,
    String? kelurahanCode,
    String? desaName,
    double? kantorDesaLat,
    double? kantorDesaLng,
    String? tahunPajak,
    String? masterDhkpFingerprint,
    Map<String, String>? dusunFingerprints,
  }) async {
    final archive = Archive();
    final isDatReport = outputPath.toLowerCase().endsWith('.dat');
    final effectiveBase = baseRecords ?? records;
    final dhkpFingerprint = computeDhkpFingerprint(effectiveBase);
    final changedList = extractChangedRecords(records);
    final targetRecords = (deltaOnly && changedList.isNotEmpty)
        ? changedList
        : records;

    final rawKecCode =
        (kecamatanCode != null && kecamatanCode.trim().isNotEmpty)
        ? kecamatanCode.trim()
        : (activeKecamatanCode.isNotEmpty ? activeKecamatanCode : '200');
    final kecCode3 = extractKecamatanCode3(rawKecCode).isNotEmpty
        ? extractKecamatanCode3(rawKecCode)
        : '200';
    final resolvedKecName =
        (kecamatanName != null && kecamatanName.trim().isNotEmpty)
        ? kecamatanName.trim().toUpperCase()
        : (activeKecamatanName.isNotEmpty
              ? activeKecamatanName
              : lookupKecamatanName(kecCode3));

    final rawKelCode =
        (kelurahanCode != null && kelurahanCode.trim().isNotEmpty)
        ? kelurahanCode.trim()
        : (activeKelurahanCode.isNotEmpty ? activeKelurahanCode : '004');
    final kelCode3 = extractKelurahanCode3(rawKelCode).isNotEmpty
        ? extractKelurahanCode3(rawKelCode)
        : '004';
    final resolvedDesaName = (desaName != null && desaName.trim().isNotEmpty)
        ? desaName.trim().toUpperCase()
        : (activeDesaName.isNotEmpty
              ? activeDesaName
              : lookupKelurahanName(kelCode3, kecamatanCode: kecCode3));

    final effectiveTahun = (tahunPajak != null && tahunPajak.trim().isNotEmpty)
        ? tahunPajak.trim()
        : (records.isNotEmpty && records.first.tahunBayar.trim().isNotEmpty
              ? records.first.tahunBayar.trim()
              : '${DateTime.now().year}');

    // 1. Buat manifest.json
    if (effectiveBase.isNotEmpty || isDatReport || (dusuns?.isNotEmpty ?? false)) {
      final effectiveDusuns = dusuns ?? DusunData.instance.allDusuns;
      final effectiveScope = scope ?? DusunData.instance.scope;
      final kantorLat =
          kantorDesaLat ?? DusunData.instance.kantorDesaLat ?? -6.763587;
      final kantorLng =
          kantorDesaLng ?? DusunData.instance.kantorDesaLng ?? 107.238769;
      final kantorDesaMap = <String, dynamic>{
        'nama': 'Kantor Desa $resolvedDesaName',
        'lat': kantorLat,
        'lng': kantorLng,
        'zoom_fokus': 17.5,
      };

      double pusatLat = kantorLat;
      double pusatLng = kantorLng;
      double pusatZoom = 14.5;
      if (effectiveScope.isDusunScope && effectiveScope.dusunNumber != null) {
        for (final d in effectiveDusuns) {
          if (d.number == effectiveScope.dusunNumber &&
              d.focusLat != null &&
              d.focusLng != null) {
            pusatLat = d.focusLat!;
            pusatLng = d.focusLng!;
            pusatZoom = d.focusZoom ?? 16.0;
            break;
          }
        }
      }

      final dusunJsonList = effectiveDusuns.map((d) => d.toJson()).toList();
      final manifestMap = <String, dynamic>{
        'format': isDatReport ? 'laporan_dat_v1' : 'dhkp_delta_v1',
        'versi_manifest': '2.0',
        'tahun': effectiveTahun,
        'tahun_pajak': effectiveTahun,
        'isDeltaOnly': deltaOnly,
        'dhkpFingerprint': dhkpFingerprint,
        'masterDhkpFingerprint':
            masterDhkpFingerprint ?? dhkpFingerprint,
        if (dusunFingerprints != null && dusunFingerprints.isNotEmpty)
          'dusunFingerprints': dusunFingerprints,
        'baseTotalNop': effectiveBase.length,
        'changedCount': changedList.length,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'kabupaten': {
          'kode': '3205',
          'nama': 'CIANJUR',
          'provinsi': 'JAWA BARAT',
        },
        'kecamatan': {
          'kode': kecCode3,
          'kode_vtax': '3205$kecCode3',
          'nama': resolvedKecName,
        },
        'desa': {
          'kode': kelCode3,
          'kode_vtax': '3205$kecCode3$kelCode3',
          'nama': resolvedDesaName,
          'prefix_nop': '3205$kecCode3$kelCode3',
          'kantor_desa': kantorDesaMap,
        },
        'geospasial': {
          'pusat_peta': {
            'lat': pusatLat,
            'lng': pusatLng,
            'zoom_awal': pusatZoom,
          },
          'kantor_desa': kantorDesaMap,
        },
        if (dusunJsonList.isNotEmpty) ...{
          'dusuns': dusunJsonList,
          'kadus': dusunJsonList,
        },
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

    // 4. Sertakan koordinat pin peta petugas (map_pins.json & map_pins.kml) bila ada
    final pins = mapPins ?? await MapPinStore.instance.loadAll();
    if (pins.isNotEmpty) {
      final pinsBytes = utf8.encode(MapPinStore.encodePinsJson(pins));
      archive.addFile(
        ArchiveFile('map_pins.json', pinsBytes.length, pinsBytes),
      );

      final groupedDots = MapPinStore.buildGroupedDots(
        pins: pins,
        dhkpRecords: records,
      );
      if (groupedDots.isNotEmpty) {
        final kmlBytes = utf8.encode(
          KmlParser.exportToKml(
            villageName: resolvedDesaName,
            dots: groupedDots,
          ),
        );
        archive.addFile(ArchiveFile('map_pins.kml', kmlBytes.length, kmlBytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Gagal mengompresi data ke arsip ZIP.');
    }

    final Uint8List outputBytes;
    if (!encrypt) {
      outputBytes = Uint8List.fromList(zipBytes);
    } else {
      final explicitPassword = password?.trim();
      final effectivePassword =
          (explicitPassword != null && explicitPassword.isNotEmpty)
          ? explicitPassword
          : await BackupPasswordStore.instance.getOrCreateActiveSecret();
      outputBytes = await DhkpCrypto.encryptBytes(
        Uint8List.fromList(zipBytes),
        password: effectivePassword,
      );
    }

    final file = File(outputPath);
    file.writeAsBytesSync(outputBytes);
    return file;
  }

  static String _sanitizeFileSegment(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'DESA' : cleaned;
  }

  /// Memecah (split) data DHKP menjadi beberapa berkas `.dkhp` terenkripsi (`DKH2` `AES-256-GCM`)
  /// sesuai jumlah Kedusunan di dalam manifest/konfigurasi (misal: 3 Dusun -> 3 berkas Dusun,
  /// atau Desa Bobojong 5 Dusun -> 5 berkas Dusun, ditambah opsional 1 berkas Master Desa).
  ///
  /// Setiap berkas Dusun hanya berisi baris `BlokRecord` untuk blok-blok pada Dusun tersebut,
  /// serta `manifest.json` lengkap dengan `scope: { role: 'dusun', dusunNumber, dusunName, allowedBloks }`.
  static Future<SplitDkhpExportResult> packSplitDkhpByDusun({
    required Directory outputDirectory,
    required List<BlokRecord> records,
    required List<Dusun> dusuns,
    String? kecamatanCode,
    String? kecamatanName,
    String? kelurahanCode,
    String? desaName,
    double? kantorDesaLat,
    double? kantorDesaLng,
    String? tahunPajak,
    String? password,
    bool includeMasterDesa = true,
    bool includePhotos = true,
    Directory? photosDir,
    List<MapPinEntry>? mapPins,
  }) async {
    if (dusuns.isEmpty) {
      throw ArgumentError(
        'Daftar dusun tidak boleh kosong saat memecah (split) berkas .dkhp.',
      );
    }
    final pwdError = DhkpCrypto.validateOptionalPassword(password);
    if (pwdError != null) {
      throw FormatException(pwdError);
    }
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final rawKecCode =
        (kecamatanCode != null && kecamatanCode.trim().isNotEmpty)
        ? kecamatanCode.trim()
        : (activeKecamatanCode.isNotEmpty ? activeKecamatanCode : '200');
    final kecCode3 = extractKecamatanCode3(rawKecCode).isNotEmpty
        ? extractKecamatanCode3(rawKecCode)
        : '200';
    final resolvedKecName =
        (kecamatanName != null && kecamatanName.trim().isNotEmpty)
        ? kecamatanName.trim().toUpperCase()
        : (activeKecamatanName.isNotEmpty
              ? activeKecamatanName
              : lookupKecamatanName(kecCode3));

    final rawKelCode =
        (kelurahanCode != null && kelurahanCode.trim().isNotEmpty)
        ? kelurahanCode.trim()
        : (activeKelurahanCode.isNotEmpty ? activeKelurahanCode : '004');
    final kelCode3 = extractKelurahanCode3(rawKelCode).isNotEmpty
        ? extractKelurahanCode3(rawKelCode)
        : '004';
    final resolvedDesaName = (desaName != null && desaName.trim().isNotEmpty)
        ? desaName.trim().toUpperCase()
        : (activeDesaName.isNotEmpty
              ? activeDesaName
              : lookupKelurahanName(kelCode3, kecamatanCode: kecCode3));

    final effectiveTahun = (tahunPajak != null && tahunPajak.trim().isNotEmpty)
        ? tahunPajak.trim()
        : (records.isNotEmpty && records.first.tahunBayar.trim().isNotEmpty
              ? records.first.tahunBayar.trim()
              : '${DateTime.now().year}');

    final safeDesa = _sanitizeFileSegment(resolvedDesaName);
    final safeTahun = _sanitizeFileSegment(effectiveTahun);
    final allPins = mapPins ?? await MapPinStore.instance.loadAll();

    // Hitung fingerprint Master Desa dan masing-masing Dusun agar kompatibilitas dua arah terjamin.
    final masterFingerprint = computeDhkpFingerprint(records);
    final dusunFingerprints = <String, String>{};
    final dusunRecordsByNumber = <int, List<BlokRecord>>{};
    final dusunBloksByNumber = <int, List<String>>{};
    final allAssignedBloks = <String>{};

    for (final d in dusuns) {
      final normalizedBloks =
          d.bloks
              .map((b) => _digitsOnly(b))
              .where((b) => b.isNotEmpty)
              .map((b) => b.padLeft(3, '0'))
              .toSet()
              .toList()
            ..sort();
      final blokSet = normalizedBloks.toSet();
      allAssignedBloks.addAll(blokSet);

      final filtered = records
          .where((r) => blokSet.contains(_digitsOnly(r.blok).padLeft(3, '0')))
          .toList();
      dusunRecordsByNumber[d.number] = filtered;
      dusunBloksByNumber[d.number] = normalizedBloks;
      dusunFingerprints['${d.number}'] = computeDhkpFingerprint(filtered);
    }

    SplitDkhpExportEntry? masterEntry;
    if (includeMasterDesa) {
      final masterFileName = 'DHKP_MASTER_${safeDesa}_$safeTahun.dkhp';
      final masterPath =
          '${outputDirectory.path}${Platform.pathSeparator}$masterFileName';
      final allBlokSet =
          records
              .map((r) => _digitsOnly(r.blok))
              .where((b) => b.isNotEmpty)
              .map((b) => b.padLeft(3, '0'))
              .toSet()
              .toList()
            ..sort();
      final masterFile = await packDkhp(
        outputPath: masterPath,
        records: records,
        baseRecords: records,
        photosDir: photosDir,
        encrypt: true,
        includePhotos: includePhotos,
        deltaOnly: false,
        password: password,
        dusuns: dusuns,
        scope: const DusunScope(role: 'desa'),
        mapPins: allPins,
        kecamatanCode: kecCode3,
        kecamatanName: resolvedKecName,
        kelurahanCode: kelCode3,
        desaName: resolvedDesaName,
        kantorDesaLat: kantorDesaLat,
        kantorDesaLng: kantorDesaLng,
        tahunPajak: effectiveTahun,
        masterDhkpFingerprint: masterFingerprint,
        dusunFingerprints: dusunFingerprints,
      );
      masterEntry = SplitDkhpExportEntry(
        isMaster: true,
        label: 'Master Desa $resolvedDesaName',
        file: masterFile,
        recordCount: records.length,
        blokList: allBlokSet,
      );
    }

    final dusunEntries = <SplitDkhpExportEntry>[];
    var assignedCount = 0;

    for (final d in dusuns) {
      final filteredRecords = dusunRecordsByNumber[d.number] ?? const [];
      final normalizedBloks = dusunBloksByNumber[d.number] ?? const [];
      final blokSet = normalizedBloks.toSet();
      assignedCount += filteredRecords.length;

      final filteredPins = allPins
          .where((p) => blokSet.contains(nopBlok(_digitsOnly(p.nop))))
          .toList();


      final safeDusunName = _sanitizeFileSegment(d.name);
      final dusunFileName =
          'DHKP_${safeDesa}_Dusun_${d.number}_${safeDusunName}_$safeTahun.dkhp';
      final dusunPath =
          '${outputDirectory.path}${Platform.pathSeparator}$dusunFileName';

      final dusunScope = DusunScope(
        role: 'dusun',
        dusunNumber: d.number,
        dusunName: d.name,
        allowedBloks: normalizedBloks,
      );

      final dusunFile = await packDkhp(
        outputPath: dusunPath,
        records: filteredRecords,
        baseRecords: filteredRecords,
        photosDir: photosDir,
        encrypt: true,
        includePhotos: includePhotos,
        deltaOnly: false,
        password: password,
        dusuns: dusuns,
        scope: dusunScope,
        mapPins: filteredPins,
        kecamatanCode: kecCode3,
        kecamatanName: resolvedKecName,
        kelurahanCode: kelCode3,
        desaName: resolvedDesaName,
        kantorDesaLat: kantorDesaLat,
        kantorDesaLng: kantorDesaLng,
        tahunPajak: effectiveTahun,
        masterDhkpFingerprint: masterFingerprint,
        dusunFingerprints: dusunFingerprints,
      );

      dusunEntries.add(
        SplitDkhpExportEntry(
          isMaster: false,
          dusunNumber: d.number,
          label: d.name,
          file: dusunFile,
          recordCount: filteredRecords.length,
          blokList: normalizedBloks,
        ),
      );
    }

    final unassignedBlokSet = <String>{};
    var unassignedCount = 0;
    for (final r in records) {
      final b = _digitsOnly(r.blok).padLeft(3, '0');
      if (!allAssignedBloks.contains(b)) {
        unassignedCount++;
        unassignedBlokSet.add(b);
      }
    }
    final unassignedBloks = unassignedBlokSet.toList()..sort();

    return SplitDkhpExportResult(
      outputDirectory: outputDirectory,
      masterEntry: masterEntry,
      dusunEntries: dusunEntries,
      totalRecords: records.length,
      assignedRecordCount: assignedCount,
      unassignedRecordCount: unassignedCount,
      unassignedBloks: unassignedBloks,
    );
  }
}

