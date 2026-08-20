import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'download_helper.dart';

class DocumentPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String fileName;

  const DocumentPreviewScreen({super.key, required this.pdfBytes, required this.fileName});

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await DownloadHelper.saveBytes(pdfBytes, fileName);
      messenger.showSnackBar(SnackBar(content: Text('Tersimpan di $location')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        pdfFileName: fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        actions: [
          PdfPreviewAction(
            icon: const Icon(Icons.download),
            onPressed: (context, build, format) => _download(context),
          ),
        ],
      ),
    );
  }
}
