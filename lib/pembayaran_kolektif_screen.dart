import 'package:flutter/material.dart';

import 'app_header.dart';
import 'monitoring/monitoring_form_fields.dart';
import 'settings_screen.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';

/// Menu "Pembayaran Kolektif" — versi read-only: daftar & filter grup
/// kolektif, meniru tabel & filter yang tampil di halaman asli
/// (`m179`/reloadDataGroup). BELUM ada Tambah/Ubah/Hapus Group, Kelola
/// Member (tambah/hapus NOP, upload CSV), Finalkan, atau Generate VA —
/// semua itu mengubah data pembayaran asli di server pemda (finalisasi
/// & generate VA menciptakan kode bayar sungguhan, hapus group tercatat
/// permanen di log), jadi sengaja belum dibuat sampai ada konfirmasi lebih
/// lanjut. Lihat catatan ketidakpastian di [StaffPortalClient.fetchKolektifGroups]
/// — modul ini pakai DataTables server-side yang parameternya direplikasi
/// manual tanpa contoh respons asli.
class PembayaranKolektifScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController themeController;

  const PembayaranKolektifScreen({super.key, required this.client, required this.themeController});

  @override
  State<PembayaranKolektifScreen> createState() => _PembayaranKolektifScreenState();
}

class _PembayaranKolektifScreenState extends State<PembayaranKolektifScreen> {
  String _bulan = '0';
  String _status = '';
  final _tahun = TextEditingController();
  final _tglAwal = TextEditingController();
  final _tglAkhir = TextEditingController();

  bool _loading = false;
  KolektifListResult? _result;

  static const _bulanOptions = [
    ('0', 'Semua'), ('1', 'Januari'), ('2', 'Februari'), ('3', 'Maret'), ('4', 'April'),
    ('5', 'Mei'), ('6', 'Juni'), ('7', 'Juli'), ('8', 'Agustus'), ('9', 'September'),
    ('10', 'Oktober'), ('11', 'November'), ('12', 'Desember'),
  ];
  static const _statusOptions = [
    ('', 'Semua'), ('0', 'Draft'), ('1', 'Siap Dibayar'), ('2', 'Sudah Di Bayar'), ('99', 'Expired'),
  ];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _tahun.dispose();
    _tglAwal.dispose();
    _tglAkhir.dispose();
    super.dispose();
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
      setState(() => _result = KolektifListResult(errorMessage: 'Gagal memuat daftar grup: $e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kHeaderGreen,
        foregroundColor: Colors.white,
        title: const Text('Pembayaran Kolektif'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(themeController: widget.themeController)),
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
                'Daftar grup pembayaran kolektif — read only. Belum bisa tambah/ubah/hapus grup atau kelola anggota dari sini.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              const WilayahBadge(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _bulan,
                    decoration: const InputDecoration(labelText: 'Bulan', border: OutlineInputBorder()),
                    items: [for (final o in _bulanOptions) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
                    onChanged: (v) => setState(() => _bulan = v ?? '0'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                    items: [for (final o in _statusOptions) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
                    onChanged: (v) => setState(() => _status = v ?? ''),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _tahun,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(labelText: 'Tahun (opsional)', border: OutlineInputBorder(), counterText: ''),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: MonitoringDateField(label: 'Tanggal Awal', controller: _tglAwal)),
                const SizedBox(width: 8),
                Expanded(child: MonitoringDateField(label: 'Tanggal Akhir', controller: _tglAkhir)),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _muat,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Tampilkan'),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
              else if (_result != null)
                _KolektifResultView(result: _result!),
            ],
          ),
        ),
      ),
    );
  }
}

class _KolektifResultView extends StatelessWidget {
  final KolektifListResult result;
  const _KolektifResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.errorMessage != null) {
      return Text(result.errorMessage!, style: const TextStyle(color: Colors.red));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Nama Group')),
          DataColumn(label: Text('Nama Kolektor')),
          DataColumn(label: Text('HP Kolektor')),
          DataColumn(label: Text('Anggota')),
          DataColumn(label: Text('Kode Bayar')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Kecamatan')),
          DataColumn(label: Text('Kelurahan')),
          DataColumn(label: Text('Keterangan')),
          DataColumn(label: Text('Tanggal Kadaluarsa')),
        ],
        rows: [
          for (final g in result.groups)
            DataRow(cells: [
              DataCell(Text(g.namaGroup)),
              DataCell(Text(g.namaKolektor)),
              DataCell(Text(g.hpKolektor)),
              DataCell(Text(g.anggota)),
              DataCell(Text(g.kodeBayar)),
              DataCell(Text(g.status)),
              DataCell(Text(g.kecamatan)),
              DataCell(Text(g.kelurahan)),
              DataCell(Text(g.keterangan)),
              DataCell(Text(g.tanggalKadaluarsa)),
            ]),
        ],
      ),
    );
  }
}
