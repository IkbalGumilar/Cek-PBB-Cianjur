import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_security_service.dart';
import 'blok_backup_scheduler.dart';
import 'cloud_sync/google_account_sync_service.dart';
import 'google_drive_backup_policy.dart';

/// Model sederhana untuk representasi akun Google yang terhubung.
class GoogleAuthUser {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String id;

  const GoogleAuthUser({
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.id,
  });
}

/// Service untuk menangani otentikasi Google (Google Auth / Sign in with Google)
/// secara langsung dari perangkat tanpa perantara backend server:
/// - Di Android & iOS: Memakai Google Sign In SDK (Google Account Chooser bawaan).
/// - Di Linux, Windows, & macOS: Memakai Google OAuth 2.0 Loopback di browser bawaan (RFC 8252 + PKCE).
class GoogleAuthService {
  GoogleAuthService._();
  static final instance = GoogleAuthService._();

  /// Default Client ID untuk aplikasi Desktop (Linux, Windows, macOS)
  /// yang terdaftar di Google Cloud Console.
  static const String defaultDesktopClientId =
      '291477165913-abopbq9ng6lkivd3egpdu598m3utq3sh.apps.googleusercontent.com';

  static const String _envDesktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
  );
  static const String _envDesktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );

  String _desktopClientId = _envDesktopClientId.isNotEmpty
      ? _envDesktopClientId
      : defaultDesktopClientId;
  String _desktopClientSecret = _envDesktopClientSecret;

  HttpServer? _activeDesktopAuthServer;
  bool _desktopSignInCancelled = false;

  /// Menunjukkan apakah kredensial OAuth Desktop (Client ID & Client Secret)
  /// sudah terpasang saat build/konfigurasi.
  bool get hasDesktopOAuthCredentials =>
      _desktopClientId.trim().isNotEmpty &&
      _desktopClientSecret.trim().isNotEmpty;

  static const List<String> _scopes = [
    'email',
    'profile',
    GoogleDriveBackupPolicy.allowedScopeDriveFile,
    GoogleDriveBackupPolicy.allowedScopeAppData,
  ];

  GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  /// Mengonfigurasi instance GoogleSignIn atau kredensial OAuth Desktop jika diperlukan.
  void configure({
    String? clientId,
    String? serverClientId,
    String? desktopClientId,
    String? desktopClientSecret,
  }) {
    if (desktopClientId != null && desktopClientId.trim().isNotEmpty) {
      _desktopClientId = desktopClientId.trim();
    }
    if (desktopClientSecret != null && desktopClientSecret.trim().isNotEmpty) {
      _desktopClientSecret = desktopClientSecret.trim();
    }
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  /// Membatalkan sesi tunggu callback OAuth Desktop yang sedang berjalan (jika ada).
  Future<void> cancelPendingDesktopSignIn() async {
    final server = _activeDesktopAuthServer;
    if (server != null) {
      _desktopSignInCancelled = true;
      _activeDesktopAuthServer = null;
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  /// Memeriksa apakah platform saat ini didukung untuk Google Sign In.
  bool get isSupportedPlatform {
    if (kIsWeb) return true;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS;
  }

  /// Mendapatkan akun Google yang saat ini terhubung di sesi aktif.
  GoogleSignInAccount? get currentGoogleAccount => _googleSignIn.currentUser;

  @visibleForTesting
  static GoogleAuthUser? mockUser;

  @visibleForTesting
  static void resetForTesting() {
    mockUser = null;
  }

  /// Memeriksa apakah izin Google Drive saat ini telah disetujui pengguna.
  Future<bool> hasDrivePermission() async {
    if (mockUser != null) return true;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final token = await BlokBackupScheduler.instance
          .getGoogleDesktopAccessToken();
      return token.isNotEmpty;
    }
    if (kIsWeb) {
      try {
        return await _googleSignIn.canAccessScopes(_scopes);
      } catch (_) {
        return false;
      }
    }
    return _googleSignIn.currentUser != null;
  }

  /// Membuka popup / dialog sistem Google Account Chooser di perangkat Android/iOS,
  /// atau membuka web browser via Loopback OAuth 2.0 di Linux/Windows/macOS
  /// sekaligus meminta izin otorisasi Google Drive.
  Future<GoogleAuthUser?> signIn() async {
    if (mockUser != null) {
      await BlokBackupScheduler.instance.setGoogleAccountDetails(
        email: mockUser!.email,
        displayName: mockUser!.displayName,
        photoUrl: mockUser!.photoUrl,
      );
      return mockUser;
    }

    if (!isSupportedPlatform) {
      throw Exception('Platform saat ini tidak didukung untuk Google Sign-In.');
    }

    // Jika berjalan di platform desktop (Linux / Windows / macOS), gunakan Loopback Browser
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return await _signInDesktop();
    }

    // Abaikan penguncian aplikasi sementara saat popup Google Sign In sistem sedang aktif
    AppSecurityService.instance.setTemporaryLockBypass(true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // Pengguna membatalkan dialog pemilihan akun
        return null;
      }

      // canAccessScopes & requestScopes hanya didukung pada platform Web.
      // Pada Android & iOS, seluruh scope di _scopes sudah diotorisasi langsung di dalam panggilan signIn().
      if (kIsWeb) {
        final hasDrive = await _googleSignIn.canAccessScopes(_scopes);
        if (!hasDrive) {
          final granted = await _googleSignIn.requestScopes(_scopes);
          if (!granted) {
            throw Exception(
              'Izin akses Google Drive ditolak. Cadangan data DHKP '
              'membutuhkan izin akses folder Google Drive agar dapat disinkronkan.',
            );
          }
        }
      }

      final user = GoogleAuthUser(
        email: account.email,
        displayName: account.displayName ?? account.email.split('@').first,
        photoUrl: account.photoUrl,
        id: account.id,
      );

      // Simpan data akun ke scheduler
      await BlokBackupScheduler.instance.setGoogleAccountDetails(
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      );
      unawaited(GoogleAccountSyncService.instance.syncAllAfterSignIn());

      return user;
    } on PlatformException catch (e) {
      debugPrint('Google Sign-In PlatformException: ${e.code} - ${e.message}');
      // Kode pembatalan oleh pengguna (12501 atau sign_in_canceled)
      if (e.code == 'sign_in_canceled' ||
          e.message?.contains('12501') == true) {
        return null;
      }
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    } finally {
      AppSecurityService.instance.setTemporaryLockBypass(false);
    }
  }

  /// Alur otentikasi Google OAuth 2.0 untuk aplikasi Desktop via Browser (RFC 8252)
  /// menggunakan Loopback IP (`127.0.0.1`) dan PKCE (Proof Key for Code Exchange).
  Future<GoogleAuthUser?> _signInDesktop() async {
    if (!hasDesktopOAuthCredentials) {
      throw Exception(
        'Kredensial OAuth Desktop Google (GOOGLE_DESKTOP_CLIENT_ID & '
        'GOOGLE_DESKTOP_CLIENT_SECRET) belum terpasang pada build ini. '
        'Jalankan/build aplikasi dengan --dart-define-from-file=env.desktop.json.',
      );
    }

    await cancelPendingDesktopSignIn();
    _desktopSignInCancelled = false;

    // 1. Siapkan PKCE (code_verifier & code_challenge)
    final codeVerifier = generateRandomString(64);
    final codeChallenge = generateCodeChallenge(codeVerifier);
    final state = generateRandomString(16);

    // 2. Buka local loopback server pada IPv4 127.0.0.1 port dinamis (RFC 8252)
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _activeDesktopAuthServer = server;
    final redirectUri = 'http://127.0.0.1:${server.port}';

    // 3. Susun URL otorisasi Google OAuth 2.0 v2
    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _desktopClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes.join(' '),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    });

    final String authCode;
    try {
      // 4. Buka browser bawaan sistem (Chrome, Firefox, Edge, dll)
      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Gagal membuka web browser sistem.');
      }

      // 5. Tunggu respon callback OAuth yang valid dari browser (timeout 3 menit)
      authCode = await waitForOAuthCallback(
        server,
        expectedState: state,
        timeout: const Duration(minutes: 3),
      );
    } catch (e) {
      if (_desktopSignInCancelled) {
        return null;
      }
      rethrow;
    } finally {
      if (identical(_activeDesktopAuthServer, server)) {
        _activeDesktopAuthServer = null;
      }
      _desktopSignInCancelled = false;
      await server.close(force: true);
    }

    // 6. Tukarkan authorization code dengan Access Token di Google Token Endpoint
    final httpClient = HttpClient();
    try {
      final tokenRequest = await httpClient.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      tokenRequest.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      final tokenParams = buildDesktopTokenExchangeParams(
        clientId: _desktopClientId,
        clientSecret: _desktopClientSecret,
        authCode: authCode,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      );
      tokenRequest.write(_encodeFormBody(tokenParams));

      final tokenResponse = await tokenRequest.close();
      final tokenResponseBody = await tokenResponse
          .transform(utf8.decoder)
          .join();
      final tokenJson = jsonDecode(tokenResponseBody) as Map<String, dynamic>;

      if (tokenResponse.statusCode != 200 ||
          !tokenJson.containsKey('access_token')) {
        final err =
            tokenJson['error_description'] ??
            tokenJson['error'] ??
            'Gagal menukarkan token';
        throw Exception('Gagal mendapatkan token dari Google: $err');
      }

      final accessToken = tokenJson['access_token'] as String;
      final refreshToken = tokenJson['refresh_token'] as String?;
      final grantedScope = tokenJson['scope'] as String? ?? '';

      // Verifikasi bahwa izin Google Drive benar-benar disetujui pengguna
      if (!grantedScope.contains('drive.file') &&
          !grantedScope.contains('drive.appdata')) {
        throw Exception(
          'Izin akses Google Drive ditolak. Cadangan data DHKP '
          'membutuhkan izin akses folder Google Drive agar dapat disinkronkan.',
        );
      }

      // 7. Ambil detail profil pengguna dari Google UserInfo Endpoint
      final userInfoRequest = await httpClient.getUrl(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      userInfoRequest.headers.set('Authorization', 'Bearer $accessToken');
      final userInfoResponse = await userInfoRequest.close();
      final userInfoBody = await userInfoResponse
          .transform(utf8.decoder)
          .join();
      final userJson = jsonDecode(userInfoBody) as Map<String, dynamic>;

      final email = userJson['email'] as String? ?? '';
      final name = userJson['name'] as String? ?? email.split('@').first;
      final picture = userJson['picture'] as String? ?? '';
      final sub = userJson['sub'] as String? ?? '';

      if (email.isEmpty) {
        throw Exception('Gagal mendapatkan informasi email akun Google.');
      }

      final user = GoogleAuthUser(
        email: email,
        displayName: name,
        photoUrl: picture,
        id: sub,
      );

      // Simpan token desktop dan profil pengguna ke scheduler
      await BlokBackupScheduler.instance.setGoogleDesktopTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await BlokBackupScheduler.instance.setGoogleAccountDetails(
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      );
      unawaited(GoogleAccountSyncService.instance.syncAllAfterSignIn());

      return user;
    } finally {
      httpClient.close();
    }
  }

  /// Menghasilkan string acak aman untuk PKCE verifier dan state.
  @visibleForTesting
  static String generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  /// Menghasilkan SHA-256 Code Challenge dari verifier sesuai RFC 7636 (PKCE).
  @visibleForTesting
  static String generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Menunggu request callback OAuth 2.0 yang valid pada [server] loopback.
  ///
  /// - Mengabaikan request `/favicon.ico` (merespons 404 dan lanjut menunggu).
  /// - Mengabaikan request yang belum memiliki query parameter `code` atau `error`.
  /// - Memvalidasi parameter `state` untuk mencegah CSRF.
  /// - Menutup `server` pada blok `finally`.
  @visibleForTesting
  static Future<String> waitForOAuthCallback(
    HttpServer server, {
    required String expectedState,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    Future<String> listenLoop() async {
      await for (final request in server) {
        final path = request.uri.path;
        if (path == '/favicon.ico') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }

        final queryParams = request.uri.queryParameters;
        final hasCode = queryParams.containsKey('code');
        final hasError = queryParams.containsKey('error');
        if (!hasCode && !hasError) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType.text;
          request.response.write('Menunggu callback OAuth...');
          await request.response.close();
          continue;
        }

        if (hasError) {
          final rawError = queryParams['error'] ?? 'access_denied';
          await _sendHtmlResponse(
            request.response,
            isSuccess: false,
            message: 'Otorisasi dibatalkan: $rawError',
          );
          throw Exception(
            'Otorisasi akun Google dibatalkan di browser ($rawError).',
          );
        }

        final returnedState = queryParams['state'];
        final authCode = queryParams['code'];

        if (returnedState != expectedState ||
            authCode == null ||
            authCode.trim().isEmpty) {
          await _sendHtmlResponse(
            request.response,
            isSuccess: false,
            message: 'Parameter otorisasi (state/code) tidak valid.',
          );
          throw Exception(
            'Kode otorisasi Google tidak valid atau sesi kadaluarsa.',
          );
        }

        await _sendHtmlResponse(request.response, isSuccess: true);
        return authCode.trim();
      }
      throw Exception('Server loopback OAuth ditutup sebelum menerima respon.');
    }

    try {
      return await listenLoop().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Waktu otorisasi di browser telah habis (timeout).',
        ),
      );
    } finally {
      await server.close(force: true);
    }
  }

  /// Mengirimkan halaman HTML informatif ke browser setelah proses otentikasi.
  /// Seluruh nilai dinamis di-escape dengan [HtmlEscape] untuk mencegah Reflected XSS.
  static Future<void> _sendHtmlResponse(
    HttpResponse response, {
    required bool isSuccess,
    String? message,
  }) async {
    response.statusCode = isSuccess ? HttpStatus.ok : HttpStatus.badRequest;
    response.headers.contentType = ContentType(
      'text',
      'html',
      charset: 'utf-8',
    );

    const htmlEscape = HtmlEscape();
    final title = htmlEscape.convert(
      isSuccess ? 'Otorisasi Berhasil' : 'Otorisasi Dibatalkan',
    );
    final heading = htmlEscape.convert(
      isSuccess
          ? '✅ Otorisasi Akun Google Berhasil'
          : '⚠️ Otorisasi Dibatalkan',
    );
    final desc = message != null
        ? htmlEscape.convert(message)
        : (isSuccess
              ? 'Aplikasi <strong>Cek PBB Cianjur</strong> telah terhubung dengan akun Google dan Google Drive Anda.<br><br><strong>Silakan tutup tab atau jendela browser ini dan kembali ke aplikasi.</strong>'
              : 'Proses otorisasi akun Google dibatalkan atau ditolak. Anda dapat menutup tab ini.');

    final html =
        '''<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cek PBB Cianjur - $title</title>
  <style>
    body {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Ubuntu, sans-serif;
      background: ${isSuccess ? '#f0fdf4' : '#fff1f2'};
      color: #1e293b;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      padding: 16px;
      box-sizing: border-box;
    }
    .card {
      background: white;
      border-radius: 16px;
      padding: 36px 28px;
      max-width: 440px;
      width: 100%;
      text-align: center;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05);
      border: 1px solid ${isSuccess ? '#bbf7d0' : '#fecdd3'};
    }
    h1 {
      font-size: 20px;
      color: ${isSuccess ? '#166534' : '#9f1239'};
      margin: 0 0 12px;
    }
    p {
      font-size: 14px;
      color: #475569;
      line-height: 1.6;
      margin: 0;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>$heading</h1>
    <p>$desc</p>
  </div>
</body>
</html>''';

    response.write(html);
    await response.close();
  }

  /// Menyusun parameter form-urlencoded untuk penukaran authorization code OAuth Desktop.
  @visibleForTesting
  static Map<String, String> buildDesktopTokenExchangeParams({
    required String clientId,
    required String clientSecret,
    required String authCode,
    required String codeVerifier,
    required String redirectUri,
  }) {
    return <String, String>{
      'client_id': clientId,
      if (clientSecret.trim().isNotEmpty) 'client_secret': clientSecret.trim(),
      'code': authCode,
      'code_verifier': codeVerifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    };
  }

  /// Menyusun parameter form-urlencoded untuk refresh access token OAuth Desktop.
  @visibleForTesting
  static Map<String, String> buildDesktopRefreshTokenParams({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) {
    return <String, String>{
      'client_id': clientId,
      if (clientSecret.trim().isNotEmpty) 'client_secret': clientSecret.trim(),
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };
  }

  static String _encodeFormBody(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }

  /// Memutuskan sambungan akun Google (Sign Out).
  Future<void> signOut() async {
    await cancelPendingDesktopSignIn();
    if (isSupportedPlatform &&
        (Platform.isAndroid || Platform.isIOS || kIsWeb)) {
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Gagal sign out dari Google: $e');
      }
    }
    await GoogleAccountSyncService.instance.clearLocalBackupMasterKey();
    await BlokBackupScheduler.instance.setGoogleAccountDetails(email: '');
  }

  /// Memperbarui access token desktop menggunakan refresh token yang tersimpan di penyimpanan aman.
  Future<String?> refreshDesktopAccessToken() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      return null;
    }
    final refreshToken = await BlokBackupScheduler.instance
        .getGoogleDesktopRefreshToken();
    if (refreshToken.isEmpty) return null;

    final httpClient = HttpClient();
    try {
      final tokenReq = await httpClient.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      tokenReq.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      final tokenParams = buildDesktopRefreshTokenParams(
        clientId: _desktopClientId,
        clientSecret: _desktopClientSecret,
        refreshToken: refreshToken,
      );
      tokenReq.write(_encodeFormBody(tokenParams));
      final tokenRes = await tokenReq.close().timeout(
        const Duration(seconds: 15),
      );
      final tokenBody = await tokenRes.transform(utf8.decoder).join();
      if (tokenRes.statusCode != 200) {
        debugPrint('Gagal refresh token Google Desktop (${tokenRes.statusCode})');
        return null;
      }
      final tokenJson = jsonDecode(tokenBody) as Map<String, dynamic>;
      final newAccessToken = tokenJson['access_token'] as String? ?? '';
      final newRefreshToken = tokenJson['refresh_token'] as String?;
      if (newAccessToken.isEmpty) return null;

      await BlokBackupScheduler.instance.setGoogleDesktopTokens(
        accessToken: newAccessToken,
        refreshToken: (newRefreshToken != null && newRefreshToken.isNotEmpty)
            ? newRefreshToken
            : refreshToken,
      );
      return newAccessToken;
    } catch (e) {
      debugPrint('Error saat refresh token Google Desktop: $e');
      return null;
    } finally {
      httpClient.close(force: true);
    }
  }

  /// Mendapatkan HTTP headers otentikasi (Bearer token) untuk sinkronisasi Google Drive.
  Future<Map<String, String>?> getAuthHeaders({
    bool interactiveIfNeeded = false,
    bool forceRefresh = false,
  }) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      var token = forceRefresh
          ? (await refreshDesktopAccessToken() ?? '')
          : await BlokBackupScheduler.instance.getGoogleDesktopAccessToken();
      if (token.isEmpty && !forceRefresh) {
        token = await refreshDesktopAccessToken() ?? '';
      }
      if (token.isEmpty) return null;
      return {'Authorization': 'Bearer $token'};
    }
    var account =
        _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null && interactiveIfNeeded) {
      final savedEmail = await BlokBackupScheduler.instance.getGoogleAccount();
      if (savedEmail.isNotEmpty) {
        AppSecurityService.instance.setTemporaryLockBypass(true);
        try {
          account = await _googleSignIn.signIn();
        } catch (_) {
        } finally {
          AppSecurityService.instance.setTemporaryLockBypass(false);
        }
      }
    }
    if (account == null) return null;
    if (forceRefresh) {
      try {
        await account.clearAuthCache();
      } catch (_) {}
    }
    if (interactiveIfNeeded &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS)) {
      AppSecurityService.instance.setTemporaryLockBypass(true);
      try {
        await _googleSignIn.requestScopes(_scopes);
        final refreshed = _googleSignIn.currentUser;
        if (refreshed != null) {
          account = refreshed;
        }
      } catch (_) {
      } finally {
        AppSecurityService.instance.setTemporaryLockBypass(false);
      }
    }
    return account?.authHeaders;
  }
}
