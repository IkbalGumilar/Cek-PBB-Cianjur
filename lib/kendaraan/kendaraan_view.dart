import 'dart:developer' as developer;
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../currency_format.dart';
import '../feature_tour/feature_tour.dart';
import '../ui/app_design_system.dart';
import 'kendaraan_client.dart';
import 'plat_scanner.dart';

class KendaraanView extends StatefulWidget {
  const KendaraanView({
    super.key,
    this.client,
    this.scrollController,
    this.emergencyFabKey,
    this.isActive = false,
  });

  final KendaraanClient? client;
  final ScrollController? scrollController;
  final GlobalKey? emergencyFabKey;
  final bool isActive;

  @override
  State<KendaraanView> createState() => KendaraanViewState();
}

class KendaraanViewState extends State<KendaraanView>
    with WidgetsBindingObserver {
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

  final _plateFormKey = GlobalKey(debugLabel: 'tour_kendaraan_plate');
  final _scanPlateButtonKey = GlobalKey(debugLabel: 'tour_kendaraan_scan');
  final _colorChipsKey = GlobalKey(debugLabel: 'tour_kendaraan_color');
  final _submitButtonKey = GlobalKey(debugLabel: 'tour_kendaraan_submit');
  final _officialLinkKey = GlobalKey(debugLabel: 'tour_kendaraan_official');

  KendaraanInfo? _result;
  String? _errorText;
  KendaraanErrorKind? _errorKind;
  String _color = '1';
  bool _loading = false;
  bool _scanningPlate = false;
  String? _plateOcrWarning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _maybeStartTour();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      clearSessionData();
    }
  }

  @override
  void didUpdateWidget(KendaraanView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      clearSessionData();
      return;
    }
    if (!oldWidget.isActive && widget.isActive) {
      _maybeStartTour();
    }
  }

  /// Menghapus seluruh data plat nomor dan hasil cek kendaraan dari memori.
  void clearSessionData() {
    if (!mounted) return;
    setState(() {
      _result = null;
      _errorText = null;
      _errorKind = null;
      _plateOcrWarning = null;
      _color = '1';
      _loading = false;
      _scanningPlate = false;
      _frontController.clear();
      _numberController.clear();
      _backController.clear();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _maybeStartTour() {
    if (!mounted || !widget.isActive) return;
    FeatureTourController.startTourIfNeeded(
      context: context,
      tourId: 'kendaraan_view',
      steps: _buildTourSteps(),
    );
  }

  void showTour() {
    if (!mounted) return;
    FeatureTourController.showTour(
      context: context,
      tourId: 'kendaraan_view',
      steps: _buildTourSteps(),
    );
  }

  List<FeatureTourStep> _buildTourSteps() {
    return [
      FeatureTourStep(
        targetKey: _plateFormKey,
        title: 'Kolom Nomor Polisi (Plat Kendaraan)',
        description:
            'Ketik nomor plat kendaraan Jawa Barat yang ingin diperiksa pada tiga bagian kotak ini:\n'
            '• Kotak kiri: Kode wilayah huruf depan (contoh: F untuk Cianjur/Bogor/Sukabumi, atau D untuk Bandung).\n'
            '• Kotak tengah: Angka nomor polisi (1 sampai 4 angka).\n'
            '• Kotak kanan: Huruf seri belakang.',
        actionHint:
            'Kursor akan otomatis berpindah ke kotak berikutnya saat bagian depan selesai diisi.',
        icon: Icons.directions_car_outlined,
      ),
      FeatureTourStep(
        targetKey: _scanPlateButtonKey,
        title: 'Tombol Foto / Pindai Plat Nomor',
        description:
            'Jika menggunakan ponsel, tekan tombol ini untuk memotret langsung plat nomor kendaraan atau memilih foto dari galeri agar nomor plat otomatis terisi.',
        actionHint:
            'Pastikan foto plat diambil dari jarak cukup dekat, lurus, dan tidak silau.',
        icon: Icons.document_scanner_outlined,
      ),
      FeatureTourStep(
        targetKey: _colorChipsKey,
        title: 'Pilihan Warna Plat Kendaraan',
        description:
            'Pilih jenis warna dasar plat kendaraan:\n'
            '• Hitam / Putih: Untuk kendaraan pribadi milik warga.\n'
            '• Merah: Untuk kendaraan dinas pemerintahan.\n'
            '• Kuning: Untuk kendaraan angkutan umum.',
        actionHint:
            'Kendaraan pribadi berplat putih terbaru maupun plat hitam lama sama-sama memilih "Hitam / Putih".',
        icon: Icons.palette_outlined,
      ),
      FeatureTourStep(
        targetKey: _submitButtonKey,
        title: 'Tombol Lihat Info Pajak Kendaraan',
        description:
            'Tekan tombol ini untuk menampilkan merek/tipe kendaraan, masa berlaku pajak tahunan & STNK 5 tahunan, serta rincian nominal pokok dan denda pajak kendaraan.',
        actionHint:
            'Hasil rincian pajak kendaraan akan langsung ditampilkan di bagian bawah layar ini.',
        icon: Icons.search_rounded,
      ),
      FeatureTourStep(
        targetKey: _officialLinkKey,
        title: 'Tautan Layanan Resmi Bapenda Jabar',
        description:
            'Tekan tombol ini jika Anda ingin membuka halaman informasi pembayaran pajak kendaraan resmi Pemerintah Provinsi Jawa Barat di peramban.',
        icon: Icons.open_in_new_rounded,
      ),
      if (widget.emergencyFabKey?.currentContext != null)
        FeatureTourStep(
          targetKey: widget.emergencyFabKey!,
          title: 'Tombol Kontak Darurat 112 Cianjur',
          description:
              'Akses cepat satu ketuk ke Cianjur Siaga 112, Polres, BPBD, RSUD/PSC 119, Damkar, PLN, SP4N-LAPOR!, serta kontak darurat desa seperti Bidan Desa & Kepala Desa.',
          actionHint:
              'Kontak darurat desa yang Anda tambahkan otomatis tersimpan ke akun Google.',
          icon: Icons.emergency_rounded,
        ),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  static const _jabarPlatePrefixes = {'F', 'D', 'T', 'Z', 'E', 'B'};

  bool get _hasAnyPlateInput =>
      _frontController.text.isNotEmpty ||
      _numberController.text.isNotEmpty ||
      _backController.text.isNotEmpty;

  void _clearPlateInputs() {
    setState(() {
      _frontController.clear();
      _numberController.clear();
      _backController.clear();
      _result = null;
      _errorKind = null;
      _plateOcrWarning = null;
      _errorText = null;
    });
  }

  void _applyQuickPrefix(String prefix) {
    final currentPrefix = _frontController.text.trim().toUpperCase();
    setState(() {
      _frontController.text = prefix;
      if (currentPrefix != prefix) {
        _result = null;
        _errorKind = null;
      }
      _plateOcrWarning = null;
      _errorText = null;
    });
    _numberFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentPrefix = _frontController.text.trim().toUpperCase();

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Banner Sambara Bapenda Jabar
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primaryContainer.withValues(alpha: 0.85),
                              scheme.primaryContainer.withValues(alpha: 0.35),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Image.asset(
                                'logo/Logo-Bapenda-Jabar.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surface.withValues(
                                        alpha: 0.8,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'SAMBARA BAPENDA JABAR',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Info Pajak Kendaraan Bermotor',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cek masa berlaku PKB, STNK, serta rincian pokok & denda kendaraan Jawa Barat.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Label + Tombol Bersihkan Cepat
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'NOMOR POLISI (PLAT KENDARAAN)',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (_hasAnyPlateInput)
                            TextButton.icon(
                              onPressed: _clearPlateInputs,
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              label: const Text('Reset'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Visual Plat Nomor Fisik Beranimasi sesuai Warna Plat
                      _PlateForm(
                        key: _plateFormKey,
                        frontController: _frontController,
                        numberController: _numberController,
                        backController: _backController,
                        numberFocus: _numberFocus,
                        backFocus: _backFocus,
                        plateColorCode: _color,
                        onSubmit: _submit,
                        onChanged: () {
                          _clearPlateOcrWarning();
                          setState(() {
                            _result = null;
                            _errorText = null;
                            _errorKind = null;
                          });
                        },
                      ),
                      const SizedBox(height: 10),

                      // Pintasan Kode Wilayah Jawa Barat + Tombol Scan
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            key: _scanPlateButtonKey,
                            onPressed: _scanningPlate
                                ? null
                                : _scanAndFillPlate,
                            icon: _scanningPlate
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.document_scanner_outlined,
                                    size: 18,
                                  ),
                            label: Text(
                              _scanningPlate
                                  ? 'Membaca plat...'
                                  : 'Foto / Scan Plat',
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          for (final item in const [
                            ('F', 'Cianjur/Bogor/Sukabumi'),
                            ('D', 'Bandung'),
                            ('T', 'Purwakarta/Karawang'),
                            ('Z', 'Garut/Tasik'),
                            ('E', 'Cirebon'),
                            ('B', 'Depok/Bekasi'),
                          ])
                            ActionChip(
                              avatar: Text(
                                item.$1,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: currentPrefix == item.$1
                                      ? scheme.onPrimary
                                      : scheme.primary,
                                ),
                              ),
                              backgroundColor: currentPrefix == item.$1
                                  ? scheme.primaryContainer
                                  : null,
                              label: Text(
                                item.$2,
                                style: const TextStyle(fontSize: 11),
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _applyQuickPrefix(item.$1),
                            ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      AppAnimatedSize(
                        child:
                            currentPrefix.isNotEmpty &&
                                !_jabarPlatePrefixes.contains(currentPrefix)
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: AppAlertBanner(
                                  message:
                                      'Kode wilayah "$currentPrefix" bukan termasuk plat Jawa Barat. '
                                      'Layanan Sambara Bapenda Jabar hanya melayani kendaraan berplat F, D, T, Z, E, atau B (Depok/Bekasi).',
                                  tone: AppBadgeTone.warning,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      if (_plateOcrWarning case final warning?) ...[
                        const SizedBox(height: 10),
                        AppAlertBanner(
                          message: warning,
                          tone: AppBadgeTone.warning,
                        ),
                      ],
                      const SizedBox(height: 18),

                      Text(
                        'WARNA DASAR PLAT NOMOR',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        key: _colorChipsKey,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _colorChip(
                            '1',
                            'Hitam / Putih (Pribadi)',
                            const Color(0xFF1E293B),
                            Colors.white,
                          ),
                          _colorChip(
                            '2',
                            'Merah (Dinas)',
                            const Color(0xFFB91C1C),
                            Colors.white,
                          ),
                          _colorChip(
                            '3',
                            'Kuning (Angkutan Umum)',
                            const Color(0xFFF59E0B),
                            Colors.black87,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const AppAlertBanner(
                        message:
                            'Data diambil langsung dari layanan PKB resmi Jawa Barat. Jika layanan sedang sibuk, coba lagi beberapa saat kemudian.',
                        tone: AppBadgeTone.info,
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _errorText == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _ErrorCard(text: _errorText!),
                                    if (_errorKind ==
                                        KendaraanErrorKind.network) ...[
                                      const SizedBox(height: 8),
                                      _OfficialFallbackActions(
                                        onWhatsApp: _openWhatsApp,
                                        onOfficialPage: _openOfficialPage,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                      ),

                      const SizedBox(height: 18),
                      FilledButton.icon(
                        key: _submitButtonKey,
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.search_rounded),
                        label: Text(
                          _loading
                              ? 'Mengambil Data Sambara...'
                              : 'Lihat Info Pajak Kendaraan',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          key: _officialLinkKey,
                          onPressed: _openOfficialPage,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Buka layanan resmi Bapenda Jabar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: _result == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(_result!.nomorPolisi),
                        padding: const EdgeInsets.only(top: 20),
                        child: _KendaraanResult(
                          result: _result!,
                          titleKey: _resultTitleKey,
                          plateColorCode: _color,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorChip(
    String value,
    String label,
    Color plateBg,
    Color plateBorder,
  ) {
    final selected = _color == value;
    return ChoiceChip(
      avatar: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: plateBg,
          shape: BoxShape.circle,
          border: Border.all(color: plateBorder, width: 1.5),
        ),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) {
        if (_color == value) return;
        setState(() {
          _color = value;
          _result = null;
          _errorText = null;
          _errorKind = null;
        });
      },
    );
  }
}

class _PlateForm extends StatelessWidget {
  final TextEditingController frontController;
  final TextEditingController numberController;
  final TextEditingController backController;
  final FocusNode numberFocus;
  final FocusNode backFocus;
  final String plateColorCode;
  final VoidCallback onSubmit;
  final VoidCallback? onChanged;

  const _PlateForm({
    super.key,
    required this.frontController,
    required this.numberController,
    required this.backController,
    required this.numberFocus,
    required this.backFocus,
    this.plateColorCode = '1',
    required this.onSubmit,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRed = plateColorCode == '2';
    final isYellow = plateColorCode == '3';

    final Color bgColor = isRed
        ? const Color(0xFFB71C1C)
        : isYellow
        ? const Color(0xFFF59E0B)
        : const Color(0xFF111827);
    final Color fgColor = isYellow ? const Color(0xFF111827) : Colors.white;
    final Color hintColor = isYellow
        ? const Color(0xFF111827).withValues(alpha: 0.38)
        : Colors.white54;
    final Color dividerColor = isYellow
        ? const Color(0xFF111827).withValues(alpha: 0.25)
        : Colors.white24;
    final Color innerBorderColor = isYellow
        ? const Color(0xFF111827).withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.75);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: innerBorderColor, width: 1.6),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fontSize = (constraints.maxWidth / 12.2).clamp(18.0, 28.0);
            final letterSpacing = constraints.maxWidth < 320 ? 1.0 : 2.5;
            final fields = [
              _plateField(
                controller: frontController,
                focusNode: null,
                nextFocus: numberFocus,
                hint: 'F',
                subLabel: 'WILAYAH',
                maxLength: 2,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                fgColor: fgColor,
                hintColor: hintColor,
                bgColor: bgColor,
                keyboard: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                  UpperCaseTextFormatter(),
                ],
                onChanged: () {
                  onChanged?.call();
                  if (frontController.text.length >= 2) {
                    numberFocus.requestFocus();
                  }
                },
              ),
              _plateField(
                controller: numberController,
                focusNode: numberFocus,
                nextFocus: backFocus,
                hint: '1234',
                subLabel: 'NOMOR',
                maxLength: 4,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                fgColor: fgColor,
                hintColor: hintColor,
                bgColor: bgColor,
                keyboard: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: () {
                  onChanged?.call();
                  if (numberController.text.length >= 4) {
                    backFocus.requestFocus();
                  }
                },
              ),
              _plateField(
                controller: backController,
                focusNode: backFocus,
                nextFocus: null,
                hint: 'ABC',
                subLabel: 'SERI',
                maxLength: 3,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                fgColor: fgColor,
                hintColor: hintColor,
                bgColor: bgColor,
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
                      width: 1.5,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: dividerColor,
                    ),
                  Expanded(flex: const [3, 5, 4][i], child: fields[i]),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _plateField({
    required TextEditingController controller,
    required FocusNode? focusNode,
    required FocusNode? nextFocus,
    required String hint,
    required String subLabel,
    required int maxLength,
    required double fontSize,
    required double letterSpacing,
    required Color fgColor,
    required Color hintColor,
    required Color bgColor,
    required TextInputType keyboard,
    required List<TextInputFormatter> inputFormatters,
    VoidCallback? onChanged,
  }) {
    final textStyle = TextStyle(
      color: fgColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: letterSpacing,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
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
          cursorColor: fgColor,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 6,
            ),
            hintText: hint,
            hintStyle: textStyle.copyWith(color: hintColor),
            counterText: '',
            border: InputBorder.none,
            filled: true,
            fillColor: bgColor,
          ),
        ),
        Text(
          subLabel,
          style: TextStyle(
            color: hintColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
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
    return AppAlertBanner(message: text, tone: AppBadgeTone.error);
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
  final String plateColorCode;

  const _KendaraanResult({
    required this.result,
    this.titleKey,
    this.plateColorCode = '1',
  });

  void _copySummary(BuildContext context) {
    final buf = StringBuffer()
      ..writeln('INFO PAJAK KENDARAAN BERMOTOR (JABAR)')
      ..writeln('Nomor Polisi : ${result.nomorPolisi}')
      ..writeln('Kendaraan    : ${result.merk} ${result.model} (${result.tahunBuatan})')
      ..writeln('Wilayah      : ${result.wilayah}')
      ..writeln('Jatuh Tempo  : ${result.tanggalPajak}')
      ..writeln('Akhir STNK   : ${result.tanggalStnk}')
      ..writeln('Total Biaya  : ${formatRupiah(result.total)}');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ringkasan pajak kendaraan disalin ke papan klip.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRed = plateColorCode == '2';
    final isYellow = plateColorCode == '3';
    final plateBg = isRed
        ? const Color(0xFFB71C1C)
        : isYellow
        ? const Color(0xFFF59E0B)
        : const Color(0xFF111827);
    final plateFg = isYellow ? const Color(0xFF111827) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Hero Summary Banner Kendaraan + Count-Up Estimasi Total Pajak
        AppAnimatedReveal(
          duration: const Duration(milliseconds: 220),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: scheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          key: titleKey,
                          'Detail Kendaraan Anda',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _copySummary(context),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: 'Salin Ringkasan Pajak',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      // Mini Physical Plate Badge + Merek/Model
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: plateBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: plateFg.withValues(alpha: 0.7),
                                width: 1.4,
                              ),
                            ),
                            child: Text(
                              result.nomorPolisi,
                              style: TextStyle(
                                color: plateFg,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${result.merk} ${result.model}'.trim(),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${result.jenis} • Tahun ${result.tahunBuatan} • ${result.wilayah}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Animated Count-Up Total Tagihan
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL ESTIMASI PAJAK',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: 0,
                                end: result.total.toDouble(),
                              ),
                              duration: const Duration(milliseconds: 650),
                              curve: Curves.easeOutCubic,
                              builder: (context, val, _) => Text(
                                formatRupiah(val.round()),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        if (result.keterangan case final message?) ...[
          const SizedBox(height: 10),
          AppAnimatedReveal(
            duration: const Duration(milliseconds: 260),
            child: AppAlertBanner(message: message, tone: AppBadgeTone.warning),
          ),
        ],
        const SizedBox(height: 12),

        // 2. Tiga Kartu Detail Beranimasi Bertingkat
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final cards = [
              AppAnimatedReveal(
                duration: const Duration(milliseconds: 280),
                child: _InfoCard(
                  title: 'Informasi Kendaraan',
                  icon: Icons.directions_car_outlined,
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
              ),
              AppAnimatedReveal(
                duration: const Duration(milliseconds: 350),
                child: _InfoCard(
                  title: 'Informasi Pajak dan PNBP',
                  icon: Icons.event_note_rounded,
                  rows: {
                    'Masa berlaku pajak': result.masaPajak,
                    'Tanggal pajak': result.tanggalPajak,
                    'Tanggal akhir STNK': result.tanggalStnk,
                    'Proses': result.tanggalProses,
                    'Milik ke': result.milikKe,
                  },
                ),
              ),
              AppAnimatedReveal(
                duration: const Duration(milliseconds: 420),
                child: _InfoCard(
                  title: 'Informasi Biaya',
                  icon: Icons.receipt_long_rounded,
                  rows: {
                    for (final entry in result.biaya.entries)
                      if (entry.key != 'total')
                        _costLabel(entry.key): formatRupiah(entry.value),
                    'Total': formatRupiah(result.total),
                  },
                  emphasizeLast: true,
                ),
              ),
            ];
            if (!wide) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 12),
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
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, String> rows;
  final bool emphasizeLast;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.emphasizeLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = rows.entries.toList();

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 14,
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              if (emphasizeLast && i == entries.length - 1)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          entries[i].key,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: SelectableText(
                          entries[i].value,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        entries[i].key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: SelectableText(
                        entries[i].value,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
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
