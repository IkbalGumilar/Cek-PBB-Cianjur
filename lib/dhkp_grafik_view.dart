import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'blok_record.dart';
import 'dhkp_widget_sync_service.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'dusun_data.dart';
import 'native_file_helper.dart';
import 'tagihan_result.dart' show formatRupiah;

/// 5 Tab Kategori Data Grafik Utama:
/// 1. Jumlah Persentase (Default)
/// 2. Jumlah Pendapatan
/// 3. Belum Bayar
/// 4. Sudah Bayar
/// 5. Tren Pembayaran tiap bulan Jan-Des
enum DhkpGrafikTab {
  persentase('Jumlah Persentase', 'Persentase', Icons.pie_chart_rounded, Colors.green),
  pendapatan('Jumlah Pendapatan', 'Pendapatan', Icons.account_balance_wallet_rounded, Colors.teal),
  belumBayar('Belum Bayar', 'Belum Bayar', Icons.pending_actions_rounded, Colors.orange),
  sudahBayar('Sudah Bayar', 'Sudah Bayar', Icons.task_alt_rounded, Colors.blue),
  trenBulanan('Tren Pembayaran', 'Tren Jan–Des', Icons.insights_rounded, Colors.purple);

  final String label;
  final String shortLabel;
  final IconData icon;
  final MaterialColor accentColor;
  const DhkpGrafikTab(this.label, this.shortLabel, this.icon, this.accentColor);
}

/// Mode tampilan diagram grafik (Default: Diagram Batang)
enum ChartStyle {
  batang('Batang', Icons.bar_chart_rounded),
  bar('Mendatar', Icons.align_horizontal_left_rounded),
  pie('Lingkaran', Icons.pie_chart_outline_rounded),
  semua('Semua', Icons.dashboard_customize_rounded);

  final String label;
  final IconData icon;
  const ChartStyle(this.label, this.icon);
}

/// Mode pengurutan data pada grafik & tabel
enum GrafikSortMode {
  wilayah('Urut Kode', Icons.sort_by_alpha_rounded),
  tertinggi('Tertinggi ↓', Icons.trending_down_rounded),
  terendah('Terendah ↑', Icons.trending_up_rounded);

  final String label;
  final IconData icon;
  const GrafikSortMode(this.label, this.icon);
}

String formatShortRupiah(int value) {
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(1)} M';
  } else if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)} Jt';
  } else if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)} Rb';
  }
  return '$value';
}

DateTime? _parsePaymentDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s == '2026') return null;
  try {
    return DateTime.parse(s);
  } catch (_) {}
  final dmy = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(s);
  if (dmy != null) {
    final d = int.tryParse(dmy.group(1)!);
    final m = int.tryParse(dmy.group(2)!);
    final y = int.tryParse(dmy.group(3)!);
    if (d != null && m != null && y != null) {
      return DateTime(y, m, d);
    }
  }
  return null;
}

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

class _DhkpGrafikViewState extends State<DhkpGrafikView> with SingleTickerProviderStateMixin {
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

  bool get _allCollapsed =>
      _collapsedSections.containsAll(['kurva', 'batang', 'bar', 'pie', 'tabel']);

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

  // =========================================================================
  // EKSPOR GRAFIK: UNDUH, BAGIKAN (GAMBAR & PDF SAJA), DAN CETAK
  // =========================================================================
  String _buildSafeFileName(String title, String ext) {
    final clean = title
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return 'Grafik_${clean.isEmpty ? 'DHKP' : clean}.$ext';
  }

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
    required List<_GroupInfo> groups,
  }) async {
    final pngBytes = await _captureSectionPng(sectionKey);
    final doc = pw.Document();

    final scopeLabel = _drillDownDusun != null
        ? 'Cakupan: Dusun $_drillDownDusun (Per Blok)'
        : (_groupByDusun ? 'Cakupan: Semua Dusun' : 'Cakupan: Semua Blok');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '$subtitle • $scopeLabel',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          if (pngBytes != null) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(pngBytes),
                fit: pw.BoxFit.contain,
                height: 220,
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          if (groups.isNotEmpty) ...[
            pw.Text(
              'Ringkasan Tabel Data',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headers: [
                _activeTab == DhkpGrafikTab.trenBulanan ? 'Bulan' : 'Wilayah',
                'Objek Lunas',
                _activeTab == DhkpGrafikTab.trenBulanan ? 'Nominal Pembayaran' : 'Sudah Bayar',
                if (_activeTab != DhkpGrafikTab.trenBulanan) 'Belum Bayar',
                _activeTab == DhkpGrafikTab.trenBulanan ? '% Porsi' : 'Persentase',
              ],
              data: [
                for (final g in groups)
                  _activeTab == DhkpGrafikTab.trenBulanan
                      ? [
                          g.label,
                          '${g.lunasNop}',
                          formatRupiah(g.lunasNominal),
                          '${g.lunasPct.toStringAsFixed(1)}%',
                        ]
                      : [
                          g.label,
                          '${g.lunasNop}/${g.totalNop}',
                          formatRupiah(g.lunasNominal),
                          formatRupiah(g.belumBayarNominal),
                          '${g.lunasPct.toStringAsFixed(1)}%',
                        ],
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<String?> _showFormatChoiceDialog({
    required String dialogTitle,
    required String dialogSubtitle,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dialogTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              dialogSubtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'png'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.image_outlined, color: Colors.teal),
              title: Text('Gambar (PNG)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Tangkapan gambar visual grafik siap kirim'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'pdf'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
              title: Text('Dokumen (PDF)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Dokumen grafik lengkap beserta tabel rincian'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDownloadSection({
    required String sectionKey,
    required String title,
    required String subtitle,
    required List<_GroupInfo> groups,
  }) async {
    final format = await _showFormatChoiceDialog(
      dialogTitle: 'Unduh Data Grafik',
      dialogSubtitle: title,
    );
    if (format == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (format == 'png') {
        final bytes = await _captureSectionPng(sectionKey);
        if (bytes == null) throw Exception('Gagal menangkap tampilan grafik.');
        final fileName = _buildSafeFileName(title, 'png');
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
        final fileName = _buildSafeFileName(title, 'pdf');
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
    required List<_GroupInfo> groups,
  }) async {
    final format = await _showFormatChoiceDialog(
      dialogTitle: 'Bagikan Grafik',
      dialogSubtitle: 'Pilih bentuk berkas yang ingin dibagikan',
    );
    if (format == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (format == 'png') {
        final bytes = await _captureSectionPng(sectionKey);
        if (bytes == null) throw Exception('Gagal menangkap tampilan grafik.');
        final fileName = _buildSafeFileName(title, 'png');
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
        final fileName = _buildSafeFileName(title, 'pdf');
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
    required List<_GroupInfo> groups,
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
      final fileName = _buildSafeFileName(title, 'pdf');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: fileName,
          ),
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

    final totalNominalTarget = murniRecords.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
    final sudahBayarNominal = sudahBayarList.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
    final belumBayarNominal = belumBayarList.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

    final lunasNopPct = totalNop > 0 ? (sudahBayarList.length / totalNop * 100) : 0.0;
    final lunasNominalPct = totalNominalTarget > 0 ? (sudahBayarNominal / totalNominalTarget * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===================================================================
          // 1. TOP TAB BAR: 5 KATEGORI UTAMA (MENGGANTIKAN FILTER ATAS)
          // ===================================================================
          _buildTopCategoryTabs(isDark, colorScheme),
          const SizedBox(height: 10),

          // ===================================================================
          // 2. FILTER CEPAT DUSUN (UNTUK DESA: SEMUA DUSUN / SEMUA BLOK / PER DUSUN)
          // ===================================================================
          if (hasMultiDusun) ...[
            _buildScopeQuickBar(uniqueDusuns.toList()..sort(), isDark, colorScheme),
            const SizedBox(height: 10),
          ],

          // ===================================================================
          // 3. KARTU RINGKASAN UTAMA DI ATAS (3 METRIK KUNCI SESUAI TAB)
          // ===================================================================
          _buildHighlightCard(
            totalNop: totalNop,
            sudahBayarCount: sudahBayarList.length,
            belumBayarCount: belumBayarList.length,
            sudahBayarNominal: sudahBayarNominal,
            belumBayarNominal: belumBayarNominal,
            totalNominalTarget: totalNominalTarget,
            lunasNominalPct: lunasNominalPct,
            lunasNopPct: lunasNopPct,
            records: murniRecords,
            isDark: isDark,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 10),

          // ===================================================================
          // 4. TOOLBAR KONTROL: PILIH DIAGRAM + URUTAN + LIPAT/BUKA SEMUA
          // ===================================================================
          _buildControlToolbar(hasMultiDusun, isDark, colorScheme),
          const SizedBox(height: 12),

          // ===================================================================
          // 5. PANEL DETAIL INTERAKTIF (MUNCUL SAAT SALAH SATU WILAYAH DIKLIK)
          // ===================================================================
          if (_selectedItemLabel != null) ...[
            _buildSelectedDetailBanner(murniRecords, hasMultiDusun, isDark),
            const SizedBox(height: 12),
          ],

          // ===================================================================
          // 6. KONTEN GRAFIK & TABEL DENGAN FITUR LIPAT + UNDUH/BAGIKAN/CETAK
          // ===================================================================
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
                    colorScheme,
                  ),
                DhkpGrafikTab.persentase => _buildPersentaseSection(
                    murniRecords,
                    hasMultiDusun,
                    lunasNominalPct,
                    isDark,
                    colorScheme,
                  ),
                DhkpGrafikTab.belumBayar => _buildBelumBayarSection(
                    murniRecords,
                    hasMultiDusun,
                    belumBayarNominal,
                    totalNominalTarget,
                    isDark,
                    colorScheme,
                  ),
                DhkpGrafikTab.sudahBayar => _buildSudahBayarSection(
                    murniRecords,
                    hasMultiDusun,
                    sudahBayarList.length,
                    sudahBayarNominal,
                    isDark,
                    colorScheme,
                  ),
                DhkpGrafikTab.trenBulanan => _buildTrenBulananSection(
                    murniRecords,
                    isDark,
                    colorScheme,
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
        color: isDark ? colorScheme.surfaceContainerHighest : Colors.grey.shade100,
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
        padding: EdgeInsets.symmetric(horizontal: isWide ? 8 : 14, vertical: 10),
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
  Widget _buildScopeQuickBar(List<int> dusunNumbers, bool isDark, ColorScheme colorScheme) {
    final accent = _activeTab.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
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
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100),
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
  Widget _buildControlToolbar(bool hasMultiDusun, bool isDark, ColorScheme colorScheme) {
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
            color: isDark ? colorScheme.surfaceContainerHigh : Colors.grey.shade200,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            fontWeight: _selectedStyle == style ? FontWeight.bold : FontWeight.w500,
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
                              fontWeight: _sortMode == m ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? colorScheme.surfaceContainerHigh : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_vert_rounded, size: 15, color: accent.shade700),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark ? colorScheme.surfaceContainerHigh : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _allCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
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
  Widget _buildSelectedDetailBanner(List<BlokRecord> records, bool hasMultiDusun, bool isDark) {
    final groups = _activeTab == DhkpGrafikTab.trenBulanan
        ? _buildMonthGroups(records)
        : _groupData(records, hasMultiDusun: hasMultiDusun, applySort: false);

    final match = groups.where((g) => g.label == _selectedItemLabel).firstOrNull;
    if (match == null) return const SizedBox.shrink();

    final accent = _activeTab.accentColor;
    final isDusunItem = match.label.startsWith('Dusun ');
    final dusunNum = isDusunItem ? int.tryParse(match.label.replaceFirst('Dusun ', '')) : null;

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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  icon: Icon(Icons.zoom_in_rounded, size: 15, color: accent.shade700),
                  label: Text(
                    'Lihat Blok',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent.shade700),
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
              _buildMiniDetailStat('Sudah Bayar', '${formatRupiah(match.lunasNominal)} (${match.lunasNop} objek)', Colors.teal, isDark),
              if (_activeTab != DhkpGrafikTab.trenBulanan) ...[
                _buildMiniDetailStat('Belum Bayar', '${formatRupiah(match.belumBayarNominal)} (${match.belumBayarNop} objek)', Colors.orange, isDark),
                _buildMiniDetailStat('Total Ketetapan', '${formatRupiah(match.totalNominal)} (${match.totalNop} objek)', Colors.indigo, isDark),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDetailStat(String label, String val, MaterialColor color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color.shade600, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
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
    required List<_GroupInfo> groups,
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
          // Header yang bisa diklik untuk melipat / membuka, dilengkapi ikon Unduh, Bagikan, Cetak
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
                      color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
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
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          isCollapsed ? 'Terlipat • $badgeText' : '$subtitle • $badgeText',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Ikon Unduh, Bagikan, dan Cetak tepat di samping panah bawah
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'Unduh Grafik',
                    icon: Icon(
                      Icons.download_outlined,
                      size: 18,
                      color: isDark ? Colors.grey.shade300 : accentColor.shade700,
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
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'Bagikan Grafik (Gambar / PDF)',
                    icon: Icon(
                      Icons.share_outlined,
                      size: 17,
                      color: isDark ? Colors.grey.shade300 : accentColor.shade700,
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
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'Cetak Grafik',
                    icon: Icon(
                      Icons.print_outlined,
                      size: 18,
                      color: isDark ? Colors.grey.shade300 : accentColor.shade700,
                    ),
                    onPressed: () => _handlePrintSection(
                      sectionKey: sectionKey,
                      title: title,
                      subtitle: subtitle,
                      groups: groups,
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Ikon panah lipat/buka
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

          // Isi Kartu dengan Animasi Buka/Lipat Halus & RepaintBoundary untuk Ekspor Gambar/PDF
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
            crossFadeState: isCollapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeInOutCubic,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // HIGHLIGHT CARDS PER TAB DI ATAS
  // =========================================================================
  Widget _buildHighlightCard({
    required int totalNop,
    required int sudahBayarCount,
    required int belumBayarCount,
    required int sudahBayarNominal,
    required int belumBayarNominal,
    required int totalNominalTarget,
    required double lunasNominalPct,
    required double lunasNopPct,
    required List<BlokRecord> records,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    switch (_activeTab) {
      case DhkpGrafikTab.pendapatan:
        return _buildStatRow([
          _StatItem(
            label: 'Pendapatan Masuk',
            value: formatRupiah(sudahBayarNominal),
            sub: 'Uang pajak terkumpul',
            color: Colors.teal,
            icon: Icons.account_balance_wallet_rounded,
          ),
          _StatItem(
            label: 'Total Target',
            value: 'Rp ${formatShortRupiah(totalNominalTarget)}',
            sub: 'Ketetapan pokok wilayah',
            color: Colors.indigo,
            icon: Icons.flag_rounded,
          ),
          _StatItem(
            label: 'Belum Masuk',
            value: 'Rp ${formatShortRupiah(belumBayarNominal)}',
            sub: 'Selisih dari target',
            color: Colors.orange,
            icon: Icons.hourglass_bottom_rounded,
          ),
        ], isDark);

      case DhkpGrafikTab.persentase:
        return _buildStatRow([
          _StatItem(
            label: 'Capaian Uang (%)',
            value: '${lunasNominalPct.toStringAsFixed(1)}%',
            sub: 'Dari total nilai target',
            color: Colors.green,
            icon: Icons.percent_rounded,
          ),
          _StatItem(
            label: 'Capaian Objek Pajak',
            value: '${lunasNopPct.toStringAsFixed(1)}%',
            sub: '$sudahBayarCount dari $totalNop objek',
            color: Colors.teal,
            icon: Icons.check_circle_outline_rounded,
          ),
          _StatItem(
            label: 'Sisa Belum Tercapai',
            value: '${(100 - lunasNominalPct).clamp(0, 100).toStringAsFixed(1)}%',
            sub: 'Perlu ditagih',
            color: Colors.amber,
            icon: Icons.timelapse_rounded,
          ),
        ], isDark);

      case DhkpGrafikTab.belumBayar:
        return _buildStatRow([
          _StatItem(
            label: 'Tagihan Belum Bayar',
            value: formatRupiah(belumBayarNominal),
            sub: 'Total belum lunas',
            color: Colors.orange,
            icon: Icons.pending_actions_rounded,
          ),
          _StatItem(
            label: 'Objek Belum Lunas',
            value: '$belumBayarCount Objek',
            sub: 'Wajib pajak belum bayar',
            color: Colors.deepOrange,
            icon: Icons.person_search_rounded,
          ),
          _StatItem(
            label: 'Persentase Belum Bayar',
            value: '${(100 - lunasNominalPct).clamp(0, 100).toStringAsFixed(1)}%',
            sub: 'Dari total target wilayah',
            color: Colors.red,
            icon: Icons.pie_chart_rounded,
          ),
        ], isDark);

      case DhkpGrafikTab.sudahBayar:
        final avgNom = sudahBayarCount > 0 ? (sudahBayarNominal ~/ sudahBayarCount) : 0;
        return _buildStatRow([
          _StatItem(
            label: 'Total Sudah Bayar',
            value: formatRupiah(sudahBayarNominal),
            sub: 'Uang sudah lunas',
            color: Colors.blue,
            icon: Icons.task_alt_rounded,
          ),
          _StatItem(
            label: 'Jumlah Objek Lunas',
            value: '$sudahBayarCount Objek',
            sub: 'Wajib pajak sudah bayar',
            color: Colors.teal,
            icon: Icons.receipt_rounded,
          ),
          _StatItem(
            label: 'Rata-rata Pembayaran',
            value: 'Rp ${formatShortRupiah(avgNom)}',
            sub: 'Nilai rata-rata per objek',
            color: Colors.indigo,
            icon: Icons.calculate_rounded,
          ),
        ], isDark);

      case DhkpGrafikTab.trenBulanan:
        final monthlyData = List<int>.filled(12, 0);
        int datedCount = 0;
        for (final r in records) {
          if (r.isPaid && r.tanggalBayar.isNotEmpty) {
            final dt = _parsePaymentDate(r.tanggalBayar);
            if (dt != null && dt.month >= 1 && dt.month <= 12) {
              monthlyData[dt.month - 1] += r.jumlahPbbValue;
              datedCount++;
            }
          }
        }
        int peakMonth = 0;
        int peakVal = 0;
        for (int i = 0; i < 12; i++) {
          if (monthlyData[i] > peakVal) {
            peakVal = monthlyData[i];
            peakMonth = i + 1;
          }
        }
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
        final peakName = peakMonth > 0 ? '${monthNames[peakMonth - 1]} (Rp ${formatShortRupiah(peakVal)})' : '-';

        return _buildStatRow([
          _StatItem(
            label: 'Bulan Tertinggi',
            value: peakName,
            sub: 'Penerimaan terbanyak',
            color: Colors.purple,
            icon: Icons.trending_up_rounded,
          ),
          _StatItem(
            label: 'Pembayaran Tercatat',
            value: '$datedCount Objek',
            sub: 'Memiliki tanggal bayar',
            color: Colors.indigo,
            icon: Icons.calendar_today_rounded,
          ),
          _StatItem(
            label: 'Total Jan–Des',
            value: 'Rp ${formatShortRupiah(sudahBayarNominal)}',
            sub: 'Penerimaan tahun ini',
            color: Colors.teal,
            icon: Icons.date_range_rounded,
          ),
        ], isDark);
    }
  }

  Widget _buildStatRow(List<_StatItem> items, bool isDark) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: items[i].color.withValues(alpha: isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: items[i].color.withValues(alpha: isDark ? 0.35 : 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(items[i].icon, size: 14, color: items[i].color.shade700),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: items[i].color.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : items[i].color.shade900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    items[i].sub,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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
    ColorScheme colorScheme,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.lunasNominal.toDouble(),
    );
    if (groups.isEmpty) return _buildEmptyCard();

    final showBatang = _selectedStyle == ChartStyle.batang || _selectedStyle == ChartStyle.semua;
    final showBar = _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie = _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

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
            child: _renderColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: groups.map((g) => g.lunasNominal.toDouble()).fold(0.0, math.max),
              topLabelExtractor: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              subLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(0)}%',
              color1: Colors.teal.shade400,
              color2: Colors.teal.shade800,
              isDark: isDark,
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
            child: _renderHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: groups.map((g) => g.lunasNominal.toDouble()).fold(0.0, math.max),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              subRight: (g) => '${g.lunasPct.toStringAsFixed(1)}% dari target',
              color1: Colors.teal.shade400,
              color2: Colors.teal.shade700,
              isDark: isDark,
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
            child: _renderPieChart(
              slices: _makeSlices(groups, (g) => g.lunasNominal.toDouble(), totalPendapatanMasuk.toDouble()),
              centerLabel: 'Rp ${formatShortRupiah(totalPendapatanMasuk)}',
              centerSub: 'TERKUMPUL',
              centerColor: Colors.teal,
              isDark: isDark,
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
          child: _buildDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Target (Rp)',
            col3: 'Pendapatan (Rp)',
            col4: '% Capaian',
            col2Val: (g) => formatShortRupiah(g.totalNominal),
            col3Val: (g) => formatShortRupiah(g.lunasNominal),
            col4Val: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
            isDark: isDark,
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
    ColorScheme colorScheme,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.lunasPct,
    );
    if (groups.isEmpty) return _buildEmptyCard();

    final showBatang = _selectedStyle == ChartStyle.batang || _selectedStyle == ChartStyle.semua;
    final showBar = _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie = _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

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
            child: _renderColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasPct,
              maxVal: 100.0,
              topLabelExtractor: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
              subLabelExtractor: (g) => '${g.lunasNop}/${g.totalNop}',
              color1: Colors.green.shade400,
              color2: Colors.green.shade700,
              isDark: isDark,
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
            child: _renderHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasPct,
              maxVal: 100.0,
              labelRight: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
              subRight: (g) => '${g.lunasNop}/${g.totalNop} objek',
              color1: Colors.green.shade400,
              color2: Colors.green.shade700,
              isDark: isDark,
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
            child: _renderDonutTwoSlice(
              achievedPct: overallPct,
              achievedLabel: 'Sudah Lunas',
              remainingLabel: 'Sisa Target',
              achievedColor: Colors.green.shade600,
              remainingColor: Colors.grey.shade400,
              centerLabel: '${overallPct.toStringAsFixed(1)}%',
              centerSub: 'TERCAPAI',
              isDark: isDark,
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
          child: _buildDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Total Objek',
            col3: 'Objek Lunas',
            col4: '% Capaian',
            col2Val: (g) => '${g.totalNop}',
            col3Val: (g) => '${g.lunasNop}',
            col4Val: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
            isDark: isDark,
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
    ColorScheme colorScheme,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.belumBayarNominal.toDouble(),
    );
    if (groups.isEmpty) return _buildEmptyCard();

    final showBatang = _selectedStyle == ChartStyle.batang || _selectedStyle == ChartStyle.semua;
    final showBar = _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie = _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

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
            child: _renderColumnBars(
              groups: groups,
              valueExtractor: (g) => g.belumBayarNominal.toDouble(),
              maxVal: groups.map((g) => g.belumBayarNominal.toDouble()).fold(0.0, math.max),
              topLabelExtractor: (g) => 'Rp ${formatShortRupiah(g.belumBayarNominal)}',
              subLabelExtractor: (g) => '${g.belumBayarNop} objek',
              color1: Colors.orange.shade400,
              color2: Colors.deepOrange.shade700,
              isDark: isDark,
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
            child: _renderHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.belumBayarNominal.toDouble(),
              maxVal: groups.map((g) => g.belumBayarNominal.toDouble()).fold(0.0, math.max),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.belumBayarNominal)}',
              subRight: (g) => '${g.belumBayarNop} objek belum lunas',
              color1: Colors.orange.shade400,
              color2: Colors.deepOrange.shade600,
              isDark: isDark,
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
            child: _renderPieChart(
              slices: _makeSlices(groups, (g) => g.belumBayarNominal.toDouble(), totalBelumBayarNominal.toDouble()),
              centerLabel: 'Rp ${formatShortRupiah(totalBelumBayarNominal)}',
              centerSub: 'BELUM BAYAR',
              centerColor: Colors.orange,
              isDark: isDark,
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
          child: _buildDetailTableContent(
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
    ColorScheme colorScheme,
  ) {
    final groups = _groupData(
      records,
      hasMultiDusun: hasMultiDusun,
      sortValueFn: (g) => g.lunasNop.toDouble(),
    );
    if (groups.isEmpty) return _buildEmptyCard();

    final showBatang = _selectedStyle == ChartStyle.batang || _selectedStyle == ChartStyle.semua;
    final showBar = _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie = _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

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
            child: _renderColumnBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNop.toDouble(),
              maxVal: groups.map((g) => g.lunasNop.toDouble()).fold(0.0, math.max),
              topLabelExtractor: (g) => '${g.lunasNop} objek',
              subLabelExtractor: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              color1: Colors.blue.shade400,
              color2: Colors.blue.shade800,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (showBar) ...[
          _buildCollapsibleSectionCard(
            sectionKey: 'bar',
            icon: Icons.align_horizontal_left_rounded,
            title: 'Diagram Mendatar: Urutan Objek Lunas',
            subtitle: 'Urutan wilayah berdasarkan jumlah warga yang sudah bayar',
            badgeText: _sortMode.label,
            accentColor: Colors.blue,
            isDark: isDark,
            groups: groups,
            child: _renderHorizontalBars(
              groups: groups,
              valueExtractor: (g) => g.lunasNop.toDouble(),
              maxVal: groups.map((g) => g.lunasNop.toDouble()).fold(0.0, math.max),
              labelRight: (g) => '${g.lunasNop} objek',
              subRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              color1: Colors.blue.shade400,
              color2: Colors.blue.shade700,
              isDark: isDark,
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
            child: _renderPieChart(
              slices: _makeSlices(groups, (g) => g.lunasNop.toDouble(), totalSudahBayarCount.toDouble()),
              centerLabel: '$totalSudahBayarCount',
              centerSub: 'OBJEK LUNAS',
              centerColor: Colors.blue,
              isDark: isDark,
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
          child: _buildDetailTableContent(
            groups: groups,
            col1: 'Wilayah',
            col2: 'Total Objek',
            col3: 'Objek Lunas',
            col4: 'Uang Masuk',
            col2Val: (g) => '${g.totalNop}',
            col3Val: (g) => '${g.lunasNop}',
            col4Val: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB: TREN PEMBAYARAN TIAP BULAN (JAN - DES)
  // =========================================================================
  List<_GroupInfo> _buildMonthGroups(List<BlokRecord> records) {
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
    final monthlyNominal = List<int>.filled(12, 0);
    final monthlyCount = List<int>.filled(12, 0);

    for (final r in records) {
      if (r.isPaid && r.tanggalBayar.isNotEmpty) {
        final dt = _parsePaymentDate(r.tanggalBayar);
        if (dt != null && dt.month >= 1 && dt.month <= 12) {
          monthlyNominal[dt.month - 1] += r.jumlahPbbValue;
          monthlyCount[dt.month - 1]++;
        }
      }
    }

    final totalDatedNominal = monthlyNominal.fold<int>(0, (sum, v) => sum + v);
    final totalDatedCount = monthlyCount.fold<int>(0, (sum, v) => sum + v);

    final monthGroups = <_GroupInfo>[];
    for (int i = 0; i < 12; i++) {
      final nom = monthlyNominal[i];
      final cnt = monthlyCount[i];
      final pct = totalDatedNominal > 0 ? (nom / totalDatedNominal * 100) : 0.0;
      monthGroups.add(_GroupInfo(
        label: monthNames[i],
        totalNop: cnt,
        lunasNop: cnt,
        belumBayarNop: 0,
        lunasNominal: nom,
        belumBayarNominal: 0,
        totalNominal: nom,
        lunasPct: pct,
        lunasNopPct: totalDatedCount > 0 ? (cnt / totalDatedCount * 100) : 0.0,
      ));
    }
    return monthGroups;
  }

  Widget _buildTrenBulananSection(
    List<BlokRecord> records,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
    final monthGroups = _buildMonthGroups(records);
    final monthlyNominal = monthGroups.map((g) => g.lunasNominal).toList();
    final totalDatedNominal = monthlyNominal.fold<int>(0, (sum, v) => sum + v);
    final maxMonthVal = monthlyNominal.fold<int>(0, math.max);

    final showBatang = _selectedStyle == ChartStyle.batang || _selectedStyle == ChartStyle.semua;
    final showBar = _selectedStyle == ChartStyle.bar || _selectedStyle == ChartStyle.semua;
    final showPie = _selectedStyle == ChartStyle.pie || _selectedStyle == ChartStyle.semua;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Grafik Perkembangan Bulanan
        _buildCollapsibleSectionCard(
          sectionKey: 'kurva',
          icon: Icons.show_chart_rounded,
          title: 'Grafik Perkembangan Pembayaran Bulanan',
          subtitle: 'Alur penerimaan pembayaran PBB dari Januari sampai Desember',
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
                    final idx = (localPos.dx / stepX).round().clamp(0, monthGroups.length - 1);
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
                        painter: _GrassLineAreaPainter(
                          data: monthlyNominal,
                          maxVal: maxMonthVal > 0 ? maxMonthVal : 1,
                          progress: _animation.value,
                          lineColor: Colors.purple.shade600,
                          isDark: isDark,
                          selectedIndex: selIndex != null && selIndex >= 0 ? selIndex : null,
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
                          _selectedItemLabel = _selectedItemLabel == m ? null : m;
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                        child: Text(
                          m,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: _selectedItemLabel == m ? FontWeight.bold : FontWeight.w600,
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
            child: _renderColumnBars(
              groups: monthGroups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: maxMonthVal.toDouble(),
              topLabelExtractor: (g) => g.lunasNominal > 0 ? formatShortRupiah(g.lunasNominal) : '-',
              subLabelExtractor: (g) => g.lunasNop > 0 ? '${g.lunasNop} objek' : '',
              color1: Colors.purple.shade400,
              color2: Colors.purple.shade800,
              isDark: isDark,
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
            child: _renderHorizontalBars(
              groups: monthGroups,
              valueExtractor: (g) => g.lunasNominal.toDouble(),
              maxVal: maxMonthVal.toDouble(),
              labelRight: (g) => 'Rp ${formatShortRupiah(g.lunasNominal)}',
              subRight: (g) => '${g.lunasNop} objek (${g.lunasPct.toStringAsFixed(1)}%)',
              color1: Colors.purple.shade400,
              color2: Colors.indigo.shade600,
              isDark: isDark,
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
            child: _renderPieChart(
              slices: _makeSlices(
                monthGroups.where((g) => g.lunasNominal > 0).toList(),
                (g) => g.lunasNominal.toDouble(),
                totalDatedNominal.toDouble(),
              ),
              centerLabel: 'Rp ${formatShortRupiah(totalDatedNominal)}',
              centerSub: 'TOTAL BULANAN',
              centerColor: Colors.purple,
              isDark: isDark,
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
          child: _buildDetailTableContent(
            groups: monthGroups,
            col1: 'Bulan',
            col2: 'Objek Lunas',
            col3: 'Nominal (Rp)',
            col4: '% Porsi',
            col2Val: (g) => '${g.lunasNop}',
            col3Val: (g) => formatShortRupiah(g.lunasNominal),
            col4Val: (g) => '${g.lunasPct.toStringAsFixed(1)}%',
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // HELPER RENDERING DIAGRAM BATANG (COLUMN) — INTERAKTIF
  // =========================================================================
  Widget _renderColumnBars({
    required List<_GroupInfo> groups,
    required double Function(_GroupInfo) valueExtractor,
    required double maxVal,
    required String Function(_GroupInfo) topLabelExtractor,
    required String Function(_GroupInfo) subLabelExtractor,
    required Color color1,
    required Color color2,
    required bool isDark,
  }) {
    final effectiveMax = maxVal > 0 ? maxVal : 1.0;
    return SizedBox(
      height: 230,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isScrollable = groups.length > 7;
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final g in groups) ...[
                () {
                  final isSelected = _selectedItemLabel == g.label;
                  final itemWidget = InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedItemLabel = isSelected ? null : g.label;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: isScrollable ? math.max(64.0, constraints.maxWidth / 7.0) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color1.withValues(alpha: isDark ? 0.2 : 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: color1, width: 1.2)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            topLabelExtractor(g),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : color2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subLabelExtractor(g).isNotEmpty)
                            Text(
                              subLabelExtractor(g),
                              style: TextStyle(
                                fontSize: 8.5,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 5),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final val = valueExtractor(g);
                                  final heightRatio = (val / effectiveMax).clamp(0.0, 1.0);
                                  final barHeight = math.max(4.0, c.maxHeight * heightRatio * _animation.value);

                                  return Container(
                                    width: isScrollable ? 26 : 28,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [color1, color2],
                                      ),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color2.withValues(alpha: isSelected ? 0.45 : 0.22),
                                          blurRadius: isSelected ? 6 : 3,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            g.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? color1 : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );

                  if (!isScrollable) {
                    return Expanded(child: itemWidget);
                  }
                  return itemWidget;
                }(),
              ],
            ],
          );

          if (isScrollable) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }

  // =========================================================================
  // HELPER RENDERING DIAGRAM MENDATAR — INTERAKTIF & PERINGKAT
  // =========================================================================
  Widget _renderHorizontalBars({
    required List<_GroupInfo> groups,
    required double Function(_GroupInfo) valueExtractor,
    required double maxVal,
    required String Function(_GroupInfo) labelRight,
    required String Function(_GroupInfo) subRight,
    required Color color1,
    required Color color2,
    required bool isDark,
    bool useSemanticPercentageColor = false,
    bool showRankNumber = true,
  }) {
    final effectiveMax = maxVal > 0 ? maxVal : 1.0;
    return Column(
      children: [
        for (int idx = 0; idx < groups.length; idx++) ...[
          Builder(
            builder: (context) {
              final g = groups[idx];
              final isSelected = _selectedItemLabel == g.label;

              Color barC1 = color1;
              Color barC2 = color2;
              if (useSemanticPercentageColor) {
                if (g.lunasPct >= 75) {
                  barC1 = Colors.green.shade400;
                  barC2 = Colors.green.shade700;
                } else if (g.lunasPct >= 50) {
                  barC1 = Colors.teal.shade400;
                  barC2 = Colors.teal.shade700;
                } else if (g.lunasPct >= 25) {
                  barC1 = Colors.amber.shade500;
                  barC2 = Colors.orange.shade700;
                } else {
                  barC1 = Colors.orange.shade400;
                  barC2 = Colors.red.shade600;
                }
              }

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedItemLabel = isSelected ? null : g.label;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 7.5, horizontal: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? barC1.withValues(alpha: isDark ? 0.18 : 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (showRankNumber && _sortMode != GrafikSortMode.wilayah) ...[
                        Container(
                          width: 22,
                          height: 20,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: idx < 3
                                ? barC2.withValues(alpha: 0.2)
                                : (isDark ? Colors.white10 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '#${idx + 1}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: idx < 3 ? barC2 : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(
                        width: 68,
                        child: Text(
                          g.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              height: 18,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final val = valueExtractor(g);
                                final widthRatio = (val / effectiveMax).clamp(0.0, 1.0);
                                final barW = constraints.maxWidth * widthRatio * _animation.value;
                                return Container(
                                  height: 18,
                                  width: math.max(0, barW),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [barC1, barC2]),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 98,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              labelRight(g),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              subRight(g),
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // HELPER RENDERING DIAGRAM LINGKARAN — INTERAKTIF DENGAN LEGENDA KLIK
  // =========================================================================
  Widget _renderPieChart({
    required List<_PieSliceInfo> slices,
    required String centerLabel,
    required String centerSub,
    required MaterialColor centerColor,
    required bool isDark,
  }) {
    if (slices.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: Text('Belum ada data untuk ditampilkan.')),
      );
    }

    final selectedSlice = slices.where((s) => s.label == _selectedItemLabel).firstOrNull;
    final activeCenterLabel = selectedSlice != null
        ? '${(selectedSlice.ratio * 100).toStringAsFixed(1)}%'
        : centerLabel;
    final activeCenterSub = selectedSlice != null
        ? selectedSlice.label.toUpperCase()
        : centerSub;

    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final center = const Offset(75, 75);
            final dx = details.localPosition.dx - center.dx;
            final dy = details.localPosition.dy - center.dy;
            final dist = math.sqrt(dx * dx + dy * dy);

            // Jika mengetuk lingkaran luar donat pie chart (radius <= 75)
            if (dist <= 75) {
              if (dist < 26) {
                // Sentuhan di tengah: reset seleksi
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedItemLabel = null;
                });
                return;
              }

              // Hitung sudut sentuhan (dimulai dari -pi/2, searah jarum jam)
              final tapAngle = math.atan2(dy, dx);
              double angleFromTop = (tapAngle - (-math.pi / 2)) % (2 * math.pi);
              if (angleFromTop < 0) angleFromTop += 2 * math.pi;

              double accumulated = 0;
              for (final s in slices) {
                final sweep = 2 * math.pi * s.ratio;
                if (angleFromTop >= accumulated && angleFromTop < accumulated + sweep) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedItemLabel = _selectedItemLabel == s.label ? null : s.label;
                  });
                  return;
                }
                accumulated += sweep;
              }
            }
          },
          child: SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              painter: _ContributionPiePainter(
                slices: slices,
                selectedLabel: _selectedItemLabel,
                progress: _animation.value,
                isDark: isDark,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeCenterLabel,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: selectedSlice?.color ?? centerColor.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        activeCenterSub,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.7),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices.take(8)) ...[
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedItemLabel = _selectedItemLabel == s.label ? null : s.label;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.5, horizontal: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _selectedItemLabel == s.label ? FontWeight.bold : FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(s.ratio * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${formatShortRupiah(s.nominal.toInt())})',
                          style: TextStyle(
                            fontSize: 9,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (slices.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    '+ ${slices.length - 8} wilayah lainnya (lihat tabel di bawah)',
                    style: TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // HELPER RENDERING DIAGRAM LINGKARAN (CAPAIAN VS SISA)
  // =========================================================================
  Widget _renderDonutTwoSlice({
    required double achievedPct,
    required String achievedLabel,
    required String remainingLabel,
    required Color achievedColor,
    required Color remainingColor,
    required String centerLabel,
    required String centerSub,
    required bool isDark,
  }) {
    final safePct = achievedPct.clamp(0.0, 100.0);
    final ratio = safePct / 100.0;
    final slices = [
      _PieSliceInfo(label: achievedLabel, nominal: safePct, ratio: ratio, color: achievedColor),
      _PieSliceInfo(label: remainingLabel, nominal: 100.0 - safePct, ratio: 1.0 - ratio, color: remainingColor),
    ];

    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final center = const Offset(75, 75);
            final dx = details.localPosition.dx - center.dx;
            final dy = details.localPosition.dy - center.dy;
            final dist = math.sqrt(dx * dx + dy * dy);

            if (dist <= 75) {
              if (dist < 26) {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedItemLabel = null;
                });
                return;
              }

              final tapAngle = math.atan2(dy, dx);
              double angleFromTop = (tapAngle - (-math.pi / 2)) % (2 * math.pi);
              if (angleFromTop < 0) angleFromTop += 2 * math.pi;

              final achievedSweep = 2 * math.pi * ratio;
              HapticFeedback.selectionClick();
              setState(() {
                if (angleFromTop < achievedSweep) {
                  _selectedItemLabel = _selectedItemLabel == achievedLabel ? null : achievedLabel;
                } else {
                  _selectedItemLabel = _selectedItemLabel == remainingLabel ? null : remainingLabel;
                }
              });
            }
          },
          child: SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              painter: _ContributionPiePainter(
                slices: slices,
                selectedLabel: _selectedItemLabel,
                progress: _animation.value,
                isDark: isDark,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: achievedColor,
                      ),
                    ),
                    Text(
                      centerSub,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTwoSliceLegend(
                color: achievedColor,
                label: achievedLabel,
                pct: '${safePct.toStringAsFixed(1)}%',
                desc: 'Sudah lunas dibayarkan',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildTwoSliceLegend(
                color: remainingColor,
                label: remainingLabel,
                pct: '${(100.0 - safePct).toStringAsFixed(1)}%',
                desc: 'Target yang belum tercapai',
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTwoSliceLegend({
    required Color color,
    required String label,
    required String pct,
    required String desc,
    required bool isDark,
  }) {
    final isSelected = _selectedItemLabel == label;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedItemLabel = isSelected ? null : label;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? color : null,
                        ),
                      ),
                      Text(pct, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                    ],
                  ),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 9, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // HELPER TABEL RINCIAN DATA (DI DALAM KARTU COLLAPSIBLE)
  // =========================================================================
  Widget _buildDetailTableContent({
    required List<_GroupInfo> groups,
    required String col1,
    required String col2,
    required String col3,
    required String col4,
    required String Function(_GroupInfo) col2Val,
    required String Function(_GroupInfo) col3Val,
    required String Function(_GroupInfo) col4Val,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(col1, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(col2, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text(col3, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(col4, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (int i = 0; i < groups.length; i++) ...[
          Builder(
            builder: (context) {
              final g = groups[i];
              final isSelected = _selectedItemLabel == g.label;
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedItemLabel = isSelected ? null : g.label;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _activeTab.accentColor.withValues(alpha: isDark ? 0.2 : 0.1)
                        : (i.isOdd ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey.shade50) : Colors.transparent),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          g.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(flex: 2, child: Text(col2Val(g), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                      Expanded(flex: 3, child: Text(col3Val(g), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text(col4Val(g), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Tidak ada data catatan blok untuk ditampilkan.')),
      ),
    );
  }

  // =========================================================================
  // LOGIKA PENGELOMPOKAN & PENGURUTAN DATA
  // - Untuk Desa (hasMultiDusun == true): default Semua Dusun (_groupByDusun)
  // - Untuk Dusun (hasMultiDusun == false): otomatis Semua Blok
  // =========================================================================
  List<_GroupInfo> _groupData(
    List<BlokRecord> records, {
    required bool hasMultiDusun,
    double Function(_GroupInfo)? sortValueFn,
    bool applySort = true,
  }) {
    final list = <_GroupInfo>[];

    // Hanya kelompokkan per Dusun apabila data memang skala Desa (multi-dusun)
    final effectiveGroupByDusun = hasMultiDusun && _groupByDusun && _drillDownDusun == null;

    if (effectiveGroupByDusun) {
      for (final dusun in dusunList) {
        final dBloks = dusun.bloks.toSet();
        final dRecs = records.where((r) => dBloks.contains(r.blok)).toList();
        if (dRecs.isEmpty) continue;

        final lunasRecs = dRecs.where((r) => r.isPaid).toList();
        final belumRecs = dRecs.where((r) => !r.isPaid).toList();

        final lunasNominal = lunasRecs.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
        final belumNominal = belumRecs.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
        final totalNominal = dRecs.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

        final lunasPct = totalNominal > 0 ? (lunasNominal / totalNominal * 100) : 0.0;
        final lunasNopPct = dRecs.isNotEmpty ? (lunasRecs.length / dRecs.length * 100) : 0.0;

        list.add(_GroupInfo(
          label: 'Dusun ${dusun.number}',
          totalNop: dRecs.length,
          lunasNop: lunasRecs.length,
          belumBayarNop: belumRecs.length,
          lunasNominal: lunasNominal,
          belumBayarNominal: belumNominal,
          totalNominal: totalNominal,
          lunasPct: lunasPct,
          lunasNopPct: lunasNopPct,
        ));
      }
    }

    if (list.isEmpty) {
      // Kelompokkan per Blok (default otomatis untuk tingkat Dusun, atau saat pilih Semua Blok / drill-down Dusun)
      final blokMap = <String, List<BlokRecord>>{};
      for (final r in records) {
        blokMap.putIfAbsent(r.blok, () => []).add(r);
      }
      final sortedBlokKeys = blokMap.keys.toList()..sort();

      for (final b in sortedBlokKeys) {
        final bRecs = blokMap[b]!;
        final lunasRecs = bRecs.where((r) => r.isPaid).toList();
        final belumRecs = bRecs.where((r) => !r.isPaid).toList();

        final lunasNominal = lunasRecs.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
        final belumNominal = belumRecs.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);
        final totalNominal = bRecs.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

        final lunasPct = totalNominal > 0 ? (lunasNominal / totalNominal * 100) : 0.0;
        final lunasNopPct = bRecs.isNotEmpty ? (lunasRecs.length / bRecs.length * 100) : 0.0;

        list.add(_GroupInfo(
          label: 'Blok ${int.tryParse(b) ?? b}',
          totalNop: bRecs.length,
          lunasNop: lunasRecs.length,
          belumBayarNop: belumRecs.length,
          lunasNominal: lunasNominal,
          belumBayarNominal: belumNominal,
          totalNominal: totalNominal,
          lunasPct: lunasPct,
          lunasNopPct: lunasNopPct,
        ));
      }
    }

    if (applySort && sortValueFn != null && _sortMode != GrafikSortMode.wilayah) {
      if (_sortMode == GrafikSortMode.tertinggi) {
        list.sort((a, b) => sortValueFn(b).compareTo(sortValueFn(a)));
      } else if (_sortMode == GrafikSortMode.terendah) {
        list.sort((a, b) => sortValueFn(a).compareTo(sortValueFn(b)));
      }
    }

    return list;
  }

  List<_PieSliceInfo> _makeSlices(
    List<_GroupInfo> groups,
    double Function(_GroupInfo) valFn,
    double totalVal,
  ) {
    const colors = [
      Colors.teal,
      Colors.indigo,
      Colors.amber,
      Colors.purple,
      Colors.cyan,
      Colors.deepOrange,
      Colors.blue,
      Colors.green,
      Colors.pink,
      Colors.lime,
      Colors.brown,
      Colors.blueGrey,
    ];
    final slices = <_PieSliceInfo>[];
    for (int i = 0; i < groups.length; i++) {
      final g = groups[i];
      final val = valFn(g);
      if (val <= 0) continue;
      final ratio = totalVal > 0 ? (val / totalVal) : 0.0;
      slices.add(_PieSliceInfo(
        label: g.label,
        nominal: val,
        ratio: ratio,
        color: colors[i % colors.length],
      ));
    }
    return slices;
  }
}

// ===========================================================================
// DATA HELPER CLASSES
// ===========================================================================
class _GroupInfo {
  final String label;
  final int totalNop;
  final int lunasNop;
  final int belumBayarNop;
  final int lunasNominal;
  final int belumBayarNominal;
  final int totalNominal;
  final double lunasPct;
  final double lunasNopPct;

  const _GroupInfo({
    required this.label,
    required this.totalNop,
    required this.lunasNop,
    required this.belumBayarNop,
    required this.lunasNominal,
    required this.belumBayarNominal,
    required this.totalNominal,
    required this.lunasPct,
    required this.lunasNopPct,
  });
}

class _PieSliceInfo {
  final String label;
  final double nominal;
  final double ratio;
  final Color color;

  const _PieSliceInfo({
    required this.label,
    required this.nominal,
    required this.ratio,
    required this.color,
  });
}

class _StatItem {
  final String label;
  final String value;
  final String sub;
  final MaterialColor color;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });
}

// ===========================================================================
// CUSTOM PAINTERS: DIAGRAM LINGKARAN & GRAFIK PERKEMBANGAN BULANAN
// ===========================================================================
class _ContributionPiePainter extends CustomPainter {
  final List<_PieSliceInfo> slices;
  final String? selectedLabel;
  final double progress;
  final bool isDark;

  _ContributionPiePainter({
    required this.slices,
    this.selectedLabel,
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    const baseStrokeWidth = 22.0;

    final bgPaint = Paint()
      ..color = isDark ? Colors.grey.shade800 : Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStrokeWidth;
    canvas.drawCircle(center, radius - baseStrokeWidth / 2, bgPaint);

    double startAngle = -math.pi / 2;
    for (final slice in slices) {
      final isSelected = selectedLabel != null && selectedLabel == slice.label;
      final strokeW = isSelected ? baseStrokeWidth + 5.0 : baseStrokeWidth;
      final sweepAngle = 2 * math.pi * slice.ratio * progress;

      final paint = Paint()
        ..color = selectedLabel == null || isSelected
            ? slice.color
            : slice.color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - baseStrokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _ContributionPiePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.slices != slices ||
        oldDelegate.selectedLabel != selectedLabel;
  }
}

class _GrassLineAreaPainter extends CustomPainter {
  final List<int> data;
  final int maxVal;
  final double progress;
  final Color lineColor;
  final bool isDark;
  final int? selectedIndex;

  _GrassLineAreaPainter({
    required this.data,
    required this.maxVal,
    required this.progress,
    required this.lineColor,
    required this.isDark,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final n = data.length;
    final w = size.width;
    final h = size.height;
    final stepX = w / (n - 1);

    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final ratio = maxVal > 0 ? (data[i] / maxVal) : 0.0;
      final y = h - (ratio * h * 0.85 * progress) - 8;
      points.add(Offset(x, y));
    }

    final gridPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.black12
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 3; i++) {
      final gy = h * (i / 4);
      canvas.drawLine(Offset(0, gy), Offset(w, gy), gridPaint);
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cpX = (p0.dx + p1.dx) / 2;
      path.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.40 * progress),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Garis pandu & sorotan khusus saat salah satu bulan disentuh
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < points.length) {
      final sp = points[selectedIndex!];
      final guidePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(sp.dx, 0), Offset(sp.dx, h), guidePaint);

      final haloPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(sp, 11.0, haloPaint);
    }

    final dotPaint = Paint()..color = lineColor;
    final dotInner = Paint()..color = isDark ? Colors.black : Colors.white;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isPtSelected = selectedIndex == i;
      final outerR = isPtSelected ? 6.0 : 4.0;
      final innerR = isPtSelected ? 3.0 : 2.0;
      canvas.drawCircle(p, outerR, isPtSelected ? (Paint()..color = Colors.amber.shade400) : dotPaint);
      canvas.drawCircle(p, innerR, dotInner);
    }
  }

  @override
  bool shouldRepaint(covariant _GrassLineAreaPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.data != data ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
