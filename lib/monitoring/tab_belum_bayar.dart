import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_tab_scaffold.dart';

/// Tab "Belum Bayar" — replika field-per-field dari tab kedua Monitoring
/// Wilayah asli.
class TabBelumBayar extends StatefulWidget {
  final StaffPortalClient client;
  const TabBelumBayar({super.key, required this.client});

  @override
  State<TabBelumBayar> createState() => _TabBelumBayarState();
}

class _TabBelumBayarState extends State<TabBelumBayar> {
  final _tglCutoff = TextEditingController(text: todayYmd());
  final _tahunAwal = TextEditingController();
  final _tahunAkhir = TextEditingController();
  final _nop = TextEditingController();
  final _namaWp = TextEditingController();
  final _kodeBayarIndividu = TextEditingController();
  String _buku = 'semua';
  String _kelurahan = '3205200004';
  final _kecamatan = '3205200';

  @override
  void dispose() {
    for (final c in [
      _tglCutoff,
      _tahunAwal,
      _tahunAkhir,
      _nop,
      _namaWp,
      _kodeBayarIndividu,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<MonitoringTableResult?> _fetch() async {
    if (_tglCutoff.text.isEmpty) {
      return const MonitoringTableResult(
        errorMessage: 'Tanggal Cutoff Belum Bayar wajib diisi.',
      );
    }
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    return widget.client.fetchBelumBayar(
      tglCutoff: _tglCutoff.text,
      tahunAwal: _tahunAwal.text.trim(),
      tahunAkhir: _tahunAkhir.text.trim(),
      nop: _nop.text.trim(),
      namaWp: _namaWp.text.trim(),
      kodeBayarIndividu: _kodeBayarIndividu.text.trim(),
      bukuMin: bukuMin,
      bukuMax: bukuMax,
      kelurahan: _kelurahan,
      kecamatan: _kecamatan,
    );
  }

  Map<String, String> _getExportParams() {
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    return {
      'tahun_1': _tahunAwal.text.trim(),
      'tahun_2': _tahunAkhir.text.trim(),
      'nop': _nop.text.trim(),
      'nama_wp': _namaWp.text.trim(),
      'bank': '',
      'merchant': '',
      'st': '2',
      'tgl_pembayaran_1': '',
      'tgl_pembayaran_2': '',
      'kec': _kecamatan,
      'kel': _kelurahan,
      'buku_1': bukuMin,
      'buku_2': bukuMax,
      'tgl_pelimpahan_1': '',
      'tgl_pelimpahan_2': '',
      'kode_bayar_individu': _kodeBayarIndividu.text.trim(),
      'kode_bayar_kolektif': '',
      'va': '',
      'qris': '',
      'tgl_cutoff': _tglCutoff.text,
      'operator': '',
      'LBL_KEL': 'Desa/Kelurahan',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Belum Bayar',
      client: widget.client,
      excelQueueFunctionName: 'loadDataDownloadExcelBelumBayar',
      toExcelFunctionName: 'toExcelBelumBayar',
      queryName: 'Belum_Bayar',
      st: 2,
      getExportParams: _getExportParams,
      onFetch: _fetch,
      formBuilder: (context, loading) => [
        const MonitoringSectionTitle('Wilayah Desa / Kelurahan'),
        DesaKelurahanDropdown(
          client: widget.client,
          value: _kelurahan,
          onChanged: (v) => setState(() => _kelurahan = v),
        ),
        const MonitoringSectionTitle('Tanggal Cutoff Belum Bayar'),
        MonitoringDateField(
          label: 'Tanggal Cutoff',
          controller: _tglCutoff,
          required: true,
        ),
        const MonitoringSectionTitle('Tahun Pajak (opsional)'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tahunAwal,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Awal',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _tahunAkhir,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Akhir',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ),
          ],
        ),
        const MonitoringSectionTitle('Filter lainnya (opsional)'),
        BukuDropdown(value: _buku, onChanged: (v) => setState(() => _buku = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _nop,
          decoration: const InputDecoration(
            labelText: 'NOP',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _namaWp,
          decoration: const InputDecoration(
            labelText: 'Nama WP',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _kodeBayarIndividu,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kode Bayar',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
