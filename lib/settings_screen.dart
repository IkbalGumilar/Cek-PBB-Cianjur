import 'package:flutter/material.dart';

import 'app_security_service.dart';
import 'blok_backup_scheduler.dart';
import 'feature_tour/feature_tour.dart';
import 'legal_document_screen.dart';
import 'settings/about_app_screen.dart';
import 'settings/backup_settings_screen.dart';
import 'settings/security_settings_screen.dart';
import 'settings/theme_settings_screen.dart';
import 'settings/user_guide_screen.dart';
import 'settings/wilayah_settings_screen.dart';
import 'nop_helper.dart';
import 'theme_controller.dart';

export 'settings/about_app_screen.dart';
export 'settings/backup_settings_screen.dart';
export 'settings/security_settings_screen.dart';
export 'settings/theme_settings_screen.dart';
export 'settings/wilayah_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController themeController;
  final bool? isMaterialYouSupported;

  const SettingsScreen({
    super.key,
    required this.themeController,
    this.isMaterialYouSupported,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _tourId = 'settings_screen';

  final GlobalKey _themeCardKey = GlobalKey(debugLabel: 'settings_theme_card');
  final GlobalKey _securityCardKey = GlobalKey(
    debugLabel: 'settings_security_card',
  );
  final GlobalKey _backupCardKey = GlobalKey(
    debugLabel: 'settings_backup_card',
  );
  final GlobalKey _tourGuideCardKey = GlobalKey(
    debugLabel: 'settings_tour_guide_card',
  );
  final GlobalKey _aboutCardKey = GlobalKey(debugLabel: 'settings_about_card');

  bool _lockEnabled = false;
  AppLockType _lockMethod = AppLockType.device;
  String _googleAccount = '';
  int _backupFreq = 1;

  @override
  void initState() {
    super.initState();
    widget.themeController.addListener(_onThemeChanged);
    _loadSummaries();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FeatureTourController.showTourIfNeeded(
        context: context,
        tourId: _tourId,
        steps: _buildTourSteps(),
      );
    });
  }

  @override
  void dispose() {
    widget.themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void showTour() {
    if (!mounted) return;
    FeatureTourController.showTour(
      context: context,
      tourId: _tourId,
      steps: _buildTourSteps(),
    );
  }

  List<FeatureTourStep> _buildTourSteps() {
    return [
      FeatureTourStep(
        targetKey: _themeCardKey,
        title: 'Tema & Tampilan Aplikasi',
        description:
            'Ubah suasana tampilan aplikasi menjadi Terang, Gelap, atau mengikuti pengaturan perangkat Anda, serta pilih warna favorit Anda.',
        icon: Icons.palette_outlined,
        actionHint: 'Gunakan mode Terang saat bertugas di bawah sinar matahari',
      ),
      FeatureTourStep(
        targetKey: _securityCardKey,
        title: 'Keamanan & Kunci Pengaman Aplikasi',
        description:
            'Pasang pengaman Sidik Jari, PIN 6 Angka, atau Kata Sandi agar catatan pajak warga di perangkat Anda tidak bisa dibuka sembarang orang.',
        icon: Icons.lock_outline_rounded,
      ),
      FeatureTourStep(
        targetKey: _backupCardKey,
        title: 'Pencadangan Data (Simpan Cadangan)',
        description:
            'Simpan salinan buku catatan DHKP Anda ke memori perangkat atau sambungkan ke Google Drive agar data tetap aman meski ganti HP.',
        icon: Icons.cloud_sync_outlined,
        actionHint: 'Aktifkan cadangan otomatis agar tidak perlu repot menyimpan manual',
      ),
      FeatureTourStep(
        targetKey: _tourGuideCardKey,
        title: 'Buku Panduan & Pusat Bantuan',
        description:
            'Buka buku panduan visual interaktif lengkap dengan tangkapan layar bertitik nomor, pencarian fitur, dan tanya jawab (FAQ).',
        icon: Icons.menu_book_rounded,
      ),
      FeatureTourStep(
        targetKey: _aboutCardKey,
        title: 'Tentang & Bagikan Aplikasi',
        description:
            'Bagikan file aplikasi ke sesama perangkat desa/kolektor lewat WhatsApp, periksa versi aplikasi terbaru, dan lihat informasi pembuat aplikasi.',
        icon: Icons.info_outline_rounded,
      ),
    ];
  }

  Future<void> _loadSummaries() async {
    final lockEnabled = await AppSecurityService.instance.isLockEnabled();
    final lockMethod = await AppSecurityService.instance.getLockType();
    final googleAcc = await BlokBackupScheduler.instance.getGoogleAccount();
    final freq = await BlokBackupScheduler.instance.getFrequencyDays();
    if (!mounted) return;
    setState(() {
      _lockEnabled = lockEnabled;
      _lockMethod = lockMethod;
      _googleAccount = googleAcc;
      _backupFreq = freq;
    });
  }

  Future<void> _openSubScreen(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      await _loadSummaries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeLabel = ThemeSettingsSection.modeLabel(
      widget.themeController.mode,
    );
    final securitySubtitle = _lockEnabled
        ? 'Aktif • ${SecuritySettingsSection.methodLabel(_lockMethod)}'
        : 'Nonaktif • Ketuk untuk mengaktifkan kunci aplikasi';
    final backupSubtitle = _googleAccount.isNotEmpty
        ? 'Google Drive ($_googleAccount) • ${BackupSettingsSection.frequencyLabel(_backupFreq)}'
        : 'Simpan cadangan data DHKP ke HP atau Google Drive';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        actions: [
          FeatureTourHelpButton(
            onPressed: showTour,
            tooltip: 'Panduan Halaman Pengaturan',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SettingsMenuCard(
              icon: Icons.domain_rounded,
              iconColor: Colors.deepPurple.shade600,
              title: 'Wilayah Kerja & Profil Desa',
              subtitle:
                  'Kec. $activeKecamatanName • Desa $activeDesaName ($activeNopPrefix)\nKetuk untuk mengganti Kecamatan atau Desa penugasan',
              onTap: () async {
                await _openSubScreen(const WilayahSettingsScreen());
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 12),
            _SettingsMenuCard(
              key: _themeCardKey,
              icon: Icons.palette_outlined,
              iconColor: scheme.primary,
              title: 'Tema & Tampilan',
              subtitle: 'Mode $themeLabel • Atur warna aplikasi',
              onTap: () => _openSubScreen(
                ThemeSettingsScreen(
                  themeController: widget.themeController,
                  isMaterialYouSupported: widget.isMaterialYouSupported,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SettingsMenuCard(
              key: _securityCardKey,
              icon: _lockEnabled
                  ? Icons.lock_outlined
                  : Icons.lock_open_outlined,
              iconColor: _lockEnabled ? Colors.green.shade700 : scheme.primary,
              title: 'Keamanan Aplikasi',
              subtitle: securitySubtitle,
              onTap: () => _openSubScreen(const SecuritySettingsScreen()),
            ),
            const SizedBox(height: 12),
            _SettingsMenuCard(
              key: _backupCardKey,
              icon: Icons.cloud_sync_outlined,
              iconColor: Colors.teal.shade700,
              title: 'Pencadangan Data',
              subtitle: backupSubtitle,
              onTap: () => _openSubScreen(const BackupSettingsScreen()),
            ),
            const SizedBox(height: 12),
            _SettingsMenuCard(
              key: _tourGuideCardKey,
              icon: Icons.menu_book_rounded,
              iconColor: Colors.amber.shade800,
              title: 'Panduan Penggunaan Aplikasi',
              subtitle:
                  'Buku panduan visual interaktif, fungsi tombol & tanya jawab',
              onTap: () => _openSubScreen(const UserGuideScreen()),
            ),
            const SizedBox(height: 12),
            _SettingsMenuCard(
              key: _aboutCardKey,
              icon: Icons.info_outline,
              iconColor: Colors.indigo.shade600,
              title: 'Tentang & Bagikan Aplikasi',
              subtitle:
                  'Bagikan aplikasi ke teman, periksa pembaruan & info pembuat',
              onTap: () => _openSubScreen(const AboutAppScreen()),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.privacy_tip_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: const Text('Kebijakan Privasi'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LegalDocumentScreen(
                          initialType: LegalDocumentType.privacyPolicy,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(
                      Icons.gavel_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: const Text('Syarat & Ketentuan'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LegalDocumentScreen(
                          initialType: LegalDocumentType.termsOfService,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsMenuCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
