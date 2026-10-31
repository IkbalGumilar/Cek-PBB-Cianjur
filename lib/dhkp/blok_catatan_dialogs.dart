import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../blok_batch_check_tracker.dart';
import '../blok_record.dart';
import '../blok_report_exporter.dart';
import '../dkhp_package_helper.dart';
import '../dusun_data.dart';
import 'blok_catatan_models.dart';

Future<String?> showEditCatatanDialog(
  BuildContext context,
  BlokRecord record,
) async {
  final controller = TextEditingController(text: record.catatan);

  final updated = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit_note, color: Colors.blue),
          SizedBox(width: 8),
          Text('Catatan Petugas', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.namaWajibPajak,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Text(
            'NOP: ${record.formattedNop} (Blok ${record.blok} No ${record.wilayah})',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: 'Catatan Petugas (Anomali / Info Khusus)',
              hintText:
                  'Misal: Bangunan sudah dibongkar, NOP ganda, pemilik pindah ke luar kota, tanah sengketa...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.save),
          label: const Text('Simpan'),
        ),
      ],
    ),
  );

  final result = updated == true ? controller.text.trim() : null;
  controller.dispose();
  return result;
}

Future<void> showRincianObjekDialog(
  BuildContext context, {
  required BlokRecord record,
  required VoidCallback onCekStatusBayar,
  required VoidCallback onCekTagihan,
  required Future<void> Function() onEditRincian,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: Theme.of(context).colorScheme.primary,
                  child: Row(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'INFORMASI DATA PEMBAYARAN',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRincianItem(
                                    'Nomor Objek Pajak (NOP)',
                                    record.formattedNop,
                                    isBold: true,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Luas Bumi',
                                    record.luasBumi.isNotEmpty
                                        ? record.luasBumi
                                        : '-',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Luas Bangunan',
                                    record.luasBangunan.isNotEmpty
                                        ? record.luasBangunan
                                        : '-',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Kecamatan Objek Pajak',
                                    record.kecamatan,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Alamat Objek Pajak',
                                    record.alamatObjek.isNotEmpty
                                        ? record.alamatObjek
                                        : '-',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Nama Wajib Pajak',
                                    record.namaWajibPajak,
                                    isBold: true,
                                    textColor: isDark
                                        ? Colors.lightBlueAccent
                                        : Colors.blue.shade900,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Alamat Wajib Pajak',
                                    record.alamatWp.isNotEmpty
                                        ? record.alamatWp
                                        : '-',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRincianItem(
                                    'Tahun Ketetapan',
                                    record.tahunBayar,
                                    isBold: true,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'NJOP Bumi',
                                    record.njopBumi.isNotEmpty
                                        ? record.njopBumi
                                        : '-',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'NJOP Bangunan',
                                    record.njopBangunan.isNotEmpty
                                        ? record.njopBangunan
                                        : '-',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Kelurahan Objek Pajak',
                                    record.kelurahan,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'RT Objek Pajak',
                                    record.rtObjek.isNotEmpty
                                        ? record.rtObjek
                                        : '-',
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Pokok / Ketetapan PBB',
                                    record.jumlahPbb.isNotEmpty
                                        ? record.jumlahPbb
                                        : '-',
                                    isBold: true,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildRincianItem(
                                    'Status Bayar',
                                    record.statusBayar,
                                    textColor: record.isPaid
                                        ? Colors.green
                                        : Colors.orange.shade800,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        if (record.isTargetPemda)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.flag, size: 16, color: Colors.red),
                                SizedBox(width: 6),
                                Text(
                                  'TARGET KHUSUS PEMDA (Prioritas Penagihan)',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (record.catatan.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade700),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.amber.shade900,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Catatan: ${record.catatan}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!record.isPaid)
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.fact_check_outlined,
                            size: 16,
                            color: Colors.teal,
                          ),
                          label: const Text('Cek Status Bayar'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            onCekStatusBayar();
                          },
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('Cek Tagihan'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onCekTagihan();
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit / Sesuaikan Pemilik'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await onEditRincian();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildRincianItem(
  String label,
  String value, {
  bool isBold = false,
  Color? textColor,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.grey,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          color: textColor,
        ),
      ),
    ],
  );
}

Future<EditRincianResult?> showEditRincianDialog(
  BuildContext context,
  BlokRecord record,
) async {
  final namaController = TextEditingController(text: record.namaWajibPajak);
  final alamatObjekController = TextEditingController(text: record.alamatObjek);
  final alamatWpController = TextEditingController(text: record.alamatWp);

  final updated = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Edit Nama & Alamat',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOP: ${record.formattedNop}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: namaController,
              decoration: const InputDecoration(
                labelText: 'Nama Wajib Pajak / Pemilik Sekarang',
                helperText: 'Sesuaikan nama dengan pemilik fisik saat ini',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: alamatObjekController,
              decoration: const InputDecoration(
                labelText: 'Alamat Objek Pajak (OP)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: alamatWpController,
              decoration: const InputDecoration(
                labelText: 'Alamat Wajib Pajak (WP)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Simpan Perubahan'),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  EditRincianResult? result;
  if (updated == true) {
    result = EditRincianResult(
      namaWajibPajak: namaController.text.trim().isEmpty
          ? record.namaWajibPajak
          : namaController.text.trim(),
      alamatObjek: alamatObjekController.text.trim(),
      alamatWp: alamatWpController.text.trim(),
    );
  }
  namaController.dispose();
  alamatObjekController.dispose();
  alamatWpController.dispose();
  return result;
}

Future<List<BlokRecord>?> showPilihBlokCekMassalDialog(
  BuildContext context, {
  required List<String> availableBloks,
  required Map<String, List<BlokRecord>> recordsByBlok,
  required int? selectedWilayah,
}) {
  return showDialog<List<BlokRecord>>(
    context: context,
    builder: (ctx) {
      String? currentBlok;
      final scheme = Theme.of(context).colorScheme;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          final blokRecords = currentBlok != null
              ? (recordsByBlok[currentBlok] ?? [])
              : <BlokRecord>[];
          final totalCount = blokRecords.length;
          final paidCount = blokRecords.where((r) => r.isPaid).length;
          final unpaidList = blokRecords.where((r) => !r.isPaid).toList();
          final checkedTodayList = unpaidList
              .where(
                (r) => BlokBatchCheckTracker.instance.isCheckedToday(r.nop),
              )
              .toList();
          final remainingToCheck = unpaidList
              .where(
                (r) => !BlokBatchCheckTracker.instance.isCheckedToday(r.nop),
              )
              .toList();

          final checkedTodayCount = checkedTodayList.length;
          final remainingCount = remainingToCheck.length;
          final isAllPaid = totalCount > 0 && unpaidList.isEmpty;
          final isFullyCheckedToday =
              unpaidList.isNotEmpty && remainingCount == 0;
          final isPartialChecked = checkedTodayCount > 0 && remainingCount > 0;

          final currentBlokInt = currentBlok != null
              ? (int.tryParse(currentBlok!) ?? currentBlok)
              : null;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.fact_check_outlined, color: Colors.teal),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pilih Blok untuk Cek Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              DusunData.instance.isDusunLocked
                                  ? 'Wilayah Terkunci: Dusun ${DusunData.instance.lockedDusunNumber} (${availableBloks.length} Blok)'
                                  : (selectedWilayah != null
                                        ? 'Wilayah: Dusun $selectedWilayah (${availableBloks.length} Blok)'
                                        : 'Wilayah: 1 Desa / Semua Wilayah (${availableBloks.length} Blok 1-41)'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Mau cek blok yang mana?',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: currentBlok,
                      isExpanded: true,
                      hint: const Text(
                        '-- Pilih Nomor Blok --',
                        style: TextStyle(fontSize: 14),
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(
                          Icons.grid_view_rounded,
                          size: 20,
                        ),
                      ),
                      items: availableBloks.map((b) {
                        final bRecs = recordsByBlok[b] ?? [];
                        final bUnpaid = bRecs.where((r) => !r.isPaid).length;
                        final bDoneToday =
                            bUnpaid > 0 &&
                            bRecs
                                    .where(
                                      (r) =>
                                          !r.isPaid &&
                                          BlokBatchCheckTracker.instance
                                              .isCheckedToday(r.nop),
                                    )
                                    .length ==
                                bUnpaid;

                        final bInt = int.tryParse(b) ?? b;
                        return DropdownMenuItem<String>(
                          value: b,
                          child: Row(
                            children: [
                              Text(
                                'Blok $bInt',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  bDoneToday
                                      ? '• Sudah dicek'
                                      : (bUnpaid == 0
                                            ? '• Semua lunas'
                                            : '• $bUnpaid belum bayar'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: bDoneToday
                                        ? Colors.grey
                                        : (bUnpaid == 0
                                              ? Colors.green
                                              : Colors.orange),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            currentBlok = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    if (currentBlok == null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade800,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Blok Belum Dipilih',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Silakan pilih salah satu nomor blok pada menu di atas terlebih dahulu untuk melihat data dan memeriksa status bayar.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Card(
                        elevation: 0,
                        color: scheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Data Objek Pajak Blok $currentBlokInt',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatColumn(
                                    'Total NOP',
                                    '$totalCount',
                                    scheme.onSurface,
                                  ),
                                  _buildStatColumn(
                                    'Sudah Bayar',
                                    '$paidCount',
                                    Colors.green,
                                  ),
                                  _buildStatColumn(
                                    'Belum Bayar',
                                    '${unpaidList.length}',
                                    Colors.orange,
                                  ),
                                ],
                              ),
                              const Divider(height: 18),
                              if (isAllPaid) ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.green.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.green,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Semua Lunas: Seluruh NOP pada blok ini sudah berstatus Sudah Bayar. Tidak ada tunggakan yang perlu dicek.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isFullyCheckedToday) ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.amber.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.amber.shade800,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Blok ini sudah dicek, coba lagi besok',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isPartialChecked) ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.blue.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.pending_actions,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '$checkedTodayCount NOP sudah diperiksa hari ini. '
                                          'Tersisa $remainingCount NOP Belum Bayar yang belum selesai dicek.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 18,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Ditemukan $remainingCount NOP Belum Bayar yang siap diperiksa. '
                                          'NOP yang sudah bayar tidak akan dicek lagi.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  currentBlok == null
                      ? 'Pilih Blok Terlebih Dahulu'
                      : (isFullyCheckedToday
                            ? 'Sudah Dicek (Coba Lagi Besok)'
                            : (isAllPaid
                                  ? 'Semua Lunas'
                                  : (isPartialChecked
                                        ? 'Lanjutkan Cek Sisa ($remainingCount NOP)'
                                        : 'Mulai Cek ($remainingCount NOP)'))),
                ),
                onPressed:
                    (currentBlok == null ||
                        isFullyCheckedToday ||
                        isAllPaid ||
                        remainingCount == 0)
                    ? null
                    : () => Navigator.pop(ctx, remainingToCheck),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _buildStatColumn(String label, String value, Color color) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ],
  );
}

Future<bool> showBuatLaporanDatDialog(
  BuildContext context,
  int totalCount,
) async {
  final konfirmasi = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.download_rounded, color: Colors.teal),
          SizedBox(width: 8),
          Text('Buat Laporan (.dat)'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Laporan ini akan mengemas seluruh data DHKP ($totalCount objek PBB) tanpa dibatasi dusun atau blok.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.teal.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Berkas .dat memuat rincian objek, status pembayaran, catatan, dan foto dokumentasi objek.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade900,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Unduh Berkas Laporan'),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return konfirmasi == true;
}

Future<String?> showUploadDataSourceDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Upload Data DHKP / Laporan (.dat)'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'file'),
          child: const ListTile(
            leading: Icon(Icons.folder_open_outlined, color: Colors.teal),
            title: Text('Pilih Berkas dari Perangkat'),
            subtitle: Text(
              'Buka berkas DHKP, Excel, atau Laporan (.dat) dari penyimpanan perangkat',
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'google_drive'),
          child: const ListTile(
            leading: FaIcon(FontAwesomeIcons.googleDrive, color: Colors.blue),
            title: Text('Ambil dari Google Drive'),
            subtitle: Text(
              'Pilih berkas dari akun Google Drive atau buka melalui tautan',
            ),
          ),
        ),
      ],
    ),
  );
}

Future<OpsiEksporResult?> showPilihOpsiEksporDialog(
  BuildContext context, {
  required List<String> bloks,
  required String? selectedBlok,
  required String title,
  required String actionButtonLabel,
  required IconData actionIcon,
  bool fixedPdf = false,
}) {
  String currentBlok = (selectedBlok != null && selectedBlok != semuaBlokValue)
      ? selectedBlok
      : semuaBlokValue;
  BlokExportFormat currentFormat = BlokExportFormat.pdf;

  return showDialog<OpsiEksporResult>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final isPerBlok = currentBlok != semuaBlokValue;
          return AlertDialog(
            title: Row(
              children: [
                Icon(actionIcon, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih Lingkup Blok:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: currentBlok,
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      prefixIcon: const Icon(Icons.grid_view_rounded, size: 20),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: semuaBlokValue,
                        child: Text(
                          'Semua Blok (${bloks.length} Blok)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final b in bloks)
                        DropdownMenuItem<String>(
                          value: b,
                          child: Text(
                            'Blok $b (Per-Blok)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => currentBlok = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  if (!fixedPdf) ...[
                    Text(
                      'Pilih Format Berkas:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<BlokExportFormat>(
                      initialValue: currentFormat,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        prefixIcon: const Icon(
                          Icons.description_outlined,
                          size: 20,
                        ),
                      ),
                      items: [
                        for (final fmt in BlokExportFormat.values)
                          DropdownMenuItem<BlokExportFormat>(
                            value: fmt,
                            child: Text(fmt.label),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => currentFormat = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isPerBlok
                          ? Colors.teal.withValues(alpha: 0.1)
                          : Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPerBlok
                            ? Colors.teal.withValues(alpha: 0.3)
                            : Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isPerBlok
                              ? Icons.bolt_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                          color: isPerBlok ? Colors.teal : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPerBlok
                                ? 'Pencetakan atau ekspor per-blok memproses data blok ini saja, lebih cepat dan hemat kertas.'
                                : 'Mengekspor semua blok akan menyusun seluruh data secara bertahap dan teratur agar perangkat tidak berat.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                icon: Icon(actionIcon, size: 18),
                label: Text(actionButtonLabel),
                onPressed: () => Navigator.pop(
                  ctx,
                  OpsiEksporResult(blok: currentBlok, format: currentFormat),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> showWhatsAppPhotoPreviewDialog(
  BuildContext context, {
  required BlokRecord record,
  required File? initialPhotoFile,
  required Future<void> Function() onDeletePhoto,
  required Future<File?> Function() onPickAndSavePhoto,
}) async {
  File? photoFile = initialPhotoFile;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final hasImage = photoFile != null && photoFile!.existsSync();

        return Dialog(
          backgroundColor: Theme.of(context).cardColor,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade900
                      : Colors.teal.shade700,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.namaWajibPajak,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'NOP: ${record.formattedNop}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    color: Colors.black87,
                    constraints: const BoxConstraints(
                      minHeight: 250,
                      maxHeight: 400,
                    ),
                    width: double.infinity,
                    child: hasImage
                        ? InteractiveViewer(
                            panEnabled: true,
                            scaleEnabled: true,
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: Image.file(photoFile!, fit: BoxFit.contain),
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.photo_camera_outlined,
                                    size: 64,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Belum Ada Gambar Dokumentasi',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Klik "Upload Foto" di bawah untuk mengambil atau memilih foto.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasImage) ...[
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Hapus'),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Hapus Foto?'),
                                content: const Text(
                                  'Foto untuk objek ini akan dihapus dari penyimpanan.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Batal'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Hapus'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await onDeletePhoto();
                              final refreshed =
                                  await DhkpPackageHelper.findPhotoForNop(
                                    record.nop,
                                    customFileName: '',
                                  );
                              setDialogState(() {
                                photoFile = refreshed;
                              });
                            }
                          },
                        ),
                        const Spacer(),
                      ],
                      FilledButton.icon(
                        icon: const Icon(Icons.add_a_photo, size: 18),
                        label: Text(hasImage ? 'Ganti Foto' : 'Upload Foto'),
                        onPressed: () async {
                          final newFile = await onPickAndSavePhoto();
                          if (newFile != null) {
                            setDialogState(() {
                              photoFile = newFile;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
