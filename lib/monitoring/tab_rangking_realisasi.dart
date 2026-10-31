import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_tab_scaffold.dart';

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

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Rangking Realisasi',
      onFetch: () =>
          widget.client.fetchRangkingRealisasi(bukuFilter: _bukuFilter),
      formBuilder: (context, loading) => [
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
      ],
    );
  }
}
