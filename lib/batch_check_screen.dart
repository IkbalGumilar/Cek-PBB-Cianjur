import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blok_data_store.dart';
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

  const BatchCheckScreen({
    super.key,
    required this.records,
    required this.tahun,
    this.downloadBuktiBayar = false,
    this.client,
  });

  @override
  State<BatchCheckScreen> createState() => _BatchCheckScreenState();
}

class _BatchCheckScreenState extends State<BatchCheckScreen> {
  late final PbbClient _client;
  final _captchaController = TextEditingController();
  final _captchaFocusNode = FocusNode();

  int _index = 0;
  Uint8List? _captchaBytes;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  String? _errorText;

  TaxRecord get _current => widget.records[_index];

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? PbbClient();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _captchaController.dispose();
    _captchaFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha({bool clearError = true}) async {
    setState(() {
      _loadingCaptcha = true;
      if (clearError) _errorText = null;
    });
    try {
      final bytes = await _client.fetchCaptchaImage(CheckMode.statusBayar);
      if (!mounted) return;
      setState(() {
        _captchaBytes = bytes;
        _loadingCaptcha = false;
      });
      _captchaFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Gagal memuat kode gambar: $e';
        _loadingCaptcha = false;
      });
    }
  }

  void _goToNext() {
    _captchaController.clear();
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
      setState(() => _errorText = e.message);
      _captchaController.clear();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await _loadCaptcha(clearError: false);
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Cek Status Bayar (${_index + 1}/$total)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LerpAnimatedProgress(
                    value: total == 0 ? 0 : (_index + 1) / total,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
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
                        color: scheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Blok ${nopBlok(_current.nop)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _current.nop,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tahun Pajak: ${widget.tahun}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Image.memory(
                                          _captchaBytes!,
                                          height: 84,
                                        ),
                                      )
                                    : const Text('Captcha belum dimuat'),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton.icon(
                              onPressed:
                                  _loadingCaptcha ? null : () => _loadCaptcha(),
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
                                  hintText: 'Ketik huruf pada gambar di atas',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  suffixIcon: value.text.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.clear, size: 20),
                                          tooltip: 'Hapus teks',
                                          onPressed: () {
                                            _captchaController.clear();
                                            _captchaFocusNode.requestFocus();
                                          },
                                        )
                                      : null,
                                ),
                                onSubmitted: (_) =>
                                    _submitting ? null : _submit(),
                              );
                            },
                          ),
                          if (_errorText != null) ...[
                            const SizedBox(height: 12),
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
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
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
                                      : const Icon(Icons.check_circle_outline),
                                  label: const Text('Cek & Lanjut'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: _submitting ? null : _skip,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 13,
                                  ),
                                ),
                                child: const Text('Lewati'),
                              ),
                            ],
                          ),
                        ],
                      ),
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
