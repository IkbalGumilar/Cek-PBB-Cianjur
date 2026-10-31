import 'package:flutter/material.dart';

import 'document_preview_screen.dart';
import 'kelola_anggota_screen.dart';
import 'monitoring/monitoring_form_fields.dart';
import 'settings_screen.dart';
import 'staff_portal/kolektif_group_dialogs.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';

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
    ('99', 'Expired'),
  ];

  static String _labelStatus(String code) => switch (code) {
    '0' => 'Draft',
    '1' => 'Siap Dibayar',
    '2' => 'Sudah Di Bayar',
    '99' => 'Expired',
    _ => code.isEmpty ? '-' : code,
  };

  @override
  void initState() {
    super.initState();
    _muat();
    _muatOpsiForm();
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
          'Grup akan dibuat di server pemda dan tercatat permanen di sana.',
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
            'Koneksi terputus saat menunggu jawaban server, jadi hasilnya belum pasti. '
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
        hasil.message ?? 'Server menolak tanpa keterangan.',
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
        'ID grup tidak terbaca dari daftar, jadi tidak ada aksi yang bisa dijalankan untuk baris ini.',
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
                    ? 'Tambah atau keluarkan NOP dari grup ini'
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
                title: const Text('Ubah Group'),
                subtitle: const Text(
                  'Ubah nama, keterangan, kolektor, atau no HP',
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
                subtitle: const Text('Buka dokumen resmi grup ini dari server'),
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
                  'Hapus Group',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: const Text(
                  'Tercatat permanen di Log History Penghapusan',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _hapusGroup(group);
                },
              )
            else
              const ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.grey),
                title: Text(
                  'Hapus Group',
                  style: TextStyle(color: Colors.grey),
                ),
                subtitle: Text(
                  'Tidak tersedia — grup sudah difinalkan, dibayar, atau tidak boleh dihapus',
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
            'Halaman Pembayaran Kolektif di server tidak terbaca seperti biasanya, jadi aksi ini '
                'dimatikan supaya tidak ada perintah yang salah terkirim. Coba buka ulang menu ini.',
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
          'Data grup di server pemda akan diganti dengan isian di bawah.',
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
            'Koneksi terputus saat menunggu jawaban server, jadi hasilnya belum pasti. '
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
        hasil.message ?? 'Server menolak tanpa keterangan.',
      );
    }
    await _muat();
  }

  Future<void> _cetakSuratPengantar(KolektifGroup group) async {
    setState(() => _aksiBerjalan = true);
    try {
      final bytes = await widget.client.fetchSuratPengantarPdf(group.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: bytes,
            fileName: 'Surat Pengantar ${group.namaGroup}.pdf',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      _tampilkanPesan('Surat pengantar tidak bisa dibuka', e.message);
    } catch (e) {
      if (!mounted) return;
      _tampilkanPesan(
        'Surat pengantar tidak bisa dibuka',
        'Gagal mengambil dokumen dari server:\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }
  }

  Future<void> _hapusGroup(KolektifGroup group) async {
    if (_formOptions?.bisaHapus != true) {
      _tampilkanPesan(
        'Belum bisa menghapus grup',
        'Halaman Pembayaran Kolektif di server tidak terbaca seperti biasanya, jadi aksi hapus '
            'dimatikan supaya tidak ada perintah yang salah terkirim. Coba buka ulang menu ini.',
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
          'Penghapusan tidak bisa dibatalkan. Grup, alasan di bawah, dan nama akun Anda '
          'akan tercatat permanen di Log History Penghapusan milik pemda.',
      rincian: {
        'Nama Group': group.namaGroup,
        'Kolektor': group.namaKolektor,
        'Anggota': group.anggota,
        'Status': _labelStatus(group.statusCode),
        'Alasan': alasan,
      },
      labelAksi: 'Hapus Group',
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
            'Koneksi terputus saat menunggu jawaban server, jadi hasilnya belum pasti. '
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
        hasil.message ?? 'Server menolak tanpa keterangan.',
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
        ? 'Aksi tambah/hapus dimatikan: struktur halaman Pembayaran Kolektif di server tidak '
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Daftar grup pembayaran kolektif. Bisa tambah grup, kelola anggota (tambah/keluarkan '
                'NOP) pada grup Draft, hapus grup, serta Finalkan dari layar Kelola Anggota. '
                'Generate VA belum tersedia karena menerbitkan kode bayar sungguhan.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              const WilayahBadge(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: sibuk || !opsiSiap ? null : _tambahGroup,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Tambah Group'),
              ),
              if (opsi?.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    opsi!.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else if (peringatanToken != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    peringatanToken,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const SizedBox(height: 16),
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
                          DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                      ],
                      onChanged: (v) => setState(() => _bulan = v ?? '0'),
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
                          DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? ''),
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
              const SizedBox(height: 16),
              FilledButton(
                onPressed: sibuk ? null : _muat,
                child: _loading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onPrimary,
                        ),
                      )
                    : const Text('Tampilkan'),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_result != null)
                KolektifResultView(
                  result: _result!,
                  onAksi: _aksiBerjalan ? null : _aksiGrup,
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
    );
  }
}
