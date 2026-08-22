import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

/// Tab "Rangking Realisasi" — replika field-per-field dari tab ketujuh
/// Monitoring Wilayah asli.
class TabRangkingRealisasi extends StatefulWidget {
  final StaffPortalClient client;
  const TabRangkingRealisasi({super.key, required this.client});

  @override
  State<TabRangkingRealisasi> createState() => _TabRangkingRealisasiState();
}

class _TabRangkingRealisasiState extends State<TabRangkingRealisasi> {
  String _bukuFilter = '123';
  bool _loading = false;
  MonitoringTableResult? _result;

  Future<void> _tampilkan() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await widget.client.fetchRangkingRealisasi(
        bukuFilter: _bukuFilter,
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
          const MonitoringSectionTitle('Buku'),
          DropdownButtonFormField<String>(
            initialValue: _bukuFilter,
            decoration: const InputDecoration(
              labelText: 'Buku',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: '1', child: Text('Buku 1')),
              DropdownMenuItem(value: '12', child: Text('Buku 1, 2')),
              DropdownMenuItem(value: '123', child: Text('Buku 1, 2, 3')),
              DropdownMenuItem(value: '2', child: Text('Buku 2')),
              DropdownMenuItem(value: '23', child: Text('Buku 2, 3')),
              DropdownMenuItem(value: '3', child: Text('Buku 3')),
            ],
            onChanged: (v) => setState(() => _bukuFilter = v ?? '123'),
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
            reportTitle: 'Rangking Realisasi',
          ),
        ],
      ),
    );
  }
}
