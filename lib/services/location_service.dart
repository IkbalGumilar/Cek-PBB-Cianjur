import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../cianjur_wilayah_data.dart';

/// Ringkasan status izin yang dibutuhkan aplikasi.
class AppPermissionsStatus {
  final bool notificationGranted;
  final bool storageGranted;
  final bool locationGranted;

  const AppPermissionsStatus({
    required this.notificationGranted,
    required this.storageGranted,
    required this.locationGranted,
  });

  bool get allGranted =>
      notificationGranted && storageGranted && locationGranted;
}

/// Hasil deteksi lokasi wilayah kerja (Kecamatan & Desa di Kabupaten Cianjur).
class WilayahDetectionResult {
  final String kecCode;
  final String kecName;
  final String desaCode;
  final String desaName;
  final double latitude;
  final double longitude;
  final String sourceDescription;

  const WilayahDetectionResult({
    required this.kecCode,
    required this.kecName,
    required this.desaCode,
    required this.desaName,
    required this.latitude,
    required this.longitude,
    required this.sourceDescription,
  });
}

/// Hasil pembacaan koordinat GPS lapangan beserta estimasi akurasi.
class FieldLocationResult {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final bool isFallbackIp;
  final String sourceDescription;

  const FieldLocationResult({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.isFallbackIp = false,
    required this.sourceDescription,
  });
}

/// Titik koordinat acuan perkiraan pusat masing-masing 32 Kecamatan di Kabupaten Cianjur
/// sesuai kode resmi Bapenda pada [cianjurWilayahCatalog].
const Map<String, ({double lat, double lng})> kecamatanCentroids = {
  '010': (lat: -7.3486, lng: 106.9142), // AGRABINTA
  '060': (lat: -6.8523, lng: 107.2514), // BOJONGPICUNG
  '150': (lat: -7.0253, lng: 107.1354), // CAMPAKA
  '250': (lat: -7.0628, lng: 107.1189), // CAMPAKAMULYA
  '011': (lat: -6.8219, lng: 107.1398), // CIANJUR
  '030': (lat: -6.9015, lng: 107.1392), // CIBEBER
  '201': (lat: -7.2185, lng: 107.0392), // CIBINONG
  '230': (lat: -7.4984, lng: 107.3421), // CIDAUN
  '290': (lat: -7.1842, lng: 106.9854), // CIJATI
  '260': (lat: -7.3489, lng: 107.2285), // CIKADU
  '120': (lat: -6.6784, lng: 107.1643), // CIKALONGKULON
  '040': (lat: -6.8574, lng: 107.1685), // CILAKU
  '280': (lat: -6.7452, lng: 107.0421), // CIPANAS
  '050': (lat: -6.8124, lng: 107.2412), // CIRANJANG
  '330': (lat: -6.8045, lng: 107.0854), // CUGENANG
  '310': (lat: -6.8854, lng: 107.0821), // GEKBRONG
  '300': (lat: -6.8321, lng: 107.2842), // HAURWANGI
  '180': (lat: -7.1425, lng: 106.9742), // KADUPANDAK
  '070': (lat: -6.8125, lng: 107.1852), // KARANGTENGAH
  '350': (lat: -7.3821, lng: 107.0542), // LELES
  '200': (lat: -6.7584, lng: 107.2341), // MANDE
  '270': (lat: -7.3854, lng: 107.3985), // NARINGGUL
  '140': (lat: -6.7582, lng: 107.0712), // PACET
  '190': (lat: -7.1845, lng: 107.1854), // PAGELARAN
  '320': (lat: -7.1852, lng: 107.2841), // PASIRKUDA
  '210': (lat: -7.4521, lng: 107.2045), // SINDANGBARANG
  '130': (lat: -6.8642, lng: 107.2085), // SUKALUYU
  '160': (lat: -7.0842, lng: 107.1542), // SUKANAGARA
  '340': (lat: -6.7142, lng: 107.0842), // SUKARESMI
  '170': (lat: -6.9984, lng: 107.0421), // TAKOKAK
  '240': (lat: -7.2452, lng: 107.1084), // TANGGEUNG
  '020': (lat: -6.8542, lng: 107.1085), // WARUNGKONDANG
};

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Meminta seluruh izin aplikasi (Notifikasi, Penyimpanan, dan Lokasi).
  Future<AppPermissionsStatus> requestAllAppPermissions() async {
    bool notifOk = false;
    bool storageOk = false;
    bool locationOk = false;

    // 1. Izin Notifikasi
    try {
      final status = await Permission.notification.request();
      notifOk = status.isGranted;
    } catch (e) {
      debugPrint('Permission notification request error: $e');
      notifOk =
          true; // Anggap diizinkan pada platform desktop jika tidak didukung
    }

    // 2. Izin Penyimpanan
    try {
      if (Platform.isAndroid) {
        final storageStatus = await Permission.storage.request();
        final photosStatus = await Permission.photos.request();
        storageOk = storageStatus.isGranted || photosStatus.isGranted;
      } else {
        storageOk = true;
      }
    } catch (e) {
      debugPrint('Permission storage request error: $e');
      storageOk = true;
    }

    // 3. Izin Lokasi
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        LocationPermission locPerm = await Geolocator.checkPermission();
        if (locPerm == LocationPermission.denied) {
          locPerm = await Geolocator.requestPermission();
        }
        locationOk =
            locPerm == LocationPermission.whileInUse ||
            locPerm == LocationPermission.always;
      } catch (e) {
        debugPrint('Geolocator permission request error: $e');
        locationOk = false;
      }
    } else {
      // Pada Desktop (Windows, Linux, macOS), tidak ada dialog izin mobile;
      // sistem menggunakan IP Geolocation / Jaringan sehingga otomatis diizinkan.
      locationOk = true;
    }

    return AppPermissionsStatus(
      notificationGranted: notifOk,
      storageGranted: storageOk,
      locationGranted: locationOk,
    );
  }

  /// Cek status izin saat ini tanpa menampilkan dialog sistem.
  Future<AppPermissionsStatus> checkPermissionsStatus() async {
    bool notifOk = false;
    bool storageOk = false;
    bool locationOk = false;

    try {
      notifOk = await Permission.notification.isGranted;
    } catch (_) {
      notifOk = true;
    }

    try {
      if (Platform.isAndroid) {
        storageOk =
            await Permission.storage.isGranted ||
            await Permission.photos.isGranted;
      } else {
        storageOk = true;
      }
    } catch (_) {
      storageOk = true;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final locPerm = await Geolocator.checkPermission();
        locationOk =
            locPerm == LocationPermission.whileInUse ||
            locPerm == LocationPermission.always;
      } catch (_) {
        locationOk = false;
      }
    } else {
      locationOk = true;
    }

    return AppPermissionsStatus(
      notificationGranted: notifOk,
      storageGranted: storageOk,
      locationGranted: locationOk,
    );
  }

  Future<bool> _ensureMobileLocationPermission() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return true;
    try {
      LocationPermission locPerm = await Geolocator.checkPermission();
      if (locPerm == LocationPermission.denied) {
        locPerm = await Geolocator.requestPermission();
      }
      return locPerm == LocationPermission.whileInUse ||
          locPerm == LocationPermission.always;
    } catch (e) {
      debugPrint('Geolocator mobile permission error: $e');
      return false;
    }
  }

  Future<({double lat, double lng})?> _fetchIpFallbackLocation() async {
    try {
      final ipRes = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 4));
      if (ipRes.statusCode == 200) {
        final data = jsonDecode(ipRes.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final lat = (data['latitude'] as num?)?.toDouble();
          final lng = (data['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) return (lat: lat, lng: lng);
        }
      }
    } catch (e) {
      debugPrint('Fallback ipwho.is error: $e');
    }

    try {
      final ipRes = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));
      if (ipRes.statusCode == 200) {
        final data = jsonDecode(ipRes.body) as Map<String, dynamic>;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) return (lat: lat, lng: lng);
      }
    } catch (e) {
      debugPrint('Fallback ipapi.co error: $e');
    }
    return null;
  }

  /// Membaca koordinat GPS lapangan akurat untuk penandaan objek pajak di peta.
  /// Mengembalikan koordinat + akurasi meter (atau fallback jaringan jika sensor GPS tidak tersedia).
  Future<FieldLocationResult?> getCurrentFieldLocation() async {
    final permOk = await _ensureMobileLocationPermission();
    if (permOk) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled || !(Platform.isAndroid || Platform.isIOS)) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              timeLimit: Duration(seconds: 10),
            ),
          );
          return FieldLocationResult(
            latitude: pos.latitude,
            longitude: pos.longitude,
            accuracyMeters: pos.accuracy > 0 ? pos.accuracy : null,
            isFallbackIp: false,
            sourceDescription: 'GPS Perangkat',
          );
        }
      } catch (e) {
        debugPrint('Geolocator best accuracy timeout/error: $e');
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            return FieldLocationResult(
              latitude: lastPos.latitude,
              longitude: lastPos.longitude,
              accuracyMeters: lastPos.accuracy > 0 ? lastPos.accuracy : null,
              isFallbackIp: false,
              sourceDescription: 'GPS Perangkat',
            );
          }
        } catch (_) {}
      }
    }

    final ipLoc = await _fetchIpFallbackLocation();
    if (ipLoc != null) {
      return FieldLocationResult(
        latitude: ipLoc.lat,
        longitude: ipLoc.lng,
        isFallbackIp: true,
        sourceDescription: 'Perkiraan Jaringan Internet',
      );
    }
    return null;
  }

  /// Mendeteksi posisi GPS/Jaringan saat ini dan mencocokkannya ke Kecamatan & Desa di Cianjur.
  /// Bekerja optimal di Android (GPS perangkat) maupun Desktop Windows/Linux (IP Geolocation & Reverse Geocoding).
  Future<WilayahDetectionResult?> detectCurrentWilayah() async {
    // 1. Cek & Minta Izin Lokasi jika pada platform mobile (Android / iOS)
    final permOk = await _ensureMobileLocationPermission();
    if (!permOk) {
      debugPrint('Izin GPS mobile ditolak, mencoba deteksi berbasis IP...');
    }

    double? lat;
    double? lng;
    String source = 'GPS Perangkat';

    // 2. Ambil Posisi GPS via Geolocator (jika sensor atau sistem mendukung)
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
      source = 'GPS Perangkat';
    } catch (e) {
      debugPrint(
        'Geolocator GPS tidak tersedia/timeout: $e. Menggunakan IP Geolocation...',
      );
    }

    // 3. Fallback IP Geolocation jika GPS tidak tersedia (misal di PC Linux/Windows tanpa sensor GPS)
    if (lat == null || lng == null) {
      final ipLoc = await _fetchIpFallbackLocation();
      if (ipLoc != null) {
        lat = ipLoc.lat;
        lng = ipLoc.lng;
        source = 'Perkiraan Jaringan Internet';
      }
    }

    if (lat == null || lng == null) {
      return null;
    }

    // 4. Reverse Geocoding via OpenStreetMap Nominatim
    String? matchedKecName;
    String? matchedDesaName;

    try {
      final osmUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=14&addressdetails=1',
      );
      final res = await http
          .get(
            osmUrl,
            headers: {'User-Agent': 'CekPBBApp/1.0 (id.cianjur.pbb)'},
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};

        final village =
            address['village']?.toString() ??
            address['suburb']?.toString() ??
            address['neighbourhood']?.toString() ??
            address['hamlet']?.toString();
        final district =
            address['city_district']?.toString() ??
            address['subdistrict']?.toString() ??
            address['municipality']?.toString();

        if (district != null && district.isNotEmpty) {
          matchedKecName = district.toUpperCase();
        }
        if (village != null && village.isNotEmpty) {
          matchedDesaName = village.toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('OSM Nominatim error: $e');
    }

    // 5. Cocokkan ke Katalog 32 Kecamatan di Kabupaten Cianjur
    KecamatanOption? targetKec;
    DesaOption? targetDesa;

    // A. Cocokkan nama Kecamatan jika terdeteksi dari reverse geocoding
    if (matchedKecName != null) {
      targetKec = _matchByName(
        cianjurWilayahCatalog,
        matchedKecName,
        (kec) => kec.name,
      );
    }

    // B. Jika nama kecamatan belum dapat tapi nama desa/kelurahan ada, cari kecamatan yang memuat desa tersebut
    if (targetKec == null && matchedDesaName != null) {
      final desaName = matchedDesaName;
      for (final kec in cianjurWilayahCatalog) {
        if (kec.desaList.any((d) => d.name == desaName)) {
          targetKec = kec;
          break;
        }
      }
      targetKec ??= cianjurWilayahCatalog.cast<KecamatanOption?>().firstWhere(
        (kec) =>
            _matchByName(kec!.desaList, desaName, (d) => d.name) != null,
        orElse: () => null,
      );
    }

    // C. Jika belum ketemu atau nama tidak cocok langsung, gunakan jarak centroid terdekat
    if (targetKec == null) {
      double minDistance = double.infinity;
      String? nearestKecCode;

      kecamatanCentroids.forEach((code, centroid) {
        final dLat = lat! - centroid.lat;
        final dLng = lng! - centroid.lng;
        final dist = math.sqrt(dLat * dLat + dLng * dLng);
        if (dist < minDistance) {
          minDistance = dist;
          nearestKecCode = code;
        }
      });

      if (nearestKecCode != null) {
        targetKec = findKecamatanByCode(nearestKecCode!);
      }
    }

    // Default jika di luar jangkauan: Mande (200)
    targetKec ??= findKecamatanByCode('200');

    if (targetKec != null) {
      if (matchedDesaName != null) {
        targetDesa = _matchByName(
          targetKec.desaList,
          matchedDesaName,
          (d) => d.name,
        );
      }
      // Jika tidak ada nama desa yang cocok persis, pilih desa pertama di kecamatan
      targetDesa ??= targetKec.desaList.isNotEmpty
          ? targetKec.desaList.first
          : null;
    }

    if (targetKec == null || targetDesa == null) {
      return null;
    }

    return WilayahDetectionResult(
      kecCode: targetKec.code,
      kecName: targetKec.name,
      desaCode: targetDesa.code,
      desaName: targetDesa.name,
      latitude: lat,
      longitude: lng,
      sourceDescription: source,
    );
  }

  static T? _matchByName<T>(
    Iterable<T> items,
    String query,
    String Function(T) getName,
  ) {
    for (final item in items) {
      if (getName(item) == query) return item;
    }
    final sorted = items.toList()
      ..sort((a, b) => getName(b).length.compareTo(getName(a).length));
    for (final item in sorted) {
      final name = getName(item);
      if (query.contains(name) || name.contains(query)) return item;
    }
    return null;
  }
}
