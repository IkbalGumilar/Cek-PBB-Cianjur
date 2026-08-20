import 'package:flutter/material.dart';

import '../staff_portal_client.dart';

String todayYmd() {
  final now = DateTime.now();
  return _formatYmd(now);
}

// Dulu default tab "Sudah Bayar" pakai rentang setahun penuh, tapi query
// tanpa filter selebar itu kena timeout 60 detik di server nyata (sudah
// dites) — jadi dipersempit ke 30 hari, cukup buat "Tampilkan" langsung
// berhasil begitu tab dibuka, staf tetap bisa perlebar manual kalau perlu.
String todayMinus30DaysYmd() {
  final now = DateTime.now();
  return _formatYmd(now.subtract(const Duration(days: 30)));
}

String _formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Field tanggal read-only yang membuka [showDatePicker] saat disentuh —
/// dipakai di semua tab Monitoring Wilayah untuk field-field tanggal.
class MonitoringDateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool required;

  const MonitoringDateField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
  });

  Future<void> _pick(BuildContext context) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1993),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    controller.text = _formatYmd(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _pick(context),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
    );
  }
}

/// Judul bagian kecil di dalam form filter — sekadar pemisah visual, sama
/// dipakai di semua tab.
class MonitoringSectionTitle extends StatelessWidget {
  final String text;
  const MonitoringSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Satu dropdown "Buku" yang menggabungkan pasangan field Buku Min/Buku Max
/// dari halaman asli (dua dropdown dengan nilai yang tidak sinkron: mis.
/// "Buku 1" di dropdown min bernilai 1, tapi "Buku 1" di dropdown max
/// bernilai 100000) menjadi satu pilihan yang lebih gampang dipahami —
/// meniru pola dropdown "Buku" tunggal yang halaman asli sendiri pakai di
/// modul Kolektif & Rangking Realisasi, hasil (min,max) yang dikirim ke
/// server tetap sama persis.
class BukuDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const BukuDropdown({super.key, required this.value, required this.onChanged});

  static const options = <(String key, String label, String min, String max)>[
    ('semua', 'Semua Buku', '', ''),
    ('1', 'Buku 1', '1', '100000'),
    ('12', 'Buku 1 - 2', '1', '500000'),
    ('123', 'Buku 1 - 3', '1', '2000000'),
    ('2', 'Buku 2', '100001', '500000'),
    ('23', 'Buku 2 - 3', '100001', '2000000'),
    ('3', 'Buku 3', '500001', '2000000'),
  ];

  static (String min, String max) rangeFor(String key) {
    final match = options.firstWhere((o) => o.$1 == key, orElse: () => options.first);
    return (match.$3, match.$4);
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Buku', border: OutlineInputBorder()),
      items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
      onChanged: (v) => onChanged(v ?? 'semua'),
    );
  }
}

/// Dropdown filter Bank — daftarnya dimuat dinamis dari server lewat
/// [StaffPortalClient.fetchBankOptions] (bukan nilai tetap).
class BankDropdown extends StatefulWidget {
  final StaffPortalClient client;
  final String value;
  final ValueChanged<String> onChanged;

  const BankDropdown({super.key, required this.client, required this.value, required this.onChanged});

  @override
  State<BankDropdown> createState() => _BankDropdownState();
}

class _BankDropdownState extends State<BankDropdown> {
  late final Future<List<BankOption>> _future = widget.client.fetchBankOptions();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BankOption>>(
      future: _future,
      builder: (context, snapshot) {
        final options = snapshot.data ?? const <BankOption>[];
        return DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.id == widget.value) ? widget.value : '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Bank (opsional)',
            border: const OutlineInputBorder(),
            suffixIcon: snapshot.connectionState == ConnectionState.waiting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Pilih Semua')),
            for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => widget.onChanged(v ?? ''),
        );
      },
    );
  }
}

/// Baris info wilayah statis — akun staf terkunci ke satu kelurahan (role
/// rmKelurahan di halaman asli, cuma satu opsi di dropdown Desa/Kelurahan
/// nya), jadi di sini ditampilkan sebagai info tetap, bukan dropdown yang
/// isinya cuma satu pilihan.
class WilayahBadge extends StatelessWidget {
  const WilayahBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: const [
          Icon(Icons.location_on_outlined, size: 18),
          SizedBox(width: 8),
          Text('Wilayah mengikuti akun staf yang login'),
        ],
      ),
    );
  }
}
