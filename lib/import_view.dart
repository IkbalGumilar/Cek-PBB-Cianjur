import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';
import 'batch_check_screen.dart';
import 'check_mode.dart';
import 'file_importer.dart';
import 'nop_helper.dart';
import 'nop_scanner.dart';
import 'tax_record.dart';
import 'unity_lerp_widgets.dart';

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
  String _loadingMessage = 'Memuat berkas...';
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
    final dir = await AppStorage.getDataDirectory();
    final target = File('${dir.path}/$_draftFileName');
    if (!await target.exists()) {
      try {
        final oldDir = await getApplicationDocumentsDirectory();
        final oldFile = File('${oldDir.path}/$_draftFileName');
        if (await oldFile.exists()) {
          await oldFile.copy(target.path);
        }
      } catch (_) {}
    }
    return target;
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
      _loadingMessage = 'Memindai NOP dari dokumen gambar...';
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
      _loadingMessage = 'Membaca & mengekstrak daftar NOP dari berkas...';
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

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchCheckScreen(
          records: records,
          tahun: tahun,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cek Banyak NOP Sekaligus',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih berkas daftar NOP (.xlsx, .csv, .txt) atau ketik langsung di bawah.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_fileName ?? 'Pilih File'),
                  ),
                  SmoothActivityBanner(
                    isActive: _loading,
                    message: _loadingMessage,
                    icon: Icons.file_open_outlined,
                    margin: const EdgeInsets.only(top: 12),
                  ),
                  if (_records.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${_records.length} NOP dari file',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
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
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    'Atau ketik langsung di sini',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tulis 18 angka NOP lengkap atau singkat (blok + nomor wilayah). Contoh: ${nopShortcutExamples.map((e) => '${e.$1} -> ${e.$2}').join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _textController,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                      hintText: _placeholderExample,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (widget.mode == CheckMode.statusBayar) ...[
                    TextField(
                      controller: _tahunController,
                      decoration: const InputDecoration(
                        labelText: 'Tahun Pajak (dipakai untuk semua NOP)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_errorText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _errorText!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                  FilledButton.icon(
                    onPressed: _startBatch,
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('Mulai Cek'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
