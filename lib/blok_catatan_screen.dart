import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_security_service.dart';
import 'batch_check_screen.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'blok_report_exporter.dart';
import 'blok_sync_service.dart';
import 'check_mode.dart';
import 'dhkp/blok_catatan_dialogs.dart';
import 'dhkp/blok_catatan_models.dart';
import 'dhkp/blok_catatan_widgets.dart';
import 'dhkp_grafik_view.dart';
import 'dkhp_package_helper.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'dusun_data.dart';
import 'file_importer.dart';
import 'google_drive_picker_dialog.dart';
import 'image_crop_helper.dart';
import 'kolase_foto_screen.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart';
import 'operator_mode_store.dart';
import 'tax_record.dart';
import 'unity_lerp_widgets.dart';

export 'dhkp/blok_catatan_models.dart';

class BlokCatatanScreen extends StatefulWidget {
  const BlokCatatanScreen({super.key});

  @override
  State<BlokCatatanScreen> createState() => _BlokCatatanScreenState();
}

class _BlokCatatanScreenState extends State<BlokCatatanScreen> {
  bool _loading = true;
  bool _busy = false;
  String _busyMessage = 'Memuat data DHKP...';
  IconData _busyIcon = Icons.sync_rounded;
  bool _isOperator = false;
  List<String> _allBloks = [];
  List<String> _bloks = [];
  Set<String> _whitelist = {};
  String? _selectedBlok;
  String? _selectedTahun;
  int? _selectedWilayah;
  DhkpKategoriFilter _kategoriFilter = DhkpKategoriFilter.semua;
  BlokSortBy _sortBy = BlokSortBy.blokWilayah;
  List<BlokRecord> _records = [];
  List<BlokRecord> _allScopeRecords = [];
  bool _tampilkanGrafik = false;

  // Paginasi & Optimasi Performa
  int _rowsPerPage = 50;
  int _currentPage = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Set<String> _cachedPhotoFileNames = {};
  Directory? _photosDir;

  // Cached summary statistics (dihitung sekali saat _loadRecords untuk 60fps)
  DhkpSummaryMetrics _summaryMetrics = const DhkpSummaryMetrics();

  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    AppSecurityService.instance.setScreenSecure(false);
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  /// Menyesuaikan proteksi tangkapan layar (FLAG_SECURE) secara dinamis.
  /// Aturan:
  /// - Aktif jika sedang berada di tampilan tabel catatan DHKP DAN terdapat data catatan yang termuat.
  /// - Nonaktif jika sedang di mode visual grafik (_tampilkanGrafik == true) atau belum ada data DHKP.
  void _updateScreenSecurity() {
    final hasData = _records.isNotEmpty || _allScopeRecords.isNotEmpty;
    final shouldSecure = !_tampilkanGrafik && hasData;
    AppSecurityService.instance.setScreenSecure(shouldSecure);
  }

  Future<void> _load() async {
    final isOperator = await OperatorModeStore.instance.isEnabled();
    final allBloks = await BlokDataStore.instance.blokList();

    if (DusunData.instance.isDusunLocked &&
        DusunData.instance.lockedDusunNumber != null) {
      final lockedNum = DusunData.instance.lockedDusunNumber!;
      final d = dusunByNumber(lockedNum);
      final whitelist =
          d?.bloks.toSet() ?? DusunData.instance.scope.allowedBloks.toSet();
      _isOperator = false;
      _allBloks = allBloks.where(whitelist.contains).toList();
      _bloks = _allBloks;
      _whitelist = whitelist;
      _selectedWilayah = lockedNum;
      _selectedBlok = semuaBlokValue;
      _selectedTahun = '${DateTime.now().year}';
    } else if (isOperator) {
      // Operator tidak terikat satu wilayah kerja — default melihat seluruh
      // wilayah desa (Semua Blok) agar ringkasan desa dan tren terlihat lengkap.
      _isOperator = true;
      _allBloks = allBloks;
      _bloks = allBloks;
      _whitelist = allBloks.toSet();
      _selectedWilayah = null;
      _selectedBlok = semuaBlokValue;
      _selectedTahun = '${DateTime.now().year}';
    } else {
      _isOperator = false;
      _allBloks = allBloks;
      _bloks = allBloks;
      _whitelist = allBloks.toSet();
      _selectedWilayah = null;
      _selectedBlok = semuaBlokValue;
      _selectedTahun = '${DateTime.now().year}';
    }

    // Pastikan seluruh data catatan blok & STTS selesai dimuat sebelum mematikan animasi loading
    if (_selectedBlok != null) {
      await _loadRecords();
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    // Sinkronisasi otomatis saat membuka DHKP
    unawaited(_triggerAutoSync(silent: true));
  }

  Future<void> _triggerAutoSync({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _busy = true;
        _busyMessage = 'Menyinkronkan perubahan data DHKP...';
        _busyIcon = Icons.cloud_sync_outlined;
      });
    }
    try {
      final newChanges = await BlokSyncService.instance.syncCurrentScope(
        blok: _selectedBlok,
      );
      if (newChanges > 0) {
        await _loadRecords();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$newChanges perubahan data baru & gambar dokumentasi berhasil disinkronkan.',
              ),
              backgroundColor: Colors.teal[800],
            ),
          );
        }
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Semua data perubahan DHKP sudah sinkron dengan Drive.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal sinkronisasi data: $e')));
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Khusus Mode Operator — pilih dusun mana yang mau dilihat, lalu daftar
  /// Blok yang tersedia mengikuti blok-blok dusun itu.
  void _pilihWilayah(int? wilayah) {
    if (wilayah == null) {
      setState(() {
        _selectedWilayah = null;
        _whitelist = _allBloks.toSet();
        _bloks = _allBloks;
        _selectedBlok = semuaBlokValue;
      });
      _loadRecords(
        setBusy: true,
        busyMessage: 'Memuat data seluruh wilayah desa...',
        busyIcon: Icons.map_outlined,
      );
      return;
    }
    final whitelist = dusunByNumber(wilayah)?.bloks.toSet() ?? {};
    setState(() {
      _selectedWilayah = wilayah;
      _whitelist = whitelist;
      _bloks = _allBloks.where(whitelist.contains).toList();
      _selectedBlok = semuaBlokValue;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: 'Memuat data wilayah Dusun $wilayah...',
      busyIcon: Icons.map_outlined,
    );
  }

  Future<void> _loadRecords({
    bool setBusy = false,
    String? busyMessage,
    IconData? busyIcon,
  }) async {
    final blok = _selectedBlok;
    if (blok == null) return;

    if (setBusy && mounted) {
      setState(() {
        _busy = true;
        _busyMessage = busyMessage ?? 'Memuat data catatan blok...';
        _busyIcon = busyIcon ?? Icons.sync_rounded;
      });
    }

    // Cache direktori & nama file foto di memori agar sel tabel tidak melakukan I/O disk
    final photosDir = await DhkpPackageHelper.photosDirectory();
    final photoNames = await DhkpPackageHelper.refreshPhotoNamesCache();

    final allScope = blok == semuaBlokValue
        ? await BlokDataStore.instance.byWhitelist(
            _whitelist,
            tahun: _selectedTahun,
            sortBy: _sortBy,
          )
        : await BlokDataStore.instance.byBlok(
            blok,
            tahun: _selectedTahun,
            sortBy: _sortBy,
          );

    final metrics = DhkpSummaryMetrics.compute(allScope);
    var records = DhkpSummaryMetrics.filterByKategori(
      allScope,
      _kategoriFilter,
    );
    records = DhkpSummaryMetrics.filterBySearch(records, _searchQuery);

    if (!mounted) return;
    setState(() {
      _photosDir = photosDir;
      _cachedPhotoFileNames = photoNames;
      _records = records;
      _allScopeRecords = allScope;
      _summaryMetrics = metrics;

      final maxPage = _rowsPerPage > 0
          ? (records.isEmpty ? 0 : ((records.length - 1) ~/ _rowsPerPage))
          : 0;
      if (_currentPage > maxPage) {
        _currentPage = 0;
      }
      _busy = false;
    });
    _updateScreenSecurity();
  }

  /// Data lingkup saat ini (mengikuti pilihan Blok & Tahun di layar atau blokOverride),
  /// selalu terurut blok+wilayah menaik — dipakai untuk unduh/bagikan/cetak
  /// supaya berkasnya tetap baku urutannya apa pun filter urutan tampilan
  /// yang sedang dipakai di layar.
  Future<List<BlokRecord>> _scopedRecordsForExport([
    String? blokOverride,
  ]) async {
    final blok = blokOverride ?? _selectedBlok;
    final records = (blok == null || blok == semuaBlokValue)
        ? (_whitelist.isNotEmpty
              ? await BlokDataStore.instance.byWhitelist(
                  _whitelist,
                  tahun: _selectedTahun,
                )
              : await BlokDataStore.instance.forReport(tahun: _selectedTahun))
        : await BlokDataStore.instance.byBlok(blok, tahun: _selectedTahun);

    return DhkpSummaryMetrics.filterByKategori(records, _kategoriFilter);
  }

  void _pilihBlok(String? blok) {
    if (blok == null) return;
    setState(() {
      _selectedBlok = blok;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: blok == semuaBlokValue
          ? 'Memuat data semua blok...'
          : 'Memuat data Blok ${int.tryParse(blok) ?? blok}...',
      busyIcon: Icons.grid_view_rounded,
    );
  }

  void _pilihTahun(String? tahun) {
    setState(() {
      _selectedTahun = tahun;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: tahun == null
          ? 'Memuat data semua tahun pajak...'
          : 'Memuat data tahun pajak $tahun...',
      busyIcon: Icons.calendar_month_outlined,
    );
  }

  void _pilihKategori(DhkpKategoriFilter? kategori) {
    if (kategori == null) return;
    setState(() {
      _kategoriFilter = kategori;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: 'Menyaring kategori: ${kategori.label}...',
      busyIcon: Icons.filter_alt_outlined,
    );
  }

  void _pilihSort(BlokSortBy? sortBy) {
    if (sortBy == null) return;
    setState(() {
      _sortBy = sortBy;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: 'Mengurutkan data: ${sortBy.label}...',
      busyIcon: Icons.sort_rounded,
    );
  }

  /// Hapus satu baris — mis. untuk mengoreksi baris yang salah tercatat
  /// (data uji coba, salah impor, dsb).
  Future<void> _hapusBaris(BlokRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Baris Ini?'),
        content: Text(
          '${record.namaWajibPajak} — NOP ${record.nop} (${record.tahunBayar}) akan dihapus '
          'permanen dari data DHKP.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (mounted) {
      setState(() {
        _busy = true;
        _busyMessage = 'Menghapus baris data DHKP...';
        _busyIcon = Icons.delete_sweep_outlined;
      });
    }
    await BlokDataStore.instance.deleteByKey(record.uniqueKey);
    await _loadRecords();
  }

  Future<void> _editCatatanDialog(BlokRecord record) async {
    final newCatatan = await showEditCatatanDialog(context, record);
    if (newCatatan != null) {
      if (mounted) {
        setState(() {
          _busy = true;
          _busyMessage = 'Menyimpan catatan petugas...';
          _busyIcon = Icons.save_outlined;
        });
      }
      final newRecord = record.copyWith(catatan: newCatatan);
      await BlokDataStore.instance.upsert(newRecord);
      unawaited(
        BlokSyncService.instance.recordChange(
          record: newRecord,
          catatan: newCatatan,
        ),
      );
      await _loadRecords();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan petugas berhasil disimpan.')),
      );
    }
  }

  /// Dialog Rincian Objek & Pembayaran sesuai lembaran resmi Bapenda (INFORMASI DATA PEMBAYARAN)
  Future<void> _bukaRincianDialog(BlokRecord record) async {
    await showRincianObjekDialog(
      context,
      record: record,
      onCekStatusBayar: () => _bukaStatusBayar(record),
      onCekTagihan: () => _bukaTagihan(record),
      onEditRincian: () => _editRincianDialog(record),
    );
  }

  /// Dialog Edit Rincian — petugas hanya menyesuaikan Nama Wajib Pajak/Pemilik, Alamat OP, dan Alamat WP
  Future<void> _editRincianDialog(BlokRecord record) async {
    final res = await showEditRincianDialog(context, record);
    if (res != null) {
      if (mounted) {
        setState(() {
          _busy = true;
          _busyMessage = 'Menyimpan perubahan nama & alamat...';
          _busyIcon = Icons.save_outlined;
        });
      }
      final updatedRecord = record.copyWith(
        namaWajibPajak: res.namaWajibPajak,
        alamatObjek: res.alamatObjek,
        alamatWp: res.alamatWp,
      );
      await BlokDataStore.instance.upsert(updatedRecord);
      unawaited(BlokSyncService.instance.recordChange(record: updatedRecord));
      await _loadRecords();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama & alamat berhasil diperbarui.')),
      );
    }
  }

  void _bukaTagihan(BlokRecord record) {
    Navigator.pop(
      context,
      BlokNavigationRequest(
        blok: record.blok,
        wilayah: record.wilayah,
        tahun: record.tahunBayar,
        targetMode: CheckMode.tagihan,
      ),
    );
  }

  void _cetakBuktiBayar(BlokRecord record) {
    Navigator.pop(
      context,
      BlokNavigationRequest(
        blok: record.blok,
        wilayah: record.wilayah,
        tahun: record.tahunBayar,
        targetMode: CheckMode.statusBayar,
      ),
    );
  }

  void _bukaStatusBayar(BlokRecord record) {
    Navigator.pop(
      context,
      BlokNavigationRequest(
        blok: record.blok,
        wilayah: record.wilayah,
        tahun: record.tahunBayar,
        targetMode: CheckMode.statusBayar,
      ),
    );
  }

  Future<void> _cekStatusBayarMassal() async {
    final List<String> availableBloks;
    if (DusunData.instance.isDusunLocked &&
        DusunData.instance.lockedDusunNumber != null) {
      final d = dusunByNumber(DusunData.instance.lockedDusunNumber!);
      final bloks = d?.bloks ?? DusunData.instance.scope.allowedBloks;
      availableBloks = bloks.where(_allBloks.contains).toList();
    } else if (_selectedWilayah != null) {
      final d = dusunByNumber(_selectedWilayah!);
      final bloks = d?.bloks ?? _bloks;
      availableBloks = bloks.where(_allBloks.contains).toList();
    } else {
      availableBloks = List<String>.from(_allBloks);
    }

    availableBloks.sort(
      (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
    );

    if (availableBloks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data blok yang tersedia untuk wilayah ini.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final rawRecords = await BlokDataStore.instance.loadAll();
    final allRecords = _selectedTahun != null
        ? rawRecords
              .where(
                (r) => r.tahunBayar.isEmpty || r.tahunBayar == _selectedTahun,
              )
              .toList()
        : rawRecords;
    final Map<String, List<BlokRecord>> recordsByBlok = {};
    for (final r in allRecords) {
      final b = nopBlok(r.nop);
      if (b.isNotEmpty) {
        recordsByBlok.putIfAbsent(b, () => []).add(r);
      }
    }

    if (!mounted) return;

    final selectedRecords = await showPilihBlokCekMassalDialog(
      context,
      availableBloks: availableBloks,
      recordsByBlok: recordsByBlok,
      selectedWilayah: _selectedWilayah,
    );

    if (selectedRecords == null || selectedRecords.isEmpty || !mounted) return;

    final taxRecords = selectedRecords
        .map((r) => TaxRecord(nop: r.nop, namaWajibPajak: r.namaWajibPajak))
        .toList();
    final tahun =
        _selectedTahun ??
        (selectedRecords.first.tahunBayar.isNotEmpty
            ? selectedRecords.first.tahunBayar
            : '2026');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchCheckScreen(records: taxRecords, tahun: tahun),
      ),
    );

    if (!mounted) return;
    await _loadRecords(
      setBusy: true,
      busyMessage: 'Memperbarui status bayar dari hasil pengecekan...',
      busyIcon: Icons.fact_check_outlined,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pengecekan selesai. Data DHKP telah otomatis diperbarui.',
        ),
        backgroundColor: Colors.teal,
      ),
    );
  }

  /// Membuat berkas laporan (.dat) berisi rincian seluruh objek DHKP, status pembayaran, catatan, dan foto dokumentasi
  Future<void> _buatLaporanDatDialog() async {
    final targetRecords = await BlokDataStore.instance.loadAll();
    if (targetRecords.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada data DHKP untuk dilaporkan.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    if (!mounted) return;
    final konfirmasi = await showBuatLaporanDatDialog(
      context,
      targetRecords.length,
    );

    if (!konfirmasi || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage =
          'Menyusun & mengemas berkas laporan .dat (${targetRecords.length} data)...';
      _busyIcon = Icons.download_rounded;
    });

    try {
      final now = DateTime.now();
      String pad(int n) => n.toString().padLeft(2, '0');
      final dateStr =
          '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
      final fileName = 'Laporan_PBB_SemuaData_$dateStr.dat';
      final tempPath = '${Directory.systemTemp.path}/$fileName';

      await DhkpPackageHelper.packDkhp(
        outputPath: tempPath,
        records: targetRecords,
        baseRecords: targetRecords,
        deltaOnly: false,
        includePhotos: true,
      );

      final bytes = await File(tempPath).readAsBytes();
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      try {
        final tmp = File(tempPath);
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Laporan .dat tersimpan di $location (${targetRecords.length} objek PBB)',
          ),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat berkas laporan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _uploadDataDialog() async {
    final action = await showUploadDataSourceDialog(context);
    if (action == null || !mounted) return;

    if (action == 'file') {
      try {
        final files = await FilePicker.pickFiles(type: FileType.any);
        if (files.isEmpty || files.first.path == null) {
          return;
        }
        if (!GoogleDriveService.isSupportedDkhpFileName(files.first.name)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Format berkas belum didukung. Silakan pilih berkas data DHKP, Excel, atau Laporan (.dat).',
              ),
            ),
          );
          return;
        }
        await _importDkhpFromPath(
          files.first.path!,
          sourceLabel: 'berkas lokal',
        );
      } on DhkpBackupValidationException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      } catch (e) {
        if (!mounted) return;
        final isMismatch = e.toString().contains('Data tidak sesuai');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMismatch ? 'Data tidak sesuai' : 'Gagal membaca berkas: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (action == 'google_drive') {
      try {
        final filePath = await showGoogleDrivePickerDialog(context);
        if (filePath == null) {
          return;
        }
        await _importDkhpFromPath(filePath, sourceLabel: 'Google Drive');
      } on DhkpBackupValidationException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      } catch (e) {
        if (!mounted) return;
        final isMismatch = e.toString().contains('Data tidak sesuai');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMismatch
                  ? 'Data tidak sesuai'
                  : 'Gagal membaca berkas Google Drive: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
  }

  Future<void> _importDkhpFromPath(
    String path, {
    required String sourceLabel,
  }) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _busyMessage = 'Mengekstrak & memuat berkas DHKP ($sourceLabel)...';
        _busyIcon = Icons.upload_file_rounded;
      });
    }
    try {
      if (DhkpPackageHelper.isDkhpArchivePath(path)) {
        final newRecords = await DhkpPackageHelper.unpackDkhp(path);
        await _load();
        if (!mounted) return;
        final isDat = path.toLowerCase().endsWith('.dat');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isDat
                  ? 'Laporan .dat berhasil dipasang ($sourceLabel): ${newRecords.length} data & foto berhasil diperbarui.'
                  : 'Paket DHKP berhasil diimpor ($sourceLabel): ${newRecords.length} data & gambar dokumentasi berhasil dimuat.',
            ),
          ),
        );
        return;
      }

      final importedBlokRecords = await FileImporter.importBlokRecordsFrom(
        path,
      );
      if (importedBlokRecords.isNotEmpty) {
        await BlokDataStore.instance.upsertAll(importedBlokRecords);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${importedBlokRecords.length} data DHKP lengkap berhasil diimpor ($sourceLabel).',
            ),
          ),
        );
        return;
      }

      final taxRecords = await FileImporter.importFrom(path);
      if (taxRecords.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ditemukan NOP yang valid di file ini.'),
          ),
        );
        return;
      }

      final nowYear = '${DateTime.now().year}';
      final newRecords = taxRecords.map(
        (t) => BlokRecord(
          nop: t.nop,
          namaWajibPajak:
              t.namaWajibPajak ?? 'WP ${nopBlok(t.nop)}/${nopWilayah(t.nop)}',
          tahunBayar: nowYear,
          tanggalBayar: t.isPaid
              ? ((t.tanggalBayar != null && t.tanggalBayar!.trim().isNotEmpty)
                    ? t.tanggalBayar!.trim()
                    : DateTime.now().toIso8601String().substring(0, 10))
              : '',
          jumlahPbb: t.jumlahPbb ?? '',
          statusBayar: t.isPaid ? 'Sudah Bayar' : 'Belum Bayar',
        ),
      );
      await BlokDataStore.instance.upsertAll(newRecords);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${newRecords.length} data DHKP berhasil diunggah ($sourceLabel).',
          ),
        ),
      );
    } on DhkpBackupValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      final isMismatch = e.toString().contains('Data tidak sesuai');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMismatch ? 'Data tidak sesuai' : 'Gagal memuat berkas: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Pop-up preview foto ala profil WhatsApp (bisa di-zoom/pan, ganti/upload foto baru, atau hapus)
  Future<void> _bukaWhatsAppPreview(BlokRecord record) async {
    final photoFile = await DhkpPackageHelper.findPhotoForNop(
      record.nop,
      customFileName: record.namaFoto,
    );
    if (!mounted) return;

    await showWhatsAppPhotoPreviewDialog(
      context,
      record: record,
      initialPhotoFile: photoFile,
      onDeletePhoto: () => _hapusFoto(record),
      onPickAndSavePhoto: () => _pilihDanSimpanFoto(record),
    );
  }

  /// Memilih foto dari Kamera, Galeri, atau File Picker lalu menyimpannya secara lokal
  Future<File?> _pilihDanSimpanFoto(BlokRecord record) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pilih Sumber Foto',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Ambil dari Kamera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.teal),
              title: const Text('Pilih dari Galeri'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.amber),
              title: const Text('Pilih dari Penyimpanan Perangkat'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (method == null) return null;

    Uint8List? imageBytes;

    try {
      if (method == 'camera' || method == 'gallery') {
        try {
          final picker = ImagePicker();
          final source = method == 'camera'
              ? ImageSource.camera
              : ImageSource.gallery;
          final picked = await picker.pickImage(
            source: source,
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 88,
          );
          if (picked != null) {
            imageBytes = await picked.readAsBytes();
          }
        } catch (_) {
          final res = await FilePicker.pickFiles(type: FileType.image);
          if (res.isNotEmpty && res.first.path != null) {
            final f = File(res.first.path!);
            imageBytes = await f.readAsBytes();
          }
        }
      } else if (method == 'file') {
        final res = await FilePicker.pickFiles(type: FileType.image);
        if (res.isNotEmpty && res.first.path != null) {
          final f = File(res.first.path!);
          imageBytes = await f.readAsBytes();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memilih gambar: $e')));
      }
      return null;
    }

    if (imageBytes == null) return null;

    if (mounted) {
      setState(() {
        _busy = true;
        _busyMessage = 'Memotong & menyimpan gambar dokumentasi...';
        _busyIcon = Icons.crop_square_rounded;
      });
    }

    try {
      // Potong otomatis dimensi gambar menjadi rasio 1:1 (persegi) agar rapi
      final squareBytes = ImageCropHelper.cropToSquare(imageBytes);

      final photosDir = await DhkpPackageHelper.photosDirectory();
      final cleanNop = record.nop.replaceAll(RegExp(r'[^0-9]'), '');
      final fileName = '$cleanNop.jpg';
      final targetFile = File('${photosDir.path}/$fileName');
      await targetFile.writeAsBytes(squareBytes);

      final updatedRecord = record.copyWith(namaFoto: fileName);
      await BlokDataStore.instance.upsert(updatedRecord);
      unawaited(
        BlokSyncService.instance.recordChange(
          record: updatedRecord,
          namaFoto: fileName,
          sourcePhotoFile: targetFile,
        ),
      );
      await _loadRecords();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto berhasil disimpan.')),
        );
      }
      return targetFile;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _hapusFoto(BlokRecord record) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _busyMessage = 'Menghapus gambar dokumentasi...';
        _busyIcon = Icons.delete_outline_rounded;
      });
    }
    try {
      final photo = await DhkpPackageHelper.findPhotoForNop(
        record.nop,
        customFileName: record.namaFoto,
      );
      if (photo != null && await photo.exists()) {
        try {
          await photo.delete();
        } catch (_) {}
      }
      final updated = record.copyWith(namaFoto: '');
      await BlokDataStore.instance.upsert(updated);
      unawaited(
        BlokSyncService.instance.recordChange(record: updated, namaFoto: ''),
      );
      await _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Foto telah dihapus.')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _buildGambarCell(BlokRecord r) {
    File? photo;
    final dir = _photosDir;
    if (dir != null && _cachedPhotoFileNames.isNotEmpty) {
      photo = DhkpPackageHelper.findPhotoForNopSync(
        r.nop,
        customFileName: r.namaFoto,
        photosDir: dir,
        cachedNames: _cachedPhotoFileNames,
      );
    }
    final hasPhoto = photo != null;
    return InkWell(
      onTap: () => _bukaWhatsAppPreview(r),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Tooltip(
          message: hasPhoto
              ? 'Klik untuk perbesar / ganti foto'
              : 'Klik untuk upload foto',
          child: CircleAvatar(
            radius: 18,
            backgroundColor: hasPhoto
                ? Colors.teal.shade100
                : Colors.grey.shade200,
            backgroundImage: hasPhoto ? FileImage(photo) : null,
            child: hasPhoto
                ? null
                : Icon(
                    Icons.add_a_photo_outlined,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
          ),
        ),
      ),
    );
  }

  Future<OpsiEksporResult?> _pilihOpsiEkspor({
    required String title,
    required String actionButtonLabel,
    required IconData actionIcon,
    bool fixedPdf = false,
  }) {
    return showPilihOpsiEksporDialog(
      context,
      bloks: _bloks,
      selectedBlok: _selectedBlok,
      title: title,
      actionButtonLabel: actionButtonLabel,
      actionIcon: actionIcon,
      fixedPdf: fixedPdf,
    );
  }

  Future<void> _unduhLaporan() async {
    final opsi = await _pilihOpsiEkspor(
      title: 'Unduh Laporan DHKP',
      actionButtonLabel: 'Unduh Berkas',
      actionIcon: Icons.download_rounded,
    );
    if (opsi == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'Menyusun berkas ${opsi.format.label}...';
      _busyIcon = Icons.download_rounded;
    });
    try {
      final records = await _scopedRecordsForExport(opsi.blok);
      if (records.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada data untuk diunduh.')),
        );
        return;
      }
      final blokTitle = opsi.blok == semuaBlokValue
          ? 'Semua Blok'
          : 'Blok ${opsi.blok}';
      final bytes = await BlokReportExporter.build(
        opsi.format,
        records,
        tahun: _selectedTahun,
        blokTitle: blokTitle,
        onProgress: (current, total) async {
          if (!mounted) return;
          setState(() {
            _busyMessage = 'Menyusun halaman $current dari $total...';
          });
        },
      );
      final prefix = opsi.blok == semuaBlokValue
          ? 'laporan_data_blok'
          : 'laporan_blok_${opsi.blok.toLowerCase().replaceAll(' ', '_')}';
      final fileName = BlokReportExporter.fileName(
        opsi.format,
        tahun: _selectedTahun,
        prefix: prefix,
      );
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Laporan tersimpan di $location')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuat laporan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bagikanLaporan() async {
    final opsi = await _pilihOpsiEkspor(
      title: 'Bagikan Laporan DHKP',
      actionButtonLabel: 'Bagikan Berkas',
      actionIcon: Icons.share_rounded,
    );
    if (opsi == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage =
          'Menyiapkan berkas ${opsi.format.label} untuk dibagikan...';
      _busyIcon = Icons.share_rounded;
    });
    try {
      final records = await _scopedRecordsForExport(opsi.blok);
      if (records.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada data untuk dibagikan.')),
        );
        return;
      }
      final blokTitle = opsi.blok == semuaBlokValue
          ? 'Semua Blok'
          : 'Blok ${opsi.blok}';
      final bytes = await BlokReportExporter.build(
        opsi.format,
        records,
        tahun: _selectedTahun,
        blokTitle: blokTitle,
        onProgress: (current, total) async {
          if (!mounted) return;
          setState(() {
            _busyMessage = 'Menyusun halaman $current dari $total...';
          });
        },
      );
      final prefix = opsi.blok == semuaBlokValue
          ? 'laporan_data_blok'
          : 'laporan_blok_${opsi.blok.toLowerCase().replaceAll(' ', '_')}';
      final fileName = BlokReportExporter.fileName(
        opsi.format,
        tahun: _selectedTahun,
        prefix: prefix,
      );
      await NativeFileHelper.shareBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: DownloadHelper.mimeTypeFor(fileName),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membagikan laporan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cetakLaporan() async {
    final opsi = await _pilihOpsiEkspor(
      title: 'Cetak Laporan DHKP',
      actionButtonLabel: 'Buka Cetakan',
      actionIcon: Icons.print_rounded,
      fixedPdf: true,
    );
    if (opsi == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'Menyiapkan pratinjau cetak PDF...';
      _busyIcon = Icons.print_rounded;
    });
    try {
      final records = await _scopedRecordsForExport(opsi.blok);
      if (records.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada data untuk dicetak.')),
        );
        return;
      }
      final blokTitle = opsi.blok == semuaBlokValue
          ? 'Semua Blok'
          : 'Blok ${opsi.blok}';
      final bytes = await BlokReportExporter.build(
        BlokExportFormat.pdf,
        records,
        tahun: _selectedTahun,
        blokTitle: blokTitle,
        onProgress: (current, total) async {
          if (!mounted) return;
          setState(() {
            _busyMessage = 'Menyusun halaman $current dari $total...';
          });
        },
      );
      if (!mounted) return;
      final tahunLabel = _selectedTahun ?? 'semua-tahun';
      final fileName = opsi.blok == semuaBlokValue
          ? 'Laporan Data Blok ($tahunLabel).pdf'
          : 'Laporan Blok ${opsi.blok} ($tahunLabel).pdf';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(pdfBytes: bytes, fileName: fileName),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menyiapkan cetakan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _bukaKolaseFoto() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            KolaseFotoScreen(initialBlok: _selectedBlok, bloks: _bloks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data DHKP'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _tampilkanGrafik = !_tampilkanGrafik;
                _updateScreenSecurity();
              });
            },
            icon: Icon(
              _tampilkanGrafik
                  ? Icons.receipt_long_rounded
                  : Icons.bar_chart_rounded,
            ),
            tooltip: _tampilkanGrafik
                ? 'Beralih ke Buku Catatan (Tabel)'
                : 'Beralih ke Visual Grafik',
          ),
          IconButton(
            onPressed: _uploadDataDialog,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload Data DHKP / Laporan (.dat)',
          ),
          IconButton(
            onPressed: _buatLaporanDatDialog,
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Buat Laporan (.dat)',
          ),
          IconButton(
            onPressed: _busy ? null : () => _triggerAutoSync(silent: false),
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sinkronkan Perubahan (Drive Bersama)',
          ),
          if (_bloks.isNotEmpty && !_tampilkanGrafik)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Menu & Aksi Lainnya',
              onSelected: (val) {
                switch (val) {
                  case 'cetak':
                    _cetakLaporan();
                    break;
                  case 'bagikan':
                    _bagikanLaporan();
                    break;
                  case 'unduh':
                    _unduhLaporan();
                    break;
                  case 'kolase':
                    _bukaKolaseFoto();
                    break;
                  case 'cek_massal':
                    _cekStatusBayarMassal();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'cetak',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('Cetak Laporan'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'bagikan',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Bagikan Laporan'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'unduh',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('Unduh Berkas (PDF/Excel/CSV)'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'kolase',
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome_mosaic_outlined),
                    title: Text('Kolase Gambar Dokumentasi'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'cek_massal',
                  child: ListTile(
                    leading: Icon(Icons.fact_check_outlined),
                    title: Text('Cek Status Bayar Massal'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: (_loading || (_busy && _allBloks.isEmpty))
              ? BlokCatatanLoadingView(
                  key: const ValueKey('loading-view'),
                  title: _loading
                      ? 'Memuat Data DHKP & Status Bayar'
                      : _busyMessage,
                )
              : (_allBloks.isEmpty || (!_isOperator && _bloks.isEmpty))
              ? const Center(
                  key: ValueKey('empty-view'),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Belum ada data DHKP. Tekan tombol Upload Data di kanan atas '
                      'untuk mengunggah berkas.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Padding(
                  key: const ValueKey('content-view'),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_tampilkanGrafik) ...[
                        if (DusunData.instance.isDusunLocked) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.blueGrey.shade900
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.blueGrey.shade700
                                    : Colors.blue.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: isDark
                                      ? Colors.blue.shade200
                                      : Colors.blue.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Pembatas Wilayah: Dusun $_selectedWilayah (${_bloks.length} blok)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.blue.shade200
                                          : Colors.blue.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ] else if (_isOperator || dusunList.length > 1) ...[
                          DropdownButtonFormField<int?>(
                            initialValue: _selectedWilayah,
                            decoration: const InputDecoration(
                              labelText: 'Wilayah (Dusun)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Semua Wilayah (Desa)'),
                              ),
                              for (final dusun in dusunList)
                                DropdownMenuItem<int?>(
                                  value: dusun.number,
                                  child: Text(
                                    '${dusun.label} (${dusun.bloks.length} blok)',
                                  ),
                                ),
                            ],
                            onChanged: _pilihWilayah,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'blok-dropdown-$_selectedWilayah',
                                ),
                                initialValue: _selectedBlok,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Blok',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: semuaBlokValue,
                                    child: Text(
                                      'Semua Blok',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  for (final b in _bloks)
                                    DropdownMenuItem(
                                      value: b,
                                      child: Text(
                                        'Blok ${int.parse(b)}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _pilihBlok,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: _selectedTahun,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Tahun',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Semua'),
                                  ),
                                  for (final y in availableDhkpYears())
                                    DropdownMenuItem(
                                      value: '$y',
                                      child: Text('$y'),
                                    ),
                                ],
                                onChanged: _pilihTahun,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText:
                                      'Cari Nama WP, NOP, atau Alamat Objek...',
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 20,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              _currentPage = 0;
                                            });
                                            _loadRecords();
                                          },
                                        )
                                      : null,
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _searchQuery = val;
                                    _currentPage = 0;
                                  });
                                  _loadRecords();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<DhkpKategoriFilter>(
                              tooltip:
                                  'Filter Kategori: ${_kategoriFilter.label}',
                              initialValue: _kategoriFilter,
                              onSelected: _pilihKategori,
                              itemBuilder: (context) => [
                                for (final k in DhkpKategoriFilter.values)
                                  PopupMenuItem<DhkpKategoriFilter>(
                                    value: k,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _kategoriFilter == k
                                              ? Icons
                                                    .radio_button_checked_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          size: 18,
                                          color: _kategoriFilter == k
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          k.label,
                                          style: TextStyle(
                                            fontWeight: _kategoriFilter == k
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      _kategoriFilter !=
                                          DhkpKategoriFilter.semua
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : null,
                                  border: Border.all(
                                    color:
                                        _kategoriFilter !=
                                            DhkpKategoriFilter.semua
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _kategoriFilter !=
                                              DhkpKategoriFilter.semua
                                          ? Icons.filter_alt_rounded
                                          : Icons.filter_list_rounded,
                                      size: 20,
                                      color:
                                          _kategoriFilter !=
                                              DhkpKategoriFilter.semua
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer
                                          : null,
                                    ),
                                    if (_kategoriFilter !=
                                        DhkpKategoriFilter.semua) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        _kategoriFilter.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<BlokSortBy>(
                              tooltip: 'Urutkan: ${_sortBy.label}',
                              initialValue: _sortBy,
                              onSelected: _pilihSort,
                              itemBuilder: (context) => [
                                for (final s in BlokSortBy.values)
                                  PopupMenuItem<BlokSortBy>(
                                    value: s,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _sortBy == s
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          size: 18,
                                          color: _sortBy == s
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          s.label,
                                          style: TextStyle(
                                            fontWeight: _sortBy == s
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _sortBy != BlokSortBy.blokWilayah
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.secondaryContainer
                                      : null,
                                  border: Border.all(
                                    color: _sortBy != BlokSortBy.blokWilayah
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.secondary
                                        : Theme.of(context).colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sort_rounded,
                                      size: 20,
                                      color: _sortBy != BlokSortBy.blokWilayah
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onSecondaryContainer
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      SmoothActivityBanner(
                        isActive: _busy,
                        message: _busyMessage,
                        icon: _busyIcon,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                      ),
                      if (!_busy) const SizedBox(height: 8),
                      Expanded(
                        child: _tampilkanGrafik
                            ? DhkpGrafikView(
                                records: _allScopeRecords.isNotEmpty
                                    ? _allScopeRecords
                                    : _records,
                                selectedBlok: _selectedBlok,
                                selectedWilayah: _selectedWilayah,
                              )
                            : _records.isEmpty
                            ? const Center(
                                child: Text('Tidak ada data untuk filter ini.'),
                              )
                            : () {
                                final totalRecords = _records.length;
                                final totalPages = _rowsPerPage > 0
                                    ? (totalRecords == 0
                                          ? 1
                                          : ((totalRecords - 1) ~/
                                                    _rowsPerPage) +
                                                1)
                                    : 1;
                                final safePage = _currentPage.clamp(
                                  0,
                                  totalPages > 0 ? totalPages - 1 : 0,
                                );
                                final startIndex = _rowsPerPage > 0
                                    ? safePage * _rowsPerPage
                                    : 0;
                                final endIndex = _rowsPerPage > 0
                                    ? ((safePage + 1) * _rowsPerPage >
                                              totalRecords
                                          ? totalRecords
                                          : (safePage + 1) * _rowsPerPage)
                                    : totalRecords;
                                final pagedRecords = totalRecords == 0
                                    ? <BlokRecord>[]
                                    : _records.sublist(startIndex, endIndex);

                                return Column(
                                  children: [
                                    Expanded(
                                      child: Scrollbar(
                                        controller: _verticalScrollController,
                                        thumbVisibility: true,
                                        notificationPredicate: (notif) =>
                                            notif.metrics.axis == Axis.vertical,
                                        child: Scrollbar(
                                          controller:
                                              _horizontalScrollController,
                                          thumbVisibility: true,
                                          notificationPredicate: (notif) =>
                                              notif.metrics.axis ==
                                              Axis.horizontal,
                                          child: SingleChildScrollView(
                                            controller:
                                                _horizontalScrollController,
                                            scrollDirection: Axis.horizontal,
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            child: SingleChildScrollView(
                                              controller:
                                                  _verticalScrollController,
                                              scrollDirection: Axis.vertical,
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              child: DataTable(
                                                columnSpacing: 18,
                                                horizontalMargin: 12,
                                                columns: const [
                                                  DataColumn(label: Text('No')),
                                                  DataColumn(
                                                    label: Text('Nama WP'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('NOP / Blok'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Tahun Pajak'),
                                                  ),
                                                  DataColumn(
                                                    label: Text(
                                                      'Pokok / Ketetapan',
                                                    ),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Status Bayar'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Gambar'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Aksi'),
                                                  ),
                                                  DataColumn(
                                                    label: Text('Catatan'),
                                                  ),
                                                ],
                                                rows: [
                                                  for (
                                                    var i = 0;
                                                    i < pagedRecords.length;
                                                    i++
                                                  ) ...[
                                                    () {
                                                      final r = pagedRecords[i];
                                                      final isDark =
                                                          Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark;

                                                      return DataRow(
                                                        color: WidgetStateProperty.resolveWith<Color?>((
                                                          states,
                                                        ) {
                                                          if (r.isTargetPemda) {
                                                            return isDark
                                                                ? Colors
                                                                      .red
                                                                      .shade900
                                                                      .withValues(
                                                                        alpha:
                                                                            0.38,
                                                                      )
                                                                : Colors
                                                                      .red
                                                                      .shade100
                                                                      .withValues(
                                                                        alpha:
                                                                            0.65,
                                                                      );
                                                          }
                                                          return null;
                                                        }),
                                                        cells: [
                                                          DataCell(
                                                            Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Text(
                                                                  '${startIndex + i + 1}',
                                                                ),
                                                                if (r
                                                                    .isTargetPemda) ...[
                                                                  const SizedBox(
                                                                    width: 4,
                                                                  ),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          4,
                                                                      vertical:
                                                                          1,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .red
                                                                          .shade700,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            4,
                                                                          ),
                                                                    ),
                                                                    child: const Text(
                                                                      'PEMDA',
                                                                      style: TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontSize:
                                                                            9,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                          ),
                                                          DataCell(
                                                            Text(
                                                              r.namaWajibPajak,
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                          DataCell(
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                  r.nop,
                                                                  style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  'Blok ${r.blok} No ${r.wilayah}',
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          DataCell(
                                                            Text(r.tahunBayar),
                                                          ),
                                                          DataCell(
                                                            Text(
                                                              r
                                                                      .jumlahPbb
                                                                      .isEmpty
                                                                  ? '-'
                                                                  : r.jumlahPbb,
                                                            ),
                                                          ),
                                                          DataCell(
                                                            DhkpStatusBadge(
                                                              record: r,
                                                            ),
                                                          ),
                                                          DataCell(
                                                            _buildGambarCell(r),
                                                          ),
                                                          DataCell(
                                                            Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                IconButton(
                                                                  onPressed: () =>
                                                                      _bukaRincianDialog(
                                                                        r,
                                                                      ),
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .receipt_long,
                                                                    color: Colors
                                                                        .blue,
                                                                  ),
                                                                  tooltip:
                                                                      'Rincian Objek & Pembayaran',
                                                                ),
                                                                if (r.isPaid)
                                                                  IconButton(
                                                                    onPressed: () =>
                                                                        _cetakBuktiBayar(
                                                                          r,
                                                                        ),
                                                                    icon: const Icon(
                                                                      Icons
                                                                          .picture_as_pdf,
                                                                      color: Colors
                                                                          .green,
                                                                    ),
                                                                    tooltip:
                                                                        'Cetak Bukti Bayar',
                                                                  )
                                                                else
                                                                  IconButton(
                                                                    onPressed: () =>
                                                                        _bukaStatusBayar(
                                                                          r,
                                                                        ),
                                                                    icon: const Icon(
                                                                      Icons
                                                                          .fact_check_outlined,
                                                                      color: Colors
                                                                          .teal,
                                                                    ),
                                                                    tooltip:
                                                                        'Cek Status Bayar (Update jika Lunas)',
                                                                  ),
                                                                IconButton(
                                                                  onPressed: () =>
                                                                      _hapusBaris(
                                                                        r,
                                                                      ),
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .delete_outline,
                                                                    color: Colors
                                                                        .red,
                                                                  ),
                                                                  tooltip:
                                                                      'Hapus Baris',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          DataCell(
                                                            IconButton(
                                                              onPressed: () =>
                                                                  _editCatatanDialog(
                                                                    r,
                                                                  ),
                                                              icon: Icon(
                                                                r
                                                                        .catatan
                                                                        .isNotEmpty
                                                                    ? Icons
                                                                          .edit_note
                                                                    : Icons
                                                                          .description_outlined,
                                                                color:
                                                                    r
                                                                        .catatan
                                                                        .isNotEmpty
                                                                    ? Colors
                                                                          .amber
                                                                          .shade800
                                                                    : Colors
                                                                          .grey
                                                                          .shade600,
                                                              ),
                                                              tooltip:
                                                                  r
                                                                      .catatan
                                                                      .isNotEmpty
                                                                  ? 'Catatan: ${r.catatan}'
                                                                  : 'Tambah Catatan Petugas',
                                                            ),
                                                          ),
                                                        ],
                                                      );
                                                    }(),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    BlokCatatanPaginationBar(
                                      startIndex: startIndex,
                                      endIndex: endIndex,
                                      totalRecords: totalRecords,
                                      safePage: safePage,
                                      totalPages: totalPages,
                                      rowsPerPage: _rowsPerPage,
                                      onPageChanged: (page) =>
                                          setState(() => _currentPage = page),
                                      onRowsPerPageChanged: (rows) =>
                                          setState(() {
                                            _rowsPerPage = rows;
                                            _currentPage = 0;
                                          }),
                                    ),
                                  ],
                                );
                              }(),
                      ),
                      if (!_tampilkanGrafik)
                        DhkpSummaryFooterCard(metrics: _summaryMetrics),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
