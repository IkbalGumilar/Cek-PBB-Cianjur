import 'package:flutter/material.dart';

import 'document_preview_screen.dart';
import 'feature_tour/feature_tour.dart';
import 'kelola_anggota_screen.dart';
import 'monitoring/monitoring_form_fields.dart';
import 'settings_screen.dart';
import 'staff_portal/kolektif_group_dialogs.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';
import 'ui/app_design_system.dart';

/// Menu "Pembayaran Kolektif" — daftar & filter grup kolektif (meniru tabel
/// dan filter halaman asli `m179`/`reloadDataGroup`), ditambah dua aksi yang
/// mengubah data di server pemda:
///
///  * **Tambah Group** (`tambahGroup()`) — membuat grup baru berstatus Draft.
///  * **Hapus Group** (`#btn-confirm-delete-group`) — menghapus grup, tercatat
///    permanen di "Log History Penghapusan" beserta alasan & nama akunnya.
///
/// Aksi anggota grup ada di [KelolaAnggotaScreen]. **Finalkan**, **Generate
/// VA**, dan **upload CSV** TETAP tidak dibuat: dua yang pertama menerbitkan
/// kode bayar sungguhan.
///
/// Karena kedua aksi di atas meninggalkan jejak permanen, alurnya sengaja
/// dibuat dua langkah — isi form dulu, lalu layar konfirmasi yang menampilkan
/// persis apa yang akan dikirim — bukan satu tombol langsung jalan.
class PembayaranKolektifScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController themeController;

  const PembayaranKolektifScreen({
    super.key,
    required this.client,
    required this.themeController,
  });

  @override
  State<PembayaranKolektifScreen> createState() =>
      _PembayaranKolektifScreenState();
}

class _PembayaranKolektifScreenState extends State<PembayaranKolektifScreen> {
  static const String _tourId = 'pembayaran_kolektif_screen';

  final GlobalKey _tambahGroupButtonKey = GlobalKey(
    debugLabel: 'kolektif_tambah_group_btn',
  );
  final GlobalKey _filterAreaKey = GlobalKey(
    debugLabel: 'kolektif_filter_area',
  );
  final GlobalKey _tampilkanButtonKey = GlobalKey(
    debugLabel: 'kolektif_tampilkan_btn',
  );
  final GlobalKey _resultAreaKey = GlobalKey(
    debugLabel: 'kolektif_result_area',
  );

  String _bulan = '0';
  String _status = '';
  final _tahun = TextEditingController();
  final _tglAwal = TextEditingController();
  final _tglAkhir = TextEditingController();

  bool _loading = false;
  bool _aksiBerjalan = false;
  KolektifListResult? _result;
  KolektifFormOptions? _formOptions;

  static const _bulanOptions = [
    ('0', 'Semua'),
    ('1', 'Januari'),
    ('2', 'Februari'),
    ('3', 'Maret'),
    ('4', 'April'),
    ('5', 'Mei'),
    ('6', 'Juni'),
    ('7', 'Juli'),
    ('8', 'Agustus'),
    ('9', 'September'),
    ('10', 'Oktober'),
    ('11', 'November'),
    ('12', 'Desember'),
  ];
  static const _statusOptions = [
    ('', 'Semua'),
    ('0', 'Draft'),
    ('1', 'Siap Dibayar'),
    ('2', 'Sudah Di Bayar'),
    ('99', 'Kedaluwarsa'),
  ];

  static String _labelStatus(String code) => switch (code) {
    '0' => 'Draft',
    '1' => 'Siap Dibayar',
    '2' => 'Sudah Di Bayar',
    '99' => 'Kedaluwarsa',
    _ => code.isEmpty ? '-' : code,
  };

  @override
  void initState() {
    super.initState();
    _muat();
    _muatOpsiForm();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FeatureTourController.showTourIfNeeded(
        context: context,
        tourId: _tourId,
        steps: _buildTourSteps(),
      );
    });
  }

  void showTour() {
    if (!mounted) return;
    FeatureTourController.showTour(
      context: context,
      tourId: _tourId,
      steps: _buildTourSteps(),
    );
  }

  List<FeatureTourStep> _buildTourSteps() {
    return [
      FeatureTourStep(
        targetKey: _tambahGroupButtonKey,
        title: 'Tombol Buat Rombongan Baru (Tambah Grup)',
        description:
            'Ketuk tombol ini untuk membuat grup rombongan bayar baru. Anda cukup mengisi nama grup, keterangan, nama petugas kolektor, dan nomor HP.',
        icon: Icons.group_add_outlined,
        actionHint:
            'Grup baru akan berstatus Draft sehingga masih bisa ditambah/dikurangi anggotanya',
      ),
      FeatureTourStep(
        targetKey: _filterAreaKey,
        title: 'Penyaring Daftar Grup',
        description:
            'Saring daftar rombongan bayar berdasarkan Bulan, Status (Draft, Siap Dibayar, Sudah Dibayar), Tahun, atau rentang tanggal pembuatan.',
        icon: Icons.filter_alt_outlined,
      ),
      FeatureTourStep(
        targetKey: _tampilkanButtonKey,
        title: 'Tombol Tampilkan & Muat Ulang',
        description:
            'Ketuk tombol ini untuk memperbarui daftar grup rombongan bayar sesuai penyaring yang Anda pilih di atas.',
        icon: Icons.refresh_rounded,
      ),
      FeatureTourStep(
        targetKey: _resultAreaKey,
        title: 'Daftar Grup & Menu Aksi Rombongan',
        description:
            'Ketuk salah satu baris grup di tabel ini untuk membuka menu aksi: Kelola Anggota (tambah/hapus NOP warga), Ubah Info Grup, Cetak Surat Pengantar, atau Hapus Grup.',
        icon: Icons.touch_app_outlined,
        actionHint: 'Ketuk baris grup mana saja untuk mengelola anggotanya',
      ),
    ];
  }

  @override
  void dispose() {
    _tahun.dispose();
    _tglAwal.dispose();
    _tglAkhir.dispose();
    super.dispose();
  }

  Future<void> _muatOpsiForm() async {
    try {
      final options = await widget.client.fetchKolektifFormOptions();
      if (!mounted) return;
      setState(() => _formOptions = options);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _formOptions = KolektifFormOptions(
          errorMessage: 'Gagal membaca wilayah: $e',
        ),
      );
    }
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await widget.client.fetchKolektifGroups(
        bulan: _bulan,
        status: _status,
        tahun: _tahun.text.trim(),
        tglAwal: _tglAwal.text,
        tglAkhir: _tglAkhir.text,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _result = KolektifListResult(
          errorMessage: 'Gagal memuat daftar grup: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tambahGroup() async {
    final options = _formOptions;
    if (options == null ||
        options.errorMessage != null ||
        options.kelurahan.isEmpty ||
        !options.bisaTambah) {
      _tampilkanPesan(
        'Belum bisa menambah grup',
        options?.errorMessage ??
            'Halaman Pembayaran Kolektif di server tidak terbaca seperti biasanya, jadi tombol ini '
                'dimatikan supaya tidak ada perintah yang salah terkirim. Coba buka ulang menu ini; '
                'kalau masih sama, kemungkinan halaman di servernya berubah.',
      );
      return;
    }

    final isian = await showDialog<IsianGroupBaru>(
      context: context,
      builder: (_) => TambahGroupDialog(options: options),
    );
    if (isian == null || !mounted) return;

    final kelurahan = options.kelurahan.firstWhere(
      (k) => k.code == isian.kelurahanCode,
    );
    final lanjut = await _konfirmasi(
      judul: 'Buat grup ini sekarang?',
      peringatan:
          'Grup akan dibuat di sistem resmi Bapenda dan tercatat permanen di sana.',
      rincian: {
        'Nama Group': isian.namaGroup,
        'Keterangan': isian.keterangan,
        'Kolektor': isian.namaKolektor,
        'No HP Kolektor': isian.noHpKolektor,
        'Kecamatan': options.kecamatanName.isEmpty
            ? options.kecamatanCode
            : '${options.kecamatanName} (${options.kecamatanCode})',
        'Kelurahan':
            '${rapikanNamaWilayah(kelurahan.name)} (${kelurahan.code})',
      },
      labelAksi: 'Simpan',
      warnaAksi: null,
    );
    if (lanjut != true || !mounted) return;

    setState(() => _aksiBerjalan = true);
    KolektifActionResult hasil;
    try {
      hasil = await widget.client.createKolektifGroup(
        namaGroup: isian.namaGroup,
        keterangan: isian.keterangan,
        namaKolektor: isian.namaKolektor,
        noHpKolektor: isian.noHpKolektor,
        kecamatanCode: options.kecamatanCode,
        kelurahanCode: isian.kelurahanCode,
      );
    } catch (e) {
      // Request sudah telanjur dikirim — tidak boleh dilaporkan sebagai
      // "gagal" begitu saja, karena bisa jadi server sudah membuat grupnya
      // dan yang putus cuma jawabannya.
      hasil = KolektifActionResult(
        success: false,
        message:
            'Koneksi terputus saat menunggu jawaban sistem, jadi hasilnya belum pasti. '
            'Periksa dulu daftar grup di bawah sebelum mencoba lagi.\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }

    if (!mounted) return;
    if (hasil.success) {
      _tampilkanSnack('Grup "${isian.namaGroup}" berhasil dibuat.');
    } else {
      _tampilkanPesan(
        'Grup tidak jadi dibuat',
        hasil.message ?? 'Permintaan ditolak tanpa keterangan.',
      );
    }
    await _muat();
  }

  /// Aksi per-grup dikumpulkan di sini, bukan sebagai ikon di kolom "Aksi".
  /// Tabelnya lebar dan harus digeser mendatar, sehingga kolom paling kiri
  /// gampang hilang dari layar — ikon aksinya jadi tidak pernah terlihat.
  /// Dengan barisnya sendiri yang bisa diketuk, aksi selalu terjangkau berapa
  /// pun posisi geseran tabelnya.
  void _aksiGrup(KolektifGroup group) {
    if (group.id.isEmpty) {
      _tampilkanPesan(
        'Grup ini tidak bisa dibuka',
        'Nomor grup tidak terbaca dari daftar, jadi tidak ada aksi yang bisa dijalankan untuk baris ini.',
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                group.namaGroup,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${rapikanNamaWilayah(group.kelurahan)} · ${group.status} · ${group.anggota} anggota',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Kelola Anggota'),
              subtitle: Text(
                group.statusCode == '0'
                    ? 'Tambah atau keluarkan NOP warga dari grup ini'
                    : 'Hanya bisa dilihat — grup tidak berstatus Draft',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KelolaAnggotaScreen(
                      client: widget.client,
                      group: group,
                    ),
                  ),
                ).then((_) => _muat());
              },
            ),
            if (group.canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Ubah Info Grup'),
                subtitle: const Text(
                  'Ubah nama grup, keterangan, nama kolektor, atau nomor HP',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _ubahGroup(group);
                },
              ),
            if (group.canPrintSurat)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Cetak Surat Pengantar'),
                subtitle: const Text(
                  'Buka dokumen surat pengantar resmi untuk grup ini',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _cetakSuratPengantar(group);
                },
              ),
            if (group.canDelete)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Hapus Grup',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Hapus grup rombongan ini beserta catatan alasannya',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _hapusGroup(group);
                },
              )
            else
              const ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.grey),
                title: Text('Hapus Grup', style: TextStyle(color: Colors.grey)),
                subtitle: Text(
                  'Tidak tersedia — grup sudah dikunci, dibayar, atau tidak boleh dihapus',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _ubahGroup(KolektifGroup group) async {
    final options = _formOptions;
    if (options == null ||
        options.errorMessage != null ||
        !options.bisaTambah) {
      _tampilkanPesan(
        'Belum bisa mengubah grup',
        options?.errorMessage ??
            'Halaman Pembayaran Kolektif sedang tidak terbaca seperti biasanya, jadi aksi ini '
                'dimatikan sementara. Coba buka ulang menu ini.',
      );
      return;
    }

    final isian = await showDialog<IsianGroupBaru>(
      context: context,
      builder: (_) => TambahGroupDialog(options: options, groupDiubah: group),
    );
    if (isian == null || !mounted) return;

    final lanjut = await _konfirmasi(
      judul: 'Simpan perubahan grup?',
      peringatan:
          'Data grup di sistem Bapenda akan diganti dengan isian di bawah.',
      rincian: {
        'Nama Group': isian.namaGroup,
        'Keterangan': isian.keterangan,
        'Kolektor': isian.namaKolektor,
        'No HP Kolektor': isian.noHpKolektor,
      },
      labelAksi: 'Simpan',
      warnaAksi: null,
    );
    if (lanjut != true || !mounted) return;

    setState(() => _aksiBerjalan = true);
    KolektifActionResult hasil;
    try {
      hasil = await widget.client.updateKolektifGroup(
        editGroupId: group.id,
        namaGroup: isian.namaGroup,
        keterangan: isian.keterangan,
        namaKolektor: isian.namaKolektor,
        noHpKolektor: isian.noHpKolektor,
        kecamatanCode: options.kecamatanCode,
        kelurahanCode: isian.kelurahanCode,
      );
    } catch (e) {
      hasil = KolektifActionResult(
        success: false,
        message:
            'Koneksi terputus saat menunggu jawaban sistem, jadi hasilnya belum pasti. '
            'Periksa dulu daftar grup di bawah sebelum mencoba lagi.\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }

    if (!mounted) return;
    if (hasil.success) {
      _tampilkanSnack('Perubahan grup "${isian.namaGroup}" tersimpan.');
    } else {
      _tampilkanPesan(
        'Perubahan tidak tersimpan',
        hasil.message ?? 'Permintaan ditolak tanpa keterangan.',
      );
    }
    await _muat();
  }

  Future<void> _cetakSuratPengantar(KolektifGroup group) async {
    setState(() => _aksiBerjalan = true);
    try {
      final bytes = await widget.client.fetchSuratPengantarPdf(group.id);
      if (!mounted) return;
      await DocumentPreviewScreen.printOrPreview(
        context,
        pdfBytes: bytes,
        fileName: 'Surat Pengantar ${group.namaGroup}.pdf',
      );
    } on StateError catch (e) {
      if (!mounted) return;
      _tampilkanPesan('Surat pengantar tidak bisa dibuka', e.message);
    } catch (e) {
      if (!mounted) return;
      _tampilkanPesan(
        'Surat pengantar tidak bisa dibuka',
        'Gagal mengambil dokumen surat pengantar:\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }
  }

  Future<void> _hapusGroup(KolektifGroup group) async {
    if (_formOptions?.bisaHapus != true) {
      _tampilkanPesan(
        'Belum bisa menghapus grup',
        'Halaman Pembayaran Kolektif sedang tidak terbaca seperti biasanya, jadi aksi hapus '
            'dimatikan sementara. Coba buka ulang menu ini.',
      );
      return;
    }

    final alasan = await showDialog<String>(
      context: context,
      builder: (_) => HapusGroupDialog(namaGroup: group.namaGroup),
    );
    if (alasan == null || !mounted) return;

    final lanjut = await _konfirmasi(
      judul: 'Hapus grup ini sekarang?',
      peringatan:
          'Penghapusan tidak bisa dibatalkan. Nama grup, alasan penghapusan, dan nama akun Anda '
          'akan tercatat di riwayat penghapusan sistem Bapenda.',
      rincian: {
        'Nama Group': group.namaGroup,
        'Kolektor': group.namaKolektor,
        'Anggota': group.anggota,
        'Status': _labelStatus(group.statusCode),
        'Alasan': alasan,
      },
      labelAksi: 'Hapus Grup',
      warnaAksi: Theme.of(context).colorScheme.error,
    );
    if (lanjut != true || !mounted) return;

    setState(() => _aksiBerjalan = true);
    KolektifActionResult hasil;
    try {
      hasil = await widget.client.deleteKolektifGroup(
        groupId: group.id,
        alasan: alasan,
      );
    } catch (e) {
      hasil = KolektifActionResult(
        success: false,
        message:
            'Koneksi terputus saat menunggu jawaban sistem, jadi hasilnya belum pasti. '
            'Periksa dulu daftar grup di bawah sebelum mencoba lagi.\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }

    if (!mounted) return;
    if (hasil.success) {
      _tampilkanSnack('Grup "${group.namaGroup}" berhasil dihapus.');
    } else {
      _tampilkanPesan(
        'Grup tidak jadi dihapus',
        hasil.message ?? 'Permintaan ditolak tanpa keterangan.',
      );
    }
    await _muat();
  }

  Future<bool?> _konfirmasi({
    required String judul,
    required String peringatan,
    required Map<String, String> rincian,
    required String labelAksi,
    required Color? warnaAksi,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(judul),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                peringatan,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              for (final entry in rincian.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 116,
                        child: Text(
                          entry.key,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Text(entry.value.isEmpty ? '-' : entry.value),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: warnaAksi == null
                ? null
                : FilledButton.styleFrom(backgroundColor: warnaAksi),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(labelAksi),
          ),
        ],
      ),
    );
  }

  void _tampilkanSnack(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  void _tampilkanPesan(String judul, String isi) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(judul),
        content: SingleChildScrollView(child: Text(isi)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opsi = _formOptions;
    final opsiSiap =
        opsi != null &&
        opsi.errorMessage == null &&
        opsi.kelurahan.isNotEmpty &&
        opsi.bisaTambah;
    final sibuk = _loading || _aksiBerjalan;
    final peringatanToken =
        (opsi != null && opsi.errorMessage == null && !opsi.bisaTambah)
        ? 'Aksi tambah/hapus dimatikan sementara: tampilan halaman sedang tidak '
              'terbaca seperti biasanya. Daftar grup di bawah tetap bisa dilihat.'
        : null;

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: onPrimary,
        title: const Text('Pembayaran Kolektif'),
        actions: [
          FeatureTourHelpButton(
            onPressed: showTour,
            color: onPrimary,
            tooltip: 'Panduan Pembayaran Kolektif',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SettingsScreen(themeController: widget.themeController),
              ),
            ),
            icon: const Icon(Icons.settings),
            tooltip: 'Pengaturan',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ResponsivePageContainer(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Kelola daftar grup pembayaran rombongan (kolektif). Anda dapat membuat grup baru, '
                          'mengatur daftar anggota (tambah/keluarkan NOP warga) selama grup berstatus Draft, '
                          'mencetak surat pengantar, atau mengunci daftar grup dari menu Kelola Anggota.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 14),
                        WilayahBadge(client: widget.client),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          key: _tambahGroupButtonKey,
                          onPressed: sibuk || !opsiSiap ? null : _tambahGroup,
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Buat Grup Rombongan Baru'),
                        ),
                        if (opsi?.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: AppAlertBanner(
                              message: opsi!.errorMessage!,
                              tone: AppBadgeTone.error,
                            ),
                          )
                        else if (peringatanToken != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: AppAlertBanner(
                              message: peringatanToken,
                              tone: AppBadgeTone.warning,
                            ),
                          ),
                        const Divider(height: 28),
                        Column(
                          key: _filterAreaKey,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _bulan,
                                    decoration: const InputDecoration(
                                      labelText: 'Bulan',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final o in _bulanOptions)
                                        DropdownMenuItem(
                                          value: o.$1,
                                          child: Text(o.$2),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _bulan = v ?? '0'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _status,
                                    decoration: const InputDecoration(
                                      labelText: 'Status',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final o in _statusOptions)
                                        DropdownMenuItem(
                                          value: o.$1,
                                          child: Text(o.$2),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _status = v ?? ''),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _tahun,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              decoration: const InputDecoration(
                                labelText: 'Tahun (opsional)',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: MonitoringDateField(
                                    label: 'Tanggal Awal',
                                    controller: _tglAwal,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: MonitoringDateField(
                                    label: 'Tanggal Akhir',
                                    controller: _tglAkhir,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: _tampilkanButtonKey,
                          onPressed: sibuk ? null : _muat,
                          icon: _loading
                              ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: onPrimary,
                                  ),
                                )
                              : const Icon(Icons.search),
                          label: const Text('Tampilkan'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  key: _resultAreaKey,
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (_result != null
                            ? KolektifResultView(
                                result: _result!,
                                onAksi: _aksiBerjalan ? null : _aksiGrup,
                              )
                            : const SizedBox.shrink()),
                ),
                if (_aksiBerjalan)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
