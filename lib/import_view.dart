import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'batch_check_screen.dart';
import 'check_mode.dart';
import 'file_importer.dart';
import 'nop_helper.dart';
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

  String? _fileName;
  List<TaxRecord> _records = [];
  bool _loading = false;
  String? _errorText;
  String? _savedNotice;

  @override
  void initState() {
    super.initState();
    _loadDraft();
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
      _textController.text = await file.readAsString();
    }
  }

  Future<void> _saveDraft() async {
    final file = await _draftFile();
    await file.writeAsString(_textController.text);
    setState(() => _savedNotice = 'Tersimpan.');
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
      if (files.isEmpty || files.first.path == null) {
        setState(() => _loading = false);
        return;
      }

      final path = files.first.path!;
      final records = await FileImporter.importFrom(path);
      setState(() {
        _fileName = files.first.name;
        _records = records;
      });
    } catch (e) {
      setState(() => _errorText = 'Gagal baca file: $e');
    } finally {
      setState(() => _loading = false);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
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
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Kembali')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tidak')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Iya')),
        ],
      ),
    );
  }

  Future<void> _startBatch() async {
    final tahun = _tahunController.text.trim();
    final combined = <String, TaxRecord>{};
    for (final r in [..._records, ...FileImporter.importFromText(_textController.text)]) {
      combined[r.nop] = r;
    }
    final records = combined.values.toList();

    if (records.isEmpty) {
      setState(() => _errorText = 'Belum ada data NOP dari file atau catatan di atas.');
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
          if (_loading) const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          if (_records.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('${_records.length} NOP dari file', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Text('Atau ketik langsung di sini', style: Theme.of(context).textTheme.titleMedium),
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
                onPressed: _clearNotes,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus Semua'),
              ),
              if (_savedNotice != null) Text(_savedNotice!, style: const TextStyle(color: Colors.green)),
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
          if (_errorText != null) Text(_errorText!, style: const TextStyle(color: Colors.red)),
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
