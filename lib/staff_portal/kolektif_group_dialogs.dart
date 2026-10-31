import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'staff_portal_models.dart';

class KolektifResultView extends StatelessWidget {
  final KolektifListResult result;
  final void Function(KolektifGroup group)? onAksi;

  const KolektifResultView({
    super.key,
    required this.result,
    required this.onAksi,
  });

  @override
  Widget build(BuildContext context) {
    if (result.errorMessage != null) {
      return Text(
        result.errorMessage!,
        style: const TextStyle(color: Colors.red),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Ketuk baris grup untuk Kelola Anggota / Hapus Group.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _tabel(context),
        ),
      ],
    );
  }

  Widget _tabel(BuildContext context) {
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
            onSelectChanged: onAksi == null ? null : (_) => onAksi!(g),
            cells: [
              DataCell(
                Icon(
                  Icons.more_horiz,
                  color: g.canDelete
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
              DataCell(Text(g.namaGroup)),
              DataCell(Text(g.namaKolektor)),
              DataCell(Text(g.hpKolektor)),
              DataCell(Text(g.anggota)),
              DataCell(Text(g.kodeBayar)),
              DataCell(Text(g.status)),
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
