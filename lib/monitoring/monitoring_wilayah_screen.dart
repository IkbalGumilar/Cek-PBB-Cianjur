import 'package:flutter/material.dart';

import '../feature_tour/feature_tour.dart';
import '../settings_screen.dart';
import '../staff_portal_client.dart';
import '../theme_controller.dart';
import 'staff_dhkp_generate_dialog.dart';
import 'staff_dhkp_sync_dialog.dart';
import 'staff_dhkp_sync_service.dart';
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
class MonitoringWilayahScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController? themeController;
  final StaffDhkpSyncOutcome? initialReportOutcome;

  /// Menandakan apakah halaman MonitoringWilayahScreen sedang terbuka aktif di layar
  static bool isCurrentlyOpen = false;

  const MonitoringWilayahScreen({
    super.key,
    required this.client,
    this.themeController,
    this.initialReportOutcome,
  });

  @override
  State<MonitoringWilayahScreen> createState() =>
      _MonitoringWilayahScreenState();
}

class _MonitoringWilayahScreenState extends State<MonitoringWilayahScreen> {
  static const String _tourId = 'monitoring_wilayah_screen';

  final GlobalKey _tabBarKey = GlobalKey(
    debugLabel: 'monitoring_wilayah_tab_bar',
  );
  final GlobalKey _tabContentKey = GlobalKey(
    debugLabel: 'monitoring_wilayah_tab_content',
  );

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
  void initState() {
    super.initState();
    MonitoringWilayahScreen.isCurrentlyOpen = true;

    if (widget.initialReportOutcome != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showStaffDhkpSyncReportDialog(context, widget.initialReportOutcome!);
      });
    }

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
    MonitoringWilayahScreen.isCurrentlyOpen = false;
    super.dispose();
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
        targetKey: _tabBarKey,
        title: '7 Jenis Laporan Pantauan Wilayah',
        description:
            'Geser ke kiri atau kanan untuk memilih laporan: Sudah Bayar, Belum Bayar, Realisasi, Tunggakan (Piutang), Kolektif, hingga Peringkat Realisasi Desa.',
        icon: Icons.tab_rounded,
        actionHint:
            'Ketuk salah satu judul tab di atas untuk berpindah laporan',
      ),
      FeatureTourStep(
        targetKey: _tabContentKey,
        title: 'Formulir Penyaring & Tabel Hasil',
        description:
            'Pilih tahun pajak, buku ketetapan, atau tanggal, lalu ketuk tombol Tampilkan untuk melihat tabel data beserta tombol Unduh/Bagikan PDF & Excel.',
        icon: Icons.table_view_rounded,
      ),
    ];
  }

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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pantauan Wilayah Desa'),
              Text(
                'Kec. ${widget.client.activeKecamatanName} - Desa ${widget.client.activeKelurahanName}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome_rounded),
              tooltip: 'Generate DHKP Baru (Timpa)',
              onPressed: () =>
                  showStaffDhkpGenerateDialog(context, client: widget.client),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_sync_rounded),
              tooltip: 'Sinkronkan Status ke DHKP',
              onPressed: () =>
                  showStaffDhkpSyncDialog(context, client: widget.client),
            ),
            FeatureTourHelpButton(
              onPressed: showTour,
              color: onPrimary,
              tooltip: 'Panduan Pantauan Wilayah',
            ),
            IconButton(
              onPressed: () {
                final tc = widget.themeController ?? ThemeController.current;
                if (tc != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(themeController: tc),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.settings),
              tooltip: 'Pengaturan',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: Container(
              key: _tabBarKey,
              child: TabBar(
                isScrollable: true,
                labelColor: onPrimary,
                unselectedLabelColor: onPrimary.withValues(alpha: 0.7),
                indicatorColor: onPrimary,
                tabs: [for (final t in _tabs) Tab(text: t)],
              ),
            ),
          ),
        ),
        body: Container(
          key: _tabContentKey,
          child: TabBarView(
            children: [
              TabSudahBayar(client: widget.client),
              TabBelumBayar(client: widget.client),
              TabRealisasi(client: widget.client),
              TabPiutang(client: widget.client),
              TabSudahBayarKolektif(client: widget.client),
              TabBelumBayarKolektif(client: widget.client),
              TabRangkingRealisasi(client: widget.client),
            ],
          ),
        ),
      ),
    );
  }
}
