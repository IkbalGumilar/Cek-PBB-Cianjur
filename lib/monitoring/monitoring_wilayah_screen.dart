import 'package:flutter/material.dart';

import '../settings_screen.dart';
import '../staff_portal_client.dart';
import '../theme_controller.dart';
import 'tab_belum_bayar.dart';
import 'tab_belum_bayar_kolektif.dart';
import 'tab_piutang.dart';
import 'tab_rangking_realisasi.dart';
import 'tab_realisasi.dart';
import 'tab_sudah_bayar.dart';
import 'tab_sudah_bayar_kolektif.dart';

/// Menu "Monitoring Wilayah" — replika 7 tab dari modul asli
/// (`mMonitoringWilayahV3`): Sudah Bayar, Belum Bayar, Realisasi, Piutang,
/// Sudah Bayar Kolektif, Belum Bayar Kolektif, Rangking Realisasi. Field per
/// tab dicocokkan langsung dengan HTML halaman aslinya (lihat masing-masing
/// file `tab_*.dart`), tata letaknya dirombak jadi form bertumpuk yang lebih
/// enak dipakai di layar sempit — bukan tabel 3 kolom seperti versi web.
class MonitoringWilayahScreen extends StatelessWidget {
  final StaffPortalClient client;
  final ThemeController themeController;

  const MonitoringWilayahScreen({
    super.key,
    required this.client,
    required this.themeController,
  });

  static const _tabs = [
    'Sudah Bayar',
    'Belum Bayar',
    'Realisasi',
    'Piutang',
    'Sudah Bayar Kolektif',
    'Belum Bayar Kolektif',
    'Rangking Realisasi',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
          title: const Text('Monitoring Wilayah'),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(themeController: themeController),
                ),
              ),
              icon: const Icon(Icons.settings),
              tooltip: 'Pengaturan',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: onPrimary,
            unselectedLabelColor: onPrimary.withValues(alpha: 0.7),
            indicatorColor: onPrimary,
            tabs: [for (final t in _tabs) Tab(text: t)],
          ),
        ),
        body: TabBarView(
          children: [
            TabSudahBayar(client: client),
            TabBelumBayar(client: client),
            TabRealisasi(client: client),
            TabPiutang(client: client),
            TabSudahBayarKolektif(client: client),
            TabBelumBayarKolektif(client: client),
            TabRangkingRealisasi(client: client),
          ],
        ),
      ),
    );
  }
}
