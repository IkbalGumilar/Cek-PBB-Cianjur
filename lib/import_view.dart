import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';
import 'batch_check_manager.dart';
import 'batch_check_screen.dart';
import 'batch_notification_service.dart';
import 'check_mode.dart';
import 'feature_tour/feature_tour.dart';
import 'file_importer.dart';
import 'nop_helper.dart';
import 'nop_scanner.dart';
import 'tax_record.dart';
import 'unity_lerp_widgets.dart';
import 'user_friendly_error.dart';

const _draftFileName = 'draft_nop.txt';

class ImportView extends StatefulWidget {
  final CheckMode mode;
  final bool isActive;
  final ValueChanged<VoidCallback>? onRegisterShowTour;

  const ImportView({
    super.key,
    required this.mode,
    this.isActive = false,
    this.onRegisterShowTour,
  });

  @override
  State<ImportView> createState() => ImportViewState();
}

class ImportViewState extends State<ImportView> {
  final _tahunController = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final _textController = TextEditingController();
  final _nopScanner = NopScanner();

  final _pickFileButtonKey = GlobalKey(debugLabel: 'tour_import_pick_file');
  final _textNotesKey = GlobalKey(debugLabel: 'tour_import_text_notes');
  final _noteActionsKey = GlobalKey(debugLabel: 'tour_import_note_actions');
  final _tahunKey = GlobalKey(debugLabel: 'tour_import_tahun');
  final _startBatchButtonKey = GlobalKey(debugLabel: 'tour_import_start_batch');

  String? _fileName;
  List<TaxRecord> _records = [];
  bool _loading = false;
  bool _downloadStts = false;
  String _loadingMessage = 'Memuat berkas...';
  String? _errorText;
  String? _savedNotice;

  String get _placeholderExample =>
      'Contoh isi (satu nomor pajak per baris, atau dipisah koma):\n'
      '17154\n'
      '300584\n'
      '${activeNopPrefix}03000330';

  @override
  void initState() {
    super.initState();
    activeWilayahRevision.addListener(_onWilayahChanged);
    widget.onRegisterShowTour?.call(showTour);
    _loadDraft();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostScan());
    }
    if (widget.isActive) {
      _maybeStartTour();
    }
  }

  void _onWilayahChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ImportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onRegisterShowTour != widget.onRegisterShowTour) {
      widget.onRegisterShowTour?.call(showTour);
    }
    if (!oldWidget.isActive && widget.isActive) {
      _maybeStartTour();
    }
  }

  void _maybeStartTour() {
    if (!mounted || !widget.isActive) return;
    FeatureTourController.startTourIfNeeded(
      context: context,
      tourId: 'import_batch_view',
      steps: _buildTourSteps(),
    );
  }

  void showTour() {
    if (!mounted) return;
    FeatureTourController.showTour(
      context: context,
      tourId: 'import_batch_view',
      steps: _buildTourSteps(),
    );
  }

  List<FeatureTourStep> _buildTourSteps() {
    final currentYear = DateTime.now().year;
    final hasCameraScan = Platform.isAndroid;
    return [
      FeatureTourStep(
        targetKey: _pickFileButtonKey,
        title: 'Pilih Berkas Daftar NOP',
        description:
            'Ambil berkas daftar wajib pajak dari perangkat (mendukung Excel .xlsx/.xls, .csv, atau teks .txt).',
        actionHint: 'Seluruh NOP di dalam berkas akan dibaca otomatis.',
        icon: Icons.folder_open_rounded,
      ),
      FeatureTourStep(
        targetKey: _textNotesKey,
        title: 'Catatan Nomor Pajak Manual',
        description:
            'Ketik atau tempel daftar NOP langsung di sini (satu per baris atau dipisah koma), lengkap 18 digit maupun singkat (Blok + Nomor Wilayah).',
        actionHint: 'Contoh singkat: ketik 17154 untuk Blok 017 Nomor 0154.',
        icon: Icons.edit_note_rounded,
      ),
      FeatureTourStep(
        targetKey: _noteActionsKey,
        title: hasCameraScan
            ? 'Simpan, Scan, & Hapus Catatan'
            : 'Simpan & Hapus Catatan',
        description: hasCameraScan
            ? '• Simpan: Menyimpan daftar agar tidak hilang.\n'
                  '• Scan: Memindai foto daftar pajak dari kamera atau galeri.\n'
                  '• Hapus Semua: Mengosongkan kotak catatan.'
            : '• Simpan: Menyimpan daftar agar tidak hilang saat aplikasi ditutup.\n'
                  '• Hapus Semua: Mengosongkan kotak catatan.',
        actionHint:
            'Gunakan Simpan saat mengumpulkan daftar NOP secara bertahap.',
        icon: Icons.save_outlined,
      ),
      FeatureTourStep(
        targetKey: _tahunKey,
        title: 'Tahun Pajak Pemeriksaan',
        description:
            'Tentukan tahun pajak yang akan diperiksa untuk seluruh daftar NOP sekaligus.',
        actionHint: 'Secara bawaan terisi tahun berjalan ($currentYear).',
        icon: Icons.calendar_month_outlined,
      ),
      FeatureTourStep(
        targetKey: _startBatchButtonKey,
        title: 'Mulai Pemeriksaan Massal',
        description:
            'Periksa seluruh daftar NOP secara berurutan. Tekan "Sembunyikan" agar berjalan di latar belakang sambil memakai menu lain.',
        actionHint:
            'Pastikan sudah ada daftar NOP dari berkas atau catatan sebelum memulai.',
        icon: Icons.play_circle_outline_rounded,
      ),
    ];
  }

  @override
  void dispose() {
    activeWilayahRevision.removeListener(_onWilayahChanged);
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
      if (mounted) {
        setState(
          () => _errorText = friendlyErrorMessage(
            e,
            fallback: 'Gagal memulihkan hasil pindai sebelumnya.',
          ),
        );
      }
    }
  }

  Future<void> _scanDocument() async {
    if (!Platform.isAndroid) return;

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
      if (mounted) {
        setState(
          () => _errorText = friendlyErrorMessage(
            e,
            fallback: 'Gagal memindai dokumen. Coba ambil foto lebih jelas.',
          ),
        );
      }
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
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
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
      if (mounted) {
        setState(
          () => _errorText = friendlyErrorMessage(
            e,
            fallback:
                'Gagal membaca berkas. Pastikan format Excel, CSV, atau TXT valid.',
          ),
        );
      }
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

    if (BatchCheckManager.instance.isActiveSession) {
      if (!mounted) return;
      final openActive = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cek Massal Sedang Berjalan'),
          content: const Text(
            'Masih ada proses cek massal lain yang aktif di latar belakang. '
            'Selesaikan atau hentikan proses tersebut terlebih dahulu sebelum memulai daftar baru.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tutup'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lihat Proses Aktif'),
            ),
          ],
        ),
      );
      if (openActive == true && mounted) {
        BatchNotificationService.instance.openActiveBatchCheck();
      }
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: BatchCheckScreen.routeName),
        builder: (_) => BatchCheckScreen(
          records: records,
          tahun: tahun,
          downloadStts: widget.mode == CheckMode.statusBayar && _downloadStts,
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
                    key: _pickFileButtonKey,
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
                    'Tulis 18 angka NOP lengkap atau singkat (blok + nomor wilayah). '
                    'Contoh: 17154 -> ${activeNopPrefix}01701540, 300584 -> ${activeNopPrefix}03005840',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: _textNotesKey,
                    controller: _textController,
                    maxLines: 7,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      hintText: _placeholderExample,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    key: _noteActionsKey,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saveDraft,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Simpan'),
                      ),
                      if (Platform.isAndroid)
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
                      key: _tahunKey,
                      controller: _tahunController,
                      decoration: const InputDecoration(
                        labelText: 'Tahun Pajak (dipakai untuk semua NOP)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      value: _downloadStts,
                      onChanged: (v) => setState(() => _downloadStts = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Unduh STTS untuk yang sudah bayar'),
                      subtitle: const Text(
                        'Jika aktif, berkas STTS NOP yang terdeteksi sudah bayar ikut diunduh. Jika tidak, hanya status yang dicek.',
                      ),
                    ),
                    const SizedBox(height: 8),
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
                    key: _startBatchButtonKey,
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
