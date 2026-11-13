import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Model representasi satu akun TOTP (Google Authenticator).
class TotpAccount {
  final String secret; // Base32
  final String name;
  final String issuer;
  final int digits;
  final int intervalSeconds;

  const TotpAccount({
    required this.secret,
    this.name = '',
    this.issuer = '',
    this.digits = 6,
    this.intervalSeconds = 30,
  });

  String get displayName {
    if (issuer.isNotEmpty && name.isNotEmpty && !name.contains(issuer)) {
      return '$issuer ($name)';
    }
    if (name.isNotEmpty) return name;
    if (issuer.isNotEmpty) return issuer;
    return 'Google Authenticator';
  }

  @override
  String toString() =>
      'TotpAccount(name: $name, issuer: $issuer, digits: $digits)';
}

/// Helper murni tanpa dependency eksternal untuk:
/// 1. Decode & encode Base32 (RFC 4648)
/// 2. Generate TOTP code (RFC 6238 / RFC 4226)
/// 3. Perhitungan countdown interval 30 detik
/// 4. Parsing input teks: Secret Key Base32 langsung, `otpauth://` URI,
///    dan migrasi ekspor Google Authenticator (`otpauth-migration://offline?data=...`).
class TotpHelper {
  TotpHelper._();

  static const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Membersihkan input Base32 dari spasi, tanda hubung, huruf kecil, dan padding `=`.
  static String sanitizeBase32(String input) {
    return input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');
  }

  /// Memvalidasi apakah string merupakan Base32 valid.
  static bool isValidBase32(String input) {
    final cleaned = sanitizeBase32(input);
    if (cleaned.length < 8) return false;
    return RegExp(r'^[A-Z2-7]+$').hasMatch(cleaned);
  }

  /// Mendekode string Base32 menjadi bytes.
  static Uint8List base32Decode(String input) {
    final cleaned = sanitizeBase32(input);
    if (cleaned.isEmpty) return Uint8List(0);

    var buffer = 0;
    var bitsLeft = 0;
    final result = <int>[];

    for (var i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      final val = _base32Alphabet.indexOf(char);
      if (val == -1) {
        throw FormatException('Karakter Base32 tidak valid: "$char"');
      }
      buffer = (buffer << 5) | val;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        result.add((buffer >> bitsLeft) & 0xff);
      }
    }
    return Uint8List.fromList(result);
  }

  /// Mengenkode bytes menjadi string Base32 tanpa padding.
  static String base32Encode(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    var buffer = 0;
    var bitsLeft = 0;
    final sb = StringBuffer();

    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        sb.write(_base32Alphabet[(buffer >> bitsLeft) & 0x1f]);
      }
    }
    if (bitsLeft > 0) {
      sb.write(_base32Alphabet[(buffer << (5 - bitsLeft)) & 0x1f]);
    }
    return sb.toString();
  }

  /// Menghitung kode TOTP (HMAC-SHA1) sesuai spesifikasi RFC 6238.
  static String generateTotp({
    required String secretBase32,
    DateTime? time,
    int intervalSeconds = 30,
    int digits = 6,
  }) {
    final secretBytes = base32Decode(secretBase32);
    if (secretBytes.isEmpty) {
      throw const FormatException('Secret key Base32 kosong');
    }

    final targetTime = time ?? DateTime.now().toUtc();
    final epochSeconds = targetTime.millisecondsSinceEpoch ~/ 1000;
    final counter = epochSeconds ~/ intervalSeconds;

    final counterBytes = Uint8List(8);
    final byteData = ByteData.sublistView(counterBytes);
    byteData.setInt64(0, counter, Endian.big);

    final hmac = Hmac(sha1, secretBytes);
    final hash = hmac.convert(counterBytes).bytes;

    final offset = hash[hash.length - 1] & 0x0f;
    final binary =
        ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);

    final modulo = math.pow(10, digits).toInt();
    final otp = binary % modulo;
    return otp.toString().padLeft(digits, '0');
  }

  /// Menghitung sisa detik sebelum kode TOTP kedaluwarsa (1..30).
  static int getRemainingSeconds({DateTime? time, int intervalSeconds = 30}) {
    final targetTime = time ?? DateTime.now().toUtc();
    final epochSeconds = targetTime.millisecondsSinceEpoch ~/ 1000;
    final remainder = epochSeconds % intervalSeconds;
    final remaining = intervalSeconds - remainder;
    return remaining == 0 ? intervalSeconds : remaining;
  }

  /// Menghitung rasio sisa waktu (0.0 .. 1.0) untuk CircularProgressIndicator.
  static double getProgressRatio({DateTime? time, int intervalSeconds = 30}) {
    final rem = getRemainingSeconds(
      time: time,
      intervalSeconds: intervalSeconds,
    );
    return rem / intervalSeconds;
  }

  /// Format kode 6 digit dengan spasi di tengah untuk keterbacaan (contoh: "123 456").
  static String formatCodeWithSpace(String code) {
    if (code.length == 6) {
      return '${code.substring(0, 3)} ${code.substring(3)}';
    }
    return code;
  }

  /// Mengurai berbagai format input yang dimasukkan pengguna:
  /// 1. Tautan ekspor migrasi `otpauth-migration://offline?data=...`
  /// 2. Tautan standar `otpauth://totp/...`
  /// 3. Secret Key Base32 polos (misal `JBSWY3DPEHPK3PXP`)
  static List<TotpAccount> parseImportInput(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) {
      throw const FormatException(
        'Input kunci authenticator tidak boleh kosong',
      );
    }

    // 1. Ekspor Migrasi Google Authenticator (QR Transfer)
    if (input.startsWith('otpauth-migration://offline')) {
      final uri = Uri.tryParse(input);
      if (uri == null) {
        throw const FormatException('Format URI migrasi tidak valid');
      }
      final dataParam = uri.queryParameters['data'];
      if (dataParam == null || dataParam.isEmpty) {
        throw const FormatException(
          'Parameter "data" tidak ditemukan pada tautan migrasi',
        );
      }
      return _parseGoogleMigrationData(dataParam);
    }

    // 2. Format standar otpauth://
    if (input.startsWith('otpauth://')) {
      final uri = Uri.tryParse(input);
      if (uri == null) {
        throw const FormatException('Format URI otpauth tidak valid');
      }
      final secret = uri.queryParameters['secret'];
      if (secret == null || !isValidBase32(secret)) {
        throw const FormatException(
          'Parameter secret tidak ditemukan atau bukan Base32 valid',
        );
      }
      var name = Uri.decodeComponent(uri.path.replaceFirst('/', ''));
      final issuer = uri.queryParameters['issuer'] ?? '';
      final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
      final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;

      return [
        TotpAccount(
          secret: sanitizeBase32(secret),
          name: name,
          issuer: issuer,
          digits: digits,
          intervalSeconds: period,
        ),
      ];
    }

    // 3. Secret Key Base32 Polos
    if (isValidBase32(input)) {
      return [
        TotpAccount(
          secret: sanitizeBase32(input),
          name: 'Portal Staf',
          issuer: 'BAPENDA',
        ),
      ];
    }

    throw const FormatException(
      'Format tidak dikenali. Masukkan Secret Key Base32 (mis. JBSWY3DPEHPK3PXP), '
      'tautan otpauth://, atau tautan ekspor otpauth-migration://.',
    );
  }

  /// Mendekode teks dari berkas gambar yang memuat QR Code (PNG, JPG, WebP, dll).
  /// Bekerja murni dalam Dart di desktop (Windows/Linux) maupun Android.
  /// Mengembalikan `null` jika tidak ditemukan QR Code yang valid pada gambar.
  static String? decodeQrFromImageBytes(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      final rgbaBytes = image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.rgba);
      final pixels = rgbaBytes.buffer.asInt32List(
        rgbaBytes.offsetInBytes,
        rgbaBytes.lengthInBytes ~/ 4,
      );

      final source = RGBLuminanceSource(image.width, image.height, pixels);
      final reader = QRCodeReader();

      // Percobaan 1: HybridBinarizer (optimal untuk mayoritas foto & screenshot)
      try {
        final bitmap = BinaryBitmap(HybridBinarizer(source));
        final result = reader.decode(bitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      // Percobaan 2: GlobalHistogramBinarizer (fallback binarizer)
      try {
        final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
        final result = reader.decode(bitmap);
        if (result.text.isNotEmpty) return result.text;
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Membaca berkas gambar QR Code dan mengurainya langsung menjadi daftar akun TOTP.
  static List<TotpAccount> parseQrImageBytes(Uint8List imageBytes) {
    final text = decodeQrFromImageBytes(imageBytes);
    if (text == null || text.trim().isEmpty) {
      throw const FormatException(
        'Tidak ditemukan QR Code yang terbaca pada berkas gambar yang dipilih. '
        'Pastikan gambar memuat QR Code Google Authenticator yang jelas dan utuh.',
      );
    }
    return parseImportInput(text);
  }

  /// Mengurai protobuf dari parameter data base64 pada migrasi Google Authenticator.
  static List<TotpAccount> _parseGoogleMigrationData(String dataBase64) {
    final sanitizedBase64 = base64.normalize(dataBase64.replaceAll(' ', '+'));
    final bytes = base64Decode(sanitizedBase64);

    final accounts = <TotpAccount>[];
    final offsetRef = [0];

    while (offsetRef[0] < bytes.length) {
      final tag = _readVarint(bytes, offsetRef);
      final fieldNum = tag >> 3;
      final wireType = tag & 0x07;

      if (fieldNum == 1 && wireType == 2) {
        // Repeated OtpParameters
        final otpBytes = _readLengthDelimited(bytes, offsetRef);
        final account = _parseOtpParameters(otpBytes);
        if (account != null) {
          accounts.add(account);
        }
      } else {
        _skipField(wireType, bytes, offsetRef);
      }
    }

    if (accounts.isEmpty) {
      throw const FormatException(
        'Tidak ada akun valid yang ditemukan dalam data ekspor migrasi',
      );
    }
    return accounts;
  }

  static TotpAccount? _parseOtpParameters(Uint8List bytes) {
    final offsetRef = [0];
    Uint8List? secretBytes;
    var name = '';
    var issuer = '';
    var digits = 6;
    var type = 2; // Default 2 = TOTP

    while (offsetRef[0] < bytes.length) {
      final tag = _readVarint(bytes, offsetRef);
      final fieldNum = tag >> 3;
      final wireType = tag & 0x07;

      if (fieldNum == 1 && wireType == 2) {
        // secret bytes
        secretBytes = _readLengthDelimited(bytes, offsetRef);
      } else if (fieldNum == 2 && wireType == 2) {
        // name
        final nameBytes = _readLengthDelimited(bytes, offsetRef);
        name = utf8.decode(nameBytes, allowMalformed: true);
      } else if (fieldNum == 3 && wireType == 2) {
        // issuer
        final issuerBytes = _readLengthDelimited(bytes, offsetRef);
        issuer = utf8.decode(issuerBytes, allowMalformed: true);
      } else if (fieldNum == 5 && wireType == 0) {
        // digits enum (1 = 6 digits, 2 = 8 digits)
        final dVal = _readVarint(bytes, offsetRef);
        digits = dVal == 2 ? 8 : 6;
      } else if (fieldNum == 6 && wireType == 0) {
        // type (1 = HOTP, 2 = TOTP)
        type = _readVarint(bytes, offsetRef);
      } else {
        _skipField(wireType, bytes, offsetRef);
      }
    }

    if (secretBytes == null || secretBytes.isEmpty) return null;
    // Kita utamakan TOTP (atau izinkan default jika type belum diset)
    if (type != 2 && type != 0) return null;

    final base32Secret = base32Encode(secretBytes);
    return TotpAccount(
      secret: base32Secret,
      name: name,
      issuer: issuer,
      digits: digits,
    );
  }

  static int _readVarint(Uint8List bytes, List<int> offsetRef) {
    var result = 0;
    var shift = 0;
    while (offsetRef[0] < bytes.length) {
      final b = bytes[offsetRef[0]++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  static Uint8List _readLengthDelimited(Uint8List bytes, List<int> offsetRef) {
    final length = _readVarint(bytes, offsetRef);
    final start = offsetRef[0];
    final end = start + length;
    if (end > bytes.length) {
      throw const FormatException('Payload terpotong sebelum selesai');
    }
    offsetRef[0] = end;
    return Uint8List.sublistView(bytes, start, end);
  }

  static void _skipField(int wireType, Uint8List bytes, List<int> offsetRef) {
    switch (wireType) {
      case 0:
        _readVarint(bytes, offsetRef);
        break;
      case 1:
        offsetRef[0] += 8;
        break;
      case 2:
        final len = _readVarint(bytes, offsetRef);
        offsetRef[0] += len;
        break;
      case 5:
        offsetRef[0] += 4;
        break;
      default:
        throw FormatException('Wire type tidak didukung: $wireType');
    }
  }
}
