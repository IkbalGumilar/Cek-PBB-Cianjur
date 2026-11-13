import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_storage.dart';
import '../blok_record.dart';
import '../dusun_data.dart';
import '../nop_helper.dart';
import 'map_models.dart';

/// Satu entri penandaan koordinat NOP hasil pemetaan GPS / pin manual / KML.
class MapPinEntry {
  final String nop;
  final double latitude;
  final double longitude;
  final double? ownerLatitude;
  final double? ownerLongitude;
  final String source;
  final int updatedAtMs;
  final String namaWajibPajak;
  final String alamatObjek;
  final String alamatWp;

  const MapPinEntry({
    required this.nop,
    required this.latitude,
    required this.longitude,
    this.ownerLatitude,
    this.ownerLongitude,
    this.source = 'manual',
    required this.updatedAtMs,
    this.namaWajibPajak = '',
    this.alamatObjek = '',
    this.alamatWp = '',
  });

  MapCoordinate get coordinate => MapCoordinate(latitude, longitude);

  MapCoordinate? get ownerCoordinate =>
      (ownerLatitude != null && ownerLongitude != null)
          ? MapCoordinate(ownerLatitude!, ownerLongitude!)
          : null;

  Map<String, dynamic> toJson() => {
        'nop': nop,
        'lat': latitude,
        'lng': longitude,
        if (ownerLatitude != null) 'ownerLat': ownerLatitude,
        if (ownerLongitude != null) 'ownerLng': ownerLongitude,
        'source': source,
        'updatedAtMs': updatedAtMs,
        if (namaWajibPajak.isNotEmpty) 'namaWp': namaWajibPajak,
        if (alamatObjek.isNotEmpty) 'alamatObjek': alamatObjek,
        if (alamatWp.isNotEmpty) 'alamatWp': alamatWp,
      };

  factory MapPinEntry.fromJson(Map<String, dynamic> json) {
    final rawNop = json['nop']?.toString() ?? '';
    return MapPinEntry(
      nop: normalizePinNop(rawNop),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      ownerLatitude: (json['ownerLat'] as num?)?.toDouble(),
      ownerLongitude: (json['ownerLng'] as num?)?.toDouble(),
      source: json['source']?.toString() ?? 'manual',
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      namaWajibPajak: json['namaWp']?.toString() ?? '',
      alamatObjek: json['alamatObjek']?.toString() ?? '',
      alamatWp: json['alamatWp']?.toString() ?? '',
    );
  }

  /// Menormalkan NOP 18 digit atau mempertahankan teks asli bila non-standar.
  static String normalizePinNop(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length == 18 ? digits : raw.trim();
  }

  /// Kunci bucket koordinat (presisi ~1,1 meter) untuk menggabungkan multi-NOP di titik yang sama.
  static String coordinateKey(double lat, double lng) {
    return '${(lat * 100000).round()}_${(lng * 100000).round()}';
  }
}

/// Penyimpan lokal permanen titik objek pajak (`map_pins.json`) + pengelompokan multi-NOP.
class MapPinStore {
  MapPinStore._();
  static final instance = MapPinStore._();

  static const String _fileName = 'map_pins.json';

  List<MapPinEntry>? _cache;
  String? _cachedFilePath;

  @visibleForTesting
  void resetForTesting() {
    _cache = null;
    _cachedFilePath = null;
  }

  Future<File> _getPinsFile() async {
    final dir = await AppStorage.getDataDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Memuat seluruh pin tersimpan dari disk.
  Future<List<MapPinEntry>> loadAll() async {
    final file = await _getPinsFile();
    if (_cache != null && _cachedFilePath == file.path) {
      return List.of(_cache!);
    }
    _cachedFilePath = file.path;

    if (!await file.exists()) {
      _cache = [];
      return [];
    }

    try {
      final raw = await file.readAsString();
      final entries = decodePinsJson(raw);
      _cache = entries;
      return List.of(entries);
    } catch (e) {
      debugPrint('Info: Gagal membaca map_pins.json: $e');
      _cache = [];
      return [];
    }
  }

  /// Menulis daftar pin ke disk.
  Future<void> saveAll(List<MapPinEntry> entries) async {
    final file = await _getPinsFile();
    _cachedFilePath = file.path;
    _cache = List.of(entries);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(encodePinsJson(entries));
  }

  /// Mengaitkan satu atau lebih NOP ke [coordinate].
  /// Jika NOP sudah pernah ditandai sebelumnya, koordinatnya dipindahkan/digabungkan
  /// ke [coordinate], sementara NOP lain yang sudah ada di titik ini tetap dipertahankan.
  Future<List<MapPinEntry>> assignNopsAtCoordinate({
    required MapCoordinate coordinate,
    required List<BlokRecord> selectedRecords,
    String source = 'manual',
    int? timestampMs,
  }) async {
    final existing = await loadAll();
    final now = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final byNop = <String, MapPinEntry>{
      for (final e in existing) e.nop: e,
    };

    for (final rec in selectedRecords) {
      final normNop = MapPinEntry.normalizePinNop(rec.nop);
      if (normNop.isEmpty) continue;
      final prev = byNop[normNop];
      byNop[normNop] = MapPinEntry(
        nop: normNop,
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        ownerLatitude: prev?.ownerLatitude,
        ownerLongitude: prev?.ownerLongitude,
        source: source,
        updatedAtMs: now,
        namaWajibPajak: rec.namaWajibPajak,
        alamatObjek: rec.alamatObjek,
        alamatWp: rec.alamatWp,
      );
    }

    final updated = byNop.values.toList();
    await saveAll(updated);
    return updated;
  }

  /// Menghapus satu NOP dari daftar pin (jika satu koordinat memiliki > 1 NOP,
  /// NOP lainnya di koordinat tersebut tetap aman).
  Future<List<MapPinEntry>> removeNop(String nop) async {
    final existing = await loadAll();
    final norm = MapPinEntry.normalizePinNop(nop);
    final updated = existing.where((e) => e.nop != norm).toList();
    await saveAll(updated);
    return updated;
  }

  /// Menghapus seluruh pin/NOP pada [coordinate] tertentu.
  Future<List<MapPinEntry>> removeByCoordinate(MapCoordinate coordinate) async {
    final existing = await loadAll();
    final targetKey =
        MapPinEntry.coordinateKey(coordinate.latitude, coordinate.longitude);
    final updated = existing
        .where(
          (e) =>
              MapPinEntry.coordinateKey(e.latitude, e.longitude) != targetKey,
        )
        .toList();
    await saveAll(updated);
    return updated;
  }

  /// Menggabungkan pin impor (dari `.dat`, `.dkhp`, atau `.kml`) tanpa menimpa pin lain yang tidak ada di berkas.
  /// Mengembalikan jumlah pin yang ditambahkan atau diperbarui.
  Future<int> mergeImportedPins(
    List<MapPinEntry> incoming, {
    bool onlyIfNewer = true,
  }) async {
    if (incoming.isEmpty) return 0;
    final existing = await loadAll();
    final byNop = <String, MapPinEntry>{
      for (final e in existing) e.nop: e,
    };

    int changedCount = 0;
    for (final item in incoming) {
      if (item.nop.isEmpty) continue;
      final prev = byNop[item.nop];
      if (prev == null) {
        byNop[item.nop] = item;
        changedCount++;
      } else if (!onlyIfNewer || item.updatedAtMs >= prev.updatedAtMs) {
        final sameCoord = prev.latitude == item.latitude &&
            prev.longitude == item.longitude &&
            prev.ownerLatitude == item.ownerLatitude &&
            prev.ownerLongitude == item.ownerLongitude;
        byNop[item.nop] = item;
        if (!sameCoord || item.updatedAtMs > prev.updatedAtMs) {
          changedCount++;
        }
      }
    }

    if (changedCount > 0 || byNop.length != existing.length) {
      await saveAll(byNop.values.toList());
    }
    return changedCount;
  }

  /// Menghapus seluruh pin tersimpan secara bersih.
  Future<void> clearAll() async {
    await saveAll([]);
  }

  /// Encode daftar pin menjadi string JSON.
  static String encodePinsJson(List<MapPinEntry> entries) {
    return jsonEncode([for (final e in entries) e.toJson()]);
  }

  /// Decode string JSON menjadi daftar [MapPinEntry].
  static List<MapPinEntry> decodePinsJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final result = <MapPinEntry>[];
    for (final item in decoded) {
      if (item is Map) {
        try {
          final entry = MapPinEntry.fromJson(Map<String, dynamic>.from(item));
          if (entry.nop.isNotEmpty) result.add(entry);
        } catch (_) {}
      }
    }
    return result;
  }

  /// Mengindeks catatan DHKP per NOP dengan memprioritaskan tahun pajak terbaru
  /// (penting saat DHKP lokal memuat multi-tahun seperti 2015-2026).
  static Map<String, BlokRecord> buildLatestRecordByNop(
    List<BlokRecord>? records,
  ) {
    final map = <String, BlokRecord>{};
    if (records == null) return map;
    for (final r in records) {
      final norm = MapPinEntry.normalizePinNop(r.nop);
      if (norm.isEmpty) continue;
      final prev = map[norm];
      if (prev == null) {
        map[norm] = r;
        continue;
      }
      final prevYr = int.tryParse(prev.tahunBayar.trim()) ?? 0;
      final curYr = int.tryParse(r.tahunBayar.trim()) ?? 0;
      if (curYr >= prevYr) {
        map[norm] = r;
      }
    }
    return map;
  }

  /// Mengelompokkan [pins] berdasarkan koordinat agar 1 koordinat bisa menampung 1 atau lebih NOP.
  static List<MapTaxDot> buildGroupedDots({
    required List<MapPinEntry> pins,
    List<BlokRecord>? dhkpRecords,
  }) {
    if (pins.isEmpty) return [];
    final latestByNop = buildLatestRecordByNop(dhkpRecords);

    // Pastikan 1 NOP hanya punya 1 entri terbaru sebelum dikelompokkan
    final dedupByNop = <String, MapPinEntry>{};
    for (final p in pins) {
      if (p.nop.isEmpty) continue;
      final prev = dedupByNop[p.nop];
      if (prev == null || p.updatedAtMs >= prev.updatedAtMs) {
        dedupByNop[p.nop] = p;
      }
    }

    final grouped = <String, List<MapPinEntry>>{};
    for (final entry in dedupByNop.values) {
      final key = MapPinEntry.coordinateKey(entry.latitude, entry.longitude);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    final dots = <MapTaxDot>[];
    for (final mapEntry in grouped.entries) {
      final entries = mapEntry.value..sort((a, b) => a.nop.compareTo(b.nop));
      final firstEntry = entries.first;

      final spptList = <BlokRecord>[];
      for (final e in entries) {
        final match = latestByNop[e.nop];
        if (match != null) {
          spptList.add(match);
        } else {
          spptList.add(
            BlokRecord(
              nop: e.nop,
              namaWajibPajak: e.namaWajibPajak.isNotEmpty
                  ? e.namaWajibPajak
                  : 'WP ${nopBlok(e.nop)}/${nopWilayah(e.nop)}',
              tahunBayar: '${DateTime.now().year}',
              tanggalBayar: '',
              jumlahPbb: '',
              statusBayar: 'Belum Bayar',
              alamatObjek: e.alamatObjek,
              alamatWp: e.alamatWp,
            ),
          );
        }
      }

      final dot = composeDotFromRecords(
        id: 'pin_${mapEntry.key}',
        coordinate: firstEntry.coordinate,
        ownerCoordinate: firstEntry.ownerCoordinate,
        spptList: spptList,
      );
      dots.add(dot);
    }

    dots.sort((a, b) => a.nop.compareTo(b.nop));
    return dots;
  }

  /// Menyusun satu [MapTaxDot] dari daftar [BlokRecord] pada satu koordinat.
  static MapTaxDot composeDotFromRecords({
    required String id,
    required MapCoordinate coordinate,
    MapCoordinate? ownerCoordinate,
    required List<BlokRecord> spptList,
  }) {
    final primary = spptList.first;
    final paidCount = spptList.where((r) => r.isPaid).length;
    final allFasum = spptList.every((r) => r.isTargetPemda);

    final MapDotStatus dotStatus;
    if (spptList.length == 1) {
      dotStatus = primary.isTargetPemda
          ? MapDotStatus.fasum
          : (primary.isPaid ? MapDotStatus.lunas : MapDotStatus.belumLunas);
    } else if (paidCount == spptList.length) {
      dotStatus = MapDotStatus.lunas;
    } else if (paidCount > 0) {
      dotStatus = MapDotStatus.sebagian;
    } else if (allFasum) {
      dotStatus = MapDotStatus.fasum;
    } else {
      dotStatus = MapDotStatus.belumLunas;
    }

    final blok = nopBlok(primary.nop).isNotEmpty ? nopBlok(primary.nop) : '001';
    final urut =
        nopWilayah(primary.nop).isNotEmpty ? nopWilayah(primary.nop) : '0000';
    final dusunNum = DusunData.instance.byBlok(blok)?.number ?? 1;

    final totalPbb = spptList.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
    final jumlahPbbLabel = spptList.length == 1
        ? primary.jumlahPbb
        : (totalPbb > 0 ? 'Rp ${formatRibuan(totalPbb)}' : primary.jumlahPbb);

    final statusLabel = spptList.length == 1
        ? primary.statusBayar
        : '$paidCount/${spptList.length} Lunas';

    final displayName = spptList.length == 1
        ? primary.namaWajibPajak
        : '${primary.namaWajibPajak} (+${spptList.length - 1} NOP)';

    return MapTaxDot(
      id: id,
      nop: primary.nop,
      namaWajibPajak: displayName,
      blok: blok,
      nomorUrut: urut,
      dusunNumber: dusunNum,
      coordinate: coordinate,
      ownerCoordinate: ownerCoordinate,
      alamatObjek: primary.alamatObjek,
      alamatWp: primary.alamatWp,
      rtObjek: primary.rtObjek,
      jumlahPbb: jumlahPbbLabel,
      statusBayar: statusLabel,
      isTargetPemda: spptList.any((r) => r.isTargetPemda),
      status: dotStatus,
      spptList: spptList,
    );
  }

  /// Mengonversi daftar [MapTaxDot] (misal hasil parse KML) menjadi [MapPinEntry] untuk disimpan/digabung.
  static List<MapPinEntry> entriesFromDots(
    List<MapTaxDot> dots, {
    String source = 'kml',
    int? timestampMs,
  }) {
    final now = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final result = <MapPinEntry>[];
    for (final d in dots) {
      if (d.spptList.isNotEmpty) {
        for (final rec in d.spptList) {
          final norm = MapPinEntry.normalizePinNop(rec.nop);
          if (norm.isEmpty) continue;
          result.add(
            MapPinEntry(
              nop: norm,
              latitude: d.coordinate.latitude,
              longitude: d.coordinate.longitude,
              ownerLatitude: d.ownerCoordinate?.latitude,
              ownerLongitude: d.ownerCoordinate?.longitude,
              source: source,
              updatedAtMs: now,
              namaWajibPajak: rec.namaWajibPajak,
              alamatObjek: rec.alamatObjek,
              alamatWp: rec.alamatWp,
            ),
          );
        }
      } else if (d.nop.trim().isNotEmpty) {
        result.add(
          MapPinEntry(
            nop: MapPinEntry.normalizePinNop(d.nop),
            latitude: d.coordinate.latitude,
            longitude: d.coordinate.longitude,
            ownerLatitude: d.ownerCoordinate?.latitude,
            ownerLongitude: d.ownerCoordinate?.longitude,
            source: source,
            updatedAtMs: now,
            namaWajibPajak: d.namaWajibPajak,
            alamatObjek: d.alamatObjek,
            alamatWp: d.alamatWp,
          ),
        );
      }
    }
    return result;
  }
}
