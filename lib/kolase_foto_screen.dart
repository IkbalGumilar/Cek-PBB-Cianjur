import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'blok_data_store.dart';
import 'dkhp_package_helper.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'image_crop_helper.dart';
import 'kolase_foto_exporter.dart';
import 'unity_lerp_widgets.dart';

/// Layar untuk membuat dan mencetak kolase foto dokumentasi penyerahan SPPT.
///
/// Fitur:
/// 1. Tampilan antarmuka ala *Photo Grid Merger* dengan canvas preview gelap.
/// 2. Pilihan template grid: 1x2, 2x1, 2x2, 2x3, 3x2, 3x3.
/// 3. Cetak 1 Wilayah Penuh atau Per-Blok tertentu.
/// 4. Judul HANYA muncul di halaman pertama di bagian paling atas.
/// 5. Dokumen PDF ukuran standar F4 (Folio).
/// 6. Dapat dicetak langsung, dibagikan, dan disimpan ke `Android/media/id.cianjur.pbb/files/`.
class KolaseFotoScreen extends StatefulWidget {
  final String? initialBlok;
  final List<String> bloks;

  const KolaseFotoScreen({
    super.key,
    this.initialBlok,
    this.bloks = const [],
  });

  @override
  State<KolaseFotoScreen> createState() => _KolaseFotoScreenState();
}

class _KolaseFotoScreenState extends State<KolaseFotoScreen> {
  late String _selectedBlok;
  KolaseGridTemplate _template = KolaseGridTemplate.grid3x3;
  bool _loading = true;
  bool _busyExport = false;
  String _busyExportMessage = 'Menyiapkan dokumen PDF F4...';

  final List<File> _photoFiles = [];
  final List<Uint8List> _photoBytes = [];

  final PageController _pageController = PageController();
  int _currentPreviewPage = 0;

  @override
  void initState() {
    super.initState();
    _selectedBlok = (widget.initialBlok == null ||
            widget.initialBlok!.isEmpty ||
            widget.initialBlok == 'Semua' ||
            widget.initialBlok == 'Semua Blok')
        ? 'Semua'
        : widget.initialBlok!;
    _loadPhotos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Memuat foto-foto dokumentasi dari BlokDataStore lokal sesuai blok yang dipilih
  Future<void> _loadPhotos() async {
    setState(() => _loading = true);
    _photoFiles.clear();
    _photoBytes.clear();

    try {
      final records = await BlokDataStore.instance.loadAll();
      final photosDir = await DhkpPackageHelper.photosDirectory();
      final photoNames = await DhkpPackageHelper.refreshPhotoNamesCache();

      final filteredRecords = (_selectedBlok == 'Semua')
          ? records
          : records.where((r) => r.blok == _selectedBlok).toList();

      final seenFiles = <String>{};

      for (final r in filteredRecords) {
        final photo = DhkpPackageHelper.findPhotoForNopSync(
          r.nop,
          customFileName: r.namaFoto,
          photosDir: photosDir,
          cachedNames: photoNames,
        );

        if (photo != null && await photo.exists()) {
          final canonical = photo.path.toLowerCase();
          if (!seenFiles.contains(canonical)) {
            seenFiles.add(canonical);
            _photoFiles.add(photo);
            try {
              final bytes = await photo.readAsBytes();
              if (bytes.isNotEmpty) {
                final squareBytes = ImageCropHelper.cropToSquare(bytes);
                _photoBytes.add(squareBytes);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loading = false;
        _currentPreviewPage = 0;
      });
    }
  }



  /// Nama berkas PDF yang rapi
  String get _pdfFileName {
    final cleanBlok = _selectedBlok == 'Semua' ? 'semua_wilayah' : 'blok_$_selectedBlok';
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'Dokumentasi_SPPT_${cleanBlok}_$stamp.pdf';
  }

  /// Membuat Uint8List PDF dokumen F4
  Future<Uint8List> _generatePdfBytes() {
    return KolaseFotoExporter.buildPdf(
      imageBytesList: _photoBytes,
      template: _template,
      blok: _selectedBlok == 'Semua' ? null : _selectedBlok,
    );
  }

  /// Buka layar pratinjau lengkap (PdfPreview / Print / Share)
  Future<void> _bukaPratinjauLengkap() async {
    if (_photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada foto dokumentasi untuk dicetak.')),
      );
      return;
    }

    setState(() {
      _busyExport = true;
      _busyExportMessage = 'Menyusun pratinjau kolase PDF F4...';
    });
    try {
      final pdfBytes = await _generatePdfBytes();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: _pdfFileName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat dokumen PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  /// Simpan berkas PDF ke folder Android/media/id.cianjur.pbb/files/
  Future<void> _simpanKeMedia() async {
    if (_photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada foto dokumentasi untuk disimpan.')),
      );
      return;
    }

    setState(() {
      _busyExport = true;
      _busyExportMessage = 'Menyimpan dokumen PDF F4 ke perangkat...';
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdfBytes = await _generatePdfBytes();
      final savedPath = await DownloadHelper.saveBytes(
        pdfBytes,
        _pdfFileName,
        subfolder: 'files',
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Dokumen PDF berhasil disimpan di:\n$savedPath'),
          backgroundColor: Colors.teal[800],
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan dokumen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  /// Cetak langsung via dialog printer
  Future<void> _cetakLangsung() async {
    if (_photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada foto dokumentasi untuk dicetak.')),
      );
      return;
    }

    setState(() {
      _busyExport = true;
      _busyExportMessage = 'Menyiapkan dokumen F4 untuk dicetak...';
    });
    try {
      final pdfBytes = await _generatePdfBytes();
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: _pdfFileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka printer: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  /// Bagikan dokumen PDF ke WhatsApp / aplikasi lain
  Future<void> _bagikanPdf() async {
    if (_photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada foto dokumentasi untuk dibagikan.')),
      );
      return;
    }

    setState(() {
      _busyExport = true;
      _busyExportMessage = 'Menyiapkan dokumen PDF F4 untuk dibagikan...';
    });
    try {
      final pdfBytes = await _generatePdfBytes();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: _pdfFileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan dokumen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCapacity = _template.capacity;
    final totalPages = _photoBytes.isEmpty ? 1 : (_photoBytes.length / totalCapacity).ceil();
    final judul = KolaseFotoExporter.formatJudul(
      blok: _selectedBlok == 'Semua' ? null : _selectedBlok,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E), // Dark theme canvas seperti screenshot
      appBar: AppBar(
        backgroundColor: const Color(0xFF262626),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Gabungkan Beberapa Gambar',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          // Filter Wilayah / Blok
          PopupMenuButton<String>(
            tooltip: 'Pilih Cakupan Blok / Wilayah',
            icon: const Icon(Icons.filter_list_rounded),
            initialValue: _selectedBlok,
            onSelected: (val) {
              if (val != _selectedBlok) {
                setState(() => _selectedBlok = val);
                _loadPhotos();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'Semua',
                child: Text('Semua Blok (1 Wilayah Full)'),
              ),
              const PopupMenuDivider(),
              for (final b in widget.bloks)
                PopupMenuItem(
                  value: b,
                  child: Text('Blok $b'),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang Foto Dokumentasi',
            onPressed: _busyExport ? null : _loadPhotos,
          ),
        ],
      ),
      body: Column(
        children: [
          // Sub-header informasi cakupan & jumlah foto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF2B2B2B),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedBlok == 'Semua'
                        ? '1 Wilayah Full (Semua Blok)'
                        : 'Wilayah: Blok $_selectedBlok',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_photoBytes.length} Foto • Kertas F4',
                    style: TextStyle(
                      color: Colors.teal.shade200,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SmoothActivityBanner(
            isActive: _busyExport,
            message: _busyExportMessage,
            icon: Icons.picture_as_pdf_outlined,
            accentColor: Colors.tealAccent.shade700,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          ),

          // Area Canvas Preview (Kertas F4 di background gelap)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _loading
                  ? const SmoothLoadingCard(
                      key: ValueKey('kolase-loading'),
                      isDarkCanvas: true,
                      icon: Icons.auto_awesome_mosaic_outlined,
                      title: 'Memuat Gambar Dokumentasi',
                      subtitle:
                          'Menyiapkan & memotong gambar dokumentasi ke rasio persegi 1:1...',
                      badgeText: 'Memuat gambar dokumentasi',
                    )
                  : _photoBytes.isEmpty
                      ? Center(
                          key: const ValueKey('kolase-empty'),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.photo_library_outlined,
                                  size: 64,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedBlok == 'Semua'
                                      ? 'Belum ada foto dokumentasi di semua blok.'
                                      : 'Belum ada foto dokumentasi di Blok $_selectedBlok.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Kolase memuat gambar dokumentasi petugas yang diambil di daftar catatan blok.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                const SizedBox(height: 20),
                                OutlinedButton.icon(
                                  onPressed: _loadPhotos,
                                  icon: const Icon(Icons.refresh, color: Colors.tealAccent),
                                  label: const Text(
                                    'Muat Ulang Foto',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.teal),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          key: const ValueKey('kolase-content'),
                          children: [
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: totalPages,
                              onPageChanged: (idx) {
                                setState(() => _currentPreviewPage = idx);
                              },
                              itemBuilder: (context, pageIdx) {
                                return _buildF4PagePreview(
                                  pageIndex: pageIdx,
                                  totalPages: totalPages,
                                  judul: judul,
                                );
                              },
                            ),
                          ),
                          // Indikator Halaman
                          if (totalPages > 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left, color: Colors.white70),
                                    onPressed: _currentPreviewPage > 0
                                        ? () => _pageController.previousPage(
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            )
                                        : null,
                                  ),
                                  Text(
                                    'Halaman ${_currentPreviewPage + 1} dari $totalPages',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, color: Colors.white70),
                                    onPressed: _currentPreviewPage < totalPages - 1
                                        ? () => _pageController.nextPage(
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
            ),
          ),

          // Bagian Bawah: Selector Template Grid & Action Bar
          _buildBottomToolbar(),
        ],
      ),
    );
  }

  /// Membuat pratinjau lembar kertas F4
  Widget _buildF4PagePreview({
    required int pageIndex,
    required int totalPages,
    required String judul,
  }) {
    final capacity = _template.capacity;
    final startIndex = pageIndex * capacity;
    final endIndex = (startIndex + capacity > _photoBytes.length)
        ? _photoBytes.length
        : startIndex + capacity;
    final pageImages = _photoBytes.sublist(startIndex, endIndex);

    final isFirstPage = pageIndex == 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AspectRatio(
          aspectRatio: 21.5 / 33.0, // Rasio Kertas F4 (Folio)
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Judul HANYA pada halaman pertama di paling atas
                if (isFirstPage) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      judul,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                // Area Grid Foto
                Expanded(
                  child: _buildPreviewGrid(
                    images: pageImages,
                    rows: _template.rows,
                    cols: _template.cols,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Grid foto untuk pratinjau lembar kertas
  Widget _buildPreviewGrid({
    required List<Uint8List> images,
    required int rows,
    required int cols,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows; r++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < cols; c++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Builder(
                        builder: (_) {
                          final idx = r * cols + c;
                          if (idx < images.length) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 0.5,
                                ),
                              ),
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: Image.memory(
                                    images[idx],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Toolbar bawah: Template cards + tombol aksi simpan/cetak/bagikan
  Widget _buildBottomToolbar() {
    return Container(
      color: const Color(0xFF262626),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Baris Template Grid Cards (1x2, 2x1, 2x2, 2x3, 3x2, 3x3)
            Container(
              height: 84,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final t in KolaseGridTemplate.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildTemplateCard(t),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),

            // Baris Tombol Aksi: Simpan ke Media, Cetak, Bagikan, & Centang Hijau
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  // Simpan ke Android/media/files
                  OutlinedButton.icon(
                    onPressed: _busyExport ? null : _simpanKeMedia,
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: const Text('Simpan Media'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Cetak Langsung
                  OutlinedButton.icon(
                    onPressed: _busyExport ? null : _cetakLangsung,
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Cetak'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Bagikan PDF
                  IconButton(
                    onPressed: _busyExport ? null : _bagikanPdf,
                    icon: const Icon(Icons.share_outlined, color: Colors.white70),
                    tooltip: 'Bagikan Dokumen PDF',
                  ),

                  const Spacer(),

                  // Tombol Centang Hijau Besar (Selesai / Buka Pratinjau Lengkap)
                  FloatingActionButton.small(
                    onPressed: _busyExport ? null : _bukaPratinjauLengkap,
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    tooltip: 'Lihat Pratinjau & Selesai',
                    child: _busyExport
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 22),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu thumbnail template grid
  Widget _buildTemplateCard(KolaseGridTemplate template) {
    final isSelected = _template == template;
    return InkWell(
      onTap: () {
        if (_template != template) {
          setState(() {
            _template = template;
            _currentPreviewPage = 0;
          });
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 58,
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.withAlpha(50) : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.tealAccent : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Expanded(
              child: _buildMiniGridThumbnail(template.rows, template.cols, isSelected),
            ),
            const SizedBox(height: 2),
            Text(
              template.label,
              style: TextStyle(
                color: isSelected ? Colors.tealAccent : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Miniatur diagram grid kotak-kotak untuk kartu template
  Widget _buildMiniGridThumbnail(int rows, int cols, bool isSelected) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.teal.shade200 : Colors.white60,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
