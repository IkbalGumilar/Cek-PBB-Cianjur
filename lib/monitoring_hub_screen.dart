import 'package:flutter/material.dart';

import 'feature_tour/feature_tour.dart';
import 'monitoring/monitoring_wilayah_screen.dart';
import 'pembayaran_kolektif_screen.dart';
import 'settings_screen.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';

/// Menu tingkat kedua yang muncul setelah login + MFA Portal Staf berhasil —
/// meniru struktur halaman asli, yang setelah login menampilkan header kedua
/// di dalam halaman berisi menu-menu utama. Untuk versi ini baru 2 menu yang
/// dibuka: Monitoring Wilayah dan Pembayaran Kolektif.
class MonitoringHubScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController themeController;

  const MonitoringHubScreen({
    super.key,
    required this.client,
    required this.themeController,
  });

  @override
  State<MonitoringHubScreen> createState() => _MonitoringHubScreenState();
}

class _MonitoringHubScreenState extends State<MonitoringHubScreen> {
  static const String _tourId = 'monitoring_hub_screen';

  final GlobalKey _monitoringWilayahCardKey = GlobalKey(
    debugLabel: 'hub_monitoring_wilayah',
  );
  final GlobalKey _pembayaranKolektifCardKey = GlobalKey(
    debugLabel: 'hub_pembayaran_kolektif',
  );
  final GlobalKey _logoutButtonKey = GlobalKey(debugLabel: 'hub_logout_btn');

  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FeatureTourController.showTourIfNeeded(
        context: context,
        tourId: _tourId,
        steps: _buildTourSteps(),
      );
    });
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
        targetKey: _monitoringWilayahCardKey,
        title: 'Menu Pantauan Wilayah Desa',
        description:
            'Ketuk kartu ini untuk memantau perkembangan pembayaran pajak warga se-desa atau kelurahan, mulai dari daftar Sudah Bayar, Belum Bayar, Realisasi, hingga Peringkat Capaian.',
        icon: Icons.map_outlined,
        actionHint: 'Buka untuk melihat laporan lengkap wilayah Anda',
      ),
      FeatureTourStep(
        targetKey: _pembayaranKolektifCardKey,
        title: 'Menu Pembayaran Rombongan (Kolektif)',
        description:
            'Ketuk kartu ini untuk mengelola rombongan bayar pajak warga: membuat grup baru, menambah atau mengeluarkan anggota (NOP), mengunci daftar bayar, dan mencetak surat pengantar.',
        icon: Icons.groups_outlined,
        actionHint:
            'Cocok untuk kolektor yang menyetor pembayaran warga sekaligus',
      ),
      FeatureTourStep(
        targetKey: _logoutButtonKey,
        title: 'Tombol Keluar Akun Petugas',
        description:
            'Gunakan tombol ini jika Anda ingin keluar dari akun petugas atau berganti ke akun desa lainnya.',
        icon: Icons.logout_rounded,
      ),
    ];
  }

  // Sesi tersimpan lewat StaffPortalClient (lihat catatan hasActiveSession),
  // jadi perlu tombol keluar eksplisit — tanpa ini pengguna tidak punya cara
  // ganti akun atau membersihkan sesi yang macet.
  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    await widget.client.logout();
    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(themeController: widget.themeController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: onPrimary,
        title: const Text('Menu Petugas Desa'),
        actions: [
          FeatureTourHelpButton(
            onPressed: showTour,
            color: onPrimary,
            tooltip: 'Panduan Menu Petugas',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Pengaturan',
          ),
          IconButton(
            key: _logoutButtonKey,
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onPrimary,
                    ),
                  )
                : const Icon(Icons.logout),
            tooltip: 'Keluar dari Akun Petugas',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HubMenuTile(
              key: _monitoringWilayahCardKey,
              icon: Icons.map_outlined,
              title: 'Pantauan Wilayah Desa',
              subtitle:
                  '7 laporan: Sudah/Belum Bayar, Realisasi, Tunggakan, Kolektif & Peringkat Capaian',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MonitoringWilayahScreen(
                    client: widget.client,
                    themeController: widget.themeController,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _HubMenuTile(
              key: _pembayaranKolektifCardKey,
              icon: Icons.groups_outlined,
              title: 'Pembayaran Kolektif (Rombongan)',
              subtitle:
                  'Kelola grup rombongan bayar, atur daftar warga, dan cetak surat pengantar',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PembayaranKolektifScreen(
                    client: widget.client,
                    themeController: widget.themeController,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
