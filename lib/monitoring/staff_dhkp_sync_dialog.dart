import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../batch_notification_service.dart';
import '../blok_data_store.dart';
import '../blok_record.dart';
import '../dhkp/blok_catatan_models.dart';
import '../nop_helper.dart';
import '../staff_portal_client.dart';
import 'staff_dhkp_sync_manager.dart';
import 'staff_dhkp_sync_service.dart';

/// Menampilkan dialog pemilih Blok & Tahun untuk memulai sinkronisasi langsung dari Portal Staf
Future<void> showStaffDhkpSyncDialog(
  BuildContext context, {
  required StaffPortalClient client,
  String kelurahan = '3205200004',
  String kecamatan = '3205200',
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _StaffDhkpSyncConfigDialog(
      client: client,
      kelurahan: kelurahan,
      kecamatan: kecamatan,
    ),
  );
}

class _StaffDhkpSyncConfigDialog extends StatefulWidget {
  final StaffPortalClient client;
  final String kelurahan;
  final String kecamatan;

  const _StaffDhkpSyncConfigDialog({
    required this.client,
    required this.kelurahan,
    required this.kecamatan,
  });

  @override
  State<_StaffDhkpSyncConfigDialog> createState() =>
      _StaffDhkpSyncConfigDialogState();
}

class _StaffDhkpSyncConfigDialogState
    extends State<_StaffDhkpSyncConfigDialog> {
  static const String _semuaBlokKey = 'ALL';

  late String _selectedTahun;
  String _selectedBlok = _semuaBlokKey;
  StaffSyncMode _selectedMode = StaffSyncMode.full;

  bool _loading = true;
  List<String> _bloks = [];
  List<BlokRecord> _allRecords = [];

  // Statistik blok terpilih di lokal DHKP
  int _localTotalCount = 0;
  int _localPaidCount = 0;
  int _localUnpaidCount = 0;

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    _selectedTahun = '$currentYear';
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final bloks = await BlokDataStore.instance.blokList();
    final records = await BlokDataStore.instance.loadAll();

    if (!mounted) return;
    setState(() {
      _bloks = bloks;
      _allRecords = records;
      _loading = false;
      _computeLocalStats();
    });
  }

  void _computeLocalStats() {
    final yearRecords = _allRecords
        .where((r) => r.tahunBayar.isEmpty || r.tahunBayar == _selectedTahun);

    final filtered = _selectedBlok == _semuaBlokKey
        ? yearRecords.toList()
        : yearRecords.where((r) => nopBlok(r.nop) == _selectedBlok.padLeft(3, '0')).toList();

    _localTotalCount = filtered.length;
    _localPaidCount = filtered.where((r) => r.isPaid).length;
    _localUnpaidCount = filtered.where((r) => !r.isPaid).length;
  }

  void _onTahunChanged(String? val) {
    if (val == null) return;
    setState(() {
      _selectedTahun = val;
      _computeLocalStats();
    });
  }

  void _onBlokChanged(String? val) {
    if (val == null) return;
    setState(() {
      _selectedBlok = val;
      _computeLocalStats();
    });
  }

  void _startSync() {
    Navigator.of(context).pop();

    final List<String> targetBloks = _selectedBlok == _semuaBlokKey
        ? (_bloks.isNotEmpty ? _bloks : ['001'])
        : [_selectedBlok];

    final blokLabel = _selectedBlok == _semuaBlokKey
        ? 'Semua Blok (${targetBloks.length} blok)'
        : 'Blok ${int.tryParse(_selectedBlok) ?? _selectedBlok}';

    StaffDhkpSyncManager.instance.startSync(
      context: context,
      client: widget.client,
      tahun: _selectedTahun,
      bloks: targetBloks,
      kelurahan: widget.kelurahan,
      kecamatan: widget.kecamatan,
      blokLabel: blokLabel,
      mode: _selectedMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.cloud_sync_rounded,
              color: Colors.teal.shade700,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Sinkronkan Status ke DHKP',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Menarik data lunas dan mendeteksi SPPT baru langsung dari tabel server Bapenda untuk memperbarui DHKP lokal kantor secara instan.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Pilihan Tahun Pajak
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedTahun,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tahun Pajak',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            for (final y in availableDhkpYears())
                              DropdownMenuItem(value: '$y', child: Text('$y')),
                          ],
                          onChanged: _onTahunChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Pilihan Blok
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedBlok,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Pilihan Blok',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: _semuaBlokKey,
                              child: Text(
                                _bloks.isNotEmpty
                                    ? 'Semua Blok (${_bloks.length})'
                                    : 'Semua Blok',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            for (final b in _bloks)
                              DropdownMenuItem(
                                value: b,
                                child: Text(
                                  'Blok ${int.tryParse(b) ?? b}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _onBlokChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<StaffSyncMode>(
                    initialValue: _selectedMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cakupan Sinkronisasi',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      for (final m in StaffSyncMode.values)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedMode = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Kotak Status Konteks DHKP Tersimpan Saat Ini
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.teal.shade900.withValues(alpha: 0.25)
                          : Colors.teal.shade50.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.teal.shade700
                            : Colors.teal.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.storage_rounded,
                              size: 16,
                              color: isDark
                                  ? Colors.teal.shade200
                                  : Colors.teal.shade800,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Data DHKP Tersimpan Saat Ini:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.teal.shade200
                                      : Colors.teal.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildMiniStat('Total SPPT', '$_localTotalCount', Colors.blue),
                            _buildMiniStat('Sudah Bayar', '$_localPaidCount', Colors.green),
                            _buildMiniStat('Belum Bayar', '$_localUnpaidCount', Colors.orange),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Jika server mendeteksi SPPT/NOP baru yang belum ada di DHKP, otomatis ditambahkan sebagai data baru.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _startSync,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Mulai Sinkronisasi'),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, MaterialColor color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color.shade700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

/// Menampilkan modal lembaran progres sinkronisasi DHKP berjalan
Future<void> showStaffDhkpSyncRunningSheetModal(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _StaffDhkpSyncRunningSheet(),
  );
}

/// Modal Lembaran Progres Sinkronisasi Berjalan
class _StaffDhkpSyncRunningSheet extends StatelessWidget {
  const _StaffDhkpSyncRunningSheet();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffDhkpSyncManager.instance,
      builder: (context, _) {
        final mgr = StaffDhkpSyncManager.instance;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        final isCompleted = mgr.isCompleted;
        final isPaused = mgr.isPaused;
        final progress = mgr.progress;
        final outcome = mgr.outcome;

        final progressRatio = progress?.ratio ?? 0.0;
        final currentBlok = progress?.currentBlok ?? 'Memulai...';
        final updatedPaid =
            outcome?.updatedPaidCount ?? progress?.updatedPaidCount ?? 0;
        final newSppt =
            outcome?.newSpptCount ?? progress?.newSpptCount ?? 0;
        final checked =
            outcome?.totalCheckedRows ?? progress?.totalCheckedRows ?? 0;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (mgr.isCompleted) {
              mgr.hideSheet(context);
              mgr.dismiss();
            } else {
              mgr.hideSheet(context);
            }
          },
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green.shade50
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.check_circle_outline_rounded
                              : Icons.sync_rounded,
                          color: isCompleted
                              ? Colors.green.shade700
                              : Colors.teal.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCompleted
                                  ? 'Sinkronisasi Selesai!'
                                  : 'Menyinkronkan ke DHKP...',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${mgr.blokLabel ?? "DHKP"} • Tahun ${mgr.tahun ?? ""}',
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
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (!isCompleted) ...[
                    // Progress Bar & Keterangan Blok Aktif
                    LinearProgressIndicator(
                      value: progressRatio.clamp(0.0, 1.0),
                      backgroundColor:
                          isDark ? Colors.white12 : Colors.grey.shade200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.teal.shade600),
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            currentBlok,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(progressRatio * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Banner Selesai
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: Colors.green.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Total $updatedPaid NOP diperbarui menjadi Lunas dan $newSppt NOP baru terdeteksi. Seluruh grafik DHKP langsung otomatis ter-update.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Kotak Kartu Hasil Real-Time
                  Row(
                    children: [
                      Expanded(
                        child: _buildResultStatCard(
                          label: 'Lunas Baru',
                          value: '$updatedPaid NOP',
                          color: Colors.green,
                          icon: Icons.check_circle_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildResultStatCard(
                          label: 'SPPT Baru Terbit',
                          value: '$newSppt NOP',
                          color: Colors.blue,
                          icon: Icons.fiber_new_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildResultStatCard(
                          label: 'Diperiksa',
                          value: '$checked Baris',
                          color: Colors.purple,
                          icon: Icons.list_alt_rounded,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (!isCompleted) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: Colors.teal.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Proses ini berjalan di latar belakang. Anda dapat meminimalkan aplikasi atau menyembunyikan sheet ini.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => mgr.togglePause(),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  isPaused ? Colors.teal.shade100 : null,
                            ),
                            icon: Icon(
                              isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              size: 18,
                            ),
                            label: Text(isPaused ? 'Lanjutkan' : 'Jeda'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => mgr.hideSheet(context),
                            icon: const Icon(
                              Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            label: const Text('Sembunyikan'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => mgr.cancelSync(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                            ),
                            icon: const Icon(Icons.stop_rounded, size: 18),
                            label: const Text('Batalkan'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: () {
                              final out = mgr.outcome;
                              final parentContext =
                                  rootNavigatorKey.currentContext ?? context;
                              mgr.hideSheet(context);
                              mgr.dismiss();
                              if (out != null) {
                                showStaffDhkpSyncReportDialog(
                                    parentContext, out);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon:
                                const Icon(Icons.assignment_outlined, size: 18),
                            label: const Text('Lihat Laporan Rinci'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () {
                              mgr.hideSheet(context);
                              mgr.dismiss();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Tutup'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultStatCard({
    required String label,
    required String value,
    required MaterialColor color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? color.shade900.withValues(alpha: 0.3)
            : color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? color.shade700 : color.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color.shade700),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : color.shade900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Menampilkan popup laporan rinci audit sinkronisasi Portal Staf
Future<void> showStaffDhkpSyncReportDialog(
  BuildContext context,
  StaffDhkpSyncOutcome outcome,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _StaffDhkpSyncReportDialog(outcome: outcome),
  );
}

class _StaffDhkpSyncReportDialog extends StatefulWidget {
  final StaffDhkpSyncOutcome outcome;

  const _StaffDhkpSyncReportDialog({required this.outcome});

  @override
  State<_StaffDhkpSyncReportDialog> createState() =>
      _StaffDhkpSyncReportDialogState();
}

class _StaffDhkpSyncReportDialogState extends State<_StaffDhkpSyncReportDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _copyAll(List<String> nops, String label) {
    if (nops.isEmpty) return;
    Clipboard.setData(ClipboardData(text: nops.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label (${nops.length} NOP) berhasil disalin.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySummary() {
    final o = widget.outcome;
    final text = StringBuffer()
      ..writeln('=== Laporan Sinkronisasi Portal Staf Bapenda ===')
      ..writeln('Wilayah: ${o.blokLabel}')
      ..writeln('Tahun Pajak: ${o.tahun}')
      ..writeln('Total Baris Diperiksa: ${o.totalCheckedRows}')
      ..writeln('NOP Baru Lunas: ${o.updatedPaidCount}')
      ..writeln('NOP Baru Terdeteksi: ${o.newSpptCount}')
      ..writeln('Status: ${o.errorMessage ?? "Sukses"}');

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ringkasan sinkronisasi disalin ke papan klip.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final o = widget.outcome;

    final newItems = o.newRecords.isNotEmpty
        ? o.newRecords
        : o.newNops
            .map((nop) => BlokRecord(
                  nop: nop,
                  namaWajibPajak: 'WP Baru (Bapenda)',
                  tahunBayar: o.tahun,
                  tanggalBayar: '',
                  statusBayar: 'Sudah Bayar',
                ))
            .toList();

    final paidItems = o.updatedRecords.isNotEmpty
        ? o.updatedRecords
        : o.updatedNops
            .map((nop) => BlokRecord(
                  nop: nop,
                  namaWajibPajak: 'Wajib Pajak',
                  tahunBayar: o.tahun,
                  tanggalBayar: '',
                  statusBayar: 'Sudah Bayar',
                ))
            .toList();

    final query = _searchQuery.trim().toLowerCase();
    final filteredNew = query.isEmpty
        ? newItems
        : newItems
            .where((r) =>
                r.nop.toLowerCase().contains(query) ||
                r.namaWajibPajak.toLowerCase().contains(query))
            .toList();

    final filteredPaid = query.isEmpty
        ? paidItems
        : paidItems
            .where((r) =>
                r.nop.toLowerCase().contains(query) ||
                r.namaWajibPajak.toLowerCase().contains(query))
            .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Dialog
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.assessment_outlined,
                        color: Colors.teal,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Laporan Hasil Sinkronisasi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${o.blokLabel} • Tahun Pajak ${o.tahun}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Chip ringkasan statistik
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildBadge(
                        label: 'Baru Lunas',
                        count: o.updatedPaidCount,
                        color: Colors.green,
                        icon: Icons.check_circle_rounded,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBadge(
                        label: 'NOP Baru Terbit',
                        count: o.newSpptCount,
                        color: Colors.blue,
                        icon: Icons.fiber_new_rounded,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBadge(
                        label: 'Diperiksa',
                        count: o.totalCheckedRows,
                        color: Colors.purple,
                        icon: Icons.search_rounded,
                        isDark: isDark,
                        unit: 'baris',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Search Filter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Cari NOP atau Nama Wajib Pajak...',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              const SizedBox(height: 8),

              // Tab Bar
              TabBar(
                labelColor: Colors.teal.shade700,
                unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
                indicatorColor: Colors.teal.shade700,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.fiber_new_rounded, size: 18),
                    text: 'NOP Baru Terbit (${filteredNew.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    text: 'NOP Baru Lunas (${filteredPaid.length})',
                  ),
                ],
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  children: [
                    _buildRecordList(
                      records: filteredNew,
                      allNops: o.newNops,
                      isPaidList: false,
                      emptyTitle: 'Tidak ada NOP baru terbit',
                      emptySubtitle:
                          'Semua data NOP yang diperiksa sudah terdaftar di DHKP lokal.',
                      isDark: isDark,
                    ),
                    _buildRecordList(
                      records: filteredPaid,
                      allNops: o.updatedNops,
                      isPaidList: true,
                      emptyTitle: 'Tidak ada NOP yang baru lunas',
                      emptySubtitle:
                          'Tidak ditemukan perubahan pelunasan baru pada periode sinkronisasi ini.',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Footer Action
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _copySummary,
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: const Text('Salin Ringkasan'),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Selesai'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required int count,
    required MaterialColor color,
    required IconData icon,
    required bool isDark,
    String unit = 'NOP',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? color.shade900.withValues(alpha: 0.25)
            : color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? color.shade700 : color.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color.shade700),
              const SizedBox(width: 4),
              Text(
                '$count $unit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : color.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordList({
    required List<BlokRecord> records,
    required List<String> allNops,
    required bool isPaidList,
    required String emptyTitle,
    required String emptySubtitle,
    required bool isDark,
  }) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPaidList ? Icons.check_circle_outline : Icons.info_outline,
                size: 40,
                color: isDark ? Colors.white30 : Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                emptyTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Menampilkan ${records.length} objek pajak',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              TextButton.icon(
                onPressed: () => _copyAll(
                  records.map((r) => r.nop).toList(),
                  isPaidList
                      ? 'Daftar NOP Baru Lunas'
                      : 'Daftar NOP Baru Terbit',
                ),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text(
                  'Salin Semua NOP',
                  style: TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (ctx, idx) {
              final r = records[idx];
              final formattedNop = r.formattedNop;
              final pokokText = r.jumlahPbb.isNotEmpty
                  ? 'Rp ${formatRibuan(r.jumlahPbbValue)}'
                  : '-';

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isPaidList
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isPaidList
                            ? Icons.check_circle_outline
                            : Icons.fiber_new_rounded,
                        color: isPaidList
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedNop,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.namaWajibPajak,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'Pokok: $pokokText',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.teal.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (r.tanggalBayar.isNotEmpty) ...[
                                const Text(' • ',
                                    style: TextStyle(fontSize: 11)),
                                Text(
                                  'Bayar: ${r.tanggalBayar}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Salin NOP',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: r.nop));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('NOP ${r.nop} disalin.'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
