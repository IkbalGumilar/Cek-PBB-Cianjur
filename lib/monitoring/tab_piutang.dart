import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_tab_scaffold.dart';

/// Tab "Piutang" — replika field-per-field dari tab keempat Monitoring
/// Wilayah asli.
class TabPiutang extends StatefulWidget {
  final StaffPortalClient client;
  const TabPiutang({super.key, required this.client});

  @override
  State<TabPiutang> createState() => _TabPiutangState();
}

class _TabPiutangState extends State<TabPiutang> {
  final _tglAwal = TextEditingController(text: todayYmd());
  final _tglAkhir = TextEditingController(text: todayYmd());
  final _tglCutoff = TextEditingController(text: todayYmd());
  final _tahunAwal = TextEditingController();
  final _tahunAkhir = TextEditingController();
  final _tglPelimpahanAwal = TextEditingController();
  final _tglPelimpahanAkhir = TextEditingController();
  String _buku = 'semua';

  @override
  void dispose() {
    for (final c in [
      _tglAwal,
      _tglAkhir,
      _tglCutoff,
      _tahunAwal,
      _tahunAkhir,
      _tglPelimpahanAwal,
      _tglPelimpahanAkhir,
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
    if (_tglCutoff.text.isEmpty) {
      return const MonitoringTableResult(
        errorMessage: 'Tanggal Cutoff Belum Bayar wajib diisi.',
      );
    }
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    if (bukuMin.isEmpty || bukuMax.isEmpty) {
      return const MonitoringTableResult(errorMessage: 'Buku wajib dipilih.');
    }
    return widget.client.fetchPiutang(
      tglBayarAwal: _tglAwal.text,
      tglBayarAkhir: _tglAkhir.text,
      tglCutoff: _tglCutoff.text,
      tahunAwal: _tahunAwal.text.trim(),
      tahunAkhir: _tahunAkhir.text.trim(),
      bukuMin: bukuMin,
      bukuMax: bukuMax,
      tglPelimpahanAwal: _tglPelimpahanAwal.text,
      tglPelimpahanAkhir: _tglPelimpahanAkhir.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Piutang',
      onFetch: _fetch,
      formBuilder: (context, loading) => [
        const MonitoringSectionTitle('Buku'),
        BukuDropdown(value: _buku, onChanged: (v) => setState(() => _buku = v)),
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
        const MonitoringSectionTitle('Tanggal Pelimpahan (opsional)'),
        Row(
          children: [
            Expanded(
              child: MonitoringDateField(
                label: 'Awal',
                controller: _tglPelimpahanAwal,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MonitoringDateField(
                label: 'Akhir',
                controller: _tglPelimpahanAkhir,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
