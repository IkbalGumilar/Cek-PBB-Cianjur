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

/// Pembaca Dokumen PDF bergaya Google PDF Viewer (Camelot):
/// 1. **Lapisan Teks Dapat Dipilih & Disalin (Selectable Text Layer)**:
///    Teks di atas kanvas PDF dapat langsung diblok/disorot (drag/long-press) untuk
///    disalin ke papan klip, ditambah panel cepat "Salin Teks & NOP" per halaman.
/// 2. **UX Navigasi & Zoom Halus ala Camelot / Google PDF**:
///    - Double-tap zoom tepat ke titik sentuh/klik dengan animasi mulus (bukan melompat ke pojok kiri atas).
///    - Zoom +/- terpusat pada tengah layar & dukungan Ctrl+Scroll di desktop.
///    - Fast-Scroll Scrubber (penggeser cepat di tepi kanan) untuk dokumen puluhan halaman.
///    - Bilah kontrol melayang di bagian bawah (Navigasi Halaman, Zoom, Salin Teks, Cetak).
/// 3. **Ekstraksi Teks Asinkron Bertahap**:
///    Membuka dokumen puluhan halaman (seperti DHKP) secara instan tanpa membekukan UI.
/// 4. **Validasi Keamanan & Mode Kotak Pasir (Sandboxed)**:
///    Verifikasi magic bytes `%PDF-`, batas ukuran 150 MB, dan perlindungan kunci aplikasi.
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

/// Satu baris teks terpetakan koordinatnya pada halaman PDF untuk lapisan seleksi teks.
class _PdfSelectableLine {
  final String text;
  final Rect normalizedBounds;

  const _PdfSelectableLine({
    required this.text,
    required this.normalizedBounds,
  });
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _loadedBytes;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isFullscreen = false;

  /// Mode seleksi teks aktif secara default agar teks pada halaman PDF dapat
  /// langsung diblok/disalin seperti Google PDF Viewer / Camelot.
  bool _isTextSelectionEnabled = true;

  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  Offset? _doubleTapLocalPosition;
  final GlobalKey _viewportKey = GlobalKey(debugLabel: 'pdf_viewport');

  final ScrollController _pageScrollController = ScrollController();
  final List<GlobalKey> _pageKeys = [];

  // Status Halaman, Scrubber, dan Zoom menggunakan ValueNotifier (mencegah rebuild berlebih)
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  final ValueNotifier<int> _totalPagesNotifier = ValueNotifier<int>(1);
  final ValueNotifier<bool> _showPageIndicatorNotifier = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<double> _scrollFractionNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<bool> _isDraggingScrollbarNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isZoomedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> _currentZoomScaleNotifier = ValueNotifier<double>(
    1.0,
  );
  final ValueNotifier<String> _selectedCanvasTextNotifier =
      ValueNotifier<String>('');
  Timer? _pageIndicatorTimer;

  // Objek dokumen Syncfusion untuk ekstraksi teks & koordinat baris per halaman
  sf.PdfDocument? _pdfDocument;
  final List<Size> _pageSizes = [];
  final Map<int, List<_PdfSelectableLine>> _pageSelectableLines = {};
  int _extractionToken = 0;

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
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformationController.value = _zoomAnimation!.value;
        }
      });
    _pageScrollController.addListener(_updateCurrentPageOnScroll);
    _transformationController.addListener(_onTransformationChanged);
    if (widget.pdfBytes != null) {
      _loadedBytes = widget.pdfBytes;
      _extractDocumentTextAsync();
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
        _extractDocumentTextAsync();
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

  /// Mengekstrak teks dan koordinat baris per halaman secara bertahap (non-blocking)
  /// agar pembukaan dokumen multi-halaman tetap instan dan mulus.
  Future<void> _extractDocumentTextAsync() async {
    final bytes = _loadedBytes;
    if (bytes == null) return;
    final token = ++_extractionToken;

    try {
      _pdfDocument?.dispose();
      final doc = sf.PdfDocument(inputBytes: bytes);
      _pdfDocument = doc;
      final pageCount = doc.pages.count;

      _pageSizes
        ..clear()
        ..addAll(List.generate(pageCount, (i) => doc.pages[i].size));
      _pageTexts
        ..clear()
        ..addAll(List.filled(pageCount, ''));
      _pageSelectableLines.clear();
      _totalPagesNotifier.value = math.max(1, pageCount);

      final extractor = sf.PdfTextExtractor(doc);

      for (int i = 0; i < pageCount; i++) {
        if (!mounted || token != _extractionToken) return;

        final pSize = _pageSizes[i];
        final rawText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        _pageTexts[i] = rawText;

        if (pSize.width > 0 && pSize.height > 0) {
          try {
            final lines = extractor.extractTextLines(
              startPageIndex: i,
              endPageIndex: i,
            );
            final mapped = <_PdfSelectableLine>[];
            for (final line in lines) {
              final clean = line.text.trim();
              if (clean.isEmpty || line.bounds.width <= 0 || line.bounds.height <= 0) {
                continue;
              }
              final norm = Rect.fromLTWH(
                (line.bounds.left / pSize.width).clamp(0.0, 0.99),
                (line.bounds.top / pSize.height).clamp(0.0, 0.99),
                (line.bounds.width / pSize.width).clamp(0.01, 1.0),
                (line.bounds.height / pSize.height).clamp(0.008, 1.0),
              );
              mapped.add(_PdfSelectableLine(text: clean, normalizedBounds: norm));
            }
            _pageSelectableLines[i] = mapped;
          } catch (_) {
            // Abaikan bila halaman tertentu gagal diekstrak koordinat barisnya.
          }
        }

        if (i == 0 || i == pageCount - 1) {
          if (mounted) setState(() {});
        }
        // Beri jeda microtask setiap 2 halaman agar UI tetap responsif 60fps
        if (i % 2 == 1) {
          await Future<void>.delayed(Duration.zero);
        }
      }
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

  void _animateMatrixTo(Matrix4 target) {
    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic),
    );
    _zoomAnimController.forward(from: 0);
  }

  Size _viewportSize() {
    final ctx = _viewportKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) return box.size;
    }
    return MediaQuery.sizeOf(context);
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

    _zoomAroundPoint(targetScale, event.localPosition, animate: false);
  }

  void _zoomAroundPoint(
    double targetScale,
    Offset focalPoint, {
    bool animate = true,
  }) {
    if (targetScale <= 1.03) {
      _resetZoom(animate: animate);
      return;
    }
    final Matrix4 currentMatrix = _transformationController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    if ((targetScale - currentScale).abs() < 1e-4) return;

    final double factor = targetScale / currentScale;
    final Offset scenePointBefore = _transformationController.toScene(
      focalPoint,
    );

    final Matrix4 scaledMatrix = currentMatrix.clone()
      ..scaleByDouble(factor, factor, 1.0, 1.0);

    // Hitung titik scene setelah skala untuk menjaga focalPoint tetap di bawah kursor/jari
    final Matrix4 invScaled = Matrix4.inverted(scaledMatrix);
    final Offset scenePointAfter = MatrixUtils.transformPoint(
      invScaled,
      focalPoint,
    );
    final Offset translationDelta = scenePointAfter - scenePointBefore;

    final Matrix4 finalMatrix = scaledMatrix
      ..translateByDouble(translationDelta.dx, translationDelta.dy, 0.0, 1.0);

    if (animate) {
      _animateMatrixTo(finalMatrix);
    } else {
      _transformationController.value = finalMatrix;
    }
  }

  void _zoomIn() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * 1.25).clamp(0.8, 6.0);
    final size = _viewportSize();
    _zoomAroundPoint(
      targetScale,
      Offset(size.width / 2, size.height / 2),
      animate: true,
    );
  }

  void _zoomOut() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale / 1.25).clamp(0.8, 6.0);
    final size = _viewportSize();
    _zoomAroundPoint(
      targetScale,
      Offset(size.width / 2, size.height / 2),
      animate: true,
    );
  }

  void _resetZoom({bool animate = true}) {
    if (animate && mounted) {
      _animateMatrixTo(Matrix4.identity());
    } else {
      _transformationController.value = Matrix4.identity();
    }
    _isZoomedNotifier.value = false;
    _currentZoomScaleNotifier.value = 1.0;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.15) {
      _resetZoom(animate: true);
    } else {
      final size = _viewportSize();
      final focal =
          _doubleTapLocalPosition ?? Offset(size.width / 2, size.height / 2);
      _zoomAroundPoint(2.25, focal, animate: true);
    }
  }

  void _updateCurrentPageOnScroll() {
    if (!mounted) return;
    if (_pageScrollController.hasClients) {
      final maxExtent = _pageScrollController.position.maxScrollExtent;
      final pixels = _pageScrollController.position.pixels;
      final fraction = maxExtent > 0 ? (pixels / maxExtent).clamp(0.0, 1.0) : 0.0;
      _scrollFractionNotifier.value = fraction;
    }

    if (_pageKeys.isEmpty) return;
    int foundPage = 1;
    for (int i = 0; i < _pageKeys.length; i++) {
      final key = _pageKeys[i];
      final ctx = key.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          if (pos.dy <= 360) {
            foundPage = i + 1;
          }
        }
      }
    }
    if (_currentPageNotifier.value != foundPage) {
      _currentPageNotifier.value = foundPage;
    }
    _triggerPageIndicatorVisibility();
  }

  void _triggerPageIndicatorVisibility() {
    if (!_showPageIndicatorNotifier.value) {
      _showPageIndicatorNotifier.value = true;
    }
    _pageIndicatorTimer?.cancel();
    _pageIndicatorTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted && !_isDraggingScrollbarNotifier.value) {
        _showPageIndicatorNotifier.value = false;
      }
    });
  }

  void _jumpToPage(int pageIndex) {
    final total = _totalPagesNotifier.value;
    if (pageIndex < 0 || pageIndex >= total) return;

    if (pageIndex < _pageKeys.length) {
      final pageCtx = _pageKeys[pageIndex].currentContext;
      if (pageCtx != null) {
        Scrollable.ensureVisible(
          pageCtx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
        _currentPageNotifier.value = pageIndex + 1;
        _triggerPageIndicatorVisibility();
        return;
      }
    }

    if (_pageScrollController.hasClients && total > 1) {
      final maxScroll = _pageScrollController.position.maxScrollExtent;
      final targetOffset = (pageIndex / (total - 1)) * maxScroll;
      _pageScrollController.animateTo(
        targetOffset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      _currentPageNotifier.value = pageIndex + 1;
      _triggerPageIndicatorVisibility();
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
            hintText: 'Contoh: 1',
            border: const OutlineInputBorder(),
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

  Future<void> _copyToClipboard(String text, {String? label}) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada teks pada halaman ini yang dapat disalin.'),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: clean));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label ?? 'Teks berhasil disalin ke papan klip.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Menampilkan lembar bawah (Bottom Sheet) gaya Google PDF / Camelot untuk
  /// menyalin teks per halaman, seluruh dokumen, maupun menyalin NOP 18-digit
  /// yang terdeteksi secara otomatis dengan 1 ketukan.
  Future<void> _showCopyTextSheet() async {
    final currentPage = _currentPageNotifier.value;
    final int pageIdx = (currentPage - 1)
        .clamp(0, math.max(0, _pageTexts.length - 1))
        .toInt();
    final pageText = pageIdx < _pageTexts.length ? _pageTexts[pageIdx].trim() : '';
    final allText = _pageTexts.where((t) => t.trim().isNotEmpty).join('\n\n--- Halaman Berikutnya ---\n\n').trim();

    // Deteksi NOP 18 digit (baik berformat titik/strip maupun angka bersambung) pada halaman aktif
    final nopRegex = RegExp(
      r'\b(?:\d{2}[.\-\s]?\d{2}[.\-\s]?\d{3}[.\-\s]?\d{3}[.\-\s]?\d{3}[.\-\s]?\d{4}[.\-\s]?\d|\d{18})\b',
    );
    final detectedNops = <String>{};
    for (final m in nopRegex.allMatches(pageText)) {
      final raw = m.group(0) ?? '';
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 18) {
        detectedNops.add(digits);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.68,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.copy_all_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pilih & Salin Teks (Halaman $currentPage)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Blok sebagian teks di bawah atau gunakan tombol salin cepat.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: pageText.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _copyToClipboard(
                                  pageText,
                                  label:
                                      'Seluruh teks Halaman $currentPage disalin ke papan klip.',
                                );
                              },
                        icon: const Icon(Icons.content_copy, size: 18),
                        label: Text('Salin Halaman $currentPage'),
                      ),
                      if (_pageTexts.length > 1)
                        OutlinedButton.icon(
                          onPressed: allText.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _copyToClipboard(
                                    allText,
                                    label:
                                        'Seluruh teks dokumen (${_pageTexts.length} halaman) disalin.',
                                  );
                                },
                          icon: const Icon(Icons.library_books_outlined, size: 18),
                          label: Text('Salin Semua (${_pageTexts.length} Hal)'),
                        ),
                    ],
                  ),
                  if (detectedNops.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'NOP Terdeteksi di Halaman Ini (Ketuk untuk Menyalin):',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: detectedNops.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final nop = detectedNops.elementAt(index);
                          return ActionChip(
                            avatar: const Icon(Icons.copy, size: 15),
                            label: Text(
                              nop,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () {
                              _copyToClipboard(
                                nop,
                                label: 'NOP $nop disalin ke papan klip.',
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: pageText.isEmpty
                          ? const Center(
                              child: Text(
                                'Halaman ini berupa gambar pindaian atau belum memiliki lapisan teks yang dapat diekstrak.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Scrollbar(
                              controller: scrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: scrollController,
                                child: SelectableText(
                                  pageText,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

  Future<void> _printDocument() async {
    if (_loadedBytes != null) {
      await Printing.layoutPdf(
        onLayout: (_) => _loadedBytes!,
        name: widget.fileName,
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
    _extractionToken++;
    AppSecurityService.instance.exitSandboxedViewer();
    _pdfDocument?.dispose();
    _pageIndicatorTimer?.cancel();
    _pageScrollController.removeListener(_updateCurrentPageOnScroll);
    _transformationController.removeListener(_onTransformationChanged);
    _zoomAnimController.dispose();
    _currentPageNotifier.dispose();
    _totalPagesNotifier.dispose();
    _showPageIndicatorNotifier.dispose();
    _scrollFractionNotifier.dispose();
    _isDraggingScrollbarNotifier.dispose();
    _isZoomedNotifier.dispose();
    _currentZoomScaleNotifier.dispose();
    _selectedCanvasTextNotifier.dispose();
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
                              hintText: 'Cari teks atau NOP di dokumen...',
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
                              tooltip: 'Cari di dokumen (Ctrl+F)',
                              onPressed: _openSearch,
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_all_rounded),
                              tooltip: 'Pilih & Salin Teks / NOP',
                              onPressed: _showCopyTextSheet,
                            ),
                            IconButton(
                              icon: const Icon(Icons.download_outlined),
                              tooltip: 'Unduh PDF',
                              onPressed: () => _download(context),
                            ),
                            IconButton(
                              icon: const Icon(Icons.print_outlined),
                              tooltip: 'Cetak',
                              onPressed: _printDocument,
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: 'Menu Lainnya',
                              onSelected: (val) async {
                                switch (val) {
                                  case 'toggle_selection':
                                    setState(() {
                                      _isTextSelectionEnabled =
                                          !_isTextSelectionEnabled;
                                    });
                                    break;
                                  case 'copy_sheet':
                                    await _showCopyTextSheet();
                                    break;
                                  case 'fullscreen':
                                    _toggleFullscreen();
                                    break;
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
                                    await _printDocument();
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
                                PopupMenuItem(
                                  value: 'toggle_selection',
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isTextSelectionEnabled
                                            ? Icons.check_box_outlined
                                            : Icons.check_box_outline_blank,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text('Seleksi Teks di Kanvas PDF'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'copy_sheet',
                                  child: Row(
                                    children: [
                                      Icon(Icons.copy_all_rounded, size: 20),
                                      SizedBox(width: 12),
                                      Text('Panel Salin Teks & NOP'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'fullscreen',
                                  child: Row(
                                    children: [
                                      Icon(Icons.fullscreen, size: 20),
                                      SizedBox(width: 12),
                                      Text('Layar Penuh'),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
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
              key: _viewportKey,
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
                    dpi: 170,
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
                          ? const Color(0xFF16181A)
                          : const Color(0xFF323639), // Warna kanvas Google PDF Viewer
                    ),
                    pagesBuilder: (context, pages) {
                      if (_totalPagesNotifier.value != pages.length &&
                          pages.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _totalPagesNotifier.value = pages.length;
                          }
                        });
                      }
                      while (_pageKeys.length < pages.length) {
                        _pageKeys.add(GlobalKey());
                      }

                      final viewerContent = Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerSignal: _handlePointerSignal,
                        child: GestureDetector(
                          onDoubleTapDown: (details) {
                            _doubleTapLocalPosition = details.localPosition;
                          },
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
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 960,
                                    ),
                                    child: SingleChildScrollView(
                                      controller: _pageScrollController,
                                      physics: const DesktopPdfScrollPhysics(),
                                      padding: const EdgeInsets.only(
                                        top: 16,
                                        bottom: 96,
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
                                ),
                              );
                            },
                          ),
                        ),
                      );

                      if (!_isTextSelectionEnabled) {
                        return viewerContent;
                      }

                      return SelectionArea(
                        onSelectionChanged: (content) {
                          _selectedCanvasTextNotifier.value =
                              content?.plainText.trim() ?? '';
                        },
                        child: viewerContent,
                      );
                    },
                  ),

                // Scrubber / Fast-Scroll Thumb di tepi kanan bergaya Camelot (Google PDF)
                _buildCamelotFastScrollbar(context),

                // Tombol cepat "Salin Teks Terpilih" saat pengguna memblok teks di kanvas PDF
                ValueListenableBuilder<String>(
                  valueListenable: _selectedCanvasTextNotifier,
                  builder: (context, selectedText, _) {
                    if (selectedText.isEmpty) return const SizedBox.shrink();
                    return Positioned(
                      left: 16,
                      right: 16,
                      bottom: 84,
                      child: Center(
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(28),
                          color: theme.colorScheme.primary,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(28),
                            onTap: () {
                              _copyToClipboard(
                                selectedText,
                                label:
                                    'Teks terpilih (${selectedText.length} karakter) disalin.',
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Salin Teks: "${selectedText.replaceAll('\n', ' ')}"',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.colorScheme.onPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
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
                ),

                // Banner hasil pencarian mengambang di bawah
                if (_isSearchOpen && _matches.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 84,
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

                // Bilah Kontrol Melayang Bawah ala Google PDF Viewer / Camelot
                if (_loadedBytes != null && _errorMessage == null && !_isLoading)
                  _buildGooglePdfBottomDock(context),

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

  /// Penggeser cepat (Fast Scrollbar Thumb + Pill Halaman) di sisi kanan layar
  /// menyerupai pembaca PDF bawaan Google (Camelot).
  Widget _buildCamelotFastScrollbar(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _totalPagesNotifier,
      builder: (context, totalPages, _) {
        if (totalPages <= 1) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: _showPageIndicatorNotifier,
          builder: (context, showIndicator, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _isDraggingScrollbarNotifier,
              builder: (context, isDragging, _) {
                final visible = showIndicator || isDragging || _isFullscreen;
                return Positioned(
                  top: _isFullscreen
                      ? MediaQuery.of(context).padding.top + 56
                      : 16,
                  bottom: 88,
                  right: 6,
                  child: AnimatedOpacity(
                    opacity: visible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final trackHeight = math.max(
                            1.0,
                            constraints.maxHeight - 44.0,
                          );
                          return ValueListenableBuilder<double>(
                            valueListenable: _scrollFractionNotifier,
                            builder: (context, fraction, _) {
                              final topOffset = (fraction * trackHeight).clamp(
                                0.0,
                                trackHeight,
                              );
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: (_) {
                                  _isDraggingScrollbarNotifier.value = true;
                                  _showPageIndicatorNotifier.value = true;
                                },
                                onVerticalDragUpdate: (details) {
                                  if (!_pageScrollController.hasClients) return;
                                  final maxScroll = _pageScrollController
                                      .position
                                      .maxScrollExtent;
                                  if (maxScroll <= 0) return;
                                  final deltaFrac =
                                      details.delta.dy / trackHeight;
                                  final newFrac = (fraction + deltaFrac).clamp(
                                    0.0,
                                    1.0,
                                  );
                                  _pageScrollController.jumpTo(
                                    newFrac * maxScroll,
                                  );
                                },
                                onVerticalDragEnd: (_) {
                                  _isDraggingScrollbarNotifier.value = false;
                                  _triggerPageIndicatorVisibility();
                                },
                                child: SizedBox(
                                  width: 132,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        top: topOffset,
                                        right: 0,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Material(
                                              elevation: 4,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              color: Colors.black87,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                onTap: _showJumpToPageDialog,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5,
                                                      ),
                                                  child: ValueListenableBuilder<int>(
                                                    valueListenable:
                                                        _currentPageNotifier,
                                                    builder:
                                                        (
                                                          context,
                                                          currentPage,
                                                          _,
                                                        ) {
                                                          return Text(
                                                            '$currentPage / $totalPages',
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          );
                                                        },
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 22,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: isDragging
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Colors.white.withValues(
                                                        alpha: 0.92,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.unfold_more_rounded,
                                                size: 16,
                                                color: isDragging
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Bilah kontrol melayang di bagian bawah ala Google Drive PDF Viewer:
  /// Menyediakan navigasi halaman (◀ Hal X/Y ▶), kontrol Zoom (- 100% +),
  /// dan tombol cepat "Salin Teks".
  Widget _buildGooglePdfBottomDock(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: Center(
        child: Material(
          elevation: 8,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(28),
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (context, currentPage, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: _totalPagesNotifier,
                        builder: (context, totalPages, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chevron_left_rounded),
                                tooltip: 'Halaman Sebelumnya',
                                onPressed: currentPage > 1
                                    ? () => _jumpToPage(currentPage - 2)
                                    : null,
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _showJumpToPageDialog,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Hal $currentPage / $totalPages',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chevron_right_rounded),
                                tooltip: 'Halaman Berikutnya',
                                onPressed: currentPage < totalPages
                                    ? () => _jumpToPage(currentPage)
                                    : null,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(
                    height: 20,
                    child: VerticalDivider(width: 12),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline, size: 19),
                    tooltip: 'Perkecil (Ctrl+-)',
                    onPressed: _zoomOut,
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _currentZoomScaleNotifier,
                    builder: (context, scale, _) {
                      final pct = (scale * 100).round();
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _resetZoom(animate: true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: pct != 100
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline, size: 19),
                    tooltip: 'Perbesar (Ctrl++)',
                    onPressed: _zoomIn,
                  ),
                  const SizedBox(
                    height: 20,
                    child: VerticalDivider(width: 12),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: _showCopyTextSheet,
                    icon: const Icon(Icons.copy_all_rounded, size: 17),
                    label: const Text(
                      'Salin Teks',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
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

    final selectableLines =
        _pageSelectableLines[pageIndex] ?? const <_PdfSelectableLine>[];

    return Container(
      key: _pageKeys[pageIndex],
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
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

          return SizedBox(
            width: renderWidth,
            height: renderHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image(
                    image: pageData.image,
                    fit: BoxFit.contain,
                    width: renderWidth,
                    height: renderHeight,
                  ),
                ),
                // Lapisan teks transparan terpetakan koordinatnya agar dapat diblok/disalin
                // langsung di atas halaman PDF seperti Google PDF Viewer / Camelot.
                if (_isTextSelectionEnabled && selectableLines.isNotEmpty)
                  Positioned.fill(
                    child: Stack(
                      children: [
                        for (final line in selectableLines)
                          _buildSelectableTextLine(
                            line: line,
                            renderWidth: renderWidth,
                            renderHeight: renderHeight,
                          ),
                      ],
                    ),
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectableTextLine({
    required _PdfSelectableLine line,
    required double renderWidth,
    required double renderHeight,
  }) {
    final norm = line.normalizedBounds;
    final left = norm.left * renderWidth;
    final top = norm.top * renderHeight;
    final width = math.max(8.0, norm.width * renderWidth);
    final height = math.max(6.0, norm.height * renderHeight);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.centerLeft,
        child: Text(
          line.text,
          style: const TextStyle(
            // Teks transparan agar tidak menduplikasi render visual PDF,
            // tetapi tetap menampilkan sorotan biru SelectionArea & bisa di-copy.
            color: Color(0x01000000),
            fontSize: 14,
            height: 1.0,
          ),
        ),
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
