import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'batch_check_screen.dart';
import 'blok_batch_check_tracker.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'blok_report_exporter.dart';
import 'blok_sync_service.dart';
import 'check_mode.dart';
import 'dhkp_grafik_view.dart';
import 'dkhp_package_helper.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'google_drive_picker_dialog.dart';
import 'tax_record.dart';
import 'dusun_data.dart';
import 'file_importer.dart';
import 'image_crop_helper.dart';
import 'kolase_foto_screen.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart';
import 'operator_mode_store.dart';
import 'tagihan_result.dart' show formatRupiah;
import 'unity_lerp_widgets.dart';

/// Dikembalikan lewat Navigator.pop saat user menekan "Rincian Tagihan" (mode tagihan)
/// atau "Cetak Bukti Bayar" (mode status bayar) — dipakai MainShell untuk membuka form
/// dengan blok/nomor wilayah/tahun sudah terisi otomatis.
class BlokNavigationRequest {
  final String blok;
  final String wilayah;
  final String tahun;
  final CheckMode targetMode;

  const BlokNavigationRequest({
    required this.blok,
    required this.wilayah,
    required this.tahun,
    this.targetMode = CheckMode.statusBayar,
  });
}

class _OpsiEksporResult {
  final String blok;
  final BlokExportFormat format;

  const _OpsiEksporResult({
    required this.blok,
    required this.format,
  });
}

/// Nilai dropdown Blok untuk menampilkan gabungan semua blok wilayah kerja
/// sekaligus, bukan satu blok saja.
const _semuaBlokValue = '__SEMUA_BLOK__';

enum DhkpKategoriFilter {
  semua('Semua Data'),
  targetPemda('🎯 Target Pemda'),
  blacklist('⛔ Blacklist (≥ 5 Thn)'),
  sudahBayar('✓ Sudah Bayar'),
  belumBayar('⏳ Belum Bayar');

  final String label;
  const DhkpKategoriFilter(this.label);
}

/// Tahun 2022 s.d. tahun berjalan (menyesuaikan tanggal saat ini secara
/// dinamis — kalau sekarang sudah 2027, 2027 ikut tersedia).
List<int> _availableYears() {
  final currentYear = DateTime.now().year;
  return [for (var y = 2022; y <= currentYear; y++) y];
}

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
  int _summarySudahBayarCount = 0;
  int _summarySudahBayarNominal = 0;
  int _summaryBelumBayarCount = 0;
  int _summaryBelumBayarNominal = 0;
  int _summaryTargetPemdaCount = 0;
  int _summaryTargetPemdaNominal = 0;
  int _summaryTotalCount = 0;
  int _summaryTotalNominal = 0;

  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
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
      _selectedBlok = _semuaBlokValue;
      _selectedTahun = '${DateTime.now().year}';
    } else if (isOperator) {
      // Operator tidak terikat satu wilayah kerja — default melihat seluruh
      // wilayah desa (Semua Blok) agar ringkasan desa dan tren terlihat lengkap.
      _isOperator = true;
      _allBloks = allBloks;
      _bloks = allBloks;
      _whitelist = allBloks.toSet();
      _selectedWilayah = null;
      _selectedBlok = _semuaBlokValue;
      _selectedTahun = '${DateTime.now().year}';
    } else {
      _isOperator = false;
      _allBloks = allBloks;
      _bloks = allBloks;
      _whitelist = allBloks.toSet();
      _selectedWilayah = null;
      _selectedBlok = _semuaBlokValue;
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
            content: Text('Semua data perubahan DHKP sudah sinkron dengan Drive.'),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal sinkronisasi data: $e')),
        );
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
        _selectedBlok = _semuaBlokValue;
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
      _selectedBlok = _semuaBlokValue;
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

    final allScope = blok == _semuaBlokValue
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

    // Hitung ringkasan statistik dalam 1 kali loop O(N) untuk mencegah lag build()
    // Total keseluruhan hanya menghitung Sudah Bayar dan Belum Bayar desa
    // (Target Pemda dipisah tersendiri dan tidak dihitung ke target desa).
    int sBayarCount = 0;
    int sBayarNom = 0;
    int bBayarCount = 0;
    int bBayarNom = 0;
    int tPemdaCount = 0;
    int tPemdaNom = 0;

    for (final r in allScope) {
      final pbb = r.jumlahPbbValue;
      if (r.isTargetPemda) {
        tPemdaCount++;
        tPemdaNom += pbb;
      } else if (r.isPaid) {
        sBayarCount++;
        sBayarNom += pbb;
      } else {
        bBayarCount++;
        bBayarNom += pbb;
      }
    }

    final totCount = sBayarCount + bBayarCount;
    final totNom = sBayarNom + bBayarNom;

    var records = allScope;
    switch (_kategoriFilter) {
      case DhkpKategoriFilter.semua:
        break;
      case DhkpKategoriFilter.targetPemda:
        records = records.where((r) => r.isTargetPemda).toList();
        break;
      case DhkpKategoriFilter.blacklist:
        records = records.where((r) => r.isBlacklist).toList();
        break;
      case DhkpKategoriFilter.sudahBayar:
        records = records.where((r) => r.isPaid && !r.isTargetPemda).toList();
        break;
      case DhkpKategoriFilter.belumBayar:
        records = records.where((r) => !r.isPaid && !r.isTargetPemda).toList();
        break;
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      records = records.where((r) {
        return r.namaWajibPajak.toLowerCase().contains(q) ||
            r.nop.contains(q) ||
            r.alamatObjek.toLowerCase().contains(q) ||
            r.catatan.toLowerCase().contains(q);
      }).toList();
    }

    if (!mounted) return;
    setState(() {
      _photosDir = photosDir;
      _cachedPhotoFileNames = photoNames;
      _records = records;
      _allScopeRecords = allScope;

      _summarySudahBayarCount = sBayarCount;
      _summarySudahBayarNominal = sBayarNom;
      _summaryBelumBayarCount = bBayarCount;
      _summaryBelumBayarNominal = bBayarNom;
      _summaryTargetPemdaCount = tPemdaCount;
      _summaryTargetPemdaNominal = tPemdaNom;
      _summaryTotalCount = totCount;
      _summaryTotalNominal = totNom;

      final maxPage = _rowsPerPage > 0
          ? (records.isEmpty ? 0 : ((records.length - 1) ~/ _rowsPerPage))
          : 0;
      if (_currentPage > maxPage) {
        _currentPage = 0;
      }
      _busy = false;
    });
  }

  /// Data lingkup saat ini (mengikuti pilihan Blok & Tahun di layar atau blokOverride),
  /// selalu terurut blok+wilayah menaik — dipakai untuk unduh/bagikan/cetak
  /// supaya berkasnya tetap baku urutannya apa pun filter urutan tampilan
  /// yang sedang dipakai di layar.
  Future<List<BlokRecord>> _scopedRecordsForExport([String? blokOverride]) async {
    final blok = blokOverride ?? _selectedBlok;
    var records = (blok == null || blok == _semuaBlokValue)
        ? (_whitelist.isNotEmpty
            ? await BlokDataStore.instance.byWhitelist(_whitelist, tahun: _selectedTahun)
            : await BlokDataStore.instance.forReport(tahun: _selectedTahun))
        : await BlokDataStore.instance.byBlok(blok, tahun: _selectedTahun);

    switch (_kategoriFilter) {
      case DhkpKategoriFilter.semua:
        break;
      case DhkpKategoriFilter.targetPemda:
        records = records.where((r) => r.isTargetPemda).toList();
        break;
      case DhkpKategoriFilter.blacklist:
        records = records.where((r) => r.isBlacklist).toList();
        break;
      case DhkpKategoriFilter.sudahBayar:
        records = records.where((r) => r.isPaid && !r.isTargetPemda).toList();
        break;
      case DhkpKategoriFilter.belumBayar:
        records = records.where((r) => !r.isPaid && !r.isTargetPemda).toList();
        break;
    }
    return records;
  }

  void _pilihBlok(String? blok) {
    if (blok == null) return;
    setState(() {
      _selectedBlok = blok;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: blok == _semuaBlokValue
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
    final controller = TextEditingController(text: record.catatan);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Colors.blue),
            SizedBox(width: 8),
            Text('Catatan Petugas', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.namaWajibPajak,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              'NOP: ${record.formattedNop} (Blok ${record.blok} No ${record.wilayah})',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: 'Catatan Petugas (Anomali / Info Khusus)',
                hintText: 'Misal: Bangunan sudah dibongkar, NOP ganda, pemilik pindah ke luar kota, tanah sengketa...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save),
            label: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (mounted) {
        setState(() {
          _busy = true;
          _busyMessage = 'Menyimpan catatan petugas...';
          _busyIcon = Icons.save_outlined;
        });
      }
      final newRecord = record.copyWith(
        catatan: controller.text.trim(),
      );
      await BlokDataStore.instance.upsert(newRecord);
      unawaited(
        BlokSyncService.instance.recordChange(
          record: newRecord,
          catatan: controller.text.trim(),
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Theme.of(context).colorScheme.primary,
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.onPrimary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'INFORMASI DATA PEMBAYARAN',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onPrimary),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // Konten 2 Kolom (Kiri & Kanan) sesuai Lembar Printout Bapenda
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Kolom Kiri
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildRincianItem(
                                      'Nomor Objek Pajak (NOP)',
                                      record.formattedNop,
                                      isBold: true,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Luas Bumi',
                                      record.luasBumi.isNotEmpty ? record.luasBumi : '-',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Luas Bangunan',
                                      record.luasBangunan.isNotEmpty ? record.luasBangunan : '-',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Kecamatan Objek Pajak',
                                      record.kecamatan,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Alamat Objek Pajak',
                                      record.alamatObjek.isNotEmpty ? record.alamatObjek : '-',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Nama Wajib Pajak',
                                      record.namaWajibPajak,
                                      isBold: true,
                                      textColor: isDark ? Colors.lightBlueAccent : Colors.blue.shade900,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Alamat Wajib Pajak',
                                      record.alamatWp.isNotEmpty ? record.alamatWp : '-',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Kolom Kanan
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildRincianItem(
                                      'Tahun Ketetapan',
                                      record.tahunBayar,
                                      isBold: true,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'NJOP Bumi',
                                      record.njopBumi.isNotEmpty ? record.njopBumi : '-',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'NJOP Bangunan',
                                      record.njopBangunan.isNotEmpty ? record.njopBangunan : '-',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Kelurahan Objek Pajak',
                                      record.kelurahan,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'RT Objek Pajak',
                                      record.rtObjek.isNotEmpty ? record.rtObjek : '-',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Pokok / Ketetapan PBB',
                                      record.jumlahPbb.isNotEmpty ? record.jumlahPbb : '-',
                                      isBold: true,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildRincianItem(
                                      'Status Bayar',
                                      record.statusBayar,
                                      textColor: record.isPaid ? Colors.green : Colors.orange.shade800,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          // Target Pemda & Catatan
                          if (record.isTargetPemda)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.red),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.flag, size: 16, color: Colors.red),
                                  SizedBox(width: 6),
                                  Text(
                                    'TARGET KHUSUS PEMDA (Prioritas Penagihan)',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (record.catatan.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.shade700),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Catatan: ${record.catatan}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!record.isPaid)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.fact_check_outlined, size: 16, color: Colors.teal),
                            label: const Text('Cek Status Bayar'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _bukaStatusBayar(record);
                            },
                          ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text('Cek Tagihan'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _bukaTagihan(record);
                          },
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit / Sesuaikan Pemilik'),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _editRincianDialog(record);
                          },
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
    );
  }

  Widget _buildRincianItem(
    String label,
    String value, {
    bool isBold = false,
    Color? textColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }

  /// Dialog Edit Rincian — petugas hanya menyesuaikan Nama Wajib Pajak/Pemilik, Alamat OP, dan Alamat WP
  Future<void> _editRincianDialog(BlokRecord record) async {
    final namaController = TextEditingController(text: record.namaWajibPajak);
    final alamatObjekController = TextEditingController(text: record.alamatObjek);
    final alamatWpController = TextEditingController(text: record.alamatWp);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Edit Nama & Alamat',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOP: ${record.formattedNop}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: namaController,
                decoration: const InputDecoration(
                  labelText: 'Nama Wajib Pajak / Pemilik Sekarang',
                  helperText: 'Sesuaikan nama dengan pemilik fisik saat ini',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: alamatObjekController,
                decoration: const InputDecoration(
                  labelText: 'Alamat Objek Pajak (OP)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: alamatWpController,
                decoration: const InputDecoration(
                  labelText: 'Alamat Wajib Pajak (WP)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.home_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Simpan Perubahan'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (mounted) {
        setState(() {
          _busy = true;
          _busyMessage = 'Menyimpan perubahan nama & alamat...';
          _busyIcon = Icons.save_outlined;
        });
      }
      final updatedRecord = record.copyWith(
        namaWajibPajak: namaController.text.trim().isEmpty
            ? record.namaWajibPajak
            : namaController.text.trim(),
        alamatObjek: alamatObjekController.text.trim(),
        alamatWp: alamatWpController.text.trim(),
      );
      await BlokDataStore.instance.upsert(updatedRecord);
      unawaited(
        BlokSyncService.instance.recordChange(
          record: updatedRecord,
        ),
      );
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
    // 1. Tentukan daftar blok yang tersedia untuk dicek:
    // Jika terkunci ke dusun / memfilter dusun tertentu -> hanya blok dusun tersebut.
    // Jika tingkat desa penuh -> semua blok (1-41).
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

    availableBloks.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    if (availableBloks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data blok yang tersedia untuk wilayah ini.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Kelompokkan data per blok dari database
    final rawRecords = await BlokDataStore.instance.loadAll();
    final allRecords = _selectedTahun != null
        ? rawRecords
            .where((r) => r.tahunBayar.isEmpty || r.tahunBayar == _selectedTahun)
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

    final selectedRecords = await showDialog<List<BlokRecord>>(
      context: context,
      builder: (ctx) {
        String? currentBlok;
        final scheme = Theme.of(context).colorScheme;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final blokRecords = currentBlok != null ? (recordsByBlok[currentBlok] ?? []) : <BlokRecord>[];
            final totalCount = blokRecords.length;
            final paidCount = blokRecords.where((r) => r.isPaid).length;
            final unpaidList = blokRecords.where((r) => !r.isPaid).toList();
            final checkedTodayList = unpaidList
                .where((r) => BlokBatchCheckTracker.instance.isCheckedToday(r.nop))
                .toList();
            final remainingToCheck = unpaidList
                .where((r) => !BlokBatchCheckTracker.instance.isCheckedToday(r.nop))
                .toList();

            final checkedTodayCount = checkedTodayList.length;
            final remainingCount = remainingToCheck.length;
            final isAllPaid = totalCount > 0 && unpaidList.isEmpty;
            final isFullyCheckedToday = unpaidList.isNotEmpty && remainingCount == 0;
            final isPartialChecked = checkedTodayCount > 0 && remainingCount > 0;

            final currentBlokInt = currentBlok != null ? (int.tryParse(currentBlok!) ?? currentBlok) : null;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.fact_check_outlined, color: Colors.teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pilih Blok untuk Cek Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chip Wilayah
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                DusunData.instance.isDusunLocked
                                    ? 'Wilayah Terkunci: Dusun ${DusunData.instance.lockedDusunNumber} (${availableBloks.length} Blok)'
                                    : (_selectedWilayah != null
                                        ? 'Wilayah: Dusun $_selectedWilayah (${availableBloks.length} Blok)'
                                        : 'Wilayah: 1 Desa / Semua Wilayah (${availableBloks.length} Blok 1-41)'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Pertanyaan Pilih Blok
                      Text(
                        'Mau cek blok yang mana?',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: currentBlok,
                        isExpanded: true,
                        hint: const Text(
                          '-- Pilih Nomor Blok --',
                          style: TextStyle(fontSize: 14),
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.grid_view_rounded, size: 20),
                        ),
                        items: availableBloks.map((b) {
                          final bRecs = recordsByBlok[b] ?? [];
                          final bUnpaid = bRecs.where((r) => !r.isPaid).length;
                          final bDoneToday = bUnpaid > 0 &&
                              bRecs
                                      .where((r) =>
                                          !r.isPaid &&
                                          BlokBatchCheckTracker.instance
                                              .isCheckedToday(r.nop))
                                      .length ==
                                  bUnpaid;

                          final bInt = int.tryParse(b) ?? b;
                          return DropdownMenuItem<String>(
                            value: b,
                            child: Row(
                              children: [
                                Text(
                                  'Blok $bInt',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    bDoneToday
                                        ? '• Sudah dicek'
                                        : (bUnpaid == 0
                                            ? '• Semua lunas'
                                            : '• $bUnpaid belum bayar'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: bDoneToday
                                          ? Colors.grey
                                          : (bUnpaid == 0
                                              ? Colors.green
                                              : Colors.orange),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              currentBlok = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // Jika belum memilih blok, perjelas bahwa blok belum diisi
                      if (currentBlok == null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.5),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.amber.shade800, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Blok Belum Dipilih',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Silakan pilih salah satu nomor blok pada menu di atas terlebih dahulu untuk melihat data dan memeriksa status bayar.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Card Rincian Blok Terpilih
                        Card(
                          elevation: 0,
                          color: scheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: scheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Data Objek Pajak Blok $currentBlokInt',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatColumn('Total NOP', '$totalCount', scheme.onSurface),
                                    _buildStatColumn('Sudah Bayar', '$paidCount', Colors.green),
                                    _buildStatColumn('Belum Bayar', '${unpaidList.length}', Colors.orange),
                                  ],
                                ),
                                const Divider(height: 18),

                                // Status Pengecekan Hari Ini
                                if (isAllPaid) ...[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.green.withValues(alpha: 0.3)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            color: Colors.green, size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Semua Lunas: Seluruh NOP pada blok ini sudah berstatus Sudah Bayar. Tidak ada tunggakan yang perlu dicek.',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.green),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (isFullyCheckedToday) ...[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.amber.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline,
                                            color: Colors.amber.shade800, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Blok ini sudah dicek, coba lagi besok',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.amber.shade900),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (isPartialChecked) ...[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.blue.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.pending_actions,
                                            color: Colors.blue, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$checkedTodayCount NOP sudah diperiksa hari ini. '
                                            'Tersisa $remainingCount NOP Belum Bayar yang belum selesai dicek.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue.shade900),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest
                                          .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline,
                                            size: 18, color: scheme.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Ditemukan $remainingCount NOP Belum Bayar yang siap diperiksa. '
                                            'NOP yang sudah bayar tidak akan dicek lagi.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    currentBlok == null
                        ? 'Pilih Blok Terlebih Dahulu'
                        : (isFullyCheckedToday
                            ? 'Sudah Dicek (Coba Lagi Besok)'
                            : (isAllPaid
                                ? 'Semua Lunas'
                                : (isPartialChecked
                                    ? 'Lanjutkan Cek Sisa ($remainingCount NOP)'
                                    : 'Mulai Cek ($remainingCount NOP)'))),
                  ),
                  onPressed: (currentBlok == null ||
                          isFullyCheckedToday ||
                          isAllPaid ||
                          remainingCount == 0)
                      ? null
                      : () => Navigator.pop(ctx, remainingToCheck),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedRecords == null || selectedRecords.isEmpty || !mounted) return;

    final taxRecords = selectedRecords
        .map((r) => TaxRecord(nop: r.nop, namaWajibPajak: r.namaWajibPajak))
        .toList();
    final tahun = _selectedTahun ??
        (selectedRecords.first.tahunBayar.isNotEmpty
            ? selectedRecords.first.tahunBayar
            : '2026');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchCheckScreen(
          records: taxRecords,
          tahun: tahun,
        ),
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
        content: Text('Pengecekan selesai. Data DHKP telah otomatis diperbarui.'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
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
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.download_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text('Buat Laporan (.dat)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Laporan ini akan mengemas seluruh data DHKP (${targetRecords.length} objek PBB) tanpa dibatasi dusun atau blok.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.teal.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Berkas .dat memuat rincian objek, status pembayaran, catatan, dan foto dokumentasi objek.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.teal.shade900,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Unduh Berkas Laporan'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (konfirmasi != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'Menyusun & mengemas berkas laporan .dat (${targetRecords.length} data)...';
      _busyIcon = Icons.download_rounded;
    });

    try {
      final now = DateTime.now();
      String pad(int n) => n.toString().padLeft(2, '0');
      final dateStr = '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
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
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Upload Data DHKP / Laporan (.dat)'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: const ListTile(
              leading: Icon(Icons.folder_open_outlined, color: Colors.teal),
              title: Text('Pilih Berkas dari Perangkat'),
              subtitle: Text(
                  'Buka berkas DHKP, Excel, atau Laporan (.dat) dari penyimpanan perangkat'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'google_drive'),
            child: const ListTile(
              leading: FaIcon(FontAwesomeIcons.googleDrive, color: Colors.blue),
              title: Text('Ambil dari Google Drive'),
              subtitle: Text(
                  'Pilih berkas dari akun Google Drive atau buka melalui tautan'),
            ),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'file') {
      try {
        final files = await FilePicker.pickFiles(
          type: FileType.any,
        );
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
        await _importDkhpFromPath(files.first.path!, sourceLabel: 'berkas lokal');
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
            content: Text(isMismatch ? 'Data tidak sesuai' : 'Gagal membaca berkas: $e'),
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
            content: Text(isMismatch ? 'Data tidak sesuai' : 'Gagal membaca berkas Google Drive: $e'),
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

      final importedBlokRecords =
          await FileImporter.importBlokRecordsFrom(path);
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
          tanggalBayar: t.isPaid ? 'Sudah Bayar' : '',
          jumlahPbb: '',
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
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final isMismatch = e.toString().contains('Data tidak sesuai');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isMismatch ? 'Data tidak sesuai' : 'Gagal memuat berkas: $e'),
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
    File? photoFile = await DhkpPackageHelper.findPhotoForNop(
      record.nop,
      customFileName: record.namaFoto,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasImage = photoFile != null && photoFile!.existsSync();

          return Dialog(
            backgroundColor: Theme.of(context).cardColor,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.teal.shade700,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.namaWajibPajak,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'NOP: ${record.formattedNop}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                  ),

                  // Area Foto / Placeholder ala Profil WhatsApp
                  Flexible(
                    child: Container(
                      color: Colors.black87,
                      constraints: const BoxConstraints(minHeight: 250, maxHeight: 400),
                      width: double.infinity,
                      child: hasImage
                          ? InteractiveViewer(
                              panEnabled: true,
                              scaleEnabled: true,
                              minScale: 0.8,
                              maxScale: 4.0,
                              child: Image.file(
                                photoFile!,
                                fit: BoxFit.contain,
                              ),
                            )
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.photo_camera_outlined,
                                      size: 64,
                                      color: Colors.white.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Belum Ada Gambar Dokumentasi',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Klik "Upload Foto" di bawah untuk mengambil atau memilih foto.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),

                  // Toolbar Tombol Aksi
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hasImage) ...[
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Hapus'),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Hapus Foto?'),
                                  content: const Text(
                                    'Foto untuk objek ini akan dihapus dari penyimpanan.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Batal'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Hapus'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _hapusFoto(record);
                                final refreshed = await DhkpPackageHelper.findPhotoForNop(
                                  record.nop,
                                  customFileName: '',
                                );
                                setDialogState(() {
                                  photoFile = refreshed;
                                });
                              }
                            },
                          ),
                          const Spacer(),
                        ],
                        FilledButton.icon(
                          icon: const Icon(Icons.add_a_photo, size: 18),
                          label: Text(hasImage ? 'Ganti Foto' : 'Upload Foto'),
                          onPressed: () async {
                            final newFile = await _pilihDanSimpanFoto(record);
                            if (newFile != null) {
                              setDialogState(() {
                                photoFile = newFile;
                              });
                            }
                          },
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
          final source = method == 'camera' ? ImageSource.camera : ImageSource.gallery;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih gambar: $e')),
        );
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
        BlokSyncService.instance.recordChange(
          record: updated,
          namaFoto: '',
        ),
      );
      await _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto telah dihapus.')),
        );
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

  Future<_OpsiEksporResult?> _pilihOpsiEkspor({
    required String title,
    required String actionButtonLabel,
    required IconData actionIcon,
    bool fixedPdf = false,
  }) async {
    String currentBlok = (_selectedBlok != null && _selectedBlok != _semuaBlokValue)
        ? _selectedBlok!
        : _semuaBlokValue;
    BlokExportFormat currentFormat = BlokExportFormat.pdf;

    return showDialog<_OpsiEksporResult>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isPerBlok = currentBlok != _semuaBlokValue;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(actionIcon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilih Lingkup Blok:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: currentBlok,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        prefixIcon: const Icon(Icons.grid_view_rounded, size: 20),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: _semuaBlokValue,
                          child: Text(
                            'Semua Blok (${_bloks.length} Blok)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        for (final b in _bloks)
                          DropdownMenuItem<String>(
                            value: b,
                            child: Text(
                              'Blok $b (Per-Blok)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => currentBlok = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    if (!fixedPdf) ...[
                      Text(
                        'Pilih Format Berkas:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<BlokExportFormat>(
                        initialValue: currentFormat,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          prefixIcon: const Icon(Icons.description_outlined, size: 20),
                        ),
                        items: [
                          for (final fmt in BlokExportFormat.values)
                            DropdownMenuItem<BlokExportFormat>(
                              value: fmt,
                              child: Text(fmt.label),
                            ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => currentFormat = val);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isPerBlok
                            ? Colors.teal.withValues(alpha: 0.1)
                            : Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPerBlok
                              ? Colors.teal.withValues(alpha: 0.3)
                              : Colors.blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isPerBlok
                                ? Icons.bolt_rounded
                                : Icons.info_outline_rounded,
                            size: 18,
                            color: isPerBlok ? Colors.teal : Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPerBlok
                                  ? 'Pencetakan atau ekspor per-blok memproses data blok ini saja, lebih cepat dan hemat kertas.'
                                  : 'Mengekspor semua blok akan menyusun seluruh data secara bertahap dan teratur agar perangkat tidak berat.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionButtonLabel),
                  onPressed: () => Navigator.pop(
                    ctx,
                    _OpsiEksporResult(
                      blok: currentBlok,
                      format: currentFormat,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
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
      final blokTitle = opsi.blok == _semuaBlokValue
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
      final prefix = opsi.blok == _semuaBlokValue
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
      _busyMessage = 'Menyiapkan berkas ${opsi.format.label} untuk dibagikan...';
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
      final blokTitle = opsi.blok == _semuaBlokValue
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
      final prefix = opsi.blok == _semuaBlokValue
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
      final blokTitle = opsi.blok == _semuaBlokValue
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
      final fileName = opsi.blok == _semuaBlokValue
          ? 'Laporan Data Blok ($tahunLabel).pdf'
          : 'Laporan Blok ${opsi.blok} ($tahunLabel).pdf';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: bytes,
            fileName: fileName,
          ),
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
        builder: (_) => KolaseFotoScreen(
          initialBlok: _selectedBlok,
          bloks: _bloks,
        ),
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
              });
            },
            icon: Icon(
              _tampilkanGrafik ? Icons.receipt_long_rounded : Icons.bar_chart_rounded,
            ),
            tooltip: _tampilkanGrafik ? 'Beralih ke Buku Catatan (Tabel)' : 'Beralih ke Visual Grafik',
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
              ? _BlokCatatanLoadingView(
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
                              // DropdownButtonFormField.initialValue cuma dibaca sekali saat
                              // widget pertama kali dipasang — kalau _selectedBlok direset dari
                              // kode (bukan dari onChanged dropdown ini sendiri, mis. saat ganti
                              // Wilayah di Mode Operator), key ini beda supaya widget dibongkar &
                              // dipasang ulang, dan initialValue yang baru benar-benar kepakai.
                              key: ValueKey('blok-dropdown-$_selectedWilayah'),
                              initialValue: _selectedBlok,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Blok',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: _semuaBlokValue,
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
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Semua'),
                                ),
                                for (final y in _availableYears())
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
                      // Baris Terpadu: Pencarian Cepat + Tombol Ikon Filter Kategori + Tombol Ikon Urutkan
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Cari Nama WP, NOP, atau Alamat Objek...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          // Tombol Filter Kategori (Ikon + Indikator Aktif)
                          PopupMenuButton<DhkpKategoriFilter>(
                            tooltip: 'Filter Kategori: ${_kategoriFilter.label}',
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
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_unchecked_rounded,
                                        size: 18,
                                        color: _kategoriFilter == k
                                            ? Theme.of(context).colorScheme.primary
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
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: _kategoriFilter != DhkpKategoriFilter.semua
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : null,
                                border: Border.all(
                                  color: _kategoriFilter != DhkpKategoriFilter.semua
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outline,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _kategoriFilter != DhkpKategoriFilter.semua
                                        ? Icons.filter_alt_rounded
                                        : Icons.filter_list_rounded,
                                    size: 20,
                                    color: _kategoriFilter != DhkpKategoriFilter.semua
                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                        : null,
                                  ),
                                  if (_kategoriFilter != DhkpKategoriFilter.semua) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      _kategoriFilter.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Tombol Urutkan Data (Ikon Sort)
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
                                            ? Theme.of(context).colorScheme.primary
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
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: _sortBy != BlokSortBy.blokWilayah
                                    ? Theme.of(context).colorScheme.secondaryContainer
                                    : null,
                                border: Border.all(
                                  color: _sortBy != BlokSortBy.blokWilayah
                                      ? Theme.of(context).colorScheme.secondary
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
                                        ? Theme.of(context).colorScheme.onSecondaryContainer
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
                              records: _allScopeRecords.isNotEmpty ? _allScopeRecords : _records,
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
                                  ? (totalRecords == 0 ? 1 : ((totalRecords - 1) ~/ _rowsPerPage) + 1)
                                  : 1;
                              final safePage = _currentPage.clamp(0, totalPages > 0 ? totalPages - 1 : 0);
                              final startIndex = _rowsPerPage > 0 ? safePage * _rowsPerPage : 0;
                              final endIndex = _rowsPerPage > 0
                                  ? ((safePage + 1) * _rowsPerPage > totalRecords
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
                                      notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
                                      child: Scrollbar(
                                        controller: _horizontalScrollController,
                                        thumbVisibility: true,
                                        notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                                        child: SingleChildScrollView(
                                          controller: _horizontalScrollController,
                                          scrollDirection: Axis.horizontal,
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          child: SingleChildScrollView(
                                            controller: _verticalScrollController,
                                            scrollDirection: Axis.vertical,
                                            physics: const AlwaysScrollableScrollPhysics(),
                                            child: DataTable(
                                              columnSpacing: 18,
                                              horizontalMargin: 12,
                                              columns: const [
                                                DataColumn(label: Text('No')),
                                                DataColumn(label: Text('Nama WP')),
                                                DataColumn(label: Text('NOP / Blok')),
                                                DataColumn(label: Text('Tahun Pajak')),
                                                DataColumn(label: Text('Pokok / Ketetapan')),
                                                DataColumn(label: Text('Status Bayar')),
                                                DataColumn(label: Text('Gambar')),
                                                DataColumn(label: Text('Aksi')),
                                                DataColumn(label: Text('Catatan')),
                                              ],
                                              rows: [
                                                for (var i = 0; i < pagedRecords.length; i++) ...[
                                                  () {
                                                    final r = pagedRecords[i];
                                                    final isDark = Theme.of(context).brightness == Brightness.dark;

                                                    return DataRow(
                                                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                                                        if (r.isTargetPemda) {
                                                          return isDark
                                                              ? Colors.red.shade900.withValues(alpha: 0.38)
                                                              : Colors.red.shade100.withValues(alpha: 0.65);
                                                        }
                                                        return null;
                                                      }),
                                                      cells: [
                                                        DataCell(
                                                          Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Text('${startIndex + i + 1}'),
                                                              if (r.isTargetPemda) ...[
                                                                const SizedBox(width: 4),
                                                                Container(
                                                                  padding: const EdgeInsets.symmetric(
                                                                    horizontal: 4,
                                                                    vertical: 1,
                                                                  ),
                                                                  decoration: BoxDecoration(
                                                                    color: Colors.red.shade700,
                                                                    borderRadius: BorderRadius.circular(4),
                                                                  ),
                                                                  child: const Text(
                                                                    'PEMDA',
                                                                    style: TextStyle(
                                                                      color: Colors.white,
                                                                      fontSize: 9,
                                                                      fontWeight: FontWeight.bold,
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
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                r.nop,
                                                                style: const TextStyle(
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                              ),
                                                              Text(
                                                                'Blok ${r.blok} No ${r.wilayah}',
                                                                style: const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors.grey,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        DataCell(Text(r.tahunBayar)),
                                                        DataCell(
                                                          Text(
                                                            r.jumlahPbb.isEmpty ? '-' : r.jumlahPbb,
                                                          ),
                                                        ),
                                                        DataCell(
                                                          () {
                                                            Color bgColor;
                                                            Color textColor;
                                                            Color borderColor;
                                                            String displayStatus = r.isPaid ? 'Sudah Bayar' : r.statusBayar;

                                                            if (r.isBlacklist) {
                                                              if (isDark) {
                                                                bgColor = Colors.white;
                                                                textColor = Colors.black87;
                                                                borderColor = Colors.white;
                                                              } else {
                                                                bgColor = Colors.black87;
                                                                textColor = Colors.white;
                                                                borderColor = Colors.black;
                                                              }
                                                              if (!displayStatus.toLowerCase().contains('black') &&
                                                                  !displayStatus.toLowerCase().contains('daftar')) {
                                                                displayStatus = 'Blacklist (≥ 5 Thn)';
                                                              }
                                                            } else if (r.isPaid) {
                                                              bgColor = Colors.green.withValues(alpha: 0.15);
                                                              textColor = isDark ? Colors.green.shade300 : Colors.green.shade800;
                                                              borderColor = Colors.green;
                                                            } else {
                                                              bgColor = Colors.orange.withValues(alpha: 0.15);
                                                              textColor = isDark ? Colors.orange.shade300 : Colors.orange.shade900;
                                                              borderColor = Colors.orange;
                                                            }

                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: bgColor,
                                                                borderRadius: BorderRadius.circular(6),
                                                                border: Border.all(color: borderColor),
                                                              ),
                                                              child: Text(
                                                                displayStatus,
                                                                style: TextStyle(
                                                                  color: textColor,
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            );
                                                          }(),
                                                        ),
                                                        DataCell(
                                                          _buildGambarCell(r),
                                                        ),
                                                        DataCell(
                                                          Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              IconButton(
                                                                onPressed: () => _bukaRincianDialog(r),
                                                                icon: const Icon(
                                                                  Icons.receipt_long,
                                                                  color: Colors.blue,
                                                                ),
                                                                tooltip: 'Rincian Objek & Pembayaran',
                                                              ),
                                                              if (r.isPaid)
                                                                IconButton(
                                                                  onPressed: () => _cetakBuktiBayar(r),
                                                                  icon: const Icon(
                                                                    Icons.picture_as_pdf,
                                                                    color: Colors.green,
                                                                  ),
                                                                  tooltip: 'Cetak Bukti Bayar',
                                                                )
                                                              else
                                                                IconButton(
                                                                  onPressed: () => _bukaStatusBayar(r),
                                                                  icon: const Icon(
                                                                    Icons.fact_check_outlined,
                                                                    color: Colors.teal,
                                                                  ),
                                                                  tooltip: 'Cek Status Bayar (Update jika Lunas)',
                                                                ),
                                                              IconButton(
                                                                onPressed: () => _hapusBaris(r),
                                                                icon: const Icon(
                                                                  Icons.delete_outline,
                                                                  color: Colors.red,
                                                                ),
                                                                tooltip: 'Hapus Baris',
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        DataCell(
                                                          IconButton(
                                                            onPressed: () => _editCatatanDialog(r),
                                                            icon: Icon(
                                                              r.catatan.isNotEmpty ? Icons.edit_note : Icons.description_outlined,
                                                              color: r.catatan.isNotEmpty
                                                                  ? Colors.amber.shade800
                                                                  : Colors.grey.shade600,
                                                            ),
                                                            tooltip: r.catatan.isNotEmpty
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
                                  // Bilah Kontrol Paginasi Modern & Responsif
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      border: Border(
                                        top: BorderSide(
                                          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final isCompact = constraints.maxWidth < 620;

                                        final infoWidget = Text(
                                          'Menampilkan ${startIndex + 1}-$endIndex dari $totalRecords data',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        );

                                        final controlsWidget = Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              icon: const Icon(Icons.first_page, size: 20),
                                              tooltip: 'Halaman Pertama',
                                              onPressed: safePage > 0
                                                  ? () => setState(() => _currentPage = 0)
                                                  : null,
                                            ),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              icon: const Icon(Icons.chevron_left, size: 20),
                                              tooltip: 'Halaman Sebelumnya',
                                              onPressed: safePage > 0
                                                  ? () => setState(() => _currentPage = safePage - 1)
                                                  : null,
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              child: Text(
                                                'Hal ${safePage + 1} / $totalPages',
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              icon: const Icon(Icons.chevron_right, size: 20),
                                              tooltip: 'Halaman Berikutnya',
                                              onPressed: safePage < totalPages - 1
                                                  ? () => setState(() => _currentPage = safePage + 1)
                                                  : null,
                                            ),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              icon: const Icon(Icons.last_page, size: 20),
                                              tooltip: 'Halaman Terakhir',
                                              onPressed: safePage < totalPages - 1
                                                  ? () => setState(() => _currentPage = totalPages - 1)
                                                  : null,
                                            ),
                                            const SizedBox(width: 6),
                                            DropdownButtonHideUnderline(
                                              child: DropdownButton<int>(
                                                value: _rowsPerPage,
                                                isDense: true,
                                                items: const [
                                                  DropdownMenuItem(value: 25, child: Text('25 / hal', style: TextStyle(fontSize: 12))),
                                                  DropdownMenuItem(value: 50, child: Text('50 / hal', style: TextStyle(fontSize: 12))),
                                                  DropdownMenuItem(value: 100, child: Text('100 / hal', style: TextStyle(fontSize: 12))),
                                                  DropdownMenuItem(value: 200, child: Text('200 / hal', style: TextStyle(fontSize: 12))),
                                                  DropdownMenuItem(value: -1, child: Text('Semua', style: TextStyle(fontSize: 12))),
                                                ],
                                                onChanged: (val) {
                                                  if (val != null) {
                                                    setState(() {
                                                      _rowsPerPage = val;
                                                      _currentPage = 0;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        );

                                        if (isCompact) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              infoWidget,
                                              const SizedBox(height: 4),
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: controlsWidget,
                                              ),
                                            ],
                                          );
                                        }

                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            infoWidget,
                                            controlsWidget,
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }(),
                    ),
                    if (!_tampilkanGrafik)
                    () {
                      final sudahBayarCount = _summarySudahBayarCount;
                      final sudahBayarNominal = _summarySudahBayarNominal;
                      final belumBayarCount = _summaryBelumBayarCount;
                      final belumBayarNominal = _summaryBelumBayarNominal;
                      final targetPemdaCount = _summaryTargetPemdaCount;
                      final targetPemdaNominal = _summaryTargetPemdaNominal;
                      final totalCount = _summaryTotalCount;
                      final totalNominal = _summaryTotalNominal;

                      String formatPct(double val) {
                        if (val.isNaN || val.isInfinite || val <= 0) return '0%';
                        if (val >= 100 || (val - val.roundToDouble()).abs() < 0.05) {
                          return '${val.round()}%';
                        }
                        return '${val.toStringAsFixed(1).replaceAll('.', ',')}%';
                      }

                      // Persentase hanya untuk Sudah Bayar dan Belum Bayar yang terbagi dari Total (100%),
                      // Target Pemda dikecualikan dari persentase total.
                      final pctSudah = totalNominal > 0
                          ? formatPct((sudahBayarNominal / totalNominal) * 100)
                          : '0%';
                      final pctBelum = totalNominal > 0
                          ? formatPct((belumBayarNominal / totalNominal) * 100)
                          : '0%';
                      const pctTotal = '100%';

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(top: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final dividerColor = Colors.grey.withValues(alpha: 0.3);

                              // Tata letak 2x2 grid pada layar HP yang sempit (< 480 dp)
                              if (constraints.maxWidth < 480) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildSummaryMetric(
                                            label: 'Sudah Bayar',
                                            count: sudahBayarCount,
                                            nominal: sudahBayarNominal,
                                            percentage: pctSudah,
                                            color: Colors.green,
                                            icon: Icons.check_circle_outline,
                                          ),
                                        ),
                                        Container(width: 1, height: 36, color: dividerColor),
                                        Expanded(
                                          child: _buildSummaryMetric(
                                            label: 'Belum Bayar',
                                            count: belumBayarCount,
                                            nominal: belumBayarNominal,
                                            percentage: pctBelum,
                                            color: Colors.orange.shade800,
                                            icon: Icons.pending_actions_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Divider(height: 12, color: dividerColor),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildSummaryMetric(
                                            label: 'Target Pemda',
                                            count: targetPemdaCount,
                                            nominal: targetPemdaNominal,
                                            color: Colors.red.shade700,
                                            icon: Icons.track_changes,
                                          ),
                                        ),
                                        Container(width: 1, height: 36, color: dividerColor),
                                        Expanded(
                                          child: _buildSummaryMetric(
                                            label: 'Total Keseluruhan',
                                            count: totalCount,
                                            nominal: totalNominal,
                                            percentage: pctTotal,
                                            color: Colors.blue.shade800,
                                            icon: Icons.account_balance_wallet_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              } else {
                                // Tata letak 4 kolom horizontal pada layar tablet/desktop yang lebar
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _buildSummaryMetric(
                                        label: 'Sudah Bayar',
                                        count: sudahBayarCount,
                                        nominal: sudahBayarNominal,
                                        percentage: pctSudah,
                                        color: Colors.green,
                                        icon: Icons.check_circle_outline,
                                      ),
                                    ),
                                    Container(width: 1, height: 38, color: dividerColor),
                                    Expanded(
                                      child: _buildSummaryMetric(
                                        label: 'Belum Bayar',
                                        count: belumBayarCount,
                                        nominal: belumBayarNominal,
                                        percentage: pctBelum,
                                        color: Colors.orange.shade800,
                                        icon: Icons.pending_actions_outlined,
                                      ),
                                    ),
                                    Container(width: 1, height: 38, color: dividerColor),
                                    Expanded(
                                      child: _buildSummaryMetric(
                                        label: 'Target Pemda',
                                        count: targetPemdaCount,
                                        nominal: targetPemdaNominal,
                                        color: Colors.red.shade700,
                                        icon: Icons.track_changes,
                                      ),
                                    ),
                                    Container(width: 1, height: 38, color: dividerColor),
                                    Expanded(
                                      child: _buildSummaryMetric(
                                        label: 'Total Keseluruhan',
                                        count: totalCount,
                                        nominal: totalNominal,
                                        percentage: pctTotal,
                                        color: Colors.blue.shade800,
                                        icon: Icons.account_balance_wallet_outlined,
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                        ),
                      );
                    }(),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required int count,
    required int nominal,
    required Color color,
    required IconData icon,
    String? percentage,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (percentage != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    percentage,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          LerpAnimatedCounter(
            value: nominal,
            formatter: (v) => formatRupiah(v.round()),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          LerpAnimatedCounter(
            value: count,
            formatter: (v) => '${v.round()} WP',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlokCatatanLoadingView extends StatelessWidget {
  final String title;

  const _BlokCatatanLoadingView({
    super.key,
    this.title = 'Memuat Data DHKP & Status Bayar',
  });

  @override
  Widget build(BuildContext context) {
    return SmoothLoadingCard(
      icon: Icons.receipt_long_rounded,
      title: title,
      subtitle:
          'Menyiapkan seluruh catatan blok, bukti STTS, dan rekapitulasi data...',
      badgeText: 'Memastikan semua data termuat',
    );
  }
}

