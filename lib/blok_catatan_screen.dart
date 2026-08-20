import 'package:flutter/material.dart';

import 'blok_data_store.dart';
import 'blok_record.dart';
import 'blok_report_exporter.dart';
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'dusun_data.dart';
import 'native_file_helper.dart';
import 'operator_mode_store.dart';
import 'tagihan_result.dart' show formatRupiah;
import 'wilayah_kerja_store.dart';

/// Dikembalikan lewat Navigator.pop saat user menekan "Cetak Bukti Bayar"
/// pada sebuah baris — dipakai MainShell untuk membuka Cek Status Bayar
/// dengan blok/nomor wilayah/tahun sudah terisi otomatis.
class BlokNavigationRequest {
  final String blok;
  final String wilayah;
  final String tahun;

  const BlokNavigationRequest({required this.blok, required this.wilayah, required this.tahun});
}

/// Nilai dropdown Blok untuk menampilkan gabungan semua blok wilayah kerja
/// sekaligus, bukan satu blok saja.
const _semuaBlokValue = '__SEMUA_BLOK__';

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
  BlokSortBy _sortBy = BlokSortBy.blokWilayah;
  List<BlokRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isOperator = await OperatorModeStore.instance.isEnabled();
    final allBloks = await BlokDataStore.instance.blokList();

    if (isOperator) {
      // Operator tidak terikat satu wilayah kerja — bisa pilih dusun mana
      // saja untuk dilihat, default ke dusun pertama yang datanya sudah ada.
      final defaultDusun = dusunList.firstWhere((d) => d.bloks.isNotEmpty, orElse: () => dusunList.first);
      final whitelist = defaultDusun.bloks.toSet();
      setState(() {
        _isOperator = true;
        _allBloks = allBloks;
        _bloks = allBloks.where(whitelist.contains).toList();
        _whitelist = whitelist;
        _selectedWilayah = defaultDusun.number;
        _selectedBlok = _semuaBlokValue;
        _selectedTahun = '${DateTime.now().year}';
        _loading = false;
      });
    } else {
      final whitelist = await WilayahKerjaStore.instance.whitelistedBloks();
      // Hanya tampilkan blok yang termasuk wilayah kerja user perangkat ini —
      // tidak semua user bertugas di blok yang sama.
      final bloks = allBloks.where(whitelist.contains).toList();
      setState(() {
        _isOperator = false;
        _allBloks = allBloks;
        _bloks = bloks;
        _whitelist = whitelist;
        _selectedBlok = bloks.isNotEmpty ? bloks.first : null;
        _selectedTahun = '${DateTime.now().year}';
        _loading = false;
      });
    }
    if (_selectedBlok != null) await _loadRecords();
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
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final blok = _selectedBlok;
    if (blok == null) return;
    final records = blok == _semuaBlokValue
        ? await BlokDataStore.instance.byWhitelist(_whitelist, tahun: _selectedTahun, sortBy: _sortBy)
        : await BlokDataStore.instance.byBlok(blok, tahun: _selectedTahun, sortBy: _sortBy);
    if (!mounted) return;
    setState(() => _records = records);
  }

  /// Data lingkup saat ini (mengikuti pilihan Blok & Tahun di layar), tapi
  /// selalu terurut blok+wilayah menaik — dipakai untuk unduh/bagikan/cetak
  /// supaya berkasnya tetap baku urutannya apa pun filter urutan tampilan
  /// yang sedang dipakai di layar.
  Future<List<BlokRecord>> _scopedRecordsForExport() async {
    final blok = _selectedBlok;
    if (blok == null) return [];
    return blok == _semuaBlokValue
        ? BlokDataStore.instance.byWhitelist(_whitelist, tahun: _selectedTahun)
        : BlokDataStore.instance.byBlok(blok, tahun: _selectedTahun);
  }

  void _pilihBlok(String? blok) {
    if (blok == null) return;
    setState(() => _selectedBlok = blok);
    _loadRecords();
  }

  void _pilihTahun(String? tahun) {
    setState(() => _selectedTahun = tahun);
    _loadRecords();
  }

  void _pilihSort(BlokSortBy? sortBy) {
    if (sortBy == null) return;
    setState(() => _sortBy = sortBy);
    _loadRecords();
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
          'permanen dari Buku Catatan Blok.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true) return;

    await BlokDataStore.instance.deleteByKey(record.uniqueKey);
    await _loadRecords();
  }

  void _cetakBuktiBayar(BlokRecord record) {
    Navigator.pop(
      context,
      BlokNavigationRequest(blok: record.blok, wilayah: record.wilayah, tahun: record.tahunBayar),
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
      final bytes = await BlokReportExporter.build(format, records, tahun: _selectedTahun);
      final fileName = BlokReportExporter.fileName(format, tahun: _selectedTahun);
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laporan tersimpan di $location')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat laporan: $e')),
      );
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
      final bytes = await BlokReportExporter.build(format, records, tahun: _selectedTahun);
      final fileName = BlokReportExporter.fileName(format, tahun: _selectedTahun);
      await NativeFileHelper.shareBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: DownloadHelper.mimeTypeFor(fileName),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membagikan laporan: $e')),
      );
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
      final bytes = await BlokReportExporter.build(BlokExportFormat.pdf, records, tahun: _selectedTahun);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyiapkan cetakan: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPbb = _records.fold<int>(0, (sum, r) => sum + r.jumlahPbbValue);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buku Catatan Blok'),
        actions: _bloks.isEmpty
            ? null
            : [
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
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (!_isOperator && _bloks.isEmpty)
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Belum ada data untuk blok wilayah kerja Anda. Data blok terisi '
                        'otomatis setiap kali Cek Status Bayar menemukan status "Sudah '
                        'Bayar", untuk blok yang sudah ditandai sebagai wilayah kerja Anda '
                        '(bisa diatur di Setelan > Data Blok).',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Padding(
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
                                  child: Text('${dusun.label} (${dusun.bloks.length} blok)'),
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
                                decoration: const InputDecoration(labelText: 'Blok', border: OutlineInputBorder()),
                                items: [
                                  const DropdownMenuItem(
                                    value: _semuaBlokValue,
                                    child: Text('Semua Blok (Wilayah Kerja)'),
                                  ),
                                  for (final b in _bloks)
                                    DropdownMenuItem(value: b, child: Text('Blok ${int.parse(b)}')),
                                ],
                                onChanged: _pilihBlok,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: _selectedTahun,
                                decoration: const InputDecoration(labelText: 'Tahun', border: OutlineInputBorder()),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Semua')),
                                  for (final y in _availableYears())
                                    DropdownMenuItem(value: '$y', child: Text('$y')),
                                ],
                                onChanged: _pilihTahun,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<BlokSortBy>(
                          initialValue: _sortBy,
                          decoration: const InputDecoration(labelText: 'Urutkan Berdasarkan', border: OutlineInputBorder()),
                          items: BlokSortBy.values
                              .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                              .toList(),
                          onChanged: _pilihSort,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _records.isEmpty
                              ? const Center(child: Text('Tidak ada data untuk filter ini.'))
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Nama WP')),
                                      DataColumn(label: Text('NOP')),
                                      DataColumn(label: Text('Tahun Bayar')),
                                      DataColumn(label: Text('Tanggal Bayar')),
                                      DataColumn(label: Text('Jumlah PBB')),
                                      DataColumn(label: Text('')),
                                    ],
                                    rows: _records
                                        .map((r) => DataRow(cells: [
                                              DataCell(Text(r.namaWajibPajak)),
                                              DataCell(Text(r.nop)),
                                              DataCell(Text(r.tahunBayar)),
                                              DataCell(Text(r.tanggalBayar.isEmpty ? '-' : r.tanggalBayar)),
                                              DataCell(Text(r.jumlahPbb.isEmpty ? '-' : r.jumlahPbb)),
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      onPressed: () => _cetakBuktiBayar(r),
                                                      icon: const Icon(Icons.picture_as_pdf),
                                                      tooltip: 'Cetak Bukti Bayar',
                                                    ),
                                                    IconButton(
                                                      onPressed: () => _hapusBaris(r),
                                                      icon: const Icon(Icons.delete_outline),
                                                      tooltip: 'Hapus Baris',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ]))
                                        .toList(),
                                  ),
                                ),
                        ),
                        if (_selectedTahun != null) ...[
                          const Divider(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total: ${formatRupiah(formatRibuan(totalPbb))}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
