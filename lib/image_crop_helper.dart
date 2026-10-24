import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Helper untuk memotong (crop) gambar otomatis menjadi rasio 1:1 (persegi/square)
/// dari bagian tengah (center crop), sehingga hasil foto dokumen seragam dan rapi.
class ImageCropHelper {
  ImageCropHelper._();

  /// Memotong [rawBytes] gambar menjadi rasio 1:1 (persegi) secara otomatis.
  /// Jika gambar sudah 1:1, byte dikembalikan apa adanya atau dioptimalkan.
  static Uint8List cropToSquare(Uint8List rawBytes) {
    if (rawBytes.isEmpty) return rawBytes;

    try {
      final image = img.decodeImage(rawBytes);
      if (image == null) return rawBytes;

      final width = image.width;
      final height = image.height;

      // Jika sudah persegi, tidak perlu dicrop
      if (width == height) {
        return rawBytes;
      }

      final size = min(width, height);
      final x = (width - size) ~/ 2;
      final y = (height - size) ~/ 2;

      final cropped = img.copyCrop(
        image,
        x: x,
        y: y,
        width: size,
        height: size,
      );

      // Encode kembali ke JPEG dengan kualitas optimal
      final encoded = img.encodeJpg(cropped, quality: 88);
      return Uint8List.fromList(encoded);
    } catch (e) {
      debugPrint('Gagal melakukan crop 1:1: $e');
      return rawBytes;
    }
  }

  /// Memotong gambar dari [file] dan menyimpan hasilnya kembali.
  static Future<File> cropFileToSquare(File file) async {
    if (!await file.exists()) return file;
    try {
      final bytes = await file.readAsBytes();
      final croppedBytes = cropToSquare(bytes);
      await file.writeAsBytes(croppedBytes);
    } catch (_) {}
    return file;
  }
}
