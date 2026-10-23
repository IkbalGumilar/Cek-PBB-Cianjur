import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_tab_scaffold.dart';

/// Tab "Sudah Bayar" — replika field-per-field dari tab pertama Monitoring
/// Wilayah asli.
class TabSudahBayar extends StatefulWidget {
  final StaffPortalClient client;
  const TabSudahBayar({super.key, required this.client});

  @override
  State<TabSudahBayar> createState() => _TabSudahBayarState();
}

class _TabSudahBayarState extends State<TabSudahBayar> {
  final _tglAwal = TextEditingController(text: todayMinus30DaysYmd());
  final _tglAkhir = TextEditingController(text: todayYmd());
  final _tahunAwal = TextEditingController();
  final _tahunAkhir = TextEditingController();
  final _nop = TextEditingController();
  final _namaWp = TextEditingController();
  final _kodeBayarIndividu = TextEditingController();
  final _kodeBayarKolektif = TextEditingController();
  final _va = TextEditingController();
  final _qris = TextEditingController();
  final _operator = TextEditingController();
  String _buku = 'semua';
  String _bank = '';

  @override
  void dispose() {
    for (final c in [
      _tglAwal,
      _tglAkhir,
      _tahunAwal,
      _tahunAkhir,
      _nop,
      _namaWp,
      _kodeBayarIndividu,
      _kodeBayarKolektif,
      _va,
      _qris,
      _operator,
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
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    return widget.client.fetchSudahBayar(
      tglBayarAwal: _tglAwal.text,
      tglBayarAkhir: _tglAkhir.text,
      tahunAwal: _tahunAwal.text.trim(),
      tahunAkhir: _tahunAkhir.text.trim(),
      bukuMin: bukuMin,
      bukuMax: bukuMax,
      bank: _bank,
      nop: _nop.text.trim(),
      namaWp: _namaWp.text.trim(),
      kodeBayarIndividu: _kodeBayarIndividu.text.trim(),
      kodeBayarKolektif: _kodeBayarKolektif.text.trim(),
      va: _va.text.trim(),
      qris: _qris.text.trim(),
      operator: _operator.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Sudah Bayar',
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
        BukuDropdown(
          value: _buku,
          onChanged: (v) => setState(() => _buku = v),
        ),
        const SizedBox(height: 12),
        BankDropdown(
          client: widget.client,
          value: _bank,
          onChanged: (v) => setState(() => _bank = v),
        ),
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
          controller: _operator,
          decoration: const InputDecoration(
            labelText: 'Petugas Pembayaran',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _kodeBayarIndividu,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kode Bayar Individu',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _kodeBayarKolektif,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kode Bayar Kolektif',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _va,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'VA',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _qris,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'QRIS',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
