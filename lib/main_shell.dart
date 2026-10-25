import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_header.dart';
import 'blok_catatan_screen.dart';
import 'blok_data_store.dart';
import 'check_form_view.dart';
import 'check_mode.dart';
import 'desil/desil_view.dart';
import 'import_view.dart';
import 'kendaraan/kendaraan_view.dart';
import 'monitoring_hub_screen.dart';
import 'operator_mode_store.dart';
import 'petugas_quote_banner.dart';
import 'shared_storage_link_service.dart';
import 'staff_login_screen.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';
import 'update_checker.dart';
import 'update_screen.dart';

enum _ActiveView { check, import, desil, kendaraan }

class MainShell extends StatefulWidget {
  final ThemeController themeController;

  const MainShell({super.key, required this.themeController});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  CheckMode _mode = CheckMode.tagihan;
  _ActiveView _view = _ActiveView.check;
  int _formNonce = 0;
  int _quoteNonce = 0;
  String? _prefillBlok;
  String? _prefillWilayah;
  String? _prefillTahun;
  bool _isOperator = false;
  final _checkScrollController = ScrollController();
  final _kendaraanScrollController = ScrollController();
  final _desilKey = GlobalKey<DesilViewState>();

  @override
  void initState() {
    super.initState();
    unawaited(BlokDataStore.instance.loadAll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupChecks());
  }

  @override
  void dispose() {
    _checkScrollController.dispose();
    _kendaraanScrollController.dispose();
    super.dispose();
  }

  Future<void> _runStartupChecks() async {
    final isOperator = await OperatorModeStore.instance.isEnabled();
    if (!mounted) return;
    setState(() => _isOperator = isOperator);

    if (isOperator) {
      await _maybeShowOperatorWelcome();
    }
    await _checkForUpdateSilently();
    if (mounted) {
      unawaited(SharedStorageLinkService.instance.init(context));
    }
  }

  // Muncul sekali, tepat setelah Mode Operator baru diaktifkan lewat 2
  // saklar tersembunyi di layar Lisensi (lihat license_screen.dart) dan
  // aplikasi restart sendiri.
  Future<void> _maybeShowOperatorWelcome() async {
    final justEnabled = await OperatorModeStore.instance
        .consumeJustEnabledFlag();
    if (!justEnabled || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selamat Datang, Operator!'),
        content: const Text(
          'Mode Operator aktif. Anda sekarang menerima & mencatat laporan dari semua dusun, '
          'tanpa batasan wilayah kerja. Status ini permanen di perangkat ini — tidak bisa '
          'kembali jadi petugas wilayah kecuali data aplikasi dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  // Cek pembaruan otomatis saat aplikasi dibuka (dibatasi sekali per 24 jam
  // lewat UpdateChecker.checkForUpdateIfDue), tampil sebagai banner yang
  // tidak mengganggu alur cek PBB kalau tidak ada pembaruan.
  Future<void> _checkForUpdateSilently() async {
    final info = await UpdateChecker.checkForUpdateIfDue();
    if (info == null || !mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text('Pembaruan tersedia: versi ${info.version}.'),
        leading: const Icon(Icons.system_update),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UpdateScreen(info: info)),
              );
            },
            child: const Text('Lihat'),
          ),
        ],
      ),
    );
  }

  void _changeMode(CheckMode mode) {
    setState(() {
      _mode = mode;
      _view = _ActiveView.check;
      _prefillBlok = null;
      _prefillWilayah = null;
      _prefillTahun = null;
      _quoteNonce++;
    });
  }

  void _openStatusBayar(String blok, String wilayah, String tahun) {
    setState(() {
      _mode = CheckMode.statusBayar;
      _view = _ActiveView.check;
      _prefillBlok = blok;
      _prefillWilayah = wilayah;
      _prefillTahun = tahun;
      _formNonce += 1;
      _quoteNonce++;
    });
  }

  void _openImport() {
    setState(() => _view = _ActiveView.import);
  }

  // Menu "Monitoring" di header — beda dari chip Cek Tagihan/Cek Status
  // Bayar (yang cuma ganti tampilan inline), ini navigasi ke alur login +
  // MFA Portal Staf, lalu (kalau berhasil) ke MonitoringHubScreen. Sesi
  // login disimpan ke berkas (lihat StaffPortalClient), jadi di sini dicek
  // dulu apakah sesi lama masih aktif — kalau iya langsung ke
  // MonitoringHubScreen tanpa login ulang.
  Future<void> _openMonitoring() async {
    final client = StaffPortalClient();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final alreadyLoggedIn = await client.hasActiveSession();
    if (!mounted) return;
    Navigator.pop(context); // tutup dialog loading
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => alreadyLoggedIn
            ? MonitoringHubScreen(
                client: client,
                themeController: widget.themeController,
              )
            : StaffLoginScreen(
                client: client,
                themeController: widget.themeController,
              ),
      ),
    );
    if (mounted) {
      setState(() => _quoteNonce++);
    }
  }

  void _backToCheck() {
    setState(() {
      _view = _ActiveView.check;
      _quoteNonce++;
    });
  }

  Future<void> _openBukuCatatan() async {
    final request = await Navigator.push<BlokNavigationRequest>(
      context,
      MaterialPageRoute(builder: (_) => const BlokCatatanScreen()),
    );
    if (!mounted) return;
    if (request == null) {
      setState(() => _quoteNonce++);
      return;
    }
    setState(() {
      _mode = request.targetMode;
      _view = _ActiveView.check;
      _prefillBlok = request.blok;
      _prefillWilayah = request.wilayah;
      _prefillTahun =
          request.targetMode == CheckMode.tagihan ? null : request.tahun;
      _formNonce += 1;
      _quoteNonce++;
    });
  }

  void _handleBack() {
    if (_view == _ActiveView.import) {
      _backToCheck();
      return;
    }
    if (_view == _ActiveView.desil) {
      final handled = _desilKey.currentState?.handleBack() ?? false;
      if (handled) return;
      _exitApp();
      return;
    }
    if (_view == _ActiveView.kendaraan) {
      if (_kendaraanScrollController.hasClients &&
          _kendaraanScrollController.offset > 20) {
        _kendaraanScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }
      _exitApp();
      return;
    }
    if (_view == _ActiveView.check) {
      if (_checkScrollController.hasClients &&
          _checkScrollController.offset > 20) {
        _checkScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        return;
      }
      _exitApp();
      return;
    }
  }

  void _exitApp() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppHeader(
          activeMode: _mode,
          onModeChanged: _changeMode,
          themeController: widget.themeController,
          isOperator: _isOperator,
          onMonitoringPressed: _openMonitoring,
          onDesilPressed: () => setState(() => _view = _ActiveView.desil),
          onKendaraanPressed: () => setState(() => _view = _ActiveView.kendaraan),
          desilSelected: _view == _ActiveView.desil,
          kendaraanSelected: _view == _ActiveView.kendaraan,
        ),
        body: Column(
          children: [
            PetugasQuoteBanner(
              triggerNonce: _quoteNonce,
              visible: _view == _ActiveView.check,
            ),
            Expanded(
              child: IndexedStack(
                index: _view.index,
                children: [
                  CheckFormView(
                    key: ValueKey('$_mode-$_formNonce'),
                    mode: _mode,
                    scrollController: _checkScrollController,
                    onImportPressed: _openImport,
                    onOpenStatusBayar: _openStatusBayar,
                    initialBlok: _prefillBlok,
                    initialWilayah: _prefillWilayah,
                    initialTahun: _prefillTahun,
                  ),
                  _ImportWithBack(mode: _mode, onBack: _backToCheck),
                  DesilView(key: _desilKey),
                  KendaraanView(scrollController: _kendaraanScrollController),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _view == _ActiveView.check
            ? _BukuCatatanButton(onPressed: _openBukuCatatan)
            : null,
      ),
    );
  }
}

class _BukuCatatanButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BukuCatatanButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BlokDataStore.instance.countNotifier,
      builder: (context, count, _) {
        return Badge(
          alignment: AlignmentDirectional.topStart,
          offset: const Offset(6, -4),
          label: Text('$count'),
          isLabelVisible: count > 0,
          child: FloatingActionButton.extended(
            onPressed: onPressed,
            tooltip: 'Data DHKP',
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('DHKP'),
          ),
        );
      },
    );
  }
}

class _ImportWithBack extends StatelessWidget {
  final CheckMode mode;
  final VoidCallback onBack;

  const _ImportWithBack({required this.mode, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(
            children: [
              IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
              Text(
                'Import File - ${mode.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ImportView(key: ValueKey(mode), mode: mode),
        ),
      ],
    );
  }
}
