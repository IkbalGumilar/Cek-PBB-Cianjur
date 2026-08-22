import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

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

  bool _loading = false;
  MonitoringTableResult? _result;

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

  Future<void> _tampilkan() async {
    if (_tglAwal.text.isEmpty || _tglAkhir.text.isEmpty) {
      setState(
        () => _result = const MonitoringTableResult(
          errorMessage: 'Tanggal Pembayaran wajib diisi.',
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await widget.client.fetchSudahBayarKolektif(
        tglBayarAwal: _tglAwal.text,
        tglBayarAkhir: _tglAkhir.text,
        kodeBayarKolektif: _kodeBayarKolektif.text.trim(),
        namaGrup: _namaGrup.text.trim(),
        namaKolektor: _namaKolektor.text.trim(),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _result = MonitoringTableResult(
          errorMessage: 'Gagal memuat data: $e',
        ),
      );
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
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _tampilkan,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Tampilkan'),
          ),
          MonitoringResultView(
            result: _result,
            loading: false,
            reportTitle: 'Sudah Bayar Kolektif',
          ),
        ],
      ),
    );
  }
}
