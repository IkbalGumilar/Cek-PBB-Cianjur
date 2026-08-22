import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

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

  bool _loading = false;
  MonitoringTableResult? _result;

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
    final (bukuMin, bukuMax) = BukuDropdown.rangeFor(_buku);
    try {
      final result = await widget.client.fetchSudahBayar(
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
            reportTitle: 'Sudah Bayar',
          ),
        ],
      ),
    );
  }
}
