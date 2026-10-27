import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apk_installer.dart';
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
      if (DateTime.now().difference(lastChecked) < _autoCheckInterval) {
        return null;
      }
    }
    try {
      return await checkForUpdate();
    } on UpdateCheckError {
      return null;
    }
  }

  /// Cek ke GitHub sekarang juga, dipakai tombol "Periksa Pembaruan" manual.
  static Future<UpdateInfo?> checkForUpdate({
    bool? includePrereleases,
    String? currentVersionOverride,
    List<Map<String, dynamic>>? releasesOverride,
    List<String>? supportedAbisOverride,
    bool? isAndroidOverride,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckedKey, DateTime.now().millisecondsSinceEpoch);

    final currentVersion = currentVersionOverride ??
        (await PackageInfo.fromPlatform()).version;
    final allowPrerelease = includePrereleases ??
        (currentVersion.contains('alpha') || currentVersion.contains('beta'));

    final List<dynamic> rawReleases;
    if (releasesOverride != null) {
      rawReleases = releasesOverride;
    } else {
      final Response<List<dynamic>> response;
      try {
        response = await Dio().get<List<dynamic>>(
          'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases',
          queryParameters: {'per_page': 100},
          options: Options(
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {'Accept': 'application/vnd.github+json'},
          ),
        );
        rawReleases = response.data ?? const [];
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) return null; // belum pernah rilis
        throw UpdateCheckError(
          'Gagal memeriksa pembaruan: ${e.message ?? e.type}',
        );
      }
    }

    final releases = rawReleases
        .whereType<Map<String, dynamic>>()
        .where((r) => isEligibleRelease(r, allowPrerelease: allowPrerelease))
        .toList();
    if (releases.isEmpty) return null;

    var data = releases.first;
    for (final release in releases.skip(1)) {
      final releaseVersion = _versionFromTag(release['tag_name']);
      final selectedVersion = _versionFromTag(data['tag_name']);
      if (releaseVersion != null &&
          (selectedVersion == null ||
              isNewerVersion(releaseVersion, selectedVersion))) {
        data = release;
      }
    }

    final latestVersion = _versionFromTag(data['tag_name']) ?? '';
    if (latestVersion.isEmpty ||
        !isNewerVersion(latestVersion, currentVersion)) {
      return null;
    }

    final assets = ((data['assets'] as List?) ?? const [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    final supportedAbis = supportedAbisOverride ??
        (isAndroid ? await ApkInstaller.getSupportedAbis() : null);

    final asset = findAssetForPlatform(
      assets,
      supportedAbis: supportedAbis,
      isAndroidOverride: isAndroidOverride,
    );
    if (asset == null) {
      return null; // rilis ada tapi belum dilampiri berkas untuk platform ini
    }

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
  /// Android: dicocokkan dengan arsitektur CPU (ABI) perangkat (arm64-v8a, armeabi-v7a, x86_64).
  /// Windows/Linux: dicocokkan lewat ekstensi berkas atau kata kunci platform.
  static Map<String, dynamic>? findAssetForPlatform(
    List<Map<String, dynamic>> assets, {
    List<String>? supportedAbis,
    bool? isAndroidOverride,
    bool? isWindowsOverride,
    bool? isLinuxOverride,
  }) {
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    final isWindows = isWindowsOverride ?? Platform.isWindows;
    final isLinux = isLinuxOverride ?? Platform.isLinux;

    bool matches(Map<String, dynamic> asset, bool Function(String name) test) {
      return test((asset['name'] as String? ?? '').toLowerCase());
    }

    if (isAndroid) {
      final apkAssets = assets
          .where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'))
          .toList();
      if (apkAssets.isEmpty) return null;
      if (apkAssets.length == 1) return apkAssets.first;

      // Urutan prioritas ABI perangkat:
      // Di Android nyata, supportedAbis dibaca dari Build.SUPPORTED_ABIS via MethodChannel.
      // Jika kosong (fallback), default prioritas ARM64 -> ARMv7 -> universal -> x86_64.
      final preferredAbis = (supportedAbis != null && supportedAbis.isNotEmpty)
          ? supportedAbis
          : const ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

      for (final abi in preferredAbis) {
        final cleanAbi = abi.toLowerCase();
        for (final asset in apkAssets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.contains(cleanAbi)) return asset;
          if (cleanAbi == 'arm64-v8a' && (name.contains('arm64') || name.contains('v8a'))) {
            return asset;
          }
          if (cleanAbi == 'armeabi-v7a' && (name.contains('armeabi') || name.contains('v7a'))) {
            return asset;
          }
          if (cleanAbi == 'x86_64' && name.contains('x86_64')) {
            return asset;
          }
        }
      }

      // Jika tidak ada nama berkas yang mencantumkan ABI di atas, cari berkas APK universal
      for (final asset in apkAssets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final hasSpecificAbi = name.contains('arm64') ||
            name.contains('v8a') ||
            name.contains('armeabi') ||
            name.contains('v7a') ||
            name.contains('x86');
        if (!hasSpecificAbi || name.contains('universal')) {
          return asset;
        }
      }

      return apkAssets.first;
    } else if (isWindows) {
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
    } else if (isLinux) {
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


  /// Memeriksa apakah rilis memenuhi syarat untuk pengguna saat ini.
  /// Pengguna versi beta/alpha diizinkan menerima pembaruan beta/alpha yang lebih baru.
  /// Pengguna rilis stabil hanya menerima pembaruan rilis stabil resmi.
  static bool isEligibleRelease(
    Map<String, dynamic> release, {
    required bool allowPrerelease,
  }) {
    if (release['draft'] == true) return false;
    final version = _versionFromTag(release['tag_name']);
    if (version == null) return false;
    if (allowPrerelease) return true;
    return isStableRelease(release);
  }

  /// Memastikan rilis bukan draft dan bukan pre-release (alpha/beta/rc).
  static bool isStableRelease(Map<String, dynamic> release) {
    if (release['draft'] == true || release['prerelease'] == true) {
      return false;
    }
    final version = _versionFromTag(release['tag_name']);
    if (version == null) return false;
    return !version.contains('alpha') && !version.contains('beta');
  }

  static String? _versionFromTag(Object? tag) {
    if (tag is! String) return null;
    final version = tag
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .replaceFirst(RegExp(r'\+.*$'), '');
    return RegExp(r'^\d+\.\d+\.\d+(?:-(?:alpha|beta)(?:\.?\d+)?)?$')
            .hasMatch(version)
        ? version
        : null;
  }

  static bool isNewerVersion(String latest, String current) {
    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    for (var i = 0; i < 3; i++) {
      if (l[i] != c[i]) return l[i] > c[i];
    }

    final latestPrerelease = l[3];
    final currentPrerelease = c[3];
    if (latestPrerelease == currentPrerelease) return false;
    if (latestPrerelease == -1) return true;
    if (currentPrerelease == -1) return false;
    return latestPrerelease > currentPrerelease;
  }

  static List<int> _parseVersion(String version) {
    final clean = version
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .replaceFirst(RegExp(r'\+.*$'), '');
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta)(?:\.?(\d+))?)?$',
    ).firstMatch(clean);
    if (match == null) return [0, 0, 0, 0];

    final stage = match.group(4);
    final numStr = match.group(5);
    final prereleaseNum = numStr != null ? int.parse(numStr) : 0;

    int prereleaseRank = -1;
    if (stage == 'alpha') {
      prereleaseRank = 1000 + prereleaseNum;
    } else if (stage == 'beta') {
      prereleaseRank = 2000 + prereleaseNum;
    }

    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      prereleaseRank,
    ];
  }
}
