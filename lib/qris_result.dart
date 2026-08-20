import 'dart:typed_data';

class QrisResult {
  final Uint8List qrImageBytes;
  final String transactionId;
  final String amount;
  final String expiredAt;

  QrisResult({
    required this.qrImageBytes,
    required this.transactionId,
    required this.amount,
    required this.expiredAt,
  });
}

class QrisGenerationError implements Exception {
  final String message;

  QrisGenerationError(this.message);
}
