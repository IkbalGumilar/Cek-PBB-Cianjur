import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'app_security_service.dart';
import 'base_table_exporter.dart';

/// Layar pembaca dokumen PDF terpadu (PDF Reader bawaan bergaya Camelot / Google PDF).
///
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
          const SnackBar(content: Text('Berkas PDF tidak ditemukan atau sudah dipindahkan.')),
        );
        return;
      }

      final fileSize = await file.length();
      if (fileSize > maxSafePdfSizeBytes) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Ukuran berkas PDF terlalu besar (maksimal 150 MB).')),
        );
        return;
      }

      // Validasi magic bytes sebelum dimuat
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(5);
      await raf.close();

      if (!hasPdfHeader(header)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Format berkas tidak valid atau bukan dokumen PDF asli.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih berkas PDF: $e')),
        );
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

class _PdfSearchMatch {
  final int pageIndex;
  final String snippet;

  const _PdfSearchMatch({
    required this.pageIndex,
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
            'Berkas tidak memiliki header PDF yang valid (%PDF-).');
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
      final doc = sf.PdfDocument(inputBytes: bytes);
      _pageTexts.clear();
      for (int i = 0; i < doc.pages.count; i++) {
        final text = sf.PdfTextExtractor(doc).extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        _pageTexts.add(text);
      }
      doc.dispose();
    } catch (e) {
      debugPrint('Gagal mengekstrak teks PDF: $e');
    }
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.2) {
      _transformationController.value = Matrix4.identity();
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

    final pattern = RegExp(RegExp.escape(_searchQuery), caseSensitive: false);
    for (int p = 0; p < _pageTexts.length; p++) {
      final text = _pageTexts[p];
      final allMatches = pattern.allMatches(text);
      for (final m in allMatches) {
        final start = (m.start - 25).clamp(0, text.length);
        final end = (m.end + 25).clamp(0, text.length);
        final prefix = start > 0 ? '...' : '';
        final suffix = end < text.length ? '...' : '';
        final snippet =
            '$prefix${text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ')}$suffix';
        _matches.add(_PdfSearchMatch(
          pageIndex: p,
          snippet: snippet,
        ));
      }
    }

    if (_matches.isNotEmpty) {
      _scrollToMatch(0);
    }
    setState(() {});
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
          Scrollable.ensureVisible(
            pageCtx,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
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
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                        onPressed: _matches.isNotEmpty ? _prevMatch : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: 'Berikutnya',
                        onPressed: _matches.isNotEmpty ? _nextMatch : null,
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
                          fontSize: 16, fontWeight: FontWeight.w600),
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
                                    context);
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
                                Icon(Icons.open_in_new_outlined, size: 20),
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
                                  Icon(Icons.folder_open_outlined, size: 20),
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
                      Icon(Icons.error_outline,
                          size: 48, color: theme.colorScheme.error),
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
                  while (_pageKeys.length < pages.length) {
                    _pageKeys.add(GlobalKey());
                  }
                  return GestureDetector(
                    onDoubleTap: _handleDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.8,
                      maxScale: 6.0,
                      boundaryMargin: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 64,
                      ),
                      child: Center(
                        child: SingleChildScrollView(
                          controller: _pageScrollController,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < pages.length; i++)
                                Container(
                                  key: _pageKeys[i],
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Image(
                                    image: pages[i].image,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                            ],
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
                bottom: 24,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                          icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                          tooltip: 'Sebelumnya',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: _prevMatch,
                        ),
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                          tooltip: 'Berikutnya',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: _nextMatch,
                        ),
                      ],
                    ),
                  ),
                ),
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
                    icon:
                        const Icon(Icons.fullscreen_exit, color: Colors.white),
                    tooltip: 'Keluar Layar Penuh',
                    onPressed: _toggleFullscreen,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
