import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';
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
/// 3. Opsi PIN kustom 6 digit atau Password kustom dengan hash PBKDF2-HMAC-SHA256
///    (100.000 iterasi) + salt acak tersimpan di FlutterSecureStorage.
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
  static const String _keyFailedAttempts = 'app_security_failed_pin_attempts';
  static const String _keyLockoutUntilMillis =
      'app_security_lockout_until_millis';

  static int pbkdf2Iterations = 100000;

  @visibleForTesting
  static void setPbkdf2IterationsForTesting(int iterations) {
    pbkdf2Iterations = iterations;
  }

  Future<String?> _readSecure(String key) => readSecureWithFallback(key);

  Future<void> _writeSecure(String key, String value) =>
      writeSecureWithFallback(key, value);

  Future<void> _deleteSecure(String key) => deleteSecureWithFallback(key);

  Future<String> _hashSecretPbkdf2(String secret, String salt) async {
    final saltBytes = utf8.encode(salt);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pbkdf2Iterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: saltBytes,
    );
    final keyBytes = await key.extractBytes();
    return '\$pbkdf2\$${base64Encode(keyBytes)}';
  }

  LocalAuthentication _localAuth = LocalAuthentication();

  @visibleForTesting
  void setLocalAuthForTesting(LocalAuthentication auth) {
    _localAuth = auth;
  }

  /// Notifier status apakah aplikasi saat ini sedang terkunci.
  final ValueNotifier<bool> isAppLockedNotifier = ValueNotifier<bool>(false);

  /// Status apakah aplikasi saat ini sedang terkunci.
  bool get isAppLocked => isAppLockedNotifier.value;

  /// Notifier status apakah pembaca dokumen sedang aktif dalam mode kotak pasir (Sandboxed Viewer).
  final ValueNotifier<bool> isSandboxedViewerNotifier = ValueNotifier<bool>(
    false,
  );

  /// Status apakah mode kotak pasir sedang aktif.
  bool get isSandboxedViewerActive => isSandboxedViewerNotifier.value;

  /// Masuk ke mode kotak pasir (membuka dokumen tanpa terhalang layar kunci).
  void enterSandboxedViewer() {
    isSandboxedViewerNotifier.value = true;
  }

  /// Keluar dari mode kotak pasir (segel kembali layar kunci jika aplikasi terkunci).
  void exitSandboxedViewer() {
    isSandboxedViewerNotifier.value = false;
  }

  static const MethodChannel _securityChannel = MethodChannel(
    'id.cianjur.cekpbb.cek_pbb_app/security',
  );

  bool _isScreenSecured = false;

  /// Status apakah proteksi screenshot saat ini sedang aktif di layar.
  bool get isScreenSecured => _isScreenSecured;

  /// Mengaktifkan atau menonaktifkan proteksi tangkapan layar (FLAG_SECURE) secara dinamis.
  /// Sesuai aturan: Hanya aktif saat berkas DHKP sedang terbuka dan memiliki data catatan.
  Future<void> setScreenSecure(bool secure) async {
    if (!Platform.isAndroid) return;
    if (_isScreenSecured == secure) return;
    try {
      await _securityChannel.invokeMethod<bool>('setSecureMode', {
        'enabled': secure,
      });
      _isScreenSecured = secure;
    } catch (e) {
      debugPrint(
        'AppSecurityService: Gagal mengatur status screenshot (FLAG_SECURE): $e',
      );
    }
  }

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
      final hasFinger =
          biometrics.contains(BiometricType.fingerprint) ||
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

  bool _isAuthenticating = false;
  bool get isAuthenticating => _isAuthenticating;

  bool _temporaryLockBypass = false;
  bool get temporaryLockBypass => _temporaryLockBypass;

  /// Mengatur bypass penguncian sementara saat membuka dialog pihak ketiga (misal: Google Sign In).
  void setTemporaryLockBypass(bool value) {
    _temporaryLockBypass = value;
  }

  /// Meminta autentikasi menggunakan Kunci Perangkat (Sidik Jari / Wajah / Kunci Layar HP).
  Future<bool> authenticateWithDevice({
    String reason = 'Konfirmasi keamanan untuk membuka Cek PBB Cianjur',
  }) async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly:
            false, // Izinkan fallback ke PIN/Pola HP jika biometrik belum diatur/gagal
        persistAcrossBackgrounding: true,
      );
      if (authenticated) {
        unlock();
      }
      return authenticated;
    } on PlatformException catch (e) {
      debugPrint(
        'AppSecurityService: PlatformException saat autentikasi biometrik: ${e.code} - ${e.message}',
      );
      return false;
    } catch (e) {
      debugPrint('AppSecurityService: Gagal autentikasi biometrik: $e');
      return false;
    } finally {
      _isAuthenticating = false;
    }
  }

  /// Meminta autentikasi biometrik/kunci HP khusus untuk mendekripsi dan membuka paket DHKP
  /// tanpa membuka status kunci aplikasi secara global jika aplikasi sedang terkunci di background.
  Future<bool> authenticateToDecryptDhkp({
    String fileName = 'paket DHKP',
  }) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck && !isSupported) {
        // Jika perangkat tidak memiliki biometrik atau kunci layar sistem,
        // lanjutkan ke proses verifikasi kata sandi berkas
        return true;
      }

      return await _localAuth.authenticate(
        localizedReason:
            'Pindai sidik jari Anda untuk mendekripsi dan membuka $fileName',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      debugPrint(
        'AppSecurityService: Gagal autentikasi DHKP: ${e.code} - ${e.message}',
      );
      return false;
    } catch (e) {
      debugPrint('AppSecurityService: Gagal autentikasi DHKP: $e');
      return false;
    }
  }

  // --- Kustom PIN (6 Digit) ---

  /// Memeriksa apakah PIN kustom sudah pernah dibuat.
  Future<bool> hasCustomPin() async {
    final hash = await _readSecure(_keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Mengatur PIN 6 digit baru dengan hash PBKDF2-HMAC-SHA256 (100.000 iterasi) + salt acak.
  Future<void> setCustomPin(String pin) async {
    final salt = _generateSalt();
    final hash = await _hashSecretPbkdf2(pin, salt);
    await _writeSecure(_keyPinSalt, salt);
    await _writeSecure(_keyPinHash, hash);
  }

  /// Memverifikasi PIN kustom yang dimasukkan pengguna.
  /// Mendukung verifikasi hash PBKDF2 maupun migrasi otomatis dari hash legacy SHA-256.
  Future<bool> verifyCustomPin(String pin) async {
    final salt = await _readSecure(_keyPinSalt);
    final storedHash = await _readSecure(_keyPinHash);
    if (salt == null || storedHash == null) return false;

    bool matches = false;
    if (storedHash.startsWith(r'$pbkdf2$')) {
      final inputHash = await _hashSecretPbkdf2(pin, salt);
      matches = inputHash == storedHash;
    } else {
      final inputHash = _hashSecret(pin, salt);
      matches = inputHash == storedHash;
      if (matches) {
        // Upgrade otomatis ke PBKDF2
        final upgraded = await _hashSecretPbkdf2(pin, salt);
        await _writeSecure(_keyPinHash, upgraded);
      }
    }

    if (matches) {
      unlock();
    }
    return matches;
  }

  // --- Kustom Password ---

  /// Memeriksa apakah password kustom sudah pernah dibuat.
  Future<bool> hasCustomPassword() async {
    final hash = await _readSecure(_keyPasswordHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Mengatur password kustom baru dengan hash PBKDF2-HMAC-SHA256 (100.000 iterasi) + salt acak.
  Future<void> setCustomPassword(String password) async {
    final salt = _generateSalt();
    final hash = await _hashSecretPbkdf2(password, salt);
    await _writeSecure(_keyPasswordSalt, salt);
    await _writeSecure(_keyPasswordHash, hash);
  }

  /// Memverifikasi password kustom yang dimasukkan pengguna.
  /// Mendukung verifikasi hash PBKDF2 maupun migrasi otomatis dari hash legacy SHA-256.
  Future<bool> verifyCustomPassword(String password) async {
    final salt = await _readSecure(_keyPasswordSalt);
    final storedHash = await _readSecure(_keyPasswordHash);
    if (salt == null || storedHash == null) return false;

    bool matches = false;
    if (storedHash.startsWith(r'$pbkdf2$')) {
      final inputHash = await _hashSecretPbkdf2(password, salt);
      matches = inputHash == storedHash;
    } else {
      final inputHash = _hashSecret(password, salt);
      matches = inputHash == storedHash;
      if (matches) {
        // Upgrade otomatis ke PBKDF2
        final upgraded = await _hashSecretPbkdf2(password, salt);
        await _writeSecure(_keyPasswordHash, upgraded);
      }
    }

    if (matches) {
      unlock();
    }
    return matches;
  }

  // --- Persistent Lockout & Percobaan Salah PIN/Password ---

  /// Mendapatkan jumlah percobaan salah yang tersimpan di penyimpanan aman.
  Future<int> getFailedPinAttempts() async {
    final raw = await _readSecure(_keyFailedAttempts);
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }

  /// Menambah 1 catatan percobaan salah dan mengembalikan hitungan terbaru.
  Future<int> recordFailedPinAttempt() async {
    final current = await getFailedPinAttempts();
    final updated = current + 1;
    await _writeSecure(_keyFailedAttempts, updated.toString());
    return updated;
  }

  /// Me-reset hitungan percobaan salah dan status lockout setelah berhasil buka kunci.
  Future<void> resetFailedPinAttempts() async {
    await _deleteSecure(_keyFailedAttempts);
    await _deleteSecure(_keyLockoutUntilMillis);
  }

  /// Mendapatkan batas waktu penguncian sementara jika ada dan belum kedaluwarsa.
  Future<DateTime?> getLockoutUntil() async {
    final raw = await _readSecure(_keyLockoutUntilMillis);
    if (raw == null) return null;
    final millis = int.tryParse(raw);
    if (millis == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(millis);
    if (DateTime.now().isBefore(until)) {
      return until;
    }
    await _deleteSecure(_keyLockoutUntilMillis);
    return null;
  }

  /// Mengatur batas waktu penguncian sementara (lockout) secara persisten.
  Future<void> setLockoutUntil(DateTime until) async {
    await _writeSecure(
      _keyLockoutUntilMillis,
      until.millisecondsSinceEpoch.toString(),
    );
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

  /// Dipanggil saat inisialisasi awal membuka aplikasi (cold start).
  Future<void> onColdStart() async {
    final enabled = await isLockEnabled();
    if (enabled) {
      lock();
    } else {
      unlock();
    }
    _lastPausedTime = null;
  }

  /// Dipanggil saat aplikasi beralih ke latar belakang (background / paused).
  void onAppPaused() {
    // Jangan catat jika aplikasi sudah terkunci, sedang dalam proses autentikasi,
    // atau bypass sementara (misal pemilih berkas sistem / dialog eksternal).
    if (isAppLocked || _isAuthenticating || _temporaryLockBypass) {
      return;
    }
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

    // Jika saat ini aplikasi sudah terkunci, biarkan tetap terkunci
    if (isAppLocked) return;

    // Jika sedang dalam proses autentikasi (misal prompt biometrik) atau bypass dialog eksternal
    if (_isAuthenticating || _temporaryLockBypass) return;

    // Jika belum pernah di-pause (misal hanya transisi lokal), jangan kunci
    if (_lastPausedTime == null) return;

    final timeout = await getTimeoutSeconds();
    final elapsedSeconds = DateTime.now()
        .difference(_lastPausedTime!)
        .inSeconds;

    if (elapsedSeconds >= timeout) {
      lock();
    }
    _lastPausedTime = null;
  }

  /// Reset preferensi untuk keperluan pengujian.
  @visibleForTesting
  void resetForTesting() {
    resetPrefsForTesting();
    pbkdf2Iterations = 100000;
    isAppLockedNotifier.value = false;
    _lastPausedTime = null;
    _isAuthenticating = false;
    _temporaryLockBypass = false;
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
