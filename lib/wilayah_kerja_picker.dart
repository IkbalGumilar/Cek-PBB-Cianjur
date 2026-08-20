import 'package:flutter/material.dart';

import 'dusun_data.dart';

/// Dialog pilih dusun sebagai wilayah kerja. [allowSkip] menampilkan opsi
/// "Lewati" (dipakai untuk prompt pertama kali aplikasi dijalankan — memilih
/// wilayah tetap opsional); kalau false, tombolnya "Batal" (dipakai untuk
/// ganti wilayah lewat Pengaturan). Balikin nomor dusun yang dipilih, atau
/// null kalau dilewati/dibatalkan.
Future<int?> pickDusunDialog(
  BuildContext context, {
  required bool allowSkip,
  int? currentDusun,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Pilih Wilayah Kerja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pilih dusun yang jadi wilayah kerja Anda supaya hasil "Sudah Bayar" yang Anda '
              'cek otomatis tercatat di Buku Catatan Blok. Blok di luar dusun ini tetap bisa '
              'dicek & dibayar seperti biasa, hanya saja tidak akan dicatat riwayatnya.',
            ),
            const SizedBox(height: 12),
            RadioGroup<int>(
              groupValue: currentDusun,
              onChanged: (value) {
                if (value != null) Navigator.pop(ctx, value);
              },
              child: Column(
                children: [
                  for (final dusun in dusunList)
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dusun.label),
                      subtitle: Text(dusun.bloks.isEmpty ? 'Belum ada data blok' : '${dusun.bloks.length} blok'),
                      value: dusun.number,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(allowSkip ? 'Lewati' : 'Batal'),
        ),
      ],
    ),
  );
}
