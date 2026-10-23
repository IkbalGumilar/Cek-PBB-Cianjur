import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'bansos_client.dart';
import 'nik_scanner.dart';

class DesilView extends StatefulWidget {
  final BansosClient? client;

  const DesilView({super.key, this.client});

  @override
  State<DesilView> createState() => DesilViewState();
}

class DesilViewState extends State<DesilView> {
  late final BansosClient _client = widget.client ?? BansosClient();
  final _nikScanner = NikScanner();
  final _nikController = TextEditingController();
  final _captchaController = TextEditingController();
  final _captchaFocus = FocusNode();
  final _scrollController = ScrollController();

  Uint8List? _captchaImage;
  BansosResult? _result;
  String? _errorText;
  bool _loadingCaptcha = false;
  bool _scanningNik = false;
  bool _submitting = false;
  bool _nikFromOcr = false;
  bool _applyingOcrNik = false;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _nikController.dispose();
    _captchaController.dispose();
    _captchaFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha({bool clearError = true}) async {
    setState(() {
      _loadingCaptcha = true;
      if (clearError) _errorText = null;
    });
    try {
      final image = await _client.fetchCaptchaImage();
      if (mounted) setState(() => _captchaImage = image);
    } on BansosException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal memuat captcha. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingCaptcha = false);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_nikFromOcr) {
      setState(() => _nikFromOcr = false);
    }
    final nik = _nikController.text.trim();
    final captcha = _captchaController.text.trim();
    if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
      setState(
        () => _errorText = 'NIK harus terdiri dari tepat 16 digit angka.',
      );
      return;
    }
    if (captcha.isEmpty) {
      setState(
        () => _errorText = 'Masukkan huruf kode captcha terlebih dahulu.',
      );
      _captchaFocus.requestFocus();
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
      _result = null;
    });
    try {
      final result = await _client.checkByNik(nik: nik, captcha: captcha);
      if (!mounted) return;
      setState(() {
        _result = result;
        _nikController.clear();
        _captchaController.clear();
      });
      _scrollToTop();
      await _loadCaptcha();
    } on BansosException catch (error) {
      if (!mounted) return;
      final shouldRefocusCaptcha = error.kind == BansosErrorKind.captcha;
      setState(() {
        _errorText = error.message;
        _captchaController.clear();
      });
      await _loadCaptcha(clearError: false);
      if (mounted) {
        if (shouldRefocusCaptcha) {
          _captchaFocus.requestFocus();
        } else {
          FocusScope.of(context).unfocus();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal menghubungi layanan. Periksa koneksi lalu coba lagi.',
        );
      }
      await _loadCaptcha(clearError: false);
      if (mounted) FocusScope.of(context).unfocus();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onNikChanged(String value) {
    if (!_applyingOcrNik && _nikFromOcr) {
      setState(() => _nikFromOcr = false);
    }
    if (_errorText != null && value.length <= 16) {
      setState(() => _errorText = null);
    }
    if (value.length == 16 && RegExp(r'^\d{16}$').hasMatch(value)) {
      _focusCaptcha();
    }
  }

  void _focusCaptcha() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captchaFocus.requestFocus();
    });
  }

  Future<void> _scanAndFillNik() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Scan NIK dari Dokumen'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ImageSource.camera),
            child: const ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Kamera'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ImageSource.gallery),
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
      _scanningNik = true;
      _errorText = null;
    });
    try {
      final candidates = await _nikScanner.scan(source: source);
      if (!mounted) return;
      if (candidates == null || candidates.isEmpty) {
        setState(
          () => _errorText = 'NIK 16 digit tidak ditemukan pada dokumen.',
        );
        return;
      }

      final selected = candidates.length == 1
          ? candidates.first
          : await _showNikCandidates(candidates);
      if (!mounted || selected == null) return;

      _applyingOcrNik = true;
      _nikController.value = TextEditingValue(
        text: selected,
        selection: TextSelection.collapsed(offset: selected.length),
      );
      _applyingOcrNik = false;
      setState(() => _nikFromOcr = true);
      _focusCaptcha();
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'OCR offline tidak dapat memproses gambar ini. Coba foto lebih dekat dan terang.',
        );
      }
    } finally {
      if (mounted) setState(() => _scanningNik = false);
    }
  }

  Future<String?> _showNikCandidates(List<String> candidates) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? selected;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Pilih NIK'),
            content: SizedBox(
              width: 360,
              height: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lebih dari satu nomor 16 digit terdeteksi. Pilih NIK yang benar:',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: selected,
                      onChanged: (value) =>
                          setDialogState(() => selected = value),
                      child: ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          return RadioListTile<String>(
                            value: candidate,
                            title: Text(candidate),
                            contentPadding: EdgeInsets.zero,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, selected),
                child: const Text('Gunakan NIK'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Menangani tombol back dari perangkat.
  /// Jika sedang menampilkan hasil pengecekan, kembali dulu ke menu/form awal.
  /// Mengembalikan true jika event berhasil ditangani (jangan keluar aplikasi).
  bool handleBack() {
    if (_result != null) {
      _reset();
      _scrollToTop();
      return true;
    }
    return false;
  }

  void _reset() {
    setState(() {
      _result = null;
      _errorText = null;
      _nikController.clear();
      _captchaController.clear();
    });
    _loadCaptcha();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _result == null ? _form(context) : _resultView(context),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cek Desil & Bansos',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Masukkan NIK dan huruf kode dari layanan Kemensos.'),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _nikController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 16,
                  onChanged: _onNikChanged,
                  onSubmitted: (value) {
                    if (value.length == 16 &&
                        RegExp(r'^\d{16}$').hasMatch(value)) {
                      _focusCaptcha();
                    } else {
                      setState(
                        () => _errorText =
                            'NIK harus terdiri dari tepat 16 digit angka.',
                      );
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'NIK (Nomor Induk Kependudukan)',
                    hintText: 'Masukkan 16 digit NIK',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _scanningNik
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filledTonal(
                      onPressed: _scanAndFillNik,
                      icon: const Icon(Icons.document_scanner_outlined),
                      tooltip: 'Scan NIK dari KTP atau KK (offline)',
                    ),
            ],
          ),
          if (_nikFromOcr) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFF3CD),
                border: Border.all(color: Color(0xFFFFD166)),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFF8A6500)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'NIK diperoleh dari OCR. Periksa kembali setiap angka dengan KTP atau KK sebelum mencari data.',
                        style: TextStyle(color: Color(0xFF5F4800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Pastikan NIK sesuai dengan KTP.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Text('HURUF KODE', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Center(
            child: _loadingCaptcha
                ? const SizedBox(
                    height: 84,
                    width: 84,
                    child: CircularProgressIndicator(),
                  )
                : _captchaImage == null
                ? const Text('Captcha belum dimuat')
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Image.memory(_captchaImage!, height: 84),
                  ),
          ),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: _loadingCaptcha ? null : _loadCaptcha,
              icon: const Icon(Icons.refresh),
              label: const Text('Ganti Captcha'),
            ),
          ),
          TextField(
            controller: _captchaController,
            focusNode: _captchaFocus,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              labelText: 'Huruf kode',
              hintText: 'Ketik huruf kode di atas',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Setelah mengetik captcha, tekan tombol Cari Data.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 16),
            _messageCard(context, _errorText!, isError: true),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting || _loadingCaptcha ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(_submitting ? 'Mencari...' : 'Cari Data'),
          ),
        ],
      ),
    ),
  );

  Widget _resultView(BuildContext context) {
    final result = _result!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hasil Pencarian Data',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (result.periodeDtsen.isNotEmpty)
                  Chip(label: Text(result.periodeDtsen)),
              ],
            ),
            const SizedBox(height: 16),
            _infoCard(context, 'Penerima Manfaat', {
              'Nama': result.nama,
              'Desil': result.desil,
              'Status KPD': result.statusKpd,
            }),
            const SizedBox(height: 12),
            _infoCard(context, 'Sembako', {
              'Status': result.sembakoStatus,
              'Periode': result.sembakoPeriode,
            }),
            const SizedBox(height: 12),
            _infoCard(context, 'PKH', {
              'Status': result.pkhStatus,
              'Periode': result.pkhPeriode,
            }),
            const SizedBox(height: 12),
            _infoCard(context, 'PBI-JK', {
              'Status': result.pbiJkStatus,
              'Periode': result.pbiJkPeriode,
              'Keterangan PBI': result.keteranganPbi,
            }),
            const SizedBox(height: 16),
            _messageCard(
              context,
              'Desil bersifat dinamis. Perubahan data dapat diajukan melalui desa/kelurahan, dinas sosial, atau aplikasi Cek Bansos resmi.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Kembali'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(
    BuildContext context,
    String title,
    Map<String, String> fields,
  ) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in fields.entries)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Text(': '),
                  Expanded(child: SelectableText(entry.value)),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _messageCard(
    BuildContext context,
    String text, {
    bool isError = false,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: isError
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    ),
  );
}
