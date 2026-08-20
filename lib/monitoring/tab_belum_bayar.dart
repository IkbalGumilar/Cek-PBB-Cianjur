import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

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

  bool _loading = false;
  MonitoringTableResult? _result;

  @override
  void dispose() {
    for (final c in [_tglCutoff, _tahunAwal, _tahunAkhir, _nop, _namaWp, _kodeBayarIndividu]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _tampilkan() async {
    if (_tglCutoff.text.isEmpty) {
      setState(() => _result = const MonitoringTableResult(errorMessage: 'Tanggal Cutoff Belum Bayar wajib diisi.'));
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    try {
      final result = await widget.client.fetchBelumBayar(
        tglCutoff: _tglCutoff.text,
        tahunAwal: _tahunAwal.text.trim(),
        tahunAkhir: _tahunAkhir.text.trim(),
        nop: _nop.text.trim(),
        namaWp: _namaWp.text.trim(),
        kodeBayarIndividu: _kodeBayarIndividu.text.trim(),
        bukuMin: bukuMin,
        bukuMax: bukuMax,
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
          const MonitoringSectionTitle('Tanggal Cutoff Belum Bayar'),
          MonitoringDateField(label: 'Tanggal Cutoff', controller: _tglCutoff, required: true),
          const MonitoringSectionTitle('Tahun Pajak (opsional)'),
          Row(children: [
            Expanded(child: TextField(controller: _tahunAwal, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Awal', border: OutlineInputBorder(), counterText: ''))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _tahunAkhir, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Akhir', border: OutlineInputBorder(), counterText: ''))),
          ]),
          const MonitoringSectionTitle('Filter lainnya (opsional)'),
          BukuDropdown(value: _buku, onChanged: (v) => setState(() => _buku = v)),
          const SizedBox(height: 12),
          TextField(controller: _nop, decoration: const InputDecoration(labelText: 'NOP', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _namaWp, decoration: const InputDecoration(labelText: 'Nama WP', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _kodeBayarIndividu, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kode Bayar', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _tampilkan,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Tampilkan'),
          ),
          MonitoringResultView(result: _result, loading: false, reportTitle: 'Belum Bayar'),
        ],
      ),
    );
  }
}
