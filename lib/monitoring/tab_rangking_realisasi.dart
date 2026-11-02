import 'package:flutter/material.dart';

import '../download_helper.dart';
import '../native_file_helper.dart';
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
  String _tahun = '${DateTime.now().year}';
  String _kelurahan = '3205200004';
  String _namaKelurahan = 'BOBOJONG';
  final _kecamatan = '3205200';
  final _namaKecamatan = 'MANDE';

  Future<void> _directExcelExport() async {
    try {
      final bytes = await widget.client.downloadRangkingRealisasiExcel(
        bukuFilter: _bukuFilter,
        tahun: _tahun,
        kelurahan: _kelurahan,
        kecamatan: _kecamatan,
        namakel: _namaKelurahan,
        namakec: _namaKecamatan,
      );
      final suffixTahun = _tahun.isNotEmpty ? '_$_tahun' : '';
      final fileName = 'rangking_realisasi_buku_$_bukuFilter$suffixTahun.xlsx';
      await DownloadHelper.saveBytes(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil mengunduh $fileName'),
          action: SnackBarAction(
            label: 'Bagikan',
            onPressed: () => NativeFileHelper.shareBytes(
              bytes: bytes,
              fileName: fileName,
              mimeType: DownloadHelper.mimeTypeFor(fileName),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengekspor Rangking Realisasi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MonitoringTabScaffold(
      reportTitle: 'Rangking Realisasi',
      client: widget.client,
      onDirectExcelExport: _directExcelExport,
      onFetch: () => widget.client.fetchRangkingRealisasi(
        bukuFilter: _bukuFilter,
        tahun: _tahun,
        kelurahan: _kelurahan,
        kecamatan: _kecamatan,
        namaKecamatan: _namaKecamatan,
      ),
      formBuilder: (context, loading) => [
        const MonitoringSectionTitle('Wilayah Desa / Kelurahan'),
        DesaKelurahanDropdown(
          client: widget.client,
          value: _kelurahan,
          onChanged: (v) => setState(() => _kelurahan = v),
          onNameChanged: (name) => setState(() => _namaKelurahan = name),
        ),
        const MonitoringSectionTitle('Tahun Pajak'),
        DropdownButtonFormField<String>(
          initialValue: _tahun,
          decoration: const InputDecoration(
            labelText: 'Tahun Pajak',
            border: OutlineInputBorder(),
          ),
          items: [
            for (var y = DateTime.now().year; y >= 2015; y--)
              DropdownMenuItem(value: '$y', child: Text('$y')),
          ],
          onChanged: (v) => setState(() => _tahun = v ?? '${DateTime.now().year}'),
        ),
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
