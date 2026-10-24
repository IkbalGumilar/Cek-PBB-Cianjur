/// Kebijakan Keamanan & Pembatasan Akses Google Drive untuk Cadangan Data DHKP.
///
/// Prinsip Keamanan & Privasi (Least Privilege):
/// 1. Aplikasi DILARANG KERAS meminta cakupan luas `https://www.googleapis.com/auth/drive`.
/// 2. Aplikasi HANYA diizinkan menggunakan scope terbatas:
///    - `https://www.googleapis.com/auth/drive.appdata` (Application Data folder rahasia/terisolasi), atau
///    - `https://www.googleapis.com/auth/drive.file` (Akses per-file hanya ke berkas/folder yang dibuat oleh aplikasi ini).
/// 3. Folder khusus aplikasi di Google Drive dinamai [dedicatedFolderName] (`Cek PBB Cianjur`).
/// 4. Aplikasi DILARANG KERAS mengakses, melihat, membaca, memodifikasi, atau menghapus berkas dan folder lain milik pengguna di Google Drive.
/// 5. Kebijakan retensi Google Drive selaras dengan penyimpanan lokal: maksimal [maxCloudBackups] = 3 berkas cadangan terbaru.
class GoogleDriveBackupPolicy {
  GoogleDriveBackupPolicy._();

  /// Nama folder khusus di Google Drive pengguna.
  static const String dedicatedFolderName = 'Cek PBB Cianjur';

  /// ID folder khusus AppData bawaan Google Drive (hidden application data).
  static const String appDataFolderId = 'appDataFolder';

  /// Scope Google Drive yang diizinkan (Least-Privilege).
  static const String allowedScopeAppData =
      'https://www.googleapis.com/auth/drive.appdata';
  static const String allowedScopeDriveFile =
      'https://www.googleapis.com/auth/drive.file';

  static const List<String> allowedScopes = [
    allowedScopeAppData,
    allowedScopeDriveFile,
  ];

  /// Scope terlarang yang dilarang digunakan karena memberikan akses ke seluruh Google Drive pengguna.
  static const List<String> forbiddenScopes = [
    'https://www.googleapis.com/auth/drive',
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/drive.metadata',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
  ];

  /// Batas retensi cadangan di Google Drive (maksimal 3 berkas).
  static const int maxCloudBackups = 3;

  /// Memeriksa apakah scope OAuth yang diminta mematuhi prinsip Least-Privilege.
  static bool isScopeAllowed(String scope) {
    if (forbiddenScopes.contains(scope)) return false;
    return allowedScopes.contains(scope);
  }

  /// Memeriksa apakah folder target adalah folder khusus yang diizinkan untuk aplikasi.
  static bool isFolderAllowed(String folder, {String? customFolderId}) {
    final trimmed = folder.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == dedicatedFolderName || trimmed == appDataFolderId) {
      return true;
    }
    if (customFolderId != null && customFolderId.isNotEmpty && trimmed == customFolderId.trim()) {
      return true;
    }
    return false;
  }

  /// Ekstrak ID folder dari URL Google Drive atau ID folder mentah.
  /// Contoh:
  /// - `https://drive.google.com/drive/folders/1ABC_123-xyz?usp=sharing` -> `1ABC_123-xyz`
  /// - `https://drive.google.com/drive/u/0/folders/1ABC_123-xyz` -> `1ABC_123-xyz`
  /// - `1ABC_123-xyz` -> `1ABC_123-xyz`
  static String? extractFolderId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final urlMatch = RegExp(r'folders/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (urlMatch != null) {
      return urlMatch.group(1);
    }

    // ID folder Google Drive biasanya alfanumerik panjang >= 15 karakter
    if (RegExp(r'^[a-zA-Z0-9_-]{15,}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Validasi keamanan ketat: melempar [SecurityException] jika ada pelanggaran izin atau akses ke folder lain.
  static void validateAccess({
    required String targetFolder,
    required List<String> requestedScopes,
  }) {
    for (final scope in requestedScopes) {
      if (!isScopeAllowed(scope)) {
        throw SecurityException(
          'Scope Google Drive "$scope" dilarang! '
          'Aplikasi hanya diizinkan menggunakan scope terbatas: $allowedScopes.',
        );
      }
    }

    if (!isFolderAllowed(targetFolder)) {
      throw SecurityException(
        'Akses ke folder "$targetFolder" dilarang! '
        'Aplikasi hanya boleh membuat dan mengakses folder khusus: '
        '"$dedicatedFolderName" atau "$appDataFolderId".',
      );
    }
  }

  /// Ringkasan jaminan privasi untuk ditampilkan di UI dialog pengaturan.
  static const String privacyNoticeTitle = 'Keamanan & Privasi Terjamin';

  static const String privacyNoticeBody =
      'Aplikasi hanya akan membuat dan mengakses folder khusus '
      '("$dedicatedFolderName" atau folder AppData terisolasi). '
      'Aplikasi dibatasi secara sistem dan dilarang mengakses dokumen, foto, '
      'atau folder pribadi lainnya di Google Drive Anda.';

  /// Pemberitahuan syarat izin Editor pada folder bersama.
  static const String editorRequirementNotice =
      'Akun Google yang terhubung wajib memiliki hak akses Editor '
      'di folder bersama ini agar aplikasi dapat membuat dan memperbarui berkas cadangan.';
}

/// Pengecualian keamanan saat terjadi pelanggaran izin atau akses folder.
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
