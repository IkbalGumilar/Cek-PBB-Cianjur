import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blok_data_store.dart';
import 'captcha_ocr_helper.dart';
import 'check_mode.dart';
import 'download_helper.dart';
import 'nop_helper.dart';
import 'pbb_client.dart';
import 'result_screen.dart';
import 'tax_record.dart';
import 'unity_lerp_widgets.dart';

class BatchCheckScreen extends StatefulWidget {
  final List<TaxRecord> records;
  final String tahun;
  final bool downloadBuktiBayar;
  final PbbClient? client;
  final bool initialAutoOcr;

  const BatchCheckScreen({
    super.key,
    required this.records,
    required this.tahun,
    this.downloadBuktiBayar = false,
    this.client,
    this.initialAutoOcr = true,
  });

  @override
  State<BatchCheckScreen> createState() => _BatchCheckScreenState();
}

class _BatchCheckScreenState extends State<BatchCheckScreen> {
  late final PbbClient _client;
  late bool _autoOcrEnabled;
  final _captchaController = TextEditingController();
  final _captchaFocusNode = FocusNode();

  int _index = 0;
  Uint8List? _captchaBytes;
  bool _loadingCaptcha = false;
  bool _ocrRunning = false;
  String? _ocrGuess;
  bool _submitting = false;
  String? _errorText;

  TaxRecord get _current => widget.records[_index];

  @override
  void initState() {
    super.initState();
    _autoOcrEnabled = widget.initialAutoOcr;
    _client = widget.client ?? PbbClient();
    _loadCaptcha();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _warnIfOutsideWilayah(),
    );
  }

  /// Peringatan sekali di awal kalau daftar impor ini ada NOP yang bloknya
  /// di luar wilayah kerja — cuma info, tidak menghentikan/mengganggu proses
  /// cek massal-nya sama sekali (per-NOP tetap jalan, cuma yang di luar
  /// wilayah tidak dicatat ke Buku Catatan Blok, lihat [_submit]). Tidak
  /// relevan sama sekali di Mode Operator — semua blok otomatis dicatat.
  Future<void> _warnIfOutsideWilayah() async {
    // Tidak perlu peringatan wilayah manual karena data DHKP sudah mencakup wilayah kerja
  }

  @override
  void dispose() {
    _captchaController.dispose();
    _captchaFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _ocrRunning = false;
      _ocrGuess = null;
      _errorText = null;
    });
    try {
      final bytes = await _client.fetchCaptchaImage(CheckMode.statusBayar);
      if (!mounted) return;
      setState(() {
        _captchaBytes = bytes;
        _loadingCaptcha = false;
        _ocrRunning = _autoOcrEnabled;
      });
      if (_autoOcrEnabled) {
        _recognizeCaptcha(bytes);
      } else {
        _captchaFocusNode.requestFocus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Gagal ambil captcha: $e';
        _loadingCaptcha = false;
        _ocrRunning = false;
      });
    }
  }

  Future<void> _recognizeCaptcha(Uint8List bytes) async {
    if (!_autoOcrEnabled) return;
    try {
      final guess = await CaptchaOcrHelper.recognizeCaptcha(bytes);
      if (!mounted || !_autoOcrEnabled) return;
      if (guess != null && guess.isNotEmpty) {
        setState(() {
          _ocrGuess = guess;
          _ocrRunning = false;
          // Isi tebakan OCR jika pengguna belum mengetik manual
          if (_captchaController.text.isEmpty ||
              _captchaController.text == _ocrGuess) {
            _captchaController.text = guess;
            // Pilih seluruh teks agar pengguna dapat langsung mengganti
            // dengan 1 ketikan jika salah, atau tekan Enter jika benar
            _captchaController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: guess.length,
            );
          }
        });
      } else {
        setState(() => _ocrRunning = false);
      }
    } catch (_) {
      if (mounted) setState(() => _ocrRunning = false);
    } finally {
      if (mounted) {
        _captchaFocusNode.requestFocus();
      }
    }
  }

  void _goToNext() {
    _captchaController.clear();
    _ocrGuess = null;
    if (_index + 1 >= widget.records.length) {
      HapticFeedback.mediumImpact();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(records: widget.records),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _index += 1);
    _loadCaptcha();
  }

  Future<void> _submit() async {
    final captcha = _captchaController.text.trim();
    if (captcha.isEmpty) {
      setState(() => _errorText = 'Kode verifikasi wajib diisi.');
      _captchaFocusNode.requestFocus();
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final result = await _client.checkStatusBayar(
        nop: _current.nop,
        tahun: widget.tahun,
        captchaCode: captcha,
      );
      if (!mounted) return;
      _current.status = result.status;
      _current.rawText = result.rawText;
      _current.namaWajibPajak = result.namaWajibPajak;

      if (_current.isPaid) {
        await BlokDataStore.instance.updateStatusBayarFromCheck(
          nop: _current.nop,
          tahun: widget.tahun,
          result: result,
        );
      }

      if (widget.downloadBuktiBayar && _current.isPaid) {
        final buktiBayarDownloaded = await _downloadBuktiBayar(_current);
        if (!mounted) return;
        _current.buktiBayarDownloaded = buktiBayarDownloaded;
      }

      if (!mounted) return;
      _goToNext();
    } on CaptchaError catch (e) {
      if (!mounted) return;
      setState(() => _errorText = '${e.message} — Memuat captcha baru...');
      _captchaController.clear();
      _ocrGuess = null;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await _loadCaptcha();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal cek: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _downloadBuktiBayar(TaxRecord record) async {
    try {
      final bytes = await _client.fetchBuktiBayarPdf(
        nop: record.nop,
        tahun: widget.tahun,
      );
      final fileName =
          'Bukti Bayar (${record.namaWajibPajak ?? record.nop}) No. '
          '(${nopBlok(record.nop)}) (${nopWilayah(record.nop)}) (${widget.tahun}).pdf';
      await DownloadHelper.saveBytes(bytes, fileName);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _skip() {
    _current.status = 'Dilewati';
    _goToNext();
  }

  Widget _buildCounterBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: LerpAnimatedCounter(
        value: count,
        formatter: (v) => '$label: ${v.round()}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.records.length;
    final sudahBayarCount = widget.records.where((r) => r.isPaid).length;
    final belumBayarCount = widget.records
        .where((r) => r.isChecked && !r.isPaid && r.status != 'Dilewati')
        .length;
    final dilewatiCount =
        widget.records.where((r) => r.status == 'Dilewati').length;
    final sisaCount = total - _index;

    return Scaffold(
      appBar: AppBar(title: Text('Cek Status Bayar (${_index + 1}/$total)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LerpAnimatedProgress(
                value: total == 0 ? 0 : (_index + 1) / total,
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildCounterBadge(
                    label: 'Sudah',
                    count: sudahBayarCount,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildCounterBadge(
                    label: 'Belum',
                    count: belumBayarCount,
                    color: Colors.orange,
                  ),
                  if (dilewatiCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildCounterBadge(
                      label: 'Lewat',
                      count: dilewatiCount,
                      color: Colors.grey,
                    ),
                  ],
                  const Spacer(),
                  _buildCounterBadge(
                    label: 'Sisa',
                    count: sisaCount,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'NOP',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          if (nopBlok(_current.nop).isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Blok ${nopBlok(_current.nop)}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _current.nop,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text('Tahun Pajak: ${widget.tahun}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    final next = !_autoOcrEnabled;
                    setState(() {
                      _autoOcrEnabled = next;
                      if (!next) {
                        _ocrRunning = false;
                        _ocrGuess = null;
                      } else if (_captchaBytes != null && !_loadingCaptcha) {
                        _ocrRunning = true;
                        _recognizeCaptcha(_captchaBytes!);
                      }
                    });
                    _captchaFocusNode.requestFocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _autoOcrEnabled,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) {
                              final next = val ?? false;
                              setState(() {
                                _autoOcrEnabled = next;
                                if (!next) {
                                  _ocrRunning = false;
                                  _ocrGuess = null;
                                } else if (_captchaBytes != null &&
                                    !_loadingCaptcha) {
                                  _ocrRunning = true;
                                  _recognizeCaptcha(_captchaBytes!);
                                }
                              });
                              _captchaFocusNode.requestFocus();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Auto-complete CAPTCHA',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.amber.shade700,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'Eksperimental',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: _loadingCaptcha
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      )
                    : _captchaBytes != null
                    ? Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.memory(_captchaBytes!, height: 84),
                          ),
                          const SizedBox(height: 8),
                          if (_ocrRunning && _autoOcrEnabled)
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Membaca captcha dengan Google OCR...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            )
                          else if (_ocrGuess != null && _autoOcrEnabled)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 14,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Tebakan OCR: "$_ocrGuess"',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : const Text('Captcha belum dimuat'),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton.icon(
                  onPressed: _loadingCaptcha ? null : _loadCaptcha,
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
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Kode Verifikasi',
                      hintText: '5-6 huruf captcha',
                      border: const OutlineInputBorder(),
                      helperText: (_autoOcrEnabled && _ocrGuess != null)
                          ? 'Otomatis terisi dari Google OCR. Tekan Enter untuk lanjut.'
                          : 'Masukkan huruf dari gambar di atas',
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Cek & Lanjut'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _submitting ? null : _skip,
                    child: const Text('Lewati'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_errorText != null)
                Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
  }
}
