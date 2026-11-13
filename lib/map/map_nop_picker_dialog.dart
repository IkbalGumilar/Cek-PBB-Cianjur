import 'package:flutter/material.dart';

import '../blok_record.dart';
import '../nop_helper.dart';
import 'map_models.dart';
import 'map_pin_store.dart';

/// Dialog pencarian & pemilihan multi-NOP Wajib Pajak untuk disematkan pada satu koordinat peta.
Future<List<BlokRecord>?> showMapNopPickerDialog(
  BuildContext context, {
  required MapCoordinate coordinate,
  required List<BlokRecord> uniqueDhkpRecords,
  required Set<String> existingNopsAtCoordinate,
  required Map<String, MapCoordinate> existingPinCoordByNop,
  String sourceLabel = 'Pin Manual',
}) {
  return showDialog<List<BlokRecord>>(
    context: context,
    builder: (ctx) => _MapNopPickerDialog(
      coordinate: coordinate,
      uniqueDhkpRecords: uniqueDhkpRecords,
      existingNopsAtCoordinate: existingNopsAtCoordinate,
      existingPinCoordByNop: existingPinCoordByNop,
      sourceLabel: sourceLabel,
    ),
  );
}

class _MapNopPickerDialog extends StatefulWidget {
  final MapCoordinate coordinate;
  final List<BlokRecord> uniqueDhkpRecords;
  final Set<String> existingNopsAtCoordinate;
  final Map<String, MapCoordinate> existingPinCoordByNop;
  final String sourceLabel;

  const _MapNopPickerDialog({
    required this.coordinate,
    required this.uniqueDhkpRecords,
    required this.existingNopsAtCoordinate,
    required this.existingPinCoordByNop,
    required this.sourceLabel,
  });

  @override
  State<_MapNopPickerDialog> createState() => _MapNopPickerDialogState();
}

class _MapNopPickerDialogState extends State<_MapNopPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _manualNopCtrl = TextEditingController();
  final TextEditingController _manualNamaCtrl = TextEditingController();

  final Map<String, BlokRecord> _selected = {};
  bool _showManualInput = false;
  String _query = '';
  String? _manualError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _manualNopCtrl.dispose();
    _manualNamaCtrl.dispose();
    super.dispose();
  }

  List<BlokRecord> get _filteredRecords {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.uniqueDhkpRecords.take(80).toList();
    }
    final digitsQ = q.replaceAll(RegExp(r'[^0-9]'), '');
    final results = <BlokRecord>[];
    for (final r in widget.uniqueDhkpRecords) {
      final matchesText = r.namaWajibPajak.toLowerCase().contains(q) ||
          r.alamatObjek.toLowerCase().contains(q) ||
          r.blok.toLowerCase().contains(q) ||
          r.wilayah.toLowerCase().contains(q);
      final matchesNop = digitsQ.isNotEmpty && r.nop.contains(digitsQ);
      if (matchesText || matchesNop) {
        results.add(r);
        if (results.length >= 100) break;
      }
    }
    return results;
  }

  void _addManualNop() {
    final expanded = expandNop(_manualNopCtrl.text.trim());
    final norm = MapPinEntry.normalizePinNop(expanded);
    if (norm.length != 18) {
      setState(() {
        _manualError =
            'Masukkan 18 digit NOP atau kode blok+urut (mis. 170154).';
      });
      return;
    }

    // Jika NOP ternyata ada di daftar DHKP, pakai data resminya
    final existingDhkp = widget.uniqueDhkpRecords.cast<BlokRecord?>().firstWhere(
          (r) => MapPinEntry.normalizePinNop(r!.nop) == norm,
          orElse: () => null,
        );

    final nama = _manualNamaCtrl.text.trim().isNotEmpty
        ? _manualNamaCtrl.text.trim().toUpperCase()
        : (existingDhkp?.namaWajibPajak ??
            'WP Blok ${nopBlok(norm)} No ${nopWilayah(norm)}');

    final rec = existingDhkp ??
        BlokRecord(
          nop: norm,
          namaWajibPajak: nama,
          tahunBayar: '${DateTime.now().year}',
          tanggalBayar: '',
          jumlahPbb: '',
          statusBayar: 'Belum Bayar',
          alamatObjek: 'Desa $activeDesaName',
        );

    setState(() {
      _selected[norm] = rec;
      _manualNopCtrl.clear();
      _manualNamaCtrl.clear();
      _manualError = null;
      _showManualInput = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final hasExisting = widget.existingNopsAtCoordinate.isNotEmpty;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      title: Row(
        children: [
          const Icon(Icons.add_location_alt_rounded, color: Color(0xFFF39C12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasExisting
                  ? 'Tambah NOP ke Titik Peta'
                  : 'Tandai Objek Pajak (WP)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.blueGrey.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded,
                      size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${widget.sourceLabel} • ${widget.coordinate.latitude.toStringAsFixed(6)}, ${widget.coordinate.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasExisting) ...[
              const SizedBox(height: 6),
              Text(
                'Titik ini sudah memuat ${widget.existingNopsAtCoordinate.length} NOP. Pilih NOP tambahan untuk digabungkan ke koordinat yang sama.',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Cari Nama WP, NOP, Blok (mis. 017), atau No Urut...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showManualInput = !_showManualInput),
                      icon: Icon(
                        _showManualInput
                            ? Icons.expand_less
                            : Icons.edit_note_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _showManualInput
                            ? 'Tutup Input NOP Manual'
                            : 'Input NOP Manual (Jika Belum Ada)',
                        style: const TextStyle(fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                if (_selected.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text(
                      '${_selected.length} dipilih',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        const Color(0xFFF1C40F).withValues(alpha: 0.25),
                  ),
                ],
              ],
            ),
            if (_showManualInput)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _manualNopCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'NOP 18 digit atau Blok+Urut (mis. 170154)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualNamaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nama Wajib Pajak (Opsional)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addManualNop,
                          child: const Text('Tambah'),
                        ),
                      ],
                    ),
                    if (_manualError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _manualError!,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.uniqueDhkpRecords.isEmpty
                            ? 'Belum ada data DHKP dimuat.\nGunakan "Input NOP Manual" di atas.'
                            : 'Tidak ditemukan NOP/WP untuk "$_query".',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final r = filtered[idx];
                        final norm = MapPinEntry.normalizePinNop(r.nop);
                        final isChecked = _selected.containsKey(norm);
                        final alreadyHere =
                            widget.existingNopsAtCoordinate.contains(norm);
                        final prevCoord = widget.existingPinCoordByNop[norm];
                        final pinnedElsewhere = prevCoord != null &&
                            !alreadyHere &&
                            prevCoord != widget.coordinate;

                        return CheckboxListTile(
                          dense: true,
                          value: isChecked,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selected[norm] = r;
                              } else {
                                _selected.remove(norm);
                              }
                            });
                          },
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.namaWajibPajak,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: r.isPaid
                                      ? Colors.green.withValues(alpha: 0.14)
                                      : Colors.red.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  r.isPaid ? 'Lunas' : 'Belum',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: r.isPaid
                                        ? Colors.green.shade800
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Blok ${r.blok} #${r.wilayah} • ${r.nop} • ${r.jumlahPbb}',
                                style: const TextStyle(fontSize: 10.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (alreadyHere)
                                Text(
                                  '✓ Sudah tertanda di titik ini',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else if (pinnedElsewhere)
                                Text(
                                  '⚠ Sudah ada pin lain — akan digabung ke koordinat ini',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.values.toList()),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text('Simpan (${_selected.length} NOP)'),
        ),
      ],
    );
  }
}
