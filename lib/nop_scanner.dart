import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'nop_helper.dart';

class NopScanner {
  NopScanner({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<List<String>?> scan({required ImageSource source}) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 100,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (image == null) return null;
    return scanImage(image);
  }

  Future<List<String>> scanImage(XFile image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      return NopScanParser.extract(recognizedText.text);
    } finally {
      await recognizer.close();
    }
  }

  Future<List<String>?> recoverLostScan() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;
    if (response.exception != null) throw response.exception!;
    final image = response.file;
    if (image == null) return null;
    return scanImage(image);
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
