import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'batch_check_screen.dart';
import 'check_mode.dart';
import 'file_importer.dart';
import 'nop_helper.dart';
import 'nop_scanner.dart';
import 'tax_record.dart';

const _draftFileName = 'draft_nop.txt';

const _placeholderExample = '''
Contoh isi (satu NOP per baris, atau dipisah koma):
17154
300584
320520000403000330''';

class ImportView extends StatefulWidget {
  final CheckMode mode;

  const ImportView({super.key, required this.mode});

  @override
  State<ImportView> createState() => _ImportViewState();
}

class _ImportViewState extends State<ImportView> {
  final _tahunController = TextEditingController(text: '2026');
  final _textController = TextEditingController();
  final _nopScanner = NopScanner();

  String? _fileName;
  List<TaxRecord> _records = [];
  bool _loading = false;
  String? _errorText;
  String? _savedNotice;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostScan());
    }
  }

  @override
  void dispose() {
    _tahunController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<File> _draftFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_draftFileName');
  }

  Future<void> _loadDraft() async {
    final file = await _draftFile();
    if (await file.exists()) {
      final content = await file.readAsString();
      if (mounted) _textController.text = content;
    }
  }

  Future<void> _saveDraft() async {
    final file = await _draftFile();
    await file.writeAsString(_textController.text);
    if (mounted) setState(() => _savedNotice = 'Tersimpan.');
  }

  Future<void> _recoverLostScan() async {
    try {
      final nops = await _nopScanner.recoverLostScan();
      if (!mounted || nops == null || nops.isEmpty) return;
      await _addScannedNops(nops);
    } catch (e) {
      if (mounted) setState(() => _errorText = 'Gagal memulihkan scan: $e');
    }
  }

  Future<void> _scanDocument() async {
    if (!Platform.isAndroid) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scan Dokumen'),
          content: const Text(
            'Scan dengan kamera atau galeri saat ini tersedia di Android.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scan NOP'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Kamera'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Galeri'),
            ),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    setState(() {
      _loading = true;
      _errorText = null;
      _savedNotice = null;
    });
    try {
      final nops = await _nopScanner.scan(source: source);
      if (!mounted || nops == null || nops.isEmpty) {
        if (mounted) {
          setState(() => _errorText = 'NOP tidak ditemukan pada dokumen.');
        }
        return;
      }

      await _addScannedNops(nops);
    } catch (e) {
      if (mounted) setState(() => _errorText = 'Gagal scan dokumen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addScannedNops(List<String> nops) async {
    // Cek duplikat sebelum konfirmasi — hanya NOP yang belum ada di kolom teks
    // (dari ketikan manual maupun hasil scan sebelumnya) yang akan ditambahkan.
    final existing = FileImporter.importFromText(
      _textController.text,
    ).map((record) => record.nop).toSet();
    final additions = nops.where((nop) => !existing.contains(nop)).toList();
    final duplicateCount = nops.length - additions.length;

    if (additions.isEmpty) {
      setState(
        () => _savedNotice =
            'Semua ${nops.length} NOP hasil scan sudah ada di daftar.',
      );
      return;
    }

    final confirmed = await _confirmScannedNops(
      additions,
      duplicateCount: duplicateCount,
    );
    if (!mounted || confirmed != true) return;

    final currentText = _textController.text.trim();
    _textController.text = [
      currentText,
      ...additions,
    ].where((value) => value.isNotEmpty).join('\n');

    final notice = StringBuffer('${additions.length} NOP ditambahkan.');
    if (duplicateCount > 0) {
      notice.write(' $duplicateCount duplikat dilewati.');
    }
    setState(() => _savedNotice = notice.toString());
  }

  Future<bool?> _confirmScannedNops(
    List<String> nops, {
    int duplicateCount = 0,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${nops.length} NOP akan ditambahkan'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (duplicateCount > 0) ...[
                  Text(
                    '$duplicateCount NOP dilewati karena sudah ada.',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final nop in nops) SelectableText(nop),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tambahkan'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _errorText = null;
      _savedNotice = null;
      _loading = true;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'csv', 'xlsx', 'xls'],
      );
      if (!mounted) return;
      if (files.isEmpty || files.first.path == null) {
        setState(() => _loading = false);
        return;
      }

      final path = files.first.path!;
      final records = await FileImporter.importFrom(path);
      if (!mounted) return;
      setState(() {
        _fileName = files.first.name;
        _records = records;
      });
    } catch (e) {
      if (mounted) setState(() => _errorText = 'Gagal baca file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearNotes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Catatan?'),
        content: const Text(
          'Semua NOP yang diketik/tersimpan di catatan akan dihapus. Berkas hasil import tidak terpengaruh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _textController.clear();
    final file = await _draftFile();
    if (await file.exists()) await file.delete();
    if (!mounted) return;
    setState(() => _savedNotice = null);
  }

  /// null = batal (tombol Kembali), true/false = jawaban unduh bukti bayar.
  Future<bool?> _confirmDownloadBuktiBayar() {
    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Unduh Bukti Bayar Sekalian?'),
        content: const Text(
          'Untuk NOP yang statusnya "Sudah Bayar", apakah bukti bayarnya sekalian '
          'diunduh semua ke folder Dokumen setelah dicek?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Kembali'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Iya'),
          ),
        ],
      ),
    );
  }

  Future<void> _startBatch() async {
    final tahun = _tahunController.text.trim();
    final combined = <String, TaxRecord>{};
    for (final r in [
      ..._records,
      ...FileImporter.importFromText(_textController.text),
    ]) {
      combined[r.nop] = r;
    }
    final records = combined.values.toList();

    if (records.isEmpty) {
      setState(
        () => _errorText = 'Belum ada data NOP dari file atau catatan di atas.',
      );
      return;
    }
    if (widget.mode == CheckMode.statusBayar && tahun.isEmpty) {
      setState(() => _errorText = 'Tahun Pajak wajib diisi.');
      return;
    }

    var downloadBuktiBayar = false;
    if (widget.mode == CheckMode.statusBayar) {
      final choice = await _confirmDownloadBuktiBayar();
      if (choice == null) return;
      downloadBuktiBayar = choice;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchCheckScreen(
          records: records,
          tahun: tahun,
          downloadBuktiBayar: downloadBuktiBayar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Format yang didukung: .txt (dipisah koma/baris baru), .csv, .xlsx',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Tiap NOP bisa ditulis lengkap (18 digit) atau singkat 5-7 digit terakhir '
            '(blok+nomor wilayah). Contoh: ${nopShortcutExamples.map((e) => '${e.$1} -> ${e.$2}').join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickFile,
            icon: const Icon(Icons.folder_open),
            label: Text(_fileName ?? 'Pilih File'),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_records.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${_records.length} NOP dari file',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                itemCount: _records.length,
                itemBuilder: (context, index) => Text(
                  _records[index].nop,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Atau ketik langsung di sini',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              hintText: _placeholderExample,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _scanDocument,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan'),
              ),
              OutlinedButton.icon(
                onPressed: _clearNotes,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus Semua'),
              ),
              if (_savedNotice != null)
                Text(
                  _savedNotice!,
                  style: const TextStyle(color: Colors.green),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.mode == CheckMode.statusBayar) ...[
            TextField(
              controller: _tahunController,
              decoration: const InputDecoration(
                labelText: 'Tahun Pajak (dipakai untuk semua NOP)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
          ],
          if (_errorText != null)
            Text(_errorText!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: _startBatch,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Mulai Cek'),
            ),
          ),
        ],
      ),
    );
  }
}
