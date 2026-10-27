import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blok_catatan_screen.dart';
import 'blok_data_store.dart';
import 'dkhp_package_helper.dart';

/// Layanan untuk menangani pembukaan berkas `.dkhp` dan `.dat` secara otomatis
/// saat diklik dari WhatsApp, File Manager, Telegram, atau Unduhan.
class IncomingFileService {
  IncomingFileService._();
  static final instance = IncomingFileService._();

  static const MethodChannel _channel =
      MethodChannel('id.cianjur.cekpbb.cek_pbb_app/incoming_file');

  BuildContext? _activeContext;
  bool _initialized = false;
  bool _isProcessing = false;

  /// Memperbarui [context] yang sedang aktif saat layar berpindah.
  void updateContext(BuildContext context) {
    _activeContext = context;
  }

  /// Menginisialisasi pendengar berkas masuk dari Android Native.
  Future<void> init(BuildContext context) async {
    _activeContext = context;
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) return;

    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onIncomingFile') {
          final filePath = call.arguments as String?;
          if (filePath != null && filePath.isNotEmpty && _activeContext != null) {
            await handleIncomingFile(_activeContext!, filePath);
          }
        }
      });

      // Periksa apakah aplikasi dibuka saat cold-start lewat klik berkas
      final initialFile = await _channel.invokeMethod<String>('getInitialFile');
      if (initialFile != null && initialFile.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_activeContext != null) {
            handleIncomingFile(_activeContext!, initialFile);
          }
        });
      }
    } catch (_) {}
  }

  /// Menampilkan dialog konfirmasi dan memproses berkas yang masuk.
  Future<void> handleIncomingFile(BuildContext context, String filePath) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      final fileName = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'berkas.dkhp';
      final isDat = fileName.toLowerCase().endsWith('.dat');
      final fileSize = await file.length();
      final sizeFormatted = _formatFileSize(fileSize);

      Map<String, dynamic>? manifest;
      try {
        manifest = await DhkpPackageHelper.readBackupManifest(filePath);
      } catch (_) {}

      if (!context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ConfirmIncomingFileDialog(
          fileName: fileName,
          fileSize: sizeFormatted,
          isDat: isDat,
          manifest: manifest,
        ),
      );

      if (confirmed != true || !context.mounted) return;

      await _processImport(context, filePath, isDat);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processImport(
    BuildContext context,
    String filePath,
    bool isDat, {
    String? password,
  }) async {
    if (!context.mounted) return;

    // Tampilkan indikator proses
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Memasang & memperbarui data DHKP...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final records = await DhkpPackageHelper.unpackDkhp(
        filePath,
        password: password,
      );
      await BlokDataStore.instance.loadAll();

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Tutup loading dialog

      final msg = isDat
          ? 'Laporan .dat berhasil dipasang: ${records.length} data diperbarui.'
          : 'Paket DHKP berhasil diimpor: ${records.length} data & dokumentasi dimuat.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Lihat DHKP',
            textColor: Colors.amberAccent,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BlokCatatanScreen(),
                ),
              );
            },
          ),
        ),
      );
    } on DkhpPasswordException {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Tutup loading dialog
      await _promptPassword(context, filePath, isDat);
    } on DhkpBackupValidationException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Tutup loading dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
          title: const Text('Validasi Data Gagal'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Tutup loading dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
          title: const Text('Gagal Membuka Berkas'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _promptPassword(
    BuildContext context,
    String filePath,
    bool isDat,
  ) async {
    final controller = TextEditingController();
    bool obscure = true;

    final pwd = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.lock_rounded, color: Colors.blue, size: 36),
          title: const Text('Kata Sandi Diperlukan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Berkas cadangan ini diproteksi dengan kata sandi. Masukkan kata sandi untuk membukanya:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Kata Sandi',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Buka Berkas'),
            ),
          ],
        ),
      ),
    );

    if (pwd != null && pwd.isNotEmpty && context.mounted) {
      await _processImport(context, filePath, isDat, password: pwd);
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ConfirmIncomingFileDialog extends StatelessWidget {
  final String fileName;
  final String fileSize;
  final bool isDat;
  final Map<String, dynamic>? manifest;

  const _ConfirmIncomingFileDialog({
    required this.fileName,
    required this.fileSize,
    required this.isDat,
    this.manifest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalRecords = manifest?['totalRecords'] ??
        (manifest?['changes'] is List ? (manifest!['changes'] as List).length : null);
    final description = manifest?['description'] as String?;
    final createdAt = manifest?['createdAt'] ?? manifest?['timestamp'];

    return AlertDialog(
      icon: Icon(
        isDat ? Icons.receipt_long_rounded : Icons.inventory_2_rounded,
        size: 40,
        color: isDat ? Colors.teal : Colors.indigo,
      ),
      title: Text(
        isDat ? 'Laporan Pembayaran (.dat)' : 'Paket Data DHKP (.dkhp)',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aplikasi menerima berkas dari WhatsApp / File Manager:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_rounded, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ukuran Berkas: $fileSize',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                  if (totalRecords != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Jumlah Data: $totalRecords baris',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Waktu Ekspor: $createdAt',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Apakah Anda ingin langsung memasang dan memperbarui data aplikasi dengan berkas ini?',
              style: TextStyle(fontSize: 12.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.download_done_rounded, size: 18),
          label: const Text('Pasang & Impor'),
        ),
      ],
    );
  }
}
