import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'blok_data_store.dart';
import 'blok_record.dart';
import 'blok_report_exporter.dart';
import 'check_mode.dart';
import 'dkhp_package_helper.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'dusun_data.dart';
import 'file_importer.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart';
import 'operator_mode_store.dart';
import 'tagihan_result.dart' show formatRupiah;
import 'unity_lerp_widgets.dart';
import 'wilayah_kerja_store.dart';

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

    if (isOperator) {
      // Operator tidak terikat satu wilayah kerja — bisa pilih dusun mana
      // saja untuk dilihat, default ke dusun pertama yang datanya sudah ada.
      final defaultDusun = dusunList.firstWhere(
        (d) => d.bloks.isNotEmpty,
        orElse: () => dusunList.first,
      );
      final whitelist = defaultDusun.bloks.toSet();
      _isOperator = true;
      _allBloks = allBloks;
      _bloks = allBloks.where(whitelist.contains).toList();
      _whitelist = whitelist;
      _selectedWilayah = defaultDusun.number;
      _selectedBlok = _semuaBlokValue;
      _selectedTahun = '${DateTime.now().year}';
    } else {
      final whitelist = await WilayahKerjaStore.instance.whitelistedBloks();
      // Hanya tampilkan blok yang termasuk wilayah kerja user perangkat ini —
      // jika belum dipilih atau kosong, tampilkan semua blok agar data DHKP tetap bisa diakses.
      final bloks = allBloks.where(whitelist.contains).toList();
      _isOperator = false;
      _allBloks = allBloks;
      _bloks = bloks.isNotEmpty ? bloks : allBloks;
      _whitelist = whitelist.isNotEmpty ? whitelist : allBloks.toSet();
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
  }

  /// Khusus Mode Operator — pilih dusun mana yang mau dilihat, lalu daftar
  /// Blok yang tersedia mengikuti blok-blok dusun itu.
  void _pilihWilayah(int? wilayah) {
    if (wilayah == null) return;
    final whitelist = dusunByNumber(wilayah)?.bloks.toSet() ?? {};
    setState(() {
      _selectedWilayah = wilayah;
      _whitelist = whitelist;
      _bloks = _allBloks.where(whitelist.contains).toList();
      _selectedBlok = _semuaBlokValue;
    });
    _loadRecords(setBusy: true);
  }

  Future<void> _loadRecords({bool setBusy = false}) async {
    final blok = _selectedBlok;
    if (blok == null) return;

    if (setBusy && mounted) {
      setState(() => _busy = true);
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

  /// Data lingkup saat ini (mengikuti pilihan Blok & Tahun di layar), tapi
  /// selalu terurut blok+wilayah menaik — dipakai untuk unduh/bagikan/cetak
  /// supaya berkasnya tetap baku urutannya apa pun filter urutan tampilan
  /// yang sedang dipakai di layar.
  Future<List<BlokRecord>> _scopedRecordsForExport() async {
    final blok = _selectedBlok;
    if (blok == null) return [];
    var records = blok == _semuaBlokValue
        ? await BlokDataStore.instance.byWhitelist(_whitelist, tahun: _selectedTahun)
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
    _loadRecords(setBusy: true);
  }

  void _pilihTahun(String? tahun) {
    setState(() {
      _selectedTahun = tahun;
      _currentPage = 0;
    });
    _loadRecords(setBusy: true);
  }

  void _pilihKategori(DhkpKategoriFilter? kategori) {
    if (kategori == null) return;
    setState(() {
      _kategoriFilter = kategori;
      _currentPage = 0;
    });
    _loadRecords(setBusy: true);
  }

  void _pilihSort(BlokSortBy? sortBy) {
    if (sortBy == null) return;
    setState(() {
      _sortBy = sortBy;
      _currentPage = 0;
    });
    _loadRecords(setBusy: true);
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
      final newRecord = record.copyWith(
        catatan: controller.text.trim(),
      );
      await BlokDataStore.instance.upsert(newRecord);
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
              constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Theme.of(context).primaryColor,
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long, color: Colors.white),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'INFORMASI DATA PEMBAYARAN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text('Cek Tagihan'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _bukaTagihan(record);
                          },
                        ),
                        const SizedBox(width: 8),
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
      final updatedRecord = record.copyWith(
        namaWajibPajak: namaController.text.trim().isEmpty
            ? record.namaWajibPajak
            : namaController.text.trim(),
        alamatObjek: alamatObjekController.text.trim(),
        alamatWp: alamatWpController.text.trim(),
      );
      await BlokDataStore.instance.upsert(updatedRecord);
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

  Future<void> _uploadDataDialog() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Upload Data DHKP'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: const ListTile(
              leading: Icon(Icons.enhanced_encryption_outlined, color: Colors.teal),
              title: Text('Pilih Berkas (.dkhp / CSV / Excel / TXT)'),
              subtitle: Text('Buka paket .dkhp terenkripsi (rahasia) atau berkas tabel'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'sample'),
            child: const ListTile(
              leading: Icon(Icons.dataset_outlined, color: Colors.blue),
              title: Text('Muat 5 Data Contoh DHKP'),
              subtitle: Text('Contoh lengkap: Target Pemda, Blacklist, Catatan & Foto'),
            ),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'sample') {
      await BlokDataStore.instance.upsertAll(BlokDataStore.initialDhkpRecords);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('5 data contoh DHKP berhasil dimuat.')),
      );
      return;
    }

    if (action == 'file') {
      try {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['dkhp', 'zip', 'csv', 'xlsx', 'xls', 'txt'],
        );
        if (files.isEmpty || files.first.path == null) {
          return;
        }
        final path = files.first.path!;
        final lower = path.toLowerCase();

        if (lower.endsWith('.dkhp') || lower.endsWith('.zip')) {
          final newRecords = await DhkpPackageHelper.unpackDkhp(path);
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Paket .dkhp berhasil diimpor: ${newRecords.length} data & foto berhasil dimuat.',
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
        final newRecords = taxRecords.map((t) => BlokRecord(
          nop: t.nop,
          namaWajibPajak:
              t.namaWajibPajak ?? 'WP ${nopBlok(t.nop)}/${nopWilayah(t.nop)}',
          tahunBayar: nowYear,
          tanggalBayar: t.isPaid ? 'Sudah Bayar' : '',
          jumlahPbb: '',
          statusBayar: t.isPaid ? 'Sudah Bayar' : 'Belum Bayar',
        ));
        await BlokDataStore.instance.upsertAll(newRecords);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newRecords.length} data DHKP berhasil diunggah.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membaca file: $e')),
        );
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
                                      'Belum Ada Foto Objek/SPPT',
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
              title: const Text('Pilih Berkas Dokumen (File Picker)'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (method == null) return null;

    Uint8List? imageBytes;
    String extension = 'jpg';

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
            final ext = picked.name.split('.').last.toLowerCase();
            if (ext.isNotEmpty) extension = ext;
          }
        } catch (_) {
          final res = await FilePicker.pickFiles(type: FileType.image);
          if (res.isNotEmpty && res.first.path != null) {
            final f = File(res.first.path!);
            imageBytes = await f.readAsBytes();
            final name = res.first.name;
            final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
            extension = ext;
          }
        }
      } else if (method == 'file') {
        final res = await FilePicker.pickFiles(type: FileType.image);
        if (res.isNotEmpty && res.first.path != null) {
          final f = File(res.first.path!);
          imageBytes = await f.readAsBytes();
          final name = res.first.name;
          final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
          extension = ext;
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

    final photosDir = await DhkpPackageHelper.photosDirectory();
    final cleanNop = record.nop.replaceAll(RegExp(r'[^0-9]'), '');
    final fileName = '$cleanNop.$extension';
    final targetFile = File('${photosDir.path}/$fileName');
    await targetFile.writeAsBytes(imageBytes);

    final updatedRecord = record.copyWith(namaFoto: fileName);
    await BlokDataStore.instance.upsert(updatedRecord);
    await _loadRecords();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto berhasil disimpan.')),
      );
    }
    return targetFile;
  }

  Future<void> _hapusFoto(BlokRecord record) async {
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
    await _loadRecords();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto telah dihapus.')),
      );
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

  Future<BlokExportFormat?> _pilihFormat(String title) {
    return showDialog<BlokExportFormat>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final format in BlokExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, format),
              child: Text(format.label),
            ),
        ],
      ),
    );
  }

  Future<void> _unduhLaporan() async {
    final format = await _pilihFormat('Unduh Sebagai');
    if (format == null) return;

    setState(() => _busy = true);
    try {
      final records = await _scopedRecordsForExport();
      final bytes = await BlokReportExporter.build(
        format,
        records,
        tahun: _selectedTahun,
      );
      final fileName = BlokReportExporter.fileName(
        format,
        tahun: _selectedTahun,
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
    final format = await _pilihFormat('Bagikan Sebagai');
    if (format == null) return;

    setState(() => _busy = true);
    try {
      final records = await _scopedRecordsForExport();
      final bytes = await BlokReportExporter.build(
        format,
        records,
        tahun: _selectedTahun,
      );
      final fileName = BlokReportExporter.fileName(
        format,
        tahun: _selectedTahun,
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
    setState(() => _busy = true);
    try {
      final records = await _scopedRecordsForExport();
      if (records.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada data untuk dicetak.')),
        );
        return;
      }
      final bytes = await BlokReportExporter.build(
        BlokExportFormat.pdf,
        records,
        tahun: _selectedTahun,
      );
      if (!mounted) return;
      final tahunLabel = _selectedTahun ?? 'semua-tahun';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: bytes,
            fileName: 'Laporan Data Blok ($tahunLabel).pdf',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data DHKP'),
        actions: [
          IconButton(
            onPressed: _uploadDataDialog,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload Data DHKP',
          ),
          if (_bloks.isNotEmpty) ...[
            IconButton(
              onPressed: _busy ? null : _unduhLaporan,
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Unduh (PDF/Excel/CSV)',
            ),
            IconButton(
              onPressed: _busy ? null : _bagikanLaporan,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Bagikan (PDF/Excel/CSV)',
            ),
            IconButton(
              onPressed: _busy ? null : _cetakLaporan,
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Cetak',
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _loading
              ? const _BlokCatatanLoadingView(key: ValueKey('loading-view'))
              : (!_isOperator && _bloks.isEmpty)
                  ? const Center(
                      key: ValueKey('empty-view'),
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Belum ada data DHKP. Tekan tombol Upload Data di kanan atas '
                          'untuk mengunggah berkas atau memuat contoh data.',
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
                    if (_isOperator) ...[
                      DropdownButtonFormField<int>(
                        initialValue: _selectedWilayah,
                        decoration: const InputDecoration(
                          labelText: 'Wilayah (Dusun)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final dusun in dusunList)
                            DropdownMenuItem(
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
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<DhkpKategoriFilter>(
                            key: ValueKey('kategori-$_kategoriFilter'),
                            initialValue: _kategoriFilter,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kategori / Status',
                              border: OutlineInputBorder(),
                            ),
                            items: DhkpKategoriFilter.values
                                .map(
                                  (k) => DropdownMenuItem(
                                    value: k,
                                    child: Text(
                                      k.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _pilihKategori,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<BlokSortBy>(
                            key: ValueKey('sort-$_sortBy'),
                            initialValue: _sortBy,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Urutkan',
                              border: OutlineInputBorder(),
                            ),
                            items: BlokSortBy.values
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _pilihSort,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Kolom Pencarian Cepat (Nama WP, NOP, Alamat)
                    TextField(
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    else
                      const SizedBox(height: 12),
                    Expanded(
                      child: _records.isEmpty
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
                                                            String displayStatus = r.statusBayar;

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
  const _BlokCatatanLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 2,
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary,
                        ),
                        backgroundColor:
                            colorScheme.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 32,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Memuat Data DHKP & Status Bayar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Menyiapkan seluruh catatan blok, bukti STTS, dan rekapitulasi data...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color ?? Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Memastikan semua data termuat',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
