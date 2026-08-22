import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_header.dart';
import 'kolektif_nop_berkas.dart';
import 'staff_portal_client.dart';

/// Layar "Unggah Berkas NOP" untuk satu grup kolektif.
///
/// Alurnya sengaja dibuat dua tahap — **pratinjau dulu, kirim belakangan** —
/// karena berkas dari luar tidak bisa dipercaya begitu saja: kolomnya bisa
/// salah tebak, NOP-nya bisa singkatan yang awalannya dilengkapi aplikasi, dan
/// Excel bisa sudah merusak digit belakang NOP sebelum berkasnya sampai ke
/// sini. Semua itu ditampilkan lebih dulu dalam bentuk NOP 18 angka yang
/// benar-benar akan dikirim.
///
/// Pengirimannya satu NOP satu permintaan (lihat
/// [StaffPortalClient.addKolektifMembersFromList]) supaya nasib tiap NOP bisa
/// dilaporkan terpisah.
class KolektifImportScreen extends StatefulWidget {
  final StaffPortalClient client;
  final KolektifGroup group;
  final String tahunPajak;
  final String buku;
  final String namaBuku;
  final String namaBerkas;
  final Uint8List bytes;

  /// NOP yang sudah jadi anggota grup untuk tahun pajak ini — dipakai untuk
  /// melewati NOP yang tidak perlu dikirim ulang.
  final Set<String> sudahAda;

  const KolektifImportScreen({
    super.key,
    required this.client,
    required this.group,
    required this.tahunPajak,
    required this.buku,
    required this.namaBuku,
    required this.namaBerkas,
    required this.bytes,
    required this.sudahAda,
  });

  @override
  State<KolektifImportScreen> createState() => _KolektifImportScreenState();
}

class _KolektifImportScreenState extends State<KolektifImportScreen> {
  static const _pratinjauAwal = 15;

  BacaanBerkasNop? _bacaan;
  int? _kolomPilihan;
  bool _memuat = true;
  int _tampil = _pratinjauAwal;

  var _siapKirim = <BarisBerkasNop>[];
  var _ganda = <BarisBerkasNop>[];
  var _sudahAda = <BarisBerkasNop>[];

  bool _mengirim = false;
  bool _batal = false;
  final _progres = ValueNotifier<int>(0);
  HasilImporNop? _hasil;

  @override
  void initState() {
    super.initState();
    Future.microtask(_uraikan);
  }

  @override
  void dispose() {
    // Kalau layarnya ditinggalkan saat pengiriman masih jalan, hentikan
    // batch-nya — meneruskan berarti tetap menembaki server pemda untuk layar
    // yang sudah tidak ada, dan laporan hasilnya tidak akan pernah terlihat.
    _batal = true;
    _progres.dispose();
    super.dispose();
  }

  void _uraikan() {
    final bacaan = bacaBerkasNop(
      namaBerkas: widget.namaBerkas,
      bytes: widget.bytes,
      kelurahanCode: widget.group.kelurahanCode,
      kolomPaksa: _kolomPilihan,
    );

    // Satu NOP hanya perlu dikirim sekali. Yang kembar di dalam berkas dan yang
    // sudah jadi anggota disingkirkan DI SINI, bukan dibiarkan ditolak server —
    // tiap permintaan yang tidak perlu adalah beban tambahan untuk server pemda
    // dan waktu tunggu tambahan untuk penggunanya.
    final terlihat = <String>{};
    final siap = <BarisBerkasNop>[];
    final ganda = <BarisBerkasNop>[];
    final sudahAda = <BarisBerkasNop>[];
    for (final b in bacaan.terbaca) {
      if (!terlihat.add(b.nop!)) {
        ganda.add(b);
      } else if (widget.sudahAda.contains(b.nop)) {
        sudahAda.add(b);
      } else {
        siap.add(b);
      }
    }

    if (!mounted) return;
    setState(() {
      _bacaan = bacaan;
      _kolomPilihan = bacaan.kolomNop >= 0 ? bacaan.kolomNop : null;
      _siapKirim = siap;
      _ganda = ganda;
      _sudahAda = sudahAda;
      _tampil = _pratinjauAwal;
      _memuat = false;
    });
  }

  String get _perkiraanWaktu {
    // Kira-kira satu detik per NOP: sekitar 250 ms jeda antar permintaan
    // ditambah waktu tunggu jawaban server.
    final detik = _siapKirim.length;
    if (detik < 60) return 'sekitar $detik detik';
    return 'sekitar ${(detik / 60).ceil()} menit';
  }

  Future<void> _kirim() async {
    final adaSingkatan = _siapKirim.any((b) => b.dariSingkatan);
    final lanjut = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Kirim ${_siapKirim.length} NOP?'),
        content: SingleChildScrollView(
          child: Text(
            '${_siapKirim.length} NOP dari "${widget.namaBerkas}" akan dicari di server lalu '
            'dimasukkan ke grup "${widget.group.namaGroup}" untuk tahun pajak ${widget.tahunPajak}, '
            '${widget.namaBuku}.\n\n'
            'Yang belum bayar akan masuk. Yang sudah bayar dan yang tidak ditemukan tidak akan masuk — '
            'daftarnya dilaporkan setelah selesai.\n\n'
            'Dikirim satu per satu, perkiraan $_perkiraanWaktu. Bisa dihentikan di tengah jalan; '
            'yang sudah masuk tetap bisa dihapus lagi selama grup masih Draft.'
            '${adaSingkatan ? '\n\nCatatan: sebagian NOP berasal dari singkatan, jadi awalan wilayahnya '
                'dilengkapi dari kelurahan grup ini. Pastikan daftarnya sudah benar.' : ''}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;

    setState(() {
      _mengirim = true;
      _batal = false;
      _hasil = null;
    });
    _progres.value = 0;
    _tampilkanProgres();

    HasilImporNop hasil;
    try {
      hasil = await widget.client.addKolektifMembersFromList(
        groupId: widget.group.id,
        nopList: [for (final b in _siapKirim) b.nop!],
        tahunPajak: widget.tahunPajak,
        buku: widget.buku,
        kelurahanCode: widget.group.kelurahanCode,
        // Dijaga `mounted`: notifier-nya sudah dilepas kalau layarnya
        // ditinggalkan, dan menulis ke notifier yang sudah dilepas melempar
        // kesalahan yang akan menutupi hasil pengiriman sebenarnya.
        onProgress: (selesai, _) {
          if (mounted) _progres.value = selesai;
        },
        batal: () => _batal,
      );
    } on Exception catch (e) {
      hasil = HasilImporNop(
        errorFatal: 'Pengiriman berhenti karena kesalahan tak terduga, jadi hasilnya belum pasti. '
            'Periksa dulu daftar anggota sebelum mengulang.\n\n$e',
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // tutup dialog progres
    setState(() {
      _mengirim = false;
      _hasil = hasil;
    });
    await _tampilkanNotifBerurutan(hasil);
  }

  void _tampilkanProgres() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Tombol kembali sistem dimatikan supaya dialog ini hanya bisa ditutup
      // oleh [_kirim] setelah pengiriman benar-benar selesai. Kalau tidak,
      // penutupan dari luar membuat `Navigator.pop` di [_kirim] menutup layar
      // ini alih-alih dialognya.
      builder: (ctx) => PopScope(
        canPop: false,
        // StatefulBuilder-nya perlu: isi dialog dibangun oleh route-nya sendiri,
        // jadi setState milik layar ini tidak akan menyegarkannya.
        child: StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('Mengirim NOP'),
            content: ValueListenableBuilder<int>(
              valueListenable: _progres,
              builder: (_, nilai, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _siapKirim.isEmpty ? null : nilai / _siapKirim.length,
                  ),
                  const SizedBox(height: 12),
                  Text('$nilai dari ${_siapKirim.length} NOP'),
                  if (_batal)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Menghentikan setelah NOP yang sedang berjalan selesai…'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _batal ? null : () => setDialog(() => _batal = true),
                child: const Text('Hentikan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tampilkan hasilnya SATU PER SATU, bukan digabung jadi satu pesan panjang.
  /// Tiap golongan punya tindak lanjut yang berbeda — yang sudah bayar memang
  /// tidak perlu diapa-apakan, sedangkan yang tidak ditemukan biasanya berarti
  /// NOP-nya salah tulis dan perlu dibetulkan — jadi menggabungnya justru
  /// membuat yang perlu ditindaklanjuti tenggelam.
  Future<void> _tampilkanNotifBerurutan(HasilImporNop hasil) async {
    final tahap = <({String judul, String keterangan, List<String> nop, Color? warna})>[
      (
        judul: 'Ditambahkan',
        keterangan: 'NOP berikut ketemu, tagihannya belum bayar, dan sudah masuk jadi anggota grup '
            '"${widget.group.namaGroup}".',
        nop: [for (final i in hasil.ditambahkan) i.nop],
        warna: Colors.green.shade700,
      ),
      (
        judul: 'Sudah Bayar — Tidak Dimasukkan',
        keterangan: 'NOP berikut ketemu, tapi tagihan tahun ${widget.tahunPajak} sudah lunas, '
            'jadi tidak dimasukkan ke grup.',
        nop: [for (final i in hasil.sudahBayar) i.nop],
        warna: null,
      ),
      (
        judul: 'Tidak Ditemukan — Tidak Dimasukkan',
        keterangan: 'NOP berikut tidak ada di data server untuk tahun ${widget.tahunPajak}, '
            'jadi tidak dimasukkan. Biasanya karena salah tulis atau salah kelurahan.',
        nop: [for (final i in hasil.tidakDitemukan) i.nop],
        warna: null,
      ),
      if (hasil.perluDiperiksa.isNotEmpty)
        (
          judul: 'Perlu Diperiksa',
          keterangan: 'Server menjawab hal lain untuk NOP berikut. Jawabannya ditampilkan apa adanya '
              'supaya tidak salah tafsir — periksa daftar anggota untuk memastikan.',
          nop: [for (final i in hasil.perluDiperiksa) '${i.nop} — ${i.pesan ?? 'tanpa keterangan'}'],
          warna: Theme.of(context).colorScheme.error,
        ),
    ];

    for (var i = 0; i < tahap.length; i++) {
      if (!mounted) return;
      final t = tahap[i];
      final terakhir = i == tahap.length - 1;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${i + 1}/${tahap.length} · ${t.judul} (${t.nop.length})',
            style: t.warna == null ? null : TextStyle(color: t.warna),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.keterangan),
                  const SizedBox(height: 12),
                  if (t.nop.isEmpty)
                    const Text('Tidak ada.', style: TextStyle(color: Colors.grey))
                  else
                    SelectableText(t.nop.join('\n'), style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(terakhir ? 'Selesai' : 'Lanjut'),
            ),
          ],
        ),
      );
    }
  }

  String _ringkasan(HasilImporNop hasil) {
    final b = StringBuffer()
      ..writeln('Unggah NOP — ${widget.group.namaGroup}')
      ..writeln('Berkas: ${widget.namaBerkas}')
      ..writeln('Tahun pajak ${widget.tahunPajak} · ${widget.namaBuku}')
      ..writeln();
    void bagian(String judul, List<ItemImporNop> item, {bool pakaiPesan = false}) {
      b.writeln('$judul (${item.length}):');
      if (item.isEmpty) {
        b.writeln('  -');
      } else {
        for (final i in item) {
          b.writeln('  ${i.nop}${pakaiPesan ? ' — ${i.pesan ?? 'tanpa keterangan'}' : ''}');
        }
      }
      b.writeln();
    }

    bagian('Ditambahkan', hasil.ditambahkan);
    bagian('Sudah bayar', hasil.sudahBayar);
    bagian('Tidak ditemukan', hasil.tidakDitemukan);
    if (hasil.perluDiperiksa.isNotEmpty) {
      bagian('Perlu diperiksa', hasil.perluDiperiksa, pakaiPesan: true);
    }
    return b.toString();
  }

  Widget _kartuHasil(HasilImporNop hasil) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hasil Pengiriman', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _barisAngka('Ditambahkan', hasil.ditambahkan.length),
            _barisAngka('Sudah bayar', hasil.sudahBayar.length),
            _barisAngka('Tidak ditemukan', hasil.tidakDitemukan.length),
            if (hasil.perluDiperiksa.isNotEmpty) _barisAngka('Perlu diperiksa', hasil.perluDiperiksa.length),
            if (hasil.dibatalkan)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Dihentikan sebelum semua NOP terkirim.'),
              ),
            if (hasil.errorFatal != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  hasil.errorFatal!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: () => _tampilkanNotifBerurutan(hasil),
                icon: const Icon(Icons.replay),
                label: const Text('Lihat Lagi'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _ringkasan(hasil)));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Ringkasan disalin.')));
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Salin'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _barisAngka(String label, int nilai) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text('$nilai NOP')],
        ),
      );

  Widget _daftarLipat(String judul, List<BarisBerkasNop> baris, String keterangan) {
    if (baris.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text('$judul (${baris.length})'),
        subtitle: Text(keterangan, style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          SelectableText(
            [
              for (final b in baris)
                'Baris ${b.nomorBaris}: ${b.asli}'
                    '${b.nop != null ? ' → ${b.nop}' : ''}'
                    '${b.alasan != null ? ' (${b.alasan})' : ''}',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bacaan = _bacaan;
    final hasil = _hasil;
    final adaSingkatan = _siapKirim.any((b) => b.dariSingkatan);
    final tampil = _siapKirim.take(_tampil).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kHeaderGreen,
        foregroundColor: Colors.white,
        title: const Text('Unggah Berkas NOP'),
      ),
      body: SafeArea(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.namaBerkas, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.group.namaGroup} · Tahun ${widget.tahunPajak} · ${widget.namaBuku}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    for (final p in bacaan?.peringatan ?? const <String>[])
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(padding: const EdgeInsets.all(12), child: Text(p)),
                      ),

                    if (bacaan?.errorMessage != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(bacaan!.errorMessage!),
                        ),
                      ),

                    if ((bacaan?.namaKolom.length ?? 0) > 1) ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: _kolomPilihan,
                        decoration: const InputDecoration(
                          labelText: 'Kolom NOP',
                          helperText: 'Kalau kolom yang terpilih bukan kolom NOP, ganti di sini.',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var i = 0; i < bacaan!.namaKolom.length; i++)
                            DropdownMenuItem(value: i, child: Text(bacaan.namaKolom[i], overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: _mengirim
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _kolomPilihan = v;
                                  _memuat = true;
                                });
                                Future.microtask(_uraikan);
                              },
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (adaSingkatan)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Sebagian isi berkas berupa singkatan (5–7 angka), jadi awalan wilayahnya '
                            'dilengkapi dari kelurahan grup ini '
                            '(${rapikanNamaWilayah(widget.group.kelurahan)}). Periksa NOP 18 angka di '
                            'bawah — awalan yang keliru berarti NOP milik wajib pajak lain.',
                          ),
                        ),
                      ),

                    _daftarLipat(
                      'Sudah ada di grup — dilewati',
                      _sudahAda,
                      'Tidak dikirim ulang karena sudah jadi anggota tahun ${widget.tahunPajak}.',
                    ),
                    _daftarLipat('Ganda di dalam berkas — dilewati', _ganda, 'Hanya kemunculan pertama yang dikirim.'),
                    _daftarLipat(
                      'Tidak terbaca — dilewati',
                      bacaan?.tidakTerbaca ?? const [],
                      'Termasuk baris judul kolom, kalau ada.',
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Siap dikirim (${_siapKirim.length})',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (_siapKirim.length > _tampil)
                          TextButton(
                            onPressed: () => setState(() => _tampil = _siapKirim.length),
                            child: Text('Tampilkan Semua (${_siapKirim.length})'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_siapKirim.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Tidak ada NOP baru yang perlu dikirim dari berkas ini.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            [
                              for (final b in tampil)
                                '${b.nop}${b.dariSingkatan ? '   (dari ${b.asli})' : ''}',
                            ].join('\n'),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ),

                    if (_siapKirim.length > _tampil)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '…dan ${_siapKirim.length - _tampil} lagi.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),

                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _mengirim || _siapKirim.isEmpty ? null : _kirim,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        _siapKirim.isEmpty ? 'Tidak Ada yang Dikirim' : 'Cari & Tambah ${_siapKirim.length} NOP',
                      ),
                    ),

                    if (hasil != null) ...[
                      const SizedBox(height: 16),
                      _kartuHasil(hasil),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
