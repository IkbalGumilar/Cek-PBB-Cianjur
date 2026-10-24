import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'base_preferences_store.dart';

/// Jenis metode penguncian aplikasi.
enum AppLockType {
  /// Menggunakan keamanan bawaan HP (Sidik Jari / Fingerprint, Wajah / Face Unlock,
  /// atau PIN/Pola layar kunci perangkat via BiometricPrompt Android).
  device,

  /// Menggunakan PIN numerik 6 digit khusus aplikasi.
  pin,

  /// Menggunakan kata sandi teks khusus aplikasi.
  password,
}

/// Layanan pengelola keamanan & kunci aplikasi (App Lock ala m-Banking).
///
/// Fitur:
/// 1. Opsional (default nonaktif), dapat diaktifkan/dinonaktifkan di Pengaturan.
/// 2. Terintegrasi dengan biometrik HP (Fingerprint & Face Unlock) serta fallback
///    ke PIN/pola layar kunci perangkat.
/// 3. Opsi PIN kustom 6 digit atau Password kustom dengan hash SHA-256 + garam acak (salt).
/// 4. Opsi waktu kunci otomatis: Segera (0 detik), 30 detik, 1 menit (60 detik), 5 menit (300 detik).
/// 5. Pengelolaan status aktif/terkunci secara reaktif via [isAppLockedNotifier].
class AppSecurityService extends BasePreferencesStore {
  AppSecurityService._();
  static final instance = AppSecurityService._();

  static const String _keyLockEnabled = 'app_security_lock_enabled';
  static const String _keyLockType = 'app_security_lock_type';
  static const String _keyTimeoutSeconds = 'app_security_timeout_seconds';
  static const String _keyPinHash = 'app_security_custom_pin_hash';
  static const String _keyPinSalt = 'app_security_custom_pin_salt';
  static const String _keyPasswordHash = 'app_security_custom_password_hash';
  static const String _keyPasswordSalt = 'app_security_custom_password_salt';

  LocalAuthentication _localAuth = LocalAuthentication();

  @visibleForTesting
  void setLocalAuthForTesting(LocalAuthentication auth) {
    _localAuth = auth;
  }

  /// Notifier status apakah aplikasi saat ini sedang terkunci.
  final ValueNotifier<bool> isAppLockedNotifier = ValueNotifier<bool>(false);

  /// Status apakah aplikasi saat ini sedang terkunci.
  bool get isAppLocked => isAppLockedNotifier.value;

  DateTime? _lastPausedTime;

  /// Apakah kunci aplikasi aktif.
  Future<bool> isLockEnabled() async {
    return getBool(_keyLockEnabled, defaultValue: false);
  }

  /// Mengaktifkan atau menonaktifkan kunci aplikasi.
  Future<void> setLockEnabled(bool enabled) async {
    await setBool(_keyLockEnabled, enabled);
    if (!enabled) {
      unlock();
    }
  }

  /// Mendapatkan jenis kunci yang dipilih. Default: [AppLockType.device].
  Future<AppLockType> getLockType() async {
    final raw = await getString(_keyLockType);
    if (raw == 'pin') return AppLockType.pin;
    if (raw == 'password') return AppLockType.password;
    return AppLockType.device;
  }

  /// Mengubah jenis kunci yang dipilih.
  Future<void> setLockType(AppLockType type) async {
    final val = switch (type) {
      AppLockType.device => 'device',
      AppLockType.pin => 'pin',
      AppLockType.password => 'password',
    };
    await setString(_keyLockType, val);
  }

  /// Mendapatkan jeda waktu kunci otomatis dalam detik.
  /// 0 = Segera saat aplikasi ditutup/ke background.
  /// 30 = Setelah 30 detik.
  /// 60 = Setelah 1 menit.
  /// 300 = Setelah 5 menit.
  Future<int> getTimeoutSeconds() async {
    return (await getInt(_keyTimeoutSeconds)) ?? 0;
  }

  /// Mengatur jeda waktu kunci otomatis dalam detik.
  Future<void> setTimeoutSeconds(int seconds) async {
    await setInt(_keyTimeoutSeconds, seconds);
  }

  /// Memeriksa apakah perangkat memiliki sensor biometrik (Fingerprint/Face).
  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Memeriksa apakah perangkat mendukung autentikasi keamanan (biometrik atau kunci layar HP).
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Mendapatkan daftar tipe biometrik yang tersedia di perangkat (misal: Fingerprint, Face).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return <BiometricType>[];
    }
  }

  /// Menghasilkan deskripsi ringkas tentang kemampuan biometrik perangkat.
  Future<String> getBiometricCapabilitiesSummary() async {
    try {
      final supported = await isDeviceSupported();
      if (!supported) {
        return 'Perangkat tidak mendukung biometrik atau kunci layar';
      }

      final biometrics = await getAvailableBiometrics();
      final hasFinger = biometrics.contains(BiometricType.fingerprint) ||
          biometrics.contains(BiometricType.strong);
      final hasFace = biometrics.contains(BiometricType.face);

      if (hasFinger && hasFace) {
        return 'Mendukung Sidik Jari & Pengenalan Wajah';
      } else if (hasFinger) {
        return 'Mendukung Sidik Jari (Fingerprint)';
      } else if (hasFace) {
        return 'Mendukung Pengenalan Wajah (Face Unlock)';
      } else {
        return 'Mendukung Kunci Layar HP (PIN / Pola / Sandi)';
      }
    } catch (_) {
      return 'Kunci Layar Perangkat Bawaan';
    }
  }

  /// Meminta autentikasi menggunakan Kunci Perangkat (Sidik Jari / Wajah / Kunci Layar HP).
  Future<bool> authenticateWithDevice({
    String reason = 'Konfirmasi keamanan untuk membuka Cek PBB Cianjur',
  }) async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // Izinkan fallback ke PIN/Pola HP jika biometrik belum diatur/gagal
        persistAcrossBackgrounding: true,
      );
      if (authenticated) {
        unlock();
      }
      return authenticated;
    } on PlatformException catch (e) {
      debugPrint('AppSecurityService: PlatformException saat autentikasi biometrik: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('AppSecurityService: Gagal autentikasi biometrik: $e');
      return false;
    }
  }

  // --- Kustom PIN (6 Digit) ---

  /// Memeriksa apakah PIN kustom sudah pernah dibuat.
  Future<bool> hasCustomPin() async {
    final hash = await getString(_keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Mengatur PIN 6 digit baru dengan hash SHA-256 + salt acak.
  Future<void> setCustomPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashSecret(pin, salt);
    await setString(_keyPinSalt, salt);
    await setString(_keyPinHash, hash);
  }

  /// Memverifikasi PIN kustom yang dimasukkan pengguna.
  Future<bool> verifyCustomPin(String pin) async {
    final salt = await getString(_keyPinSalt);
    final storedHash = await getString(_keyPinHash);
    if (salt == null || storedHash == null) return false;

    final inputHash = _hashSecret(pin, salt);
    final matches = inputHash == storedHash;
    if (matches) {
      unlock();
    }
    return matches;
  }

  // --- Kustom Password ---

  /// Memeriksa apakah password kustom sudah pernah dibuat.
  Future<bool> hasCustomPassword() async {
    final hash = await getString(_keyPasswordHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Mengatur password kustom baru dengan hash SHA-256 + salt acak.
  Future<void> setCustomPassword(String password) async {
    final salt = _generateSalt();
    final hash = _hashSecret(password, salt);
    await setString(_keyPasswordSalt, salt);
    await setString(_keyPasswordHash, hash);
  }

  /// Memverifikasi password kustom yang dimasukkan pengguna.
  Future<bool> verifyCustomPassword(String password) async {
    final salt = await getString(_keyPasswordSalt);
    final storedHash = await getString(_keyPasswordHash);
    if (salt == null || storedHash == null) return false;

    final inputHash = _hashSecret(password, salt);
    final matches = inputHash == storedHash;
    if (matches) {
      unlock();
    }
    return matches;
  }

  // --- Lifecycle & Lock State ---

  /// Kunci aplikasi secara manual.
  void lock() {
    isAppLockedNotifier.value = true;
  }

  /// Buka kunci aplikasi.
  void unlock() {
    isAppLockedNotifier.value = false;
    _lastPausedTime = null;
  }

  /// Dipanggil saat aplikasi beralih ke latar belakang (background / paused).
  void onAppPaused() {
    _lastPausedTime = DateTime.now();
  }

  /// Dipanggil saat aplikasi kembali aktif (resume).
  /// Memeriksa apakah waktu di background telah melampaui batas timeout.
  Future<void> onAppResumed() async {
    final enabled = await isLockEnabled();
    if (!enabled) {
      unlock();
      return;
    }

    if (_lastPausedTime == null) {
      // Pembukaan awal aplikasi (cold start) -> langsung kunci
      lock();
      return;
    }

    final timeout = await getTimeoutSeconds();
    final elapsedSeconds =
        DateTime.now().difference(_lastPausedTime!).inSeconds;

    if (elapsedSeconds >= timeout) {
      lock();
    }
  }

  /// Reset preferensi untuk keperluan pengujian.
  @visibleForTesting
  void resetForTesting() {
    resetPrefsForTesting();
    isAppLockedNotifier.value = false;
    _lastPausedTime = null;
  }

  // --- Internal Crypto Helper ---

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  String _hashSecret(String secret, String salt) {
    final bytes = utf8.encode('$secret::$salt');
    return sha256.convert(bytes).toString();
  }
}
