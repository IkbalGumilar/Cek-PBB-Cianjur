import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/app_design_system.dart';
import 'staff_portal_models.dart';

class KolektifResultView extends StatefulWidget {
  final KolektifListResult result;
  final void Function(KolektifGroup group)? onAksi;

  const KolektifResultView({
    super.key,
    required this.result,
    required this.onAksi,
  });

  @override
  State<KolektifResultView> createState() => _KolektifResultViewState();
}

class _KolektifResultViewState extends State<KolektifResultView> {
  bool? _forceTableMode;

  static AppBadgeTone _toneForStatus(String status) {
    final s = status.toLowerCase();
    if (s.contains('sudah')) return AppBadgeTone.success;
    if (s.contains('siap') || s.contains('final')) return AppBadgeTone.info;
    if (s.contains('kedaluwarsa') || s.contains('kadaluarsa')) {
      return AppBadgeTone.error;
    }
    return AppBadgeTone.warning;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    if (result.errorMessage != null) {
      return AppAlertBanner(
        message: result.errorMessage!,
        tone: AppBadgeTone.error,
      );
    }
    if (result.groups.isEmpty) {
      return const AppEmptyStateCard(
        icon: Icons.groups_2_outlined,
        title: 'Belum Ada Grup Rombongan',
        subtitle:
            'Tidak ditemukan grup pembayaran kolektif untuk filter ini. Tekan "Buat Grup Rombongan Baru" di atas untuk memulai.',
      );
    }

    final isMobile = AppBreakpoints.isMobileOf(context);
    final useTableMode = _forceTableMode ?? !isMobile;
    final scheme = Theme.of(context).colorScheme;

    return AppAnimatedReveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ketuk baris grup untuk Kelola Anggota / Hapus Group (${result.groups.length} grup).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _forceTableMode = !useTableMode);
                },
                icon: Icon(
                  useTableMode
                      ? Icons.view_agenda_outlined
                      : Icons.table_rows_outlined,
                ),
                tooltip: useTableMode
                    ? 'Tampilkan sebagai Kartu Ringkas'
                    : 'Tampilkan sebagai Tabel Lengkap',
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (useTableMode)
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: AppHorizontalTableScroll(child: _tabel(context)),
            )
          else
            Column(
              children: [
                for (final g in result.groups)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 0,
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onAksi == null
                          ? null
                          : () => widget.onAksi!(g),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    g.namaGroup,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AppStatusBadge(
                                  label: g.status.isEmpty ? '-' : g.status,
                                  tone: _toneForStatus(g.status),
                                  compact: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Kolektor: ${g.namaKolektor} (${g.hpKolektor}) • ${g.anggota} Anggota',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Wilayah: ${rapikanNamaWilayah(g.kelurahan)} • Kode Bayar: ${g.kodeBayar.isEmpty ? "-" : g.kodeBayar}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tabel(BuildContext context) {
    final result = widget.result;
    final onAksi = widget.onAksi;
    return DataTable(
      showCheckboxColumn: false,
      columns: const [
        DataColumn(label: Text('')),
        DataColumn(label: Text('Nama Group')),
        DataColumn(label: Text('Nama Kolektor')),
        DataColumn(label: Text('HP Kolektor')),
        DataColumn(label: Text('Anggota')),
        DataColumn(label: Text('Kode Bayar')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Kecamatan')),
        DataColumn(label: Text('Kelurahan')),
        DataColumn(label: Text('Keterangan')),
        DataColumn(label: Text('Tanggal Kadaluarsa')),
      ],
      rows: [
        for (final g in result.groups)
          DataRow(
            onSelectChanged: onAksi == null ? null : (_) => onAksi(g),
            cells: [
              DataCell(
                Icon(
                  Icons.more_horiz,
                  color: g.canDelete
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
              DataCell(
                Text(
                  g.namaGroup,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(Text(g.namaKolektor)),
              DataCell(Text(g.hpKolektor)),
              DataCell(Text(g.anggota)),
              DataCell(Text(g.kodeBayar)),
              DataCell(
                AppStatusBadge(
                  label: g.status.isEmpty ? '-' : g.status,
                  tone: _toneForStatus(g.status),
                  compact: true,
                ),
              ),
              DataCell(Text(g.kecamatan)),
              DataCell(Text(g.kelurahan)),
              DataCell(Text(g.keterangan)),
              DataCell(Text(g.tanggalKadaluarsa)),
            ],
          ),
      ],
    );
  }
}

/// Isian mentah form Tambah Group, dibawa keluar dari dialog supaya layar
/// konfirmasi bisa menampilkannya sebelum ada request yang dikirim.
class IsianGroupBaru {
  final String namaGroup;
  final String keterangan;
  final String namaKolektor;
  final String noHpKolektor;
  final String kelurahanCode;

  const IsianGroupBaru({
    required this.namaGroup,
    required this.keterangan,
    required this.namaKolektor,
    required this.noHpKolektor,
    required this.kelurahanCode,
  });
}

/// Form "Tambah Group" / "Ubah Group".
class TambahGroupDialog extends StatefulWidget {
  final KolektifFormOptions options;
  final KolektifGroup? groupDiubah;

  const TambahGroupDialog({super.key, required this.options, this.groupDiubah});

  @override
  State<TambahGroupDialog> createState() => _TambahGroupDialogState();
}

class _TambahGroupDialogState extends State<TambahGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _namaGroup = TextEditingController();
  final _keterangan = TextEditingController();
  final _namaKolektor = TextEditingController();
  final _noHpKolektor = TextEditingController();
  String? _kelurahanCode;

  static final _teksDiizinkan = FilteringTextInputFormatter.allow(
    RegExp(r"""[a-zA-Z0-9 ()/'"_.\-]"""),
  );

  bool get _modeUbah => widget.groupDiubah != null;

  bool get _kelurahanTerkunci =>
      (_modeUbah && widget.groupDiubah!.kelurahanCode.isNotEmpty) ||
      widget.options.kelurahan.length == 1;

  @override
  void initState() {
    super.initState();
    final group = widget.groupDiubah;
    if (group != null) {
      _namaGroup.text = group.namaGroup;
      _keterangan.text = group.keterangan;
      _namaKolektor.text = group.namaKolektor;
      _noHpKolektor.text = group.hpKolektor;
      if (group.kelurahanCode.isNotEmpty) _kelurahanCode = group.kelurahanCode;
    }
    if (_kelurahanCode == null && widget.options.kelurahan.length == 1) {
      _kelurahanCode = widget.options.kelurahan.single.code;
    }
  }

  String get _namaKelurahanTerpilih {
    final cocok = widget.options.kelurahan.where(
      (k) => k.code == _kelurahanCode,
    );
    if (cocok.isNotEmpty) return rapikanNamaWilayah(cocok.first.name);
    final group = widget.groupDiubah;
    if (group != null && group.kelurahan.isNotEmpty) {
      return rapikanNamaWilayah(group.kelurahan);
    }
    return _kelurahanCode ?? '';
  }

  @override
  void dispose() {
    _namaGroup.dispose();
    _keterangan.dispose();
    _namaKolektor.dispose();
    _noHpKolektor.dispose();
    super.dispose();
  }

  String? _wajib(String? value, String namaField) =>
      (value == null || value.trim().isEmpty)
      ? '$namaField tidak boleh kosong'
      : null;

  void _lanjut() {
    if (!_formKey.currentState!.validate()) return;
    if (_kelurahanCode == null || _kelurahanCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kelurahan tidak terbaca — coba buka ulang menu Pembayaran Kolektif.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      IsianGroupBaru(
        namaGroup: _namaGroup.text.trim(),
        keterangan: _keterangan.text.trim(),
        namaKolektor: _namaKolektor.text.trim(),
        noHpKolektor: _noHpKolektor.text.trim(),
        kelurahanCode: _kelurahanCode!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_modeUbah ? 'Ubah Group' : 'Tambah Group'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _namaGroup,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_teksDiizinkan, FormatHurufBesar()],
                decoration: const InputDecoration(
                  labelText: 'Nama Group',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _wajib(v, 'Nama Group'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keterangan,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_teksDiizinkan, FormatHurufBesar()],
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _wajib(v, 'Keterangan'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _namaKolektor,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_teksDiizinkan, FormatHurufBesar()],
                decoration: const InputDecoration(
                  labelText: 'Kolektor',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _wajib(v, 'Kolektor'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noHpKolektor,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'No HP Kolektor',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final kosong = _wajib(v, 'No HP Kolektor');
                  if (kosong != null) return kosong;
                  return v!.trim().length < 10
                      ? 'No HP Kolektor minimal 10 angka'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: widget.options.kecamatanName.isNotEmpty
                    ? widget.options.kecamatanName
                    : widget.options.kecamatanCode,
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Kecamatan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_kelurahanTerkunci)
                TextFormField(
                  key: ValueKey('kel-$_kelurahanCode'),
                  initialValue: _namaKelurahanTerpilih,
                  readOnly: true,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Kelurahan',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _kelurahanCode,
                  decoration: const InputDecoration(
                    labelText: 'Kelurahan',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in widget.options.kelurahan)
                      DropdownMenuItem(
                        value: k.code,
                        child: Text(
                          rapikanNamaWilayah(k.name),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _kelurahanCode = v),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Kelurahan tidak boleh kosong'
                      : null,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kembali Ke Group'),
        ),
        FilledButton(onPressed: _lanjut, child: const Text('Lanjut')),
      ],
    );
  }
}

/// Form alasan penghapusan.
class HapusGroupDialog extends StatefulWidget {
  final String namaGroup;

  const HapusGroupDialog({super.key, required this.namaGroup});

  @override
  State<HapusGroupDialog> createState() => _HapusGroupDialogState();
}

class _HapusGroupDialogState extends State<HapusGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _alasan = TextEditingController();
  final _fokusAlasan = FocusNode();
  String? _pilihan;

  static const _alasanSiapPakai = [
    'Salah input data group',
    'Salah pilih kelurahan',
    'Nama atau nomor kolektor keliru',
    'Group dibuat ganda',
    'Group dibuat untuk uji coba',
    'Anggota batal ikut pembayaran kolektif',
  ];

  static const _lainnya = '__lainnya__';

  @override
  void dispose() {
    _alasan.dispose();
    _fokusAlasan.dispose();
    super.dispose();
  }

  void _pilihAlasan(String? nilai) {
    if (nilai == null) return;
    setState(() {
      _pilihan = nilai;
      _alasan.text = nilai == _lainnya ? '' : nilai;
      _alasan.selection = TextSelection.collapsed(offset: _alasan.text.length);
    });
    if (nilai == _lainnya) _fokusAlasan.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hapus Group Kolektif'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.namaGroup,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _pilihan,
                decoration: const InputDecoration(
                  labelText: 'Pilih Alasan',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in _alasanSiapPakai)
                    DropdownMenuItem(value: a, child: Text(a)),
                  const DropdownMenuItem(
                    value: _lainnya,
                    child: Text('Lainnya — tulis sendiri'),
                  ),
                ],
                onChanged: _pilihAlasan,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _alasan,
                focusNode: _fokusAlasan,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Alasan Penghapusan',
                  hintText: 'Masukkan alasan penghapusan group kolektif',
                  helperText:
                      'Tersimpan permanen di Log History Penghapusan beserta nama akun Anda.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Mohon isi alasan penghapusan terlebih dahulu'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _alasan.text.trim());
          },
          child: const Text('Lanjut'),
        ),
      ],
    );
  }
}

class FormatHurufBesar extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
