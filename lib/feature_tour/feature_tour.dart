import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu langkah panduan interaktif untuk menjelaskan fungsi sebuah tombol,
/// kolom isian, atau bagian tampilan pada layar yang sedang dibuka.
class FeatureTourStep {
  /// [GlobalKey] dari komponen/tombol yang ingin disorot di layar.
  final GlobalKey targetKey;

  /// Judul singkat nama tombol atau fitur (ramah pengguna, tanpa istilah teknis).
  final String title;

  /// Penjelasan lengkap dan merinci mengenai fungsi tombol serta cara menggunakannya.
  final String description;

  /// Petunjuk praktis / tips penggunaan singkat (opsional).
  final String? actionHint;

  /// Ikon pendamping agar panduan lebih jelas dan menarik secara visual.
  final IconData icon;

  /// Padding tambahan di sekeliling kotak sorotan.
  final EdgeInsets spotlightPadding;

  /// Radius lengkungan kotak sorotan.
  final double borderRadius;

  const FeatureTourStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.actionHint,
    this.icon = Icons.touch_app_rounded,
    this.spotlightPadding = const EdgeInsets.all(6),
    this.borderRadius = 12,
  });
}

/// Penyimpan status panduan per layar/widget agar panduan otomatis tampil
/// hanya satu kali saat pengguna pertama kali membuka widget tersebut,
/// dan dapat diputar ulang kapan saja melalui tombol bantuan (`?`) atau menu Pengaturan.
class FeatureTourStore {
  FeatureTourStore._();

  static const String _prefix = 'feature_tour_completed_v1_';

  /// Daftar seluruh ID panduan widget di aplikasi.
  static const List<String> allTourIds = [
    'check_tagihan_view',
    'check_status_bayar_view',
    'import_batch_view',
    'desil_view',
    'kendaraan_view',
    'dhkp_table_view',
    'dhkp_grafik_view',
    'kolase_foto_screen',
    'monitoring_hub_screen',
    'monitoring_wilayah_screen',
    'pembayaran_kolektif_screen',
    'kelola_anggota_screen',
    'settings_screen',
  ];

  /// Memeriksa apakah panduan untuk [tourId] sudah pernah ditampilkan.
  static Future<bool> hasSeenTour(String tourId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefix$tourId') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Menandai bahwa panduan untuk [tourId] sudah selesai dilihat atau dilewati.
  static Future<void> markTourSeen(String tourId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$tourId', true);
    } catch (_) {}
  }

  /// Menghapus status panduan untuk satu [tourId] tertentu agar tampil kembali.
  static Future<void> resetTour(String tourId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$tourId');
    } catch (_) {}
  }

  /// Mengatur ulang seluruh panduan di semua layar agar aktif kembali saat dibuka.
  static Future<void> resetAllTours() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
      for (final id in allTourIds) {
        await prefs.remove('$_prefix$id');
      }
    } catch (_) {}
  }
}

/// Pengendali utama untuk menampilkan panduan fitur kontekstual per widget
/// di semua platform (Android, iOS, Linux, Windows, macOS).
class FeatureTourController {
  FeatureTourController._();

  /// Instance bersama untuk pemanggilan berbasis objek (`FeatureTourController.instance`).
  static final FeatureTourController instance = FeatureTourController._();

  static OverlayEntry? _activeEntry;
  static String? _activeTourId;

  /// Apakah saat ini sedang ada panduan yang tampil di layar.
  static bool get isShowing => _activeEntry != null;

  /// ID panduan yang sedang tampil (jika ada).
  static String? get activeTourId => _activeTourId;

  /// Menutup panduan yang sedang aktif (misal saat pengguna berpindah layar).
  static void dismissActiveTour() {
    try {
      _activeEntry?.remove();
    } catch (_) {}
    _activeEntry = null;
    _activeTourId = null;
  }

  /// Alias metode instance untuk menutup panduan yang sedang aktif.
  void dismiss() => dismissActiveTour();

  /// Memeriksa dan menjalankan panduan secara otomatis saat widget baru dibuka,
  /// hanya jika pengguna belum pernah melihat panduan untuk [tourId] tersebut.
  ///
  /// Otomatis dilewati saat berjalan di dalam lingkungan pengujian otomatis
  /// (`WidgetsBinding.instance.runtimeType.toString().contains('Test')`)
  /// agar tidak menghalangi interaksi pengujian widget.
  static Future<void> startTourIfNeeded({
    required BuildContext context,
    required String tourId,
    required List<FeatureTourStep> steps,
    String? tourTitle,
    Duration delay = const Duration(milliseconds: 550),
  }) async {
    // Jangan jalankan otomatis di dalam flutter test agar widget test tetap bersih
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.contains('TestWidgetsFlutterBinding') ||
        bindingName.contains('AutomatedTestWidgetsFlutterBinding')) {
      return;
    }

    final seen = await FeatureTourStore.hasSeenTour(tourId);
    if (seen) return;

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!context.mounted) return;

    // Periksa kembali apakah ada panduan lain yang sedang tampil
    if (isShowing) return;

    await showTour(
      context: context,
      tourId: tourId,
      steps: steps,
      tourTitle: tourTitle,
      markSeenOnStart: true,
    );
  }

  /// Alias statis untuk [startTourIfNeeded].
  static Future<void> showTourIfNeeded({
    required BuildContext context,
    required String tourId,
    required List<FeatureTourStep> steps,
    String? tourTitle,
    Duration delay = const Duration(milliseconds: 550),
  }) => startTourIfNeeded(
    context: context,
    tourId: tourId,
    steps: steps,
    tourTitle: tourTitle,
    delay: delay,
  );

  /// Alias metode instance untuk menjalankan panduan jika belum pernah dilihat.
  Future<void> showTourIfNotSeen({
    required BuildContext context,
    required String tourId,
    required List<FeatureTourStep> steps,
    String? tourTitle,
    Duration delay = const Duration(milliseconds: 550),
  }) => startTourIfNeeded(
    context: context,
    tourId: tourId,
    steps: steps,
    tourTitle: tourTitle,
    delay: delay,
  );

  /// Menampilkan panduan secara langsung (misalnya ketika pengguna menekan
  /// tombol bantuan `?` di pojok atas layar).
  static Future<void> showTour({
    required BuildContext context,
    required String tourId,
    required List<FeatureTourStep> steps,
    String? tourTitle,
    bool markSeenOnStart = true,
  }) async {
    if (!context.mounted) return;
    dismissActiveTour();

    // Saring hanya langkah-langkah yang komponennya benar-benar sedang tampil di layar
    final validSteps = _filterMountedSteps(steps);
    if (validSteps.isEmpty) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    if (markSeenOnStart) {
      unawaited(FeatureTourStore.markTourSeen(tourId));
    }

    final completer = Completer<void>();
    _activeTourId = tourId;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _FeatureTourOverlayWidget(
        tourId: tourId,
        tourTitle: tourTitle,
        allSteps: steps,
        initialValidSteps: validSteps,
        onFinish: () {
          unawaited(FeatureTourStore.markTourSeen(tourId));
          if (_activeEntry == entry) {
            dismissActiveTour();
          }
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
    return completer.future;
  }

  static List<FeatureTourStep> _filterMountedSteps(
    List<FeatureTourStep> steps,
  ) {
    final result = <FeatureTourStep>[];
    for (final step in steps) {
      final ctx = step.targetKey.currentContext;
      if (ctx != null && ctx.mounted) {
        final renderObj = ctx.findRenderObject();
        if (renderObj is RenderBox && renderObj.hasSize) {
          final size = renderObj.size;
          if (size.width > 0 && size.height > 0) {
            result.add(step);
          }
        } else if (renderObj != null) {
          result.add(step);
        }
      }
    }
    return result;
  }
}

/// Tombol ikon bantuan (`?`) standar yang seragam untuk ditempatkan di AppBar
/// atau header setiap widget agar pengguna dapat memutar ulang panduan fitur kapan saja.
class FeatureTourHelpButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final Color? iconColor;
  final Color? color;

  const FeatureTourHelpButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Panduan Penggunaan Layar Ini',
    this.iconColor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(Icons.help_outline_rounded, color: color ?? iconColor),
      tooltip: tooltip,
    );
  }
}

class _FeatureTourOverlayWidget extends StatefulWidget {
  final String tourId;
  final String? tourTitle;
  final List<FeatureTourStep> allSteps;
  final List<FeatureTourStep> initialValidSteps;
  final VoidCallback onFinish;

  const _FeatureTourOverlayWidget({
    required this.tourId,
    this.tourTitle,
    required this.allSteps,
    required this.initialValidSteps,
    required this.onFinish,
  });

  @override
  State<_FeatureTourOverlayWidget> createState() =>
      _FeatureTourOverlayWidgetState();
}

class _FeatureTourOverlayWidgetState extends State<_FeatureTourOverlayWidget>
    with TickerProviderStateMixin {
  late List<FeatureTourStep> _steps;
  int _currentIndex = 0;
  Rect? _targetRect;

  late final AnimationController _pulseController;
  late final AnimationController _cardController;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _steps = List<FeatureTourStep>.from(widget.initialValidSteps);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _cardFade = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutCubic,
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
        _focusCurrentStep();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cardController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _refreshValidSteps() {
    final refreshed = FeatureTourController._filterMountedSteps(
      widget.allSteps,
    );
    if (refreshed.isNotEmpty) {
      _steps = refreshed;
      if (_currentIndex >= _steps.length) {
        _currentIndex = _steps.length - 1;
      }
    }
  }

  Future<void> _focusCurrentStep() async {
    if (!mounted) return;
    _refreshValidSteps();
    if (_steps.isEmpty) {
      widget.onFinish();
      return;
    }

    _cardController.value = 0;

    final step = _steps[_currentIndex];
    final ctx = step.targetKey.currentContext;

    if (ctx != null && ctx.mounted) {
      final renderBox = ctx.findRenderObject();
      bool needsScroll = true;
      if (renderBox is RenderBox && renderBox.hasSize) {
        final origin = renderBox.localToGlobal(Offset.zero);
        final bottom = origin.dy + renderBox.size.height;
        final screenHeight = MediaQuery.of(context).size.height;
        // Jika elemen target sudah terlihat nyaman di layar (antara Y=70 dan Y=screenHeight-250),
        // tidak perlu scroll paksa agar posisi tidak bergeser aneh.
        if (origin.dy >= 70 && bottom <= (screenHeight - 250)) {
          needsScroll = false;
        }
      }

      if (needsScroll) {
        try {
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.20,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        } catch (_) {}
      }
    }

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final measured = _measureTargetRect(step);
    setState(() {
      _targetRect = measured;
    });
    unawaited(_cardController.forward());
  }

  Rect? _measureTargetRect(FeatureTourStep step) {
    final ctx = step.targetKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return null;

    final rawRect = topLeft & size;
    return step.spotlightPadding.inflateRect(rawRect);
  }

  void _nextStep() {
    HapticFeedback.selectionClick();
    if (_currentIndex < _steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _focusCurrentStep();
    } else {
      widget.onFinish();
    }
  }

  void _prevStep() {
    if (_currentIndex <= 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex--;
    });
    _focusCurrentStep();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _nextStep();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_currentIndex > 0) _prevStep();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onFinish();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) return const SizedBox.shrink();

    final step = _steps[_currentIndex];
    // Perbarui ukuran target secara langsung (real-time) agar selalu pas
    final liveRect = _measureTargetRect(step) ?? _targetRect;

    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final safePadding = media.padding;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Tentukan lebar kartu panduan yang ideal baik di layar HP maupun layar monitor PC
    final double maxCardWidth = math.min(
      440.0,
      math.max(280.0, screenSize.width - 32.0),
    );

    // Hitung posisi vertikal dan horizontal kartu panduan agar tidak menutupi tombol yang sedang disorot
    double cardLeft = (screenSize.width - maxCardWidth) / 2;
    double? cardTop;
    double? cardBottom;
    bool placeBelow = true;
    double maxCardHeight = screenSize.height * 0.65;

    if (liveRect != null) {
      final centerTargetX = liveRect.center.dx;
      cardLeft = (centerTargetX - (maxCardWidth / 2)).clamp(
        16.0,
        math.max(16.0, screenSize.width - maxCardWidth - 16.0),
      );

      final spaceBelow =
          screenSize.height - liveRect.bottom - safePadding.bottom - 24.0;
      final spaceAbove = liveRect.top - safePadding.top - 24.0;

      // Prioritaskan area yang cukup longgar (>= 270px)
      if (spaceBelow >= 270) {
        placeBelow = true;
        cardTop = liveRect.bottom + 12.0;
        cardBottom = null;
        maxCardHeight = spaceBelow;
      } else if (spaceAbove >= 270) {
        placeBelow = false;
        cardBottom = (screenSize.height - liveRect.top) + 12.0;
        cardTop = null;
        maxCardHeight = spaceAbove;
      } else if (spaceBelow >= spaceAbove) {
        placeBelow = true;
        cardTop = math.max(
          safePadding.top + 16.0,
          math.min(liveRect.bottom + 12.0, screenSize.height - 240.0),
        );
        cardBottom = null;
        maxCardHeight = screenSize.height - cardTop - safePadding.bottom - 16.0;
      } else {
        placeBelow = false;
        cardBottom = math.max(
          safePadding.bottom + 16.0,
          math.min(
            (screenSize.height - liveRect.top) + 12.0,
            screenSize.height - 240.0,
          ),
        );
        cardTop = null;
        maxCardHeight = screenSize.height - cardBottom - safePadding.top - 16.0;
      }
    } else {
      cardTop = safePadding.top + 36.0;
      cardBottom = null;
      maxCardHeight = screenSize.height - cardTop - safePadding.bottom - 24.0;
    }

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 1. Latar Belakang Gelap dengan Lubang Sorotan (Spotlight Cutout) + Animasi Denyut
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Ketuk di luar kartu untuk lanjut ke langkah berikutnya dengan mudah
                  _nextStep();
                },
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SpotlightOverlayPainter(
                        targetRect: _measureTargetRect(step) ?? liveRect,
                        borderRadius: step.borderRadius,
                        pulseValue: _pulseController.value,
                        accentColor: scheme.primary,
                        isDark: isDark,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 2. Indikator Panah Penunjuk ke Komponen yang Disorot
            if (liveRect != null)
              Positioned(
                left: (liveRect.center.dx - 14).clamp(
                  24.0,
                  math.max(24.0, screenSize.width - 52.0),
                ),
                top: placeBelow ? (liveRect.bottom + 1) : null,
                bottom: !placeBelow
                    ? (screenSize.height - liveRect.top + 1)
                    : null,
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: _cardFade,
                    child: Icon(
                      placeBelow
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                      size: 26,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),

            // 3. Kartu Penjelasan Fitur yang Responsif & Merinci
            Positioned(
              left: cardLeft,
              width: maxCardWidth,
              top: cardTop,
              bottom: cardBottom,
              child: FadeTransition(
                opacity: _cardFade,
                child: SlideTransition(
                  position: _cardSlide,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: maxCardHeight.clamp(160.0, screenSize.height * 0.75),
                    ),
                    child: _buildTourCard(context, step, scheme, isDark),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTourCard(
    BuildContext context,
    FeatureTourStep step,
    ColorScheme scheme,
    bool isDark,
  ) {
    final total = _steps.length;
    final isLast = _currentIndex == total - 1;

    return Card(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      color: isDark ? const Color(0xFF1E242B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: isDark ? 0.55 : 0.35),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Baris Atas (Pinned): Lencana Langkah + Judul Layar/Tur + Tombol Tutup (X)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Langkah ${_currentIndex + 1} dari $total',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.tourTitle != null &&
                    widget.tourTitle!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.tourTitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                IconButton(
                  onPressed: widget.onFinish,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Tutup Panduan',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ],
            ),
          ),

          // 2. Isi Penjelasan (Scrollable secara halus jika ruang vertikal terbatas)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Judul Fitur & Ikon
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(step.icon, color: scheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          step.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.5,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Teks Penjelasan Fitur
                  Text(
                    step.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.45,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.black87,
                    ),
                  ),

                  // Kotak Tips Tambahan (Bila ada)
                  if (step.actionHint != null &&
                      step.actionHint!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? scheme.primaryContainer.withValues(alpha: 0.25)
                            : scheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step.actionHint!,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.88)
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // 3. Bagian Bawah (Pinned): Indikator Titik Berjarak Luas + Tombol Navigasi
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Indikator Titik: Berada di baris tersendiri dan di tengah agar lega & rapi
                Center(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (int i = 0; i < total; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: i == _currentIndex ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _currentIndex
                                ? scheme.primary
                                : (isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Tombol Navigasi: "Lewati" di kiri, "Sebelumnya" & "Lanjut" di kanan
                Row(
                  children: [
                    TextButton(
                      onPressed: widget.onFinish,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: isDark ? Colors.white60 : Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Lewati'),
                    ),
                    const Spacer(),
                    if (_currentIndex > 0) ...[
                      OutlinedButton(
                        onPressed: _prevStep,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Sebelumnya'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: _nextStep,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      icon: Icon(
                        isLast
                            ? Icons.check_circle_outline_rounded
                            : Icons.arrow_forward_rounded,
                        size: 16,
                      ),
                      label: Text(isLast ? 'Selesai' : 'Lanjut'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightOverlayPainter extends CustomPainter {
  final Rect? targetRect;
  final double borderRadius;
  final double pulseValue;
  final Color accentColor;
  final bool isDark;

  _SpotlightOverlayPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.pulseValue,
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final backdropPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.76 : 0.68)
      ..style = PaintingStyle.fill;

    if (targetRect == null) {
      canvas.drawRect(fullRect, backdropPaint);
      return;
    }

    final clampedRect = Rect.fromLTRB(
      targetRect!.left.clamp(4.0, size.width - 4.0),
      targetRect!.top.clamp(4.0, size.height - 4.0),
      targetRect!.right.clamp(4.0, size.width - 4.0),
      targetRect!.bottom.clamp(4.0, size.height - 4.0),
    );

    final holeRRect = RRect.fromRectAndRadius(
      clampedRect,
      Radius.circular(borderRadius),
    );

    final backdropPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(fullRect)
      ..addRRect(holeRRect);

    canvas.drawPath(backdropPath, backdropPaint);

    // Efek cincin berdenyut di sekeliling komponen yang sedang dijelaskan
    final pulseInflation = 3.0 + (pulseValue * 5.0);
    final outerPulseRRect = RRect.fromRectAndRadius(
      clampedRect.inflate(pulseInflation),
      Radius.circular(borderRadius + pulseInflation),
    );

    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.45 * (1.0 - pulseValue * 0.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawRRect(outerPulseRRect, glowPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(holeRRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark;
  }
}
