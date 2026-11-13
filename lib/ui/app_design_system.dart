import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Konfigurasi scroll global aplikasi agar geser horizontal/vertikal pada desktop
/// dapat dilakukan memakai drag mouse maupun trackpad seperti sentuhan di HP.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
}

/// Pembungkus tabel horizontal dengan [ScrollController] khusus serta [Scrollbar]
/// interaktif yang selalu terlihat di bawah tabel saat kolom melampaui lebar layar,
/// sehingga mudah digeser memakai mouse/scrollbar di desktop maupun sentuhan di HP.
class AppHorizontalTableScroll extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  const AppHorizontalTableScroll({
    super.key,
    required this.child,
    this.controller,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  @override
  State<AppHorizontalTableScroll> createState() =>
      _AppHorizontalTableScrollState();
}

class _AppHorizontalTableScrollState extends State<AppHorizontalTableScroll> {
  ScrollController? _ownedController;

  ScrollController get _effectiveController =>
      widget.controller ?? (_ownedController ??= ScrollController());

  @override
  void didUpdateWidget(covariant AppHorizontalTableScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && _ownedController != null) {
      _ownedController!.dispose();
      _ownedController = null;
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _effectiveController;
    return ScrollConfiguration(
      behavior: const AppScrollBehavior(),
      child: Scrollbar(
        controller: ctrl,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal &&
            notification.depth == 0,
        child: SingleChildScrollView(
          controller: ctrl,
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Klasifikasi ukuran layar berdasarkan lebar dalam logical pixels (dp).
enum AppScreenClass {
  /// `< 600 dp` — Ponsel (Mobile)
  mobile,

  /// `600 – 1023 dp` — Tablet / Layar Menengah
  tablet,

  /// `>= 1024 dp` — Desktop / Monitor Lebar
  desktop,
}

/// Sistem Breakpoint & Tata Letak Responsif terpusat.
class AppBreakpoints {
  AppBreakpoints._();

  static const double mobileMax = 599.0;
  static const double tabletMin = 600.0;
  static const double tabletMax = 1023.0;
  static const double desktopMin = 1024.0;

  static AppScreenClass ofWidth(double width) {
    if (width >= desktopMin) return AppScreenClass.desktop;
    if (width >= tabletMin) return AppScreenClass.tablet;
    return AppScreenClass.mobile;
  }

  static AppScreenClass of(BuildContext context) {
    return ofWidth(MediaQuery.sizeOf(context).width);
  }

  static bool isMobile(BuildContext context) =>
      of(context) == AppScreenClass.mobile;

  static bool isMobileOf(BuildContext context) => isMobile(context);

  static bool isTablet(BuildContext context) =>
      of(context) == AppScreenClass.tablet;

  static bool isDesktop(BuildContext context) =>
      of(context) == AppScreenClass.desktop;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletMin;

  /// Lebar maksimum konten agar form tidak melebar berlebihan di monitor besar,
  /// namun tabel/dashboard data tetap leluasa.
  static double maxContentWidth(
    double viewportWidth, {
    bool isDataHeavy = false,
    bool isCompactForm = false,
  }) {
    if (isCompactForm) return 520.0;
    if (isDataHeavy) {
      if (viewportWidth >= 1440) return 1380.0;
      if (viewportWidth >= desktopMin) return 1220.0;
      return double.infinity;
    }
    if (viewportWidth >= desktopMin) return 920.0;
    if (viewportWidth >= tabletMin) return 780.0;
    return 760.0;
  }

  /// Padding halaman adaptif berdasarkan lebar layar.
  static EdgeInsets pagePadding(double viewportWidth, {double bottom = 24.0}) {
    if (viewportWidth >= desktopMin) {
      return EdgeInsets.fromLTRB(28, 20, 28, bottom);
    }
    if (viewportWidth >= tabletMin) {
      return EdgeInsets.fromLTRB(20, 18, 20, bottom);
    }
    return EdgeInsets.fromLTRB(16, 16, 16, bottom);
  }
}

/// Token spasi terukur (4, 8, 12, 16, 20, 24, 32).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
}

/// Token radius sudut konsisten untuk komponen.
class AppRadius {
  AppRadius._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double pill = 999.0;
}

/// Sistem Motion Design & Animasi Terpusat.
///
/// Seluruh durasi dan kurva mengikuti pedoman aplikasi finansial/operasional:
/// cepat, responsif, fungsional, dan menghormati preferensi Reduced Motion OS.
class AppMotion {
  AppMotion._();

  /// Micro-interaction: hover, press, focus (`120 ms`).
  static const Duration micro = Duration(milliseconds: 120);

  /// Perubahan state tombol, chip, toggle (`150 ms`).
  static const Duration button = Duration(milliseconds: 150);

  /// Buka/lipat panel filter, kemunculan kartu hasil (`200 ms`).
  static const Duration component = Duration(milliseconds: 200);

  /// Dialog, bottom sheet, perpindahan tab (`240 ms`).
  static const Duration dialog = Duration(milliseconds: 240);

  /// Transisi antar halaman (`260 ms`).
  static const Duration page = Duration(milliseconds: 260);

  /// Transisi metrik KPI count-up / grafik (`340 ms`).
  static const Duration complex = Duration(milliseconds: 340);

  /// Kurva standar elemen masuk ke layar.
  static const Curve enterCurve = Curves.easeOutCubic;

  /// Kurva standar elemen keluar dari layar.
  static const Curve exitCurve = Curves.easeInCubic;

  /// Kurva perubahan ukuran atau posisi.
  static const Curve standardCurve = Curves.fastOutSlowIn;

  /// Kurva mikro-interaksi halus.
  static const Curve smoothCurve = Curves.easeInOutCubic;

  /// Memeriksa apakah pengguna mengaktifkan "Reduce Motion" / "Remove Animations"
  /// pada sistem operasi atau di lingkungan pengujian dengan animasi nonaktif.
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Mengembalikan `Duration.zero` apabila Reduced Motion aktif, atau [normal] jika tidak.
  static Duration resolve(BuildContext context, Duration normal) {
    return isReducedMotion(context) ? Duration.zero : normal;
  }
}

/// PageTransitionsBuilder adaptif yang menghormati Reduced Motion serta memberikan
/// transisi fade + subtle slide yang ringan dan cepat di semua platform.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || AppMotion.isReducedMotion(context)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enterCurve,
      reverseCurve: AppMotion.exitCurve,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.02, 0.0),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

/// Kategori warna semantik untuk lencana status, kartu KPI, dan pesan sistem.
enum AppBadgeTone {
  /// Sudah Bayar / Lunas / Sukses (Hijau)
  paid,

  /// Belum Bayar / Tunggakan / Galat (Merah)
  unpaid,

  /// Perhatian / Denda / Draft / Menunggu (Oranye/Amber)
  warning,

  /// Informasi / Siap Dibayar / Aktif (Biru/Teal)
  info,

  /// Netral / Nonaktif / Arsip (Abu-abu)
  neutral;

  static const AppBadgeTone success = AppBadgeTone.paid;
  static const AppBadgeTone error = AppBadgeTone.unpaid;
  static const AppBadgeTone danger = AppBadgeTone.unpaid;
}

typedef AppStatusTone = AppBadgeTone;

/// Pasangan warna semantik yang selalu memiliki kontras tinggi baik di Light,
/// Dark, maupun AMOLED mode.
class AppTonePalette {
  final Color foreground;
  final Color background;
  final Color border;
  final IconData defaultIcon;

  const AppTonePalette({
    required this.foreground,
    required this.background,
    required this.border,
    required this.defaultIcon,
  });
}

/// Penyedia warna semantik adaptif terhadap tema aktif.
class AppSemanticColors {
  AppSemanticColors._();

  static AppTonePalette of(BuildContext context, AppBadgeTone tone) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    return switch (tone) {
      AppBadgeTone.paid => AppTonePalette(
        foreground: isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20),
        background: isDark
            ? const Color(0xFF1B5E20).withValues(alpha: 0.28)
            : const Color(0xFFE8F5E9),
        border: isDark
            ? const Color(0xFF4CAF50).withValues(alpha: 0.45)
            : const Color(0xFFA5D6A7),
        defaultIcon: Icons.check_circle_outline_rounded,
      ),
      AppBadgeTone.unpaid => AppTonePalette(
        foreground: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C),
        background: isDark
            ? const Color(0xFFB71C1C).withValues(alpha: 0.26)
            : const Color(0xFFFFEBEE),
        border: isDark
            ? const Color(0xFFEF5350).withValues(alpha: 0.45)
            : const Color(0xFFEF9A9A),
        defaultIcon: Icons.error_outline_rounded,
      ),
      AppBadgeTone.warning => AppTonePalette(
        foreground: isDark ? const Color(0xFFFFCC80) : const Color(0xFFE65100),
        background: isDark
            ? const Color(0xFFE65100).withValues(alpha: 0.24)
            : const Color(0xFFFFF3E0),
        border: isDark
            ? const Color(0xFFFFA726).withValues(alpha: 0.45)
            : const Color(0xFFFFCC80),
        defaultIcon: Icons.warning_amber_rounded,
      ),
      AppBadgeTone.info => AppTonePalette(
        foreground: isDark ? const Color(0xFF80CBC4) : const Color(0xFF00695C),
        background: isDark
            ? const Color(0xFF00695C).withValues(alpha: 0.26)
            : const Color(0xFFE0F2F1),
        border: isDark
            ? const Color(0xFF26A69A).withValues(alpha: 0.45)
            : const Color(0xFF80CBC4),
        defaultIcon: Icons.info_outline_rounded,
      ),
      AppBadgeTone.neutral => AppTonePalette(
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        border: scheme.outlineVariant,
        defaultIcon: Icons.circle_outlined,
      ),
    };
  }

  static Color successContainer(BuildContext context) =>
      of(context, AppBadgeTone.paid).background;
  static Color onSuccessContainer(BuildContext context) =>
      of(context, AppBadgeTone.paid).foreground;
  static Color successBorder(BuildContext context) =>
      of(context, AppBadgeTone.paid).border;

  static Color warningContainer(BuildContext context) =>
      of(context, AppBadgeTone.warning).background;
  static Color onWarningContainer(BuildContext context) =>
      of(context, AppBadgeTone.warning).foreground;
  static Color warningBorder(BuildContext context) =>
      of(context, AppBadgeTone.warning).border;

  static Color errorContainer(BuildContext context) =>
      of(context, AppBadgeTone.unpaid).background;
  static Color onErrorContainer(BuildContext context) =>
      of(context, AppBadgeTone.unpaid).foreground;
  static Color errorBorder(BuildContext context) =>
      of(context, AppBadgeTone.unpaid).border;

  /// Menentukan tone semantik otomatis dari teks status PBB/Kolektif.
  static AppBadgeTone toneFromStatusText(String status) {
    final s = status.trim().toLowerCase();
    if (s.contains('sudah') || s.contains('lunas') || s.contains('aktif')) {
      return AppBadgeTone.paid;
    }
    if (s.contains('belum') ||
        s.contains('tunggak') ||
        s.contains('kedaluwarsa') ||
        s.contains('batal') ||
        s.contains('gagal')) {
      return AppBadgeTone.unpaid;
    }
    if (s.contains('draft') || s.contains('denda') || s.contains('proses')) {
      return AppBadgeTone.warning;
    }
    if (s.contains('siap')) {
      return AppBadgeTone.info;
    }
    return AppBadgeTone.neutral;
  }
}

/// Lencana status (Status Badge) yang selalu menyertakan ikon + teks + kontras tinggi
/// sehingga informasi tidak pernah hanya bergantung pada warna.
class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppBadgeTone? tone;
  final IconData? icon;
  final bool dense;
  final bool? compact;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone,
    this.icon,
    this.dense = false,
    this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final isDense = compact ?? dense;
    final resolvedTone = tone ?? AppSemanticColors.toneFromStatusText(label);
    final palette = AppSemanticColors.of(context, resolvedTone);
    final effectiveIcon = icon ?? palette.defaultIcon;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDense ? 8 : 10,
        vertical: isDense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            effectiveIcon,
            size: isDense ? 13 : 15,
            color: palette.foreground,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isDense ? 11.5 : 12.5,
                fontWeight: FontWeight.w700,
                color: palette.foreground,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pembungkus konten halaman responsif dengan lebar maksimum terukur dan padding adaptif.
class ResponsivePageContainer extends StatelessWidget {
  final Widget child;
  final bool isDataHeavy;
  final bool isCompactForm;
  final double bottomPadding;
  final EdgeInsetsGeometry? paddingOverride;
  final EdgeInsetsGeometry? padding;

  const ResponsivePageContainer({
    super.key,
    required this.child,
    this.isDataHeavy = false,
    this.isCompactForm = false,
    this.bottomPadding = 28.0,
    this.paddingOverride,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = AppBreakpoints.maxContentWidth(
      width,
      isDataHeavy: isDataHeavy,
      isCompactForm: isCompactForm,
    );
    final effectivePadding =
        padding ??
        paddingOverride ??
        AppBreakpoints.pagePadding(width, bottom: bottomPadding);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: effectivePadding, child: child),
      ),
    );
  }
}

/// Kartu Empty State informatif yang menjelaskan kondisi data kosong dan tindakan selanjutnya.
class AppEmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const AppEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveMessage = message ?? subtitle ?? '';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 28, color: scheme.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (effectiveMessage.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    effectiveMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon ?? Icons.add_rounded, size: 18),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner peringatan/error kontekstual dengan animasi masuk/keluar yang halus
/// serta dukungan tombol coba lagi (retry).
class AppAlertBanner extends StatelessWidget {
  final String message;
  final String? title;
  final AppBadgeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry margin;

  const AppAlertBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = AppBadgeTone.unpaid,
    this.actionLabel,
    this.onAction,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppSemanticColors.of(context, tone);
    final duration = AppMotion.resolve(context, AppMotion.component);

    return AnimatedSize(
      duration: duration,
      curve: AppMotion.standardCurve,
      child: Padding(
        padding: margin,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  palette.defaultIcon,
                  size: 20,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null && title!.isNotEmpty) ...[
                      Text(
                        title!,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: palette.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: palette.foreground,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.foreground,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel filter sekunder yang dapat dilipat/dibuka (Progressive Disclosure)
/// untuk menjaga layar ponsel tetap ringkas dan tidak membingungkan.
class AppCollapsibleFilterSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int activeFilterCount;
  final bool initiallyExpanded;
  final List<Widget> children;

  const AppCollapsibleFilterSection({
    super.key,
    this.title = 'Filter Lanjutan (Opsional)',
    this.subtitle,
    this.activeFilterCount = 0,
    this.initiallyExpanded = false,
    required this.children,
  });

  @override
  State<AppCollapsibleFilterSection> createState() =>
      _AppCollapsibleFilterSectionState();
}

class _AppCollapsibleFilterSectionState
    extends State<AppCollapsibleFilterSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.component);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: widget.activeFilterCount > 0
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: widget.activeFilterCount > 0
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: widget.activeFilterCount > 0
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                            if (widget.activeFilterCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  '${widget.activeFilterCount} aktif',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.subtitle != null && !_expanded)
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: duration,
                    curve: AppMotion.standardCurve,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: AppMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [const Divider(height: 12), ...widget.children],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pembungkus transisi masuk (Fade + Slide halus `200ms`) untuk kartu hasil pencarian
/// atau elemen dinamis. Otomatis instan apabila Reduced Motion aktif.
class AppAnimatedReveal extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final double slideOffsetY;

  const AppAnimatedReveal({
    super.key,
    required this.child,
    this.duration = AppMotion.component,
    this.slideOffsetY = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: AppMotion.enterCurve,
      builder: (context, t, builtChild) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - t) * slideOffsetY),
            child: builtChild,
          ),
        );
      },
      child: child,
    );
  }
}
