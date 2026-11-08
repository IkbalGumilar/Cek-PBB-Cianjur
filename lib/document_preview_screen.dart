import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'app_security_service.dart';
import 'base_table_exporter.dart';

/// Fitur utama:
/// 1. Tampilan antarmuka Material 3 yang bersih, minimalis, dan imersif.
/// 2. Mode layar penuh (Immersive Mode) untuk kenyamanan membaca tanpa distraksi.
/// 3. Navigasi halaman, pinch-to-zoom halus, cetak langsung ke printer, bagikan berkas,
///    dan simpan ke folder dokumen.
/// 4. Validasi keamanan (Security First): verifikasi magic bytes `%PDF-` dan batas ukuran berkas.
/// 5. Kemampuan membuka berkas PDF dari memori (bytes), berkas lokal (File), maupun
///    pemilihan berkas lewat File Picker.
/// 6. Mode Kotak Pasir (Sandboxed): Jika dibuka dari aplikasi eksternal (WhatsApp/File Manager),
///    layar ini dapat dibaca tanpa membuka kunci aplikasi, dan langsung menutup kembali
///    secara aman saat pengguna menekan tombol kembali.
class DocumentPreviewScreen extends StatefulWidget {
  final Uint8List? pdfBytes;
  final File? pdfFile;
  final String fileName;
  final bool isExternal;

  const DocumentPreviewScreen({
    super.key,
    this.pdfBytes,
    this.pdfFile,
    required this.fileName,
    this.isExternal = false,
  }) : assert(
         pdfBytes != null || pdfFile != null,
         'Salah satu dari pdfBytes atau pdfFile wajib disediakan.',
       );

  /// Batas ukuran maksimal berkas PDF yang aman diproses dalam memori (150 MB).
  static const int maxSafePdfSizeBytes = 150 * 1024 * 1024;

  /// Memeriksa header magic bytes `%PDF-` untuk memastikan berkas benar-benar format PDF.
  static bool hasPdfHeader(List<int> bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2D; // -
  }

  /// Membuka berkas [File] PDF eksternal secara aman dan menampilkannya di pembaca.
  static Future<void> openPdfFile(
    BuildContext context,
    File file, {
    String? title,
    bool isExternal = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await file.exists()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Berkas PDF tidak ditemukan atau sudah dipindahkan.'),
          ),
        );
        return;
      }

      final fileSize = await file.length();
      if (fileSize > maxSafePdfSizeBytes) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Ukuran berkas PDF terlalu besar (maksimal 150 MB).'),
          ),
        );
        return;
      }

      // Validasi magic bytes sebelum dimuat
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(5);
      await raf.close();

      if (!hasPdfHeader(header)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Format berkas tidak valid atau bukan dokumen PDF asli.',
            ),
          ),
        );
        return;
      }

      final fileName = title ?? file.uri.pathSegments.last;
      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfFile: file,
            fileName: fileName,
            isExternal: isExternal,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Gagal membuka dokumen PDF: $e')),
        );
      }
    }
  }

  /// Membuka dialog pemilih berkas untuk memilih dan membaca PDF lokal perangkat.
  static Future<void> pickAndOpenPdf(BuildContext context) async {
    try {
      AppSecurityService.instance.setTemporaryLockBypass(true);
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (files.isEmpty || files.first.path == null) return;

      final path = files.first.path!;
      final file = File(path);
      if (!context.mounted) return;
      await openPdfFile(context, file, title: files.first.name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memilih berkas PDF: $e')));
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        AppSecurityService.instance.setTemporaryLockBypass(false);
      });
    }
  }

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

/// ScrollPhysics khusus dokumen PDF desktop:
/// Menahan scroll dokumen saat tombol Ctrl / Command ditekan agar gestur scroll mouse
/// dialihkan sepenuhnya untuk pembesaran/pengecilan (zoom in/out).
class DesktopPdfScrollPhysics extends ClampingScrollPhysics {
  const DesktopPdfScrollPhysics({super.parent});

  @override
  DesktopPdfScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DesktopPdfScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    return super.shouldAcceptUserOffset(position);
  }
}

class _PdfSearchMatch {
  final int pageIndex;
  final String text;
  final Rect bounds;
  final Rect normalizedBounds;
  final String snippet;

  const _PdfSearchMatch({
    required this.pageIndex,
    required this.text,
    required this.bounds,
    required this.normalizedBounds,
    required this.snippet,
  });
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  Uint8List? _loadedBytes;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isFullscreen = false;

  final TransformationController _transformationController =
      TransformationController();
  final ScrollController _pageScrollController = ScrollController();
  final List<GlobalKey> _pageKeys = [];

  // Status Halaman dan Zoom menggunakan ValueNotifier (mencegah loop rebuild & jitter)
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  final ValueNotifier<int> _totalPagesNotifier = ValueNotifier<int>(1);
  final ValueNotifier<bool> _showPageIndicatorNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<bool> _isZoomedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> _currentZoomScaleNotifier = ValueNotifier<double>(
    1.0,
  );
  Timer? _pageIndicatorTimer;

  // Objek dokumen Syncfusion untuk inspeksi ukuran lembar & pencarian teks berkoordinat
  sf.PdfDocument? _pdfDocument;
  final List<Size> _pageSizes = [];

  // Fitur Pencarian Teks
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  final List<String> _pageTexts = [];
  final List<_PdfSearchMatch> _matches = [];
  int _currentMatchIndex = 0;

  @override
  void initState() {
    super.initState();
    AppSecurityService.instance.enterSandboxedViewer();
    _pageScrollController.addListener(_updateCurrentPageOnScroll);
    _transformationController.addListener(_onTransformationChanged);
    if (widget.pdfBytes != null) {
      _loadedBytes = widget.pdfBytes;
      _extractDocumentText();
    } else if (widget.pdfFile != null) {
      _loadFileBytes();
    }
  }

  void _handleBack() {
    AppSecurityService.instance.exitSandboxedViewer();
    if (widget.isExternal) {
      SystemNavigator.pop();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _loadFileBytes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bytes = await widget.pdfFile!.readAsBytes();
      if (!DocumentPreviewScreen.hasPdfHeader(bytes)) {
        throw const FormatException(
          'Berkas tidak memiliki header PDF yang valid (%PDF-).',
        );
      }
      if (mounted) {
        setState(() {
          _loadedBytes = bytes;
          _isLoading = false;
        });
        _extractDocumentText();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _extractDocumentText() {
    final bytes = _loadedBytes;
    if (bytes == null) return;
    try {
      _pdfDocument?.dispose();
      final doc = sf.PdfDocument(inputBytes: bytes);
      _pdfDocument = doc;
      _pageSizes.clear();
      _pageTexts.clear();
      for (int i = 0; i < doc.pages.count; i++) {
        _pageSizes.add(doc.pages[i].size);
        final text = sf.PdfTextExtractor(
          doc,
        ).extractText(startPageIndex: i, endPageIndex: i);
        _pageTexts.add(text);
      }
      _totalPagesNotifier.value = doc.pages.count;
    } catch (e) {
      debugPrint('Gagal mengekstrak teks PDF: $e');
    }
  }

  void _onTransformationChanged() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = (currentScale - 1.0).abs() > 0.05;
    if (_isZoomedNotifier.value != isZoomed) {
      _isZoomedNotifier.value = isZoomed;
    }
    if ((_currentZoomScaleNotifier.value - currentScale).abs() > 0.02) {
      _currentZoomScaleNotifier.value = currentScale;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isCtrl =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (isCtrl) {
        _handleCtrlZoom(event);
      }
    }
  }

  void _handleCtrlZoom(PointerScrollEvent event) {
    final double zoomDelta = -event.scrollDelta.dy;
    if (zoomDelta == 0.0) return;

    final double scaleMultiplier = math.exp(zoomDelta / 300.0);
    final Matrix4 currentMatrix = _transformationController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    const double minScale = 0.8;
    const double maxScale = 6.0;

    final double targetScale = (currentScale * scaleMultiplier).clamp(
      minScale,
      maxScale,
    );
    if ((targetScale - currentScale).abs() < 1e-4) return;

    if (targetScale <= 1.05 && currentScale > 1.05) {
      _resetZoom();
      return;
    }

    final double factor = targetScale / currentScale;
    final Offset local = event.localPosition;
    final Offset scenePointBefore = _transformationController.toScene(local);

    final Matrix4 scaledMatrix = currentMatrix.clone()
      ..scaleByDouble(factor, factor, 1.0, 1.0);
    _transformationController.value = scaledMatrix;

    final Offset scenePointAfter = _transformationController.toScene(local);
    final Offset translationDelta = scenePointAfter - scenePointBefore;

    _transformationController.value = scaledMatrix
      ..translateByDouble(translationDelta.dx, translationDelta.dy, 0.0, 1.0);
  }

  void _zoomIn() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * 1.25).clamp(0.8, 6.0);
    _setZoomScale(targetScale);
  }

  void _zoomOut() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale / 1.25).clamp(0.8, 6.0);
    _setZoomScale(targetScale);
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    _isZoomedNotifier.value = false;
    _currentZoomScaleNotifier.value = 1.0;
  }

  void _setZoomScale(double targetScale) {
    if (targetScale <= 1.05) {
      _resetZoom();
      return;
    }
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final factor = targetScale / currentScale;
    _transformationController.value = _transformationController.value.clone()
      ..scaleByDouble(factor, factor, 1.0, 1.0);
  }

  void _updateCurrentPageOnScroll() {
    if (!mounted || _pageKeys.isEmpty) return;
    int foundPage = 1;
    for (int i = 0; i < _pageKeys.length; i++) {
      final key = _pageKeys[i];
      final ctx = key.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          if (pos.dy <= 350) {
            foundPage = i + 1;
          }
        }
      }
    }
    if (_currentPageNotifier.value != foundPage) {
      _currentPageNotifier.value = foundPage;
    }
    if (!_showPageIndicatorNotifier.value) {
      _showPageIndicatorNotifier.value = true;
    }
    _pageIndicatorTimer?.cancel();
    _pageIndicatorTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        _showPageIndicatorNotifier.value = false;
      }
    });
  }

  void _jumpToPage(int pageIndex) {
    if (pageIndex >= 0 && pageIndex < _pageKeys.length) {
      final pageCtx = _pageKeys[pageIndex].currentContext;
      if (pageCtx != null) {
        Scrollable.ensureVisible(
          pageCtx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1,
        );
      }
    }
  }

  Future<void> _showJumpToPageDialog() async {
    final total = _totalPagesNotifier.value;
    if (total <= 1) return;
    final controller = TextEditingController(
      text: '${_currentPageNotifier.value}',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lompat ke Halaman'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Nomor Halaman (1 - $total)',
            hintText: 'Contoh: 5',
          ),
          onSubmitted: (val) {
            final p = int.tryParse(val);
            Navigator.pop(ctx, p);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(controller.text);
              Navigator.pop(ctx, p);
            },
            child: const Text('Lompat'),
          ),
        ],
      ),
    );
    if (result != null && result >= 1 && result <= total) {
      _jumpToPage(result - 1);
    }
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.2) {
      _resetZoom();
    } else {
      _transformationController.value = Matrix4.diagonal3Values(2.2, 2.2, 1.0);
    }
  }

  void _openSearch() {
    setState(() {
      _isSearchOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearchOpen = false;
      _searchQuery = '';
      _matches.clear();
      _currentMatchIndex = 0;
      _searchController.clear();
    });
  }

  void _performSearch(String query) {
    _searchQuery = query.trim();
    _matches.clear();
    _currentMatchIndex = 0;
    if (_searchQuery.isEmpty) {
      setState(() {});
      return;
    }

    final doc = _pdfDocument;
    if (doc != null) {
      try {
        final extractor = sf.PdfTextExtractor(doc);
        final rawMatches = extractor.findText([_searchQuery]);
        for (final m in rawMatches) {
          if (m.pageIndex >= _pageSizes.length) continue;
          final pSize = _pageSizes[m.pageIndex];
          if (pSize.width <= 0 || pSize.height <= 0) continue;
          final normRect = Rect.fromLTWH(
            (m.bounds.left / pSize.width).clamp(0.0, 1.0),
            (m.bounds.top / pSize.height).clamp(0.0, 1.0),
            (m.bounds.width / pSize.width).clamp(0.0, 1.0),
            (m.bounds.height / pSize.height).clamp(0.0, 1.0),
          );

          final pText = m.pageIndex < _pageTexts.length
              ? _pageTexts[m.pageIndex]
              : '';
          final snippet = _extractSnippet(pText, _searchQuery);

          _matches.add(
            _PdfSearchMatch(
              pageIndex: m.pageIndex,
              text: m.text,
              bounds: m.bounds,
              normalizedBounds: normRect,
              snippet: snippet,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error finding text matches via findText: $e');
      }
    }

    // Fallback pencarian teks jika ekstraksi koordinat tidak menemukan hasil
    if (_matches.isEmpty) {
      final pattern = RegExp(RegExp.escape(_searchQuery), caseSensitive: false);
      for (int p = 0; p < _pageTexts.length; p++) {
        final text = _pageTexts[p];
        final allMatches = pattern.allMatches(text);
        for (final _ in allMatches) {
          final snippet = _extractSnippet(text, _searchQuery);
          _matches.add(
            _PdfSearchMatch(
              pageIndex: p,
              text: _searchQuery,
              bounds: Rect.zero,
              normalizedBounds: Rect.zero,
              snippet: snippet,
            ),
          );
        }
      }
    }

    if (_matches.isNotEmpty) {
      _scrollToMatch(0);
    }
    setState(() {});
  }

  String _extractSnippet(String text, String query) {
    if (text.isEmpty) return query;
    final idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) return query;
    final start = (idx - 25).clamp(0, text.length);
    final end = (idx + query.length + 25).clamp(0, text.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    return '$prefix${text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ')}$suffix';
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    });
    _scrollToMatch(_currentMatchIndex);
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    });
    _scrollToMatch(_currentMatchIndex);
  }

  void _scrollToMatch(int index) {
    if (index >= 0 && index < _matches.length) {
      final match = _matches[index];
      if (match.pageIndex < _pageKeys.length) {
        final pageCtx = _pageKeys[match.pageIndex].currentContext;
        if (pageCtx != null) {
          final align = (match.normalizedBounds.top - 0.15).clamp(0.0, 0.85);
          Scrollable.ensureVisible(
            pageCtx,
            duration: const Duration(milliseconds: 250),
            alignment: align,
          );
        }
      }
    }
  }

  Future<void> _openWithExternalApp() async {
    final bytes = _loadedBytes;
    if (bytes == null) return;
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/files');
        await channel.invokeMethod('openWithExternalApp', {
          'filePath': widget.pdfFile?.path,
          'fileName': widget.fileName,
          'bytes': bytes,
          'mimeType': 'application/pdf',
        });
        return;
      }
    } catch (e) {
      debugPrint('openWithExternalApp error: $e');
    }
    await Printing.sharePdf(bytes: bytes, filename: widget.fileName);
  }

  Future<void> _download(BuildContext context) async {
    final bytes = _loadedBytes;
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await BaseTableExporter.saveExportedBytes(
        bytes: bytes,
        fileName: widget.fileName,
      );
      if (location == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Dokumen tersimpan di $location'),
          action: SnackBarAction(label: 'Tutup', onPressed: () {}),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan dokumen: $e')),
      );
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    AppSecurityService.instance.exitSandboxedViewer();
    _pdfDocument?.dispose();
    _pageIndicatorTimer?.cancel();
    _pageScrollController.removeListener(_updateCurrentPageOnScroll);
    _transformationController.removeListener(_onTransformationChanged);
    _currentPageNotifier.dispose();
    _totalPagesNotifier.dispose();
    _showPageIndicatorNotifier.dispose();
    _isZoomedNotifier.dispose();
    _currentZoomScaleNotifier.dispose();
    _transformationController.dispose();
    _pageScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearchOpen) {
          _closeSearch();
          return;
        }
        _handleBack();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.equal, control: true):
              _zoomIn,
          const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
          const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
              _zoomIn,
          const SingleActivator(LogicalKeyboardKey.minus, control: true):
              _zoomOut,
          const SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            control: true,
          ): _zoomOut,
          const SingleActivator(LogicalKeyboardKey.digit0, control: true):
              _resetZoom,
          const SingleActivator(LogicalKeyboardKey.numpad0, control: true):
              _resetZoom,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_isSearchOpen) {
              _closeSearch();
            } else if (_isFullscreen) {
              _toggleFullscreen();
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: _isFullscreen
                ? null
                : (_isSearchOpen
                      ? AppBar(
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Tutup Pencarian',
                            onPressed: _closeSearch,
                          ),
                          title: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            decoration: const InputDecoration(
                              hintText: 'Cari di dokumen...',
                              border: InputBorder.none,
                            ),
                            style: const TextStyle(fontSize: 16),
                            onChanged: _performSearch,
                          ),
                          actions: [
                            if (_searchQuery.isNotEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Text(
                                    _matches.isEmpty
                                        ? '0/0'
                                        : '${_currentMatchIndex + 1}/${_matches.length}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_up),
                              tooltip: 'Sebelumnya',
                              onPressed: _matches.isNotEmpty
                                  ? _prevMatch
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down),
                              tooltip: 'Berikutnya',
                              onPressed: _matches.isNotEmpty
                                  ? _nextMatch
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Bersihkan',
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('');
                              },
                            ),
                          ],
                        )
                      : AppBar(
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            tooltip: 'Kembali',
                            onPressed: _handleBack,
                          ),
                          title: Text(
                            widget.fileName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: 'Cari di dokumen',
                              onPressed: _openSearch,
                            ),
                            IconButton(
                              icon: const Icon(Icons.fullscreen),
                              tooltip: 'Layar Penuh',
                              onPressed: _toggleFullscreen,
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: 'Menu Lainnya',
                              onSelected: (val) async {
                                switch (val) {
                                  case 'share':
                                    if (_loadedBytes != null) {
                                      await Printing.sharePdf(
                                        bytes: _loadedBytes!,
                                        filename: widget.fileName,
                                      );
                                    }
                                    break;
                                  case 'open_with':
                                    await _openWithExternalApp();
                                    break;
                                  case 'download':
                                    await _download(context);
                                    break;
                                  case 'print':
                                    if (_loadedBytes != null) {
                                      await Printing.layoutPdf(
                                        onLayout: (_) => _loadedBytes!,
                                        name: widget.fileName,
                                      );
                                    }
                                    break;
                                  case 'open_other':
                                    if (context.mounted) {
                                      await DocumentPreviewScreen.pickAndOpenPdf(
                                        context,
                                      );
                                    }
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'share',
                                  child: Row(
                                    children: [
                                      Icon(Icons.share_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Bagikan'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'open_with',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.open_in_new_outlined,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text('Buka dengan...'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'download',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Unduh'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'print',
                                  child: Row(
                                    children: [
                                      Icon(Icons.print_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Cetak'),
                                    ],
                                  ),
                                ),
                                if (!widget.isExternal)
                                  const PopupMenuItem(
                                    value: 'open_other',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.folder_open_outlined,
                                          size: 20,
                                        ),
                                        SizedBox(width: 12),
                                        Text('Buka Berkas PDF Lain'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        )),
            body: Stack(
              children: [
                if (_isLoading)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Memuat dokumen PDF...'),
                      ],
                    ),
                  )
                else if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Gagal Membaca PDF',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _handleBack,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Kembali'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_loadedBytes != null)
                  PdfPreview.builder(
                    build: (format) async => _loadedBytes!,
                    useActions: false,
                    loadingWidget: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Menyiapkan pratinjau dokumen...'),
                        ],
                      ),
                    ),
                    scrollViewDecoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF141414)
                          : const Color(0xFF2B2B2B),
                    ),
                    pagesBuilder: (context, pages) {
                      if (_totalPagesNotifier.value != pages.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _totalPagesNotifier.value = pages.length;
                          }
                        });
                      }
                      while (_pageKeys.length < pages.length) {
                        _pageKeys.add(GlobalKey());
                      }
                      return Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerSignal: _handlePointerSignal,
                        child: GestureDetector(
                          onDoubleTap: _handleDoubleTap,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _isZoomedNotifier,
                            builder: (context, isZoomed, _) {
                              return InteractiveViewer(
                                transformationController:
                                    _transformationController,
                                minScale: 0.8,
                                maxScale: 6.0,
                                scaleFactor: double.maxFinite,
                                panEnabled: isZoomed,
                                boundaryMargin: EdgeInsets.zero,
                                child: Center(
                                  child: SingleChildScrollView(
                                    controller: _pageScrollController,
                                    physics: const DesktopPdfScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (int i = 0; i < pages.length; i++)
                                          _buildPageItem(pages[i], i),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),

                // Banner hasil pencarian mengambang di bawah
                if (_isSearchOpen && _matches.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Hal ${_matches[_currentMatchIndex].pageIndex + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _matches[_currentMatchIndex].snippet,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                size: 20,
                              ),
                              tooltip: 'Sebelumnya',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: _prevMatch,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                              ),
                              tooltip: 'Berikutnya',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: _nextMatch,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Indikator nomor halaman mengambang gaya Camelot (Fast Scroll Page Pill)
                ValueListenableBuilder<int>(
                  valueListenable: _totalPagesNotifier,
                  builder: (context, totalPages, _) {
                    if (totalPages <= 1) return const SizedBox.shrink();
                    return ValueListenableBuilder<bool>(
                      valueListenable: _showPageIndicatorNotifier,
                      builder: (context, showIndicator, _) {
                        final visible = showIndicator || _isFullscreen;
                        return Positioned(
                          top: _isFullscreen
                              ? MediaQuery.of(context).padding.top + 16
                              : 16,
                          right: _isFullscreen ? 72 : 16,
                          child: AnimatedOpacity(
                            opacity: visible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: IgnorePointer(
                              ignoring: !visible,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.black87,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: _showJumpToPageDialog,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.menu_book_outlined,
                                          color: Colors.white70,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        ValueListenableBuilder<int>(
                                          valueListenable: _currentPageNotifier,
                                          builder: (context, currentPage, _) {
                                            return Text(
                                              'Hal $currentPage / $totalPages',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.3,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Tombol Reset Zoom mengambang saat tampilan diperbesar/diperkecil
                ValueListenableBuilder<bool>(
                  valueListenable: _isZoomedNotifier,
                  builder: (context, isZoomed, _) {
                    if (!isZoomed) return const SizedBox.shrink();
                    return Positioned(
                      bottom: (_isSearchOpen && _matches.isNotEmpty) ? 88 : 24,
                      right: 16,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(24),
                        color: theme.colorScheme.primaryContainer,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _resetZoom,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.zoom_out_map,
                                  size: 16,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 6),
                                ValueListenableBuilder<double>(
                                  valueListenable: _currentZoomScaleNotifier,
                                  builder: (context, scale, _) {
                                    return Text(
                                      '${(scale * 100).round()}% (Reset)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: theme
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Tombol keluar dari mode layar penuh mengambang saat fullscreen aktif
                if (_isFullscreen)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    right: 16,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                      child: IconButton(
                        icon: const Icon(
                          Icons.fullscreen_exit,
                          color: Colors.white,
                        ),
                        tooltip: 'Keluar Layar Penuh',
                        onPressed: _toggleFullscreen,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageItem(PdfPreviewPageData pageData, int pageIndex) {
    // Kumpulkan semua kecocokan pencarian pada halaman ini
    final pageMatches = <int, _PdfSearchMatch>{};
    for (int m = 0; m < _matches.length; m++) {
      if (_matches[m].pageIndex == pageIndex) {
        pageMatches[m] = _matches[m];
      }
    }

    return Container(
      key: _pageKeys[pageIndex],
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double renderWidth = constraints.maxWidth;
          final double aspectRatio = pageData.width > 0 && pageData.height > 0
              ? pageData.width / pageData.height
              : 0.707;
          final double renderHeight = renderWidth / aspectRatio;

          return Stack(
            children: [
              Image(
                image: pageData.image,
                fit: BoxFit.contain,
                width: renderWidth,
              ),
              if (pageMatches.isNotEmpty)
                Positioned.fill(
                  child: Stack(
                    children: [
                      for (final entry in pageMatches.entries)
                        _buildHighlightBox(
                          match: entry.value,
                          matchIndex: entry.key,
                          renderWidth: renderWidth,
                          renderHeight: renderHeight,
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHighlightBox({
    required _PdfSearchMatch match,
    required int matchIndex,
    required double renderWidth,
    required double renderHeight,
  }) {
    final norm = match.normalizedBounds;
    if (norm.width <= 0 || norm.height <= 0) {
      return const SizedBox.shrink();
    }

    final bool isActive = matchIndex == _currentMatchIndex;

    final left = norm.left * renderWidth;
    final top = norm.top * renderHeight;
    final width = norm.width * renderWidth;
    final height = norm.height * renderHeight;

    return Positioned(
      left: left - 2,
      top: top - 1,
      width: width + 4,
      height: height + 2,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.amber.withValues(alpha: 0.65)
                : Colors.yellow.withValues(alpha: 0.35),
            border: Border.all(
              color: isActive ? Colors.deepOrange : Colors.amber.shade700,
              width: isActive ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}
