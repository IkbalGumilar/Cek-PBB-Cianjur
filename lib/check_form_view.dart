import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_storage.dart';
import 'blok_data_store.dart';
import 'check_mode.dart';
import 'nop_helper.dart';
import 'nop_scanner.dart';
import 'pbb/check_result_cards.dart';
import 'pbb_client.dart';
import 'tagihan_result.dart';

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

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('NOP berhasil dideteksi: $nop')));
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
                          child: RadioGroup<String>(
                            groupValue: tempSelected,
                            onChanged: (value) {
                              setState(() => tempSelected = value);
                            },
                            child: ListView.builder(
                              itemCount: nops.length,
                              itemBuilder: (context, index) {
                                final n = nops[index];
                                return RadioListTile<String>(
                                  value: n,
                                  title: Text(
                                    '${index + 1}. $n',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  contentPadding: const EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                  ),
                                );
                              },
                            ),
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
            _wilayahController.text =
                int.tryParse(wilayah)?.toString() ?? wilayah;

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
            final existing = await file.exists()
                ? await file.readAsString()
                : '';
            final existingSet = existing
                .split(RegExp(r'[,\n\r]+'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet();

            final toAdd = nops.where((n) => !existingSet.contains(n)).toList();
            if (toAdd.isNotEmpty) {
              final newContent = [
                existing.trim(),
                ...toAdd,
              ].where((e) => e.isNotEmpty).join('\n');
              await file.writeAsString(newContent);
            }

            widget.onImportPressed();
          } else if (checkMassal == false) {
            final nop = nops.first;
            final blok = nopBlok(nop);
            final wilayah = nopWilayah(nop);
            _blokController.text = int.tryParse(blok)?.toString() ?? blok;
            _wilayahController.text =
                int.tryParse(wilayah)?.toString() ?? wilayah;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dipakai NOP pertama: $nop')),
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

  Future<void> _loadCaptcha({bool clearError = true}) async {
    setState(() {
      _loadingCaptcha = true;
      if (clearError) _errorText = null;
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
        () => _errorText = 'Lengkapi dulu semua kolom yang wajib diisi.',
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
          final outcome = await _recordIfInWilayah(
            nop: nop,
            tahun: tahun,
            result: result,
          );
          if (!mounted) return;
          if (outcome != null) {
            final msg = outcome.changedFromUnpaid
                ? 'Data DHKP diperbarui: Status menjadi Sudah Bayar!'
                : (outcome.wasExisting
                      ? 'Data DHKP sudah tercatat Sudah Bayar.'
                      : 'Data baru berhasil dicatat ke DHKP (Sudah Bayar).');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 20,
                    ),
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
      await _loadCaptcha(clearError: false);
      if (mounted) _captchaFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal cek: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Catat / perbarui hasil "Sudah Bayar" ke Buku Catatan Data DHKP.
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
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isTagihan
                                  ? Icons.receipt_long_outlined
                                  : Icons.verified_outlined,
                              color: scheme.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isTagihan
                                      ? 'Cek Tagihan PBB'
                                      : 'Cek Status Bayar PBB',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isTagihan
                                      ? 'Lihat rincian tunggakan dan bayar lewat QRIS atau VA'
                                      : 'Periksa bukti lunas pembayaran PBB per tahun',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _blokController,
                              decoration: const InputDecoration(
                                labelText: 'Blok',
                                hintText: 'Contoh: 17',
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
                                hintText: 'Contoh: 154',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _scanningOcr
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton.filledTonal(
                                  onPressed: _scanAndFill,
                                  icon: const Icon(
                                    Icons.document_scanner_outlined,
                                  ),
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
                      const SizedBox(height: 6),
                      Text(
                        'Cukup isi angka tanpa nol di depan (contoh: Blok 1, Nomor 1).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (widget.mode == CheckMode.statusBayar) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _tahunController,
                          decoration: const InputDecoration(
                            labelText: 'Tahun Pajak',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                      const SizedBox(height: 18),
                      Center(
                        child: _loadingCaptcha
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              )
                            : _captchaBytes != null
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.memory(_captchaBytes!, height: 84),
                              )
                            : const Text('Captcha belum dimuat'),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton.icon(
                          onPressed: _loadingCaptcha || _submitting
                              ? null
                              : () => _loadCaptcha(),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Ganti Captcha'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _captchaController,
                        builder: (context, value, _) {
                          return TextField(
                            controller: _captchaController,
                            focusNode: _captchaFocusNode,
                            textInputAction: TextInputAction.go,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'Kode Verifikasi',
                              hintText: 'Ketik huruf pada gambar di atas',
                              border: const OutlineInputBorder(),
                              suffixIcon: value.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      tooltip: 'Hapus teks',
                                      onPressed: () {
                                        _captchaController.clear();
                                        _captchaFocusNode.requestFocus();
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: (_) => _submitting ? null : _submit(),
                          );
                        },
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 18,
                                color: scheme.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorText!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: const Text('Cek'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_statusBayarResult != null) ...[
                const SizedBox(height: 16),
                StatusBayarResultCard(
                  result: _statusBayarResult!,
                  nop: buildNop(
                    blok: _blokController.text,
                    wilayah: _wilayahController.text,
                  ),
                  tahun: _tahunController.text.trim(),
                  client: _client,
                ),
              ],
              if (_tagihanResult != null) ...[
                const SizedBox(height: 16),
                TagihanResultCard(
                  result: _tagihanResult!,
                  nop: buildNop(
                    blok: _blokController.text,
                    wilayah: _wilayahController.text,
                  ),
                  client: _client,
                  onOpenStatusBayar: widget.onOpenStatusBayar,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
