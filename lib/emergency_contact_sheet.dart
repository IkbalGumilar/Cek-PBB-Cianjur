import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cloud_sync/google_account_sync_service.dart';

/// Model kontak darurat lokal/desa yang dapat ditambahkan sendiri oleh pengguna
/// (misal: Bidan Desa, Tenaga Medis, Kepala Desa, Bhabinkamtibmas, Babinsa, dll.).
class CustomEmergencyContact {
  final String id;
  final String name;
  final String category;
  final String phone;
  final bool hasWhatsApp;

  const CustomEmergencyContact({
    required this.id,
    required this.name,
    required this.category,
    required this.phone,
    this.hasWhatsApp = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'phone': phone,
    'hasWhatsApp': hasWhatsApp,
  };

  factory CustomEmergencyContact.fromJson(Map<String, dynamic> json) {
    return CustomEmergencyContact(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? 'Lainnya').toString(),
      phone: (json['phone'] ?? '').toString(),
      hasWhatsApp: json['hasWhatsApp'] != false,
    );
  }
}

/// Tombol mengambang ringkas "112" (khusus perangkat seluler) untuk membuka
/// daftar Kontak Darurat resmi Kabupaten Cianjur & kontak darurat lokal desa.
class EmergencyContactFab extends StatelessWidget {
  final VoidCallback onPressed;

  const EmergencyContactFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Kontak Darurat Kabupaten Cianjur (112)',
      child: Material(
        color: const Color(0xFFC62828),
        elevation: 4,
        shadowColor: Colors.black45,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emergency_rounded, color: Colors.white, size: 19),
                SizedBox(width: 6),
                Text(
                  '112',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Menampilkan lembar bawah (bottom sheet) berisi seluruh Kontak Darurat Resmi
/// Kabupaten Cianjur serta Kontak Darurat Lokal/Desa yang dapat dikustomisasi.
Future<void> showEmergencyContactSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _EmergencyContactSheetBody(),
  );
}

class _EmergencyContactSheetBody extends StatefulWidget {
  const _EmergencyContactSheetBody();

  @override
  State<_EmergencyContactSheetBody> createState() =>
      _EmergencyContactSheetBodyState();
}

class _EmergencyContactSheetBodyState
    extends State<_EmergencyContactSheetBody> {
  static const _prefsKey =
      GoogleAccountSyncService.customEmergencyContactsPrefsKey;

  static const _categories = [
    'Tenaga Medis / Bidan',
    'Pemerintah Desa',
    'Keamanan / Aparat',
    'Ambulans / Relawan',
    'Lainnya',
  ];

  static const _quickTemplates = [
    ('Bidan Desa', 'Tenaga Medis / Bidan'),
    ('Kepala Desa', 'Pemerintah Desa'),
    ('Bhabinkamtibmas', 'Keamanan / Aparat'),
    ('Babinsa', 'Keamanan / Aparat'),
    ('Ambulans Desa', 'Ambulans / Relawan'),
  ];

  static const _damkarPosts = [
    ('WMK 1 Cianjur (Kota)', '(0263) 281392', '0263281392'),
    ('WMK 2 Ciranjang', '(0263) 321213', '0263321213'),
    ('WMK 3 Cipanas', '(0263) 521573', '0263521573'),
    ('WMK 4 Cikalong', '(0263) 317333', '0263317333'),
    ('WMK 5 Cibeber', '(0263) 2330113', '02632330113'),
    ('WMK Sindangbarang', '(0263) 2361382', '02632361382'),
  ];

  List<CustomEmergencyContact> _customContacts = [];

  @override
  void initState() {
    super.initState();
    _loadCustomContacts();
  }

  Future<void> _loadCustomContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = decoded
          .whereType<Map>()
          .map(
            (e) => CustomEmergencyContact.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .where((c) => c.name.isNotEmpty && c.phone.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() => _customContacts = parsed);
      }
    } catch (_) {}
  }

  Future<void> _saveCustomContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _customContacts.map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_prefsKey, encoded);
      await GoogleAccountSyncService.instance.touchLocalPreferencesTimestamp();
      unawaited(GoogleAccountSyncService.instance.pushPreferencesToCloud());
    } catch (_) {}
  }

  String _normalizeDigits(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '');

  String _toWhatsAppNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) return '62${digits.substring(1)}';
    return digits;
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Tenaga Medis / Bidan':
        return Icons.medical_services_rounded;
      case 'Pemerintah Desa':
        return Icons.account_balance_rounded;
      case 'Keamanan / Aparat':
        return Icons.shield_rounded;
      case 'Ambulans / Relawan':
        return Icons.airport_shuttle_rounded;
      default:
        return Icons.contact_phone_rounded;
    }
  }

  Future<void> _openContactDialog({
    CustomEmergencyContact? existing,
    String? initialName,
    String? initialCategory,
  }) async {
    final nameCtrl = TextEditingController(
      text: existing?.name ?? initialName ?? '',
    );
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    var selectedCategory = existing?.category ?? initialCategory ?? _categories.first;
    if (!_categories.contains(selectedCategory)) {
      selectedCategory = _categories.last;
    }
    var hasWhatsApp = existing?.hasWhatsApp ?? true;
    String? formError;

    final saved = await showDialog<CustomEmergencyContact>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Tambah Kontak Darurat Lokal'
                    : 'Ubah Kontak Darurat',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Nama / Jabatan',
                        hintText: 'Contoh: Bidan Desa / Kades / Bhabinkamtibmas',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Kategori',
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        for (final cat in _categories)
                          DropdownMenuItem(value: cat, child: Text(cat)),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Nomor Telepon / HP',
                        hintText: 'Contoh: 081234567890',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: hasWhatsApp,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Aktifkan tombol WhatsApp',
                        style: TextStyle(fontSize: 13),
                      ),
                      onChanged: (val) =>
                          setDialogState(() => hasWhatsApp = val ?? true),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        formError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
                    if (name.isEmpty) {
                      setDialogState(
                        () => formError = 'Nama atau jabatan wajib diisi.',
                      );
                      return;
                    }
                    if (digits.length < 3) {
                      setDialogState(
                        () => formError = 'Nomor telepon tidak valid.',
                      );
                      return;
                    }
                    Navigator.pop(
                      dialogCtx,
                      CustomEmergencyContact(
                        id:
                            existing?.id ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        name: name,
                        category: selectedCategory,
                        phone: phone,
                        hasWhatsApp: hasWhatsApp,
                      ),
                    );
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();

    if (saved == null || !mounted) return;
    setState(() {
      final idx = _customContacts.indexWhere((c) => c.id == saved.id);
      if (idx >= 0) {
        _customContacts[idx] = saved;
      } else {
        _customContacts.add(saved);
      }
    });
    await _saveCustomContacts();
  }

  Future<void> _deleteContact(CustomEmergencyContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus Kontak Darurat?'),
        content: Text(
          'Hapus "${contact.name}" (${contact.phone}) dari daftar kontak darurat lokal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _customContacts.removeWhere((c) => c.id == contact.id);
    });
    await _saveCustomContacts();
  }

  Future<void> _dial(BuildContext context, String rawNumber) async {
    final uri = Uri(scheme: 'tel', path: _normalizeDigits(rawNumber));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tidak dapat membuka telepon untuk $rawNumber.'),
        ),
      );
    }
  }

  Future<void> _openUrl(
    BuildContext context,
    String url,
    String fallbackLabel,
  ) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fallbackLabel tidak dapat dibuka.')),
      );
    }
  }

  Future<void> _copy(BuildContext context, String label, String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nomor $label ($number) disalin.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            // Judul Sheet
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.emergency_rounded,
                    color: Color(0xFFC62828),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kontak Darurat Cianjur',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Layanan tanggap darurat resmi & kontak terdekat',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Hero Utama: Cianjur Siaga 112 (Bebas Pulsa 24 Jam)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB71C1C).withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'BEBAS PULSA • 24 JAM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Cianjur Siaga 112',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Satu nomor terpadu untuk kebakaran, bencana alam, ambulans, kecelakaan, dan keamanan.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _dial(context, '112'),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text(
                      'Hubungi 112 Sekarang',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFB71C1C),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. Kontak Darurat Lokal / Desa (Bidan, Kades, Bhabinkamtibmas, dll.)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'KONTAK DARURAT TERDEKAT / DESA',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openContactDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_customContacts.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Simpan nomor penting terdekat seperti Bidan Desa, Kepala Desa, Bhabinkamtibmas, Babinsa, atau Ambulans Desa agar bisa dihubungi sekali ketuk.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tpl in _quickTemplates)
                          ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 15),
                            label: Text(
                              tpl.$1,
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _openContactDialog(
                              initialName: tpl.$1,
                              initialCategory: tpl.$2,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              for (final c in _customContacts) ...[
                _contactTile(
                  context,
                  icon: _categoryIcon(c.category),
                  title: c.name,
                  subtitle: '${c.category} • ${c.phone}',
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    onSelected: (action) {
                      if (action == 'edit') {
                        _openContactDialog(existing: c);
                      } else if (action == 'copy') {
                        _copy(context, c.name, c.phone);
                      } else if (action == 'delete') {
                        _deleteContact(c);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Ubah Kontak'),
                      ),
                      PopupMenuItem(
                        value: 'copy',
                        child: Text('Salin Nomor'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Hapus'),
                      ),
                    ],
                  ),
                  actions: [
                    _actionChip(
                      context,
                      icon: Icons.call_rounded,
                      label: 'Telepon',
                      onTap: () => _dial(context, c.phone),
                    ),
                    if (c.hasWhatsApp)
                      _actionChip(
                        context,
                        icon: Icons.chat_rounded,
                        label: 'WhatsApp',
                        onTap: () => _openUrl(
                          context,
                          'https://wa.me/${_toWhatsAppNumber(c.phone)}',
                          'WhatsApp ${c.name}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],

            const SizedBox(height: 14),
            Text(
              'INSTANSI DARURAT KABUPATEN CIANJUR',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),

            // 3. Instansi Darurat Utama
            _contactTile(
              context,
              icon: Icons.local_police_rounded,
              title: 'Polres Cianjur / Kepolisian',
              subtitle: 'Call Center 110 • Polres (0263) 265444',
              actions: [
                _actionChip(
                  context,
                  icon: Icons.call_rounded,
                  label: '110',
                  onTap: () => _dial(context, '110'),
                ),
                _actionChip(
                  context,
                  icon: Icons.phone_in_talk_rounded,
                  label: 'Polres',
                  onTap: () => _dial(context, '0263265444'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            _contactTile(
              context,
              icon: Icons.flood_rounded,
              title: 'BPBD Kabupaten Cianjur',
              subtitle: 'Posko Darurat Bencana • WA 0811-2220-5252',
              actions: [
                _actionChip(
                  context,
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  onTap: () => _openUrl(
                    context,
                    'https://wa.me/6281122205252',
                    'WhatsApp BPBD Cianjur',
                  ),
                ),
                _actionChip(
                  context,
                  icon: Icons.call_rounded,
                  label: 'Telepon',
                  onTap: () => _dial(context, '0263282400'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            _contactTile(
              context,
              icon: Icons.local_hospital_rounded,
              title: 'Medis & Ambulans',
              subtitle: 'PSC 119 • RSUD Sayang (0263) 261026',
              actions: [
                _actionChip(
                  context,
                  icon: Icons.call_rounded,
                  label: '119',
                  onTap: () => _dial(context, '119'),
                ),
                _actionChip(
                  context,
                  icon: Icons.local_hospital_outlined,
                  label: 'RSUD',
                  onTap: () => _dial(context, '0263261026'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            _contactTile(
              context,
              icon: Icons.bolt_rounded,
              title: 'PLN Gangguan Listrik',
              subtitle: 'Call Center Nasional 123',
              actions: [
                _actionChip(
                  context,
                  icon: Icons.call_rounded,
                  label: '123',
                  onTap: () => _dial(context, '123'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 4. Damkar Cianjur (6 Pos Wilayah) — Expandable
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Pemadam Kebakaran (Damkar)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '6 Pos Wilayah Manajemen Kebakaran Cianjur',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final post in _damkarPosts)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        post.$1,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(post.$2),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Salin nomor',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () => _copy(context, post.$1, post.$2),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Telepon ${post.$1}',
                            icon: const Icon(Icons.call_rounded, size: 18),
                            onPressed: () => _dial(context, post.$3),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 5. Pengaduan Publik Resmi SP4N-LAPOR!
            _contactTile(
              context,
              icon: Icons.campaign_rounded,
              title: 'Pengaduan Resmi SP4N-LAPOR!',
              subtitle:
                  'Laporkan kendala bansos atau layanan publik (lapor.go.id)',
              actions: [
                _actionChip(
                  context,
                  icon: Icons.open_in_new_rounded,
                  label: 'Buka lapor.go.id',
                  onTap: () => _openUrl(
                    context,
                    'https://www.lapor.go.id',
                    'SP4N-LAPOR!',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _contactTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> actions,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
