import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../feature_tour/feature_tour.dart';
import '../ui/app_design_system.dart';
import '../user_friendly_error.dart';
import 'bansos_client.dart';
import 'nik_scanner.dart';

class DesilView extends StatefulWidget {
  final BansosClient? client;
  final GlobalKey? emergencyFabKey;
  final bool isActive;

  const DesilView({
    super.key,
    this.client,
    this.emergencyFabKey,
    this.isActive = false,
  });

  @override
  State<DesilView> createState() => DesilViewState();
}

class DesilViewState extends State<DesilView> with WidgetsBindingObserver {
  late final BansosClient _client = widget.client ?? BansosClient();
  final _nikScanner = NikScanner();
  final _nikController = TextEditingController();
  final _captchaController = TextEditingController();
  final _captchaFocus = FocusNode();
  final _scrollController = ScrollController();

  final _nikInputKey = GlobalKey(debugLabel: 'tour_desil_nik');
  final _scanNikButtonKey = GlobalKey(debugLabel: 'tour_desil_scan');
  final _captchaAreaKey = GlobalKey(debugLabel: 'tour_desil_captcha_area');
  final _captchaInputKey = GlobalKey(debugLabel: 'tour_desil_captcha_input');
  final _submitButtonKey = GlobalKey(debugLabel: 'tour_desil_submit');

  static const _minNikForCaptcha = 12;

  Uint8List? _captchaImage;
  DateTime? _captchaLoadedAt;
  BansosResult? _result;
  String? _errorText;
  bool _loadingCaptcha = false;
  bool _scanningNik = false;
  bool _submitting = false;
  bool _nikFromOcr = false;
  bool _applyingOcrNik = false;

  bool get _canGenerateCaptcha =>
      _nikController.text.trim().length >= _minNikForCaptcha;

  bool get _isCaptchaStale =>
      _captchaLoadedAt == null ||
      DateTime.now().difference(_captchaLoadedAt!) >
          const Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      if (_canGenerateCaptcha) {
        _loadCaptcha();
      }
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
  void didUpdateWidget(DesilView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      clearSessionData();
      return;
    }
    if (!oldWidget.isActive && widget.isActive) {
      if (_canGenerateCaptcha &&
          (_captchaImage == null || _isCaptchaStale) &&
          !_loadingCaptcha) {
        _loadCaptcha();
      }
      _maybeStartTour();
    }
  }

  /// Menghapus seluruh data input, hasil cek, dan gambar captcha dari memori.
  void clearSessionData() {
    if (!mounted) return;
    setState(() {
      _result = null;
      _errorText = null;
      _nikController.clear();
      _captchaController.clear();
      _captchaImage = null;
      _captchaLoadedAt = null;
      _nikFromOcr = false;
      _applyingOcrNik = false;
      _loadingCaptcha = false;
      _submitting = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _maybeStartTour() {
    if (!mounted || !widget.isActive || _result != null) return;
    FeatureTourController.startTourIfNeeded(
      context: context,
      tourId: 'desil_view',
      steps: _buildTourSteps(),
    );
  }

  void showTour() {
    if (!mounted) return;
    if (_result != null) {
      _reset();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FeatureTourController.showTour(
        context: context,
        tourId: 'desil_view',
        steps: _buildTourSteps(),
      );
    });
  }

  List<FeatureTourStep> _buildTourSteps() {
    return [
      FeatureTourStep(
        targetKey: _nikInputKey,
        title: 'Kolom Nomor Induk Kependudukan (NIK)',
        description:
            'Ketik 16 angka NIK warga sesuai yang tertera pada KTP atau Kartu Keluarga (KK) untuk memeriksa tingkat kesejahteraan (Desil) dan kepesertaan bantuan sosial.',
        actionHint:
            'Begitu 16 angka selesai diketik, kursor akan otomatis berpindah ke kolom huruf kode di bawah.',
        icon: Icons.badge_outlined,
      ),
      if (isMobilePlatform)
        FeatureTourStep(
          targetKey: _scanNikButtonKey,
          title: 'Tombol Pindai Foto KTP atau KK',
          description:
              'Tidak perlu mengetik 16 angka satu per satu! Tekan tombol ini untuk memotret KTP atau Kartu Keluarga warga, dan aplikasi akan otomatis mengenali serta mengisi angka NIK-nya.',
          actionHint:
              'Pastikan foto diambil di tempat terang dan tulisan NIK terlihat jelas.',
          icon: Icons.document_scanner_outlined,
        ),
      FeatureTourStep(
        targetKey: _captchaAreaKey,
        title: 'Gambar Huruf Kode & Tombol Ganti Kode',
        description:
            'Gambar kode akan dimuat otomatis setelah Anda mengisi minimal 12 digit NIK agar tidak mudah kedaluwarsa. Jika gambarnya kurang terbaca, tekan tombol "Ganti Kode" untuk memuat gambar baru.',
        actionHint:
            'Gambar kode diambil langsung dari layanan resmi Kementerian Sosial.',
        icon: Icons.refresh_rounded,
      ),
      FeatureTourStep(
        targetKey: _captchaInputKey,
        title: 'Kolom Pengisian Huruf Kode',
        description:
            'Ketikkan huruf atau angka sesuai gambar kode di atas ke dalam kotak ini.',
        actionHint:
            'Perhatikan kemiripan huruf dan angka sebelum menekan tombol Cari Data.',
        icon: Icons.keyboard_alt_outlined,
      ),
      FeatureTourStep(
        targetKey: _submitButtonKey,
        title: 'Tombol Cari Data Desil & Bantuan Sosial',
        description:
            'Tekan tombol ini untuk menampilkan nama penerima manfaat, kelompok Desil DTSEN, serta status bantuan Sembako, PKH, dan PBI-JK (BPJS Kesehatan Gratis).',
        actionHint:
            'Tekan tombol Kembali jika Anda ingin memeriksa NIK warga lainnya.',
        icon: Icons.search_rounded,
      ),
      if (isMobilePlatform && widget.emergencyFabKey?.currentContext != null)
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
      if (mounted) {
        setState(() {
          _captchaImage = image;
          _captchaLoadedAt = DateTime.now();
        });
      }
    } on BansosException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal memuat gambar kode. Periksa koneksi internet lalu coba lagi.',
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
        _captchaImage = null;
        _captchaLoadedAt = null;
      });
      _scrollToTop();
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
    final trimmed = value.trim();
    if (!_applyingOcrNik && _nikFromOcr) {
      setState(() => _nikFromOcr = false);
    }
    if (_errorText != null && trimmed.length <= 16) {
      setState(() => _errorText = null);
    }
    if (trimmed.length >= _minNikForCaptcha) {
      if ((_captchaImage == null || _isCaptchaStale) && !_loadingCaptcha) {
        _loadCaptcha(clearError: false);
      }
    } else if (_captchaImage != null || _captchaController.text.isNotEmpty) {
      setState(() {
        _captchaImage = null;
        _captchaLoadedAt = null;
        _captchaController.clear();
      });
    }
    if (trimmed.length == 16 && RegExp(r'^\d{16}$').hasMatch(trimmed)) {
      _focusCaptcha();
    }
  }

  void _focusCaptcha() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captchaFocus.requestFocus();
    });
  }

  Future<void> _scanAndFillNik() async {
    if (!isMobilePlatform) return;
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
      if ((_captchaImage == null || _isCaptchaStale) && !_loadingCaptcha) {
        _loadCaptcha(clearError: false);
      }
      _focusCaptcha();
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorText =
              'Gagal membaca gambar. Coba foto KTP atau KK lebih dekat dan terang.',
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
      _captchaImage = null;
      _captchaLoadedAt = null;
    });
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

  int _captchaRefreshTurns = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _result == null
                ? KeyedSubtree(
                    key: const ValueKey('desil_form_view'),
                    child: _form(context),
                  )
                : KeyedSubtree(
                    key: const ValueKey('desil_result_view'),
                    child: _resultView(context),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nikLen = _nikController.text.trim().length;
    final isNikComplete = nikLen == 16;
    final nikProgress = (nikLen / 16).clamp(0.0, 1.0);

    return Column(
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
                // Header Banner DTSEN
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
                          'logo/Kemensos logo.jpeg',
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
                                color: scheme.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'DTSEN KEMENSOS RI',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Cek Desil & Bansos',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pencarian Data Penerima Manfaat (Sembako, PKH, PBI-JK) berdasarkan NIK.',
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

                // Label NIK + Indikator 16 Digit
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'NOMOR INDUK KEPENDUDUKAN (NIK)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isNikComplete
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isNikComplete) ...[
                            Icon(
                              Icons.check_circle_rounded,
                              size: 13,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '$nikLen / 16 digit',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isNikComplete
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 420;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: _nikInputKey,
                            controller: _nikController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            maxLength: 16,
                            onChanged: (val) {
                              setState(() {});
                              _onNikChanged(val);
                            },
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
                            decoration: InputDecoration(
                              labelText: isCompact
                                  ? 'NIK (16 Digit KTP)'
                                  : 'NIK (Nomor Induk Kependudukan)',
                              hintText: 'Masukkan 16 digit NIK sesuai KTP',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              suffixIcon: nikLen > 0
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      tooltip: 'Bersihkan NIK',
                                      onPressed: () {
                                        setState(() {
                                          _nikController.clear();
                                          _captchaController.clear();
                                          _captchaImage = null;
                                          _captchaLoadedAt = null;
                                          _nikFromOcr = false;
                                          _errorText = null;
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              counterText: '',
                            ),
                          ),
                        ),
                        if (isMobilePlatform) ...[
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 56,
                            width: 56,
                            child: _scanningNik
                                ? const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    ),
                                  )
                                : IconButton.filledTonal(
                                    key: _scanNikButtonKey,
                                    onPressed: _scanAndFillNik,
                                    icon: const Icon(
                                      Icons.document_scanner_outlined,
                                    ),
                                    tooltip: 'Pindai NIK dari Foto KTP atau KK',
                                    style: IconButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
                // Bar progres pengisian 16 digit NIK
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: nikProgress),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isNikComplete
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),

                if (_nikFromOcr) ...[
                  const SizedBox(height: 10),
                  const AppAlertBanner(
                    message:
                        'NIK terisi otomatis dari pindaian dokumen. Pastikan 16 digit sudah sesuai KTP/KK.',
                    tone: AppBadgeTone.warning,
                  ),
                ],

                const SizedBox(height: 20),
                Text(
                  'VERIFIKASI HURUF KODE (CAPTCHA)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),

                // Kotak Captcha Interaktif dengan Animasi Transisi & Tombol Putar
                Container(
                  key: _captchaAreaKey,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            height: 74,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _loadingCaptcha
                                  ? Center(
                                      key: const ValueKey('cap_loading'),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Memuat kode...',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    )
                                  : !_canGenerateCaptcha
                                  ? Center(
                                      key: const ValueKey('cap_wait_nik'),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.lock_clock_outlined,
                                            size: 18,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Isi minimal $_minNikForCaptcha digit NIK untuk memuat huruf kode',
                                              textAlign: TextAlign.center,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : _captchaImage == null
                                  ? Center(
                                      key: const ValueKey('cap_empty'),
                                      child: Text(
                                        'Gambar kode belum muncul',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    )
                                  : Container(
                                      key: ValueKey(_captchaImage!.hashCode),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.memory(
                                        _captchaImage!,
                                        height: 70,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed:
                                (_loadingCaptcha || !_canGenerateCaptcha)
                                ? null
                                : () {
                                    setState(() => _captchaRefreshTurns++);
                                    _loadCaptcha();
                                  },
                            icon: AnimatedRotation(
                              turns: _captchaRefreshTurns.toDouble(),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOutBack,
                              child: const Icon(Icons.refresh_rounded),
                            ),
                            label: const Text('Ganti Kode'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: _captchaInputKey,
                        controller: _captchaController,
                        focusNode: _captchaFocus,
                        enabled: _canGenerateCaptcha,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          if (!_submitting && !_loadingCaptcha) {
                            _submit();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Huruf kode',
                          hintText: 'Ketik 4 huruf/angka kode di atas',
                          prefixIcon: const Icon(Icons.key_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Error Banner Beranimasi
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _errorText == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _messageCard(
                            context,
                            _errorText!,
                            isError: true,
                          ),
                        ),
                ),

                const SizedBox(height: 20),
                FilledButton.icon(
                  key: _submitButtonKey,
                  onPressed: _submitting || _loadingCaptcha ? null : _submit,
                  icon: _submitting
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    _submitting ? 'Memeriksa Data DTSEN...' : 'Cari Data',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Mengembalikan `(minDesil, maxDesil)` dari teks desil Kemensos.
  /// Mendukung rentang baru DTSEN (`"1-5"`, `"1 - 5"`, `"1 s/d 5"`, `"6-10"`)
  /// maupun angka tunggal (`"1"`, `"5"`, `"10"`).
  (int, int)? _parseDesilBounds(String raw) {
    final rangeMatch = RegExp(
      r'\b(10|[1-9])\s*(?:[-–—]|s\.?\/?d\.?|sampai)\s*(10|[1-9])\b',
      caseSensitive: false,
    ).firstMatch(raw);
    if (rangeMatch != null) {
      final a = int.tryParse(rangeMatch.group(1)!);
      final b = int.tryParse(rangeMatch.group(2)!);
      if (a != null && b != null) {
        return a <= b ? (a, b) : (b, a);
      }
    }
    final singleMatch = RegExp(r'\b(10|[1-9])\b').firstMatch(raw);
    if (singleMatch == null) return null;
    final val = int.tryParse(singleMatch.group(1)!);
    return val != null ? (val, val) : null;
  }

  String _describeDesilEligibility((int, int)? bounds) {
    if (bounds == null) {
      return 'Kelompok kesejahteraan berdasarkan Data Tunggal Sosial dan Ekonomi Nasional (DTSEN).';
    }
    final (minD, maxD) = bounds;
    if (minD >= 1 && maxD <= 5) {
      return 'Masuk kelompok sasaran program bantuan sosial (PKH, Sembako, & PBI-JK) sesuai ketentuan DTSEN Kemensos.';
    }
    if (minD >= 6) {
      return 'Di luar kelompok prioritas utama bantuan sosial sesuai ketentuan DTSEN Kemensos.';
    }
    return 'Kelompok kesejahteraan keluarga berdasarkan Data Tunggal Sosial dan Ekonomi Nasional (DTSEN).';
  }

  bool _isPositiveStatus(String status) {
    final s = status.trim().toUpperCase();
    if (s.isEmpty || s == '—' || s == '-') return false;
    if (s.contains('TIDAK') || s.contains('NON') || s.contains('BELUM')) {
      return false;
    }
    return s.contains('YA') || s.contains('AKTIF') || s.contains('TERDAFTAR');
  }

  Widget _resultView(BuildContext context) {
    final result = _result!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desilBounds = _parseDesilBounds(result.desil);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Kartu Profil & Peringkat Desil (cb-v4 style)
        AppAnimatedReveal(
          duration: const Duration(milliseconds: 220),
          child: Card(
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Hasil Pencarian Data',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (result.periodeDtsen.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            result.periodeDtsen,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Identitas Penerima Manfaat
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: scheme.onPrimary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NAMA PENERIMA MANFAAT',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                result.nama,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Box Kelompok Kesejahteraan DTSEN (nilai langsung dari Kemensos)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KELOMPOK DESIL DTSEN',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          result.desil,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _describeDesilEligibility(desilBounds),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Kotak Stat Profil Tambahan: Status KPD (Keterangan PBI sudah tampil di kartu PBI-JK)
                  SizedBox(
                    width: double.infinity,
                    child: _miniStatBox(
                      context,
                      label: 'STATUS KPD (DISABILITAS)',
                      value: result.statusKpd,
                      icon: Icons.accessible_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Kartu Program Bansos Beranimasi Bertingkat (Sembako, PKH, PBI-JK)
        AppAnimatedReveal(
          duration: const Duration(milliseconds: 290),
          child: _programCard(
            context,
            title: 'Bantuan Sembako (BPNT)',
            subtitle: 'Bantuan Pangan Non Tunai',
            icon: Icons.shopping_basket_outlined,
            status: result.sembakoStatus,
            periode: result.sembakoPeriode,
          ),
        ),
        const SizedBox(height: 12),
        AppAnimatedReveal(
          duration: const Duration(milliseconds: 360),
          child: _programCard(
            context,
            title: 'Program Keluarga Harapan (PKH)',
            subtitle: 'Bantuan tunai bersyarat keluarga prasejahtera',
            icon: Icons.family_restroom_rounded,
            status: result.pkhStatus,
            periode: result.pkhPeriode,
          ),
        ),
        const SizedBox(height: 12),
        AppAnimatedReveal(
          duration: const Duration(milliseconds: 430),
          child: _programCard(
            context,
            title: 'PBI-JK (BPJS Kesehatan)',
            subtitle: 'Penerima Bantuan Iuran Jaminan Kesehatan',
            icon: Icons.medical_services_outlined,
            status: result.pbiJkStatus,
            periode: result.pbiJkPeriode,
            extraLabel: 'Keterangan PBI',
            extraValue: result.keteranganPbi,
          ),
        ),
        const SizedBox(height: 16),

        AppAnimatedReveal(
          duration: const Duration(milliseconds: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _messageCard(
                context,
                'Desil bersifat dinamis. Perubahan data dapat diajukan melalui desa/kelurahan, dinas sosial, atau aplikasi Cek Bansos resmi.',
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: _reset,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text(
                  'Kembali & Cari NIK Lainnya',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStatBox(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _programCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String status,
    required String periode,
    String? extraLabel,
    String? extraValue,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = _isPositiveStatus(status);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isActive
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isActive
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive
                            ? Icons.check_circle_rounded
                            : Icons.remove_circle_outline_rounded,
                        size: 14,
                        color: isActive
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isActive
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _dlCell(context, label: 'PERIODE', value: periode),
            if (extraLabel != null &&
                extraValue != null &&
                extraValue.trim().isNotEmpty &&
                extraValue != '—') ...[
              const SizedBox(height: 8),
              _dlCell(context, label: extraLabel.toUpperCase(), value: extraValue),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dlCell(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(
    BuildContext context,
    String text, {
    bool isError = false,
  }) => AppAlertBanner(
    message: text,
    tone: isError ? AppBadgeTone.error : AppBadgeTone.info,
  );
}
