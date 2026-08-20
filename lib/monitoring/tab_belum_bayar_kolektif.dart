import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

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

  bool _loading = false;
  MonitoringTableResult? _result;

  @override
  void dispose() {
    for (final c in [_tglCutoffBelumBayar, _tglCutoffKadaluarsa, _kodeBayarKolektif, _namaGrup, _namaKolektor]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _tampilkan() async {
    if (_tglCutoffBelumBayar.text.isEmpty) {
      setState(() => _result = const MonitoringTableResult(errorMessage: 'Tanggal Cutoff Belum Bayar wajib diisi.'));
      return;
    }
    if (_tglCutoffKadaluarsa.text.isEmpty) {
      setState(() => _result = const MonitoringTableResult(errorMessage: 'Tanggal Cutoff Kadaluarsa wajib diisi.'));
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await widget.client.fetchBelumBayarKolektif(
        tglCutoffBelumBayar: _tglCutoffBelumBayar.text,
        tglCutoffKadaluarsa: _tglCutoffKadaluarsa.text,
        kodeBayarKolektif: _kodeBayarKolektif.text.trim(),
        namaGrup: _namaGrup.text.trim(),
        namaKolektor: _namaKolektor.text.trim(),
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
          const MonitoringSectionTitle('Tanggal Cutoff'),
          Row(children: [
            Expanded(child: MonitoringDateField(label: 'Belum Bayar', controller: _tglCutoffBelumBayar, required: true)),
            const SizedBox(width: 8),
            Expanded(child: MonitoringDateField(label: 'Kadaluarsa', controller: _tglCutoffKadaluarsa, required: true)),
          ]),
          const MonitoringSectionTitle('Filter lainnya (opsional)'),
          TextField(controller: _kodeBayarKolektif, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kode Bayar Kolektif', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _namaGrup, decoration: const InputDecoration(labelText: 'Nama Grup', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _namaKolektor, decoration: const InputDecoration(labelText: 'Nama Kolektor', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _tampilkan,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Tampilkan'),
          ),
          MonitoringResultView(result: _result, loading: false, reportTitle: 'Belum Bayar Kolektif'),
        ],
      ),
    );
  }
}
