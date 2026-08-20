import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

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

  bool _loading = false;
  MonitoringTableResult? _result;

  @override
  void dispose() {
    for (final c in [_tglAwal, _tglAkhir, _tglCutoff, _tahunAwal, _tahunAkhir, _tglPelimpahanAwal, _tglPelimpahanAkhir]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _tampilkan() async {
    if (_tglAwal.text.isEmpty || _tglAkhir.text.isEmpty) {
      setState(() => _result = const MonitoringTableResult(errorMessage: 'Tanggal Pembayaran wajib diisi.'));
      return;
    }
    if (_tglCutoff.text.isEmpty) {
      setState(() => _result = const MonitoringTableResult(errorMessage: 'Tanggal Cutoff Belum Bayar wajib diisi.'));
      return;
    }
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    if (bukuMin.isEmpty || bukuMax.isEmpty) {
      setState(() => _result = const MonitoringTableResult(errorMessage: 'Buku wajib dipilih.'));
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await widget.client.fetchPiutang(
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
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = MonitoringTableResult(errorMessage: 'Gagal memuat data: $e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WilayahBadge(),
          const MonitoringSectionTitle('Buku'),
          BukuDropdown(value: _buku, onChanged: (v) => setState(() => _buku = v)),
          const MonitoringSectionTitle('Tanggal Pembayaran'),
          Row(children: [
            Expanded(child: MonitoringDateField(label: 'Awal', controller: _tglAwal, required: true)),
            const SizedBox(width: 8),
            Expanded(child: MonitoringDateField(label: 'Akhir', controller: _tglAkhir, required: true)),
          ]),
          const MonitoringSectionTitle('Tanggal Cutoff Belum Bayar'),
          MonitoringDateField(label: 'Tanggal Cutoff', controller: _tglCutoff, required: true),
          const MonitoringSectionTitle('Tahun Pajak (opsional)'),
          Row(children: [
            Expanded(child: TextField(controller: _tahunAwal, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Awal', border: OutlineInputBorder(), counterText: ''))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _tahunAkhir, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Akhir', border: OutlineInputBorder(), counterText: ''))),
          ]),
          const MonitoringSectionTitle('Tanggal Pelimpahan (opsional)'),
          Row(children: [
            Expanded(child: MonitoringDateField(label: 'Awal', controller: _tglPelimpahanAwal)),
            const SizedBox(width: 8),
            Expanded(child: MonitoringDateField(label: 'Akhir', controller: _tglPelimpahanAkhir)),
          ]),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _tampilkan,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Tampilkan'),
          ),
          MonitoringResultView(result: _result, loading: false, reportTitle: 'Piutang'),
        ],
      ),
    );
  }
}
