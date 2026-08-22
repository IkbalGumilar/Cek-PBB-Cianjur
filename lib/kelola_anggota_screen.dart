import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_header.dart';
import 'blok_record.dart' show formatRibuan;
import 'document_preview_screen.dart';
import 'download_helper.dart';
import 'kolektif_import_screen.dart';
import 'kolektif_nop_berkas.dart';
import 'monitoring/monitoring_result_exporter.dart';
import 'native_file_helper.dart';
import 'staff_portal_client.dart';
import 'tagihan_result.dart' show formatRupiah;

/// Layar "Kelola Anggota" satu grup kolektif — replika modal "Tambah NOP Pada
/// Group" di halaman asli, dengan tiga aksinya:
///
///  * **Tambah NOP** (`cariNOP()`) — memasukkan satu atau beberapa NOP.
///  * **Unggah Berkas** — daftar NOP dari CSV/Excel/teks, diuraikan di sisi
///    aplikasi lalu dikirim satu per satu lewat `cariNOP()` yang sama. Halaman
///    aslinya punya unggah CSV sendiri, tapi jalur itu tidak dipakai: lihat
///    [StaffPortalClient.addKolektifMembersFromList] untuk alasannya.
///  * **Hapus Data Terpilih** (`#btn-delete-all`) — mengeluarkan NOP dari grup.
///
/// Yang SENGAJA tidak dibawa ke sini:
///
///  * **Finalkan** — mengunci grup dan menerbitkan kode bayar sungguhan.
///  * **Generate VA** — sama, membuat nomor virtual account asli.
///  * Penambahan **MASSAL** (di halaman asli, mengosongkan kolom NOP lalu
///    menekan "Cari & Tambah ke Draft" akan memasukkan SELURUH NOP yang belum
///    bayar di satu kelurahan sekaligus). Aplikasi ini selalu mengirim NOP
///    yang tertulis, jadi jalur itu tertutup — termasuk lewat unggah berkas,
///    yang tidak pernah mengirim NOP kosong.
///
/// Berbeda dari buat/hapus grup, dua aksi di layar ini **bisa dibatalkan**
/// selama grup masih Draft: NOP yang salah tambah tinggal dihapus lagi, dan
/// tidak ada kode bayar yang terbit. Karena itu alurnya tidak dibuat
/// dua-langkah seperti di sana, cukup satu konfirmasi.
class KelolaAnggotaScreen extends StatefulWidget {
  final StaffPortalClient client;
  final KolektifGroup group;

  const KelolaAnggotaScreen({
    super.key,
    required this.client,
    required this.group,
  });

  @override
  State<KelolaAnggotaScreen> createState() => _KelolaAnggotaScreenState();
}

class _KelolaAnggotaScreenState extends State<KelolaAnggotaScreen> {
  static const _pageSize = 10;

  final _nop = TextEditingController();
  final _tahunPajak = TextEditingController(text: '${DateTime.now().year}');
  final _scroll = ScrollController();
  String _buku = '1';

  bool _loading = false;
  bool _aksiBerjalan = false;
  KolektifMemberListResult? _result;
  final _terpilih = <String>{};
  int _tampil = _pageSize;

  /// Grup yang sudah difinalkan / dibayar / kedaluwarsa tidak bisa diubah
  /// anggotanya — halaman aslinya menyembunyikan seluruh form-nya untuk
  /// status selain Draft, jadi di sini pun begitu.
  bool get _bisaDiubah => widget.group.statusCode == '0';

  static const _bukuOptions = [
    ('1', 'Buku 1'),
    ('12', 'Buku 1,2'),
    ('123', 'Buku 1,2,3'),
    ('2', 'Buku 2'),
    ('23', 'Buku 2,3'),
    ('3', 'Buku 3'),
  ];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _nop.dispose();
    _tahunPajak.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Buka seluruh daftar sekaligus lalu lompat ke paling bawah — dipakai untuk
  /// melihat total tanpa harus menekan "Muat 10 Data Lagi" berkali-kali.
  /// Lompatannya ditunda sampai bingkai berikutnya karena baris yang baru
  /// dibuka belum punya tinggi sebelum sempat digambar, jadi
  /// `maxScrollExtent`-nya belum mencerminkan daftar yang utuh.
  void _bukaSemuaLaluKeBawah(int jumlah) {
    setState(() => _tampil = jumlah);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  /// Daftar anggota dalam bentuk tabel generik, supaya bisa memakai
  /// pengekspor yang sudah dipakai tab-tab Monitoring Wilayah — termasuk baris
  /// "Total Keseluruhan" di kaki, jadi angka totalnya ikut terbawa ke berkas
  /// PDF/Excel/CSV, bukan cuma tampil di layar.
  MonitoringTableResult _sebagaiTabel(KolektifMemberListResult hasil) {
    return MonitoringTableResult(
      headers: const [
        'NOP',
        'Tahun Pajak',
        'Jatuh Tempo',
        'Nama WP',
        'Kecamatan',
        'Kelurahan',
        'Pokok',
        'Denda',
        'Total',
      ],
      rows: [
        for (final m in hasil.members)
          [
            m.nop,
            m.tahunPajak,
            m.jatuhTempo,
            m.namaWp,
            m.kecamatan,
            m.kelurahan,
            m.pokok,
            m.denda,
            m.total,
          ],
        [
          '',
          '',
          '',
          '',
          '',
          'Total Keseluruhan',
          formatRibuan(hasil.totalPokok),
          formatRibuan(hasil.totalDenda),
          formatRibuan(hasil.totalBayar),
        ],
      ],
    );
  }

  String get _judulBerkas => 'Anggota ${widget.group.namaGroup}';

  Future<MonitoringExportFormat?> _pilihFormat(String judul) {
    return showDialog<MonitoringExportFormat>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(judul),
        children: [
          for (final format in MonitoringExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, format),
              child: Text(format.label),
            ),
        ],
      ),
    );
  }

  Future<void> _unduh(KolektifMemberListResult hasil) async {
    final format = await _pilihFormat('Unduh Sebagai');
    if (format == null) return;
    setState(() => _aksiBerjalan = true);
    try {
      final bytes = await MonitoringResultExporter.build(
        format,
        _sebagaiTabel(hasil),
        _judulBerkas,
      );
      final namaBerkas = MonitoringResultExporter.fileName(
        format,
        _judulBerkas,
        prefix: 'anggota',
      );
      final lokasi = await DownloadHelper.saveBytes(bytes, namaBerkas);
      if (!mounted) return;
      _snack('Tersimpan di $lokasi');
    } catch (e) {
      if (!mounted) return;
      _snack('Gagal mengunduh: $e');
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }
  }

  Future<void> _bagikan(KolektifMemberListResult hasil) async {
    final format = await _pilihFormat('Bagikan Sebagai');
    if (format == null) return;
    setState(() => _aksiBerjalan = true);
    try {
      final bytes = await MonitoringResultExporter.build(
        format,
        _sebagaiTabel(hasil),
        _judulBerkas,
      );
      final namaBerkas = MonitoringResultExporter.fileName(
        format,
        _judulBerkas,
        prefix: 'anggota',
      );
      await NativeFileHelper.shareBytes(
        bytes: bytes,
        fileName: namaBerkas,
        mimeType: DownloadHelper.mimeTypeFor(namaBerkas),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Gagal membagikan: $e');
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }
  }

  Future<void> _cetak(KolektifMemberListResult hasil) async {
    setState(() => _aksiBerjalan = true);
    try {
      final bytes = await MonitoringResultExporter.build(
        MonitoringExportFormat.pdf,
        _sebagaiTabel(hasil),
        _judulBerkas,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            pdfBytes: bytes,
            fileName: '$_judulBerkas.pdf',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Gagal menyiapkan cetakan: $e');
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _result = null;
      _terpilih.clear();
      _tampil = _pageSize;
    });
    try {
      final result = await widget.client.fetchKolektifMembers(
        groupId: widget.group.id,
        status: widget.group.statusCode,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _result = KolektifMemberListResult(
          errorMessage: 'Gagal memuat daftar anggota: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Periksa tahun pajak; kembalikan pesan kesalahan kalau tidak wajar.
  /// Dipakai jalur ketik manual maupun jalur unggah berkas, karena keduanya
  /// mengirim tahun pajak yang sama ke server.
  String? _masalahTahun(String tahun) {
    if (tahun.length != 4) return 'Tahun pajak harus 4 angka.';
    final angka = int.tryParse(tahun);
    if (angka == null) return 'Tahun pajak harus berupa angka.';
    if (angka > DateTime.now().year) {
      return 'Tahun pajak tidak boleh lebih dari ${DateTime.now().year}.';
    }
    return null;
  }

  Future<void> _tambahNop() async {
    final nop = _nop.text.trim();
    final tahun = _tahunPajak.text.trim();
    if (nop.isEmpty) {
      _pesan(
        'NOP belum diisi',
        'Isi dulu NOP yang mau dimasukkan. Pakai koma (,) sebagai pemisah kalau lebih dari satu.',
      );
      return;
    }
    final terurai = uraikanNopKolektif(
      nop,
      kelurahanCode: widget.group.kelurahanCode,
    );
    if (terurai.error != null) {
      _pesan('NOP belum bisa dibaca', terurai.error!);
      return;
    }
    final masalahTahun = _masalahTahun(tahun);
    if (masalahTahun != null) {
      _pesan('Tahun pajak tidak wajar', masalahTahun);
      return;
    }

    final daftar = terurai.nop;
    // NOP hasil uraian ditampilkan lengkap 18 angka, bukan apa yang diketik —
    // supaya kalau singkatannya melebar jadi NOP milik orang lain, kelihatan
    // sebelum terkirim.
    final lanjut = await _konfirmasi(
      judul: 'Tambahkan ke grup?',
      isi:
          '${daftar.length} NOP akan dimasukkan ke grup "${widget.group.namaGroup}" '
          'untuk tahun pajak $tahun, ${_bukuOptions.firstWhere((b) => b.$1 == _buku).$2}.\n\n'
          '${daftar.join('\n')}',
      labelAksi: 'Tambahkan',
      warna: null,
    );
    if (lanjut != true || !mounted) return;

    setState(() => _aksiBerjalan = true);
    KolektifActionResult hasil;
    try {
      hasil = await widget.client.addKolektifMember(
        groupId: widget.group.id,
        nop: daftar.join(','),
        tahunPajak: tahun,
        buku: _buku,
        kelurahanCode: widget.group.kelurahanCode,
      );
    } catch (e) {
      hasil = KolektifActionResult(
        success: false,
        message:
            'Koneksi terputus saat menunggu jawaban server, jadi hasilnya belum pasti. '
            'Periksa dulu daftar anggota di bawah sebelum mencoba lagi.\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }

    if (!mounted) return;
    if (hasil.success) {
      _nop.clear();
      _snack(hasil.message ?? 'NOP berhasil ditambahkan.');
    } else {
      _pesan(
        'NOP tidak jadi ditambahkan',
        hasil.message ?? 'Server menolak tanpa keterangan.',
      );
    }
    await _muat();
  }

  /// Ambil berkas daftar NOP lalu buka layar pratinjaunya.
  ///
  /// Tahun pajak & buku diperiksa DI SINI, sebelum berkasnya dipilih, karena
  /// keduanya ikut terkirim untuk setiap NOP di berkas — salah tahun berarti
  /// salah tagihan untuk seluruh isi berkas sekaligus.
  Future<void> _unggahBerkas() async {
    final tahun = _tahunPajak.text.trim();
    final masalahTahun = _masalahTahun(tahun);
    if (masalahTahun != null) {
      _pesan(
        'Tahun pajak tidak wajar',
        '$masalahTahun\n\nBetulkan dulu sebelum memilih berkas — '
            'tahun ini dipakai untuk seluruh NOP di dalam berkas.',
      );
      return;
    }

    final List<PlatformFile> berkas;
    try {
      berkas = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx', 'xls', 'txt'],
      );
    } on Exception catch (e) {
      if (!mounted) return;
      _pesan('Gagal membuka berkas', 'Pemilih berkas tidak bisa dibuka: $e');
      return;
    }
    if (berkas.isEmpty || !mounted) return;

    setState(() => _aksiBerjalan = true);
    final Uint8List bytes;
    try {
      bytes = await berkas.first.readAsBytes();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _aksiBerjalan = false);
      _pesan(
        'Gagal membaca berkas',
        'Isi "${berkas.first.name}" tidak bisa dibaca: $e',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _aksiBerjalan = false);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KolektifImportScreen(
          client: widget.client,
          group: widget.group,
          tahunPajak: tahun,
          buku: _buku,
          namaBuku: _bukuOptions.firstWhere((b) => b.$1 == _buku).$2,
          namaBerkas: berkas.first.name,
          bytes: bytes,
          sudahAda: {
            for (final m in _result?.members ?? const <KolektifMember>[])
              if (m.tahunPajak == tahun) m.nop,
          },
        ),
      ),
    );
    // Selalu muat ulang setelah kembali — bahkan kalau pengirimannya dibatalkan
    // di tengah jalan, sebagian NOP bisa saja sudah masuk.
    if (mounted) await _muat();
  }

  Future<void> _hapusTerpilih() async {
    final members = (_result?.members ?? [])
        .where((m) => _terpilih.contains(m.kunci))
        .toList();
    if (members.isEmpty) {
      _pesan('Belum ada yang dipilih', 'Silakan pilih data terlebih dahulu.');
      return;
    }

    final lanjut = await _konfirmasi(
      judul: 'Hapus ${members.length} data terpilih?',
      isi:
          'NOP berikut akan dikeluarkan dari grup "${widget.group.namaGroup}". '
          'Selama grup masih Draft, NOP ini bisa dimasukkan lagi nanti.\n\n'
          '${members.map((m) => '${m.nop} (${m.tahunPajak})').join('\n')}',
      labelAksi: 'Hapus',
      warna: Theme.of(context).colorScheme.error,
    );
    if (lanjut != true || !mounted) return;

    setState(() => _aksiBerjalan = true);
    KolektifActionResult hasil;
    try {
      hasil = await widget.client.deleteKolektifMembers(members: members);
    } catch (e) {
      hasil = KolektifActionResult(
        success: false,
        message:
            'Koneksi terputus saat menunggu jawaban server, jadi hasilnya belum pasti. '
            'Periksa dulu daftar anggota di bawah sebelum mencoba lagi.\n\n$e',
      );
    } finally {
      if (mounted) setState(() => _aksiBerjalan = false);
    }

    if (!mounted) return;
    if (hasil.success) {
      _snack('${members.length} data dikeluarkan dari grup.');
    } else {
      _pesan(
        'Data tidak jadi dihapus',
        hasil.message ?? 'Server menolak tanpa keterangan.',
      );
    }
    await _muat();
  }

  Future<bool?> _konfirmasi({
    required String judul,
    required String isi,
    required String labelAksi,
    required Color? warna,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(judul),
        content: SingleChildScrollView(child: Text(isi)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: warna == null
                ? null
                : FilledButton.styleFrom(backgroundColor: warna),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(labelAksi),
          ),
        ],
      ),
    );
  }

  Widget _barisTotal(String label, int nilai, {bool tebal = false}) {
    final gaya = tebal
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: gaya),
          Text(formatRupiah(formatRibuan(nilai)), style: gaya),
        ],
      ),
    );
  }

  void _snack(String pesan) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(pesan)));

  void _pesan(String judul, String isi) {
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
    final members = _result?.members ?? const <KolektifMember>[];
    final tampil = members.take(_tampil).toList();
    final sibuk = _loading || _aksiBerjalan;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kHeaderGreen,
        foregroundColor: Colors.white,
        title: const Text('Kelola Anggota'),
      ),
      floatingActionButton: members.length > _pageSize
          ? FloatingActionButton.extended(
              onPressed: sibuk
                  ? null
                  : () => _bukaSemuaLaluKeBawah(members.length),
              icon: const Icon(Icons.vertical_align_bottom),
              label: const Text('Ke Bawah'),
              tooltip:
                  'Buka semua anggota lalu lompat ke total di paling bawah',
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.group.namaGroup,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${rapikanNamaWilayah(widget.group.kelurahan)} · ${widget.group.status}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (!_bisaDiubah)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Grup ini sudah tidak berstatus Draft, jadi anggotanya hanya bisa dilihat — '
                      'sama seperti di sistem aslinya.',
                    ),
                  ),
                )
              else ...[
                TextField(
                  controller: _nop,
                  keyboardType: TextInputType.number,
                  maxLines: 2,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'NOP',
                    helperText:
                        'NOP lengkap 18 angka, atau singkatan blok+nomor wilayah 5–7 angka '
                        '(contoh 17154 → blok 017 nomor 0154). Pisahkan dengan koma kalau lebih dari satu.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tahunPajak,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Tahun Pajak',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _buku,
                        decoration: const InputDecoration(
                          labelText: 'Buku',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final b in _bukuOptions)
                            DropdownMenuItem(value: b.$1, child: Text(b.$2)),
                        ],
                        onChanged: (v) => setState(() => _buku = v ?? '1'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: sibuk ? null : _tambahNop,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Cari & Tambah ke Draft'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: sibuk ? null : _unggahBerkas,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Unggah Berkas (CSV/Excel)'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Berkas dibaca dulu dan ditampilkan sebagai NOP 18 angka sebelum ada yang dikirim. '
                  'Tahun pajak & buku di atas dipakai untuk seluruh isi berkas.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      members.isEmpty
                          ? 'Anggota'
                          : 'Anggota (${members.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (members.isNotEmpty) ...[
                    IconButton(
                      onPressed: sibuk ? null : () => _unduh(_result!),
                      icon: const Icon(Icons.download_outlined),
                      tooltip: 'Unduh (PDF/Excel/CSV)',
                    ),
                    IconButton(
                      onPressed: sibuk ? null : () => _bagikan(_result!),
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Bagikan (PDF/Excel/CSV)',
                    ),
                    IconButton(
                      onPressed: sibuk ? null : () => _cetak(_result!),
                      icon: const Icon(Icons.print_outlined),
                      tooltip: 'Cetak',
                    ),
                  ],
                  IconButton(
                    onPressed: sibuk ? null : _muat,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Muat ulang',
                  ),
                ],
              ),
              if (_bisaDiubah && members.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: sibuk
                            ? null
                            : () => setState(() {
                                if (_terpilih.length == members.length) {
                                  _terpilih.clear();
                                } else {
                                  _terpilih
                                    ..clear()
                                    ..addAll(members.map((m) => m.kunci));
                                }
                              }),
                        child: Text(
                          _terpilih.length == members.length
                              ? 'Batal Pilih Semua'
                              : 'Pilih Semua Data',
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: sibuk || _terpilih.isEmpty
                            ? null
                            : _hapusTerpilih,
                        icon: const Icon(Icons.delete_outline),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        label: Text('Hapus (${_terpilih.length})'),
                      ),
                    ],
                  ),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_result?.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _result!.errorMessage!,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              else ...[
                for (final m in tampil)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: _bisaDiubah
                          ? Checkbox(
                              value: _terpilih.contains(m.kunci),
                              onChanged: sibuk
                                  ? null
                                  : (v) => setState(() {
                                      if (v == true) {
                                        _terpilih.add(m.kunci);
                                      } else {
                                        _terpilih.remove(m.kunci);
                                      }
                                    }),
                            )
                          : null,
                      title: Text(
                        m.nop,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      subtitle: Text(
                        '${m.namaWp}\nTahun ${m.tahunPajak} · Jatuh tempo ${m.jatuhTempo}\n'
                        'Pokok ${m.pokok} · Denda ${m.denda} · Total ${m.total}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                if (_tampil < members.length) ...[
                  OutlinedButton(
                    onPressed: () => setState(() => _tampil += _pageSize),
                    child: Text(
                      'Muat $_pageSize Data Lagi (${members.length - _tampil} tersisa)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _bukaSemuaLaluKeBawah(members.length),
                    icon: const Icon(Icons.vertical_align_bottom),
                    label: Text('Buka Semua (${members.length}) & Lihat Total'),
                  ),
                ],
                // Total keseluruhan selalu ditampilkan dari SEMUA anggota,
                // bukan cuma yang sedang terlihat — jumlah yang berubah-ubah
                // mengikuti banyaknya baris yang terbuka justru menyesatkan.
                if (members.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(top: 8, bottom: 72),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Keseluruhan (${members.length} NOP)',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          _barisTotal('Pokok', _result!.totalPokok),
                          _barisTotal('Denda', _result!.totalDenda),
                          const Divider(),
                          _barisTotal(
                            'Total Bayar',
                            _result!.totalBayar,
                            tebal: true,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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
