import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../apk_share_helper.dart';
import '../legal_document_screen.dart';
import '../license_screen.dart';
import '../update_checker.dart';
import '../update_screen.dart';

/// Halaman terpisah untuk Tentang Aplikasi & Bagikan Aplikasi.
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tentang & Bagikan Aplikasi'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            AboutAppSection(),
          ],
        ),
      ),
    );
  }
}

/// Widget terpisah yang menyatukan Tentang Aplikasi, Bagikan Aplikasi,
/// profil pembuat, pembaruan, serta dokumen hukum.
class AboutAppSection extends StatefulWidget {
  const AboutAppSection({super.key});

  @override
  State<AboutAppSection> createState() => _AboutAppSectionState();
}

class _AboutAppSectionState extends State<AboutAppSection> {
  static const _username = 'IkbalGumilar';
  static const _githubUrl = 'https://github.com/$_username';
  static const _apiUrl = 'https://api.github.com/users/$_username';
  static const _saweriaUrl = 'https://saweria.co/IkbalGumilar';

  bool _sharing = false;
  bool _checking = false;
  String _devName = 'Ikbal Gumilar';
  String? _devBio;
  String? _devAvatarUrl;

  @override
  void initState() {
    super.initState();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _loadGithubProfile();
    }
  }

  Future<void> _loadGithubProfile() async {
    try {
      final response = await Dio().get<Map<String, dynamic>>(
        _apiUrl,
        options: Options(
          headers: const {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = response.data;
      if (data == null || !mounted) return;
      setState(() {
        _devName = (data['name'] as String?)?.trim().isNotEmpty == true
            ? data['name'] as String
            : _username;
        final bio = (data['bio'] as String?)?.trim();
        _devBio = (bio != null && bio.isNotEmpty) ? bio : null;
        _devAvatarUrl = data['avatar_url'] as String?;
      });
    } catch (_) {
      // Tetap tampilkan informasi bawaan jika offline
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tautan disalin: $url')),
      );
    }
  }

  Future<void> _shareApp() async {
    setState(() => _sharing = true);
    try {
      if (Platform.isAndroid) {
        final location = await ApkShareHelper.shareApk();
        if (!mounted) return;
        final message = location != null
            ? 'APK tersimpan di $location'
            : 'Menu berbagi dibuka.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      } else {
        await Clipboard.setData(
          const ClipboardData(text: UpdateChecker.releasesPageUrl),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Link unduhan aplikasi berhasil disalin.',
            ),
          ),
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

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await UpdateChecker.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aplikasi sudah menggunakan versi terbaru.'),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UpdateScreen(info: info)),
      );
    } on UpdateCheckError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kartu Tentang Aplikasi + Bagikan Aplikasi (disatukan)
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      'logo/kabupaten-cianjur.png',
                      errorBuilder: (_, _, _) => Icon(
                        Icons.account_balance,
                        size: 32,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cek PBB Cianjur',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    if (info == null) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Versi ${info.version} (${info.buildNumber})',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Membantu perangkat desa dan kolektor mengecek tagihan, status pembayaran PBB, serta mencatat DHKP warga dengan cepat dan mudah.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _shareApp,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Platform.isAndroid ? Icons.share : Icons.link),
                    label: Text(
                      Platform.isAndroid
                          ? 'Bagikan Aplikasi (APK)'
                          : 'Salin Link Unduhan Aplikasi',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Platform.isAndroid
                      ? 'Kirim file aplikasi langsung lewat WhatsApp, Bluetooth, atau Quick Share.'
                      : 'Salin tautan halaman unduhan resmi untuk dibagikan.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Kartu Pembuat Aplikasi (Profil GitHub)
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openUrl(_githubUrl),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.primaryContainer,
                        backgroundImage: _devAvatarUrl != null
                            ? NetworkImage(_devAvatarUrl!)
                            : null,
                        onBackgroundImageError:
                            _devAvatarUrl != null ? (_, _) {} : null,
                        child: _devAvatarUrl == null
                            ? Text(
                                'IG',
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _devName,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '@$_username',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _devBio ??
                                  'Pengembang Aplikasi • Cianjur, Jawa Barat',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openUrl(_githubUrl),
                          icon: const FaIcon(FontAwesomeIcons.github, size: 16),
                          label: const Text('GitHub'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _openUrl(_saweriaUrl),
                          icon: const Icon(Icons.favorite, size: 16),
                          label: const Text('Saweria'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Kartu Pembaruan & Dokumen Resmi
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _checking
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_outlined),
                  title: const Text('Periksa Pembaruan'),
                  subtitle: const Text('Cek apakah ada versi aplikasi terbaru'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _checking ? null : _checkForUpdate,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Kebijakan Privasi'),
                  subtitle: const Text('Keamanan data & perlindungan privasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        initialType: LegalDocumentType.privacyPolicy,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Syarat & Ketentuan'),
                  subtitle: const Text('Ketentuan penggunaan aplikasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        initialType: LegalDocumentType.termsOfService,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Lisensi Open Source'),
                  subtitle: const Text('Daftar komponen perangkat lunak'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LicenseScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
