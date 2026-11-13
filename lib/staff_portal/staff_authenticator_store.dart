import '../base_preferences_store.dart';
import 'totp_helper.dart';

/// Penyimpanan aman lokal untuk kunci Google Authenticator (MFA) Portal Staf.
///
/// Menyimpan Secret Key secara terenkripsi (Android Keystore / Linux libsecret /
/// Windows DPAPI) via [BasePreferencesStore], serta preferensi auto-fill/auto-verify.
class StaffAuthenticatorStore extends BasePreferencesStore {
  static const String _keySecret = 'staff_mfa_secret';
  static const String _keyAccountName = 'staff_mfa_account_name';
  static const String _keyIssuer = 'staff_mfa_issuer';
  static const String _keyAutoVerify = 'staff_mfa_auto_verify';

  /// Memeriksa apakah Secret Key sudah tersimpan dan valid.
  Future<bool> hasSecret() async {
    final secret = await getSecret();
    return secret != null && TotpHelper.isValidBase32(secret);
  }

  /// Mengambil Secret Key Base32 yang tersimpan secara terenkripsi.
  Future<String?> getSecret() async {
    final secret = await readSecureWithMigration(_keySecret);
    if (secret == null || secret.trim().isEmpty) return null;
    return TotpHelper.sanitizeBase32(secret);
  }

  /// Mengambil nama akun yang tersimpan (misal nama staf / username).
  Future<String?> getAccountName() async {
    return getString(_keyAccountName);
  }

  /// Mengambil nama penerbit (issuer, misal BAPENDA).
  Future<String?> getIssuer() async {
    return getString(_keyIssuer);
  }

  /// Menghasilkan label tampilan akun (misal "BAPENDA (admin)").
  Future<String> getAccountLabel() async {
    final name = await getAccountName() ?? '';
    final issuer = await getIssuer() ?? '';
    if (issuer.isNotEmpty && name.isNotEmpty && !name.contains(issuer)) {
      return '$issuer ($name)';
    }
    if (name.isNotEmpty) return name;
    if (issuer.isNotEmpty) return issuer;
    return 'Google Authenticator Staf';
  }

  /// Menyimpan Secret Key Base32 dan opsional metadata akun.
  Future<void> saveSecret(
    String secretBase32, {
    String? accountName,
    String? issuer,
  }) async {
    final cleaned = TotpHelper.sanitizeBase32(secretBase32);
    if (!TotpHelper.isValidBase32(cleaned)) {
      throw const FormatException('Secret key bukan format Base32 yang valid.');
    }
    await writeSecureOnly(_keySecret, cleaned);
    if (accountName != null && accountName.isNotEmpty) {
      await setString(_keyAccountName, accountName);
    }
    if (issuer != null && issuer.isNotEmpty) {
      await setString(_keyIssuer, issuer);
    }
  }

  /// Menghapus Secret Key dan seluruh metadata Authenticator terkait.
  Future<void> clearSecret() async {
    await deleteSecureOnly(_keySecret);
    await remove(_keyAccountName);
    await remove(_keyIssuer);
  }

  /// Mengecek apakah mode Verifikasi & Login Otomatis aktif (default: true).
  Future<bool> isAutoVerifyEnabled() async {
    return getBool(_keyAutoVerify, defaultValue: true);
  }

  /// Mengaktifkan atau menonaktifkan mode Verifikasi & Login Otomatis.
  Future<void> setAutoVerifyEnabled(bool enabled) async {
    await setBool(_keyAutoVerify, enabled);
  }

  /// Menghitung kode TOTP 6 digit aktif saat ini. Mengembalikan `null` jika kunci belum tersimpan.
  Future<String?> getCurrentCode({DateTime? time}) async {
    final secret = await getSecret();
    if (secret == null) return null;
    try {
      return TotpHelper.generateTotp(secretBase32: secret, time: time);
    } catch (_) {
      return null;
    }
  }
}
