import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'blok_data_store.dart';
import 'blok_record.dart';
import 'check_mode.dart';
import 'download_helper.dart';
import 'nop_helper.dart';
import 'operator_mode_store.dart';
import 'pbb_client.dart';
import 'result_screen.dart';
import 'tax_record.dart';
import 'wilayah_kerja_store.dart';

class BatchCheckScreen extends StatefulWidget {
  final List<TaxRecord> records;
  final String tahun;
  final bool downloadBuktiBayar;

  const BatchCheckScreen({
    super.key,
    required this.records,
    required this.tahun,
    this.downloadBuktiBayar = false,
  });

  @override
  State<BatchCheckScreen> createState() => _BatchCheckScreenState();
}

class _BatchCheckScreenState extends State<BatchCheckScreen> {
  final _client = PbbClient();
  final _captchaController = TextEditingController();

  int _index = 0;
  Uint8List? _captchaBytes;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  String? _errorText;

  TaxRecord get _current => widget.records[_index];

  @override
  void initState() {
    super.initState();
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
    if (await OperatorModeStore.instance.isEnabled()) return;
    final dusun = await WilayahKerjaStore.instance.selectedDusun();
    if (dusun == null || !mounted) return;
    final wilayahBloks = await WilayahKerjaStore.instance.whitelistedBloks();
    final hasOutside = widget.records.any(
      (r) => !wilayahBloks.contains(nopBlok(r.nop)),
    );
    if (!hasOutside || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Terdapat blok yang bukan wilayah kerja Anda di daftar ini — tetap bisa dicek, '
          'tapi hasilnya tidak akan dicatat ke Buku Catatan Blok.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  @override
  void dispose() {
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _errorText = null;
    });
    try {
      final bytes = await _client.fetchCaptchaImage(CheckMode.statusBayar);
      if (!mounted) return;
      setState(() => _captchaBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal ambil captcha: $e');
    } finally {
      if (mounted) setState(() => _loadingCaptcha = false);
    }
  }

  void _goToNext() {
    _captchaController.clear();
    if (_index + 1 >= widget.records.length) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(records: widget.records),
        ),
      );
      return;
    }
    setState(() => _index += 1);
    _loadCaptcha();
  }

  Future<void> _submit() async {
    final captcha = _captchaController.text.trim();
    if (captcha.isEmpty) {
      setState(() => _errorText = 'Kode verifikasi wajib diisi.');
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
        final isOperator = await OperatorModeStore.instance.isEnabled();
        if (!mounted) return;
        final wilayahBloks = await WilayahKerjaStore.instance
            .whitelistedBloks();
        if (!mounted) return;
        if (isOperator || wilayahBloks.contains(nopBlok(_current.nop))) {
          await BlokDataStore.instance.upsert(
            BlokRecord(
              nop: _current.nop,
              namaWajibPajak: result.namaWajibPajak ?? '',
              tahunBayar: widget.tahun,
              tanggalBayar: result.tanggalBayar ?? '',
              jumlahPbb: result.jumlahPbb ?? '',
            ),
          );
        }
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

  @override
  Widget build(BuildContext context) {
    final total = widget.records.length;
    return Scaffold(
      appBar: AppBar(title: Text('Cek Status Bayar (${_index + 1}/$total)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: total == 0 ? 0 : _index / total),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NOP',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        _current.nop,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text('Tahun Pajak: ${widget.tahun}'),
                    ],
                  ),
                ),
              ),
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
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _loadingCaptcha ? null : _loadCaptcha,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ganti Captcha'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _captchaController,
                decoration: const InputDecoration(
                  labelText: 'Kode Verifikasi',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitting ? null : _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
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
