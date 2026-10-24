import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_storage.dart';
import 'blok_data_store.dart';
import 'check_mode.dart';
import 'document_preview_screen.dart';
import 'nop_helper.dart';
import 'nop_scanner.dart';
import 'pbb_client.dart';
import 'qris_result.dart';
import 'qris_view_screen.dart';
import 'tagihan_result.dart';
import 'va_result.dart';
import 'va_view_screen.dart';

class CheckFormView extends StatefulWidget {
  final CheckMode mode;
  final VoidCallback onImportPressed;
  final void Function(String blok, String wilayah, String tahun)?
  onOpenStatusBayar;
  final String? initialBlok;
  final String? initialWilayah;
  final String? initialTahun;
  final ScrollController? scrollController;
  final PbbClient? client;

  const CheckFormView({
    super.key,
    required this.mode,
    required this.onImportPressed,
    this.onOpenStatusBayar,
    this.initialBlok,
    this.initialWilayah,
    this.initialTahun,
    this.scrollController,
    this.client,
  });

  @override
  State<CheckFormView> createState() => _CheckFormViewState();
}

class _CheckFormViewState extends State<CheckFormView> {
  late final PbbClient _client;
  final _nopScanner = NopScanner();
  final _blokController = TextEditingController();
  final _wilayahController = TextEditingController();
  final _tahunController = TextEditingController(text: '2026');
  final _captchaController = TextEditingController();
  final _captchaFocusNode = FocusNode();
  late final ScrollController _scrollController =
      widget.scrollController ?? ScrollController();

  Uint8List? _captchaBytes;
  bool _loadingCaptcha = false;
  bool _scanningOcr = false;
  bool _ready = false;
  bool _submitting = false;
  PbbResult? _statusBayarResult;
  TagihanResult? _tagihanResult;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? PbbClient();
    _blokController.text = widget.initialBlok ?? '';
    _wilayahController.text = widget.initialWilayah ?? '';
    if (widget.initialTahun != null) {
      _tahunController.text = widget.initialTahun!;
    }
    _loadCaptcha();
  }

  @override
  void didUpdateWidget(CheckFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      setState(() {
        _statusBayarResult = null;
        _tagihanResult = null;
        _errorText = null;
      });
      _loadCaptcha();
    }
  }

  @override
  void dispose() {
    _blokController.dispose();
    _wilayahController.dispose();
    _tahunController.dispose();
    _captchaController.dispose();
    _captchaFocusNode.dispose();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  /// Pindai gambar (kamera atau galeri) lalu isi kolom Blok & Nomor Wilayah
  /// dari NOP pertama yang berhasil dikenali OCR.
  Future<void> _scanAndFill() async {
    // Pilih sumber gambar
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scan NOP dari Dokumen'),
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
      _scanningOcr = true;
      _errorText = null;
    });
    try {
      final nops = await _nopScanner.scan(source: source);
      if (!mounted) return;
      if (nops == null || nops.isEmpty) {
        setState(() => _errorText = 'NOP tidak ditemukan pada dokumen.');
        return;
      }

      if (nops.length == 1) {
        final nop = nops.first;
        final blok = nopBlok(nop);
        final wilayah = nopWilayah(nop);
        _blokController.text = int.tryParse(blok)?.toString() ?? blok;
        _wilayahController.text = int.tryParse(wilayah)?.toString() ?? wilayah;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NOP berhasil dideteksi: $nop')),
        );
      } else {
        if (widget.mode == CheckMode.tagihan) {
          final selectedNop = await showDialog<String>(
            context: context,
            builder: (ctx) {
              String? tempSelected;
              return StatefulBuilder(
                builder: (context, setState) {
                  return AlertDialog(
                    title: const Text('Pilih NOP'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lebih dari 1 NOP ditemukan dari dokumen.\n'
                          'Pilih NOP mana yang ingin Anda cek:',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 300,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ListView.builder(
                            itemCount: nops.length,
                            itemBuilder: (context, index) {
                              final n = nops[index];
                              return RadioListTile<String>(
                                value: n,
                                groupValue: tempSelected,
                                title: Text(
                                  '${index + 1}. $n',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                contentPadding: const EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                ),
                                onChanged: (value) {
                                  setState(() => tempSelected = value);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: tempSelected == null
                            ? null
                            : () => Navigator.pop(ctx, tempSelected),
                        child: const Text('Lanjutkan'),
                      ),
                    ],
                  );
                },
              );
            },
          );
          if (!mounted) return;
          if (selectedNop != null) {
            final blok = nopBlok(selectedNop);
            final wilayah = nopWilayah(selectedNop);
            _blokController.text = int.tryParse(blok)?.toString() ?? blok;
            _wilayahController.text = int.tryParse(wilayah)?.toString() ?? wilayah;
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('NOP dipilih: $selectedNop')),
            );
          }
        } else {
          // Di mode Status Bayar, tawarkan pindah ke Cek Massal
          final checkMassal = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Lebih dari 1 NOP Ditemukan'),
              content: Text(
                'Ada ${nops.length} NOP yang berhasil dibaca dari dokumen.\n\n'
                'Apakah Anda ingin memasukkan semuanya ke menu "Cek Massal / Import" '
                'untuk dicek secara kolektif?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Tidak, pakai NOP pertama saja'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ya, cek kolektif'),
                ),
              ],
            ),
          );
          if (!mounted) return;

          if (checkMassal == true) {
            // Tambahkan ke file draft NOP untuk ImportView
            final dir = await AppStorage.getDataDirectory();
            final file = File('${dir.path}/draft_nop.txt');
            final existing = await file.exists() ? await file.readAsString() : '';
            final existingSet = existing
                .split(RegExp(r'[,\n\r]+'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet();

            final toAdd = nops.where((n) => !existingSet.contains(n)).toList();
            if (toAdd.isNotEmpty) {
              final newContent =
                  [existing.trim(), ...toAdd].where((e) => e.isNotEmpty).join('\n');
              await file.writeAsString(newContent);
            }
            
            widget.onImportPressed();
          } else if (checkMassal == false) {
            final nop = nops.first;
            final blok = nopBlok(nop);
            final wilayah = nopWilayah(nop);
            _blokController.text = int.tryParse(blok)?.toString() ?? blok;
            _wilayahController.text = int.tryParse(wilayah)?.toString() ?? wilayah;
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Dipakai NOP pertama: $nop',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = 'Gagal scan: $e');
    } finally {
      if (mounted) setState(() => _scanningOcr = false);
    }
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _errorText = null;
    });
    try {
      final bytes = await _client.fetchCaptchaImage(widget.mode);
      if (!mounted) return;
      setState(() => _captchaBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal ambil captcha: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCaptcha = false;
          _ready = true;
        });
      }
    }
  }

  void _scrollAfterResult() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus(); // Singkirkan keyboard saat mulai cek

    final nop = buildNop(
      blok: _blokController.text,
      wilayah: _wilayahController.text,
    );
    final tahun = _tahunController.text.trim();
    final manualCaptcha = _captchaController.text.trim();

    if (nop.isEmpty ||
        (widget.mode == CheckMode.statusBayar && tahun.isEmpty) ||
        manualCaptcha.isEmpty) {
      setState(
        () => _errorText = 'Lengkapi dulu semua field yang wajib diisi.',
      );
      return;
    }

    await _submitManual(nop: nop, tahun: tahun, captcha: manualCaptcha);
  }

  Future<void> _submitManual({
    required String nop,
    required String tahun,
    required String captcha,
  }) async {
    setState(() {
      _submitting = true;
      _errorText = null;
      _statusBayarResult = null;
      _tagihanResult = null;
    });

    try {
      if (widget.mode == CheckMode.statusBayar) {
        final result = await _client.checkStatusBayar(
          nop: nop,
          tahun: tahun,
          captchaCode: captcha,
        );
        if (!mounted) return;
        setState(() => _statusBayarResult = result);
        if (result.isPaid) {
          final outcome = await _recordIfInWilayah(nop: nop, tahun: tahun, result: result);
          if (!mounted) return;
          if (outcome != null) {
            final msg = outcome.changedFromUnpaid
                ? 'Data DHKP berhasil di-update: Status berubah dari Belum Bayar menjadi Sudah Bayar!'
                : (outcome.wasExisting
                    ? 'Data DHKP sudah berstatus Sudah Bayar.'
                    : 'Data baru berhasil dicatat ke Data DHKP (Sudah Bayar).');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(msg)),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        final result = await _client.checkTagihan(
          nop: nop,
          captchaCode: captcha,
        );
        if (!mounted) return;
        setState(() => _tagihanResult = result);
      }

      _captchaController.clear();
      await _loadCaptcha();
      _scrollAfterResult();
    } on CaptchaError catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.message);
      _captchaController.clear();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await _loadCaptcha();
      if (mounted) _captchaFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal cek: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Catat hasil "Sudah Bayar" ke Buku Catatan Blok kalau blok-nya termasuk
  /// wilayah kerja yang sedang dipilih (lihat WilayahKerjaStore). Kalau belum
  /// ada wilayah kerja dipilih sama sekali, diam-diam tidak dicatat (memang
  /// pilihan user untuk tidak menyimpan riwayat). Kalau sudah ada wilayah
  /// kerja tapi blok ini di luar itu, beri tahu lewat dialog lalu tetap tidak
  /// dicatat — pengecekan & pembayaran sendiri tidak terpengaruh sama sekali.
  ///
  /// Mode Operator melewati semua pengecekan wilayah ini — operator menerima
  /// Catat / perbarui hasil "Sudah Bayar" ke Buku Catatan Data DHKP.
  /// Karena paket DHKP sudah mencakup wilayah kerja perangkat ini,
  /// data langsung disinkronkan tanpa perlu memilih dusun atau role secara manual.
  Future<DhkpCheckUpdateOutcome?> _recordIfInWilayah({
    required String nop,
    required String tahun,
    required PbbResult result,
  }) async {
    return await BlokDataStore.instance.updateStatusBayarFromCheck(
      nop: nop,
      tahun: tahun,
      result: result,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Memuat...'),
            ],
          ),
        ),
      );
    }

    final isTagihan = widget.mode == CheckMode.tagihan;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _blokController,
                  decoration: const InputDecoration(
                    labelText: 'Blok',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _wilayahController,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Wilayah',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                ),
              ),
              const SizedBox(width: 8),
              // Tombol scan OCR — tersedia di semua mode
              _scanningOcr
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filledTonal(
                      onPressed: _scanAndFill,
                      icon: const Icon(Icons.document_scanner_outlined),
                      tooltip: 'Scan NOP dari dokumen',
                    ),
              if (!isTagihan) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: widget.onImportPressed,
                  icon: const Icon(Icons.upload_file),
                  tooltip: 'Import File (cek banyak NOP)',
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Isi blok & nomor wilayah saja, tanpa nol di depan. '
            'Contoh: Blok 1, Nomor 1 -> otomatis jadi 001 dan 0001.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.mode == CheckMode.statusBayar) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _tahunController,
              decoration: const InputDecoration(
                labelText: 'Tahun Pajak',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: _loadingCaptcha
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                : _captchaBytes != null
                ? Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Image.memory(_captchaBytes!, height: 84),
                  )
                : const Text('Captcha belum dimuat'),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: _loadingCaptcha || _submitting ? null : _loadCaptcha,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Ganti Captcha'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _captchaController,
            focusNode: _captchaFocusNode,
            textInputAction: TextInputAction.go,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Kode Verifikasi',
              hintText: '5-6 huruf captcha',
              helperText: 'Ketik manual kode verifikasi pada gambar di atas',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submitting ? null : _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Cek'),
          ),
          const SizedBox(height: 16),
          if (_errorText != null)
            Text(_errorText!, style: const TextStyle(color: Colors.red)),
          if (_statusBayarResult != null)
            _StatusBayarResultCard(
              result: _statusBayarResult!,
              nop: buildNop(
                blok: _blokController.text,
                wilayah: _wilayahController.text,
              ),
              tahun: _tahunController.text.trim(),
              client: _client,
            ),
          if (_tagihanResult != null)
            _TagihanResultCard(
              result: _tagihanResult!,
              nop: buildNop(
                blok: _blokController.text,
                wilayah: _wilayahController.text,
              ),
              client: _client,
              onOpenStatusBayar: widget.onOpenStatusBayar,
            ),
        ],
      ),
    );
  }
}

class _StatusBayarResultCard extends StatelessWidget {
  final PbbResult result;
  final String nop;
  final String tahun;
  final PbbClient client;

  const _StatusBayarResultCard({
    required this.result,
    required this.nop,
    required this.tahun,
    required this.client,
  });

  bool get _isPaid => result.status.startsWith('Sudah Bayar');

  Future<void> _previewBuktiBayar(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await client.fetchBuktiBayarPdf(nop: nop, tahun: tahun);
      if (!context.mounted) return;
      Navigator.pop(context);
      final fileName =
          'Bukti Bayar (${result.namaWajibPajak ?? nop}) No. (${nopBlok(nop)}) (${nopWilayah(nop)}) ($tahun).pdf';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(pdfBytes: bytes, fileName: fileName),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Gagal'),
          content: Text('Gagal memuat PDF: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _isPaid
          ? Colors.green.withValues(alpha: 0.12)
          : Colors.orange.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                result.status,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isPaid)
              IconButton(
                onPressed: () => _previewBuktiBayar(context),
                icon: const Icon(Icons.visibility),
                tooltip: 'Detail',
              ),
          ],
        ),
      ),
    );
  }
}

class _TagihanResultCard extends StatelessWidget {
  final TagihanResult result;
  final String nop;
  final PbbClient client;
  final void Function(String blok, String wilayah, String tahun)?
  onOpenStatusBayar;

  const _TagihanResultCard({
    required this.result,
    required this.nop,
    required this.client,
    this.onOpenStatusBayar,
  });

  Future<void> _payWithQris(BuildContext context, String tahun) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'PEMBAYARAN QRIS PBB KABUPATEN CIANJUR',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          '1. Pembayaran QRIS berlaku selama 1 jam\n'
          '2. Pembayaran dapat dilakukan melalui penyedia pembayaran QRIS\n'
          '3. Jika Setuju, dalam 1 jam kedepan pembayaran hanya dapat dilakukan melalui QRIS\n'
          '4. QRIS tersebut hanya berlaku untuk 1 x pembayaran',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setuju'),
          ),
        ],
      ),
    );

    if (agreed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final qris = await client.generateQrisPbb(nop: nop, tahun: tahun);
      if (!context.mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QrisViewScreen(result: qris, nop: nop, tahun: tahun),
        ),
      );
    } on QrisGenerationError catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, 'Gagal generate QRIS: $e');
    }
  }

  Future<void> _payWithVa(BuildContext context, TagihanYearRow row) async {
    final paymentCode = row.paymentCodeVa;
    if (paymentCode == null) {
      _showError(
        context,
        'Pembayaran VA tidak tersedia untuk tahun ${row.tahun}.',
      );
      return;
    }

    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'PEMBAYARAN VIRTUAL ACCOUNT BANK BJB',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          '1. Pembayaran VA berlaku selama 1 jam\n'
          '2. Pembayaran dapat dilakukan melalui penyedia pembayaran VA\n'
          '3. Jika Setuju, dalam 1 jam kedepan pembayaran hanya dapat dilakukan melalui VA\n'
          '4. VA tersebut hanya berlaku untuk 1 x pembayaran',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setuju'),
          ),
        ],
      ),
    );

    if (agreed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final va = await client.generateVaPbb(
        nop: nop,
        tahun: row.tahun,
        paymentCode: paymentCode,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VaViewScreen(
            result: va,
            nop: nop,
            tahun: row.tahun,
            paymentCode: paymentCode,
          ),
        ),
      );
    } on VaGenerationError catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, 'Gagal generate VA: $e');
    }
  }

  Future<void> _previewTagihan(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await client.fetchTagihanPdf(nop: nop);
      if (!context.mounted) return;
      Navigator.pop(context);
      final fileName =
          'Tagihan PBB (${result.namaWajibPajak}) No. (${nopBlok(nop)}) (${nopWilayah(nop)}).pdf';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(pdfBytes: bytes, fileName: fileName),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showError(context, 'Gagal memuat PDF: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gagal'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (result.serverMessage != null) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.serverMessage!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (result.inactiveUntilYear != null && onOpenStatusBayar != null)
                TextButton(
                  onPressed: () => onOpenStatusBayar!(
                    nopBlok(nop),
                    nopWilayah(nop),
                    result.inactiveUntilYear!,
                  ),
                  child: Text(
                    '[Cek status bayar tahun ${result.inactiveUntilYear}]',
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (result.notFound) {
      return Card(
        color: Colors.green.withValues(alpha: 0.12),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Data Tidak Ditemukan (tidak ada tunggakan tercatat)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (result.namaWajibPajak.isNotEmpty)
                  Expanded(
                    child: Text(
                      result.namaWajibPajak,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _previewTagihan(context),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Cetak PDF'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                // VA hanya lewat aplikasi bank di HP (butuh channel native
                // Android) — di Windows/Linux pembayaran cuma lewat QRIS.
                columns: [
                  const DataColumn(label: Text('Tahun')),
                  const DataColumn(label: Text('PBB')),
                  const DataColumn(label: Text('Denda')),
                  const DataColumn(label: Text('Kurang Bayar')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('QRIS')),
                  if (Platform.isAndroid) const DataColumn(label: Text('VA')),
                ],
                rows: result.rows
                    .map(
                      (r) => DataRow(
                        cells: [
                          DataCell(Text(r.tahun)),
                          DataCell(Text(formatRupiah(r.pbb))),
                          DataCell(Text(formatRupiah(r.denda))),
                          DataCell(Text(formatRupiah(r.kurangBayar))),
                          DataCell(
                            Text(r.statusBayar.isEmpty ? '-' : r.statusBayar),
                          ),
                          DataCell(
                            FilledButton(
                              onPressed: () => _payWithQris(context, r.tahun),
                              child: const Text('Bayar QRIS'),
                            ),
                          ),
                          if (Platform.isAndroid)
                            DataCell(
                              r.paymentCodeVa == null
                                  ? const Text('-')
                                  : FilledButton(
                                      onPressed: () => _payWithVa(context, r),
                                      child: const Text('Bayar VA'),
                                    ),
                            ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(),
            Text(
              'Total Kurang Bayar: ${result.totalKurangBayar.isEmpty ? '-' : formatRupiah(result.totalKurangBayar)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
