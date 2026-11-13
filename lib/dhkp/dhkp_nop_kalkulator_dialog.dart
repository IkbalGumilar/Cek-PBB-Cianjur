import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blok_record.dart';
import '../calculator/pbb_calculator_models.dart';
import '../currency_format.dart';
import '../native_file_helper.dart';

/// Membuka popup kalkulator terpadu untuk suatu objek pajak (Denda, Cicilan & Tabungan, dan AJB).
Future<void> showNopKalkulatorDialog(
  BuildContext context, {
  required BlokRecord record,
  int initialTab = 0,
  VoidCallback? onCekTagihan,
  ValueChanged<BlokRecord>? onRecordUpdated,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _NopKalkulatorDialogContent(
      record: record,
      initialTab: initialTab,
      onCekTagihan: onCekTagihan,
      onRecordUpdated: onRecordUpdated,
    ),
  );
}

/// Membuka kalkulator mandiri AJB & Simulasi NJOP (bisa dibuka tanpa data NOP).
Future<void> showStandaloneAjbDialog(
  BuildContext context, {
  double? initialLuas,
  int? initialNjop,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _StandaloneAjbDialogContent(
      initialLuas: initialLuas ?? 100.0,
      initialNjop: initialNjop ?? 100000,
    ),
  );
}

class _NopKalkulatorDialogContent extends StatefulWidget {
  final BlokRecord record;
  final int initialTab;
  final VoidCallback? onCekTagihan;
  final ValueChanged<BlokRecord>? onRecordUpdated;

  const _NopKalkulatorDialogContent({
    required this.record,
    required this.initialTab,
    this.onCekTagihan,
    this.onRecordUpdated,
  });

  @override
  State<_NopKalkulatorDialogContent> createState() =>
      _NopKalkulatorDialogContentState();
}

class _NopKalkulatorDialogContentState
    extends State<_NopKalkulatorDialogContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BlokRecord _currentRecord;

  // State Tab Denda
  late TextEditingController _pokokPbbCtrl;
  late DateTime _jatuhTempo;
  DateTime _rencanaBayar = DateTime.now();
  double _tarifBungaBulanan = 1.0;

  // State Tab Cicilan & Tabungan Warga
  late PbbTabunganModel _tabungan;
  late TextEditingController _nominalMutasiCtrl;
  late TextEditingController _catatanTabunganCtrl;
  String _cicilanFrekuensi = 'Mingguan';
  int _cicilanDurasiBulan = 6;
  late List<List<int>> _draftTtdStrokes;
  List<int>? _activeTtdStroke;
  bool _ttdDirty = false;

  // State Tab AJB
  late TextEditingController _luasTanahCtrl;
  late TextEditingController _njopPerM2Ctrl;

  @override
  void initState() {
    super.initState();
    _currentRecord = widget.record;
    final defaultTarget = _currentRecord.jumlahPbbValue > 0
        ? _currentRecord.jumlahPbbValue
        : 50000;
    _tabungan = PbbTabunganHelper.extractTabungan(
      _currentRecord.catatan,
      defaultTarget: defaultTarget,
    );
    _nominalMutasiCtrl = TextEditingController();
    _catatanTabunganCtrl = TextEditingController(text: _tabungan.catatan);
    _draftTtdStrokes = _tabungan.tandaTanganStrokes
        .map((s) => List<int>.from(s))
        .toList();

    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );

    final pokok = _currentRecord.jumlahPbbValue > 0
        ? _currentRecord.jumlahPbbValue
        : 50000;
    _pokokPbbCtrl = TextEditingController(text: pokok.toString());

    // Tahun jatuh tempo sesuai data record atau tahun ini
    final tahunInt =
        int.tryParse(_currentRecord.tahunBayar.trim()) ?? DateTime.now().year;
    _jatuhTempo = DateTime(tahunInt, 8, 31);

    // Inisialisasi Luas & NJOP untuk AJB
    final parsedLuas = parseNominalRupiah(_currentRecord.luasBumi);
    _luasTanahCtrl = TextEditingController(
      text: parsedLuas > 0 ? parsedLuas.toString() : '100',
    );

    final parsedNjop = parseNominalRupiah(_currentRecord.njopBumi);
    _njopPerM2Ctrl = TextEditingController(
      text: parsedNjop > 0 ? parsedNjop.toString() : '100000',
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pokokPbbCtrl.dispose();
    _luasTanahCtrl.dispose();
    _njopPerM2Ctrl.dispose();
    _nominalMutasiCtrl.dispose();
    _catatanTabunganCtrl.dispose();
    super.dispose();
  }

  int _parseNumeric(TextEditingController ctrl, [int defaultValue = 0]) {
    final clean = ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? defaultValue;
  }

  double _parseDouble(TextEditingController ctrl, [double defaultValue = 0.0]) {
    final clean = ctrl.text.replaceAll(',', '.');
    return double.tryParse(clean) ?? defaultValue;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
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

  String _formatNow() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year.toString();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  void _updateTabunganState(
    PbbTabunganModel newTabungan, {
    String? successMessage,
    String? errorMessage,
  }) {
    if (errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final cleanNote = PbbTabunganHelper.cleanCatatan(_currentRecord.catatan);
    final encoded = PbbTabunganHelper.encodeCatatanWithTabungan(
      cleanNote,
      newTabungan,
    );

    final updated = _currentRecord.copyWith(catatan: encoded);

    setState(() {
      _currentRecord = updated;
      _tabungan = newTabungan;
    });

    widget.onRecordUpdated?.call(updated);

    if (successMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(successMessage)),
            ],
          ),
          backgroundColor: Colors.green[800],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _tambahTabungan(int nominal, {String keterangan = ''}) {
    if (nominal <= 0) {
      _updateTabunganState(
        _tabungan,
        errorMessage: 'Masukkan nominal setoran yang valid (> 0)',
      );
      return;
    }
    final ket = keterangan.trim().isNotEmpty
        ? keterangan.trim()
        : 'Setoran tabungan cicilan';
    final mutasi = PbbTabunganMutasi(
      nominal: nominal,
      tanggal: _formatNow(),
      keterangan: ket,
    );
    final updatedTabungan = _tabungan.setor(nominal, mutasi: mutasi);
    _nominalMutasiCtrl.clear();
    _updateTabunganState(
      updatedTabungan,
      successMessage:
          'Berhasil setor ${formatRupiah(nominal)} ke celengan warga!',
    );
  }

  void _kurangTabungan(
    int nominal, {
    bool tarikSemua = false,
    String keterangan = '',
  }) {
    final nominalTarik = tarikSemua ? _tabungan.saldo : nominal;
    if (nominalTarik <= 0) {
      _updateTabunganState(
        _tabungan,
        errorMessage: 'Saldo tabungan saat ini Rp 0',
      );
      return;
    }
    if (nominalTarik > _tabungan.saldo) {
      _updateTabunganState(
        _tabungan,
        errorMessage:
            'Saldo tabungan tidak mencukupi (Tersedia: ${formatRupiah(_tabungan.saldo)})',
      );
      return;
    }
    final ket = keterangan.trim().isNotEmpty
        ? keterangan.trim()
        : (tarikSemua
              ? 'Tarik seluruh sisa tabungan'
              : 'Penarikan tabungan warga');
    final mutasi = PbbTabunganMutasi(
      nominal: -nominalTarik,
      tanggal: _formatNow(),
      keterangan: ket,
    );
    final updatedTabungan = _tabungan.tarik(nominalTarik, mutasi: mutasi);
    _nominalMutasiCtrl.clear();
    _updateTabunganState(
      updatedTabungan,
      successMessage:
          'Berhasil menarik ${formatRupiah(nominalTarik)} dari tabungan!',
    );
  }

  void _simpanCatatanTabunganSaja() {
    final newCatatan = _catatanTabunganCtrl.text.trim();
    final updatedTabungan = _tabungan.copyWith(catatan: newCatatan);
    _updateTabunganState(
      updatedTabungan,
      successMessage: 'Catatan tabungan cicilan berhasil disimpan!',
    );
  }

  void _pilihAlokasiKelebihan(PbbKelebihanAlokasi alokasi) {
    final updated = _tabungan.copyWith(kelebihanAlokasi: alokasi);
    _updateTabunganState(
      updated,
      successMessage: 'Alokasi kelebihan dicatat: ${alokasi.label}',
    );
  }

  List<int> _toNormalizedPoint(Offset localPos, Size canvasSize) {
    final nx = ((localPos.dx / canvasSize.width) * 1000).round().clamp(0, 1000);
    final ny = ((localPos.dy / canvasSize.height) * 1000).round().clamp(
      0,
      1000,
    );
    return [nx, ny];
  }

  void _startSignatureStroke(Offset localPos, Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    final pt = _toNormalizedPoint(localPos, canvasSize);
    setState(() {
      _activeTtdStroke = pt;
      _ttdDirty = true;
    });
  }

  void _appendSignatureStroke(Offset localPos, Size canvasSize) {
    final active = _activeTtdStroke;
    if (active == null || canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }
    final pt = _toNormalizedPoint(localPos, canvasSize);
    if (active.length >= 2) {
      final prevX = active[active.length - 2];
      final prevY = active[active.length - 1];
      if ((pt[0] - prevX).abs() < 6 && (pt[1] - prevY).abs() < 6) return;
    }
    setState(() {
      active.add(pt[0]);
      active.add(pt[1]);
    });
  }

  void _endSignatureStroke() {
    final active = _activeTtdStroke;
    if (active == null) return;
    setState(() {
      if (active.length >= 2) {
        _draftTtdStrokes.add(active);
      }
      _activeTtdStroke = null;
    });
  }

  void _simpanTandaTanganWp() {
    if (_draftTtdStrokes.isEmpty) {
      _updateTabunganState(
        _tabungan,
        errorMessage:
            'Silakan buat tanda tangan WP pada area kanvas terlebih dahulu.',
      );
      return;
    }
    final cleanStrokes = _draftTtdStrokes
        .where((s) => s.length >= 2)
        .map((s) => List<int>.from(s))
        .toList();
    final updated = _tabungan.copyWith(
      tandaTanganStrokes: cleanStrokes,
      tandaTanganWaktu: _formatNow(),
    );
    setState(() => _ttdDirty = false);
    _updateTabunganState(
      updated,
      successMessage: 'Tanda tangan digital WP berhasil disimpan!',
    );
  }

  void _hapusTandaTanganWp() {
    setState(() {
      _draftTtdStrokes.clear();
      _activeTtdStroke = null;
      _ttdDirty = false;
    });
    if (_tabungan.hasTandaTangan) {
      _updateTabunganState(
        _tabungan.copyWith(clearTandaTangan: true),
        successMessage: 'Tanda tangan digital WP dihapus.',
      );
    }
  }

  Future<void> _pickDate({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Pilih Tanggal',
      confirmText: 'Pilih',
      cancelText: 'Batal',
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => onSelected(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
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
                    Icons.calculate_outlined,
                    color: theme.colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KALKULATOR PAJAK & AKSI DHKP',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${widget.record.formattedNop} • ${widget.record.namaWajibPajak}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.85,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: isDark ? Colors.white70 : Colors.black87,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.hourglass_bottom_rounded, size: 18),
                  text: 'Denda Pajak',
                ),
                Tab(
                  icon: Icon(Icons.savings_outlined, size: 18),
                  text: 'Cicilan Warga',
                ),
                Tab(
                  icon: Icon(Icons.gavel_outlined, size: 18),
                  text: 'Kalkulator AJB',
                ),
              ],
            ),

            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabDenda(theme, isDark),
                  _buildTabCicilan(theme, isDark),
                  _buildTabAjb(theme, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: DENDA KETERLAMBATAN
  // ==========================================
  Widget _buildTabDenda(ThemeData theme, bool isDark) {
    final pokok = _parseNumeric(_pokokPbbCtrl, 50000);
    final dendaResult = PbbCalculatorHelper.calculateDenda(
      pokokPbb: pokok,
      jatuhTempo: _jatuhTempo,
      rencanaBayar: _rencanaBayar,
      tarifBungaPerBulan: _tarifBungaBulanan,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pokokPbbCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pokok Ketetapan PBB (Rp)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(
                  context: context,
                  initialDate: _jatuhTempo,
                  onSelected: (d) => _jatuhTempo = d,
                ),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tgl Jatuh Tempo',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.event_busy_outlined),
                  ),
                  child: Text(
                    '${_jatuhTempo.day}/${_jatuhTempo.month}/${_jatuhTempo.year}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(
                  context: context,
                  initialDate: _rencanaBayar,
                  onSelected: (d) => _rencanaBayar = d,
                ),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tgl Rencana Bayar',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.event_available_outlined),
                  ),
                  child: Text(
                    '${_rencanaBayar.day}/${_rencanaBayar.month}/${_rencanaBayar.year}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(
              value: 1.0,
              label: Text(
                '1.0% / bln (UU HKPD)',
                style: TextStyle(fontSize: 11),
              ),
            ),
            ButtonSegment(
              value: 2.0,
              label: Text(
                '2.0% / bln (Perda Lama)',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
          selected: {_tarifBungaBulanan},
          onSelectionChanged: (set) =>
              setState(() => _tarifBungaBulanan = set.first),
        ),
        const SizedBox(height: 14),

        // Hasil Perhitungan Denda
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dendaResult.tepatWaktu
                ? (isDark ? const Color(0xFF18331A) : const Color(0xFFE8F5E9))
                : (isDark ? const Color(0xFF3B1E1E) : const Color(0xFFFFEBEE)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: dendaResult.tepatWaktu
                  ? Colors.green.shade600
                  : Colors.red.shade700,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dendaResult.tepatWaktu
                        ? '✅ BEBAS DENDA (TEPAT WAKTU)'
                        : '⚠️ TERKENA DENDA (${dendaResult.bulanKeterlambatan} BULAN)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: dendaResult.tepatWaktu
                          ? (isDark
                                ? Colors.green.shade300
                                : Colors.green.shade900)
                          : (isDark
                                ? Colors.red.shade300
                                : Colors.red.shade900),
                    ),
                  ),
                  if (!dendaResult.tepatWaktu)
                    Text(
                      '+${dendaResult.totalPersenDenda.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatRupiah(dendaResult.totalBayar),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: dendaResult.tepatWaktu
                      ? (isDark ? Colors.green.shade200 : Colors.green.shade900)
                      : (isDark ? Colors.red.shade200 : Colors.red.shade900),
                ),
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pokok Ketetapan:',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    formatRupiah(dendaResult.pokokPbb),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sanksi Bunga/Denda:',
                    style: TextStyle(
                      fontSize: 12,
                      color: dendaResult.nominalDenda > 0 ? Colors.red : null,
                    ),
                  ),
                  Text(
                    formatRupiah(dendaResult.nominalDenda),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: dendaResult.nominalDenda > 0 ? Colors.red : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final text = PbbCalculatorHelper.formatWhatsAppDenda(
                    nop: widget.record.formattedNop,
                    namaWp: widget.record.namaWajibPajak,
                    dendaResult: dendaResult,
                  );
                  _copyToClipboard(text, 'Rincian Denda Wajib Pajak');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Salin Rincian WA'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () {
                final text = PbbCalculatorHelper.formatWhatsAppDenda(
                  nop: widget.record.formattedNop,
                  namaWp: widget.record.namaWajibPajak,
                  dendaResult: dendaResult,
                );
                NativeFileHelper.shareText(
                  text: text,
                  title: 'Rincian Denda PBB',
                );
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              tooltip: 'Bagikan',
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: CICILAN & TABUNGAN WARGA
  // ==========================================
  Widget _buildTabCicilan(ThemeData theme, bool isDark) {
    final pokok = _parseNumeric(_pokokPbbCtrl, widget.record.jumlahPbbValue);
    final cicilanResult = PbbCalculatorHelper.calculateCicilan(
      totalTagihan: _tabungan.target > 0 ? _tabungan.target : pokok,
      frekuensi: _cicilanFrekuensi,
      durasiBulan: _cicilanDurasiBulan,
    );

    final isLunas = _tabungan.isLunas;
    final progressFraction = (_tabungan.persentase / 100).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ------------------------------------------
        // KARTU CELENGAN / TABUNGAN WARGA (HEADER)
        // ------------------------------------------
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isLunas
                  ? (isDark
                        ? [const Color(0xFF1B4332), const Color(0xFF081C15)]
                        : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)])
                  : (isDark
                        ? [const Color(0xFF3E1F2A), const Color(0xFF1F1218)]
                        : [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)]),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLunas
                  ? Colors.green.shade600
                  : (isDark ? Colors.pink.shade700 : Colors.pink.shade300),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isLunas ? Colors.green : Colors.pink).withValues(
                  alpha: isDark ? 0.2 : 0.15,
                ),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isLunas
                          ? Colors.green.shade700
                          : Colors.pink.shade600,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isLunas
                          ? Icons.check_circle_rounded
                          : Icons.savings_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CELENGAN / TABUNGAN PBB WARGA',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: isLunas
                                ? (isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade900)
                                : (isDark
                                      ? Colors.pink.shade200
                                      : Colors.pink.shade900),
                          ),
                        ),
                        Text(
                          _tabungan.hasKelebihan
                              ? 'Lunas + lebih ${formatRupiah(_tabungan.kelebihanSaldo)} — tentukan alokasi sisa'
                              : (isLunas
                                    ? 'Alhamdulillah! Saldo Tabungan Sudah Lunas'
                                    : 'Kumpulkan cicilan warga hingga cukup untuk bayar PBB'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_tabungan.target != pokok && pokok > 0)
                    IconButton(
                      tooltip:
                          'Samakan target dengan tagihan pokok (${formatRupiah(pokok)})',
                      icon: const Icon(Icons.sync_rounded, size: 20),
                      onPressed: () {
                        final updated = _tabungan.copyWith(
                          target: pokok,
                          clearKelebihanAlokasi: _tabungan.saldo <= pokok,
                        );
                        _updateTabunganState(
                          updated,
                          successMessage:
                              'Target disesuaikan ke ${formatRupiah(pokok)}',
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Rincian Nilai: Target vs Terkumpul
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target Tagihan:',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatRupiah(_tabungan.target),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 32,
                    width: 1,
                    color: (isDark ? Colors.white24 : Colors.black26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo Terkumpul:',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatRupiah(_tabungan.saldo),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isLunas
                                ? (isDark
                                      ? Colors.green.shade400
                                      : Colors.green.shade800)
                                : (isDark
                                      ? Colors.pink.shade300
                                      : Colors.pink.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Progress Bar & Keterangan Kekurangan
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progressFraction,
                  minHeight: 10,
                  backgroundColor: isDark ? Colors.black38 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isLunas ? Colors.green.shade600 : Colors.pink.shade500,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      _tabungan.hasKelebihan
                          ? 'LUNAS + LEBIH ${formatRupiah(_tabungan.kelebihanSaldo)}'
                          : (isLunas
                                ? 'LUNAS (100%)'
                                : 'Kurang: ${formatRupiah(_tabungan.sisaKekurangan)}'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isLunas
                            ? (isDark
                                  ? Colors.green.shade300
                                  : Colors.green.shade800)
                            : (isDark
                                  ? Colors.orange.shade300
                                  : Colors.orange.shade900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: _tabungan.hasKelebihan
                        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                        : EdgeInsets.zero,
                    decoration: _tabungan.hasKelebihan
                        ? BoxDecoration(
                            color: isDark
                                ? Colors.teal.shade800
                                : Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(6),
                          )
                        : null,
                    child: Text(
                      '${_tabungan.persentase.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _tabungan.hasKelebihan
                            ? (isDark
                                  ? Colors.teal.shade200
                                  : Colors.teal.shade900)
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ------------------------------------------
        // TOMBOL BAYAR MENYALA / CEK TAGIHAN
        // "jika pbb == nilai maka toombol bayar menyala ini mengarahkan ke cek tagihan"
        // ------------------------------------------
        if (isLunas)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.shade600.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 2,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.white70, width: 1.5),
                ),
                elevation: 4,
              ),
              icon: const Icon(
                Icons.verified_rounded,
                size: 22,
                color: Colors.white,
              ),
              label: const Text(
                'BAYAR PBB SEKARANG (CEK TAGIHAN)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onCekTagihan?.call();
              },
            ),
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Buka Cek Tagihan PBB'),
            onPressed: () {
              Navigator.pop(context);
              widget.onCekTagihan?.call();
            },
          ),
        const SizedBox(height: 16),

        if (_tabungan.hasKelebihan) ...[
          _buildKelebihanAlokasiSection(isDark),
          const SizedBox(height: 16),
        ],

        // ------------------------------------------
        // INPUT SETOR / TARIK TABUNGAN
        // ------------------------------------------
        Text(
          'Kelola Setoran & Penarikan Tabungan:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nominalMutasiCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Nominal Tabungan (Rp)',
            hintText: 'Contoh: 25000',
            prefixText: 'Rp ',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => _nominalMutasiCtrl.clear(),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Quick Nominal Chips
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('+10 rb'),
              onPressed: () {
                final current = _parseNumeric(_nominalMutasiCtrl);
                _nominalMutasiCtrl.text = (current + 10000).toString();
              },
            ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('+25 rb'),
              onPressed: () {
                final current = _parseNumeric(_nominalMutasiCtrl);
                _nominalMutasiCtrl.text = (current + 25000).toString();
              },
            ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('+50 rb'),
              onPressed: () {
                final current = _parseNumeric(_nominalMutasiCtrl);
                _nominalMutasiCtrl.text = (current + 50000).toString();
              },
            ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('+100 rb'),
              onPressed: () {
                final current = _parseNumeric(_nominalMutasiCtrl);
                _nominalMutasiCtrl.text = (current + 100000).toString();
              },
            ),
            if (_tabungan.sisaKekurangan > 0)
              ActionChip(
                visualDensity: VisualDensity.compact,
                backgroundColor: isDark
                    ? Colors.teal.shade900
                    : Colors.teal.shade50,
                label: Text(
                  'Paskan Target (${formatRupiah(_tabungan.sisaKekurangan)})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                  ),
                ),
                onPressed: () {
                  _nominalMutasiCtrl.text = _tabungan.sisaKekurangan.toString();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Action Buttons: Setor (+), Tarik (-), Tarik Semua
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Setor (+)'),
                onPressed: () {
                  final nominal = _parseNumeric(_nominalMutasiCtrl);
                  _tambahTabungan(nominal);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Tarik (-)'),
                onPressed: () {
                  final nominal = _parseNumeric(_nominalMutasiCtrl);
                  _kurangTabungan(nominal);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Tarik Seluruh Sisa Tabungan',
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? Colors.red.shade900.withValues(alpha: 0.5)
                    : Colors.red.shade50,
                foregroundColor: Colors.red.shade700,
              ),
              icon: const Icon(Icons.money_off_rounded, size: 18),
              onPressed: _tabungan.saldo > 0
                  ? () => _kurangTabungan(0, tarikSemua: true)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ------------------------------------------
        // CATATAN SENDIRI KHUSUS CICILAN / TABUNGAN
        // ------------------------------------------
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E242B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Catatan Khusus Tabungan / Cicilan:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Simpan'),
                    onPressed: _simpanCatatanTabunganSaja,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _catatanTabunganCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText:
                      'Misal: Titip tiap panen / Target sebelum jatuh tempo...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ------------------------------------------
        // RIWAYAT MUTASI TRANSAKSI
        // ------------------------------------------
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.history_rounded, size: 20),
          title: Text(
            'Riwayat Transaksi Tabungan (${_tabungan.riwayat.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          children: [
            if (_tabungan.riwayat.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada riwayat transaksi setoran/penarikan tabungan.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tabungan.riwayat.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  // Tampilkan transaksi terbaru di atas
                  final item =
                      _tabungan.riwayat[_tabungan.riwayat.length - 1 - index];
                  final isSetor = item.nominal > 0;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: isSetor
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      child: Icon(
                        isSetor ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 14,
                        color: isSetor
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                      ),
                    ),
                    title: Text(
                      item.keterangan.isNotEmpty
                          ? item.keterangan
                          : (isSetor ? 'Setoran Tabungan' : 'Penarikan Dana'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      item.tanggal,
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: Text(
                      '${isSetor ? '+' : ''}${formatRupiah(item.nominal)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSetor
                            ? (isDark
                                  ? Colors.green.shade400
                                  : Colors.green.shade800)
                            : (isDark
                                  ? Colors.red.shade400
                                  : Colors.red.shade800),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ------------------------------------------
        // SIMULASI ESTIMASI CICILAN
        // ------------------------------------------
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.calculate_outlined, size: 20),
          title: const Text(
            'Simulasi Skema Cicilan (Rekomendasi)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _cicilanFrekuensi,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Frekuensi Setoran',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Mingguan',
                        child: Text('Mingguan (4x/bln)'),
                      ),
                      DropdownMenuItem(
                        value: 'Bulanan',
                        child: Text('Bulanan (1x/bln)'),
                      ),
                      DropdownMenuItem(
                        value: 'Harian',
                        child: Text('Harian (30x/bln)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _cicilanFrekuensi = val);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _cicilanDurasiBulan,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jangka Waktu',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [1, 2, 3, 4, 6, 8, 10, 12].map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text('$m Bulan'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _cicilanDurasiBulan = val);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF162A28)
                    : const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimasi per ${_cicilanFrekuensi.toLowerCase()}:',
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatRupiah(cicilanResult.nominalPerSetoran),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.teal.shade300
                                : Colors.teal.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${cicilanResult.jumlahKaliSetoran}x setoran\n($_cicilanDurasiBulan bulan)',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
        const SizedBox(height: 16),

        // ------------------------------------------
        // TANDA TANGAN DIGITAL WP (PERSETUJUAN & SERAH TERIMA)
        // ------------------------------------------
        _buildTandaTanganWpSection(isDark),
        const SizedBox(height: 16),

        // ------------------------------------------
        // BAGIKAN BUKTI TABUNGAN & SALIN
        // ------------------------------------------
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final text = PbbTabunganHelper.formatWhatsAppTabungan(
                    nop: widget.record.formattedNop,
                    namaWp: widget.record.namaWajibPajak,
                    tabungan: _tabungan,
                  );
                  _copyToClipboard(text, 'Bukti Tabungan PBB');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Salin Rincian Tabungan'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () {
                final text = PbbTabunganHelper.formatWhatsAppTabungan(
                  nop: widget.record.formattedNop,
                  namaWp: widget.record.namaWajibPajak,
                  tabungan: _tabungan,
                );
                NativeFileHelper.shareText(
                  text: text,
                  title: 'Tabungan PBB Warga',
                );
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              tooltip: 'Bagikan ke WhatsApp',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKelebihanAlokasiSection(bool isDark) {
    final selected = _tabungan.kelebihanAlokasi;
    return Container(
      key: const Key('kelebihan_alokasi_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132A2E) : const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.teal.shade600 : Colors.teal.shade300,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alokasi Sisa / Kembalian (${formatRupiah(_tabungan.kelebihanSaldo)})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: isDark ? Colors.teal.shade100 : Colors.teal.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Setoran mencapai ${_tabungan.persentase.toStringAsFixed(1)}% dari target. Tandai peruntukan dana lebih:',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: PbbKelebihanAlokasi.values.map((opt) {
              final isSelected = selected == opt;
              final icon = opt == PbbKelebihanAlokasi.kembalianKeWp
                  ? Icons.assignment_return_outlined
                  : Icons.volunteer_activism_outlined;
              return ChoiceChip(
                selected: isSelected,
                avatar: Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.teal.shade200 : Colors.teal.shade800),
                ),
                label: Text(opt.label),
                selectedColor: Colors.teal.shade700,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                ),
                onSelected: (_) => _pilihAlokasiKelebihan(opt),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            selected != null
                ? 'Tercatat: ${selected.label}'
                : 'Belum dipilih — silakan pilih Dikembalikan ke WP atau Tip Petugas.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected != null
                  ? FontWeight.w600
                  : FontWeight.normal,
              color: selected != null
                  ? (isDark ? Colors.green.shade300 : Colors.teal.shade900)
                  : (isDark ? Colors.amber.shade200 : Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTandaTanganWpSection(bool isDark) {
    final hasAnyStrokes =
        _draftTtdStrokes.isNotEmpty || _activeTtdStroke != null;
    final canSave =
        _draftTtdStrokes.isNotEmpty && (_ttdDirty || !_tabungan.hasTandaTangan);

    final String statusLabel;
    final Color statusBg;
    final Color statusFg;
    if (_tabungan.hasTandaTangan && !_ttdDirty) {
      statusLabel = _tabungan.tandaTanganWaktu.isNotEmpty
          ? 'Tersimpan • ${_tabungan.tandaTanganWaktu}'
          : 'Tersimpan';
      statusBg = isDark ? Colors.green.shade900 : Colors.green.shade100;
      statusFg = isDark ? Colors.green.shade200 : Colors.green.shade900;
    } else if (_ttdDirty) {
      statusLabel = 'Belum disimpan';
      statusBg = isDark ? Colors.amber.shade900 : Colors.amber.shade100;
      statusFg = isDark ? Colors.amber.shade200 : Colors.amber.shade900;
    } else {
      statusLabel = 'Belum ada TTD';
      statusBg = isDark ? Colors.white12 : Colors.black12;
      statusFg = isDark ? Colors.white70 : Colors.black54;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E242B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.draw_rounded, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Tanda Tangan Digital WP',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: statusFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Bukti persetujuan cicilan & serah terima dana dengan wajib pajak.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 130,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _tabungan.hasTandaTangan && !_ttdDirty
                    ? Colors.green.shade500
                    : Colors.blueGrey.shade300,
                width: 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final canvasSize = Size(constraints.maxWidth, 130);
                  return RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: <Type, GestureRecognizerFactory>{
                      EagerGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            EagerGestureRecognizer
                          >(EagerGestureRecognizer.new, (_) {}),
                    },
                    child: Listener(
                      key: const Key('ttd_wp_canvas'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) =>
                          _startSignatureStroke(e.localPosition, canvasSize),
                      onPointerMove: (e) =>
                          _appendSignatureStroke(e.localPosition, canvasSize),
                      onPointerUp: (_) => _endSignatureStroke(),
                      onPointerCancel: (_) => _endSignatureStroke(),
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: canvasSize,
                            painter: _TandaTanganWpPainter(
                              strokes: _draftTtdStrokes,
                              activeStroke: _activeTtdStroke,
                            ),
                          ),
                          if (!hasAnyStrokes)
                            Center(
                              child: IgnorePointer(
                                child: Text(
                                  'Goreskan tanda tangan WP di area ini',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('btn_hapus_ttd_wp'),
                  onPressed: (hasAnyStrokes || _tabungan.hasTandaTangan)
                      ? _hapusTandaTanganWp
                      : null,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('Hapus TTD'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('btn_simpan_ttd_wp'),
                  onPressed: canSave ? _simpanTandaTanganWp : null,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Simpan TTD'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: KALKULATOR AJB (AKTA JUAL BELI)
  // ==========================================
  Widget _buildTabAjb(ThemeData theme, bool isDark) {
    final luas = _parseDouble(_luasTanahCtrl, 100);
    final njop = _parseNumeric(_njopPerM2Ctrl, 100000);

    final ajbResult = PbbCalculatorHelper.calculateAjb(
      luas: luas,
      njopPerM2: njop,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _luasTanahCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Luas Tanah (m²)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _njopPerM2Ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'NJOP Tanah / m² (Rp)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Kartu Hasil AJB
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2638) : const Color(0xFFE8EAF6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.indigo.shade400),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Total Nilai Transaksi / NJOP:',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatRupiah(ajbResult.totalNilai),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('PPh (2.5%):', style: TextStyle(fontSize: 12)),
                  Text(
                    formatRupiah(ajbResult.pph),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('PPN (2.5%):', style: TextStyle(fontSize: 12)),
                  Text(
                    formatRupiah(ajbResult.ppn),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      ajbResult.kenaBphtb
                          ? 'BPHTB (5% - Transaksi >= 80 Jt):'
                          : 'BPHTB (Bebas / < 80 Jt):',
                      style: TextStyle(
                        fontSize: 12,
                        color: ajbResult.kenaBphtb
                            ? Colors.indigo
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatRupiah(ajbResult.bphtb),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: ajbResult.kenaBphtb
                          ? Colors.indigo
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'TOTAL ESTIMASI PAJAK AJB:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatRupiah(ajbResult.totalBiayaPajak),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final text = PbbCalculatorHelper.formatWhatsAppAjb(
                    nop: widget.record.formattedNop,
                    namaWp: widget.record.namaWajibPajak,
                    ajbResult: ajbResult,
                  );
                  _copyToClipboard(text, 'Rincian Biaya AJB');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Salin Rincian AJB'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () {
                final text = PbbCalculatorHelper.formatWhatsAppAjb(
                  nop: widget.record.formattedNop,
                  namaWp: widget.record.namaWajibPajak,
                  ajbResult: ajbResult,
                );
                NativeFileHelper.shareText(
                  text: text,
                  title: 'Estimasi AJB & Pajak',
                );
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              tooltip: 'Bagikan',
            ),
          ],
        ),
      ],
    );
  }
}

/// Dialog mandiri untuk simulasi AJB tanpa keterikatan pada suatu NOP tertentu.
class _StandaloneAjbDialogContent extends StatefulWidget {
  final double initialLuas;
  final int initialNjop;

  const _StandaloneAjbDialogContent({
    required this.initialLuas,
    required this.initialNjop,
  });

  @override
  State<_StandaloneAjbDialogContent> createState() =>
      _StandaloneAjbDialogContentState();
}

class _StandaloneAjbDialogContentState
    extends State<_StandaloneAjbDialogContent> {
  late TextEditingController _luasTanahCtrl;
  late TextEditingController _njopPerM2Ctrl;

  @override
  void initState() {
    super.initState();
    _luasTanahCtrl = TextEditingController(
      text: widget.initialLuas.toStringAsFixed(0),
    );
    _njopPerM2Ctrl = TextEditingController(text: widget.initialNjop.toString());
  }

  @override
  void dispose() {
    _luasTanahCtrl.dispose();
    _njopPerM2Ctrl.dispose();
    super.dispose();
  }

  double _parseDouble(TextEditingController ctrl, [double defaultValue = 0.0]) {
    final clean = ctrl.text.replaceAll(',', '.');
    return double.tryParse(clean) ?? defaultValue;
  }

  int _parseNumeric(TextEditingController ctrl, [int defaultValue = 0]) {
    final clean = ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? defaultValue;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final luas = _parseDouble(_luasTanahCtrl, 100);
    final njop = _parseNumeric(_njopPerM2Ctrl, 100000);
    final ajbResult = PbbCalculatorHelper.calculateAjb(
      luas: luas,
      njopPerM2: njop,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: theme.colorScheme.primary,
              child: Row(
                children: [
                  Icon(
                    Icons.gavel_outlined,
                    color: theme.colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'KALKULATOR AJB & SIMULASI NJOP',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _luasTanahCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Luas Tanah (m²)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _njopPerM2Ctrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'NJOP Tanah / m² (Rp)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [50000, 100000, 200000, 500000, 1000000].map((
                          nominal,
                        ) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(formatRupiah(nominal)),
                              onPressed: () => setState(
                                () => _njopPerM2Ctrl.text = nominal.toString(),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2638)
                            : const Color(0xFFE8EAF6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.indigo.shade400),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'Total Nilai Transaksi / NJOP:',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatRupiah(ajbResult.totalNilai),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PPh (2.5%):',
                                style: TextStyle(fontSize: 12),
                              ),
                              Text(
                                formatRupiah(ajbResult.pph),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PPN (2.5%):',
                                style: TextStyle(fontSize: 12),
                              ),
                              Text(
                                formatRupiah(ajbResult.ppn),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  ajbResult.kenaBphtb
                                      ? 'BPHTB (5% - Transaksi >= 80 Jt):'
                                      : 'BPHTB (Bebas / < 80 Jt):',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: ajbResult.kenaBphtb
                                        ? Colors.indigo
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatRupiah(ajbResult.bphtb),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: ajbResult.kenaBphtb
                                      ? Colors.indigo
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'TOTAL ESTIMASI PAJAK AJB:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatRupiah(ajbResult.totalBiayaPajak),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? Colors.indigo.shade200
                                      : Colors.indigo.shade900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final text =
                                  PbbCalculatorHelper.formatWhatsAppAjb(
                                    ajbResult: ajbResult,
                                  );
                              _copyToClipboard(text, 'Rincian Biaya AJB');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Salin Rincian AJB'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () {
                            final text = PbbCalculatorHelper.formatWhatsAppAjb(
                              ajbResult: ajbResult,
                            );
                            NativeFileHelper.shareText(
                              text: text,
                              title: 'Estimasi AJB & Pajak',
                            );
                          },
                          icon: const Icon(Icons.share_rounded, size: 18),
                          tooltip: 'Bagikan',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter untuk menggambar tanda tangan digital WP dari koordinat ternormalisasi (0..1000).
class _TandaTanganWpPainter extends CustomPainter {
  final List<List<int>> strokes;
  final List<int>? activeStroke;

  const _TandaTanganWpPainter({
    required this.strokes,
    required this.activeStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baselinePaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1.0;
    final baselineY = size.height * 0.80;
    canvas.drawLine(
      Offset(14, baselineY),
      Offset(size.width - 14, baselineY),
      baselinePaint,
    );

    final inkPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    final allStrokes = <List<int>>[...strokes, ?activeStroke];

    for (final pts in allStrokes) {
      if (pts.length < 2) continue;
      if (pts.length == 2) {
        final x = (pts[0] / 1000.0) * size.width;
        final y = (pts[1] / 1000.0) * size.height;
        canvas.drawCircle(Offset(x, y), 1.8, dotPaint);
        continue;
      }

      final path = Path();
      final x0 = (pts[0] / 1000.0) * size.width;
      final y0 = (pts[1] / 1000.0) * size.height;
      path.moveTo(x0, y0);

      for (int i = 2; i < pts.length - 1; i += 2) {
        final prevX = (pts[i - 2] / 1000.0) * size.width;
        final prevY = (pts[i - 1] / 1000.0) * size.height;
        final currX = (pts[i] / 1000.0) * size.width;
        final currY = (pts[i + 1] / 1000.0) * size.height;
        final midX = (prevX + currX) / 2;
        final midY = (prevY + currY) / 2;
        path.quadraticBezierTo(prevX, prevY, midX, midY);
      }

      final lastX = (pts[pts.length - 2] / 1000.0) * size.width;
      final lastY = (pts[pts.length - 1] / 1000.0) * size.height;
      path.lineTo(lastX, lastY);

      canvas.drawPath(path, inkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TandaTanganWpPainter oldDelegate) => true;
}
