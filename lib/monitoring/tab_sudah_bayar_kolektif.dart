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
    );
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Sudah Bayar Kolektif',
      onFetch: _fetch,
      formBuilder: (context, loading) => [
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
