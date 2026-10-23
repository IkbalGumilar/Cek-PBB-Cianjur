import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Kelas dasar abstrak (inheritance) untuk semua scanner berbasis kamera & OCR.
///
/// Menangani alur ImagePicker, resolusi foto, penanganan foto yang tertunda
/// di Android saat low-memory (lost data recovery), serta daur hidup Google MLKit
/// TextRecognizer agar tidak terjadi memory leak.
abstract class BaseOcrScanner<T> {
  final ImagePicker picker;

  BaseOcrScanner({ImagePicker? picker}) : picker = picker ?? ImagePicker();

  /// Batas resolusi maksimal gambar sebelum diproses oleh TextRecognizer.
  int get maxWidth => 1920;
  int get maxHeight => 1920;

  /// Buka kamera atau galeri untuk mengambil foto dan menjalankan OCR.
  Future<T?> scan({required ImageSource source}) async {
    final image = await picker.pickImage(
      source: source,
      imageQuality: 100,
      maxWidth: maxWidth.toDouble(),
      maxHeight: maxHeight.toDouble(),
    );
    if (image == null) return null;
    return scanImage(image);
  }

  /// Jalankan OCR pada berkas [XFile] yang sudah ada.
  Future<T> scanImage(XFile image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      return await parseRecognizedText(image, recognizedText);
    } finally {
      await recognizer.close();
    }
  }

  /// Ambil kembali hasil foto jika sistem Android mematikan Activity kamera saat low-memory.
  Future<T?> recoverLostScan() async {
    final response = await picker.retrieveLostData();
    if (response.isEmpty) return null;
    if (response.exception != null) throw response.exception!;
    final image = response.file;
    if (image == null) return null;
    return scanImage(image);
  }

  /// Template method: anak kelas mewarisi seluruh alur scan di atas dan HANYA
  /// wajib mengimplementasikan logika ekstraksi data spesifiknya.
  Future<T> parseRecognizedText(XFile image, RecognizedText recognizedText);
}
