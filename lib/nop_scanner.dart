import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'base_ocr_scanner.dart';
import 'nop_helper.dart';

/// Scanner OCR untuk membaca dan mengekstrak NOP dari foto SPPT.
///
/// Mewarisi [BaseOcrScanner] untuk mengelola lifecycle kamera, recovery low-memory,
/// dan pemrosesan MLKit secara terpusat alih-alih menduplikasi fungsionalitas.
class NopScanner extends BaseOcrScanner<List<String>> {
  NopScanner({super.picker});

  @override
  int get maxWidth => 2200;

  @override
  int get maxHeight => 2200;

  @override
  Future<List<String>> parseRecognizedText(
    XFile image,
    RecognizedText recognizedText,
  ) async {
    return NopScanParser.extract(recognizedText.text);
  }
}

class NopScanParser {
  static List<String> extract(String text) {
    final found = <String>{};

    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final compact = line.replaceAll(RegExp(r'[^0-9]'), '');
      final prefixIndex = compact.indexOf(nopPrefix);
      if (prefixIndex != -1 && compact.length - prefixIndex >= 18) {
        final candidate = compact.substring(prefixIndex, prefixIndex + 18);
        if (candidate.endsWith('0')) found.add(candidate);
      }
    }

    for (final match in RegExp(r'\d{5,18}').allMatches(text)) {
      final value = match.group(0)!;
      if (value.length == 18 && value.startsWith(nopPrefix)) {
        if (value.endsWith('0')) found.add(value);
      } else if (_isShortNop(text, match)) {
        found.add(expandNop(value));
      }
    }

    return found.toList()..sort();
  }

  static bool _isShortNop(String text, RegExpMatch match) {
    final value = match.group(0)!;
    if (value.length < 5 || value.length > 7) return false;
    final before = text.substring(
      match.start > 40 ? match.start - 40 : 0,
      match.start,
    );
    final after = text.substring(
      match.end,
      match.end + 40 > text.length ? text.length : match.end + 40,
    );
    final context = '$before $after'.toLowerCase();
    final hasNopContext = RegExp(
      r'\b(nop|sppt|blok|objek pajak|nomor wilayah)\b',
    ).hasMatch(context);
    final isBracketed =
        before.trimRight().endsWith('[') && after.trimLeft().startsWith(']');
    return hasNopContext || isBracketed;
  }
}
