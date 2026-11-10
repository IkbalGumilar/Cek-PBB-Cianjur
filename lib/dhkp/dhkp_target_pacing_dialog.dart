import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calculator/pbb_calculator_models.dart';
import '../currency_format.dart';
import '../native_file_helper.dart';

/// Menampilkan popup dialog Target Capaian & Pacing Kecepatan Realisasi PBB-P2.
Future<void> showTargetPacingDialog(
  BuildContext context, {
  required int totalKetetapan,
  required int realisasi,
  required int totalNop,
  required String wilayahTitle,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _TargetPacingDialogContent(
      totalKetetapan: totalKetetapan,
      realisasi: realisasi,
      totalNop: totalNop,
      wilayahTitle: wilayahTitle,
    ),
  );
}

class _TargetPacingDialogContent extends StatefulWidget {
  final int totalKetetapan;
  final int realisasi;
  final int totalNop;
  final String wilayahTitle;

  const _TargetPacingDialogContent({
    required this.totalKetetapan,
    required this.realisasi,
    required this.totalNop,
    required this.wilayahTitle,
  });

  @override
  State<_TargetPacingDialogContent> createState() =>
      _TargetPacingDialogContentState();
}

class _TargetPacingDialogContentState
    extends State<_TargetPacingDialogContent> {
  double _targetPersen = 50.0;
  DateTime _jatuhTempo = DateTime(DateTime.now().year, 8, 31);
  late int _rataRataPerNop;

  @override
  void initState() {
    super.initState();
    _rataRataPerNop = widget.totalNop > 0
        ? (widget.totalKetetapan / widget.totalNop).round()
        : 50000;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('$label berhasil disalin ke papan klip!')),
          ],
        ),
        backgroundColor: Colors.green[800],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _jatuhTempo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Pilih Batas Jatuh Tempo',
      confirmText: 'Pilih',
      cancelText: 'Batal',
    );
    if (picked != null) {
      setState(() => _jatuhTempo = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final targetResult = PbbCalculatorHelper.calculateTarget(
      totalKetetapan: widget.totalKetetapan,
      realisasiSaatIni: widget.realisasi,
      targetPersen: _targetPersen,
      rataRataNominalPerNop: _rataRataPerNop,
    );

    final pacingResult = PbbCalculatorHelper.calculatePacing(
      sisaNominal: targetResult.targetSudahTercapai
          ? 0
          : targetResult.kekuranganNominal,
      jatuhTempo: _jatuhTempo,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Dialog
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: theme.colorScheme.primary,
              child: Row(
                children: [
                  Icon(
                    Icons.speed_rounded,
                    color: theme.colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TARGET & PACING REALISASI',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          widget.wilayahTitle,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onPrimary,
                    ),
                    onPressed: () => Navigator.pop(context),
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
                    // Ringkasan Pagu & Realisasi Saat Ini
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E281E) : const Color(0xFFF1F8E9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.green.shade900 : Colors.green.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Pagu Ketetapan:', style: TextStyle(fontSize: 11)),
                                Text(
                                  formatRupiah(widget.totalKetetapan),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Realisasi Terkini:', style: TextStyle(fontSize: 11)),
                                Text(
                                  '${formatRupiah(widget.realisasi)} (${targetResult.persenSaatIni.toStringAsFixed(1)}%)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Slider Target
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Pilih Target Realisasi:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_targetPersen.toStringAsFixed(0)}% (${formatRupiah(targetResult.targetNominal)})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _targetPersen,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      label: '${_targetPersen.toStringAsFixed(0)}%',
                      onChanged: (val) => setState(() => _targetPersen = val),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [50, 60, 75, 90, 100].map((preset) {
                        final isSel = _targetPersen.round() == preset;
                        return ActionChip(
                          label: Text('$preset%'),
                          backgroundColor: isSel ? theme.colorScheme.primary : null,
                          labelStyle: TextStyle(
                            color: isSel ? theme.colorScheme.onPrimary : null,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _targetPersen = preset.toDouble()),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Kartu Status Gap Target
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: targetResult.targetSudahTercapai
                            ? (isDark ? const Color(0xFF1B331A) : const Color(0xFFE8F5E9))
                            : (isDark ? const Color(0xFF332B15) : const Color(0xFFFFF8E1)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: targetResult.targetSudahTercapai
                              ? Colors.green.shade600
                              : Colors.amber.shade700,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            targetResult.targetSudahTercapai
                                ? '🎉 SASARAN ${_targetPersen.toStringAsFixed(0)}% SUDAH TERCAPAI'
                                : '⚠️ KEKURANGAN MENUJU ${_targetPersen.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: targetResult.targetSudahTercapai
                                  ? (isDark ? Colors.green.shade300 : Colors.green.shade900)
                                  : (isDark ? Colors.amber.shade300 : Colors.amber.shade900),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            targetResult.targetSudahTercapai
                                ? 'Surplus: +${formatRupiah(targetResult.kelebihanNominal)}'
                                : formatRupiah(targetResult.kekuranganNominal),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: targetResult.targetSudahTercapai
                                  ? (isDark ? Colors.green.shade200 : Colors.green.shade900)
                                  : (isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                            ),
                          ),
                          if (!targetResult.targetSudahTercapai) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Estimasi Penagihan: Butuh pelunasan ~${targetResult.estimasiNopDibutuhkan} NOP lagi (rata-rata ${formatRupiah(_rataRataPerNop)}/SPPT).',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Bagian Pacing / Kecepatan Waktu
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Pacing Kecepatan Penagihan',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_outlined, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Jatuh Tempo: ${_jatuhTempo.day}/${_jatuhTempo.month}/${_jatuhTempo.year}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (pacingResult.sudahLewatJatuhTempo)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF331515) : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade400),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Batas tanggal jatuh tempo telah terlewati.',
                                style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricBox(
                              title: 'Sisa Waktu',
                              value: '${pacingResult.sisaHari} Hari',
                              subtitle: 'ke ${_jatuhTempo.day}/${_jatuhTempo.month}',
                              color: Colors.blue,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricBox(
                              title: 'Target Harian',
                              value: formatRupiah(pacingResult.targetHarian),
                              subtitle: 'per hari kalender',
                              color: Colors.purple,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricBox(
                              title: 'Target Mingguan',
                              value: formatRupiah(pacingResult.targetMingguan),
                              subtitle: 'kumulatif 7 hari',
                              color: Colors.teal,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Footer Tombol
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final text = PbbCalculatorHelper.formatWhatsAppTarget(
                          namaWilayah: widget.wilayahTitle,
                          targetResult: targetResult,
                          pacingResult: pacingResult,
                        );
                        _copyToClipboard(text, 'Pesan Ringkasan Target');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Salin Pesan WA'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      final text = PbbCalculatorHelper.formatWhatsAppTarget(
                        namaWilayah: widget.wilayahTitle,
                        targetResult: targetResult,
                        pacingResult: pacingResult,
                      );
                      NativeFileHelper.shareText(text: text, title: 'Target Capaian PBB-P2');
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    tooltip: 'Bagikan',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox({
    required String title,
    required String value,
    required String subtitle,
    required MaterialColor color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, color: color.shade800, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade900)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
