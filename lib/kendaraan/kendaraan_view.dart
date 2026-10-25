import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'kendaraan_client.dart';
import 'plat_scanner.dart';

class KendaraanView extends StatefulWidget {
  const KendaraanView({super.key, this.client, this.scrollController});

  final KendaraanClient? client;
  final ScrollController? scrollController;

  @override
  State<KendaraanView> createState() => _KendaraanViewState();
}

class _KendaraanViewState extends State<KendaraanView> {
  late final KendaraanClient _client = widget.client ?? KendaraanClient();
  final _platScanner = PlatScanner();
  final _frontController = TextEditingController();
  final _numberController = TextEditingController();
  final _backController = TextEditingController();
  late final ScrollController _scrollController =
      widget.scrollController ?? ScrollController();
  final _resultTitleKey = GlobalKey();
  final _numberFocus = FocusNode();
  final _backFocus = FocusNode();

  KendaraanInfo? _result;
  String? _errorText;
  KendaraanErrorKind? _errorKind;
  String _color = '1';
  bool _loading = false;
  bool _scanningPlate = false;
  String? _plateOcrWarning;

  @override
  void dispose() {
    _frontController.dispose();
    _numberController.dispose();
    _backController.dispose();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _numberFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final front = _frontController.text.trim().toUpperCase();
    final number = _numberController.text.trim();
    final back = _backController.text.trim().toUpperCase();
    if (_plateOcrWarning != null) {
      setState(() => _plateOcrWarning = null);
    }
    if (!RegExp(r'^[A-Z]{1,2}$').hasMatch(front) ||
        !RegExp(r'^\d{1,4}$').hasMatch(number) ||
        !RegExp(r'^[A-Z]{1,3}$').hasMatch(back)) {
      setState(() {
        _errorText =
            'Isi nomor polisi lengkap: huruf, angka, dan huruf belakang.';
        _errorKind = null;
        _result = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
      _errorKind = null;
      _result = null;
    });
    try {
      final result = await _client.check(
        platDepan: front,
        angka: number,
        platBelakang: back,
        warna: _color,
      );
      if (!mounted) return;
      setState(() => _result = result);
      _scrollToResult();
    } on KendaraanException catch (error) {
      if (mounted) {
        setState(() {
          _errorText = error.message;
          _errorKind = error.kind;
        });
      }
    } catch (e, st) {
      developer.log(
        'Unexpected error while checking vehicle info',
        error: e,
        stackTrace: st,
        name: 'KendaraanView',
      );
      if (mounted) {
        setState(() {
          _errorText =
              'Terjadi kesalahan saat mengambil data kendaraan. Coba lagi.';
          _errorKind = KendaraanErrorKind.service;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanAndFillPlate() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(
        () => _errorText =
            'Scan foto plat tersedia di HP. Pada komputer, ketik nomor plat secara manual.',
      );
      return;
    }

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Scan Plat Nomor'),
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
      _scanningPlate = true;
      _errorText = null;
      _plateOcrWarning = null;
      _result = null;
    });
    try {
      final scan = await _platScanner.scan(source: source);
      if (!mounted || scan == null) return;
      if (scan.candidates.isEmpty) {
        setState(
          () => _errorText =
              'Plat nomor tidak ditemukan. Foto plat lebih dekat, lurus, dan terang.',
        );
        return;
      }
      final selected = scan.candidates.length == 1
          ? scan.candidates.first
          : await _showPlateCandidates(scan.candidates);
      if (!mounted || selected == null) return;

      _frontController.text = selected.front;
      _numberController.text = selected.number;
      _backController.text = selected.back;
      setState(() {
        // API PKB memakai kode 1 untuk kendaraan pribadi. Plat pribadi
        // berwarna hitam maupun putih tetap masuk kategori ini.
        _color = '1';
        _plateOcrWarning =
            'Plat terbaca: ${selected.formatted}. ${scan.colorMessage} Periksa kembali sebelum menekan Lihat Info.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal membaca foto plat. Coba foto plat lebih dekat dan terang.',
        );
      }
    } finally {
      if (mounted) setState(() => _scanningPlate = false);
    }
  }

  Future<PlatCandidate?> _showPlateCandidates(List<PlatCandidate> candidates) {
    return showDialog<PlatCandidate>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Pilih Plat Nomor'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Beberapa kemungkinan plat terdeteksi. Pilih yang sesuai foto:',
            ),
          ),
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, candidate),
              child: Text(
                candidate.formatted,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _clearPlateOcrWarning() {
    if (_plateOcrWarning != null) {
      setState(() => _plateOcrWarning = null);
    }
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultContext = _resultTitleKey.currentContext;
      if (!mounted || resultContext == null) return;
      Scrollable.ensureVisible(
        resultContext,
        alignment: 0.04,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openOfficialPage() async {
    final uri = Uri.parse(
      'https://jabarprov.go.id/layanan/pembayaran-pajak-kendaraan-bermotor-pkb-1690533115',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Halaman resmi tidak dapat dibuka.')),
      );
    }
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse('https://wa.me/6281122301818?text=Halo');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp Bapenda tidak dapat dibuka.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Info Kendaraan Bermotor',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Masukkan nomor polisi kendaraan Jawa Barat yang ingin dicari.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _PlateForm(
                frontController: _frontController,
                numberController: _numberController,
                backController: _backController,
                numberFocus: _numberFocus,
                backFocus: _backFocus,
                onSubmit: _submit,
                onChanged: _clearPlateOcrWarning,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _scanningPlate ? null : _scanAndFillPlate,
                  icon: _scanningPlate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_outlined),
                  label: Text(
                    _scanningPlate
                        ? 'Membaca plat...'
                        : 'Foto / Scan Plat Nomor',
                  ),
                ),
              ),
              if (_plateOcrWarning case final warning?) ...[
                const SizedBox(height: 8),
                Card(
                  color: Colors.amber.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            warning,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Pilih Warna Plat Nomor',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _colorChip('1', 'Hitam / Putih'),
                  _colorChip('2', 'Merah'),
                  _colorChip('3', 'Kuning'),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Data diambil dari layanan PKB resmi Jawa Barat. Jika layanan sedang sibuk, coba lagi beberapa saat kemudian.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(text: _errorText!),
                if (_errorKind == KendaraanErrorKind.network) ...[
                  const SizedBox(height: 8),
                  _OfficialFallbackActions(
                    onWhatsApp: _openWhatsApp,
                    onOfficialPage: _openOfficialPage,
                  ),
                ],
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_loading ? 'Mengambil data...' : 'Lihat Info'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _openOfficialPage,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Buka layanan resmi Jabar'),
              ),
              if (_result case final result?) ...[
                const SizedBox(height: 20),
                _KendaraanResult(result: result, titleKey: _resultTitleKey),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _color == value,
      onSelected: (_) => setState(() => _color = value),
    );
  }
}

class _PlateForm extends StatelessWidget {
  final TextEditingController frontController;
  final TextEditingController numberController;
  final TextEditingController backController;
  final FocusNode numberFocus;
  final FocusNode backFocus;
  final VoidCallback onSubmit;
  final VoidCallback? onChanged;

  const _PlateForm({
    required this.frontController,
    required this.numberController,
    required this.backController,
    required this.numberFocus,
    required this.backFocus,
    required this.onSubmit,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fontSize = (constraints.maxWidth / 12.5).clamp(18.0, 28.0);
          final letterSpacing = constraints.maxWidth < 320 ? 1.0 : 2.0;
          final fields = [
            _plateField(
              controller: frontController,
              focusNode: null,
              nextFocus: numberFocus,
              hint: 'XX',
              maxLength: 2,
              fontSize: fontSize,
              letterSpacing: letterSpacing,
              keyboard: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                UpperCaseTextFormatter(),
              ],
              onChanged: onChanged,
            ),
            _plateField(
              controller: numberController,
              focusNode: numberFocus,
              nextFocus: backFocus,
              hint: 'XXXX',
              maxLength: 4,
              fontSize: fontSize,
              letterSpacing: letterSpacing,
              keyboard: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
            ),
            _plateField(
              controller: backController,
              focusNode: backFocus,
              nextFocus: null,
              hint: 'XXX',
              maxLength: 3,
              fontSize: fontSize,
              letterSpacing: letterSpacing,
              keyboard: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                UpperCaseTextFormatter(),
              ],
              onChanged: onChanged,
            ),
          ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: Colors.white24,
                  ),
                Expanded(flex: const [3, 5, 4][i], child: fields[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _plateField({
    required TextEditingController controller,
    required FocusNode? focusNode,
    required FocusNode? nextFocus,
    required String hint,
    required int maxLength,
    required double fontSize,
    required double letterSpacing,
    required TextInputType keyboard,
    required List<TextInputFormatter> inputFormatters,
    VoidCallback? onChanged,
  }) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      letterSpacing: letterSpacing,
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: maxLength,
      keyboardType: keyboard,
      textInputAction: nextFocus == null
          ? TextInputAction.search
          : TextInputAction.next,
      onSubmitted: (_) {
        if (nextFocus != null) {
          nextFocus.requestFocus();
        } else {
          onSubmit();
        }
      },
      inputFormatters: inputFormatters,
      onChanged: (_) => onChanged?.call(),
      textAlign: TextAlign.center,
      style: textStyle,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        hintText: hint,
        hintStyle: textStyle.copyWith(color: Colors.white54),
        counterText: '',
        border: InputBorder.none,
        filled: true,
        fillColor: Colors.black,
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _ErrorCard extends StatelessWidget {
  final String text;

  const _ErrorCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficialFallbackActions extends StatelessWidget {
  final VoidCallback onWhatsApp;
  final VoidCallback onOfficialPage;

  const _OfficialFallbackActions({
    required this.onWhatsApp,
    required this.onOfficialPage,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onWhatsApp,
          icon: const Icon(Icons.chat_outlined, size: 18),
          label: const Text('Cek lewat WhatsApp Bapenda'),
        ),
        OutlinedButton.icon(
          onPressed: onOfficialPage,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Buka Portal Jabar'),
        ),
      ],
    );
  }
}

class _KendaraanResult extends StatelessWidget {
  final KendaraanInfo result;
  final Key? titleKey;

  const _KendaraanResult({required this.result, this.titleKey});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: titleKey,
          'Detail Kendaraan Anda',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (result.keterangan case final message?) ...[
          const SizedBox(height: 10),
          Card(
            color: Colors.amber.shade100,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                message,
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final cards = [
              _InfoCard(
                title: 'Informasi Kendaraan',
                rows: {
                  'Nomor Polisi': result.nomorPolisi,
                  'Warna KB': result.warna,
                  'Merek': result.merk,
                  'Model': result.model,
                  'Wilayah': result.wilayah,
                  'Jenis': result.jenis,
                  'Tahun': result.tahunBuatan,
                },
              ),
              _InfoCard(
                title: 'Informasi Pajak dan PNBP',
                rows: {
                  'Masa berlaku pajak': result.masaPajak,
                  'Tanggal pajak': result.tanggalPajak,
                  'Tanggal akhir STNK': result.tanggalStnk,
                  'Proses': result.tanggalProses,
                  'Milik ke': result.milikKe,
                },
              ),
              _InfoCard(
                title: 'Informasi Biaya',
                rows: {
                  for (final entry in result.biaya.entries)
                    if (entry.key != 'total')
                      _costLabel(entry.key): _rupiah(entry.value),
                  'Total': _rupiah(result.total),
                },
                emphasizeLast: true,
              ),
            ];
            if (!wide) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static String _costLabel(String key) {
    const labels = {
      'pkb-pokok': 'PKB Pokok',
      'pkb-denda': 'PKB Denda',
      'opsen-pkb-pokok': 'Opsen PKB Pokok',
      'opsen-pkb-denda': 'Opsen PKB Denda',
      'swdkllj-pokok': 'SWDKLLJ Pokok',
      'swdkllj-denda': 'SWDKLLJ Denda',
      'pnbp-stnk': 'PNBP STNK',
      'pnbp-tnkb': 'PNBP TNKB',
      'total': 'Total',
    };
    return labels[key] ?? key;
  }

  static String _rupiah(int value) {
    final text = value.toString();
    final groups = <String>[];
    for (var end = text.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      groups.insert(0, text.substring(start, end));
    }
    return 'Rp ${groups.join('.')}';
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Map<String, String> rows;
  final bool emphasizeLast;

  const _InfoCard({
    required this.title,
    required this.rows,
    this.emphasizeLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final entries = rows.entries.toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      entries[i].key,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: Text(
                      entries[i].value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: emphasizeLast && i == entries.length - 1
                            ? FontWeight.bold
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
