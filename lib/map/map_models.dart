import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../blok_record.dart';

/// Representasi koordinat geografis (Latitude, Longitude) pada peta objek pajak.
class MapCoordinate {
  final double latitude;
  final double longitude;

  const MapCoordinate(this.latitude, this.longitude);

  /// Menghitung jarak perkiraan (Euclidean sederhana dalam derajat).
  double distanceTo(MapCoordinate other) {
    final dLat = latitude - other.latitude;
    final dLng = longitude - other.longitude;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// Interpolasi linear antara dua koordinat (untuk animasi kamera/sorotan).
  static MapCoordinate lerp(MapCoordinate a, MapCoordinate b, double t) {
    return MapCoordinate(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  Offset toOffset() => Offset(longitude, latitude);

  LatLng toLatLng() => LatLng(latitude, longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapCoordinate &&
          (latitude - other.latitude).abs() < 0.000001 &&
          (longitude - other.longitude).abs() < 0.000001;

  @override
  int get hashCode =>
      Object.hash((latitude * 100000).round(), (longitude * 100000).round());

  @override
  String toString() => '($latitude, $longitude)';
}

/// Batas wilayah geografis (*bounding box*) untuk mengatur fokus kamera peta.
class MapBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const MapBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  MapCoordinate get center =>
      MapCoordinate((minLat + maxLat) / 2, (minLng + maxLng) / 2);

  double get width => (maxLng - minLng).abs();
  double get height => (maxLat - minLat).abs();

  bool contains(MapCoordinate c) {
    return c.latitude >= minLat &&
        c.latitude <= maxLat &&
        c.longitude >= minLng &&
        c.longitude <= maxLng;
  }

  /// Memberikan padding margin pada batas wilayah.
  MapBounds pad(double factor) {
    final latPadding = height * factor;
    final lngPadding = width * factor;
    return MapBounds(
      minLat: minLat - latPadding,
      maxLat: maxLat + latPadding,
      minLng: minLng - lngPadding,
      maxLng: maxLng + lngPadding,
    );
  }

  /// Membuat batas dari kumpulan koordinat.
  static MapBounds fromCoordinates(List<MapCoordinate> coords) {
    if (coords.isEmpty) {
      // Default Desa Bobojong, Kec. Mande, Cianjur
      return const MapBounds(
        minLat: -6.770000,
        maxLat: -6.735000,
        minLng: 107.240000,
        maxLng: 107.280000,
      );
    }
    double minLat = coords.first.latitude;
    double maxLat = coords.first.latitude;
    double minLng = coords.first.longitude;
    double maxLng = coords.first.longitude;

    for (final c in coords) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    // Pastikan tidak nol
    if ((maxLat - minLat).abs() < 0.0001) {
      minLat -= 0.002;
      maxLat += 0.002;
    }
    if ((maxLng - minLng).abs() < 0.0001) {
      minLng -= 0.002;
      maxLng += 0.002;
    }

    return MapBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }
}

/// Status visual titik objek pajak pada peta.
enum MapDotStatus {
  /// 🟢 Lunas: Seluruh SPPT pada titik ini sudah lunas.
  lunas,

  /// 🔴 Belum Lunas: Objek pajak belum lunas.
  belumLunas,

  /// 🟡 Sebagian Lunas: Terdapat >= 2 SPPT pada titik ini dan baru lunas sebagian.
  sebagian,

  /// ⚫ Fasum / Target Pemda: Fasilitas umum atau target Pemda (tanpa nomor).
  fasum,
}

extension MapDotStatusExt on MapDotStatus {
  Color get color {
    switch (this) {
      case MapDotStatus.lunas:
        return const Color(0xFF2ECC71); // Hijau Lunas
      case MapDotStatus.belumLunas:
        return const Color(0xFFE74C3C); // Merah Belum Bayar
      case MapDotStatus.sebagian:
        return const Color(0xFFF1C40F); // Kuning Sebagian
      case MapDotStatus.fasum:
        return const Color(0xFF34495E); // Abu Gelap Fasum
    }
  }

  String get label {
    switch (this) {
      case MapDotStatus.lunas:
        return 'Lunas';
      case MapDotStatus.belumLunas:
        return 'Belum Bayar';
      case MapDotStatus.sebagian:
        return 'Sebagian Lunas';
      case MapDotStatus.fasum:
        return 'Fasum / Pemda';
    }
  }

  IconData get icon {
    switch (this) {
      case MapDotStatus.lunas:
        return Icons.check_circle_rounded;
      case MapDotStatus.belumLunas:
        return Icons.error_rounded;
      case MapDotStatus.sebagian:
        return Icons.pie_chart_rounded;
      case MapDotStatus.fasum:
        return Icons.account_balance_rounded;
    }
  }
}

/// Representasi satu titik objek pajak (Dot) di peta wilayah.
class MapTaxDot {
  final String id;
  final String nop;
  final String namaWajibPajak;
  final String blok;
  final String nomorUrut;
  final int dusunNumber;
  final MapCoordinate coordinate;

  /// Koordinat rumah pemilik jika berbeda dengan lokasi objek pajak (misal kebun/sawah).
  final MapCoordinate? ownerCoordinate;

  final String alamatObjek;
  final String alamatWp;
  final String rtObjek;
  final String jumlahPbb;
  final String statusBayar;
  final bool isTargetPemda;
  final MapDotStatus status;

  /// Kumpulan SPPT pada koordinat ini (bisa multi-SPPT).
  final List<BlokRecord> spptList;

  const MapTaxDot({
    required this.id,
    required this.nop,
    required this.namaWajibPajak,
    required this.blok,
    required this.nomorUrut,
    required this.dusunNumber,
    required this.coordinate,
    this.ownerCoordinate,
    this.alamatObjek = '',
    this.alamatWp = '',
    this.rtObjek = '',
    this.jumlahPbb = '',
    this.statusBayar = '',
    this.isTargetPemda = false,
    required this.status,
    this.spptList = const [],
  });

  /// Apakah alamat WP sama dengan alamat objek pajak (rumah tempat tinggal sendiri)?
  bool get isOwnerAddressSame {
    if (ownerCoordinate != null && ownerCoordinate != coordinate) {
      return false;
    }
    final cleanObj = alamatObjek.trim().toUpperCase().replaceAll(' ', '');
    final cleanWp = alamatWp.trim().toUpperCase().replaceAll(' ', '');
    if (cleanObj.isNotEmpty && cleanWp.isNotEmpty) {
      return cleanObj == cleanWp;
    }
    return true;
  }

  /// Apakah memiliki koordinat pemilik terpisah untuk aksi "Sorot Alamat Pemilik"?
  bool get hasSeparateOwnerLocation =>
      ownerCoordinate != null && ownerCoordinate != coordinate;
}

/// Wilayah kedusunan dan daftar blok.
class MapDusunZone {
  final int dusunNumber;
  final String name;
  final List<String> bloks;
  final MapBounds bounds;
  final List<MapCoordinate> boundaryPolygon;

  const MapDusunZone({
    required this.dusunNumber,
    required this.name,
    required this.bloks,
    required this.bounds,
    this.boundaryPolygon = const [],
  });
}
