import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'blok_record.dart';
import 'dhkp/blok_catatan_models.dart' show semuaBlokValue;
import 'dhkp/blok_catatan_widgets.dart'
    show
        BlokPrintCancelToken,
        BlokPrintCancelledException,
        runCancellableDhkpPrint;
import 'dhkp/dhkp_chart_widgets.dart';
import 'dhkp/dhkp_grafik_analytics.dart';
import 'dhkp/dhkp_grafik_exporter.dart';
import 'dhkp/dhkp_rincian_bulanan_dialog.dart';
import 'dhkp_widget_sync_service.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'dusun_data.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart'
    show
        lookupKecamatanName,
        lookupKelurahanName,
        nopKecamatan,
        nopKelurahan;
import 'feature_tour/feature_tour.dart';
import 'tagihan_result.dart' show formatRupiah;
import 'ui/app_design_system.dart';
import 'unity_lerp_widgets.dart' show UnityAnimationCurve, unityLerp;
import 'user_friendly_error.dart';

export 'dhkp/dhkp_grafik_analytics.dart';

class DhkpGrafikView extends StatefulWidget {
  final List<BlokRecord> records;
  final String? selectedBlok;
  final int? selectedWilayah;
  final String? selectedTahun;
  final ValueChanged<String>? onTahunChanged;
  final ValueChanged<VoidCallback>? onRegisterShowTour;
  final ValueChanged<Future<void> Function()>? onRegisterPrintShortcut;

  const DhkpGrafikView({
    super.key,
    required this.records,
    this.selectedBlok,
    this.selectedWilayah,
    this.selectedTahun,
    this.onTahunChanged,
    this.onRegisterShowTour,
    this.onRegisterPrintShortcut,
  });

  @override
  State<DhkpGrafikView> createState() => _DhkpGrafikViewState();
}

class _DhkpGrafikViewState extends State<DhkpGrafikView>
    with SingleTickerProviderStateMixin {
  static const _prefKeyTab = 'dhkp_grafik_active_tab';
  static const _prefKeyStyle = 'dhkp_grafik_chart_style';
  static const _prefKeySort = 'dhkp_grafik_sort_mode';
  static const _prefKeySeDesa = 'dhkp_grafik_se_desa_mode';
  static const _prefKeyCollapsed = 'dhkp_grafik_collapsed_sections';
  static const _prefKeyFitColumnBars = 'dhkp_grafik_fit_column_bars';

  static const _maxCustomDesas = 5;

  // Default: Data = Jumlah Persentase, Diagram = Batang, Desa = Semua Dusun
  DhkpGrafikTab _activeTab = DhkpGrafikTab.persentase;

  /// Warna aksen monokromatik utama yang mengikuti warna tema pilihan pengguna.
  MaterialColor get _themeAccent =>
      buildThemeMaterialColor(Theme.of(context).colorScheme.primary);

  MaterialColor get _themeSecondaryAccent =>
      buildThemeMaterialColor(Theme.of(context).colorScheme.secondary);

  MaterialColor get _themeTertiaryAccent =>
      buildThemeMaterialColor(Theme.of(context).colorScheme.tertiary);

  List<Color> get _themeSlicePalette =>
      buildThemeSlicePalette(Theme.of(context).colorScheme);
  ChartStyle _selectedStyle = ChartStyle.batang;
  GrafikSortMode _sortMode = GrafikSortMode.wilayah;
  bool _seDesaMode = false;

  /// Mode diagram batang: true = Pas Layar (dirapatkan muat semua blok), false = Bisa Digeser
  bool _fitColumnBars = true;

  /// Drill-down khusus ketika pengguna mengeklik salah satu Dusun dari grafik
  int? _drillDownDusun;

  /// Drill-down khusus ketika data mencakup multi-desa dalam 1 kecamatan
  String? _selectedDesaCode;

  /// Satu tahun pembanding aktif pada tab Tren (khusus 1 entitas tunggal vs 1 tahun lain)
  String? _compareYear;

  /// Pilihan manual desa pembanding dalam 1 kecamatan (maks 5 desa)
  final Set<String> _customCompareDesas = {};

  /// Filter tahun aktif khusus di dalam tampilan grafik (default ke data terbaru)
  late String _selectedTahun;

  /// Item wilayah/bulan yang sedang diklik/disorot untuk melihat detail lengkap
  String? _selectedItemLabel;

  /// Menyimpan daftar ID kartu yang sedang dilipat.
  final Set<String> _collapsedSections = {};

  /// GlobalKey per bagian grafik untuk tangkapan gambar (PNG) & dokumen (PDF)
  final Map<String, GlobalKey> _boundaryKeys = {};

  final _topTabsKey = GlobalKey(debugLabel: 'tour_grafik_top_tabs');
  final _scopeBarKey = GlobalKey(debugLabel: 'tour_grafik_scope_bar');
  final _statCardsKey = GlobalKey(debugLabel: 'tour_grafik_stat_cards');
  final _controlToolbarKey = GlobalKey(debugLabel: 'tour_grafik_toolbar');
  final _chartContentKey = GlobalKey(debugLabel: 'tour_grafik_content');

  late AnimationController _animController;
  late Animation<double> _animation;
  bool _didInitialAnimate = false;
  bool _isCapturingExport = false;

  bool get _isSpecificBlokFiltered {
    final sb = widget.selectedBlok?.trim();
    if (sb == null || sb.isEmpty) return false;
    return sb != semuaBlokValue && sb != 'Semua' && sb != 'Semua Blok';
  }

  @override
  void initState() {
    super.initState();
    final availableYears =
        widget.records
            .map((r) => r.tahunBayar)
            .where((y) => y.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    _selectedTahun =
        widget.selectedTahun ??
        (availableYears.isNotEmpty
            ? availableYears.first
            : '${DateTime.now().year}');
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: const UnityAnimationCurve(),
    );
    if (widget.selectedWilayah != null || DusunData.instance.isDusunLocked) {
      _drillDownDusun = null;
      _seDesaMode = false;
    }
    if (_isSpecificBlokFiltered) {
      _selectedItemLabel =
          'Blok ${int.tryParse(widget.selectedBlok!) ?? widget.selectedBlok}';
    }
    widget.onRegisterShowTour?.call(showTour);
    widget.onRegisterPrintShortcut?.call(printCurrentSelection);
    _loadSavedPreferences();
    DhkpWidgetSyncService.syncFromRecords(widget.records);
    FeatureTourController.startTourIfNeeded(
      context: context,
      tourId: 'dhkp_grafik_view',
      steps: _buildTourSteps(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = AppMotion.isReducedMotion(context);
    _animController.duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 1500);
    if (!_didInitialAnimate) {
      _didInitialAnimate = true;
      _replayAnimation();
    } else if (reducedMotion && _animController.value < 1.0) {
      _animController.value = 1.0;
    }
  }

  void _replayAnimation() {
    if (!mounted) return;
    if (AppMotion.isReducedMotion(context)) {
      _animController.duration = Duration.zero;
      _animController.value = 1.0;
    } else {
      _animController.duration = const Duration(milliseconds: 1500);
      _animController.forward(from: 0.0);
    }
  }

  void showTour() {
    if (!mounted) return;
    FeatureTourController.showTour(
      context: context,
      tourId: 'dhkp_grafik_view',
      steps: _buildTourSteps(),
    );
  }

  List<FeatureTourStep> _buildTourSteps() {
    final exportButtons = Platform.isAndroid
        ? 'Unduh PNG atau PDF, Bagikan, dan Cetak'
        : 'Unduh PNG atau PDF dan Cetak';
    return [
      FeatureTourStep(
        targetKey: _topTabsKey,
        title: '5 Kategori Laporan Grafik',
        description:
            'Pilih sudut pandang grafik: Persentase lunas, Pendapatan, Sudah/Belum Bayar, atau Tren Pembayaran bulanan.',
        actionHint: 'Ketuk salah satu kategori di atas untuk mengganti grafik.',
        icon: Icons.analytics_outlined,
      ),
      FeatureTourStep(
        targetKey: _scopeBarKey,
        title: 'Cakupan Wilayah Cepat',
        description:
            'Ganti cakupan sesuai wilayah aktif (Se-Desa, Dusun, atau Semua Blok). Bilah otomatis disembunyikan saat memilih 1 Blok.',
        actionHint: 'Ketuk batang dusun/blok pada grafik untuk melihat detail.',
        icon: Icons.place_outlined,
      ),
      FeatureTourStep(
        targetKey: _statCardsKey,
        title: 'Indikator Capaian & 3 Kartu Tren',
        description:
            'Menampilkan Indikator Capaian pelunasan beserta 3 kartu ringkasan berisi grafik tren, perbandingan tahun lalu, jumlah SPPT, dan nilai rupiah.',
        icon: Icons.assessment_outlined,
      ),
      FeatureTourStep(
        targetKey: _controlToolbarKey,
        title: 'Bentuk Diagram, Urutan & Lipat Kartu',
        description:
            'Atur bentuk diagram (Batang Tegak, Mendatar, Lingkaran), mode Pas Layar/Geser, urutan wilayah, serta lipat/buka kartu.',
        actionHint: 'Pilihan tampilan tersimpan otomatis.',
        icon: Icons.tune_rounded,
      ),
      FeatureTourStep(
        targetKey: _chartContentKey,
        title: 'Grafik Interaktif & Ekspor PNG/PDF',
        description:
            '• Ketuk batang atau titik bulan untuk melihat rincian wajib pajak.\n'
            '• Pada tab Tren Pembayaran, tekan "Bandingkan" untuk membandingkan 2 tahun sekaligus.\n'
            '• Di pojok kanan atas kartu tersedia tombol $exportButtons.',
        actionHint: 'Geser ke bawah untuk melihat tabel perbandingan lengkap.',
        icon: Icons.bar_chart_rounded,
      ),
    ];
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTabName = prefs.getString(_prefKeyTab);
      final savedStyleName = prefs.getString(_prefKeyStyle);
      final savedSortName = prefs.getString(_prefKeySort);
      final savedSeDesa = prefs.getBool(_prefKeySeDesa);
      final savedCollapsed = prefs.getStringList(_prefKeyCollapsed);
      final savedFitColumnBars = prefs.getBool(_prefKeyFitColumnBars);

      if (!mounted) return;
      setState(() {
        if (savedTabName != null) {
          for (final t in DhkpGrafikTab.values) {
            if (t.name == savedTabName) {
              _activeTab = t;
              break;
            }
          }
        }
        if (savedStyleName != null) {
          for (final s in ChartStyle.values) {
            if (s.name == savedStyleName) {
              _selectedStyle = s;
              break;
            }
          }
        }
        if (savedSortName != null) {
          for (final m in GrafikSortMode.values) {
            if (m.name == savedSortName) {
              _sortMode = m;
              break;
            }
          }
        }
        if (widget.selectedWilayah == null &&
            !DusunData.instance.isDusunLocked &&
            savedSeDesa != null) {
          _seDesaMode = savedSeDesa;
        }
        if (savedCollapsed != null) {
          _collapsedSections
            ..clear()
            ..addAll(savedCollapsed);
        }
        if (savedFitColumnBars != null) {
          _fitColumnBars = savedFitColumnBars;
        }
      });
      _replayAnimation();
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyTab, _activeTab.name);
      await prefs.setString(_prefKeyStyle, _selectedStyle.name);
      await prefs.setString(_prefKeySort, _sortMode.name);
      await prefs.setBool(_prefKeySeDesa, _seDesaMode);
      await prefs.setStringList(_prefKeyCollapsed, _collapsedSections.toList());
      await prefs.setBool(_prefKeyFitColumnBars, _fitColumnBars);
    } catch (_) {}
  }

  GlobalKey _getBoundaryKey(String sectionKey) {
    final fullKey = '${_activeTab.name}_$sectionKey';
    return _boundaryKeys.putIfAbsent(fullKey, () => GlobalKey());
  }

  @override
  void didUpdateWidget(DhkpGrafikView oldWidget) {
    super.didUpdateWidget(oldWidget);
    var shouldAnimate = false;

    if (oldWidget.selectedTahun != widget.selectedTahun &&
        widget.selectedTahun != null) {
      _selectedTahun = widget.selectedTahun!;
      _selectedItemLabel = null;
      shouldAnimate = true;
    } else {
      final availableYears = widget.records
          .map((r) => r.tahunBayar)
          .where((y) => y.isNotEmpty)
          .toSet();
      if (availableYears.isNotEmpty &&
          !availableYears.contains(_selectedTahun)) {
        _selectedTahun =
            (availableYears.toList()..sort((a, b) => b.compareTo(a))).first;
        _selectedItemLabel = null;
        shouldAnimate = true;
      }
    }

    if (oldWidget.records != widget.records ||
        oldWidget.selectedBlok != widget.selectedBlok ||
        oldWidget.selectedWilayah != widget.selectedWilayah) {
      if (oldWidget.selectedWilayah != widget.selectedWilayah) {
        _drillDownDusun = null;
        _seDesaMode = false;
      }
      if (oldWidget.selectedBlok != widget.selectedBlok) {
        _selectedItemLabel = _isSpecificBlokFiltered
            ? 'Blok ${int.tryParse(widget.selectedBlok!) ?? widget.selectedBlok}'
            : null;
      } else if (oldWidget.records != widget.records) {
        _selectedItemLabel = null;
        _customCompareDesas.clear();
      }
      shouldAnimate = true;
      if (oldWidget.records.length != widget.records.length) {
        DhkpWidgetSyncService.syncFromRecords(widget.records);
      }
    }

    if (_compareYear != null) {
      final currentYears =
          widget.records
              .map((r) => r.tahunBayar)
              .where((y) => y.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      if (currentYears.length <= 1 || !currentYears.contains(_compareYear)) {
        _compareYear = null;
      } else if (_compareYear == _selectedTahun) {
        _compareYear = _suggestDefaultCompareYear(currentYears);
      }
    }

    if (shouldAnimate) {
      _replayAnimation();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _switchTab(DhkpGrafikTab tab) {
    if (_activeTab == tab) return;
    setState(() {
      _activeTab = tab;
      _selectedItemLabel = null;
    });
    _savePreferences();
    _replayAnimation();
  }

  void _switchStyle(ChartStyle style) {
    setState(() {
      _selectedStyle = style;
      if (style == ChartStyle.batang) _collapsedSections.remove('batang');
      if (style == ChartStyle.bar) _collapsedSections.remove('bar');
      if (style == ChartStyle.pie) _collapsedSections.remove('pie');
    });
    _savePreferences();
    _replayAnimation();
  }

  void _toggleSection(String sectionKey) {
    setState(() {
      if (_collapsedSections.contains(sectionKey)) {
        _collapsedSections.remove(sectionKey);
      } else {
        _collapsedSections.add(sectionKey);
      }
    });
    _savePreferences();
  }

  bool get _allCollapsed => _collapsedSections.containsAll([
    'kurva',
    'batang',
    'bar',
    'pie',
    'tabel',
  ]);

  void _toggleExpandCollapseAll() {
    setState(() {
      if (_allCollapsed) {
        _collapsedSections.clear();
      } else {
        _collapsedSections.addAll(['kurva', 'batang', 'bar', 'pie', 'tabel']);
      }
    });
    _savePreferences();
  }

  void _onSelectLabel(String? label) {
    setState(() {
      _selectedItemLabel = label;
    });
  }

  String _formatKecamatanLabel(String kecCode) {
    if (kecCode.isEmpty) return 'Se-Kecamatan';
    final raw = lookupKecamatanName(kecCode).trim();
    if (raw.isEmpty) return 'Kec. $kecCode';
    final clean = raw.toLowerCase().startsWith('kec')
        ? raw.replaceFirst(RegExp(r'^kecamatan\s*', caseSensitive: false), '')
        : raw;
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return words.isEmpty ? 'Kec. $kecCode' : 'Kec. $words';
  }

  String _formatGaugeScopeTitle(
    _DhkpResolvedContext scope,
    List<BlokRecord> murniRecords,
    int distinctBlokCount,
  ) {
    if (scope.isKecamatanAggregate) {
      return _formatKecamatanLabel(scope.primaryKecamatanCode);
    }
    final kelCode = scope.effectiveDesaCode ??
        (scope.desaCodes.length == 1 ? scope.desaCodes.first : null);
    String base = 'Realisasi DHKP';
    if (kelCode != null) {
      final raw = lookupKelurahanName(
        kelCode,
        kecamatanCode: scope.primaryKecamatanCode,
      ).trim();
      if (raw.isNotEmpty) {
        final formatted = raw.startsWith('Desa ') || raw.startsWith('Kel')
            ? raw
            : 'Desa ${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}';
        base = formatted;
      }
    }
    if (scope.isKedusunanScope) {
      final dusunNum = scope.activeKedusunanNumber;
      final kedusunanTitle = dusunNum != null
          ? '$base • Dusun $dusunNum'
          : '$base • Kedusunan';
      if (distinctBlokCount == 1 && murniRecords.isNotEmpty) {
        final blokInt = int.tryParse(murniRecords.first.blok);
        return '$kedusunanTitle • Blok ${blokInt ?? murniRecords.first.blok}';
      }
      return kedusunanTitle;
    }
    if (_drillDownDusun != null) {
      return '$base • Dusun $_drillDownDusun';
    }
    if (distinctBlokCount == 1 && murniRecords.isNotEmpty) {
      final blokInt = int.tryParse(murniRecords.first.blok);
      return '$base • Blok ${blokInt ?? murniRecords.first.blok}';
    }
    return base;
  }

  static final RegExp _nonDigitRegex = RegExp(r'[^0-9]');

  // Cache memoization untuk mencegah perhitungan ulang ribuan record di setiap frame animasi (60 FPS)
  List<BlokRecord>? _cachedScopeWidgetRecords;
  int _cachedScopeRecordsLen = -1;
  int? _cachedScopeWilayah;
  String? _cachedScopeDesaCode;
  int? _cachedScopeDrillDusun;
  String? _cachedScopeTahun;
  bool? _cachedScopeDusunLocked;
  _DhkpResolvedContext? _cachedScopeContext;

  List<BlokRecord>? _cachedGroupInputRecords;
  bool? _cachedGroupHasMultiDusun;
  String? _cachedGroupDesaCode;
  int? _cachedGroupDrillDusun;
  bool? _cachedGroupSeDesa;
  List<DhkpGroupInfo>? _cachedUnsortedGroups;
  GrafikSortMode? _cachedSortedMode;
  DhkpGrafikTab? _cachedSortedTab;
  List<DhkpGroupInfo>? _cachedSortedGroups;

  List<DhkpGroupInfo> _groupData(
    List<BlokRecord> records, {
    required bool hasMultiDusun,
    double Function(DhkpGroupInfo)? sortValueFn,
    bool applySort = true,
  }) {
    final baseMatch =
        identical(_cachedGroupInputRecords, records) &&
        _cachedGroupHasMultiDusun == hasMultiDusun &&
        _cachedGroupDesaCode == _selectedDesaCode &&
        _cachedGroupDrillDusun == _drillDownDusun &&
        _cachedGroupSeDesa == _seDesaMode;

    if (!applySort && baseMatch && _cachedUnsortedGroups != null) {
      return _cachedUnsortedGroups!;
    }
    if (applySort &&
        baseMatch &&
        _cachedSortedGroups != null &&
        _cachedSortedMode == _sortMode &&
        _cachedSortedTab == _activeTab) {
      return _cachedSortedGroups!;
    }

    final scope = _resolveScopeContext();
    final primaryKec = scope.primaryKecamatanCode;
    final desaCodes = scope.desaCodes;
    final effectiveDesa = scope.effectiveDesaCode;
    final isKecLevel = desaCodes.length > 1 && effectiveDesa == null;
    final isKedusunanScope =
        desaCodes.length <= 1 &&
        (DusunData.instance.isDusunLocked ||
            widget.selectedWilayah != null ||
            !hasMultiDusun);
    final groupByDusun =
        hasMultiDusun &&
        !isKedusunanScope &&
        _drillDownDusun == null &&
        !_seDesaMode;

    final List<DhkpGroupInfo> computed;
    if (isKecLevel) {
      computed = DhkpGrafikAnalytics.groupData(
        records,
        hasMultiDusun: hasMultiDusun,
        groupByDusun: groupByDusun,
        drillDownDusun: null,
        sortMode: _sortMode,
        sortValueFn: sortValueFn,
        applySort: applySort,
        seDesaMode: _seDesaMode,
        groupByDesa: !_seDesaMode,
        singleEntityLabel: _formatKecamatanLabel(primaryKec),
      );
    } else {
      final singleLabel = effectiveDesa != null
          ? DhkpGrafikAnalytics.formatDesaLabel(effectiveDesa)
          : (isKedusunanScope ? 'Se-Kedusunan' : 'Se-Desa');

      computed = DhkpGrafikAnalytics.groupData(
        records,
        hasMultiDusun: isKedusunanScope ? false : hasMultiDusun,
        groupByDusun: groupByDusun,
        drillDownDusun: isKedusunanScope ? null : _drillDownDusun,
        sortMode: _sortMode,
        sortValueFn: sortValueFn,
        applySort: applySort,
        seDesaMode: isKedusunanScope
            ? _seDesaMode
            : (_seDesaMode && _drillDownDusun == null),
        singleEntityLabel: singleLabel,
      );
    }

    if (!baseMatch) {
      _cachedGroupInputRecords = records;
      _cachedGroupHasMultiDusun = hasMultiDusun;
      _cachedGroupDesaCode = _selectedDesaCode;
      _cachedGroupDrillDusun = _drillDownDusun;
      _cachedGroupSeDesa = _seDesaMode;
      _cachedUnsortedGroups = null;
      _cachedSortedGroups = null;
    }
    if (!applySort) {
      _cachedUnsortedGroups = computed;
    } else {
      _cachedSortedMode = _sortMode;
      _cachedSortedTab = _activeTab;
      _cachedSortedGroups = computed;
    }
    return computed;
  }

  // =========================================================================
  // EKSPOR GRAFIK: UNDUH, BAGIKAN (GAMBAR & PDF SAJA), DAN CETAK
  // =========================================================================
  Future<Uint8List?> _captureSectionPng(String sectionKey) async {
    if (_collapsedSections.contains(sectionKey)) {
      setState(() {
        _collapsedSections.remove(sectionKey);
      });
      await Future.delayed(const Duration(milliseconds: 320));
    }
    var restoreCaptureFlag = false;
    if (!_isCapturingExport) {
      setState(() => _isCapturingExport = true);
      restoreCaptureFlag = true;
    }
    try {
      if (_animController.value < 1.0) {
        _animController.value = 1.0;
      }
      await Future.delayed(const Duration(milliseconds: 50));
      await WidgetsBinding.instance.endOfFrame;

      final key = _getBoundaryKey(sectionKey);
      final ctx = key.currentContext;
      if (ctx == null || !ctx.mounted) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      if (restoreCaptureFlag && mounted) {
        setState(() => _isCapturingExport = false);
      }
    }
  }

  Future<Uint8List> _generateSectionPdf({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
  }) async {
    final scope = _resolveScopeContext();
    final pngBytes = await _captureSectionPng(sectionKey);
    return DhkpGrafikExporter.generateSectionPdf(
      pngBytes: pngBytes,
      title: title,
      subtitle: subtitle,
      groups: groups,
      activeTab: _activeTab,
      groupByDusun:
          scope.hasMultiDusun && _drillDownDusun == null && !_seDesaMode,
      drillDownDusun: _drillDownDusun,
    );
  }

  Future<void> _handleDownloadSection({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
  }) async {
    final format = await DhkpGrafikExporter.showFormatChoiceDialog(
      context,
      dialogTitle: 'Unduh Data Grafik',
      dialogSubtitle: title,
    );
    if (format == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (format == 'png') {
        final bytes = await _captureSectionPng(sectionKey);
        if (bytes == null) throw Exception('Gagal menangkap tampilan grafik.');
        final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'png');
        final savedPath = await DownloadHelper.saveBytes(bytes, fileName);
        if (savedPath == null) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Gambar grafik disimpan: ${friendlyFileName(savedPath)}',
            ),
          ),
        );
      } else {
        final pdfBytes = await _generateSectionPdf(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
        final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'pdf');
        final savedPath = await DownloadHelper.saveBytes(pdfBytes, fileName);
        if (savedPath == null) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Dokumen PDF grafik disimpan: ${friendlyFileName(savedPath)}',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal mengunduh grafik: ${friendlyErrorMessage(e)}'),
        ),
      );
    }
  }

  Future<void> _handleShareSection({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
  }) async {
    final format = await DhkpGrafikExporter.showFormatChoiceDialog(
      context,
      dialogTitle: 'Bagikan Grafik',
      dialogSubtitle: 'Pilih bentuk berkas yang ingin dibagikan',
    );
    if (format == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (format == 'png') {
        final bytes = await _captureSectionPng(sectionKey);
        if (bytes == null) throw Exception('Gagal menangkap tampilan grafik.');
        final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'png');
        if (Platform.isAndroid) {
          await NativeFileHelper.shareBytes(
            bytes: bytes,
            fileName: fileName,
            mimeType: 'image/png',
          );
        } else {
          final savedPath = await DownloadHelper.saveBytes(
            bytes,
            fileName,
            useSaveAs: false,
          );
          if (savedPath == null) return;
          await NativeFileHelper.showInFileManager(savedPath);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Gambar grafik disimpan: ${friendlyFileName(savedPath)}',
              ),
            ),
          );
        }
      } else {
        final pdfBytes = await _generateSectionPdf(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
        final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'pdf');
        if (Platform.isAndroid) {
          await NativeFileHelper.shareBytes(
            bytes: pdfBytes,
            fileName: fileName,
            mimeType: 'application/pdf',
          );
        } else {
          final savedPath = await DownloadHelper.saveBytes(
            pdfBytes,
            fileName,
            useSaveAs: false,
          );
          if (savedPath == null) return;
          await NativeFileHelper.showInFileManager(savedPath);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Dokumen PDF grafik disimpan: ${friendlyFileName(savedPath)}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal membagikan grafik: ${friendlyErrorMessage(e)}'),
        ),
      );
    }
  }

  _DhkpResolvedContext _resolveScopeContext() {
    final isLocked = DusunData.instance.isDusunLocked;
    if (_cachedScopeContext != null &&
        identical(_cachedScopeWidgetRecords, widget.records) &&
        _cachedScopeRecordsLen == widget.records.length &&
        _cachedScopeWilayah == widget.selectedWilayah &&
        _cachedScopeDesaCode == _selectedDesaCode &&
        _cachedScopeDrillDusun == _drillDownDusun &&
        _cachedScopeTahun == _selectedTahun &&
        _cachedScopeDusunLocked == isLocked) {
      return _cachedScopeContext!;
    }

    final allMurni = widget.records.where((r) => !r.isTargetPemda).toList();

    final kecSet = <String>{};
    for (final r in allMurni) {
      final d = r.nop.replaceAll(_nonDigitRegex, '');
      if (d.length == 18) kecSet.add(nopKecamatan(d));
    }
    final primaryKecCode = DhkpGrafikAnalytics.resolvePrimaryKecamatanCode(
      allMurni,
    );
    final hasMultipleKecamatans = kecSet.length > 1;

    // Antisipasi data lintas kecamatan: batasi tampilan grafik ke 1 kecamatan utama saja.
    final scopedKecRecords = primaryKecCode.isEmpty
        ? allMurni
        : allMurni.where((r) {
            final d = r.nop.replaceAll(_nonDigitRegex, '');
            return d.length != 18 || nopKecamatan(d) == primaryKecCode;
          }).toList();

    final desaCodes = DhkpGrafikAnalytics.resolveDesaCodesInKecamatan(
      scopedKecRecords,
      primaryKecCode,
    );
    final hasMultiDesa = desaCodes.length > 1;
    final effectiveDesaCode =
        (hasMultiDesa &&
            _selectedDesaCode != null &&
            desaCodes.contains(_selectedDesaCode))
        ? _selectedDesaCode
        : null;

    var entityAcrossYears = scopedKecRecords;
    if (effectiveDesaCode != null) {
      entityAcrossYears = entityAcrossYears.where((r) {
        final d = r.nop.replaceAll(_nonDigitRegex, '');
        return d.length == 18 && nopKelurahan(d) == effectiveDesaCode;
      }).toList();
    }

    if (!hasMultiDesa && widget.selectedWilayah != null) {
      final dObj = dusunByNumber(widget.selectedWilayah!);
      final dBloks = dObj?.bloks.toSet() ?? <String>{};
      if (dBloks.isNotEmpty) {
        entityAcrossYears = entityAcrossYears
            .where((r) => dBloks.contains(r.blok))
            .toList();
      }
    }

    final uniqueDusuns = <int>{};
    for (final r in entityAcrossYears) {
      for (final d in dusunList) {
        if (d.bloks.contains(r.blok)) {
          uniqueDusuns.add(d.number);
          break;
        }
      }
    }
    final hasMultiDusun = uniqueDusuns.length > 1;
    final isKedusunanScope =
        !hasMultiDesa &&
        (DusunData.instance.isDusunLocked ||
            widget.selectedWilayah != null ||
            (!hasMultiDusun && uniqueDusuns.length == 1));
    final activeKedusunanNumber = isKedusunanScope
        ? (DusunData.instance.isDusunLocked
              ? DusunData.instance.lockedDusunNumber
              : (widget.selectedWilayah ??
                    (uniqueDusuns.length == 1 ? uniqueDusuns.first : null)))
        : null;

    if (!hasMultiDesa || effectiveDesaCode != null) {
      if (!isKedusunanScope && hasMultiDusun && _drillDownDusun != null) {
        final dObj = dusunByNumber(_drillDownDusun!);
        final dBloks = dObj?.bloks.toSet() ?? <String>{};
        entityAcrossYears = entityAcrossYears
            .where((r) => dBloks.contains(r.blok))
            .toList();
      }
    }

    final availableYears =
        scopedKecRecords
            .map((r) => r.tahunBayar)
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    if (availableYears.isNotEmpty && !availableYears.contains(_selectedTahun)) {
      _selectedTahun =
          (widget.selectedTahun != null &&
              availableYears.contains(widget.selectedTahun))
          ? widget.selectedTahun!
          : availableYears.first;
    }

    var murniRecords = entityAcrossYears;
    if (availableYears.isNotEmpty) {
      murniRecords = murniRecords
          .where((r) => r.tahunBayar == _selectedTahun)
          .toList();
    }

    final resolved = _DhkpResolvedContext(
      murniRecords: murniRecords,
      entityRecordsAcrossYears: entityAcrossYears,
      allScopedRecordsAcrossYears: scopedKecRecords,
      hasMultiDusun: isKedusunanScope ? false : hasMultiDusun,
      uniqueDusuns: uniqueDusuns.toList()..sort(),
      availableYears: availableYears,
      primaryKecamatanCode: primaryKecCode,
      hasMultipleKecamatans: hasMultipleKecamatans,
      desaCodes: desaCodes,
      hasMultiDesa: hasMultiDesa,
      effectiveDesaCode: effectiveDesaCode,
      isKedusunanScope: isKedusunanScope,
      activeKedusunanNumber: activeKedusunanNumber,
    );
    _cachedScopeWidgetRecords = widget.records;
    _cachedScopeRecordsLen = widget.records.length;
    _cachedScopeWilayah = widget.selectedWilayah;
    _cachedScopeDesaCode = _selectedDesaCode;
    _cachedScopeDrillDusun = _drillDownDusun;
    _cachedScopeTahun = _selectedTahun;
    _cachedScopeDusunLocked = isLocked;
    _cachedScopeContext = resolved;
    return resolved;
  }

  (
    List<BlokRecord> murniRecords,
    bool hasMultiDusun,
    List<int> uniqueDusuns,
    List<String> availableYears,
  )
  _resolveFilteredMurniRecords() {
    final ctx = _resolveScopeContext();
    return (
      ctx.murniRecords,
      ctx.hasMultiDusun,
      ctx.uniqueDusuns,
      ctx.availableYears,
    );
  }

  bool _canCompareYearsForScope(_DhkpResolvedContext ctx) {
    if (ctx.availableYears.length <= 1) return false;
    if (ctx.isKecamatanAggregate) return _seDesaMode;
    if (ctx.isKedusunanScope) return _seDesaMode || _isSpecificBlokFiltered;
    if (_drillDownDusun != null) return true;
    if (_seDesaMode) return true;
    final distinctBloks = ctx.entityRecordsAcrossYears
        .map((r) => r.blok)
        .toSet();
    return !ctx.hasMultiDusun && distinctBloks.length <= 1;
  }

  String? _resolveValidCompareYear(List<String> availableYears) {
    final target = _compareYear;
    if (target == null ||
        target == _selectedTahun ||
        !availableYears.contains(target)) {
      return null;
    }
    return target;
  }

  String? _suggestDefaultCompareYear(List<String> availableYears) {
    final candidates = availableYears
        .where((y) => y != _selectedTahun)
        .toList();
    if (candidates.isEmpty) return null;
    final selectedInt = int.tryParse(_selectedTahun);
    for (final y in candidates) {
      final yInt = int.tryParse(y);
      if (selectedInt != null && yInt != null) {
        if (yInt < selectedInt) return y;
      } else if (y.compareTo(_selectedTahun) < 0) {
        return y;
      }
    }
    return candidates.last;
  }

  void _applyCompareYear(String? year, {required _DhkpResolvedContext scope}) {
    if (year == null) {
      if (_compareYear == null) return;
      setState(() {
        _compareYear = null;
        _selectedItemLabel = null;
      });
      _savePreferences();
      return;
    }

    if (scope.availableYears.length <= 1) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Data perbandingan tahun belum tersedia di database. Membutuhkan minimal 2 tahun data.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    final validTarget = year == _selectedTahun
        ? _suggestDefaultCompareYear(scope.availableYears)
        : (scope.availableYears.contains(year) ? year : null);
    if (validTarget == null) return;

    final canCompare = _canCompareYearsForScope(scope);
    setState(() {
      if (!canCompare) {
        _drillDownDusun = null;
        _seDesaMode = true;
      }
      _compareYear = validTarget;
      _selectedItemLabel = null;
    });
    _savePreferences();
  }

  List<DhkpTrendSeries> _buildTrendSeriesForScope(
    _DhkpResolvedContext ctx,
    bool isDark,
  ) {
    final canCompare = _canCompareYearsForScope(ctx);
    final activeCompareYear = canCompare
        ? _resolveValidCompareYear(ctx.availableYears)
        : null;
    if (activeCompareYear != null) {
      return DhkpGrafikAnalytics.buildYearComparisonSeries(
        entityRecords: ctx.entityRecordsAcrossYears,
        primaryYear: _selectedTahun,
        compareYears: [_selectedTahun, activeCompareYear],
        isDark: isDark,
        maxYears: 2,
      );
    }

    if (ctx.isKecamatanAggregate) {
      if (_seDesaMode) {
        final single = DhkpGrafikAnalytics.buildYearComparisonSeries(
          entityRecords: ctx.entityRecordsAcrossYears,
          primaryYear: _selectedTahun,
          compareYears: [_selectedTahun],
          isDark: isDark,
          maxYears: 1,
        );
        if (single.isEmpty) return single;
        final label = _formatKecamatanLabel(ctx.primaryKecamatanCode);
        final s = single.first;
        return [
          DhkpTrendSeries(
            id: 'kec:$label',
            label: label,
            monthlyNominal: s.monthlyNominal,
            monthlyCounts: s.monthlyCounts,
            totalNominal: s.totalNominal,
            totalCount: s.totalCount,
            color: s.color,
            isPrimary: true,
            isDashed: false,
          ),
        ];
      }
      return DhkpGrafikAnalytics.buildDesaMonthlySeries(
        records: ctx.murniRecords,
        tahun: _selectedTahun,
        isDark: isDark,
        customDesas: _customCompareDesas,
        maxDesas: _maxCustomDesas,
      );
    }

    if (_drillDownDusun != null && ctx.hasMultiDusun) {
      return DhkpGrafikAnalytics.buildBlokMonthlySeries(
        records: ctx.murniRecords,
        tahun: _selectedTahun,
        isDark: isDark,
        dusunNumber: _drillDownDusun,
      );
    }

    if (_seDesaMode) {
      final single = DhkpGrafikAnalytics.buildYearComparisonSeries(
        entityRecords: ctx.entityRecordsAcrossYears,
        primaryYear: _selectedTahun,
        compareYears: [_selectedTahun],
        isDark: isDark,
        maxYears: 1,
      );
      if (single.isEmpty) return single;
      final label = ctx.effectiveDesaCode != null
          ? DhkpGrafikAnalytics.formatDesaLabel(ctx.effectiveDesaCode!)
          : (ctx.isKedusunanScope
                ? 'Se-Kedusunan ($_selectedTahun)'
                : 'Se-Desa ($_selectedTahun)');
      final s = single.first;
      return [
        DhkpTrendSeries(
          id: 'desa:$label',
          label: label,
          monthlyNominal: s.monthlyNominal,
          monthlyCounts: s.monthlyCounts,
          totalNominal: s.totalNominal,
          totalCount: s.totalCount,
          color: s.color,
          isPrimary: true,
          isDashed: false,
        ),
      ];
    }

    if (ctx.hasMultiDusun) {
      return DhkpGrafikAnalytics.buildMultiDusunMonthlySeries(
        records: ctx.murniRecords,
        tahun: _selectedTahun,
        isDark: isDark,
      );
    }

    return DhkpGrafikAnalytics.buildBlokMonthlySeries(
      records: ctx.murniRecords,
      tahun: _selectedTahun,
      isDark: isDark,
      dusunNumber:
          ctx.activeKedusunanNumber ??
          (ctx.uniqueDusuns.length == 1 ? ctx.uniqueDusuns.first : null),
    );
  }

  Future<Set<String>?> _showChecklistCompareDialog({
    required String title,
    required String description,
    required int maxItems,
    required List<({String id, String label, int nominal})> items,
    required Set<String> currentSelected,
  }) async {
    if (items.isEmpty) return null;
    final initial = currentSelected
        .where((id) => items.any((item) => item.id == id))
        .toSet();
    if (initial.isEmpty) {
      final byTop = [...items]..sort((a, b) => b.nominal.compareTo(a.nominal));
      initial.addAll(byTop.take(maxItems).map((e) => e.id));
    }

    return showDialog<Set<String>>(
      context: context,
      builder: (dlgCtx) {
        final temp = Set<String>.from(initial);
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text('$title (${temp.length}/$maxItems)'),
              content: SizedBox(
                width: 340,
                height: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, idx) {
                          final item = items[idx];
                          final checked = temp.contains(item.id);
                          final blocked = !checked && temp.length >= maxItems;
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            onChanged: blocked
                                ? null
                                : (val) {
                                    setDlgState(() {
                                      if (val == true) {
                                        temp.add(item.id);
                                      } else if (temp.length > 1) {
                                        temp.remove(item.id);
                                      }
                                    });
                                  },
                            title: Text(item.label),
                            subtitle: Text(
                              'Lunas: ${formatRupiah(item.nominal)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dlgCtx).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: temp.isEmpty
                      ? null
                      : () => Navigator.of(dlgCtx).pop(temp),
                  child: const Text('Terapkan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openSelectDesaDialog(
    List<BlokRecord> kecRecords,
    List<String> desaCodes,
  ) async {
    final desaNom = <String, int>{for (final k in desaCodes) k: 0};
    for (final r in kecRecords) {
      final d = r.nop.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length == 18 && r.isPaid) {
        final k = nopKelurahan(d);
        if (desaNom.containsKey(k)) {
          desaNom[k] = (desaNom[k] ?? 0) + r.jumlahPbbValue;
        }
      }
    }
    final items = [
      for (final k in desaCodes)
        (
          id: k,
          label: DhkpGrafikAnalytics.formatDesaLabel(k),
          nominal: desaNom[k] ?? 0,
        ),
    ];
    final picked = await _showChecklistCompareDialog(
      title: 'Pilih Desa Pembanding',
      description:
          'Pilih maksimal $_maxCustomDesas desa dalam 1 kecamatan agar perbandingan tetap rapi.',
      maxItems: _maxCustomDesas,
      items: items,
      currentSelected: _customCompareDesas,
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      _customCompareDesas
        ..clear()
        ..addAll(picked.take(_maxCustomDesas));
    });
  }

  Future<void> _printSingleSelectedMonth(
    List<BlokRecord> murniRecords,
    int monthIndex,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final monthRecords = DhkpGrafikAnalytics.getPaidRecordsForMonth(
        murniRecords,
        monthIndex,
        tahun: _selectedTahun,
      );
      final monthName =
          (monthIndex >= 1 &&
              monthIndex <= DhkpGrafikAnalytics.fullMonthNames.length)
          ? DhkpGrafikAnalytics.fullMonthNames[monthIndex - 1]
          : 'Bulan_$monthIndex';
      final cancelToken = BlokPrintCancelToken();
      final pdfBytes = await runCancellableDhkpPrint<Uint8List>(
        context: context,
        cancelToken: cancelToken,
        title: 'Menyiapkan Cetakan Grafik',
        initialMessage: 'Menyusun rincian pembayaran bulan $monthName...',
        subtitle:
            'Anda dapat menekan Batal Cetak kapan saja sebelum dokumen dikirim ke printer.',
        task: (_) async {
          final bytes = await generateDhkpRincianBulananPdfBytes(
            targetRecords: monthRecords,
            monthIndex: monthIndex,
            tahun: _selectedTahun,
          );
          if (cancelToken.isCancelled) {
            throw const BlokPrintCancelledException();
          }
          return bytes;
        },
      );
      if (pdfBytes == null || cancelToken.isCancelled || !mounted) {
        if (cancelToken.isCancelled && mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Proses cetak DHKP dibatalkan.')),
          );
        }
        return;
      }
      final fileName =
          'Laporan_Bayar_${monthName.toLowerCase()}_$_selectedTahun.pdf';
      await DocumentPreviewScreen.printOrPreview(
        context,
        pdfBytes: pdfBytes,
        fileName: fileName,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Gagal menyiapkan cetak laporan bulanan.',
            ),
          ),
        ),
      );
    }
  }

  /// Mencetak tampilan grafik/diagram aktif saat ini (dipanggil saat menekan Ctrl+P
  /// atau tombol Cetak di AppBar ketika tab Grafik sedang dibuka).
  /// - Untuk tab Tren Bulanan:
  ///   * Jika pengguna sudah mengeklik salah satu batang bulan (misal "Jan".."Des"),
  ///     maka mencetak khusus rincian pembayaran 1 bulan tersebut saja.
  ///   * Jika tidak ada bulan yang diklik, mencetak rekapitulasi seluruh 12 bulan.
  /// - Untuk tab Persentase / Pendapatan / Belum Bayar / Sudah Bayar:
  ///   * Mencetak diagram yang sedang dipilih (Batang / Mendatar / Lingkaran)
  ///     beserta tabel data tab aktif.
  Future<void> printCurrentSelection() async {
    final (murniRecords, hasMultiDusun, _, _) = _resolveFilteredMurniRecords();
    if (murniRecords.isEmpty) return;

    if (_activeTab == DhkpGrafikTab.trenBulanan) {
      final selectedMonthIdx = _selectedItemLabel != null
          ? DhkpGrafikAnalytics.monthNames.indexOf(_selectedItemLabel!) + 1
          : 0;
      if (selectedMonthIdx >= 1 && selectedMonthIdx <= 12) {
        await _printSingleSelectedMonth(murniRecords, selectedMonthIdx);
        return;
      }

      final monthGroups = DhkpGrafikAnalytics.buildMonthGroups(
        murniRecords,
        tahun: _selectedTahun,
      );
      final (sectionKey, title, subtitle) = switch (_selectedStyle) {
        ChartStyle.bar => (
          'bar',
          'Diagram Mendatar: Rincian Bulanan (Jan - Des)',
          'Daftar penerimaan kas dari awal hingga akhir tahun',
        ),
        ChartStyle.pie => (
          'pie',
          'Diagram Lingkaran: Porsi Penerimaan per Bulan',
          'Kontribusi tiap bulan terhadap total penerimaan tahunan',
        ),
        ChartStyle.batang || ChartStyle.semua => (
          'batang',
          'Grafik Garis Tren Pembayaran Bulanan',
          'Pergerakan penerimaan kas dari awal hingga akhir tahun (Jan - Des)',
        ),
      };
      await _handlePrintSection(
        sectionKey: sectionKey,
        title: title,
        subtitle: subtitle,
        groups: monthGroups,
      );
      return;
    }

    final sectionKey = switch (_selectedStyle) {
      ChartStyle.bar => 'bar',
      ChartStyle.pie => 'pie',
      ChartStyle.batang || ChartStyle.semua => 'batang',
    };

    switch (_activeTab) {
      case DhkpGrafikTab.persentase:
        final groups = _groupData(
          murniRecords,
          hasMultiDusun: hasMultiDusun,
          sortValueFn: (g) => g.lunasPct,
        );
        final (title, subtitle) = switch (sectionKey) {
          'bar' => (
            'Diagram Mendatar: Capaian Persentase Wilayah',
            'Tingkat pencapaian pembayaran terhadap target 100%',
          ),
          'pie' => (
            'Diagram Lingkaran: Sudah Tercapai vs Sisa Target',
            'Perbandingan persentase lunas dan sisa yang belum masuk',
          ),
          _ => (
            'Diagram Batang: Capaian Persentase (%)',
            'Skala capaian 0% sampai 100% per wilayah',
          ),
        };
        await _handlePrintSection(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
      case DhkpGrafikTab.pendapatan:
        final groups = _groupData(
          murniRecords,
          hasMultiDusun: hasMultiDusun,
          sortValueFn: (g) => g.lunasNominal.toDouble(),
        );
        final (title, subtitle) = switch (sectionKey) {
          'bar' => (
            'Diagram Mendatar: Peringkat Pendapatan (Rp)',
            'Perbandingan uang masuk antar wilayah',
          ),
          'pie' => (
            'Diagram Lingkaran: Porsi Pendapatan Masuk',
            'Perbandingan sumbangan penerimaan tiap wilayah',
          ),
          _ => (
            'Diagram Batang: Pendapatan Masuk (Rp)',
            'Ketuk batang untuk melihat rincian wilayah',
          ),
        };
        await _handlePrintSection(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
      case DhkpGrafikTab.belumBayar:
        final groups = _groupData(
          murniRecords,
          hasMultiDusun: hasMultiDusun,
          sortValueFn: (g) => g.belumBayarNominal.toDouble(),
        );
        final (title, subtitle) = switch (sectionKey) {
          'bar' => (
            'Diagram Mendatar: Urutan Belum Bayar per Wilayah',
            'Wilayah dengan sisa tagihan belum lunas terbesar',
          ),
          'pie' => (
            'Diagram Lingkaran: Sebaran Belum Bayar',
            'Perbandingan sisa tagihan antar wilayah',
          ),
          _ => (
            'Diagram Batang: Tagihan Belum Bayar (Rp)',
            'Jumlah tagihan yang masih perlu ditagih per wilayah',
          ),
        };
        await _handlePrintSection(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
      case DhkpGrafikTab.sudahBayar:
        final groups = _groupData(
          murniRecords,
          hasMultiDusun: hasMultiDusun,
          sortValueFn: (g) => g.lunasNop.toDouble(),
        );
        final (title, subtitle) = switch (sectionKey) {
          'bar' => (
            'Diagram Mendatar: Urutan Objek Lunas',
            'Urutan wilayah berdasarkan jumlah warga yang sudah bayar',
          ),
          'pie' => (
            'Diagram Lingkaran: Sebaran Objek Lunas',
            'Perbandingan jumlah wajib pajak yang telah membayar',
          ),
          _ => (
            'Diagram Batang: Jumlah Objek Sudah Bayar',
            'Banyaknya objek pajak yang sudah lunas per wilayah',
          ),
        };
        await _handlePrintSection(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
      case DhkpGrafikTab.trenBulanan:
        break;
    }
  }

  Future<void> _handlePrintSection({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
  }) async {
    // Jika di tab Tren Pembayaran dan pengguna sedang memilih 1 batang bulan tertentu,
    // cetak langsung laporan 1 bulan yang dipilih tersebut saja.
    if (_activeTab == DhkpGrafikTab.trenBulanan && _selectedItemLabel != null) {
      final selectedMonthIdx =
          DhkpGrafikAnalytics.monthNames.indexOf(_selectedItemLabel!) + 1;
      if (selectedMonthIdx >= 1 && selectedMonthIdx <= 12) {
        final (murniRecords, _, _, _) = _resolveFilteredMurniRecords();
        await _printSingleSelectedMonth(murniRecords, selectedMonthIdx);
        return;
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final cancelToken = BlokPrintCancelToken();
      final pdfBytes = await runCancellableDhkpPrint<Uint8List>(
        context: context,
        cancelToken: cancelToken,
        title: 'Menyiapkan Cetakan Grafik',
        initialMessage: 'Menyusun $title...',
        subtitle:
            'Anda dapat menekan Batal Cetak kapan saja sebelum dokumen dikirim ke printer.',
        task: (_) async {
          final bytes = await _generateSectionPdf(
            sectionKey: sectionKey,
            title: title,
            subtitle: subtitle,
            groups: groups,
          );
          if (cancelToken.isCancelled) {
            throw const BlokPrintCancelledException();
          }
          return bytes;
        },
      );
      if (pdfBytes == null || cancelToken.isCancelled || !mounted) {
        if (cancelToken.isCancelled && mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Proses cetak DHKP dibatalkan.')),
          );
        }
        return;
      }
      final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'pdf');
      await DocumentPreviewScreen.printOrPreview(
        context,
        pdfBytes: pdfBytes,
        fileName: fileName,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Gagal menyiapkan cetak grafik.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final scope = _resolveScopeContext();
    final murniRecords = scope.murniRecords;
    final hasMultiDusun = scope.hasMultiDusun;
    final distinctBlokCount = scope.entityRecordsAcrossYears
        .map((r) => r.blok)
        .toSet()
        .length;
    final showScopeBar =
        !_isSpecificBlokFiltered &&
        (hasMultiDusun ||
            scope.hasMultiDesa ||
            scope.hasMultipleKecamatans ||
            distinctBlokCount > 1);

    final totalNop = murniRecords.length;
    final sudahBayarList = murniRecords.where((r) => r.isPaid).toList();
    final belumBayarList = murniRecords.where((r) => !r.isPaid).toList();

    final totalNominalTarget = murniRecords.fold<int>(
      0,
      (sum, r) => sum + r.jumlahPbbValue,
    );
    final sudahBayarNominal = sudahBayarList.fold<int>(
      0,
      (sum, r) => sum + r.jumlahPbbValue,
    );
    final belumBayarNominal = belumBayarList.fold<int>(
      0,
      (sum, r) => sum + r.jumlahPbbValue,
    );

    final lunasNopPct = totalNop > 0
        ? (sudahBayarList.length / totalNop * 100)
        : 0.0;
    final lunasNominalPct = (totalNominalTarget > 0 && belumBayarNominal > 0)
        ? (sudahBayarNominal / totalNominalTarget * 100)
        : (belumBayarList.isEmpty ? (totalNop > 0 ? 100.0 : 0.0) : lunasNopPct);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            printCurrentSelection,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            printCurrentSelection,
      },
      child: Focus(
        autofocus: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. TOP TAB BAR: 5 KATEGORI UTAMA
              KeyedSubtree(
                key: _topTabsKey,
                child: _buildTopCategoryTabs(isDark, colorScheme),
              ),
              const SizedBox(height: 10),

              // 2. FILTER CEPAT WILAYAH (KECAMATAN/DESA/SE-DESA/DUSUN/BLOK)
              if (showScopeBar) ...[
                KeyedSubtree(
                  key: _scopeBarKey,
                  child: _buildScopeQuickBar(scope, isDark, colorScheme),
                ),
                const SizedBox(height: 10),
              ],

              // 3. KARTU RINGKASAN UTAMA DI ATAS (GAUGE REALISASI + 3 METRIK SPARKLINE)
              KeyedSubtree(
                key: _statCardsKey,
                child: () {
                  final overviewGroups = _groupData(
                    murniRecords,
                    hasMultiDusun: hasMultiDusun,
                    applySort: false,
                  );
                  String? prevYearLabel;
                  List<BlokRecord>? prevYearRecords;
                  if (scope.availableYears.length > 1 &&
                      _selectedTahun.isNotEmpty) {
                    final activeIdx = scope.availableYears.indexOf(
                      _selectedTahun,
                    );
                    if (activeIdx >= 0 &&
                        activeIdx + 1 < scope.availableYears.length) {
                      prevYearLabel = scope.availableYears[activeIdx + 1];
                      prevYearRecords = scope.entityRecordsAcrossYears
                          .where((r) => r.tahunBayar == prevYearLabel)
                          .toList();
                    }
                  }

                  final gaugeScopeTitle = _formatGaugeScopeTitle(
                    scope,
                    murniRecords,
                    distinctBlokCount,
                  );
                  final gaugeSummary = DhkpGrafikAnalytics.buildGaugeSummary(
                    scopeTitle: gaugeScopeTitle,
                    tahun: _selectedTahun,
                    paidNominal: sudahBayarNominal,
                    targetNominal: totalNominalTarget,
                    paidCount: sudahBayarList.length,
                    totalCount: totalNop,
                    achievedPct: lunasNominalPct,
                    objPct: lunasNopPct,
                    accentColor: _themeAccent,
                    previousYearRecords: prevYearRecords,
                    previousYearLabel: prevYearLabel,
                  );
                  final highlightItems = DhkpGrafikAnalytics.buildHighlightStats(
                    activeTab: _activeTab,
                    totalNop: totalNop,
                    sudahBayarCount: sudahBayarList.length,
                    belumBayarCount: belumBayarList.length,
                    sudahBayarNominal: sudahBayarNominal,
                    belumBayarNominal: belumBayarNominal,
                    totalNominalTarget: totalNominalTarget,
                    lunasNominalPct: lunasNominalPct,
                    lunasNopPct: lunasNopPct,
                    records: murniRecords,
                    tahun: _selectedTahun,
                    previousYearRecords: prevYearRecords,
                    previousYearLabel: prevYearLabel,
                    groups: overviewGroups,
                    colorScheme: colorScheme,
                  );

                  return buildDhkpKpiWithGaugeOverview(
                    items: highlightItems,
                    gauge: gaugeSummary,
                    isDark: isDark,
                  );
                }(),
              ),
              const SizedBox(height: 10),

              // 4. TOOLBAR KONTROL: PILIH DIAGRAM + URUTAN + LIPAT/BUKA SEMUA
              KeyedSubtree(
                key: _controlToolbarKey,
                child: _buildControlToolbar(hasMultiDusun, isDark, colorScheme),
              ),
              const SizedBox(height: 12),

              // 5. PANEL DETAIL INTERAKTIF (MUNCUL SAAT SALAH SATU WILAYAH DIKLIK)
              AppAnimatedSize(
                duration: AppMotion.component,
                curve: AppMotion.smoothCurve,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: AppMotion.resolve(context, AppMotion.component),
                  switchInCurve: AppMotion.enterCurve,
                  switchOutCurve: AppMotion.exitCurve,
                  child: _selectedItemLabel != null
                      ? Padding(
                          key: ValueKey(
                            'banner:${_activeTab.name}:$_selectedItemLabel',
                          ),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildSelectedDetailBanner(
                            murniRecords,
                            hasMultiDusun,
                            isDark,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('banner:empty')),
                ),
              ),

              // 6. KONTEN GRAFIK & TABEL DENGAN FITUR LIPAT + UNDUH/BAGIKAN/CETAK
              KeyedSubtree(
                key: _chartContentKey,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, _) {
                    final tabContent = KeyedSubtree(
                      key: ValueKey(_activeTab),
                      child: switch (_activeTab) {
                        DhkpGrafikTab.pendapatan => _buildPendapatanSection(
                          murniRecords,
                          hasMultiDusun,
                          sudahBayarNominal,
                          totalNominalTarget,
                          isDark,
                        ),
                        DhkpGrafikTab.persentase => _buildPersentaseSection(
                          murniRecords,
                          hasMultiDusun,
                          lunasNominalPct,
                          isDark,
                        ),
                        DhkpGrafikTab.belumBayar => _buildBelumBayarSection(
                          murniRecords,
                          hasMultiDusun,
                          belumBayarNominal,
                          totalNominalTarget,
                          isDark,
                        ),
                        DhkpGrafikTab.sudahBayar => _buildSudahBayarSection(
                          murniRecords,
                          hasMultiDusun,
                          sudahBayarList.length,
                          sudahBayarNominal,
                          isDark,
                        ),
                        DhkpGrafikTab.trenBulanan => _buildTrenBulananSection(
                          scope,
                          isDark,
                        ),
                      },
                    );
                    return AnimatedSwitcher(
                      duration: AppMotion.resolve(
                        context,
                        const Duration(milliseconds: 380),
                      ),
                      switchInCurve: const UnityAnimationCurve(),
                      switchOutCurve: AppMotion.exitCurve,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previousChildren, ?currentChild],
                      ),
                      transitionBuilder: (child, anim) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.015),
                          end: Offset.zero,
                        ).animate(anim);
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: tabContent,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 1. TOP CATEGORY TABS (5 DATA UTAMA)
  // =========================================================================
  Widget _buildTopCategoryTabs(bool isDark, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 620;
          final tabWidgets = [
            for (final tab in DhkpGrafikTab.values)
              _buildSingleTabButton(tab, isWide, isDark),
          ];

          if (isWide) {
            return Row(
              children: [
                for (int i = 0; i < tabWidgets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: tabWidgets[i]),
                ],
              ],
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (int i = 0; i < tabWidgets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  tabWidgets[i],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSingleTabButton(DhkpGrafikTab tab, bool isWide, bool isDark) {
    final isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => _switchTab(tab),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 8 : 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [_themeAccent.shade600, _themeAccent.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _themeAccent.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.grey.shade300 : _themeAccent.shade700),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 2. QUICK SCOPE BAR (KECAMATAN/PER DESA/SE-DESA/SEMUA DUSUN/BLOK/DUSUN)
  // =========================================================================
  Widget _buildDesaSubScopeRow(
    _DhkpResolvedContext scope,
    MaterialColor accent,
    bool isDark, {
    String prefixLabel = 'Wilayah:',
  }) {
    final isAtDesaSubScope =
        !scope.hasMultiDesa || scope.effectiveDesaCode != null;
    final distinctBlokCount = scope.entityRecordsAcrossYears
        .map((r) => r.blok)
        .toSet()
        .length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Icon(Icons.place_rounded, size: 15, color: accent.shade700),
          const SizedBox(width: 6),
          Text(
            prefixLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 8),
          if (scope.hasMultipleKecamatans && !scope.hasMultiDesa) ...[
            _buildScopeMetaBadge(
              label:
                  '${_formatKecamatanLabel(scope.primaryKecamatanCode)} (1 Kec)',
              accent: accent,
              isDark: isDark,
              tooltip:
                  'Data lintas kecamatan dibatasi ke 1 kecamatan utama agar grafik tetap fokus dan terbaca.',
            ),
            const SizedBox(width: 6),
          ],
          if (scope.isKedusunanScope) ...[
            _buildScopeChip(
              label: 'Se-Kedusunan',
              isSelected: _seDesaMode,
              accent: accent,
              isDark: isDark,
              onTap: () {
                setState(() {
                  _drillDownDusun = null;
                  _seDesaMode = true;
                  _selectedItemLabel = null;
                });
                _savePreferences();
                _replayAnimation();
              },
            ),
            const SizedBox(width: 4),
            _buildScopeChip(
              label: 'Semua Blok',
              isSelected: !_seDesaMode,
              accent: accent,
              isDark: isDark,
              onTap: () {
                setState(() {
                  _drillDownDusun = null;
                  _seDesaMode = false;
                  _compareYear = null;
                  _selectedItemLabel = null;
                });
                _savePreferences();
                _replayAnimation();
              },
            ),
          ] else ...[
            _buildScopeChip(
              label: 'Se-Desa',
              isSelected:
                  isAtDesaSubScope && _drillDownDusun == null && _seDesaMode,
              accent: accent,
              isDark: isDark,
              onTap: () {
                setState(() {
                  _drillDownDusun = null;
                  _seDesaMode = true;
                  _selectedItemLabel = null;
                });
                _savePreferences();
                _replayAnimation();
              },
            ),
            if (scope.hasMultiDusun) ...[
              const SizedBox(width: 4),
              _buildScopeChip(
                label: 'Semua Dusun',
                isSelected:
                    isAtDesaSubScope && _drillDownDusun == null && !_seDesaMode,
                accent: accent,
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _drillDownDusun = null;
                    _seDesaMode = false;
                    _compareYear = null;
                    _selectedItemLabel = null;
                  });
                  _savePreferences();
                  _replayAnimation();
                },
              ),
            ],
            if (!scope.hasMultiDusun &&
                scope.uniqueDusuns.isEmpty &&
                distinctBlokCount > 1) ...[
              const SizedBox(width: 4),
              _buildScopeChip(
                label: 'Per Blok',
                isSelected:
                    isAtDesaSubScope && _drillDownDusun == null && !_seDesaMode,
                accent: accent,
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _drillDownDusun = null;
                    _seDesaMode = false;
                    _compareYear = null;
                    _selectedItemLabel = null;
                  });
                  _savePreferences();
                  _replayAnimation();
                },
              ),
            ],
            if (scope.uniqueDusuns.isNotEmpty) ...[
              Container(
                height: 16,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
              for (final dNum in scope.uniqueDusuns)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _buildScopeChip(
                    label: 'Dusun $dNum',
                    isSelected:
                        isAtDesaSubScope &&
                        (_drillDownDusun == dNum ||
                            (!scope.hasMultiDusun &&
                                _drillDownDusun == null &&
                                !_seDesaMode)),
                    accent: accent,
                    isDark: isDark,
                    onTap: () {
                      setState(() {
                        final isCurrentlySelected =
                            _drillDownDusun == dNum ||
                            (!scope.hasMultiDusun &&
                                _drillDownDusun == null &&
                                !_seDesaMode);
                        if (isCurrentlySelected) {
                          _drillDownDusun = null;
                          _seDesaMode = !scope.hasMultiDusun;
                        } else {
                          _drillDownDusun = dNum;
                          _seDesaMode = false;
                        }
                        _selectedItemLabel = null;
                      });
                      _savePreferences();
                      _replayAnimation();
                    },
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildScopeMetaBadge({
    required String label,
    required MaterialColor accent,
    required bool isDark,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.42 : 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 12,
              color: isDark ? accent.shade200 : accent.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isDark ? accent.shade200 : accent.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeQuickBar(
    _DhkpResolvedContext scope,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final accent = _themeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: scope.hasMultiDesa
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildScopeMetaBadge(
                        label: scope.hasMultipleKecamatans
                            ? '${_formatKecamatanLabel(scope.primaryKecamatanCode)} (Maks. 1 Kec)'
                            : _formatKecamatanLabel(scope.primaryKecamatanCode),
                        accent: accent,
                        isDark: isDark,
                        tooltip:
                            'Antisipasi data kecamatan: grafik dibatasi 1 kecamatan (${_formatKecamatanLabel(scope.primaryKecamatanCode)}) dan dapat dilihat per desa.',
                      ),
                      const SizedBox(width: 8),
                      _buildScopeChip(
                        label: 'Se-Kecamatan',
                        isSelected: scope.isKecamatanAggregate && _seDesaMode,
                        accent: accent,
                        isDark: isDark,
                        onTap: () {
                          setState(() {
                            _selectedDesaCode = null;
                            _drillDownDusun = null;
                            _seDesaMode = true;
                            _selectedItemLabel = null;
                          });
                          _savePreferences();
                          _replayAnimation();
                        },
                      ),
                      const SizedBox(width: 4),
                      _buildScopeChip(
                        label: 'Per Desa',
                        isSelected: scope.isKecamatanAggregate && !_seDesaMode,
                        accent: accent,
                        isDark: isDark,
                        onTap: () {
                          setState(() {
                            _selectedDesaCode = null;
                            _drillDownDusun = null;
                            _seDesaMode = false;
                            _compareYear = null;
                            _selectedItemLabel = null;
                          });
                          _savePreferences();
                          _replayAnimation();
                        },
                      ),
                      Container(
                        height: 16,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                      ),
                      for (final kel in scope.desaCodes)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _buildScopeChip(
                            label: DhkpGrafikAnalytics.formatDesaLabel(kel),
                            isSelected: scope.effectiveDesaCode == kel,
                            accent: accent,
                            isDark: isDark,
                            onTap: () {
                              setState(() {
                                if (_selectedDesaCode == kel) {
                                  _selectedDesaCode = null;
                                  _drillDownDusun = null;
                                  _seDesaMode = false;
                                } else {
                                  _selectedDesaCode = kel;
                                  _drillDownDusun = null;
                                  _seDesaMode = false;
                                }
                                _selectedItemLabel = null;
                              });
                              _savePreferences();
                              _replayAnimation();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (scope.effectiveDesaCode != null) ...[
                  const SizedBox(height: 6),
                  _buildDesaSubScopeRow(
                    scope,
                    accent,
                    isDark,
                    prefixLabel: 'Dalam Desa:',
                  ),
                ],
              ],
            )
          : _buildDesaSubScopeRow(scope, accent, isDark),
    );
  }

  Widget _buildScopeChip({
    required String label,
    required bool isSelected,
    required MaterialColor accent,
    required bool isDark,
    required VoidCallback onTap,
    IconData? leadingIcon,
    String? badgeSuffix,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: isDark ? 0.3 : 0.15)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent.shade600 : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: 13,
                color: isSelected
                    ? (isDark ? accent.shade200 : accent.shade800)
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? accent.shade200 : accent.shade800)
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
            ),
            if (badgeSuffix != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.35 : 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeSuffix,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isDark ? accent.shade100 : accent.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 4. CONTROL TOOLBAR (PEMILIH DIAGRAM, URUTKAN, BUKA/LIPAT SEMUA)
  // =========================================================================
  Widget _buildControlToolbar(
    bool hasMultiDusun,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final accent = _themeAccent;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Pemilih Jenis Diagram (Batang / Mendatar / Lingkaran / Semua)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.surfaceContainerHigh
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final style in ChartStyle.values) ...[
                  () {
                    final isTrendLineChip =
                        _activeTab == DhkpGrafikTab.trenBulanan &&
                        style == ChartStyle.batang;
                    final chipIcon = isTrendLineChip
                        ? Icons.show_chart_rounded
                        : style.icon;
                    final chipLabel = isTrendLineChip
                        ? 'Garis Tren'
                        : style.label;
                    return InkWell(
                      onTap: () => _switchStyle(style),
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: AppMotion.resolve(
                          context,
                          AppMotion.component,
                        ),
                        curve: AppMotion.smoothCurve,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedStyle == style
                              ? (isDark ? colorScheme.surface : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedStyle == style
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              chipIcon,
                              size: 14,
                              color: _selectedStyle == style
                                  ? accent.shade700
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              chipLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _selectedStyle == style
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: _selectedStyle == style
                                    ? accent.shade700
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
                ],
              ],
            ),
          ),
        ),

        // Kanan: Pengurutan & Tombol Lipat/Buka Semua (Wrap aman di 360dp mobile)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Mode Pas Layar / Bisa Digeser (Khusus Diagram Batang)
            if (_activeTab != DhkpGrafikTab.trenBulanan &&
                (_selectedStyle == ChartStyle.batang ||
                    _selectedStyle == ChartStyle.semua))
              Tooltip(
                message: _fitColumnBars
                    ? 'Mode Pas Layar: Semua blok dirapatkan agar muat dalam satu layar tanpa digeser. Ketuk untuk beralih ke Mode Geser.'
                    : 'Mode Geser: Data dapat digeser secara horizontal dengan mouse atau sentuhan. Ketuk untuk beralih ke Mode Pas Layar.',
                child: InkWell(
                  onTap: () {
                    setState(() => _fitColumnBars = !_fitColumnBars);
                    _savePreferences();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainerHigh
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _fitColumnBars
                            ? accent.shade600
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _fitColumnBars
                              ? Icons.fit_screen_rounded
                              : Icons.open_with_rounded,
                          size: 15,
                          color: _fitColumnBars
                              ? accent.shade700
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fitColumnBars ? 'Pas Layar' : 'Bisa Digeser',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _fitColumnBars
                                ? accent.shade700
                                : (isDark
                                      ? Colors.white
                                      : Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_activeTab != DhkpGrafikTab.trenBulanan)
              PopupMenuButton<GrafikSortMode>(
                tooltip: 'Urutkan Grafik & Tabel',
                initialValue: _sortMode,
                onSelected: (mode) {
                  setState(() => _sortMode = mode);
                  _savePreferences();
                },
                itemBuilder: (context) => [
                  for (final m in GrafikSortMode.values)
                    PopupMenuItem(
                      value: m,
                      child: Row(
                        children: [
                          Icon(
                            m.icon,
                            size: 16,
                            color: _sortMode == m ? accent.shade700 : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            m.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _sortMode == m
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceContainerHigh
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_vert_rounded,
                        size: 15,
                        color: accent.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _sortMode.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down_rounded, size: 16),
                    ],
                  ),
                ),
              ),

            // Tombol Lipat Semua / Buka Semua
            InkWell(
              onTap: _toggleExpandCollapseAll,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHigh
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _allCollapsed
                          ? Icons.unfold_more_rounded
                          : Icons.unfold_less_rounded,
                      size: 15,
                      color: accent.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _allCollapsed ? 'Buka Semua' : 'Lipat Semua',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================================
  // 5. PANEL DETAIL SAAT ITEM GRAFIK DIKLIK (INTERACTIVE SELECTION)
  // =========================================================================
  Widget _buildSelectedDetailBanner(
    List<BlokRecord> records,
    bool hasMultiDusun,
    bool isDark,
  ) {
    final groups = _activeTab == DhkpGrafikTab.trenBulanan
        ? DhkpGrafikAnalytics.buildMonthGroups(records, tahun: _selectedTahun)
        : _groupData(records, hasMultiDusun: hasMultiDusun, applySort: false);

    final match = groups
        .where((g) => g.label == _selectedItemLabel)
        .firstOrNull;
    if (match == null) return const SizedBox.shrink();

    final accent = _themeAccent;
    final isDusunItem = match.label.startsWith('Dusun ');
    final dusunNum = isDusunItem
        ? int.tryParse(match.label.replaceFirst('Dusun ', ''))
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [accent.shade900.withValues(alpha: 0.5), Colors.grey.shade900]
              : [accent.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.shade400, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  match.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Capaian: ${match.lunasPct.toStringAsFixed(1)}% (${match.lunasNop} dari ${match.totalNop} objek pajak)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : accent.shade900,
                  ),
                ),
              ),
              if (hasMultiDusun && dusunNum != null && _drillDownDusun == null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _drillDownDusun = dusunNum;
                      _seDesaMode = false;
                      _selectedItemLabel = null;
                    });
                    _savePreferences();
                    _replayAnimation();
                  },
                  icon: Icon(
                    Icons.zoom_in_rounded,
                    size: 15,
                    color: accent.shade700,
                  ),
                  label: Text(
                    'Lihat Blok',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accent.shade700,
                    ),
                  ),
                ),
              if (match.label.startsWith('Desa ') && _selectedDesaCode == null)
                () {
                  final kelMatch =
                      DhkpGrafikAnalytics.resolveDesaCodesInKecamatan(
                            records,
                            '',
                          )
                          .where(
                            (k) =>
                                DhkpGrafikAnalytics.formatDesaLabel(k) ==
                                match.label,
                          )
                          .firstOrNull;
                  if (kelMatch == null) return const SizedBox.shrink();
                  return TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedDesaCode = kelMatch;
                        _drillDownDusun = null;
                        _seDesaMode = false;
                        _selectedItemLabel = null;
                      });
                      _savePreferences();
                      _replayAnimation();
                    },
                    icon: Icon(
                      Icons.zoom_in_rounded,
                      size: 15,
                      color: accent.shade700,
                    ),
                    label: Text(
                      'Lihat Desa',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accent.shade700,
                      ),
                    ),
                  );
                }(),
              if (_activeTab == DhkpGrafikTab.trenBulanan) ...[
                () {
                  final mIdx =
                      DhkpGrafikAnalytics.monthNames.indexOf(match.label) + 1;
                  if (mIdx <= 0) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          onPressed: () {
                            showDhkpRincianBulananDialog(
                              context,
                              allRecords: records,
                              monthIndex: mIdx,
                              tahun: _selectedTahun,
                              isDark: isDark,
                            );
                          },
                          icon: const Icon(
                            Icons.receipt_long_rounded,
                            size: 15,
                          ),
                          label: const Text(
                            'Rincian',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                          ),
                          onPressed: () =>
                              _printSingleSelectedMonth(records, mIdx),
                          icon: const Icon(Icons.print_outlined, size: 15),
                          label: const Text(
                            'Cetak Bulan Ini',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }(),
              ],
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _selectedItemLabel = null),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Tutup rincian',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _buildMiniDetailStat(
                'Sudah Bayar',
                '${formatRupiah(match.lunasNominal)} (${match.lunasNop} objek)',
                _themeAccent,
                isDark,
              ),
              if (_activeTab != DhkpGrafikTab.trenBulanan) ...[
                _buildMiniDetailStat(
                  'Belum Bayar',
                  '${formatRupiah(match.belumBayarNominal)} (${match.belumBayarNop} objek)',
                  _themeTertiaryAccent,
                  isDark,
                ),
                _buildMiniDetailStat(
                  'Total Ketetapan',
                  '${formatRupiah(match.totalNominal)} (${match.totalNop} objek)',
                  _themeSecondaryAccent,
                  isDark,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDetailStat(
    String label,
    String val,
    MaterialColor color,
    bool isDark,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color.shade600,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
        Text(
          val,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.grey.shade900,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // KOMPONEN KARTU LIPAT DENGAN TOMBOL UNDUH, BAGIKAN, CETAK DI SAMPING PANAH
  // =========================================================================
  Widget _buildCollapsibleSectionCard({
    required String sectionKey,
    required IconData icon,
    required String title,
    required String subtitle,
    required String badgeText,
    required MaterialColor accentColor,
    required bool isDark,
    required List<DhkpGroupInfo> groups,
    required Widget child,
  }) {
    final isCollapsed = _collapsedSections.contains(sectionKey);
    final boundaryKey = _getBoundaryKey(sectionKey);

    return Card(
      elevation: isCollapsed ? 0.5 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCollapsed
              ? (isDark ? Colors.white12 : Colors.grey.shade300)
              : accentColor.withValues(alpha: isDark ? 0.35 : 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleSection(sectionKey),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isCollapsed
                    ? Colors.transparent
                    : accentColor.withValues(alpha: isDark ? 0.08 : 0.04),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(
                        alpha: isDark ? 0.22 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 17, color: accentColor.shade700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isCollapsed
                              ? 'Terlipat • $badgeText'
                              : '$subtitle • $badgeText',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (sectionKey == 'batang' &&
                      _activeTab != DhkpGrafikTab.trenBulanan) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: const EdgeInsets.all(4),
                      tooltip: _fitColumnBars
                          ? 'Beralih ke Mode Geser (Lebarkan batang)'
                          : 'Beralih ke Mode Pas Layar (Rapatkan semua blok)',
                      icon: Icon(
                        _fitColumnBars
                            ? Icons.fit_screen_rounded
                            : Icons.open_with_rounded,
                        size: 18,
                        color: _fitColumnBars
                            ? accentColor.shade700
                            : (isDark
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade700),
                      ),
                      onPressed: () {
                        setState(() => _fitColumnBars = !_fitColumnBars);
                        _savePreferences();
                      },
                    ),
                  ],
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'Unduh Grafik',
                    icon: Icon(
                      Icons.download_outlined,
                      size: 18,
                      color: isDark
                          ? Colors.grey.shade300
                          : accentColor.shade700,
                    ),
                    onPressed: () => _handleDownloadSection(
                      sectionKey: sectionKey,
                      title: title,
                      subtitle: subtitle,
                      groups: groups,
                    ),
                  ),
                  if (Platform.isAndroid)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: const EdgeInsets.all(4),
                      tooltip: 'Bagikan Grafik (Gambar / PDF)',
                      icon: Icon(
                        Icons.share_outlined,
                        size: 17,
                        color: isDark
                            ? Colors.grey.shade300
                            : accentColor.shade700,
                      ),
                      onPressed: () => _handleShareSection(
                        sectionKey: sectionKey,
                        title: title,
                        subtitle: subtitle,
                        groups: groups,
                      ),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'Cetak Grafik',
                    icon: Icon(
                      Icons.print_outlined,
                      size: 18,
                      color: isDark
                          ? Colors.grey.shade300
                          : accentColor.shade700,
                    ),
                    onPressed: () => _handlePrintSection(
                      sectionKey: sectionKey,
                      title: title,
                      subtitle: subtitle,
                      groups: groups,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: isCollapsed ? 0.0 : 0.5,
                    duration: AppMotion.resolve(context, AppMotion.dialog),
                    curve: AppMotion.smoothCurve,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: accentColor.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Builder(
            builder: (ctx) {
              final expandedSection = RepaintBoundary(
                key: boundaryKey,
                child: Container(
                  color: isDark ? Theme.of(ctx).cardColor : Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: child,
                ),
              );
              if (AppMotion.isReducedMotion(ctx)) {
                return isCollapsed
                    ? const SizedBox(width: double.infinity, height: 0)
                    : expandedSection;
              }
              return AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: expandedSection,
                crossFadeState: isCollapsed
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: AppMotion.page,
                sizeCurve: AppMotion.smoothCurve,
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB: JUMLAH PENDAPATAN
  // =========================================================================
  Widget _buildPendapatanSection(
    List<BlokRecord> records,
    bool hasMultiDusun,
    int totalPendapatanMasuk,
    int totalNominalTarget,
    bool isDark,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.lunasNominal.toDouble(),
    );
    if (groups.isEmpty) return buildDhkpEmptyCard();

    final showBatang =
        _selectedStyle == ChartStyle.batang ||
        _selectedStyle == ChartStyle.semua;
    final showBar =
        _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie =
        _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBatang) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'batang',
            icon: Icons.bar_chart_rounded,
            title: 'Diagram Batang: Pendapatan Masuk (Rp)',
            subtitle: 'Ketuk batang untuk melihat rincian wilayah',
            badgeText: '${groups.length} Wilayah',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNominal.toDouble())
                  .fold(0.0, math.max),
              topLabelExtractor: (g) =>
                  'Rp ${formatShortRupiah(g.lunasNominal)}',
              animatedTopLabelBuilder: (g, t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, g.lunasNominal.toDouble(), t).round())}',
              subLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(0)}%',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade800,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
              fitScreen: _fitColumnBars,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Peringkat Pendapatan (Rp)',
            subtitle: 'Perbandingan uang masuk antar wilayah',
            badgeText: _sortMode.label,
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNominal.toDouble())
                  .fold(0.0, math.max),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              animatedLabelRightBuilder: (g, t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, g.lunasNominal.toDouble(), t).round())}',
              subRight: (g) => '${g.lunasPct.toStringAsFixed(1)}% dari target',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              sortMode: _sortMode,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showPie) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'pie',
            icon: Icons.pie_chart_outline_rounded,
            title: 'Diagram Lingkaran: Porsi Pendapatan Masuk',
            subtitle: 'Perbandingan sumbangan penerimaan tiap wilayah',
            badgeText: 'Total Rp ${formatShortRupiah(totalPendapatanMasuk)}',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                groups,
                (g) => g.lunasNominal.toDouble(),
                totalPendapatanMasuk.toDouble(),
                palette: _themeSlicePalette,
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalPendapatanMasuk)}',
              animatedCenterLabelBuilder: (t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, totalPendapatanMasuk.toDouble(), t).round())}',
              centerSub: 'TERKUMPUL',
              centerColor: _themeAccent,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildCollapsibleSectionCard(
          sectionKey: 'tabel',
          icon: Icons.table_chart_rounded,
          title: 'Tabel Rincian Pendapatan per Wilayah',
          subtitle: 'Daftar angka target dan uang yang sudah masuk',
          badgeText: '${groups.length} Baris',
          accentColor: _themeAccent,
          isDark: isDark,
          groups: groups,
          child: buildDhkpDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Target (Rp)',
            col3: 'Pendapatan (Rp)',
            col4: '% Capaian',
            col2Val: (g) => formatShortRupiah(g.totalNominal),
            col3Val: (g) => formatShortRupiah(g.lunasNominal),
            col4Val: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
            isDark: isDark,
            selectedItemLabel: _selectedItemLabel,
            accentColor: _themeAccent,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: JUMLAH PERSENTASE (DEFAULT)
  // =========================================================================
  Widget _buildPersentaseSection(
    List<BlokRecord> records,
    bool hasMultiDusun,
    double overallPct,
    bool isDark,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.lunasPct,
    );
    if (groups.isEmpty) return buildDhkpEmptyCard();

    final showBatang =
        _selectedStyle == ChartStyle.batang ||
        _selectedStyle == ChartStyle.semua;
    final showBar =
        _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie =
        _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBatang) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'batang',
            icon: Icons.bar_chart_rounded,
            title: 'Diagram Batang: Capaian Persentase (%)',
            subtitle: 'Skala capaian 0% sampai 100% per wilayah',
            badgeText: 'Rata-rata ${overallPct.toStringAsFixed(1)}%',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasPct,
              maxVal: 100.0,
              topLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
              animatedTopLabelBuilder: (g, t) =>
                  '${unityLerp(0.0, g.lunasPct, t).toStringAsFixed(1)}%',
              subLabelExtractor: (g) => '${g.lunasNop}/${g.totalNop}',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
              fitScreen: _fitColumnBars,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Capaian Persentase Wilayah',
            subtitle: 'Tingkat pencapaian pembayaran terhadap target 100%',
            badgeText: _sortMode.label,
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasPct,
              maxVal: 100.0,
              labelRight: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
              animatedLabelRightBuilder: (g, t) =>
                  '${unityLerp(0.0, g.lunasPct, t).toStringAsFixed(1)}%',
              subRight: (g) => '${g.lunasNop}/${g.totalNop} objek',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              sortMode: _sortMode,
              onSelectLabel: _onSelectLabel,
              useSemanticPercentageColor: true,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showPie) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'pie',
            icon: Icons.donut_large_rounded,
            title: 'Diagram Lingkaran: Sudah Tercapai vs Sisa Target',
            subtitle: 'Perbandingan persentase lunas dan sisa yang belum masuk',
            badgeText: '${overallPct.toStringAsFixed(1)}% Lunas',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpDonutTwoSlice(
              achievedPct: overallPct,
              achievedLabel: 'Sudah Lunas',
              remainingLabel: 'Sisa Target',
              achievedColor: _themeAccent.shade600,
              remainingColor: Colors.grey.shade400,
              centerLabel: '${overallPct.toStringAsFixed(1)}%',
              animatedCenterLabelBuilder: (animatedPct) =>
                  '${animatedPct.toStringAsFixed(1)}%',
              centerSub: 'TERCAPAI',
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildCollapsibleSectionCard(
          sectionKey: 'tabel',
          icon: Icons.table_chart_rounded,
          title: 'Tabel Rincian Persentase per Wilayah',
          subtitle: 'Perbandingan jumlah objek lunas dan persentase capaian',
          badgeText: '${groups.length} Baris',
          accentColor: _themeAccent,
          isDark: isDark,
          groups: groups,
          child: buildDhkpDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Total Objek',
            col3: 'Objek Lunas',
            col4: '% Capaian',
            col2Val: (g) => '${g.totalNop}',
            col3Val: (g) => '${g.lunasNop}',
            col4Val: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
            isDark: isDark,
            selectedItemLabel: _selectedItemLabel,
            accentColor: _themeAccent,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: BELUM BAYAR
  // =========================================================================
  Widget _buildBelumBayarSection(
    List<BlokRecord> records,
    bool hasMultiDusun,
    int totalBelumBayarNominal,
    int totalNominalTarget,
    bool isDark,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.belumBayarNominal.toDouble(),
    );
    if (groups.isEmpty) return buildDhkpEmptyCard();

    final showBatang =
        _selectedStyle == ChartStyle.batang ||
        _selectedStyle == ChartStyle.semua;
    final showBar =
        _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie =
        _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBatang) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'batang',
            icon: Icons.bar_chart_rounded,
            title: 'Diagram Batang: Tagihan Belum Bayar (Rp)',
            subtitle: 'Jumlah tagihan yang masih perlu ditagih per wilayah',
            badgeText: '${groups.length} Wilayah',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpColumnBars(
              groups: groups,
              valueExtractor: (g) => g.belumBayarNominal.toDouble(),
              maxVal: groups
                  .map((g) => g.belumBayarNominal.toDouble())
                  .fold(0.0, math.max),
              topLabelExtractor: (g) =>
                  'Rp ${formatShortRupiah(g.belumBayarNominal)}',
              animatedTopLabelBuilder: (g, t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, g.belumBayarNominal.toDouble(), t).round())}',
              subLabelExtractor: (g) => '${g.belumBayarNop} objek',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
              fitScreen: _fitColumnBars,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Urutan Belum Bayar per Wilayah',
            subtitle: 'Wilayah dengan sisa tagihan belum lunas terbesar',
            badgeText: _sortMode.label,
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.belumBayarNominal.toDouble(),
              maxVal: groups
                  .map((g) => g.belumBayarNominal.toDouble())
                  .fold(0.0, math.max),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.belumBayarNominal)}',
              animatedLabelRightBuilder: (g, t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, g.belumBayarNominal.toDouble(), t).round())}',
              subRight: (g) => '${g.belumBayarNop} objek belum lunas',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade600,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              sortMode: _sortMode,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showPie) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'pie',
            icon: Icons.pie_chart_outline_rounded,
            title: 'Diagram Lingkaran: Sebaran Belum Bayar',
            subtitle: 'Perbandingan sisa tagihan antar wilayah',
            badgeText: 'Total Rp ${formatShortRupiah(totalBelumBayarNominal)}',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                groups,
                (g) => g.belumBayarNominal.toDouble(),
                totalBelumBayarNominal.toDouble(),
                palette: _themeSlicePalette,
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalBelumBayarNominal)}',
              animatedCenterLabelBuilder: (t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, totalBelumBayarNominal.toDouble(), t).round())}',
              centerSub: 'BELUM BAYAR',
              centerColor: _themeAccent,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildCollapsibleSectionCard(
          sectionKey: 'tabel',
          icon: Icons.table_chart_rounded,
          title: 'Tabel Rincian Belum Bayar per Wilayah',
          subtitle: 'Daftar jumlah objek dan nilai rupiah yang belum lunas',
          badgeText: '${groups.length} Baris',
          accentColor: _themeAccent,
          isDark: isDark,
          groups: groups,
          child: buildDhkpDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Objek Belum',
            col3: 'Belum Bayar (Rp)',
            col4: '% Porsi',
            col2Val: (g) => '${g.belumBayarNop}',
            col3Val: (g) => formatShortRupiah(g.belumBayarNominal),
            col4Val: (g) => totalBelumBayarNominal > 0
                ? '${(g.belumBayarNominal / totalBelumBayarNominal * 100).toStringAsFixed(1)}%'
                : '0%',
            isDark: isDark,
            selectedItemLabel: _selectedItemLabel,
            accentColor: _themeAccent,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: SUDAH BAYAR
  // =========================================================================
  Widget _buildSudahBayarSection(
    List<BlokRecord> records,
    bool hasMultiDusun,
    int totalSudahBayarCount,
    int totalSudahBayarNominal,
    bool isDark,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.lunasNop.toDouble(),
    );
    if (groups.isEmpty) return buildDhkpEmptyCard();

    final showBatang =
        _selectedStyle == ChartStyle.batang ||
        _selectedStyle == ChartStyle.semua;
    final showBar =
        _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie =
        _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBatang) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'batang',
            icon: Icons.bar_chart_rounded,
            title: 'Diagram Batang: Jumlah Objek Sudah Bayar',
            subtitle: 'Banyaknya objek pajak yang sudah lunas per wilayah',
            badgeText: 'Total $totalSudahBayarCount Objek',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNop.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNop.toDouble())
                  .fold(0.0, math.max),
              topLabelExtractor: (g) => '${g.lunasNop} objek',
              animatedTopLabelBuilder: (g, t) =>
                  '${unityLerp(0.0, g.lunasNop.toDouble(), t).round()} objek',
              subLabelExtractor: (g) =>
                  'Rp ${formatShortRupiah(g.lunasNominal)}',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade800,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
              fitScreen: _fitColumnBars,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Urutan Objek Lunas',
            subtitle:
                'Urutan wilayah berdasarkan jumlah warga yang sudah bayar',
            badgeText: _sortMode.label,
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNop.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNop.toDouble())
                  .fold(0.0, math.max),
              labelRight: (g) => '${g.lunasNop} objek',
              animatedLabelRightBuilder: (g, t) =>
                  '${unityLerp(0.0, g.lunasNop.toDouble(), t).round()} objek',
              subRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              sortMode: _sortMode,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showPie) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'pie',
            icon: Icons.pie_chart_outline_rounded,
            title: 'Diagram Lingkaran: Sebaran Objek Lunas',
            subtitle: 'Perbandingan jumlah wajib pajak yang telah membayar',
            badgeText: '$totalSudahBayarCount Objek',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: groups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                groups,
                (g) => g.lunasNop.toDouble(),
                totalSudahBayarCount.toDouble(),
                palette: _themeSlicePalette,
              ),
              centerLabel: '$totalSudahBayarCount',
              animatedCenterLabelBuilder: (t) =>
                  '${unityLerp(0.0, totalSudahBayarCount.toDouble(), t).round()}',
              centerSub: 'OBJEK LUNAS',
              centerColor: _themeAccent,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildCollapsibleSectionCard(
          sectionKey: 'tabel',
          icon: Icons.table_chart_rounded,
          title: 'Tabel Rincian Sudah Bayar per Wilayah',
          subtitle: 'Rekapitulasi jumlah objek lunas dan uang terkumpul',
          badgeText: '${groups.length} Baris',
          accentColor: _themeAccent,
          isDark: isDark,
          groups: groups,
          child: buildDhkpDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Total Objek',
            col3: 'Objek Lunas',
            col4: 'Uang Masuk',
            col2Val: (g) => '${g.totalNop}',
            col3Val: (g) => '${g.lunasNop}',
            col4Val: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
            isDark: isDark,
            selectedItemLabel: _selectedItemLabel,
            accentColor: _themeAccent,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: TREN PEMBAYARAN TIAP BULAN (JAN - DES)
  // =========================================================================
  Widget _buildTrenBulananSection(_DhkpResolvedContext scope, bool isDark) {
    final records = scope.murniRecords;
    final monthGroups = DhkpGrafikAnalytics.buildMonthGroups(
      records,
      tahun: _selectedTahun,
    );
    final trendSeries = _buildTrendSeriesForScope(scope, isDark);
    final monthlyNominal = monthGroups.map((g) => g.lunasNominal).toList();
    final totalDatedNominal = monthlyNominal.fold<int>(0, (sum, v) => sum + v);
    final maxMonthVal = monthlyNominal.fold<int>(0, math.max);

    var maxTrendVal = 0;
    for (final s in trendSeries) {
      for (final v in s.monthlyNominal) {
        if (v > maxTrendVal) maxTrendVal = v;
      }
    }
    if (maxTrendVal == 0) maxTrendVal = maxMonthVal;

    final canCompare = _canCompareYearsForScope(scope);
    final activeCompareYear = canCompare
        ? _resolveValidCompareYear(scope.availableYears)
        : null;
    final isYearCompareActive = activeCompareYear != null;
    final distinctBlokCount = records.map((r) => r.blok).toSet().length;
    final showDesaPicker =
        !isYearCompareActive &&
        scope.isKecamatanAggregate &&
        !_seDesaMode &&
        scope.desaCodes.length > _maxCustomDesas;

    final (cardTitle, cardSubtitle, cardBadge) = () {
      if (isYearCompareActive) {
        final entityName = _drillDownDusun != null
            ? 'Total Dusun $_drillDownDusun'
            : (scope.isKecamatanAggregate
                  ? _formatKecamatanLabel(scope.primaryKecamatanCode)
                  : (scope.effectiveDesaCode != null
                        ? DhkpGrafikAnalytics.formatDesaLabel(
                            scope.effectiveDesaCode!,
                          )
                        : (scope.isKedusunanScope
                              ? 'Se-Kedusunan'
                              : 'Se-Desa')));
        final primaryTotal = trendSeries.isNotEmpty
            ? trendSeries.first.totalNominal
            : 0;
        final compareTotal = trendSeries.length > 1
            ? trendSeries[1].totalNominal
            : 0;
        final deltaSuffix = compareTotal > 0
            ? () {
                final diffPct =
                    ((primaryTotal - compareTotal) / compareTotal) * 100.0;
                final sign = diffPct >= 0 ? '+' : '';
                return ' • Selisih: $sign${diffPct.toStringAsFixed(1)}%';
              }()
            : '';
        return (
          'Tren $_selectedTahun vs $activeCompareYear ($entityName)',
          'Garis solid: $_selectedTahun • Garis putus-putus: $activeCompareYear$deltaSuffix',
          '$_selectedTahun vs $activeCompareYear',
        );
      }
      if (scope.isKecamatanAggregate && !_seDesaMode) {
        return (
          'Grafik Tren Pembayaran Per Desa',
          scope.desaCodes.length > _maxCustomDesas
              ? 'Menampilkan maks. $_maxCustomDesas desa dalam ${_formatKecamatanLabel(scope.primaryKecamatanCode)}'
              : 'Perbandingan penerimaan bulanan antar desa dalam 1 kecamatan',
          '${trendSeries.length} Desa',
        );
      }
      if (_drillDownDusun != null) {
        return (
          'Grafik Tren Pembayaran Dusun $_drillDownDusun (Per Blok)',
          'Pergerakan bulanan tiap blok di Dusun $_drillDownDusun — ketuk legend untuk fokus',
          '${trendSeries.length} Blok',
        );
      }
      if (!_seDesaMode && scope.hasMultiDusun) {
        return (
          'Grafik Garis Tren per Dusun (Kadus)',
          'Perbandingan tren pembayaran Dusun 1–${scope.uniqueDusuns.length} (Jan - Des $_selectedTahun)',
          '${trendSeries.length} Dusun',
        );
      }
      if (!_seDesaMode && !scope.hasMultiDusun && distinctBlokCount > 1) {
        if (scope.uniqueDusuns.isNotEmpty) {
          final activeDusun = scope.uniqueDusuns.first;
          return (
            'Grafik Tren Pembayaran Dusun $activeDusun (Per Blok)',
            'Pergerakan bulanan tiap blok di Dusun $activeDusun — ketuk legend untuk fokus',
            '${trendSeries.length} Blok',
          );
        }
        return (
          'Grafik Garis Tren per Blok',
          'Perbandingan tren penerimaan tiap blok (Jan - Des $_selectedTahun)',
          '${trendSeries.length} Blok',
        );
      }
      return (
        'Grafik Garis Tren Pembayaran Bulanan',
        'Pergerakan penerimaan kas dari awal hingga akhir tahun (Jan - Des)',
        'Jan - Des',
      );
    }();

    final showBatang =
        _selectedStyle == ChartStyle.batang ||
        _selectedStyle == ChartStyle.semua;
    final showBar =
        _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie =
        _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Grafik Garis Tren Bulanan Halus (Jan - Des) tanpa batang
        if (showBatang) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'batang',
            icon: Icons.show_chart_rounded,
            title: cardTitle,
            subtitle: cardSubtitle,
            badgeText: cardBadge,
            accentColor: _themeAccent,
            isDark: isDark,
            groups: monthGroups,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDesaPicker) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Filter ${scope.desaCodes.length} Desa:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                        ),
                        _buildScopeChip(
                          label: 'Top $_maxCustomDesas Desa',
                          isSelected: _customCompareDesas.isEmpty,
                          accent: _themeAccent,
                          isDark: isDark,
                          onTap: () {
                            setState(() => _customCompareDesas.clear());
                          },
                        ),
                        _buildScopeChip(
                          label: _customCompareDesas.isEmpty
                              ? 'Pilih Desa (Maks. $_maxCustomDesas)'
                              : 'Desa Pilihan (${_customCompareDesas.length}/$_maxCustomDesas)',
                          isSelected: _customCompareDesas.isNotEmpty,
                          accent: _themeAccent,
                          isDark: isDark,
                          leadingIcon: Icons.checklist_rounded,
                          onTap: () => _openSelectDesaDialog(
                            scope.allScopedRecordsAcrossYears,
                            scope.desaCodes,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                renderDhkpComboBarLineTrend(
                  monthGroups: monthGroups,
                  maxMonthVal: maxTrendVal,
                  animationValue: _animation.value,
                  isDark: isDark,
                  selectedItemLabel: _selectedItemLabel,
                  onSelectLabel: _onSelectLabel,
                  tahun: _selectedTahun,
                  forceCompleteAnimation: _isCapturingExport,
                  seriesList: trendSeries,
                  footerTrailing: _buildBottomComparisonControl(
                    scope: scope,
                    isDark: isDark,
                    canCompare: canCompare,
                    activeCompareYear: activeCompareYear,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Rincian Bulanan (Jan - Des)',
            subtitle: 'Daftar penerimaan kas dari awal hingga akhir tahun',
            badgeText: '12 Bulan',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: monthGroups,
            child: renderDhkpHorizontalBars(
              groups: monthGroups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: maxMonthVal.toDouble(),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              animatedLabelRightBuilder: (g, t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, g.lunasNominal.toDouble(), t).round())}',
              subRight: (g) =>
                  '${g.lunasNop} objek (${g.lunasPct.toStringAsFixed(1)}%)',
              color1: _themeAccent.shade400,
              color2: _themeAccent.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              sortMode: _sortMode,
              onSelectLabel: _onSelectLabel,
              showRankNumber: false,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showPie) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'pie',
            icon: Icons.pie_chart_outline_rounded,
            title: 'Diagram Lingkaran: Porsi Penerimaan per Bulan',
            subtitle: 'Kontribusi tiap bulan terhadap total penerimaan tahunan',
            badgeText: 'Rp ${formatShortRupiah(totalDatedNominal)}',
            accentColor: _themeAccent,
            isDark: isDark,
            groups: monthGroups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                monthGroups.where((g) => g.lunasNominal > 0).toList(),
                (g) => g.lunasNominal.toDouble(),
                totalDatedNominal.toDouble(),
                palette: _themeSlicePalette,
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalDatedNominal)}',
              animatedCenterLabelBuilder: (t) =>
                  'Rp ${formatShortRupiah(unityLerp(0.0, totalDatedNominal.toDouble(), t).round())}',
              centerSub: 'TOTAL BULANAN',
              centerColor: _themeAccent,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildCollapsibleSectionCard(
          sectionKey: 'tabel',
          icon: Icons.table_chart_rounded,
          title: 'Tabel Rincian Penerimaan Bulanan (Jan - Des)',
          subtitle: 'Rekapitulasi jumlah pembayaran dan nilai rupiah per bulan',
          badgeText: '12 Bulan',
          accentColor: _themeAccent,
          isDark: isDark,
          groups: monthGroups,
          child: buildDhkpDetailTableContent(
            groups: monthGroups,
            col1: 'Bulan',
            col2: 'Objek Lunas',
            col3: 'Nominal (Rp)',
            col4: '% Porsi',
            col2Val: (g) => '${g.lunasNop}',
            col3Val: (g) => formatShortRupiah(g.lunasNominal),
            col4Val: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
            isDark: isDark,
            selectedItemLabel: _selectedItemLabel,
            accentColor: _themeAccent,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomComparisonControl({
    required _DhkpResolvedContext scope,
    required bool isDark,
    required bool canCompare,
    required String? activeCompareYear,
  }) {
    final years = scope.availableYears;
    final candidateYears = years.where((y) => y != _selectedTahun).toList();
    final suggestedYear = _suggestDefaultCompareYear(years);
    final accent = _themeAccent;

    if (candidateYears.isEmpty || suggestedYear == null) {
      return Semantics(
        container: true,
        button: true,
        label: 'Bandingkan Tahun (perlu minimal 2 tahun data)',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _applyCompareYear(_selectedTahun, scope: scope),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.compare_arrows_rounded,
                    size: 14,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Bandingkan',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final palette = DhkpGrafikAnalytics.trendSeriesPalette(isDark: isDark);
    final compareColor = palette.length > 1
        ? palette[1]
        : (isDark ? _themeAccent.shade200 : _themeAccent.shade700);

    List<PopupMenuEntry<String>> buildMenuItems({required bool includeClear}) {
      return [
        PopupMenuItem<String>(
          enabled: false,
          height: 30,
          child: Text(
            !canCompare
                ? 'Bandingkan di ${scope.isKecamatanAggregate ? "Se-Kecamatan" : (scope.isKedusunanScope ? "Se-Kedusunan" : "Se-Desa")} vs $_selectedTahun'
                : 'Bandingkan $_selectedTahun dengan:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? accent.shade200 : accent.shade700,
            ),
          ),
        ),
        const PopupMenuDivider(height: 6),
        for (final y in candidateYears)
          PopupMenuItem<String>(
            value: y,
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  activeCompareYear == y
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: activeCompareYear == y
                      ? compareColor
                      : Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'vs $y',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: activeCompareYear == y
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (y == suggestedYear) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.25 : 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'Tahun lalu',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? accent.shade100 : accent.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (includeClear) ...[
          const PopupMenuDivider(height: 6),
          PopupMenuItem<String>(
            value: '__clear__',
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Hentikan perbandingan',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ];
    }

    if (activeCompareYear == null) {
      return Semantics(
        container: true,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.42 : 0.28),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _applyCompareYear(suggestedYear, scope: scope),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 10,
                      right: 8,
                      top: 6,
                      bottom: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.compare_arrows_rounded,
                          size: 14,
                          color: isDark ? accent.shade200 : accent.shade700,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Bandingkan',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? accent.shade100 : accent.shade800,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: isDark ? 0.28 : 0.14,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'vs $suggestedYear',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? accent.shade100 : accent.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 20,
                  color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
                ),
                PopupMenuButton<String>(
                  tooltip: '',
                  padding: EdgeInsets.zero,
                  position: PopupMenuPosition.over,
                  constraints: const BoxConstraints(
                    minWidth: 200,
                    maxWidth: 320,
                  ),
                  onSelected: (value) => _applyCompareYear(value, scope: scope),
                  itemBuilder: (_) => buildMenuItems(includeClear: false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: isDark ? accent.shade100 : accent.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: compareColor.withValues(alpha: isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: compareColor.withValues(alpha: isDark ? 0.55 : 0.45),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                tooltip: '',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.over,
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
                onSelected: (value) {
                  if (value == '__clear__') {
                    _applyCompareYear(null, scope: scope);
                  } else {
                    _applyCompareYear(value, scope: scope);
                  }
                },
                itemBuilder: (_) => buildMenuItems(includeClear: true),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 6,
                    top: 6,
                    bottom: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 15,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (int i = 0; i < 3; i++)
                              Container(
                                width: 3.6,
                                height: 2.2,
                                decoration: BoxDecoration(
                                  color: compareColor,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'vs $activeCompareYear',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.grey.shade200
                            : Colors.grey.shade800,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: compareColor.withValues(alpha: isDark ? 0.35 : 0.30),
              ),
              Tooltip(
                message: 'Hentikan perbandingan tahun',
                child: InkWell(
                  onTap: () => _applyCompareYear(null, scope: scope),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 6,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: isDark
                          ? Colors.grey.shade200
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DhkpResolvedContext {
  final List<BlokRecord> murniRecords;
  final List<BlokRecord> entityRecordsAcrossYears;
  final List<BlokRecord> allScopedRecordsAcrossYears;
  final bool hasMultiDusun;
  final List<int> uniqueDusuns;
  final List<String> availableYears;
  final String primaryKecamatanCode;
  final bool hasMultipleKecamatans;
  final List<String> desaCodes;
  final bool hasMultiDesa;
  final String? effectiveDesaCode;
  final bool isKedusunanScope;
  final int? activeKedusunanNumber;

  const _DhkpResolvedContext({
    required this.murniRecords,
    required this.entityRecordsAcrossYears,
    required this.allScopedRecordsAcrossYears,
    required this.hasMultiDusun,
    required this.uniqueDusuns,
    required this.availableYears,
    required this.primaryKecamatanCode,
    required this.hasMultipleKecamatans,
    required this.desaCodes,
    required this.hasMultiDesa,
    required this.effectiveDesaCode,
    this.isKedusunanScope = false,
    this.activeKedusunanNumber,
  });

  bool get isKecamatanAggregate => hasMultiDesa && effectiveDesaCode == null;
}
