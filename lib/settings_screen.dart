import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apk_share_helper.dart';
import 'blok_data_store.dart';
import 'blok_whitelist_store.dart';
import 'theme_controller.dart';

const _githubUsername = 'IkbalGumilar';
final _githubProfileUrl = Uri.parse('https://github.com/$_githubUsername');

class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;

  const SettingsScreen({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          const _DeveloperCard(),
          const Divider(height: 32),
          _ThemeSection(themeController: themeController),
          const Divider(height: 32),
          const _BlokDataSection(),
          const Divider(height: 32),
          const _ShareAppSection(),
          const Divider(height: 32),
          const _AboutSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  @override
  Widget build(BuildContext context) {
    if (_githubUsername.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            CircleAvatar(radius: 32, child: Icon(Icons.person, size: 32)),
            SizedBox(width: 16),
            Expanded(child: Text('Cek PBB Cianjur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchGithubProfile(_githubUsername),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final name = data?['name'] as String? ?? _githubUsername;
        final bio = data?['bio'] as String?;
        final avatarUrl = data?['avatar_url'] as String?;

        return InkWell(
          onTap: () => launchUrl(_githubProfileUrl, mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null ? const Icon(Icons.person, size: 32) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FaIcon(FontAwesomeIcons.github, size: 14),
                          const SizedBox(width: 6),
                          Text('@$_githubUsername', style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                      if (bio != null && bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(bio, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchGithubProfile(String username) async {
    final response = await Dio().get<Map<String, dynamic>>(
      'https://api.github.com/users/$username',
      options: Options(
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    return response.data ?? {};
  }
}

class _ThemeSection extends StatelessWidget {
  final ThemeController themeController;

  const _ThemeSection({required this.themeController});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tema', style: Theme.of(context).textTheme.titleMedium),
          ValueListenableBuilder<AppThemeMode>(
            valueListenable: themeController,
            builder: (context, current, _) {
              return RadioGroup<AppThemeMode>(
                groupValue: current,
                onChanged: (value) {
                  if (value != null) themeController.setMode(value);
                },
                child: Column(
                  children: AppThemeMode.values.map((mode) {
                    return RadioListTile<AppThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(mode.label),
                      value: mode,
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BlokDataSection extends StatefulWidget {
  const _BlokDataSection();

  @override
  State<_BlokDataSection> createState() => _BlokDataSectionState();
}

class _BlokDataSectionState extends State<_BlokDataSection> {
  bool _busy = false;
  int? _totalCount;
  Set<String>? _whitelist;

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _loadWhitelist();
  }

  Future<void> _refreshCount() async {
    final count = await BlokDataStore.instance.totalCount;
    if (!mounted) return;
    setState(() => _totalCount = count);
  }

  Future<void> _loadWhitelist() async {
    final whitelist = await BlokWhitelistStore.instance.loadWhitelist();
    if (!mounted) return;
    setState(() => _whitelist = whitelist);
  }

  Future<void> _toggleBlok(String blok, bool included) async {
    setState(() {
      if (included) {
        _whitelist!.add(blok);
      } else {
        _whitelist!.remove(blok);
      }
    });
    await BlokWhitelistStore.instance.decide(blok, included);
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final location = await BlokDataStore.instance.exportCsv();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup tersimpan di $location')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importRestore() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (files.isEmpty || files.first.path == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Impor Data Blok?'),
        content: Text(
          'Data dari "${files.first.name}" akan digabungkan dengan data blok yang sudah '
          'ada di aplikasi ini (baris dengan NOP+tahun yang sama akan ditimpa).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Impor')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final count = await BlokDataStore.instance.importCsv(files.first.path!);
      await _refreshCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count baris berhasil diimpor.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal impor: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Blok', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _totalCount == null
                ? 'Memuat data tersimpan...'
                : '$_totalCount NOP "Sudah Bayar" tersimpan di perangkat ini, terisi otomatis '
                    'setiap kali Cek Status Bayar berhasil. Lihat di tombol buku catatan pada '
                    'menu cek.',
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Ekspor Data (Backup)'),
            subtitle: const Text('Simpan semua data blok ke berkas CSV di folder Dokumen.'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: _exportBackup,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Impor Data (Restore)'),
            subtitle: const Text('Muat data blok dari berkas CSV backup.'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: _importRestore,
          ),
          const SizedBox(height: 16),
          Text('Wilayah Kerja (Blok)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Centang blok yang termasuk wilayah kerja Anda. Blok yang belum dicentang '
            'otomatis ditanyakan lagi saat pertama kali Anda mengecek NOP di blok itu, dan '
            'disembunyikan dari Buku Catatan Blok.',
          ),
          const SizedBox(height: 8),
          if (_whitelist == null)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= totalBlokCount; i++)
                  FilterChip(
                    label: Text('$i'),
                    selected: _whitelist!.contains(i.toString().padLeft(3, '0')),
                    onSelected: (selected) => _toggleBlok(i.toString().padLeft(3, '0'), selected),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ShareAppSection extends StatefulWidget {
  const _ShareAppSection();

  @override
  State<_ShareAppSection> createState() => _ShareAppSectionState();
}

class _ShareAppSectionState extends State<_ShareAppSection> {
  bool _sharing = false;

  Future<void> _shareApp() async {
    setState(() => _sharing = true);
    try {
      final location = await ApkShareHelper.shareApk();
      if (!mounted) return;
      final message = location != null
          ? 'APK tersimpan di $location'
          : 'Share sheet dibuka. Gagal menyimpan salinan ke folder Dokumen.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membagikan aplikasi: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bagikan Aplikasi', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Aplikasi ini belum ada di Play Store, jadi diinstal manual. Berkas APK-nya akan '
            'disimpan ke penyimpanan internal (folder Dokumen) dan bisa langsung dibagikan '
            'lewat WhatsApp, Quick Share, Bluetooth, atau aplikasi lain.',
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _sharing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share),
            title: const Text('Bagikan Aplikasi (APK)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _sharing ? null : _shareApp,
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tentang Aplikasi', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Cek PBB Cianjur membantu perangkat desa mengecek tagihan dan status pembayaran '
            'PBB warga secara cepat, satuan maupun massal, tanpa perlu membuka situs resmi '
            'satu per satu di browser.',
          ),
          const SizedBox(height: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              if (info == null) return const SizedBox.shrink();
              return Text(
                'Versi ${info.version} (${info.buildNumber})',
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Lisensi Open Source'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final info = await PackageInfo.fromPlatform();
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: info.appName,
                applicationVersion: info.version,
              );
            },
          ),
        ],
      ),
    );
  }
}
