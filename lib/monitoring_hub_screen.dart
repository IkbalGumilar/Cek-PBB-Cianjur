import 'package:flutter/material.dart';

import 'app_header.dart';
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

  const MonitoringHubScreen({super.key, required this.client, required this.themeController});

  @override
  State<MonitoringHubScreen> createState() => _MonitoringHubScreenState();
}

class _MonitoringHubScreenState extends State<MonitoringHubScreen> {
  bool _loggingOut = false;

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
      MaterialPageRoute(builder: (_) => SettingsScreen(themeController: widget.themeController)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kHeaderGreen,
        foregroundColor: Colors.white,
        title: const Text('Monitoring'),
        actions: [
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings), tooltip: 'Pengaturan'),
          IconButton(
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.logout),
            tooltip: 'Keluar dari Portal Staf',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HubMenuTile(
              icon: Icons.map_outlined,
              title: 'Monitoring Wilayah',
              subtitle: '7 tab: Sudah/Belum Bayar, Realisasi, Piutang, Sudah/Belum Bayar Kolektif, Rangking Realisasi',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MonitoringWilayahScreen(client: widget.client, themeController: widget.themeController),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _HubMenuTile(
              icon: Icons.groups_outlined,
              title: 'Pembayaran Kolektif',
              subtitle: 'Daftar grup kolektif (read-only)',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PembayaranKolektifScreen(client: widget.client, themeController: widget.themeController),
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
