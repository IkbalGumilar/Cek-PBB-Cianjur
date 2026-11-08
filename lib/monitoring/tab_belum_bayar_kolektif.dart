import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_tab_scaffold.dart';

/// Tab "Belum Bayar Kolektif" — replika field-per-field dari tab keenam
/// Monitoring Wilayah asli.
class TabBelumBayarKolektif extends StatefulWidget {
  final StaffPortalClient client;
  const TabBelumBayarKolektif({super.key, required this.client});

  @override
  State<TabBelumBayarKolektif> createState() => _TabBelumBayarKolektifState();
}

class _TabBelumBayarKolektifState extends State<TabBelumBayarKolektif> {
  final _tglCutoffBelumBayar = TextEditingController(text: todayYmd());
  final _tglCutoffKadaluarsa = TextEditingController(text: todayYmd());
  final _kodeBayarKolektif = TextEditingController();
  final _namaGrup = TextEditingController();
  final _namaKolektor = TextEditingController();
  late String _kelurahan = widget.client.activeKelurahanCode;
  String get _kecamatan => widget.client.activeKecamatanCode;

  @override
  void dispose() {
    for (final c in [
      _tglCutoffBelumBayar,
      _tglCutoffKadaluarsa,
      _kodeBayarKolektif,
      _namaGrup,
      _namaKolektor,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<MonitoringTableResult?> _fetch() async {
    if (_tglCutoffBelumBayar.text.isEmpty) {
      return const MonitoringTableResult(
        errorMessage: 'Tanggal Cutoff Belum Bayar wajib diisi.',
      );
    }
    if (_tglCutoffKadaluarsa.text.isEmpty) {
      return const MonitoringTableResult(
        errorMessage: 'Tanggal Cutoff Kadaluarsa wajib diisi.',
      );
    }
    return widget.client.fetchBelumBayarKolektif(
      tglCutoffBelumBayar: _tglCutoffBelumBayar.text,
      tglCutoffKadaluarsa: _tglCutoffKadaluarsa.text,
      kodeBayarKolektif: _kodeBayarKolektif.text.trim(),
      namaGrup: _namaGrup.text.trim(),
      namaKolektor: _namaKolektor.text.trim(),
      kelurahan: _kelurahan,
      kecamatan: _kecamatan,
    );
  }

  Map<String, String> _getExportParams() {
    return {
      'tgl_pembayaran_1': '',
      'tgl_pembayaran_2': '',
      'nama_grup': _namaGrup.text.trim(),
      'nama_kolektor': _namaKolektor.text.trim(),
      'kode_bayar_kolektif': _kodeBayarKolektif.text.trim(),
      'tgl_cutoff_belum_bayar': _tglCutoffBelumBayar.text,
      'tgl_cutoff_kadaluarsa': _tglCutoffKadaluarsa.text,
      'st': '2',
      'kc': _kecamatan,
      'kl': _kelurahan,
      'exp': '',
      'LBL_KEL': 'Desa/Kelurahan',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Belum Bayar Kolektif',
      client: widget.client,
      excelQueueFunctionName: 'loadDataDownloadExcelBelumBayarKolektif',
      toExcelFunctionName: 'toExcelBelumBayarKolektif',
      queryName: 'Belum_Bayar_Kolektif',
      st: 2,
      isKolektif: true,
      getExportParams: _getExportParams,
      onFetch: _fetch,
      formBuilder: (context, loading) => [
        const MonitoringSectionTitle('Wilayah Desa / Kelurahan'),
        DesaKelurahanDropdown(
          client: widget.client,
          value: _kelurahan,
          onChanged: (v) => setState(() => _kelurahan = v),
        ),
        const MonitoringSectionTitle('Tanggal Cutoff'),
        Row(
          children: [
            Expanded(
              child: MonitoringDateField(
                label: 'Belum Bayar',
                controller: _tglCutoffBelumBayar,
                required: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MonitoringDateField(
                label: 'Kadaluarsa',
                controller: _tglCutoffKadaluarsa,
                required: true,
              ),
            ),
          ],
        ),
        const MonitoringSectionTitle('Filter lainnya (opsional)'),
        TextField(
          controller: _kodeBayarKolektif,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kode Bayar Kolektif',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _namaGrup,
          decoration: const InputDecoration(
            labelText: 'Nama Grup',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _namaKolektor,
          decoration: const InputDecoration(
            labelText: 'Nama Kolektor',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
