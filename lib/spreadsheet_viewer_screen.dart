import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_security_service.dart';
import 'blok_catatan_screen.dart';
import 'blok_data_store.dart';
import 'dkhp_package_helper.dart';
import 'spreadsheet/spreadsheet_parser.dart';
import 'spreadsheet/spreadsheet_view_widgets.dart';

// =============================================================================
// UI SCREEN UTAMA (PEMBACA SPREADSHEET & PRATINJAU DHKP)
// =============================================================================

/// Layar pembaca lembar kerja spreadsheet (Excel & CSV) serta pratinjau DHKP.
///
/// Sesuai instruksi:
/// - Berkas Excel (.xlsx/.xls) dan CSV bersifat **Hanya Lihat (View Only)** tanpa edit & tanpa tombol impor.
/// - Berkas DHKP (.dkhp / .dhkp / .dat) menampilkan pratinjau data dan dilengkapi tombol **"Impor ke Buku Catatan"**.
class SpreadsheetViewerScreen extends StatefulWidget {
  final File file;
  final String fileName;
  final bool isDkhp;
  final bool isExternal;

  const SpreadsheetViewerScreen({
    super.key,
    required this.file,
    required this.fileName,
    required this.isDkhp,
    this.isExternal = false,
  });

  /// Membuka berkas spreadsheet secara aman.
  static Future<void> openFile(
    BuildContext context,
    File file, {
    bool? isDkhp,
    String? title,
    bool isExternal = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await file.exists()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Berkas tidak ditemukan atau sudah dipindahkan.'),
          ),
        );
        return;
      }

      final fileName = title ?? file.uri.pathSegments.last;
      final lower = fileName.toLowerCase();
      final effectiveIsDkhp =
          isDkhp ??
          (lower.endsWith('.dkhp') ||
              lower.endsWith('.dhkp') ||
              lower.endsWith('.dat'));

      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SpreadsheetViewerScreen(
            file: file,
            fileName: fileName,
            isDkhp: effectiveIsDkhp,
            isExternal: isExternal,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Gagal membuka berkas spreadsheet: $e')),
        );
      }
    }
  }

  /// Membuka dialog pemilih berkas sistem (Excel, CSV, atau DHKP).
  static Future<void> pickAndOpenFile(BuildContext context) async {
    try {
      AppSecurityService.instance.setTemporaryLockBypass(true);
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'dkhp', 'dhkp', 'dat'],
      );
      if (files.isEmpty || files.first.path == null) return;

      final file = File(files.first.path!);
      if (!context.mounted) return;

      await openFile(context, file, title: files.first.name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memilih berkas: $e')));
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        AppSecurityService.instance.setTemporaryLockBypass(false);
      });
    }
  }

  @override
  State<SpreadsheetViewerScreen> createState() =>
      _SpreadsheetViewerScreenState();
}

class _SpreadsheetViewerScreenState extends State<SpreadsheetViewerScreen> {
  List<SpreadsheetTable> _tables = [];
  int _activeTableIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String? _providedPassword;

  // Pencarian baris
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Paginasi
  int _currentPage = 1;
  int _rowsPerPage = 50;

  // Pengontrol gulir
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    AppSecurityService.instance.enterSandboxedViewer();
    _loadFile();
  }

  void _handleBack() {
    AppSecurityService.instance.setScreenSecure(false);
    AppSecurityService.instance.exitSandboxedViewer();
    if (widget.isExternal) {
      SystemNavigator.pop();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    AppSecurityService.instance.setScreenSecure(false);
    AppSecurityService.instance.exitSandboxedViewer();
    _searchController.dispose();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  SpreadsheetTable? get _currentTable {
    if (_tables.isEmpty || _activeTableIndex >= _tables.length) return null;
    return _tables[_activeTableIndex];
  }

  Future<void> _loadFile({String? password}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final parser = SpreadsheetParserFactory.parserForPath(widget.file.path);
      final parsed = await parser.parseFile(
        widget.file,
        password: password ?? _providedPassword,
      );

      if (!mounted) return;
      if (widget.isExternal) {
        AppSecurityService.instance.enterSandboxedViewer();
      }
      setState(() {
        _tables = parsed;
        _activeTableIndex = 0;
        _isLoading = false;
        _currentPage = 1;
        _providedPassword = password ?? _providedPassword;
      });

      // Proteksi tangkapan layar (screenshot):
      // Hanya aktif jika berkas adalah DHKP DAN telah berhasil memuat data (ada baris data).
      // Jika data kosong atau bukan DHKP, proteksi screenshot tidak aktif.
      final hasData = parsed.isNotEmpty && parsed.any((t) => t.rowCount > 0);
      if (widget.isDkhp && hasData) {
        AppSecurityService.instance.setScreenSecure(true);
      } else {
        AppSecurityService.instance.setScreenSecure(false);
      }
    } on DkhpPasswordException {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSecurityService.instance.setScreenSecure(false);
      await _showPasswordDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('FormatException: ', '');
      });
      AppSecurityService.instance.setScreenSecure(false);
    }
  }

  Future<void> _showPasswordDialog() async {
    final controller = TextEditingController();
    bool obscure = true;

    final pwd = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          icon: const Icon(Icons.lock_rounded, color: Colors.blue, size: 36),
          title: const Text('Berkas Diproteksi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Berkas DHKP ini terenkripsi. Masukkan kata sandi untuk membukanya:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Kata Sandi',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setLocalState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Buka'),
            ),
          ],
        ),
      ),
    );

    if (pwd != null && pwd.isNotEmpty) {
      await _loadFile(password: pwd);
    } else {
      setState(() {
        _errorMessage = 'Kata sandi diperlukan untuk membuka berkas ini.';
      });
    }
  }

  /// Memproses impor berkas DHKP ke dalam database aplikasi.
  Future<void> _importDkhp() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.inventory_2_rounded,
          color: theme.colorScheme.primary,
          size: 38,
        ),
        title: const Text('Impor ke Buku Catatan'),
        content: Text(
          'Pasang data dari "${widget.fileName}" ke Buku Catatan Blok sekarang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Pasang Sekarang'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Tampilkan indikator proses
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Memasang data DHKP ke Buku Catatan...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final records = await DhkpPackageHelper.unpackDkhp(
        widget.file.path,
        password: _providedPassword,
      );
      await BlokDataStore.instance.loadAll();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Tutup loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sukses! ${records.length} data DHKP berhasil diimpor ke Buku Catatan.',
          ),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 5),
          action: widget.isExternal
              ? null
              : SnackBarAction(
                  label: 'Buka Catatan',
                  textColor: Colors.amberAccent,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BlokCatatanScreen(),
                      ),
                    );
                  },
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Tutup loading dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 36,
          ),
          title: const Text('Gagal Memasang DHKP'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  void _showFileInfoSheet() {
    final table = _currentTable;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.isDkhp
                        ? Icons.inventory_2_outlined
                        : Icons.table_chart_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Informasi Berkas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildInfoRow('Nama Berkas', widget.fileName),
              _buildInfoRow(
                'Tipe Dokumen',
                widget.isDkhp
                    ? 'Paket DHKP (.dkhp)'
                    : (widget.fileName.toLowerCase().endsWith('.csv')
                          ? 'Comma-Separated Values (.csv)'
                          : 'Excel Spreadsheet (.xlsx/.xls)'),
              ),
              _buildInfoRow('Jumlah Lembar (Sheet)', '${_tables.length}'),
              if (table != null) ...[
                _buildInfoRow('Lembar Aktif', table.sheetName),
                _buildInfoRow('Jumlah Baris Data', '${table.rowCount}'),
                _buildInfoRow('Jumlah Kolom', '${table.columnCount}'),
              ],
              _buildInfoRow('Lokasi Berkas', widget.file.path),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showRowDetails(int rowIndex, List<String> rowValues) {
    final table = _currentTable;
    if (table == null) return;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '#${rowIndex + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Rincian Baris Data',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: table.headers.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 8),
                  itemBuilder: (_, colIdx) {
                    final header = table.headers[colIdx];
                    final val = colIdx < rowValues.length
                        ? rowValues[colIdx]
                        : '';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        header,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: SelectableText(
                        val.isEmpty ? '-' : val,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: val.isEmpty ? Colors.grey : null,
                        ),
                      ),
                      trailing: val.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              tooltip: 'Salin nilai',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: val));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Disalin: $val'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            )
                          : null,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final table = _currentTable;

    // Filter baris berdasarkan pencarian
    List<List<String>> displayRows = [];
    if (table != null) {
      if (_searchQuery.trim().isEmpty) {
        displayRows = table.rows;
      } else {
        final q = _searchQuery.toLowerCase();
        displayRows = table.rows.where((row) {
          return row.any((cell) => cell.toLowerCase().contains(q));
        }).toList();
      }
    }

    // Hitung paginasi
    final totalRows = displayRows.length;
    final totalPages = max(1, (totalRows / _rowsPerPage).ceil());
    final effectivePage = _currentPage.clamp(1, totalPages);
    final startIndex = (effectivePage - 1) * _rowsPerPage;
    final endIndex = min(startIndex + _rowsPerPage, totalRows);
    final pageRows = (totalRows > 0)
        ? displayRows.sublist(startIndex, endIndex)
        : <List<String>>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Kembali',
            onPressed: _handleBack,
          ),
          title: _isSearchOpen
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Cari NOP, nama, atau kata kunci...',
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _currentPage = 1;
                        });
                      },
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _currentPage = 1;
                    });
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      widget.isDkhp
                          ? 'Pratinjau DHKP (Bisa Diimpor)'
                          : 'Pembaca Spreadsheet (Hanya Lihat)',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDkhp ? Colors.teal : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              icon: Icon(
                _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
              ),
              tooltip: _isSearchOpen ? 'Tutup Pencarian' : 'Cari Data',
              onPressed: () {
                setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                    _currentPage = 1;
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'Info Berkas',
              onPressed: _showFileInfoSheet,
            ),
            // Tombol impor khusus DHKP di AppBar
            if (widget.isDkhp)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonalIcon(
                  onPressed: _importDkhp,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: const Text('Impor'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Tab Selector jika terdapat lebih dari 1 sheet (pada Excel)
              if (_tables.length > 1)
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    itemCount: _tables.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final isSelected = idx == _activeTableIndex;
                      final t = _tables[idx];
                      return ChoiceChip(
                        label: Text('${t.sheetName} (${t.rowCount})'),
                        selected: isSelected,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _activeTableIndex = idx;
                            _currentPage = 1;
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      );
                    },
                  ),
                ),

              // Indikator hasil pencarian
              if (_searchQuery.trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  child: Text(
                    'Ditemukan $totalRows baris yang cocok dengan "$_searchQuery"',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),

              // Tampilan utama tabel
              Expanded(
                child: SpreadsheetDataView(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  isDkhp: widget.isDkhp,
                  table: table,
                  pageRows: pageRows,
                  startIndex: startIndex,
                  totalRows: totalRows,
                  searchQuery: _searchQuery,
                  horizontalController: _horizontalController,
                  verticalController: _verticalController,
                  onRetry: _loadFile,
                  onRowSelected: _showRowDetails,
                ),
              ),

              // Paginasi di bagian bawah
              if (!_isLoading && _errorMessage == null && table != null)
                SpreadsheetPaginationBar(
                  rowsPerPage: _rowsPerPage,
                  totalPages: totalPages,
                  effectivePage: effectivePage,
                  totalRows: totalRows,
                  startIndex: startIndex,
                  endIndex: endIndex,
                  onRowsPerPageChanged: (value) {
                    setState(() {
                      _rowsPerPage = value;
                      _currentPage = 1;
                    });
                  },
                  onPrevious: () =>
                      setState(() => _currentPage = effectivePage - 1),
                  onNext: () =>
                      setState(() => _currentPage = effectivePage + 1),
                ),

              // Banner khusus paket DHKP dengan tombol Impor
              if (widget.isDkhp && !_isLoading && _errorMessage == null)
                SpreadsheetImportBanner(table: table, onImport: _importDkhp),
            ],
          ),
        ),
      ),
    );
  }
}
