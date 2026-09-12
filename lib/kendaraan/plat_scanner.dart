import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// OCR plat nomor yang diproses sepenuhnya di perangkat.
class PlatScanner {
  PlatScanner({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<PlatScanResult?> scan({required ImageSource source}) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 100,
      maxWidth: 2800,
      maxHeight: 2800,
    );
    if (image == null) return null;
    return scanImage(image);
  }

  Future<PlatScanResult> scanImage(XFile image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final candidates = PlatScanParser.extractCandidates(recognizedText.text);
      final color = await PlatColorDetector.detect(
        image.readAsBytes,
        recognizedText.blocks,
      );
      return PlatScanResult(candidates: candidates, color: color);
    } finally {
      await recognizer.close();
    }
  }
}

class PlatScanResult {
  final List<PlatCandidate> candidates;
  final PlatSurfaceColor color;

  const PlatScanResult({required this.candidates, required this.color});

  String get colorMessage => switch (color) {
    PlatSurfaceColor.black => 'TNKB hitam terdeteksi.',
    PlatSurfaceColor.white =>
      'TNKB putih terdeteksi dan dipetakan sebagai plat pribadi.',
    PlatSurfaceColor.unknown => 'Warna TNKB belum dapat dipastikan.',
  };
}

class PlatCandidate {
  final String front;
  final String number;
  final String back;
  final double score;

  const PlatCandidate({
    required this.front,
    required this.number,
    required this.back,
    required this.score,
  });

  String get formatted => '$front $number $back';

  String get key => '$front|$number|$back';
}

/// Parser format Indonesia: kode wilayah, angka, lalu kode belakang.
///
/// Parser sengaja tidak membatasi daftar wilayah karena foto dapat berasal
/// dari luar Jawa Barat. Validasi wilayah tetap dilakukan oleh layanan PKB.
class PlatScanParser {
  static const _maxAlternatives = 24;
  static const _maxResults = 6;

  static List<PlatCandidate> extractCandidates(String text) {
    final candidates = <String, PlatCandidate>{};
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (final line in lines) {
      final contextScore = _contextScore(line);
      _extractFromSequence(_compact(line), contextScore, candidates);
    }

    // Pada teks satu baris, rangkaian tanpa pemisah membantu ketika OCR
    // membaca plat sebagai satu token. Pada teks multiline, setiap baris
    // diproses sendiri agar tanggal kecil di bawah plat tidak ikut tersambung.
    if (!RegExp(r'[\r\n]').hasMatch(text)) {
      _extractFromSequence(_compact(text), 0, candidates);
    }

    if (candidates.isEmpty) return const [];
    final sorted = candidates.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.key.compareTo(b.key) : score;
      });
    final bestScore = sorted.first.score;
    return sorted
        .where((candidate) => candidate.score >= bestScore - 2.6)
        .take(_maxResults)
        .toList(growable: false);
  }

  static String _compact(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static double _contextScore(String line) {
    return RegExp(
          r'\b(plat|tnkb|nomor|kendaraan|polisi)\b',
          caseSensitive: false,
        ).hasMatch(line)
        ? 4
        : 0;
  }

  static void _extractFromSequence(
    String sequence,
    double contextScore,
    Map<String, PlatCandidate> candidates,
  ) {
    if (sequence.length < 3) return;
    for (var start = 0; start < sequence.length; start++) {
      for (var frontLength = 1; frontLength <= 2; frontLength++) {
        for (var numberLength = 1; numberLength <= 4; numberLength++) {
          for (var backLength = 1; backLength <= 3; backLength++) {
            final end = start + frontLength + numberLength + backLength;
            if (end > sequence.length) continue;
            final front = sequence.substring(start, start + frontLength);
            final number = sequence.substring(
              start + frontLength,
              start + frontLength + numberLength,
            );
            final back = sequence.substring(
              start + frontLength + numberLength,
              end,
            );
            _addConversions(front, number, back, contextScore, candidates);
          }
        }
      }
    }
  }

  static void _addConversions(
    String front,
    String number,
    String back,
    double contextScore,
    Map<String, PlatCandidate> candidates,
  ) {
    // Tanggal seperti "01-22" tidak memiliki huruf mentah. Menolaknya
    // mencegah koreksi karakter ambigu menghasilkan plat palsu.
    if (!RegExp(r'[A-Z]').hasMatch(front + back)) return;
    final frontOptions = _expand(front, _frontOptions, exactLetters: true);
    final numberOptions = _expand(number, _numberOptions, exactDigits: true);
    final backOptions = _expand(back, _backOptions, exactLetters: true);
    for (final frontOption in frontOptions) {
      for (final numberOption in numberOptions) {
        for (final backOption in backOptions) {
          final value = numberOption.value;
          if (value.length > 1 && value.startsWith('0')) continue;
          final score =
              contextScore +
              frontOption.score +
              numberOption.score +
              backOption.score +
              _formatScore(frontOption.value, value, backOption.value);
          if (score < 1) continue;
          final candidate = PlatCandidate(
            front: frontOption.value,
            number: value,
            back: backOption.value,
            score: score,
          );
          final previous = candidates[candidate.key];
          if (previous == null || candidate.score > previous.score) {
            candidates[candidate.key] = candidate;
          }
        }
      }
    }
  }

  static double _formatScore(String front, String number, String back) {
    var score = 0.0;
    if (front.length == 1) score += 0.7;
    if (number.length >= 2) score += 0.6;
    if (back.isNotEmpty) score += 0.5;
    if (_commonIndonesianPrefix.contains(front)) score += 1.7;
    return score;
  }

  static List<_PlateOption> _expand(
    String value,
    Map<String, List<_PlateOption>> options, {
    bool exactLetters = false,
    bool exactDigits = false,
  }) {
    var result = const <_PlateOption>[_PlateOption(value: '', score: 0)];
    for (final character in value.split('')) {
      final alternatives =
          options[character] ??
          (exactLetters && RegExp(r'[A-Z]').hasMatch(character)
              ? [_PlateOption(value: character, score: 1)]
              : exactDigits && RegExp(r'\d').hasMatch(character)
              ? [_PlateOption(value: character, score: 1)]
              : const <_PlateOption>[]);
      if (alternatives.isEmpty) return const [];
      final next = <_PlateOption>[];
      for (final prefix in result) {
        for (final alternative in alternatives) {
          next.add(
            _PlateOption(
              value: '${prefix.value}${alternative.value}',
              score: prefix.score + alternative.score,
            ),
          );
        }
      }
      next.sort((a, b) => b.score.compareTo(a.score));
      result = next.take(_maxAlternatives).toList(growable: false);
    }
    return result;
  }

  static const _frontOptions = <String, List<_PlateOption>>{
    '0': [
      _PlateOption(value: 'O', score: 0.35),
      _PlateOption(value: 'D', score: 0.25),
    ],
    '1': [
      _PlateOption(value: 'I', score: 0.35),
      _PlateOption(value: 'L', score: 0.3),
    ],
    '2': [_PlateOption(value: 'Z', score: 0.35)],
    '5': [_PlateOption(value: 'S', score: 0.35)],
    '6': [_PlateOption(value: 'G', score: 0.3)],
    '8': [_PlateOption(value: 'B', score: 0.35)],
  };

  static const _numberOptions = <String, List<_PlateOption>>{
    '0': [
      _PlateOption(value: '0', score: 1),
      _PlateOption(value: '8', score: 0.2),
    ],
    '1': [
      _PlateOption(value: '1', score: 1),
      _PlateOption(value: '7', score: 0.2),
    ],
    '2': [
      _PlateOption(value: '2', score: 1),
      _PlateOption(value: '7', score: 0.2),
    ],
    '3': [
      _PlateOption(value: '3', score: 1),
      _PlateOption(value: '8', score: 0.2),
    ],
    '4': [
      _PlateOption(value: '4', score: 1),
      _PlateOption(value: '1', score: 0.2),
    ],
    '5': [
      _PlateOption(value: '5', score: 1),
      _PlateOption(value: '8', score: 0.2),
    ],
    '6': [
      _PlateOption(value: '6', score: 1),
      _PlateOption(value: '8', score: 0.2),
    ],
    '7': [
      _PlateOption(value: '7', score: 1),
      _PlateOption(value: '1', score: 0.2),
    ],
    '8': [
      _PlateOption(value: '8', score: 1),
      _PlateOption(value: '0', score: 0.2),
    ],
    '9': [
      _PlateOption(value: '9', score: 1),
      _PlateOption(value: '0', score: 0.2),
    ],
    'O': [
      _PlateOption(value: '0', score: 0.45),
      _PlateOption(value: '8', score: 0.2),
    ],
    'Q': [
      _PlateOption(value: '0', score: 0.35),
      _PlateOption(value: '9', score: 0.2),
    ],
    'D': [
      _PlateOption(value: '0', score: 0.35),
      _PlateOption(value: '8', score: 0.2),
    ],
    'I': [
      _PlateOption(value: '1', score: 0.45),
      _PlateOption(value: '7', score: 0.2),
    ],
    'L': [
      _PlateOption(value: '1', score: 0.45),
      _PlateOption(value: '7', score: 0.2),
    ],
    'T': [
      _PlateOption(value: '1', score: 0.4),
      _PlateOption(value: '7', score: 0.2),
    ],
    'Z': [
      _PlateOption(value: '2', score: 0.45),
      _PlateOption(value: '7', score: 0.2),
    ],
    'S': [
      _PlateOption(value: '5', score: 0.45),
      _PlateOption(value: '8', score: 0.2),
    ],
    'B': [
      _PlateOption(value: '8', score: 0.45),
      _PlateOption(value: '6', score: 0.2),
    ],
    'G': [
      _PlateOption(value: '6', score: 0.4),
      _PlateOption(value: '9', score: 0.2),
    ],
  };

  static const _backOptions = <String, List<_PlateOption>>{
    '0': [_PlateOption(value: 'O', score: 0.35)],
    '1': [
      _PlateOption(value: 'I', score: 0.35),
      _PlateOption(value: 'L', score: 0.3),
    ],
    '2': [_PlateOption(value: 'Z', score: 0.35)],
    '5': [_PlateOption(value: 'S', score: 0.35)],
    '6': [_PlateOption(value: 'G', score: 0.3)],
    '7': [_PlateOption(value: 'T', score: 0.3)],
    '8': [_PlateOption(value: 'B', score: 0.35)],
  };

  static const _commonIndonesianPrefix = <String>{
    'A',
    'B',
    'D',
    'E',
    'F',
    'G',
    'H',
    'K',
    'L',
    'M',
    'N',
    'P',
    'R',
    'S',
    'T',
    'W',
    'Z',
    'AB',
    'AD',
    'AE',
    'AG',
    'BD',
    'BK',
    'BL',
    'BM',
    'BN',
    'BP',
    'BO',
    'BG',
    'BH',
    'DK',
    'DR',
    'EA',
    'EB',
    'ED',
    'KB',
    'KH',
    'KU',
    'DB',
    'DC',
    'DD',
    'DE',
    'DG',
    'DH',
    'DM',
    'DN',
    'DT',
    'DL',
    'DS',
    'KT',
    'PA',
    'PB',
    'PC',
    'PD',
    'PE',
    'PF',
    'PG',
    'PH',
    'RI',
    'SL',
    'SN',
    'SR',
    'SS',
    'ST',
    'SU',
    'UB',
    'VE',
    'Y',
  };
}

class _PlateOption {
  final String value;
  final double score;

  const _PlateOption({required this.value, required this.score});
}

enum PlatSurfaceColor { black, white, unknown }

class PlatColorDetector {
  static Future<PlatSurfaceColor> detect(
    Future<Uint8List> Function() readBytes,
    List<TextBlock> blocks,
  ) async {
    final plateBlock = _findPlateBlock(blocks);
    if (plateBlock == null) return PlatSurfaceColor.unknown;

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? frameImage;
    try {
      final bytes = await readBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      frameImage = frame.image;
      final byteData = await frameImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return PlatSurfaceColor.unknown;
      return _classify(
        byteData,
        frameImage.width,
        frameImage.height,
        plateBlock.boundingBox,
      );
    } catch (_) {
      return PlatSurfaceColor.unknown;
    } finally {
      frameImage?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static TextBlock? _findPlateBlock(List<TextBlock> blocks) {
    TextBlock? selected;
    var selectedScore = -double.infinity;
    for (final block in blocks) {
      final candidates = PlatScanParser.extractCandidates(block.text);
      final score = candidates.isEmpty
          ? -double.infinity
          : candidates.first.score + block.boundingBox.width / 10000;
      if (score > selectedScore) {
        selected = block;
        selectedScore = score;
      }
    }
    return selected;
  }

  static PlatSurfaceColor _classify(
    ByteData data,
    int width,
    int height,
    ui.Rect textBounds,
  ) {
    final marginX = math.max(textBounds.width * 0.2, 12.0);
    final marginY = math.max(textBounds.height * 1.5, 18.0);
    final left = math.max(0, (textBounds.left - marginX).floor());
    final top = math.max(0, (textBounds.top - marginY).floor());
    final right = math.min(width, (textBounds.right + marginX).ceil());
    final bottom = math.min(height, (textBounds.bottom + marginY).ceil());
    if (right <= left || bottom <= top) return PlatSurfaceColor.unknown;

    var dark = 0;
    var light = 0;
    var samples = 0;
    final stepX = math.max(1, (right - left) ~/ 80);
    final stepY = math.max(1, (bottom - top) ~/ 40);
    for (var y = top; y < bottom; y += stepY) {
      for (var x = left; x < right; x += stepX) {
        final index = (y * width + x) * 4;
        final red = data.getUint8(index);
        final green = data.getUint8(index + 1);
        final blue = data.getUint8(index + 2);
        final luminance = (red * 299 + green * 587 + blue * 114) ~/ 1000;
        if (luminance < 70) dark++;
        if (luminance > 185) light++;
        samples++;
      }
    }
    if (samples == 0) return PlatSurfaceColor.unknown;
    final darkRatio = dark / samples;
    final lightRatio = light / samples;
    if (darkRatio >= 0.48 && darkRatio > lightRatio + 0.12) {
      return PlatSurfaceColor.black;
    }
    if (lightRatio >= 0.48 && lightRatio > darkRatio + 0.12) {
      return PlatSurfaceColor.white;
    }
    return PlatSurfaceColor.unknown;
  }
}
