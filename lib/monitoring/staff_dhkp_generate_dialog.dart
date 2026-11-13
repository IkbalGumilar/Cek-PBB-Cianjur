import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dkhp_package_helper.dart';
import '../dusun_data.dart';
import '../staff_portal_client.dart';
import 'staff_dhkp_generate_service.dart';

/// Membuka dialog Generate DHKP Baru dari Portal Staf (Mode Timpa)
Future<void> showStaffDhkpGenerateDialog(
  BuildContext context, {
  required StaffPortalClient client,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StaffDhkpGenerateDialog(client: client),
  );
}

class _DusunFormEntry {
  final TextEditingController nameController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController bloksController;

  _DusunFormEntry({
    required String name,
    String lat = '',
    String lng = '',
    String bloks = '',
  }) : nameController = TextEditingController(text: name),
       latController = TextEditingController(text: lat),
       lngController = TextEditingController(text: lng),
       bloksController = TextEditingController(text: bloks);

  void dispose() {
    nameController.dispose();
    latController.dispose();
    lngController.dispose();
    bloksController.dispose();
  }
}

class StaffDhkpGenerateDialog extends StatefulWidget {
  final StaffPortalClient client;

  const StaffDhkpGenerateDialog({super.key, required this.client});

  @override
  State<StaffDhkpGenerateDialog> createState() =>
      _StaffDhkpGenerateDialogState();
}

class _StaffDhkpGenerateDialogState extends State<StaffDhkpGenerateDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _tahunAwalController;
  late TextEditingController _tahunAkhirController;
  late TextEditingController _kecamatanController;
  late TextEditingController _desaController;
  late TextEditingController _kantorLatController;
  late TextEditingController _kantorLngController;

  final List<_DusunFormEntry> _dusunEntries = [];
  bool _filterByDusunBlocks = true;

  bool _isProcessing = false;
  StaffDhkpGenerateProgress? _progress;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _tahunAwalController = TextEditingController(text: '2015');
    _tahunAkhirController = TextEditingController(
      text: '${DateTime.now().year}',
    );

    final kecName = widget.client.activeKecamatanName.isNotEmpty
        ? widget.client.activeKecamatanName
        : 'MANDE';
    final desaName = widget.client.activeKelurahanName.isNotEmpty
        ? widget.client.activeKelurahanName
        : 'BOBOJONG';

    _kecamatanController = TextEditingController(text: kecName);
    _desaController = TextEditingController(text: desaName);

    final kantorLat = DusunData.instance.kantorDesaLat ?? -6.763587;
    final kantorLng = DusunData.instance.kantorDesaLng ?? 107.238769;
    _kantorLatController = TextEditingController(text: kantorLat.toString());
    _kantorLngController = TextEditingController(text: kantorLng.toString());

    _initDefaultDusuns();
  }

  void _initDefaultDusuns() {
    final existingDusuns = DusunData.instance.allDusuns;
    final sourceDusuns = existingDusuns.isNotEmpty
        ? existingDusuns
        : DusunData.defaultBobojongDusuns;

    for (final d in sourceDusuns) {
      _dusunEntries.add(
        _DusunFormEntry(
          name: d.name,
          lat: d.focusLat?.toString() ?? '',
          lng: d.focusLng?.toString() ?? '',
          bloks: d.bloks
              .map((b) => int.tryParse(b)?.toString() ?? b)
              .join(', '),
        ),
      );
    }

    if (_dusunEntries.isEmpty) {
      _dusunEntries.add(_DusunFormEntry(name: 'Dusun 1', bloks: '1, 2, 3'));
    }
  }

  @override
  void dispose() {
    _tahunAwalController.dispose();
    _tahunAkhirController.dispose();
    _kecamatanController.dispose();
    _desaController.dispose();
    _kantorLatController.dispose();
    _kantorLngController.dispose();
    for (final e in _dusunEntries) {
      e.dispose();
    }
    super.dispose();
  }

  void _addDusun() {
    setState(() {
      final nextNum = _dusunEntries.length + 1;
      _dusunEntries.add(_DusunFormEntry(name: 'Dusun $nextNum', bloks: ''));
    });
  }

  void _removeDusun(int index) {
    if (_dusunEntries.length <= 1) return;
    setState(() {
      final removed = _dusunEntries.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pickManifestFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dkhp', 'dhkp', 'dat', 'json', 'zip'],
      );

      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;

      Map<String, dynamic>? manifest;
      final lower = path.toLowerCase();
      if (lower.endsWith('.json')) {
        final text = await File(path).readAsString();
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) manifest = decoded;
      } else {
        manifest = await DhkpPackageHelper.readBackupManifest(path);
      }

      if (manifest == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gagal menemukan berkas manifest.json yang valid di dalam file tersebut.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 1. Ekstrak Wilayah
      final kec = manifest['kecamatan'] as Map?;
      final desa = manifest['desa'] as Map?;
      final kecName = kec?['nama']?.toString();
      final desaName = desa?['nama']?.toString();

      if (kecName != null && kecName.isNotEmpty) {
        _kecamatanController.text = kecName;
      }
      if (desaName != null && desaName.isNotEmpty) {
        _desaController.text = desaName;
      }

      // 2. Ekstrak Koordinat Kantor Desa
      final kantor =
          (manifest['geospasial'] as Map?)?['kantor_desa'] as Map? ??
          (desa?['kantor_desa'] as Map?);
      if (kantor != null) {
        final lat = kantor['lat']?.toString();
        final lng = kantor['lng']?.toString();
        if (lat != null && lat.isNotEmpty) _kantorLatController.text = lat;
        if (lng != null && lng.isNotEmpty) _kantorLngController.text = lng;
      }

      // 3. Ekstrak Daftar Dusun & Blok
      final rawDusuns = manifest['dusuns'] as List?;
      if (rawDusuns != null && rawDusuns.isNotEmpty) {
        for (final e in _dusunEntries) {
          e.dispose();
        }
        _dusunEntries.clear();

        for (final item in rawDusuns) {
          if (item is Map) {
            final name = item['name']?.toString() ?? 'Dusun ${item['number']}';
            final titikFokus = item['titik_fokus'] as Map?;
            final lat =
                titikFokus?['lat']?.toString() ??
                item['focusLat']?.toString() ??
                '';
            final lng =
                titikFokus?['lng']?.toString() ??
                item['focusLng']?.toString() ??
                '';
            final bloksList = item['bloks'] as List?;
            final bloksStr = bloksList != null
                ? bloksList
                      .map(
                        (b) =>
                            int.tryParse(b.toString())?.toString() ??
                            b.toString(),
                      )
                      .join(', ')
                : '';

            _dusunEntries.add(
              _DusunFormEntry(name: name, lat: lat, lng: lng, bloks: bloksStr),
            );
          }
        }
      }

      final tahunManifest =
          manifest['tahun']?.toString() ??
          manifest['tahun_pajak']?.toString() ??
          manifest['tahunPajak']?.toString();
      if (tahunManifest != null && tahunManifest.isNotEmpty) {
        _tahunAkhirController.text = tahunManifest;
      }

      setState(() {});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Berhasil memuat manifest: Wilayah ${_desaController.text} (${_dusunEntries.length} Dusun terdeteksi)',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan membaca berkas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Dusun> _buildDusunsFromForm() {
    final list = <Dusun>[];
    for (var i = 0; i < _dusunEntries.length; i++) {
      final entry = _dusunEntries[i];
      final name = entry.nameController.text.trim();
      final lat = double.tryParse(entry.latController.text.trim());
      final lng = double.tryParse(entry.lngController.text.trim());

      final bloksTokens =
          entry.bloksController.text
              .split(RegExp(r'[,;]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map((s) {
                final num = int.tryParse(s);
                return num != null
                    ? num.toString().padLeft(3, '0')
                    : s.padLeft(3, '0');
              })
              .toSet()
              .toList()
            ..sort();

      list.add(
        Dusun(
          number: i + 1,
          name: name.isNotEmpty ? name : 'Dusun ${i + 1}',
          bloks: bloksTokens,
          focusLat: lat,
          focusLng: lng,
        ),
      );
    }
    return list;
  }

  Future<void> _startGenerate() async {
    if (!_formKey.currentState!.validate()) return;

    final tAwal = _tahunAwalController.text.trim();
    final tAkhir = _tahunAkhirController.text.trim();
    final labelTahun = tAwal == tAkhir ? tAwal : '$tAwal s/d $tAkhir';

    final dusuns = _buildDusunsFromForm();
    final allConfiguredBlocks = <String>{};
    for (final d in dusuns) {
      for (final b in d.bloks) {
        final cb = b.padLeft(3, '0');
        if (cb.isNotEmpty) allConfiguredBlocks.add(cb);
      }
    }

    final cakupanKet = (_filterByDusunBlocks && allConfiguredBlocks.isNotEmpty)
        ? 'Hanya blok terdaftar pada dusun (${allConfiguredBlocks.length} blok: ${allConfiguredBlocks.join(", ")})'
        : 'Semua blok se-desa (tanpa filter blok dusun)';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Konfirmasi Timpa DHKP'),
          ],
        ),
        content: Text(
          'Anda akan mengunduh seluruh data SPPT Tahun $labelTahun dari Portal Staf untuk Desa ${_desaController.text}.\n\n'
          '📌 Cakupan: $cakupanKet\n\n'
          '⚠️ Basis data DHKP di aplikasi saat ini akan DITIMPA dengan data baru. Salinan cadangan (backup) otomatis disimpan sebelum proses.\n\n'
          'Lanjutkan proses?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Ya, Mulai Timpa DHKP'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final kantorLat = double.tryParse(_kantorLatController.text.trim());
    final kantorLng = double.tryParse(_kantorLngController.text.trim());

    setState(() {
      _isProcessing = true;
      _cancelled = false;
      _progress = null;
    });

    final outcome = await StaffDhkpGenerateService.instance.generateAndApply(
      client: widget.client,
      tahunAwal: tAwal,
      tahunAkhir: tAkhir,
      kelurahanCode: widget.client.activeKelurahanCode,
      kecamatanCode: widget.client.activeKecamatanCode,
      desaName: _desaController.text.trim(),
      kecamatanName: _kecamatanController.text.trim(),
      dusuns: dusuns,
      filterByDusunBlocks: _filterByDusunBlocks,
      kantorDesaLat: kantorLat,
      kantorDesaLng: kantorLng,
      targetPemdaThreshold: 2000000,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
      shouldCancel: () => _cancelled,
    );

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
    });

    if (outcome.success) {
      Navigator.of(context).pop();
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Colors.green,
            size: 48,
          ),
          title: const Text('DHKP Berhasil Digenerate!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tahun Pajak: ${outcome.tahun}'),
              Text('Wilayah: Desa ${outcome.desaName}'),
              const Divider(),
              Text('• Total SPPT Terbit: ${outcome.totalRecords} objek pajak'),
              Text('• Sudah Bayar: ${outcome.sudahBayarCount} NOP'),
              Text('• Belum Bayar: ${outcome.belumBayarCount} NOP'),
              Text(
                '• Target Pemda (>= 2 Juta): ${outcome.targetPemdaCount} NOP',
              ),
              Text('• Terdeteksi: ${outcome.totalBloks} Blok aktif'),
              const SizedBox(height: 12),
              const Text(
                'Data baru telah aktif langsung di aplikasi. Anda dapat langsung membuka Buku Catatan Blok atau Pantauan Grafik.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup & Selesai'),
            ),
          ],
        ),
      );
    } else if (outcome.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proses generate DHKP dibatalkan.')),
      );
    } else {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 48,
          ),
          title: const Text('Gagal Generate DHKP'),
          content: Text(
            outcome.errorMessage ?? 'Terjadi kesalahan tidak dikenal.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isProcessing) {
      final p = _progress;
      final ratio = p?.ratio ?? 0.0;
      final status =
          p?.currentStatus ?? 'Menghubungkan ke Portal Staf Bapenda...';

      return AlertDialog(
        title: const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Menyusun DHKP Master...')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: ratio > 0 ? ratio : null),
            const SizedBox(height: 12),
            Text(status, style: const TextStyle(fontSize: 13)),
            if (p != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tercatat: ${p.belumBayarCount} Belum Bayar • ${p.sudahBayarCount} Sudah Bayar',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _cancelled = true;
              });
            },
            child: const Text('Batalkan', style: TextStyle(color: Colors.red)),
          ),
        ],
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generate DHKP Baru (Timpa)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Unduh seluruh SPPT dari Portal Staf & susun master DHKP baru.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // FORM BODY
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TOMBOL MUAT DARI BERKAS MANIFEST
                      OutlinedButton.icon(
                        onPressed: _pickManifestFile,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text(
                          '📁 Muat Otomatis dari Berkas .dkhp / .dat (Hanya Ambil Manifest)',
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // TAHUN PAJAK (RENTANG TAHUN) & KECAMATAN
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _tahunAwalController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Tahun Awal',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          hintText: '2015',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Wajib'
                                            : null,
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text(
                                        's/d',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _tahunAkhirController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Tahun Akhir',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          hintText: '2026',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Wajib'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _tahunAwalController.text =
                                              '${DateTime.now().year}';
                                          _tahunAkhirController.text =
                                              '${DateTime.now().year}';
                                        });
                                      },
                                      child: Chip(
                                        label: Text(
                                          'Tahun Ini (${DateTime.now().year})',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _tahunAwalController.text = '2015';
                                          _tahunAkhirController.text =
                                              '${DateTime.now().year}';
                                        });
                                      },
                                      child: Chip(
                                        label: Text(
                                          '2015 - ${DateTime.now().year}',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _kecamatanController,
                              decoration: const InputDecoration(
                                labelText: 'Kecamatan',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Wajib diisi'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // DESA & KOORDINAT KANTOR
                      TextFormField(
                        controller: _desaController,
                        decoration: const InputDecoration(
                          labelText: 'Desa / Kelurahan',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _kantorLatController,
                              decoration: const InputDecoration(
                                labelText: 'Latitude Kantor Desa',
                                border: OutlineInputBorder(),
                                isDense: true,
                                hintText: '-6.763587',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _kantorLngController,
                              decoration: const InputDecoration(
                                labelText: 'Longitude Kantor Desa',
                                border: OutlineInputBorder(),
                                isDense: true,
                                hintText: '107.238769',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // DAFTAR DUSUN & BLOK
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Pembagian Dusun & Blok',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addDusun,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Dusun'),
                          ),
                        ],
                      ),
                      Text(
                        'Tuliskan nama dusun, koordinat fokus, dan daftar bloknya (pisahkan dengan koma).',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // KARTU FORM DUSUN
                      ..._dusunEntries.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Dusun #${idx + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (_dusunEntries.length > 1)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Hapus Dusun',
                                        onPressed: () => _removeDusun(idx),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: item.nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Nama Dusun',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    hintText: 'Dusun ${idx + 1}',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: item.latController,
                                        decoration: const InputDecoration(
                                          labelText: 'Lat Fokus',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: item.lngController,
                                        decoration: const InputDecoration(
                                          labelText: 'Lng Fokus',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: item.bloksController,
                                  decoration: const InputDecoration(
                                    labelText: 'Daftar Blok (pisahkan koma)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    hintText: '1, 2, 3, 4, 11, 12, ...',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),

                      // OPSI FILTER CAKUPAN BLOK BERDASARKAN DUSUN
                      Material(
                        color: isDark
                            ? Colors.grey.shade900
                            : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text(
                              'Hanya ambil blok yang terdaftar pada form dusun di atas',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              'Jika dicentang dan Anda hanya mengisi Dusun 1, maka hanya data blok Dusun 1 yang disimpan. '
                              'Bila tidak dicentang, seluruh blok se-desa akan diambil.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                            value: _filterByDusunBlocks,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _filterByDusunBlocks = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // INFO BUKU 1, 2, 3 & TARGET PEMDA
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.shade700.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              color: Colors.amber.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Khusus Buku 1, 2, 3 (PBB Pedesaan s/d Rp 2.000.000): Data diambil langsung dari tabel Bapenda dengan metode santai/lambat (jeda aman) agar stabil dan tidak terputus. Target Pemda (>= Rp 2.000.000) otomatis dipisahkan.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // WARNING TIMPA
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mode Timpa: Database DHKP aktif akan digantikan dengan data baru hasil unduh dari Portal Staf. Salinan cadangan (backup) otomatis dibuat.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // FOOTER ACTIONS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                    ),
                    onPressed: _startGenerate,
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('Mulai Generate & Timpa DHKP'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
