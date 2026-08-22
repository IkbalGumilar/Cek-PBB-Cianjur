import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'qris_result.dart';

class QrisViewScreen extends StatefulWidget {
  final QrisResult result;
  final String nop;
  final String tahun;

  const QrisViewScreen({
    super.key,
    required this.result,
    required this.nop,
    required this.tahun,
  });

  @override
  State<QrisViewScreen> createState() => _QrisViewScreenState();
}

class _QrisViewScreenState extends State<QrisViewScreen> {
  double? _originalBrightness;

  @override
  void initState() {
    super.initState();
    _boostBrightness();
  }

  Future<void> _boostBrightness() async {
    try {
      _originalBrightness = await ScreenBrightness().application;
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {
      // Beberapa perangkat/desktop tidak mendukung kontrol brightness; abaikan saja.
    }
  }

  Future<void> _restoreBrightness() async {
    final original = _originalBrightness;
    if (original == null) return;
    try {
      await ScreenBrightness().setApplicationScreenBrightness(original);
    } catch (_) {
      // Sama seperti di atas.
    }
  }

  @override
  void dispose() {
    _restoreBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QRIS Pembayaran PBB')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NOP: ${widget.nop}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Tahun Pajak: ${widget.tahun}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.memory(
                    widget.result.qrImageBytes,
                    width: 260,
                    height: 260,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.result.amount,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('ID Transaksi: ${widget.result.transactionId}'),
                const SizedBox(height: 4),
                Text(
                  widget.result.expiredAt,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Scan QR ini pakai aplikasi dompet digital/mobile banking yang mendukung QRIS.\n'
                  'Berlaku 1 jam dan hanya untuk 1x pembayaran.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
