import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'batch_check_manager.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart';
import 'pbb_client.dart';
import 'result_screen.dart';
import 'tax_record.dart';
import 'ui/app_design_system.dart';
import 'unity_lerp_widgets.dart';

class BatchCheckScreen extends StatefulWidget {
  static const String routeName = 'BatchCheckScreen';

  final List<TaxRecord> records;
  final String tahun;
  final PbbClient? client;
  final Duration pacingDelay;
  final int cooldownBatchSize;
  final Duration cooldownDuration;
  final bool autoStart;

  /// Jika true, NOP yang terdeteksi sudah bayar juga diunduh berkas STTS-nya.
  final bool downloadStts;

  /// Folder khusus untuk menampung seluruh berkas STTS dan berkas informasi blok (.txt).
  final Directory? sttsTargetDirectory;

  /// Nomor blok yang sedang diperiksa (misalnya "001" atau "1").
  final String? sttsBlokNumber;

  /// Label cakupan pengecekan (mis. "Blok 001" atau "Seluruh Blok • Dusun 1").
  final String? scopeTitle;

  /// Jika true, layar menempel ke sesi [BatchCheckManager.instance] yang
  /// sedang berjalan di latar belakang tanpa memulai ulang proses.
  final bool attachActive;

  const BatchCheckScreen({
    super.key,
    required this.records,
    required this.tahun,
    this.client,
    this.pacingDelay = const Duration(milliseconds: 750),
    this.cooldownBatchSize = 50,
    this.cooldownDuration = const Duration(seconds: 3),
    this.autoStart = true,
    this.downloadStts = false,
    this.sttsTargetDirectory,
    this.sttsBlokNumber,
    this.scopeTitle,
    this.attachActive = false,
  });

  /// Membuka kembali layar progres pengecekan massal yang sedang disembunyikan.
  factory BatchCheckScreen.attachActive({Key? key}) {
    final mgr = BatchCheckManager.instance;
    return BatchCheckScreen(
      key: key,
      records: mgr.records,
      tahun: mgr.tahun,
      autoStart: false,
      downloadStts: mgr.downloadStts,
      sttsTargetDirectory: mgr.sttsDirectory,
      sttsBlokNumber: mgr.sttsBlokNumber,
      scopeTitle: mgr.scopeTitle,
      attachActive: true,
    );
  }

  @override
  State<BatchCheckScreen> createState() => _BatchCheckScreenState();
}

class _BatchCheckScreenState extends State<BatchCheckScreen>
    with SingleTickerProviderStateMixin {
  static const double _rowExtent = 80.0;
  static const double _listVerticalPadding = 8.0;

  final ScrollController _scrollController = ScrollController();
  late final AnimationController _spinController;
  Timer? _completionNavTimer;
  int _lastScrolledIndex = -1;
  bool _navigatedToResult = false;
  int _trackedSessionId = -1;

  BatchCheckManager get _mgr => BatchCheckManager.instance;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _mgr.setScreenOpen(true);
    _mgr.onHideScreenRequested = _hideToBackground;
    _mgr.addListener(_onManagerChanged);

    if (widget.attachActive) {
      _trackedSessionId = _mgr.sessionId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrent(jump: true);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _mgr.startBatch(
            records: widget.records,
            tahun: widget.tahun,
            client: widget.client,
            pacingDelay: widget.pacingDelay,
            cooldownBatchSize: widget.cooldownBatchSize,
            cooldownDuration: widget.cooldownDuration,
            downloadStts: widget.downloadStts,
            sttsTargetDirectory: widget.sttsTargetDirectory,
            sttsBlokNumber: widget.sttsBlokNumber,
            scopeTitle: widget.scopeTitle,
            autoStart: widget.autoStart,
          ),
        );
        _trackedSessionId = _mgr.sessionId;
      });
    }
  }

  @override
  void dispose() {
    _completionNavTimer?.cancel();
    _mgr.removeListener(_onManagerChanged);
    if (_mgr.onHideScreenRequested == _hideToBackground) {
      _mgr.onHideScreenRequested = null;
    }
    _mgr.setScreenOpen(false);
    _spinController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onManagerChanged() {
    if (!mounted) return;

    if (_mgr.isRunning && !_mgr.isPaused) {
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else if (_spinController.isAnimating) {
      _spinController.stop();
    }

    if (_mgr.currentIndex != _lastScrolledIndex &&
        _mgr.currentIndex < _mgr.totalCount) {
      _lastScrolledIndex = _mgr.currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrent();
      });
    }

    if (_mgr.isCompleted &&
        _mgr.isScreenOpen &&
        !_navigatedToResult &&
        _mgr.sessionId == _trackedSessionId) {
      _navigatedToResult = true;
      _completionNavTimer?.cancel();
      _completionNavTimer = Timer(const Duration(milliseconds: 550), () {
        if (mounted && _mgr.isCompleted && _mgr.isScreenOpen) {
          _openResultScreen(replace: true);
        }
      });
    }
  }

  /// Menggulir otomatis daftar NOP agar item yang sedang diperiksa selalu
  /// berada tepat di tengah layar (bukan tertinggal di atas/bawah).
  void _scrollToCurrent({bool jump = false}) {
    if (!_scrollController.hasClients || _mgr.totalCount == 0) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final activeIndex = _mgr.currentIndex.clamp(0, _mgr.totalCount - 1);
    final itemCenter = _listVerticalPadding + (activeIndex + 0.5) * _rowExtent;
    final targetOffset = (itemCenter - (viewport / 2)).clamp(
      0.0,
      position.maxScrollExtent,
    );

    final reducedMotion = AppMotion.isReducedMotion(context);
    if (jump || reducedMotion) {
      _scrollController.jumpTo(targetOffset);
    } else {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _hideToBackground() {
    if (!mounted) return;
    _mgr.setScreenOpen(false);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _openResultScreen({bool replace = false}) {
    if (!mounted) return;
    _mgr.dismiss();
    if (ResultScreen.isCurrentlyOpen) {
      if (replace && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    final route = MaterialPageRoute(
      settings: const RouteSettings(name: ResultScreen.routeName),
      builder: (_) => ResultScreen(records: _mgr.records),
    );
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  void _stopAndViewResult() {
    _mgr.stopAndFinalize(notifyCancelled: false);
    _openResultScreen(replace: true);
  }

  Future<bool> _onWillPop() async {
    if (!_mgr.isActiveSession) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Layar Cek Massal?'),
        content: const Text(
          'Anda dapat menyembunyikan layar ini agar pengecekan tetap berjalan di latar belakang sambil menggunakan fitur aplikasi lainnya, atau menghentikan proses sekarang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Tetap di Sini'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, 'stop'),
            child: const Text('Hentikan Proses'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'hide'),
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Sembunyikan'),
          ),
        ],
      ),
    );
    if (choice == 'hide') {
      _mgr.setScreenOpen(false);
      return true;
    }
    if (choice == 'stop') {
      _mgr.cancel();
      return true;
    }
    return false;
  }

  Widget _buildCounterBadge({
    required String label,
    required int count,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          LerpAnimatedCounter(
            value: count,
            formatter: (v) => '$label: ${v.round()}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  ({
    Color color,
    IconData icon,
    String label,
    String stateKey,
  })
  _resolveItemVisual(TaxRecord item, bool isCurrent, ColorScheme scheme) {
    if (isCurrent) {
      return (
        color: scheme.primary,
        icon: Icons.autorenew_rounded,
        label: 'Memeriksa...',
        stateKey: 'checking',
      );
    }
    if (!item.isChecked) {
      return (
        color: Colors.blueGrey.shade500,
        icon: Icons.hourglass_empty_rounded,
        label: 'Belum Dicek',
        stateKey: 'pending',
      );
    }
    final s = item.status.toLowerCase();
    if (item.isPaid || s.contains('sudah') || s.contains('lunas')) {
      return (
        color: Colors.green.shade700,
        icon: Icons.check_circle_rounded,
        label: 'Sudah Bayar',
        stateKey: 'paid',
      );
    }
    if (s.contains('belum')) {
      return (
        color: Colors.deepOrange.shade600,
        icon: Icons.cancel_rounded,
        label: 'Belum Bayar',
        stateKey: 'unpaid',
      );
    }
    if (s.contains('blacklist')) {
      return (
        color: Colors.deepPurple.shade600,
        icon: Icons.block_rounded,
        label: item.status,
        stateKey: 'blacklist',
      );
    }
    if (s.contains('lewat')) {
      return (
        color: Colors.grey.shade600,
        icon: Icons.skip_next_rounded,
        label: 'Dilewati',
        stateKey: 'skipped',
      );
    }
    if (s.contains('gagal') || s.contains('error')) {
      return (
        color: Colors.red.shade700,
        icon: Icons.error_rounded,
        label: 'Gagal Cek',
        stateKey: 'error',
      );
    }
    return (
      color: scheme.outline,
      icon: Icons.help_outline_rounded,
      label: item.status,
      stateKey: 'other',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _mgr,
      builder: (context, _) {
        final records = _mgr.records;
        final total = _mgr.totalCount;
        final currentIdx = _mgr.currentIndex;
        final current = _mgr.currentRecord;
        final sudahBayarCount = _mgr.sudahBayarCount;
        final belumBayarCount = _mgr.belumBayarCount;
        final blacklistCount = _mgr.blacklistCount;
        final gagalCount = _mgr.gagalCount;
        final dilewatiCount = _mgr.dilewatiCount;
        final sisaCount = _mgr.sisaCount;
        final sttsDownloadedCount = _mgr.sttsDownloadedCount;
        final progressVal = _mgr.progressRatio;
        final percentText = '${(progressVal * 100).toStringAsFixed(0)}%';
        final scheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return PopScope(
          canPop: !_mgr.isActiveSession,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final shouldPop = await _onWillPop();
            if (shouldPop && context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                'Cek Massal (${currentIdx.clamp(0, total)}/$total)',
              ),
              actions: [
                if (_mgr.isActiveSession)
                  TextButton.icon(
                    key: const ValueKey('batch_hide_appbar_btn'),
                    onPressed: _hideToBackground,
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('Sembunyikan'),
                  ),
                if (currentIdx > 0 && !_mgr.isActiveSession)
                  TextButton.icon(
                    onPressed: () => _openResultScreen(replace: true),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Hasil'),
                  ),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    children: [
                      // Progress & Counters Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: LerpAnimatedProgress(
                                    value: progressVal,
                                    minHeight: 10,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    percentText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _buildCounterBadge(
                                  label: 'Sudah',
                                  count: sudahBayarCount,
                                  color: Colors.green.shade700,
                                  icon: Icons.check_circle_rounded,
                                ),
                                _buildCounterBadge(
                                  label: 'Belum',
                                  count: belumBayarCount,
                                  color: Colors.deepOrange.shade600,
                                  icon: Icons.cancel_rounded,
                                ),
                                if (_mgr.downloadStts)
                                  _buildCounterBadge(
                                    label: 'STTS',
                                    count: sttsDownloadedCount,
                                    color: Colors.teal.shade700,
                                    icon: Icons.receipt_long_rounded,
                                  ),
                                if (blacklistCount > 0)
                                  _buildCounterBadge(
                                    label: 'Blacklist',
                                    count: blacklistCount,
                                    color: Colors.deepPurple,
                                    icon: Icons.block_rounded,
                                  ),
                                if (gagalCount > 0)
                                  _buildCounterBadge(
                                    label: 'Gagal',
                                    count: gagalCount,
                                    color: Colors.red.shade700,
                                    icon: Icons.error_rounded,
                                  ),
                                if (dilewatiCount > 0)
                                  _buildCounterBadge(
                                    label: 'Lewat',
                                    count: dilewatiCount,
                                    color: Colors.grey.shade600,
                                    icon: Icons.skip_next_rounded,
                                  ),
                                _buildCounterBadge(
                                  label: 'Antrean',
                                  count: sisaCount,
                                  color: Colors.blueGrey.shade600,
                                  icon: Icons.hourglass_empty_rounded,
                                ),
                              ],
                            ),
                            if (_mgr.downloadStts &&
                                _mgr.sttsDirectory != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.teal.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.folder_outlined,
                                      size: 16,
                                      color: Colors.teal,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'STTS: ${_mgr.sttsDirectory!.path.split(Platform.pathSeparator).last}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.teal,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () =>
                                          NativeFileHelper.showInFileManager(
                                            _mgr.sttsDirectory!.path,
                                          ),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: Text(
                                          'Buka Folder',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Active Item & Controls Card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AnimatedContainer(
                          duration: AppMotion.resolve(
                            context,
                            const Duration(milliseconds: 240),
                          ),
                          decoration: BoxDecoration(
                            color: _mgr.isCompleted
                                ? Colors.green.withValues(
                                    alpha: isDark ? 0.14 : 0.08,
                                  )
                                : scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _mgr.isRunning
                                  ? scheme.primary.withValues(alpha: 0.45)
                                  : (_mgr.isCompleted
                                        ? Colors.green.withValues(alpha: 0.45)
                                        : scheme.outlineVariant.withValues(
                                            alpha: 0.5,
                                          )),
                              width: _mgr.isRunning ? 1.3 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    if (_mgr.isCooldown)
                                      const Icon(
                                        Icons.hourglass_top_rounded,
                                        size: 18,
                                        color: Colors.cyan,
                                      )
                                    else if (_mgr.isRunning)
                                      RotationTransition(
                                        turns: _spinController,
                                        child: Icon(
                                          Icons.autorenew_rounded,
                                          size: 20,
                                          color: scheme.primary,
                                        ),
                                      )
                                    else if (_mgr.isPaused)
                                      const Icon(
                                        Icons.pause_circle_filled_rounded,
                                        size: 20,
                                        color: Colors.orange,
                                      )
                                    else if (_mgr.isCompleted)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
                                        color: Colors.green,
                                      )
                                    else
                                      const Icon(
                                        Icons.hourglass_empty_rounded,
                                        size: 18,
                                        color: Colors.blueGrey,
                                      ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _mgr.statusMessage,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: _mgr.isCooldown
                                                  ? Colors.cyan.shade700
                                                  : scheme.onSurfaceVariant,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (current != null) ...[
                                  const Divider(height: 16),
                                  AnimatedSwitcher(
                                    duration: AppMotion.resolve(
                                      context,
                                      const Duration(milliseconds: 200),
                                    ),
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0, 0.12),
                                              end: Offset.zero,
                                            ).animate(anim),
                                            child: child,
                                          ),
                                        ),
                                    child: Row(
                                      key: ValueKey(current.nop),
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                current.nop,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      letterSpacing: 1.0,
                                                    ),
                                              ),
                                              if (current.namaWajibPajak !=
                                                      null &&
                                                  current
                                                      .namaWajibPajak!
                                                      .isNotEmpty)
                                                Text(
                                                  current.namaWajibPajak!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (nopBlok(current.nop).isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: scheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Blok ${nopBlok(current.nop)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    scheme.onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                // Action controls
                                Row(
                                  children: [
                                    if (_mgr.isRunning) ...[
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: _mgr.pause,
                                          icon: const Icon(
                                            Icons.pause_rounded,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Jeda',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          key: const ValueKey(
                                            'batch_hide_action_btn',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: _hideToBackground,
                                          icon: const Icon(
                                            Icons.visibility_off_outlined,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Sembunyikan',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton.outlined(
                                        tooltip: 'Hentikan & Lihat Hasil',
                                        color: scheme.error,
                                        onPressed: _stopAndViewResult,
                                        icon: const Icon(
                                          Icons.stop_circle_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    ] else if (!_mgr.isCompleted) ...[
                                      Expanded(
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          onPressed: _mgr.resume,
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Lanjutkan',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                        ),
                                        onPressed: _mgr.skipCurrent,
                                        child: const Text('Lewati'),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton.outlined(
                                        tooltip: 'Sembunyikan ke Latar Belakang',
                                        onPressed: _hideToBackground,
                                        icon: const Icon(
                                          Icons.visibility_off_outlined,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton.outlined(
                                        tooltip: 'Hentikan & Lihat Hasil',
                                        onPressed: _stopAndViewResult,
                                        icon: const Icon(
                                          Icons.fact_check_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ] else ...[
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () =>
                                              _openResultScreen(replace: true),
                                          icon: const Icon(
                                            Icons.check_circle_rounded,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Buka Hasil Pengecekan',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Live Records Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _mgr.scopeTitle != null &&
                                        _mgr.scopeTitle!.isNotEmpty
                                    ? '${_mgr.scopeTitle} ($total NOP)'
                                    : 'Daftar NOP ($total)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tahun Pajak: ${_mgr.tahun}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Live Records List with exact itemExtent for dead-center auto-scroll
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemExtent: _rowExtent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: _listVerticalPadding,
                          ),
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final item = records[index];
                            final isCurrent =
                                index == currentIdx && _mgr.isRunning;
                            final visual = _resolveItemVisual(
                              item,
                              isCurrent,
                              scheme,
                            );

                            final subtitleParts = <String>[];
                            if (item.namaWajibPajak != null &&
                                item.namaWajibPajak!.trim().isNotEmpty) {
                              subtitleParts.add(item.namaWajibPajak!.trim());
                            }
                            if (item.tanggalBayar != null &&
                                item.tanggalBayar!.trim().isNotEmpty) {
                              subtitleParts.add('Bayar: ${item.tanggalBayar}');
                            }
                            if (item.buktiBayarDownloaded != null) {
                              subtitleParts.add(
                                item.buktiBayarDownloaded!
                                    ? 'STTS tersimpan'
                                    : 'STTS belum terbit',
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: AnimatedContainer(
                                duration: AppMotion.resolve(
                                  context,
                                  const Duration(milliseconds: 220),
                                ),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? scheme.primaryContainer.withValues(
                                          alpha: isDark ? 0.42 : 0.36,
                                        )
                                      : (item.isChecked && item.isPaid
                                            ? Colors.green.withValues(
                                                alpha: isDark ? 0.08 : 0.04,
                                              )
                                            : scheme.surfaceContainerLowest),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCurrent
                                        ? scheme.primary
                                        : scheme.outlineVariant.withValues(
                                            alpha: 0.35,
                                          ),
                                    width: isCurrent ? 1.8 : 1,
                                  ),
                                  boxShadow: isCurrent
                                      ? [
                                          BoxShadow(
                                            color: scheme.primary.withValues(
                                              alpha: 0.16,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    // Status icon badge with smooth switch animation
                                    AnimatedSwitcher(
                                      duration: AppMotion.resolve(
                                        context,
                                        const Duration(milliseconds: 240),
                                      ),
                                      transitionBuilder: (child, anim) =>
                                          ScaleTransition(
                                            scale: anim,
                                            child: FadeTransition(
                                              opacity: anim,
                                              child: child,
                                            ),
                                          ),
                                      child: Container(
                                        key: ValueKey(visual.stateKey),
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: visual.color.withValues(
                                            alpha: isCurrent ? 0.2 : 0.14,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: isCurrent
                                              ? RotationTransition(
                                                  turns: _spinController,
                                                  child: Icon(
                                                    visual.icon,
                                                    color: visual.color,
                                                    size: 20,
                                                  ),
                                                )
                                              : Icon(
                                                  visual.icon,
                                                  color: visual.color,
                                                  size: 20,
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.nop,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: isCurrent
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              fontSize: 13,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          if (subtitleParts.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              subtitleParts.join(' • '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: item.isPaid
                                                    ? (isDark
                                                          ? Colors.green.shade300
                                                          : Colors
                                                                .green
                                                                .shade800)
                                                    : scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AnimatedContainer(
                                      duration: AppMotion.resolve(
                                        context,
                                        const Duration(milliseconds: 220),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: visual.color.withValues(
                                          alpha: 0.13,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: visual.color.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        visual.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: visual.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
