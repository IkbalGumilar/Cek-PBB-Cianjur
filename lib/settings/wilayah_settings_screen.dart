import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cianjur_wilayah_data.dart';
import '../nop_helper.dart';

/// Halaman Pengaturan Wilayah Kerja & Profil Desa.
/// Memungkinkan petugas mengubah Kecamatan dan Desa penugasan tanpa mereset
/// data aplikasi ataupun memicu alur setup wizard baru.
class WilayahSettingsScreen extends StatefulWidget {
  const WilayahSettingsScreen({super.key});

  @override
  State<WilayahSettingsScreen> createState() => _WilayahSettingsScreenState();
}

class _WilayahSettingsScreenState extends State<WilayahSettingsScreen> {
  static const _prefDesaNameKey = 'startup_desa_name';
  static const _prefKecCodeKey = 'startup_kec_code';
  static const _prefKelCodeKey = 'startup_kel_code';
  static const _prefKecNameKey = 'startup_kec_name';

  String? _selectedKecCode;
  String? _selectedDesaCode;
  bool _isManualDesa = false;
  bool _saving = false;

  late final TextEditingController _desaNameController;
  late final TextEditingController _kelCodeController;

  @override
  void initState() {
    super.initState();
    _desaNameController = TextEditingController(text: activeDesaName);
    _kelCodeController = TextEditingController(text: activeKelurahanCode);
    _selectedKecCode = activeKecamatanCode.isNotEmpty ? activeKecamatanCode : null;
    _selectedDesaCode = activeKelurahanCode.isNotEmpty ? activeKelurahanCode : null;
    _syncDesaSelection();
  }

  @override
  void dispose() {
    _desaNameController.dispose();
    _kelCodeController.dispose();
    super.dispose();
  }

  void _syncDesaSelection() {
    if (_selectedKecCode == null) return;
    final kec = findKecamatanByCode(_selectedKecCode!);
    if (kec == null || kec.desaList.isEmpty) {
      _isManualDesa = true;
      _selectedDesaCode = 'custom';
      return;
    }

    if (_selectedDesaCode == null) return;

    final hasMatchingDesa =
        kec.desaList.any((d) => d.code == _selectedDesaCode);
    if (!hasMatchingDesa) {
      _selectedDesaCode = null;
      _desaNameController.text = '';
      _kelCodeController.text = '';
      _isManualDesa = false;
    } else {
      _isManualDesa = false;
      final desa = kec.desaList.firstWhere((d) => d.code == _selectedDesaCode);
      _desaNameController.text = desa.name;
      _kelCodeController.text = desa.code;
    }
  }

  String get _calculatedPrefix {
    if (_selectedKecCode == null || _kelCodeController.text.trim().isEmpty) {
      return '32.05.---.---';
    }
    final cleanKel = _kelCodeController.text
        .replaceAll(RegExp(r'[^0-9]'), '')
        .padLeft(3, '0');
    return calculateNopPrefix(_selectedKecCode!, cleanKel);
  }

  Future<void> _saveWilayah() async {
    if (_selectedKecCode == null) return;
    setState(() => _saving = true);
    try {
      final kec = findKecamatanByCode(_selectedKecCode!);
      final kecName = kec?.name ?? 'Kec. $_selectedKecCode';
      final desaName = _desaNameController.text.trim().toUpperCase();
      final kelCode = _kelCodeController.text.trim().padLeft(3, '0');

      setActiveWilayah(
        kecCode: _selectedKecCode!,
        kelCode: kelCode,
        desaName: desaName,
        kecName: kecName,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKecCodeKey, _selectedKecCode!);
      await prefs.setString(_prefDesaNameKey, desaName);
      await prefs.setString(_prefKelCodeKey, kelCode);
      await prefs.setString(_prefKecNameKey, kecName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wilayah kerja berhasil diubah ke Kec. $kecName - Desa $desaName',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan perubahan wilayah: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentKec = _selectedKecCode != null
        ? findKecamatanByCode(_selectedKecCode!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wilayah Kerja & Profil Desa'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Card 1: Status Wilayah Aktif Saat Ini
            Card(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.domain_rounded,
                        color: scheme.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wilayah Aktif Saat Ini',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kec. $activeKecamatanName • Desa $activeDesaName',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Prefix NOP: $activeNopPrefix (Format: 32.05.$activeKecamatanCode.$activeKelurahanCode)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Card 2: Form Ubah Wilayah
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ubah Wilayah Penugasan',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pilih Kecamatan dan Desa/Kelurahan penugasan Anda. Pengaturan ini akan memperbarui prefix pencarian online di menu Cek Tagihan & Status Bayar.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Dropdown Kecamatan
                    DropdownButtonFormField<String>(
                      key: const ValueKey('settings_dropdown_kecamatan'),
                      initialValue: _selectedKecCode,
                      hint: const Text('Pilih Kecamatan...'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Kecamatan *',
                        prefixIcon: Icon(Icons.apartment_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: cianjurWilayahCatalog.map((kec) {
                        return DropdownMenuItem<String>(
                          value: kec.code,
                          child: Text(
                            'Kec. ${kec.name} (${kec.code})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedKecCode = val;
                            _selectedDesaCode = null;
                            _desaNameController.text = '';
                            _kelCodeController.text = '';
                            _isManualDesa = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Dropdown Desa / Kelurahan
                    if (currentKec != null && currentKec.desaList.isNotEmpty && !_isManualDesa) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey('settings_dropdown_desa_$_selectedKecCode'),
                        initialValue: _selectedDesaCode,
                        hint: const Text('Pilih Desa / Kelurahan...'),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Desa / Kelurahan *',
                          prefixIcon: Icon(Icons.location_city_rounded),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          ...currentKec.desaList.map((desa) {
                            return DropdownMenuItem<String>(
                              value: desa.code,
                              child: Text(
                                '${desa.name} (Kode: ${desa.code})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                          const DropdownMenuItem<String>(
                            value: 'custom',
                            child: Text('✏️ Masukkan Kode / Nama Lainnya...'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == 'custom') {
                            setState(() => _isManualDesa = true);
                          } else if (val != null) {
                            final d = currentKec.desaList.firstWhere(
                              (item) => item.code == val,
                              orElse: () => currentKec.desaList.first,
                            );
                            setState(() {
                              _selectedDesaCode = val;
                              _desaNameController.text = d.name;
                              _kelCodeController.text = d.code;
                            });
                          }
                        },
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _desaNameController,
                              decoration: const InputDecoration(
                                labelText: 'Nama Desa / Kelurahan',
                                prefixIcon: Icon(Icons.badge_outlined),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _kelCodeController,
                              keyboardType: TextInputType.number,
                              maxLength: 3,
                              decoration: const InputDecoration(
                                labelText: 'Kode (3 Digit)',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      if (currentKec != null && currentKec.desaList.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Kembali ke Daftar Desa'),
                            onPressed: () {
                              setState(() {
                                _isManualDesa = false;
                                _syncDesaSelection();
                              });
                            },
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Badge Live Preview NOP Prefix
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.pin_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Prefix NOP 10 Digit:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _calculatedPrefix,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Card 3: Informasi Data Aman (Bukan Reset)
            Card(
              elevation: 0,
              color: Colors.blue.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Mengubah wilayah kerja di sini hanya memperbarui identitas kecamatan dan desa untuk pencarian online. Data DHKP, catatan warga, dan setoran yang sudah tersimpan tidak akan hilang atau tereset.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Builder(
              builder: (context) {
                final bool isWilayahValid = _selectedKecCode != null &&
                    ((!_isManualDesa &&
                            _selectedDesaCode != null &&
                            _selectedDesaCode != 'custom') ||
                        (_isManualDesa &&
                            _desaNameController.text.trim().isNotEmpty &&
                            _kelCodeController.text.trim().isNotEmpty));

                return SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const ValueKey('btn_simpan_wilayah_settings'),
                    onPressed: (_saving || !isWilayahValid) ? null : _saveWilayah,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _saving ? 'Menyimpan...' : 'Simpan Perubahan Wilayah',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
