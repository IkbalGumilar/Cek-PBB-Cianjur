import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_tab_scaffold.dart';

/// Tab "Sudah Bayar Kolektif" — replika field-per-field dari tab kelima
/// Monitoring Wilayah asli.
class TabSudahBayarKolektif extends StatefulWidget {
  final StaffPortalClient client;
  const TabSudahBayarKolektif({super.key, required this.client});

  @override
  State<TabSudahBayarKolektif> createState() => _TabSudahBayarKolektifState();
}

class _TabSudahBayarKolektifState extends State<TabSudahBayarKolektif> {
  final _tglAwal = TextEditingController(text: todayYmd());
  final _tglAkhir = TextEditingController(text: todayYmd());
  final _kodeBayarKolektif = TextEditingController();
  final _namaGrup = TextEditingController();
  final _namaKolektor = TextEditingController();
  late String _kelurahan = widget.client.activeKelurahanCode;
  String get _kecamatan => widget.client.activeKecamatanCode;

  @override
  void dispose() {
    for (final c in [
      _tglAwal,
      _tglAkhir,
      _kodeBayarKolektif,
      _namaGrup,
      _namaKolektor,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<MonitoringTableResult?> _fetch() async {
    if (_tglAwal.text.isEmpty || _tglAkhir.text.isEmpty) {
      return const MonitoringTableResult(
        errorMessage: 'Tanggal Pembayaran wajib diisi.',
      );
    }
    return widget.client.fetchSudahBayarKolektif(
      tglBayarAwal: _tglAwal.text,
      tglBayarAkhir: _tglAkhir.text,
      kodeBayarKolektif: _kodeBayarKolektif.text.trim(),
      namaGrup: _namaGrup.text.trim(),
      namaKolektor: _namaKolektor.text.trim(),
      kelurahan: _kelurahan,
      kecamatan: _kecamatan,
    );
  }

  Map<String, String> _getExportParams() {
    return {
      'tgl_pembayaran_1': _tglAwal.text,
      'tgl_pembayaran_2': _tglAkhir.text,
      'nama_grup': _namaGrup.text.trim(),
      'nama_kolektor': _namaKolektor.text.trim(),
      'kc': _kecamatan,
      'kl': _kelurahan,
      'kode_bayar_kolektif': _kodeBayarKolektif.text.trim(),
      'tgl_cutoff_belum_bayar': '',
      'tgl_cutoff_kadaluarsa': '',
      'st': '1',
      'exp': '',
      'LBL_KEL': 'Desa/Kelurahan',
      'ADMIN_SW_DBNAME': 'SW_PBB',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Sudah Bayar Kolektif',
      client: widget.client,
      excelQueueFunctionName: 'loadDataDownloadExcelSudahBayarKolektif',
      toExcelFunctionName: 'toExcelSudahBayarKolektif',
      queryName: 'Sudah_Bayar_Kolektif',
      st: 1,
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
        const MonitoringSectionTitle('Tanggal Pembayaran'),
        Row(
          children: [
            Expanded(
              child: MonitoringDateField(
                label: 'Awal',
                controller: _tglAwal,
                required: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MonitoringDateField(
                label: 'Akhir',
                controller: _tglAkhir,
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
