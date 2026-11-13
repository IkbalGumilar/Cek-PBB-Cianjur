import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_security_service.dart';
import 'batch_check_screen.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'blok_report_exporter.dart';
import 'blok_report_pdf.dart';
import 'blok_sync_service.dart';
import 'dhkp/dhkp_nop_kalkulator_dialog.dart';
import 'dhkp/dhkp_target_pacing_dialog.dart';
import 'calculator/pbb_calculator_models.dart';
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
import 'feature_tour/feature_tour.dart';
import 'google_drive_picker_dialog.dart';
import 'image_crop_helper.dart';
import 'kolase_foto_screen.dart';
import 'map/dhkp_map_screen.dart';
import 'native_file_helper.dart';
import 'nop_helper.dart';
import 'operator_mode_store.dart';
import 'tax_record.dart';
import 'ui/app_design_system.dart';
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
  String _selectedTahun = '${DateTime.now().year}';
  int? _selectedWilayah;
  DhkpKategoriFilter _kategoriFilter = DhkpKategoriFilter.semua;
  bool _sembunyikanNihil = false;
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

  final _toggleGrafikButtonKey = GlobalKey(debugLabel: 'tour_dhkp_grafik_btn');
  final _moreMenuButtonKey = GlobalKey(debugLabel: 'tour_dhkp_more_btn');
  final _filterBlokTahunKey = GlobalKey(debugLabel: 'tour_dhkp_filter_bar');
  final _searchFilterSortKey = GlobalKey(debugLabel: 'tour_dhkp_search_bar');
  final _tableAreaKey = GlobalKey(debugLabel: 'tour_dhkp_table_area');
  final _summaryFooterKey = GlobalKey(debugLabel: 'tour_dhkp_summary_footer');
  VoidCallback? _showGrafikTour;
  Future<void> Function()? _printGrafikCallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    FeatureTourController.dismissActiveTour();
    AppSecurityService.instance.setScreenSecure(false);
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onHelpPressed() {
    if (_tampilkanGrafik) {
      _showGrafikTour?.call();
    } else {
      showTableTour();
    }
  }

  void showTableTour() {
    if (!mounted || _loading) return;
    FeatureTourController.showTour(
      context: context,
      tourId: 'dhkp_table_view',
      steps: _buildTableTourSteps(),
    );
  }

  List<FeatureTourStep> _buildTableTourSteps() {
    return [
      FeatureTourStep(
        targetKey: _toggleGrafikButtonKey,
        title: 'Tombol Beralih ke Tampilan Grafik',
        description:
            'Tekan ikon diagram ini untuk melihat laporan DHKP dalam bentuk grafik batang, diagram lingkaran, dan kurva tren bulanan yang mudah dipahami.',
        actionHint:
            'Tekan kembali tombol yang sama saat berada di layar grafik untuk kembali ke tabel catatan ini.',
        icon: Icons.bar_chart_rounded,
      ),
      FeatureTourStep(
        targetKey: _moreMenuButtonKey,
        title: 'Menu Aksi DHKP & Fitur Lanjutan',
        description:
            'Tekan ikon tiga titik ini untuk mengakses seluruh fitur utama:\n'
            '• Unggah Berkas DHKP / Laporan (.dat): Memuat berkas daftar pajak.\n'
            '• Buat Paket Laporan (.dat): Mengemas data DHKP dan foto STTS.\n'
            '• Peta Objek Pajak: Menampilkan sebaran bidang tanah di peta.\n'
            '• Cetak, Bagikan, & Unduh Laporan: Rekap PDF, Excel, atau CSV.\n'
            '• Kolase Gambar Dokumentasi & Cek Status Bayar Massal.',
        icon: Icons.more_vert_rounded,
      ),
      FeatureTourStep(
        targetKey: _filterBlokTahunKey,
        title: 'Pilihan Wilayah Dusun, Blok, & Tahun Pajak',
        description:
            'Pilih dusun (khusus operator), nomor Blok tertentu atau "Semua Blok", serta Tahun Pajak untuk menampilkan daftar wajib pajak yang ingin Anda periksa.',
        icon: Icons.filter_alt_outlined,
      ),
      FeatureTourStep(
        targetKey: _searchFilterSortKey,
        title: 'Pencarian Cepat, Saring Kategori, & Urutan Baris',
        description:
            '• Kotak Cari: Ketik nama warga, nomor objek pajak, atau alamat untuk menemukan baris dengan cepat.\n'
            '• Tombol Saring (Ikon Corong): Tampilkan hanya warga yang Sudah Bayar, Belum Bayar, khusus Target Pemda, atau yang sudah memiliki foto/catatan.\n'
            '• Tombol Urutkan: Urutkan daftar berdasarkan nomor wilayah, abjad nama, nominal pajak tertinggi/terendah, atau status bayar.',
        icon: Icons.manage_search_rounded,
      ),
      FeatureTourStep(
        targetKey: _tableAreaKey,
        title: 'Tabel Daftar Wajib Pajak & Tombol Aksi Baris',
        description:
            'Di setiap baris warga, Anda dapat:\n'
            '• Kolom Gambar: Memotret atau mengunggah foto lembar STTS/bukti bayar.\n'
            '• Kolom Aksi: Melihat rincian lengkap objek pajak, mencetak bukti lunas PDF, atau langsung memeriksa status bayar.\n'
            '• Kolom Catatan: Menambahkan catatan keterangan petugas untuk wajib pajak tersebut.',
        actionHint:
            'Geser tabel ke kiri/kanan atau atas/bawah untuk melihat seluruh kolom dan baris.',
        icon: Icons.table_rows_outlined,
      ),
      FeatureTourStep(
        targetKey: _summaryFooterKey,
        title: 'Kartu Ringkasan Capaian & Target Pemda',
        description:
            'Menampilkan rekap otomatis untuk daftar yang sedang dibuka: jumlah & rupiah Sudah Bayar, Kurang Bayar, persentase pelunasan, serta informasi Target Pemda yang dipisahkan secara khusus.',
        actionHint:
            'Ketuk kepala kartu ringkasan ini untuk melipat atau membukanya agar ruang tabel lebih lega.',
        icon: Icons.summarize_outlined,
      ),
    ];
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

    if (!_tampilkanGrafik) {
      FeatureTourController.startTourIfNeeded(
        context: context,
        tourId: 'dhkp_table_view',
        steps: _buildTableTourSteps(),
      );
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

    final filteredScope = DhkpSummaryMetrics.filterOutNihil(
      allScope,
      excludeNihil: _sembunyikanNihil,
    );
    final metrics = DhkpSummaryMetrics.compute(filteredScope);
    var records = DhkpSummaryMetrics.filterByKategori(
      filteredScope,
      _kategoriFilter,
    );
    records = DhkpSummaryMetrics.filterBySearch(records, _searchQuery);

    if (!mounted) return;
    setState(() {
      _photosDir = photosDir;
      _cachedPhotoFileNames = photoNames;
      _records = records;
      _allScopeRecords = filteredScope;
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
    bool? excludeNihilOverride,
  ]) async {
    final blok = blokOverride ?? _selectedBlok;
    final rawRecords = (blok == null || blok == semuaBlokValue)
        ? (_whitelist.isNotEmpty
              ? await BlokDataStore.instance.byWhitelist(
                  _whitelist,
                  tahun: _selectedTahun,
                )
              : await BlokDataStore.instance.forReport(tahun: _selectedTahun))
        : await BlokDataStore.instance.byBlok(blok, tahun: _selectedTahun);

    final records = DhkpSummaryMetrics.filterOutNihil(
      rawRecords,
      excludeNihil: excludeNihilOverride ?? _sembunyikanNihil,
    );
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

  void _pilihTahun(String tahun) {
    setState(() {
      _selectedTahun = tahun;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: 'Memuat data tahun pajak $tahun...',
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

  void _toggleSembunyikanNihil() {
    setState(() {
      _sembunyikanNihil = !_sembunyikanNihil;
      _currentPage = 0;
    });
    _loadRecords(
      setBusy: true,
      busyMessage: _sembunyikanNihil
          ? 'Mengecualikan SPPT Rp 0 (Nihil)...'
          : 'Menampilkan kembali SPPT Rp 0 (Nihil)...',
      busyIcon: Icons.money_off_csred_outlined,
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

  /// Membuka kalkulator terpadu (Denda, Cicilan & Tabungan Warga, AJB)
  Future<void> _bukaKalkulatorNop(
    BlokRecord record, {
    int initialTab = 0,
  }) async {
    await showNopKalkulatorDialog(
      context,
      record: record,
      initialTab: initialTab,
      onCekTagihan: () => _bukaTagihan(record),
      onRecordUpdated: (updated) async {
        await BlokDataStore.instance.upsert(updated);
        unawaited(
          BlokSyncService.instance.recordChange(
            record: updated,
            catatan: updated.catatan,
          ),
        );
        await _loadRecords();
      },
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
    final allRecords = rawRecords
        .where((r) => r.tahunBayar.isEmpty || r.tahunBayar == _selectedTahun)
        .toList();
    final Map<String, List<BlokRecord>> recordsByBlok = {};
    for (final r in allRecords) {
      final b = nopBlok(r.nop);
      if (b.isNotEmpty) {
        recordsByBlok.putIfAbsent(b, () => []).add(r);
      }
    }

    if (!mounted) return;

    final downloadSttsOption = ValueNotifier<bool>(false);
    final selectedRecords = await showPilihBlokCekMassalDialog(
      context,
      availableBloks: availableBloks,
      recordsByBlok: recordsByBlok,
      selectedWilayah: _selectedWilayah,
      downloadSttsOption: downloadSttsOption,
    );
    final downloadStts = downloadSttsOption.value;
    downloadSttsOption.dispose();

    if (selectedRecords == null || selectedRecords.isEmpty || !mounted) return;

    Directory? targetSttsDir;
    String? cleanBlok;
    if (downloadStts) {
      final pickedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih Folder Penyimpanan Berkas STTS',
      );
      if (pickedPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pengecekan massal dibatalkan karena folder penyimpanan STTS tidak dipilih.',
              ),
            ),
          );
        }
        return;
      }

      final blokStr = nopBlok(selectedRecords.first.nop);
      cleanBlok = blokStr.replaceAll(RegExp(r'[^0-9]'), '');
      final blokFormatted = cleanBlok.isNotEmpty
          ? cleanBlok.padLeft(3, '0')
          : blokStr;
      final now = DateTime.now();
      const namaHariList = [
        'Senin',
        'Selasa',
        'Rabu',
        'Kamis',
        'Jumat',
        'Sabtu',
        'Minggu',
      ];
      final namaHari = namaHariList[now.weekday - 1];
      final tgl = now.day.toString().padLeft(2, '0');
      final bln = now.month.toString().padLeft(2, '0');
      final thn = now.year.toString();
      final folderName = 'STTS Blok $blokFormatted - $namaHari, $tgl-$bln-$thn';

      targetSttsDir = Directory('$pickedPath/$folderName');
      if (!await targetSttsDir.exists()) {
        await targetSttsDir.create(recursive: true);
      }
    }

    final taxRecords = selectedRecords
        .map(
          (r) => TaxRecord(
            nop: r.nop,
            namaWajibPajak: r.namaWajibPajak,
            status: r.isPaid ? 'Sudah Bayar' : 'Belum Bayar',
            tanggalBayar: r.tanggalBayar,
            jumlahPbb: r.jumlahPbb,
          ),
        )
        .toList();
    final tahun = _selectedTahun;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchCheckScreen(
          records: taxRecords,
          tahun: tahun,
          downloadStts: downloadStts,
          sttsTargetDirectory: targetSttsDir,
          sttsBlokNumber: cleanBlok,
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

      if (!mounted || location == null) return;
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
          jumlahPbb: cleanNominalRupiah(t.jumlahPbb ?? ''),
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
      await FileImage(targetFile).evict();

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
          const SnackBar(
            content: Text('Foto berhasil disimpan.'),
            behavior: SnackBarBehavior.floating,
          ),
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
        await FileImage(photo).evict();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto telah dihapus.'),
            behavior: SnackBarBehavior.floating,
          ),
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
      initialSertakanNihil: !_sembunyikanNihil,
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
      final records = await _scopedRecordsForExport(
        opsi.blok,
        !opsi.sertakanNihil,
      );
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
        kategoriFilter: _kategoriFilter,
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
        kategoriFilter: _kategoriFilter,
      );
      final location = await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted || location == null) return;
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
      final records = await _scopedRecordsForExport(
        opsi.blok,
        !opsi.sertakanNihil,
      );
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
        kategoriFilter: _kategoriFilter,
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
        kategoriFilter: _kategoriFilter,
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

  Future<void> _cetakDariMenu() async {
    if (_tampilkanGrafik && _printGrafikCallback != null) {
      final pilihan = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pilih Jenis Cetakan'),
          content: const Text(
            'Anda sedang membuka tampilan Grafik DHKP. Ingin mencetak grafik aktif atau laporan tabel DHKP?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'grafik'),
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: const Text('Cetak Grafik'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'laporan'),
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Cetak Laporan'),
            ),
          ],
        ),
      );
      if (!mounted || pilihan == null) return;
      if (pilihan == 'grafik') {
        await _printGrafikCallback?.call();
        return;
      }
    }
    await _cetakLaporan();
  }

  Future<void> _cetakPdfDenganBatal({
    required Future<List<BlokRecord>> Function() loadRecords,
    required String blokTitle,
    required String emptyMessage,
    required String initialMessage,
  }) async {
    final cancelToken = BlokPrintCancelToken();
    var emptyRecords = false;
    setState(() {
      _busy = true;
      _busyMessage = initialMessage;
      _busyIcon = Icons.print_rounded;
    });
    try {
      final bytes = await runCancellableDhkpPrint<Uint8List>(
        context: context,
        cancelToken: cancelToken,
        title: 'Menyiapkan Cetakan DHKP',
        initialMessage: initialMessage,
        subtitle:
            'Data DHKP berukuran besar memerlukan waktu. Tekan Batal Cetak jika ingin membatalkan proses cetak.',
        task: (reportProgress) async {
          final records = await loadRecords();
          if (cancelToken.isCancelled) {
            throw const BlokPrintCancelledException();
          }
          if (records.isEmpty) {
            emptyRecords = true;
            throw const BlokPrintCancelledException();
          }
          return BlokReportExporter.build(
            BlokExportFormat.pdf,
            records,
            tahun: _selectedTahun,
            blokTitle: blokTitle,
            kategoriFilter: _kategoriFilter,
            cancelToken: cancelToken,
            onProgress: (current, total) async {
              reportProgress(current, total);
              if (mounted && !cancelToken.isCancelled) {
                setState(() {
                  _busyMessage = 'Menyusun halaman $current dari $total...';
                });
              }
            },
          );
        },
      );
      if (!mounted) return;
      if (emptyRecords) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(emptyMessage)));
        return;
      }
      if (bytes == null || cancelToken.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proses cetak DHKP dibatalkan.')),
        );
        return;
      }
      final fileName =
          '${buildReportJudul(blokTitle: blokTitle, kategoriFilter: _kategoriFilter, tahun: _selectedTahun)}.pdf';
      await DocumentPreviewScreen.printOrPreview(
        context,
        pdfBytes: bytes,
        fileName: fileName,
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

  Future<void> _cetakLaporan() async {
    final opsi = await _pilihOpsiEkspor(
      title: 'Cetak Laporan DHKP',
      actionButtonLabel: DocumentPreviewScreen.isDesktop
          ? 'Cetak Langsung'
          : 'Buka Cetakan',
      actionIcon: Icons.print_rounded,
      fixedPdf: true,
    );
    if (opsi == null || !mounted) return;

    final blokTitle = opsi.blok == semuaBlokValue
        ? 'Semua Blok'
        : 'Blok ${opsi.blok}';
    await _cetakPdfDenganBatal(
      loadRecords: () =>
          _scopedRecordsForExport(opsi.blok, !opsi.sertakanNihil),
      blokTitle: blokTitle,
      emptyMessage: 'Belum ada data untuk dicetak.',
      initialMessage: 'Menyiapkan dokumen cetak PDF...',
    );
  }

  /// Pintasan Cetak Cepat (`Ctrl + P`):
  /// - Jika sedang di tab Grafik: mencetak grafik/diagram aktif (atau 1 bulan
  ///   yang dipilih pada Tren Pembayaran) dengan opsi Batal Cetak.
  /// - Jika sedang di tampilan Tabel DHKP: mencetak data `_records` yang sedang
  ///   disaring di layar dengan dialog progres serta tombol Batal Cetak.
  Future<void> _cetakLangsungShortcut() async {
    if (_loading || _busy) return;
    if (_tampilkanGrafik) {
      await _printGrafikCallback?.call();
      return;
    }

    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Belum ada data pada tampilan filter saat ini untuk dicetak.',
          ),
        ),
      );
      return;
    }

    final blokTitle = (_selectedBlok == null || _selectedBlok == semuaBlokValue)
        ? (_selectedWilayah != null ? 'Dusun $_selectedWilayah' : 'Semua Blok')
        : 'Blok $_selectedBlok';
    final targetRecords = List<BlokRecord>.from(_records);
    await _cetakPdfDenganBatal(
      loadRecords: () async => targetRecords,
      blokTitle: blokTitle,
      emptyMessage:
          'Belum ada data pada tampilan filter saat ini untuk dicetak.',
      initialMessage: 'Menyiapkan cetakan sesuai filter tampilan saat ini...',
    );
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

  void _bukaPeta() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DhkpMapScreen(
          initialRecords: _records,
          initialDusun: _selectedWilayah,
          initialBlok: (_selectedBlok != null && _selectedBlok != 'Semua')
              ? _selectedBlok
              : null,
        ),
      ),
    );
  }

  void _bukaTargetPacingDialog() {
    final blokTitle = _selectedBlok == null || _selectedBlok == semuaBlokValue
        ? (_selectedWilayah != null
              ? 'Dusun $_selectedWilayah'
              : 'Semua Wilayah (Desa)')
        : 'Blok $_selectedBlok';
    showTargetPacingDialog(
      context,
      totalKetetapan: _summaryMetrics.totalNominal,
      realisasi: _summaryMetrics.sudahBayarNominal,
      totalNop: _summaryMetrics.totalCount,
      wilayahTitle: blokTitle,
    );
  }

  void _bukaKalkulatorAjb() {
    showStandaloneAjbDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _cetakLangsungShortcut,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            _cetakLangsungShortcut,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 4,
            title: const Text('Data DHKP'),
            actions: [
              IconButton(
                key: _toggleGrafikButtonKey,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  FeatureTourController.dismissActiveTour();
                  setState(() {
                    _tampilkanGrafik = !_tampilkanGrafik;
                    _updateScreenSecurity();
                  });
                  if (!_tampilkanGrafik) {
                    FeatureTourController.startTourIfNeeded(
                      context: context,
                      tourId: 'dhkp_table_view',
                      steps: _buildTableTourSteps(),
                    );
                  }
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
                key: const ValueKey('dhkp_target_pacing_btn'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.speed_rounded),
                tooltip: 'Target & Pacing Realisasi',
                onPressed: _bukaTargetPacingDialog,
              ),
              FeatureTourHelpButton(onPressed: _onHelpPressed),
              PopupMenuButton<String>(
                key: _moreMenuButtonKey,
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'Menu & Aksi Lainnya',
                onSelected: (val) {
                  switch (val) {
                    case 'unggah_dhkp':
                      _uploadDataDialog();
                      break;
                    case 'buat_laporan_dat':
                      _buatLaporanDatDialog();
                      break;
                    case 'peta_dhkp':
                      _bukaPeta();
                      break;
                    case 'cetak':
                      _cetakDariMenu();
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
                    case 'kalkulator_ajb':
                      _bukaKalkulatorAjb();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'unggah_dhkp',
                    child: ListTile(
                      leading: Icon(Icons.upload_file_outlined),
                      title: Text('Unggah Berkas DHKP / Laporan (.dat)'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  if (_bloks.isNotEmpty) ...[
                    const PopupMenuItem(
                      value: 'buat_laporan_dat',
                      child: ListTile(
                        leading: Icon(Icons.download_rounded),
                        title: Text('Buat Paket Laporan (.dat)'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'peta_dhkp',
                      child: ListTile(
                        leading: Icon(Icons.explore_outlined),
                        title: Text.rich(
                          TextSpan(
                            text: 'Peta Objek Pajak ',
                            children: [
                              TextSpan(
                                text: '(Eksperimental)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFE67E22),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
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
                    const PopupMenuItem(
                      value: 'kalkulator_ajb',
                      child: ListTile(
                        leading: Icon(Icons.calculate_outlined),
                        title: Text('Kalkulator AJB & Simulasi NJOP'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: AppMotion.resolve(context, AppMotion.complex),
              switchInCurve: AppMotion.enterCurve,
              switchOutCurve: AppMotion.exitCurve,
              child: (_loading || (_busy && _allBloks.isEmpty))
                  ? BlokCatatanLoadingView(
                      key: const ValueKey('loading-view'),
                      title: _loading
                          ? 'Memuat Data DHKP & Status Bayar'
                          : _busyMessage,
                    )
                  : (_allBloks.isEmpty || (!_isOperator && _bloks.isEmpty))
                  ? Center(
                      key: const ValueKey('empty-view'),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: AppEmptyStateCard(
                            icon: Icons.folder_open_rounded,
                            title: 'Belum Ada Data DHKP',
                            subtitle:
                                'Belum ada data DHKP. Tekan tombol di bawah atau menu tiga titik (⋮) di kanan atas lalu pilih Unggah Berkas DHKP '
                                'untuk memuat berkas daftar pajak.',
                            actionLabel: 'Unggah Berkas DHKP',
                            actionIcon: Icons.upload_file_outlined,
                            onAction: _uploadDataDialog,
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      key: const ValueKey('content-view'),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                            key: _filterBlokTahunKey,
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
                                          'Blok ${int.tryParse(b) ?? b}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: _pilihBlok,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
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
                                    for (final y in availableDhkpYears())
                                      DropdownMenuItem(
                                        value: '$y',
                                        child: Text('$y'),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) _pilihTahun(v);
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (!_tampilkanGrafik) ...[
                            const SizedBox(height: 8),
                            Row(
                              key: _searchFilterSortKey,
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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.outline,
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
                                Tooltip(
                                  message: _sembunyikanNihil
                                      ? 'SPPT Rp 0 (Nihil) sedang dikecualikan — ketuk untuk menampilkan kembali'
                                      : 'Kecualikan SPPT Rp 0 (Nihil) dari tampilan dan cetakan',
                                  child: InkWell(
                                    key: const ValueKey(
                                      'dhkp_exclude_nihil_btn',
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: _toggleSembunyikanNihil,
                                    child: Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _sembunyikanNihil
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.tertiaryContainer
                                            : null,
                                        border: Border.all(
                                          color: _sembunyikanNihil
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.tertiary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.money_off_csred_outlined,
                                            size: 18,
                                            color: _sembunyikanNihil
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .onTertiaryContainer
                                                : null,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Tanpa Rp 0',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: _sembunyikanNihil
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: _sembunyikanNihil
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .onTertiaryContainer
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
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
                                            : Theme.of(
                                                context,
                                              ).colorScheme.outline,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sort_rounded,
                                          size: 20,
                                          color:
                                              _sortBy != BlokSortBy.blokWilayah
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .onSecondaryContainer
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
                                    key: ValueKey(
                                      'dhkp_grafik_${_selectedBlok}_${_selectedWilayah}_$_selectedTahun',
                                    ),
                                    records: _allScopeRecords.isNotEmpty
                                        ? _allScopeRecords
                                        : _records,
                                    selectedBlok: _selectedBlok,
                                    selectedWilayah: _selectedWilayah,
                                    selectedTahun: _selectedTahun,
                                    onTahunChanged: _pilihTahun,
                                    onRegisterShowTour: (fn) =>
                                        _showGrafikTour = fn,
                                    onRegisterPrintShortcut: (fn) =>
                                        _printGrafikCallback = fn,
                                  )
                                : _records.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Tidak ada data untuk filter ini.',
                                    ),
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
                                        : _records.sublist(
                                            startIndex,
                                            endIndex,
                                          );

                                    return Column(
                                      key: _tableAreaKey,
                                      children: [
                                        Expanded(
                                          child: Scrollbar(
                                            controller:
                                                _verticalScrollController,
                                            thumbVisibility: true,
                                            interactive: true,
                                            notificationPredicate: (notif) =>
                                                notif.metrics.axis ==
                                                Axis.vertical,
                                            child: Scrollbar(
                                              controller:
                                                  _horizontalScrollController,
                                              thumbVisibility: true,
                                              trackVisibility: true,
                                              interactive: true,
                                              scrollbarOrientation:
                                                  ScrollbarOrientation.bottom,
                                              notificationPredicate: (notif) =>
                                                  notif.metrics.axis ==
                                                  Axis.horizontal,
                                              child: SingleChildScrollView(
                                                controller:
                                                    _horizontalScrollController,
                                                scrollDirection:
                                                    Axis.horizontal,
                                                physics:
                                                    const AlwaysScrollableScrollPhysics(),
                                                child: SingleChildScrollView(
                                                  controller:
                                                      _verticalScrollController,
                                                  scrollDirection:
                                                      Axis.vertical,
                                                  physics:
                                                      const AlwaysScrollableScrollPhysics(),
                                                  child: DataTable(
                                                    columnSpacing: 18,
                                                    horizontalMargin: 12,
                                                    columns: const [
                                                      DataColumn(
                                                        label: Text('No'),
                                                      ),
                                                      DataColumn(
                                                        label: Text('Nama WP'),
                                                      ),
                                                      DataColumn(
                                                        label: Text(
                                                          'NOP / Blok',
                                                        ),
                                                      ),
                                                      DataColumn(
                                                        label: Text(
                                                          'Tahun Pajak',
                                                        ),
                                                      ),
                                                      DataColumn(
                                                        label: Text(
                                                          'Pokok / Ketetapan',
                                                        ),
                                                      ),
                                                      DataColumn(
                                                        label: Text(
                                                          'Status Bayar',
                                                        ),
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
                                                          final r =
                                                              pagedRecords[i];
                                                          final isDark =
                                                              Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark;

                                                          return DataRow(
                                                            color: WidgetStateProperty.resolveWith<Color?>((
                                                              states,
                                                            ) {
                                                              if (r
                                                                  .isTargetPemda) {
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
                                                                        width:
                                                                            4,
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
                                                                            color:
                                                                                Colors.white,
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
                                                                            FontWeight.w500,
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
                                                                Text(
                                                                  r.tahunBayar,
                                                                ),
                                                              ),
                                                              DataCell(
                                                                Text(
                                                                  r.formattedJumlahPbb,
                                                                ),
                                                              ),
                                                              DataCell(
                                                                DhkpStatusBadge(
                                                                  record: r,
                                                                ),
                                                              ),
                                                              DataCell(
                                                                _buildGambarCell(
                                                                  r,
                                                                ),
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
                                                                    if (r
                                                                        .isPaid)
                                                                      IconButton(
                                                                        onPressed: () =>
                                                                            _cetakBuktiBayar(
                                                                              r,
                                                                            ),
                                                                        icon: const Icon(
                                                                          Icons
                                                                              .picture_as_pdf,
                                                                          color:
                                                                              Colors.green,
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
                                                                          color:
                                                                              Colors.teal,
                                                                        ),
                                                                        tooltip:
                                                                            'Cek Status Bayar (Update jika Lunas)',
                                                                      ),
                                                                    IconButton(
                                                                      onPressed: () =>
                                                                          _bukaKalkulatorNop(
                                                                            r,
                                                                          ),
                                                                      icon: const Icon(
                                                                        Icons
                                                                            .calculate_outlined,
                                                                        color: Colors
                                                                            .deepPurple,
                                                                      ),
                                                                      tooltip:
                                                                          'Kalkulator Denda, Cicilan & AJB',
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              DataCell(() {
                                                                final cleanCatatan =
                                                                    PbbTabunganHelper.cleanCatatan(
                                                                      r.catatan,
                                                                    );
                                                                final hasCatatan =
                                                                    cleanCatatan
                                                                        .isNotEmpty;

                                                                return Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    IconButton(
                                                                      onPressed: () =>
                                                                          _editCatatanDialog(
                                                                            r,
                                                                          ),
                                                                      icon: Icon(
                                                                        hasCatatan
                                                                            ? Icons.edit_note
                                                                            : Icons.description_outlined,
                                                                        color:
                                                                            hasCatatan
                                                                            ? Colors.amber.shade800
                                                                            : Colors.grey.shade600,
                                                                      ),
                                                                      tooltip:
                                                                          hasCatatan
                                                                          ? 'Catatan: $cleanCatatan'
                                                                          : 'Tambah Catatan Petugas',
                                                                    ),
                                                                    DhkpRowCelenganButton(
                                                                      record: r,
                                                                      onPressed: () =>
                                                                          _bukaKalkulatorNop(
                                                                            r,
                                                                            initialTab:
                                                                                1,
                                                                          ),
                                                                    ),
                                                                  ],
                                                                );
                                                              }()),
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
                                          onPageChanged: (page) => setState(
                                            () => _currentPage = page,
                                          ),
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
                            DhkpSummaryFooterCard(
                              key: _summaryFooterKey,
                              metrics: _summaryMetrics,
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
