import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apk_share_helper.dart';
import 'blok_data_store.dart';
import 'license_screen.dart';
import 'operator_mode_store.dart';
import 'theme_controller.dart';
import 'update_checker.dart';
import 'update_screen.dart';
import 'wilayah_kerja_picker.dart';
import 'wilayah_kerja_store.dart';

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
  int? _selectedDusun;
  bool _isOperator = false;

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _loadDusun();
    _loadOperatorStatus();
  }

  Future<void> _loadOperatorStatus() async {
    final isOperator = await OperatorModeStore.instance.isEnabled();
    if (!mounted) return;
    setState(() => _isOperator = isOperator);
  }

  Future<void> _refreshCount() async {
    final count = await BlokDataStore.instance.totalCount;
    if (!mounted) return;
    setState(() => _totalCount = count);
  }

  Future<void> _loadDusun() async {
    final dusun = await WilayahKerjaStore.instance.selectedDusun();
    if (!mounted) return;
    setState(() => _selectedDusun = dusun);
  }

  /// Ganti wilayah kerja. Kalau sudah ada data Buku Catatan Blok tersimpan
  /// (dari wilayah sebelumnya), tanya dulu mau di-backup atau langsung
  /// dihapus — data lama sudah tidak relevan untuk wilayah yang baru.
  Future<void> _changeWilayah() async {
    final chosen = await pickDusunDialog(context, allowSkip: false, currentDusun: _selectedDusun);
    if (chosen == null || chosen == _selectedDusun) return;

    final hasData = (_totalCount ?? 0) > 0;
    if (!hasData) {
      await WilayahKerjaStore.instance.setSelectedDusun(chosen);
      if (!mounted) return;
      setState(() => _selectedDusun = chosen);
      return;
    }

    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti Wilayah Kerja?'),
        content: const Text(
          'Mengganti wilayah kerja akan menghapus semua data Buku Catatan Blok yang tersimpan '
          'sekarang (data lama sudah tidak relevan untuk wilayah yang baru).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'batal'), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'ganti'), child: const Text('Ganti Saja')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'backup'), child: const Text('Backup Dulu')),
        ],
      ),
    );
    if (action == null || action == 'batal') return;

    setState(() => _busy = true);
    try {
      if (action == 'backup') {
        await BlokDataStore.instance.exportCsv();
      }
      await BlokDataStore.instance.clearAll();
      await WilayahKerjaStore.instance.setSelectedDusun(chosen);
      await _refreshCount();
      if (!mounted) return;
      setState(() => _selectedDusun = chosen);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wilayah kerja diganti ke Dusun $chosen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengganti wilayah kerja: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['bak', 'csv']);
    if (files.isEmpty || files.first.path == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isOperator ? 'Terima Laporan Dusun?' : 'Impor Data Blok?'),
        content: Text(
          _isOperator
              ? 'Laporan dari "${files.first.name}" akan digabungkan ke data operator (baris dengan '
                  'NOP+tahun yang sama akan ditimpa).'
              : 'Data dari "${files.first.name}" akan digabungkan dengan data blok yang sudah '
                  'ada di aplikasi ini (baris dengan NOP+tahun yang sama akan ditimpa).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isOperator ? 'Terima' : 'Impor'),
          ),
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
            subtitle: const Text(
              'Simpan semua data blok ke berkas backup terenkripsi (.bak) di folder Dokumen — '
              'hanya bisa dibuka kembali oleh wilayah/mode ini sendiri.',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: _exportBackup,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_isOperator ? Icons.inbox_outlined : Icons.download_outlined),
            title: Text(_isOperator ? 'Terima Laporan Dusun' : 'Impor Data (Restore)'),
            subtitle: Text(
              _isOperator
                  ? 'Impor berkas backup (.bak) yang dikirim kepala dusun — hanya laporan asli '
                      'dari dusun (atau backup Operator) yang bisa dibuka, digabungkan ke data '
                      'operator, semua blok otomatis tercatat.'
                  : 'Muat data blok dari berkas backup (.bak) milik wilayah ini sendiri — berkas '
                      'dari wilayah lain otomatis ditolak.',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: _importRestore,
          ),
          const SizedBox(height: 16),
          Text('Wilayah Kerja', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_isOperator)
            const Text(
              'Anda adalah Operator — menerima laporan dari semua dusun, wilayah kerja tidak '
              'berlaku. Status ini permanen di perangkat ini (tidak bisa dibatalkan kecuali '
              'data aplikasi dihapus).',
            )
          else ...[
            Text(
              _selectedDusun == null
                  ? 'Belum ada wilayah kerja dipilih — hasil "Sudah Bayar" tidak akan dicatat ke '
                      'Buku Catatan Blok sampai Anda memilih dusun.'
                  : 'Wilayah kerja saat ini: Dusun $_selectedDusun. Blok di luar dusun ini tetap '
                      'bisa dicek & dibayar, hanya saja tidak dicatat.',
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.map_outlined),
              title: Text(_selectedDusun == null ? 'Pilih Wilayah Kerja' : 'Ganti Wilayah Kerja'),
              trailing: const Icon(Icons.chevron_right),
              enabled: !_busy,
              onTap: _changeWilayah,
            ),
          ],
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

  // Android: bagikan berkas APK langsung (sideload). Windows/Linux: tidak
  // ada mekanisme share-sheet berkas biner yang generik lintas platform,
  // jadi cukup salin link halaman rilis GitHub-nya — penerima unduh sendiri
  // versi yang cocok untuk sistem operasinya.
  Future<void> _shareApp() async {
    setState(() => _sharing = true);
    try {
      if (Platform.isAndroid) {
        final location = await ApkShareHelper.shareApk();
        if (!mounted) return;
        final message = location != null
            ? 'APK tersimpan di $location'
            : 'Share sheet dibuka. Gagal menyimpan salinan ke folder Dokumen.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      } else {
        await Clipboard.setData(const ClipboardData(text: UpdateChecker.releasesPageUrl));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link unduhan aplikasi disalin, tinggal tempel & bagikan.')),
        );
      }
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
          Text(
            Platform.isAndroid
                ? 'Aplikasi ini belum ada di Play Store, jadi diinstal manual. Berkas APK-nya akan '
                    'disimpan ke penyimpanan internal (folder Dokumen) dan bisa langsung dibagikan '
                    'lewat WhatsApp, Quick Share, Bluetooth, atau aplikasi lain.'
                : 'Bagikan link halaman unduhan aplikasi ini (bukan berkas langsung), supaya penerima '
                    'bisa mengunduh sendiri versi yang sesuai dengan sistem operasinya.',
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _sharing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Platform.isAndroid ? Icons.share : Icons.link),
            title: Text(Platform.isAndroid ? 'Bagikan Aplikasi (APK)' : 'Salin Link Aplikasi'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _sharing ? null : _shareApp,
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _checking = false;

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await UpdateChecker.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aplikasi sudah menggunakan versi terbaru.')),
        );
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => UpdateScreen(info: info)));
    } on UpdateCheckError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

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
            leading: _checking
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_outlined),
            title: const Text('Periksa Pembaruan'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkForUpdate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Lisensi Open Source'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseScreen())),
          ),
        ],
      ),
    );
  }
}
