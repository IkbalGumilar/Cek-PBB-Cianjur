class VaResult {
  final String virtualAccount;
  final String customerName;
  final String amount;
  final String expiredAt;

  VaResult({
    required this.virtualAccount,
    required this.customerName,
    required this.amount,
    required this.expiredAt,
  });
}

class VaGenerationError implements Exception {
  final String message;

  VaGenerationError(this.message);
}
