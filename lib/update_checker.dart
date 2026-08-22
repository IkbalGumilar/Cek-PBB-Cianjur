import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_info.dart';

class UpdateCheckError implements Exception {
  final String message;
  const UpdateCheckError(this.message);
  @override
  String toString() => message;
}

/// Cek rilis terbaru lewat GitHub Releases API repo publik aplikasi ini.
/// Rilis GitHub jadi satu-satunya sumber pembaruan: tag versi dibaca dari
/// `tag_name`, catatan pembaruan dari `body`, dan berkas APK dari asset
/// rilis yang namanya berakhiran ".apk".
class UpdateChecker {
  static const _githubOwner = 'IkbalGumilar';
  static const _githubRepo = 'Cek-PBB-Cianjur';
  static const _lastCheckedKey = 'update_last_checked_at';
  static const _autoCheckInterval = Duration(hours: 24);

  /// Halaman rilis GitHub — dipakai juga oleh "Bagikan Aplikasi" di
  /// Windows/Linux (bagikan link, bukan berkas biner langsung seperti APK).
  static const releasesPageUrl =
      'https://github.com/$_githubOwner/$_githubRepo/releases/latest';

  /// Dipanggil otomatis tiap aplikasi dibuka. Tidak kirim request kalau baru
  /// saja dicek dalam [_autoCheckInterval] terakhir (termasuk lewat
  /// pengecekan manual), supaya tidak membebani API GitHub tiap kali
  /// aplikasi dibuka.
  static Future<UpdateInfo?> checkForUpdateIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckedMs = prefs.getInt(_lastCheckedKey);
    if (lastCheckedMs != null) {
      final lastChecked = DateTime.fromMillisecondsSinceEpoch(lastCheckedMs);
      if (DateTime.now().difference(lastChecked) < _autoCheckInterval)
        return null;
    }
    try {
      return await checkForUpdate();
    } on UpdateCheckError {
      return null;
    }
  }

  /// Cek ke GitHub sekarang juga, dipakai tombol "Periksa Pembaruan" manual.
  static Future<UpdateInfo?> checkForUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckedKey, DateTime.now().millisecondsSinceEpoch);

    final currentVersion = (await PackageInfo.fromPlatform()).version;

    final Response<Map<String, dynamic>> response;
    try {
      response = await Dio().get<Map<String, dynamic>>(
        'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Accept': 'application/vnd.github+json'},
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null; // belum pernah rilis
      throw UpdateCheckError(
        'Gagal memeriksa pembaruan: ${e.message ?? e.type}',
      );
    }

    final data = response.data;
    if (data == null) return null;

    final tagName = data['tag_name'] as String? ?? '';
    final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
    if (latestVersion.isEmpty || !_isNewer(latestVersion, currentVersion))
      return null;

    final assets = ((data['assets'] as List?) ?? const [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final asset = _findAssetForPlatform(assets);
    if (asset == null)
      return null; // rilis ada tapi belum dilampiri berkas untuk platform ini

    return UpdateInfo(
      version: latestVersion,
      changelog: (data['body'] as String? ?? '').trim(),
      apkDownloadUrl: asset['browser_download_url'] as String,
      apkSize: asset['size'] as int? ?? 0,
      publishedAt:
          DateTime.tryParse(data['published_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Cari asset rilis GitHub yang cocok untuk platform yang sedang berjalan.
  /// Android selalu cari `.apk` (satu-satunya format instal Android). Di
  /// Windows/Linux belum ada konvensi baku, jadi dicocokkan lewat kata kunci
  /// nama platform di nama berkas rilisnya (mis. "CekPBBCianjur-windows.zip",
  /// "CekPBBCianjur-linux.tar.gz") — sesuaikan nama berkas rilis di GitHub
  /// dengan kata kunci ini supaya terdeteksi.
  static Map<String, dynamic>? _findAssetForPlatform(
    List<Map<String, dynamic>> assets,
  ) {
    bool matches(Map<String, dynamic> asset, bool Function(String name) test) {
      return test((asset['name'] as String? ?? '').toLowerCase());
    }

    if (Platform.isAndroid) {
      for (final asset in assets) {
        if (matches(asset, (name) => name.endsWith('.apk'))) return asset;
      }
    } else if (Platform.isWindows) {
      for (final asset in assets) {
        if (matches(
          asset,
          (name) =>
              name.contains('windows') ||
              name.endsWith('.exe') ||
              name.endsWith('.msix'),
        )) {
          return asset;
        }
      }
    } else if (Platform.isLinux) {
      for (final asset in assets) {
        if (matches(
          asset,
          (name) =>
              name.contains('linux') ||
              name.endsWith('.appimage') ||
              name.endsWith('.tar.gz') ||
              name.endsWith('.deb'),
        )) {
          return asset;
        }
      }
    }
    return null;
  }

  static bool _isNewer(String latest, String current) {
    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    for (var i = 0; i < 3; i++) {
      if (l[i] != c[i]) return l[i] > c[i];
    }
    return false;
  }

  static List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return List.generate(
      3,
      (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    );
  }
}
