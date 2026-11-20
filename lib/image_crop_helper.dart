import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// Helper untuk memotong (crop) gambar otomatis menjadi rasio 1:1 (persegi/square)
/// dari bagian tengah (center crop), sehingga hasil foto dokumen seragam dan rapi.
class ImageCropHelper {
  ImageCropHelper._();

  static bool get _canUseIsolate {
    try {
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      return !bindingName.contains('Test');
    } catch (_) {
      return true;
    }
  }

  /// Memotong [rawBytes] gambar menjadi rasio 1:1 (persegi) di background isolate
  /// dengan pembatasan resolusi [maxDimension] agar tidak membekukan UI atau memicu OOM.
  static Future<Uint8List> cropToSquareAsync(
    Uint8List rawBytes, {
    int maxDimension = 1024,
  }) async {
    if (rawBytes.isEmpty) return rawBytes;
    if (_canUseIsolate) {
      return Isolate.run(
        () => cropToSquare(rawBytes, maxDimension: maxDimension),
      );
    }
    return cropToSquare(rawBytes, maxDimension: maxDimension);
  }

  /// Memotong [rawBytes] gambar menjadi rasio 1:1 (persegi) secara otomatis
  /// dan mengecilkan dimensi maksimal ke [maxDimension] bila melebihi batas.
  static Uint8List cropToSquare(
    Uint8List rawBytes, {
    int maxDimension = 1024,
  }) {
    if (rawBytes.isEmpty) return rawBytes;

    try {
      final image = img.decodeImage(rawBytes);
      if (image == null) return rawBytes;

      final width = image.width;
      final height = image.height;
      final size = min(width, height);

      // Jika sudah persegi dan ukurannya sudah di bawah batas, tidak perlu diproses ulang
      if (width == height && (maxDimension <= 0 || size <= maxDimension)) {
        return rawBytes;
      }

      var processed = (width == height)
          ? image
          : img.copyCrop(
              image,
              x: (width - size) ~/ 2,
              y: (height - size) ~/ 2,
              width: size,
              height: size,
            );

      if (maxDimension > 0 && processed.width > maxDimension) {
        processed = img.copyResize(
          processed,
          width: maxDimension,
          height: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      }

      // Encode kembali ke JPEG dengan kualitas optimal
      final encoded = img.encodeJpg(processed, quality: 85);
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
      final croppedBytes = await cropToSquareAsync(bytes);
      await file.writeAsBytes(croppedBytes);
    } catch (_) {}
    return file;
  }
}
