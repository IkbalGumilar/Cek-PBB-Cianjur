import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../base_ocr_scanner.dart';

/// OCR NIK yang seluruh proses pengenalan dan koreksinya dilakukan lokal.
class NikScanner extends BaseOcrScanner<List<String>> {
  NikScanner({super.picker});

  @override
  int get maxWidth => 2400;

  @override
  int get maxHeight => 2400;

  @override
  Future<List<String>> parseRecognizedText(
    XFile image,
    RecognizedText recognizedText,
  ) async {
    return NikScanParser.extract(recognizedText.text);
  }
}

class NikScanParser {
  static const _maxCandidatesPerSequence = 32;
  static const _digitAlternatives = <String, List<_DigitAlternative>>{
    // Angka juga diberi alternatif karena font kotak dapat membuat satu
    // angka terbaca sebagai angka lain, misalnya 1 menjadi 3.
    '0': [
      _DigitAlternative('0', 0.72),
      _DigitAlternative('6', 0.10),
      _DigitAlternative('8', 0.10),
      _DigitAlternative('9', 0.08),
    ],
    '1': [
      _DigitAlternative('1', 0.72),
      _DigitAlternative('3', 0.12),
      _DigitAlternative('7', 0.10),
      _DigitAlternative('4', 0.06),
    ],
    '2': [
      _DigitAlternative('2', 0.75),
      _DigitAlternative('7', 0.10),
      _DigitAlternative('3', 0.10),
      _DigitAlternative('8', 0.05),
    ],
    '3': [
      _DigitAlternative('3', 0.72),
      _DigitAlternative('1', 0.10),
      _DigitAlternative('8', 0.10),
      _DigitAlternative('5', 0.08),
    ],
    '4': [
      _DigitAlternative('4', 0.75),
      _DigitAlternative('1', 0.10),
      _DigitAlternative('7', 0.08),
      _DigitAlternative('9', 0.07),
    ],
    '5': [
      _DigitAlternative('5', 0.72),
      _DigitAlternative('6', 0.10),
      _DigitAlternative('8', 0.10),
      _DigitAlternative('3', 0.08),
    ],
    '6': [
      _DigitAlternative('6', 0.72),
      _DigitAlternative('5', 0.10),
      _DigitAlternative('8', 0.10),
      _DigitAlternative('0', 0.08),
    ],
    '7': [
      _DigitAlternative('7', 0.72),
      _DigitAlternative('1', 0.12),
      _DigitAlternative('2', 0.10),
      _DigitAlternative('9', 0.06),
    ],
    '8': [
      _DigitAlternative('8', 0.72),
      _DigitAlternative('3', 0.10),
      _DigitAlternative('0', 0.10),
      _DigitAlternative('6', 0.08),
    ],
    '9': [
      _DigitAlternative('9', 0.72),
      _DigitAlternative('0', 0.10),
      _DigitAlternative('3', 0.10),
      _DigitAlternative('8', 0.08),
    ],
    'O': [_DigitAlternative('0', 0.90), _DigitAlternative('8', 0.10)],
    'Q': [_DigitAlternative('9', 0.70), _DigitAlternative('0', 0.30)],
    'D': [
      _DigitAlternative('0', 0.55),
      _DigitAlternative('8', 0.30),
      _DigitAlternative('1', 0.15),
    ],
    'I': [_DigitAlternative('1', 0.90), _DigitAlternative('7', 0.10)],
    'L': [_DigitAlternative('1', 0.90), _DigitAlternative('7', 0.10)],
    'T': [_DigitAlternative('1', 0.85), _DigitAlternative('7', 0.15)],
    'Z': [_DigitAlternative('2', 0.85), _DigitAlternative('7', 0.15)],
    'E': [_DigitAlternative('3', 0.85), _DigitAlternative('8', 0.15)],
    'A': [_DigitAlternative('4', 0.85), _DigitAlternative('9', 0.15)],
    'S': [_DigitAlternative('5', 0.90), _DigitAlternative('8', 0.10)],
    'G': [_DigitAlternative('6', 0.60), _DigitAlternative('9', 0.40)],
    'B': [
      _DigitAlternative('8', 0.55),
      _DigitAlternative('6', 0.25),
      _DigitAlternative('0', 0.20),
    ],
  };

  /// Mengambil kandidat NIK dengan urutan dari yang paling meyakinkan.
  static List<NikCandidate> extractCandidates(String text) {
    final candidates = <String, NikCandidate>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final sequence = line.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
      final contextScore =
          RegExp(r'\bNIK\b', caseSensitive: false).hasMatch(line) ? 8.0 : 0.0;
      _extractSequence(sequence, contextScore, candidates);
    }

    for (final match in RegExp(r'[0-9A-Za-z]{16,}').allMatches(text)) {
      _extractSequence(match.group(0)!, 0.0, candidates);
    }

    final result = candidates.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.value.compareTo(b.value) : score;
      });
    return result;
  }

  /// Mengambil nilai NIK saja untuk pemanggil lama dan pengujian parser.
  ///
  static List<String> extract(String text) {
    return extractCandidates(text).map((candidate) => candidate.value).toList();
  }

  static void _extractSequence(
    String sequence,
    double contextScore,
    Map<String, NikCandidate> candidates,
  ) {
    if (sequence.length < 16) return;
    for (var start = 0; start <= sequence.length - 16; start++) {
      final window = sequence.substring(start, start + 16).toUpperCase();
      final expandDigits = RegExp(r'[A-Za-z]').hasMatch(window);
      for (final conversion in _convert(window, expandDigits: expandDigits)) {
        final score =
            contextScore + conversion.score + _structureScore(conversion.value);
        final candidate = NikCandidate(value: conversion.value, score: score);
        final previous = candidates[conversion.value];
        if (previous == null || candidate.score > previous.score) {
          candidates[conversion.value] = candidate;
        }
      }
    }
  }

  static List<_Conversion> _convert(
    String value, {
    required bool expandDigits,
  }) {
    var choices = const <_Conversion>[_Conversion(value: '', score: 0)];
    for (final character in value.split('')) {
      final alternatives = RegExp(r'\d').hasMatch(character) && !expandDigits
          ? [_DigitAlternative(character, 1)]
          : _digitAlternatives[character];
      if (alternatives == null) return const [];

      final next = <_Conversion>[];
      for (final prefix in choices) {
        for (final alternative in alternatives) {
          next.add(
            _Conversion(
              value: '${prefix.value}${alternative.digit}',
              score: prefix.score + _logWeight(alternative.weight),
            ),
          );
        }
      }
      next.sort((a, b) => b.score.compareTo(a.score));
      choices = next.take(_maxCandidatesPerSequence).toList(growable: false);
    }
    return choices;
  }

  static double _structureScore(String value) {
    final day = int.tryParse(value.substring(6, 8));
    final month = int.tryParse(value.substring(8, 10));
    var score = 0.0;
    if (day != null && (day >= 1 && day <= 31 || day >= 41 && day <= 71)) {
      score += 4;
    } else {
      score -= 5;
    }
    if (month != null && month >= 1 && month <= 12) {
      score += 4;
    } else {
      score -= 5;
    }
    return score;
  }

  static double _logWeight(double weight) {
    return math.log(weight);
  }
}

class NikCandidate {
  final String value;
  final double score;

  const NikCandidate({required this.value, required this.score});
}

class _DigitAlternative {
  final String digit;
  final double weight;

  const _DigitAlternative(this.digit, this.weight);
}

class _Conversion {
  final String value;
  final double score;

  const _Conversion({required this.value, required this.score});
}
