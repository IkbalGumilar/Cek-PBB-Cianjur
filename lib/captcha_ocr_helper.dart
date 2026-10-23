import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Helper untuk mengenali teks pada gambar Captcha menggunakan Google ML Kit Text Recognition.
class CaptchaOcrHelper {
  /// Runner tiruan untuk pengujian otomatis (unit/widget test) di lingkungan
  /// desktop/CI di mana Google ML Kit native binary tidak tersedia.
  @visibleForTesting
  static Future<String?> Function(Uint8List bytes)? ocrRunnerForTesting;

  /// Membaca teks captcha dari [bytes] gambar.
  ///
  /// Hanya berjalan aktif pada platform Android dan iOS di mana Google ML Kit
  /// didukung secara native. Pada platform desktop/web atau jika terjadi kesalahan
  /// pemrosesan, metode ini akan mengembalikan `null` dengan aman tanpa melempar exception.
  static Future<String?> recognizeCaptcha(Uint8List bytes) async {
    if (ocrRunnerForTesting != null) {
      final mockResult = await ocrRunnerForTesting!(bytes);
      return mockResult != null ? cleanCaptchaText(mockResult) : null;
    }

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return null;
    }

    File? tempFile;
    TextRecognizer? recognizer;
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/captcha_ocr_${DateTime.now().microsecondsSinceEpoch}.png';
      tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes, flush: true);

      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizedText = await recognizer.processImage(inputImage);

      return cleanCaptchaText(recognizedText.text);
    } catch (e) {
      debugPrint('CaptchaOcrHelper: Gagal memproses OCR captcha: $e');
      return null;
    } finally {
      try {
        await recognizer?.close();
      } catch (_) {}
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Membersihkan hasil pembacaan OCR:
  /// - Mengubah huruf menjadi huruf kecil (lowercase).
  /// - Menghilangkan spasi, tanda baca, simbol, dan baris baru.
  /// - Mengembalikan teks bersih atau `null` jika tidak ada karakter valid.
  static String? cleanCaptchaText(String raw) {
    if (raw.trim().isEmpty) return null;
    final cleaned = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }
}
