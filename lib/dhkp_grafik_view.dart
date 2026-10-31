import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'blok_record.dart';
import 'dhkp/dhkp_chart_widgets.dart';
import 'dhkp/dhkp_grafik_analytics.dart';
import 'dhkp/dhkp_grafik_exporter.dart';
import 'dhkp_widget_sync_service.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'dusun_data.dart';
import 'native_file_helper.dart';
import 'tagihan_result.dart' show formatRupiah;

export 'dhkp/dhkp_grafik_analytics.dart';

class DhkpGrafikView extends StatefulWidget {
  final List<BlokRecord> records;
  final String? selectedBlok;
  final int? selectedWilayah;

  const DhkpGrafikView({
    super.key,
    required this.records,
    this.selectedBlok,
    this.selectedWilayah,
  });

  @override
  State<DhkpGrafikView> createState() => _DhkpGrafikViewState();
}

class _DhkpGrafikViewState extends State<DhkpGrafikView>
    with SingleTickerProviderStateMixin {
  static const _prefKeyTab = 'dhkp_grafik_active_tab';
  static const _prefKeyStyle = 'dhkp_grafik_chart_style';
  static const _prefKeySort = 'dhkp_grafik_sort_mode';
  static const _prefKeyGroupByDusun = 'dhkp_grafik_group_by_dusun';
  static const _prefKeyCollapsed = 'dhkp_grafik_collapsed_sections';

  // Default: Data = Jumlah Persentase, Diagram = Batang, Desa = Semua Dusun
  DhkpGrafikTab _activeTab = DhkpGrafikTab.persentase;
  ChartStyle _selectedStyle = ChartStyle.batang;
  GrafikSortMode _sortMode = GrafikSortMode.wilayah;
  bool _groupByDusun = true;

  /// Drill-down khusus ketika pengguna mengeklik salah satu Dusun dari grafik
  int? _drillDownDusun;

  /// Item wilayah/bulan yang sedang diklik/disorot untuk melihat detail lengkap
  String? _selectedItemLabel;

  /// Menyimpan daftar ID kartu yang sedang dilipat.
  final Set<String> _collapsedSections = {};

  /// GlobalKey per bagian grafik untuk tangkapan gambar (PNG) & dokumen (PDF)
  final Map<String, GlobalKey> _boundaryKeys = {};

  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadSavedPreferences();
    _animController.forward();
    DhkpWidgetSyncService.syncFromRecords(widget.records);
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTabName = prefs.getString(_prefKeyTab);
      final savedStyleName = prefs.getString(_prefKeyStyle);
      final savedSortName = prefs.getString(_prefKeySort);
      final savedGroupByDusun = prefs.getBool(_prefKeyGroupByDusun);
      final savedCollapsed = prefs.getStringList(_prefKeyCollapsed);

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
        if (savedGroupByDusun != null) {
          _groupByDusun = savedGroupByDusun;
        }
        if (savedCollapsed != null) {
          _collapsedSections
            ..clear()
            ..addAll(savedCollapsed);
        }
      });
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyTab, _activeTab.name);
      await prefs.setString(_prefKeyStyle, _selectedStyle.name);
      await prefs.setString(_prefKeySort, _sortMode.name);
      await prefs.setBool(_prefKeyGroupByDusun, _groupByDusun);
      await prefs.setStringList(_prefKeyCollapsed, _collapsedSections.toList());
    } catch (_) {}
  }

  GlobalKey _getBoundaryKey(String sectionKey) {
    final fullKey = '${_activeTab.name}_$sectionKey';
    return _boundaryKeys.putIfAbsent(fullKey, () => GlobalKey());
  }

  @override
  void didUpdateWidget(DhkpGrafikView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records ||
        oldWidget.selectedBlok != widget.selectedBlok ||
        oldWidget.selectedWilayah != widget.selectedWilayah) {
      _selectedItemLabel = null;
      _animController.reset();
      _animController.forward();
      DhkpWidgetSyncService.syncFromRecords(widget.records);
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
    _animController.reset();
    _animController.forward();
  }

  void _switchStyle(ChartStyle style) {
    setState(() {
      _selectedStyle = style;
      if (style == ChartStyle.batang) _collapsedSections.remove('batang');
      if (style == ChartStyle.bar) _collapsedSections.remove('bar');
      if (style == ChartStyle.pie) _collapsedSections.remove('pie');
    });
    _savePreferences();
    _animController.reset();
    _animController.forward();
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

  List<DhkpGroupInfo> _groupData(
    List<BlokRecord> records, {
    required bool hasMultiDusun,
    double Function(DhkpGroupInfo)? sortValueFn,
    bool applySort = true,
  }) {
    return DhkpGrafikAnalytics.groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      groupByDusun: _groupByDusun,
      drillDownDusun: _drillDownDusun,
      sortMode: _sortMode,
      sortValueFn: sortValueFn,
      applySort: applySort,
    );
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
    if (_animController.value < 1.0) {
      _animController.value = 1.0;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await WidgetsBinding.instance.endOfFrame;

    final key = _getBoundaryKey(sectionKey);
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<Uint8List> _generateSectionPdf({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
  }) async {
    final pngBytes = await _captureSectionPng(sectionKey);
    return DhkpGrafikExporter.generateSectionPdf(
      pngBytes: pngBytes,
      title: title,
      subtitle: subtitle,
      groups: groups,
      activeTab: _activeTab,
      groupByDusun: _groupByDusun,
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
        messenger.showSnackBar(
          SnackBar(content: Text('Gambar grafik disimpan di: $savedPath')),
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
        messenger.showSnackBar(
          SnackBar(content: Text('Dokumen PDF grafik disimpan di: $savedPath')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mengunduh grafik: $e')),
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
        await NativeFileHelper.shareBytes(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'image/png',
        );
      } else {
        final pdfBytes = await _generateSectionPdf(
          sectionKey: sectionKey,
          title: title,
          subtitle: subtitle,
          groups: groups,
        );
        final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'pdf');
        await NativeFileHelper.shareBytes(
          bytes: pdfBytes,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal membagikan grafik: $e')),
      );
    }
  }

  Future<void> _handlePrintSection({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<DhkpGroupInfo> groups,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdfBytes = await _generateSectionPdf(
        sectionKey: sectionKey,
        title: title,
        subtitle: subtitle,
        groups: groups,
      );
      if (!mounted) return;
      final fileName = DhkpGrafikExporter.buildSafeFileName(title, 'pdf');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(pdfBytes: pdfBytes, fileName: fileName),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan cetak grafik: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    // 1. Filter kalkulasi murni desa (Target Pemda dipisah tidak dihitung)
    final allMurni = widget.records.where((r) => !r.isTargetPemda).toList();

    // Periksa apakah data asli mencakup beberapa dusun (Skala Desa vs Skala Dusun)
    final uniqueDusuns = <int>{};
    for (final r in allMurni) {
      for (final d in dusunList) {
        if (d.bloks.contains(r.blok)) {
          uniqueDusuns.add(d.number);
          break;
        }
      }
    }
    final hasMultiDusun = uniqueDusuns.length > 1;

    // 2. Terapkan drill-down dusun jika sedang aktif
    final List<BlokRecord> murniRecords;
    if (hasMultiDusun && _drillDownDusun != null) {
      final dObj = dusunByNumber(_drillDownDusun!);
      final dBloks = dObj?.bloks.toSet() ?? <String>{};
      murniRecords = allMurni.where((r) => dBloks.contains(r.blok)).toList();
    } else {
      murniRecords = allMurni;
    }

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
    final lunasNominalPct = totalNominalTarget > 0
        ? (sudahBayarNominal / totalNominalTarget * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. TOP TAB BAR: 5 KATEGORI UTAMA
          _buildTopCategoryTabs(isDark, colorScheme),
          const SizedBox(height: 10),

          // 2. FILTER CEPAT DUSUN (UNTUK DESA: SEMUA DUSUN / SEMUA BLOK / PER DUSUN)
          if (hasMultiDusun) ...[
            _buildScopeQuickBar(
              uniqueDusuns.toList()..sort(),
              isDark,
              colorScheme,
            ),
            const SizedBox(height: 10),
          ],

          // 3. KARTU RINGKASAN UTAMA DI ATAS (3 METRIK KUNCI SESUAI TAB)
          buildDhkpStatRow(
            DhkpGrafikAnalytics.buildHighlightStats(
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
            ),
            isDark,
          ),
          const SizedBox(height: 10),

          // 4. TOOLBAR KONTROL: PILIH DIAGRAM + URUTAN + LIPAT/BUKA SEMUA
          _buildControlToolbar(hasMultiDusun, isDark, colorScheme),
          const SizedBox(height: 12),

          // 5. PANEL DETAIL INTERAKTIF (MUNCUL SAAT SALAH SATU WILAYAH DIKLIK)
          if (_selectedItemLabel != null) ...[
            _buildSelectedDetailBanner(murniRecords, hasMultiDusun, isDark),
            const SizedBox(height: 12),
          ],

          // 6. KONTEN GRAFIK & TABEL DENGAN FITUR LIPAT + UNDUH/BAGIKAN/CETAK
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return switch (_activeTab) {
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
                  murniRecords,
                  isDark,
                ),
              };
            },
          ),
        ],
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
                  colors: [tab.accentColor.shade600, tab.accentColor.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: tab.accentColor.withValues(alpha: 0.35),
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
                  : (isDark ? Colors.grey.shade300 : tab.accentColor.shade700),
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
  // 2. QUICK SCOPE BAR (SEMUA DUSUN vs SEMUA BLOK vs DRILL-DOWN PER DUSUN)
  // =========================================================================
  Widget _buildScopeQuickBar(
    List<int> dusunNumbers,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final accent = _activeTab.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.place_rounded, size: 15, color: accent.shade700),
            const SizedBox(width: 6),
            Text(
              'Wilayah:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            // Chip Semua Dusun (Default untuk Desa)
            _buildScopeChip(
              label: 'Semua Dusun',
              isSelected: _drillDownDusun == null && _groupByDusun,
              accent: accent,
              isDark: isDark,
              onTap: () {
                setState(() {
                  _drillDownDusun = null;
                  _groupByDusun = true;
                  _selectedItemLabel = null;
                });
                _savePreferences();
                _animController.reset();
                _animController.forward();
              },
            ),
            const SizedBox(width: 4),
            // Chip Semua Blok Se-Desa
            _buildScopeChip(
              label: 'Semua Blok',
              isSelected: _drillDownDusun == null && !_groupByDusun,
              accent: accent,
              isDark: isDark,
              onTap: () {
                setState(() {
                  _drillDownDusun = null;
                  _groupByDusun = false;
                  _selectedItemLabel = null;
                });
                _savePreferences();
                _animController.reset();
                _animController.forward();
              },
            ),
            Container(
              height: 16,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: isDark ? Colors.white24 : Colors.grey.shade300,
            ),
            // Chip masing-masing Dusun untuk lihat blok di dalamnya
            for (final dNum in dusunNumbers) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildScopeChip(
                  label: 'Dusun $dNum',
                  isSelected: _drillDownDusun == dNum,
                  accent: accent,
                  isDark: isDark,
                  onTap: () {
                    setState(() {
                      if (_drillDownDusun == dNum) {
                        _drillDownDusun = null;
                        _groupByDusun = true;
                      } else {
                        _drillDownDusun = dNum;
                        _groupByDusun = false;
                      }
                      _selectedItemLabel = null;
                    });
                    _animController.reset();
                    _animController.forward();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScopeChip({
    required String label,
    required bool isSelected,
    required MaterialColor accent,
    required bool isDark,
    required VoidCallback onTap,
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? (isDark ? accent.shade200 : accent.shade800)
                : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
          ),
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
    final accent = _activeTab.accentColor;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Pemilih Jenis Diagram (Batang / Mendatar / Lingkaran / Semua)
        Container(
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
              for (final style in ChartStyle.values)
                InkWell(
                  onTap: () => _switchStyle(style),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
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
                          style.icon,
                          size: 14,
                          color: _selectedStyle == style
                              ? accent.shade700
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          style.label,
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
                ),
            ],
          ),
        ),

        // Kanan: Pengurutan & Tombol Lipat/Buka Semua
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_activeTab != DhkpGrafikTab.trenBulanan) ...[
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
              const SizedBox(width: 6),
            ],

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
        ? DhkpGrafikAnalytics.buildMonthGroups(records)
        : _groupData(records, hasMultiDusun: hasMultiDusun, applySort: false);

    final match = groups
        .where((g) => g.label == _selectedItemLabel)
        .firstOrNull;
    if (match == null) return const SizedBox.shrink();

    final accent = _activeTab.accentColor;
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
                      _groupByDusun = false;
                      _selectedItemLabel = null;
                    });
                    _animController.reset();
                    _animController.forward();
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
                Colors.teal,
                isDark,
              ),
              if (_activeTab != DhkpGrafikTab.trenBulanan) ...[
                _buildMiniDetailStat(
                  'Belum Bayar',
                  '${formatRupiah(match.belumBayarNominal)} (${match.belumBayarNop} objek)',
                  Colors.orange,
                  isDark,
                ),
                _buildMiniDetailStat(
                  'Total Ketetapan',
                  '${formatRupiah(match.totalNominal)} (${match.totalNop} objek)',
                  Colors.indigo,
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
                    duration: const Duration(milliseconds: 250),
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
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: RepaintBoundary(
              key: boundaryKey,
              child: Container(
                color: isDark ? Theme.of(context).cardColor : Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: child,
              ),
            ),
            crossFadeState: isCollapsed
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
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
            accentColor: Colors.teal,
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
              subLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(0)}%',
              color1: Colors.teal.shade400,
              color2: Colors.teal.shade800,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
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
            accentColor: Colors.teal,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNominal.toDouble())
                  .fold(0.0, math.max),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              subRight: (g) => '${g.lunasPct.toStringAsFixed(1)}% dari target',
              color1: Colors.teal.shade400,
              color2: Colors.teal.shade700,
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
            accentColor: Colors.teal,
            isDark: isDark,
            groups: groups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                groups,
                (g) => g.lunasNominal.toDouble(),
                totalPendapatanMasuk.toDouble(),
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalPendapatanMasuk)}',
              centerSub: 'TERKUMPUL',
              centerColor: Colors.teal,
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
          accentColor: Colors.teal,
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
            accentColor: _activeTab.accentColor,
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
            accentColor: Colors.green,
            isDark: isDark,
            groups: groups,
            child: renderDhkpColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasPct,
              maxVal: 100.0,
              topLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
              subLabelExtractor: (g) => '${g.lunasNop}/${g.totalNop}',
              color1: Colors.green.shade400,
              color2: Colors.green.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
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
            accentColor: Colors.green,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasPct,
              maxVal: 100.0,
              labelRight: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
              subRight: (g) => '${g.lunasNop}/${g.totalNop} objek',
              color1: Colors.green.shade400,
              color2: Colors.green.shade700,
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
            accentColor: Colors.green,
            isDark: isDark,
            groups: groups,
            child: renderDhkpDonutTwoSlice(
              achievedPct: overallPct,
              achievedLabel: 'Sudah Lunas',
              remainingLabel: 'Sisa Target',
              achievedColor: Colors.green.shade600,
              remainingColor: Colors.grey.shade400,
              centerLabel: '${overallPct.toStringAsFixed(1)}%',
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
          accentColor: Colors.green,
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
            accentColor: _activeTab.accentColor,
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
            accentColor: Colors.orange,
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
              subLabelExtractor: (g) => '${g.belumBayarNop} objek',
              color1: Colors.orange.shade400,
              color2: Colors.deepOrange.shade700,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
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
            accentColor: Colors.orange,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.belumBayarNominal.toDouble(),
              maxVal: groups
                  .map((g) => g.belumBayarNominal.toDouble())
                  .fold(0.0, math.max),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.belumBayarNominal)}',
              subRight: (g) => '${g.belumBayarNop} objek belum lunas',
              color1: Colors.orange.shade400,
              color2: Colors.deepOrange.shade600,
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
            accentColor: Colors.orange,
            isDark: isDark,
            groups: groups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                groups,
                (g) => g.belumBayarNominal.toDouble(),
                totalBelumBayarNominal.toDouble(),
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalBelumBayarNominal)}',
              centerSub: 'BELUM BAYAR',
              centerColor: Colors.orange,
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
          accentColor: Colors.orange,
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
            accentColor: _activeTab.accentColor,
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
            accentColor: Colors.blue,
            isDark: isDark,
            groups: groups,
            child: renderDhkpColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNop.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNop.toDouble())
                  .fold(0.0, math.max),
              topLabelExtractor: (g) => '${g.lunasNop} objek',
              subLabelExtractor: (g) =>
                  'Rp ${formatShortRupiah(g.lunasNominal)}',
              color1: Colors.blue.shade400,
              color2: Colors.blue.shade800,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
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
            accentColor: Colors.blue,
            isDark: isDark,
            groups: groups,
            child: renderDhkpHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNop.toDouble(),
              maxVal: groups
                  .map((g) => g.lunasNop.toDouble())
                  .fold(0.0, math.max),
              labelRight: (g) => '${g.lunasNop} objek',
              subRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              color1: Colors.blue.shade400,
              color2: Colors.blue.shade700,
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
            accentColor: Colors.blue,
            isDark: isDark,
            groups: groups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                groups,
                (g) => g.lunasNop.toDouble(),
                totalSudahBayarCount.toDouble(),
              ),
              centerLabel: '$totalSudahBayarCount',
              centerSub: 'OBJEK LUNAS',
              centerColor: Colors.blue,
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
          accentColor: Colors.blue,
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
            accentColor: _activeTab.accentColor,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: TREN PEMBAYARAN TIAP BULAN (JAN - DES)
  // =========================================================================
  Widget _buildTrenBulananSection(List<BlokRecord> records, bool isDark) {
    const monthNames = DhkpGrafikAnalytics.monthNames;
    final monthGroups = DhkpGrafikAnalytics.buildMonthGroups(records);
    final monthlyNominal = monthGroups.map((g) => g.lunasNominal).toList();
    final totalDatedNominal = monthlyNominal.fold<int>(0, (sum, v) => sum + v);
    final maxMonthVal = monthlyNominal.fold<int>(0, math.max);

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
        // 1. Grafik Perkembangan Bulanan
        _buildCollapsibleSectionCard(
          sectionKey: 'kurva',
          icon: Icons.show_chart_rounded,
          title: 'Grafik Perkembangan Pembayaran Bulanan',
          subtitle:
              'Alur penerimaan pembayaran PBB dari Januari sampai Desember',
          badgeText: 'Jan – Des',
          accentColor: Colors.purple,
          isDark: isDark,
          groups: monthGroups,
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  void onTouch(Offset localPos) {
                    if (monthGroups.isEmpty || w <= 0) return;
                    final stepX = w / (monthGroups.length - 1);
                    final idx = (localPos.dx / stepX).round().clamp(
                      0,
                      monthGroups.length - 1,
                    );
                    final label = monthNames[idx];
                    if (_selectedItemLabel != label) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedItemLabel = label;
                      });
                    }
                  }

                  final selIndex = _selectedItemLabel != null
                      ? monthNames.indexOf(_selectedItemLabel!)
                      : null;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => onTouch(d.localPosition),
                    onPanUpdate: (d) => onTouch(d.localPosition),
                    child: SizedBox(
                      height: 180,
                      child: CustomPaint(
                        size: Size(w, 180),
                        painter: GrassLineAreaPainter(
                          data: monthlyNominal,
                          maxVal: maxMonthVal > 0 ? maxMonthVal : 1,
                          progress: _animation.value,
                          lineColor: Colors.purple.shade600,
                          isDark: isDark,
                          selectedIndex: selIndex != null && selIndex >= 0
                              ? selIndex
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final m in monthNames)
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedItemLabel = _selectedItemLabel == m
                              ? null
                              : m;
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Text(
                          m,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: _selectedItemLabel == m
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: _selectedItemLabel == m
                                ? Colors.purple
                                : (isDark ? Colors.grey.shade400 : Colors.grey),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (showBatang) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'batang',
            icon: Icons.bar_chart_rounded,
            title: 'Diagram Batang: Penerimaan per Bulan',
            subtitle: 'Perbandingan uang masuk tiap bulan (Jan–Des)',
            badgeText: '12 Bulan',
            accentColor: Colors.purple,
            isDark: isDark,
            groups: monthGroups,
            child: renderDhkpColumnBars(
              groups: monthGroups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: maxMonthVal.toDouble(),
              topLabelExtractor: (g) =>
                  g.lunasNominal > 0 ? formatShortRupiah(g.lunasNominal) : '-',
              subLabelExtractor: (g) =>
                  g.lunasNop > 0 ? '${g.lunasNop} objek' : '',
              color1: Colors.purple.shade400,
              color2: Colors.purple.shade800,
              isDark: isDark,
              selectedItemLabel: _selectedItemLabel,
              animationValue: _animation.value,
              onSelectLabel: _onSelectLabel,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Rincian Bulanan (Jan–Des)',
            subtitle: 'Daftar penerimaan kas dari awal hingga akhir tahun',
            badgeText: '12 Bulan',
            accentColor: Colors.purple,
            isDark: isDark,
            groups: monthGroups,
            child: renderDhkpHorizontalBars(
              groups: monthGroups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: maxMonthVal.toDouble(),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              subRight: (g) =>
                  '${g.lunasNop} objek (${g.lunasPct.toStringAsFixed(1)}%)',
              color1: Colors.purple.shade400,
              color2: Colors.indigo.shade600,
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
            accentColor: Colors.purple,
            isDark: isDark,
            groups: monthGroups,
            child: renderDhkpPieChart(
              slices: DhkpGrafikAnalytics.makeSlices(
                monthGroups.where((g) => g.lunasNominal > 0).toList(),
                (g) => g.lunasNominal.toDouble(),
                totalDatedNominal.toDouble(),
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalDatedNominal)}',
              centerSub: 'TOTAL BULANAN',
              centerColor: Colors.purple,
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
          title: 'Tabel Rincian Penerimaan Bulanan (Jan – Des)',
          subtitle: 'Rekapitulasi jumlah pembayaran dan nilai rupiah per bulan',
          badgeText: '12 Bulan',
          accentColor: Colors.purple,
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
            accentColor: _activeTab.accentColor,
            onSelectLabel: _onSelectLabel,
          ),
        ),
      ],
    );
  }
}
