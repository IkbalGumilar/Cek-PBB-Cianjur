import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/image_crop_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crop_helper_test_');
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Uint8List createTestJpeg(int width, int height) {
    final image = img.Image(width: width, height: height);
    // Isi dengan warna solid sederhana
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgba(x, y, 100, 150, 200, 255);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image));
  }

  group('ImageCropHelper Tests', () {
    test('memotong gambar landscape (misal 200x100) menjadi persegi 1:1 (100x100)', () {
      final landscapeBytes = createTestJpeg(200, 100);
      final croppedBytes = ImageCropHelper.cropToSquare(landscapeBytes);

      expect(croppedBytes.isNotEmpty, isTrue);
      final decoded = img.decodeImage(croppedBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(100));
      expect(decoded.height, equals(100));
    });

    test('memotong gambar portrait (misal 100x200) menjadi persegi 1:1 (100x100)', () {
      final portraitBytes = createTestJpeg(100, 200);
      final croppedBytes = ImageCropHelper.cropToSquare(portraitBytes);

      expect(croppedBytes.isNotEmpty, isTrue);
      final decoded = img.decodeImage(croppedBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(100));
      expect(decoded.height, equals(100));
    });

    test('gambar yang sudah 1:1 (misal 120x120) dikembalikan dengan dimensi tetap 120x120', () {
      final squareBytes = createTestJpeg(120, 120);
      final resultBytes = ImageCropHelper.cropToSquare(squareBytes);

      expect(resultBytes, equals(squareBytes));
      final decoded = img.decodeImage(resultBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(120));
      expect(decoded.height, equals(120));
    });

    test('byte kosong dikembalikan aman tanpa error', () {
      final empty = Uint8List(0);
      final result = ImageCropHelper.cropToSquare(empty);
      expect(result.isEmpty, isTrue);
    });

    test('byte acak / rusak dikembalikan aman tanpa exception', () {
      final invalid = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final result = ImageCropHelper.cropToSquare(invalid);
      expect(result, equals(invalid));
    });

    test('cropFileToSquare memotong file gambar di disk menjadi 1:1', () async {
      final file = File('${tempDir.path}/test_foto.jpg');
      await file.writeAsBytes(createTestJpeg(300, 150));

      final croppedFile = await ImageCropHelper.cropFileToSquare(file);
      expect(await croppedFile.exists(), isTrue);

      final bytes = await croppedFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(150));
      expect(decoded.height, equals(150));
    });

    test('cropFileToSquare file tidak ada dikembalikan aman', () async {
      final nonExistent = File('${tempDir.path}/non_existent.jpg');
      final result = await ImageCropHelper.cropFileToSquare(nonExistent);
      expect(result.path, equals(nonExistent.path));
    });
  });
}
