import 'package:flutter/material.dart';

import 'app_header.dart';
import 'blok_catatan_screen.dart';
import 'blok_data_store.dart';
import 'check_form_view.dart';
import 'check_mode.dart';
import 'import_view.dart';
import 'operator_mode_store.dart';
import 'theme_controller.dart';
import 'update_checker.dart';
import 'update_screen.dart';
import 'wilayah_kerja_picker.dart';
import 'wilayah_kerja_store.dart';

enum _ActiveView { check, import }

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
  String? _prefillBlok;
  String? _prefillWilayah;
  String? _prefillTahun;
  bool _isOperator = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupChecks());
  }

  Future<void> _runStartupChecks() async {
    final isOperator = await OperatorModeStore.instance.isEnabled();
    if (!mounted) return;
    setState(() => _isOperator = isOperator);

    if (isOperator) {
      await _maybeShowOperatorWelcome();
    } else {
      await _ensureWilayahKerjaChosen();
    }
    await _checkForUpdateSilently();
  }

  // Muncul sekali, tepat setelah Mode Operator baru diaktifkan lewat 2
  // saklar tersembunyi di layar Lisensi (lihat license_screen.dart) dan
  // aplikasi restart sendiri.
  Future<void> _maybeShowOperatorWelcome() async {
    final justEnabled = await OperatorModeStore.instance.consumeJustEnabledFlag();
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
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti'))],
      ),
    );
  }

  // Tanya sekali di aplikasi pertama kali dijalankan (lihat
  // WilayahKerjaStore.hasBeenAsked) — melewati dialog ini sepenuhnya boleh,
  // cuma berarti tidak ada riwayat "Sudah Bayar" yang dicatat ke Buku
  // Catatan Blok; cek & bayar tetap jalan normal. Tidak dipanggil sama
  // sekali di Mode Operator — operator tidak terikat satu wilayah.
  Future<void> _ensureWilayahKerjaChosen() async {
    final alreadyAsked = await WilayahKerjaStore.instance.hasBeenAsked();
    if (alreadyAsked || !mounted) return;
    final chosen = await pickDusunDialog(context, allowSkip: true);
    await WilayahKerjaStore.instance.setSelectedDusun(chosen);
    await WilayahKerjaStore.instance.markAsked();
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
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Navigator.push(context, MaterialPageRoute(builder: (_) => UpdateScreen(info: info)));
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
    });
  }

  void _openImport() {
    setState(() => _view = _ActiveView.import);
  }

  void _backToCheck() {
    setState(() => _view = _ActiveView.check);
  }

  Future<void> _openBukuCatatan() async {
    final request = await Navigator.push<BlokNavigationRequest>(
      context,
      MaterialPageRoute(builder: (_) => const BlokCatatanScreen()),
    );
    if (request == null || !mounted) return;
    setState(() {
      _mode = CheckMode.statusBayar;
      _view = _ActiveView.check;
      _prefillBlok = request.blok;
      _prefillWilayah = request.wilayah;
      _prefillTahun = request.tahun;
      _formNonce += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        activeMode: _mode,
        onModeChanged: _changeMode,
        themeController: widget.themeController,
        isOperator: _isOperator,
      ),
      body: _view == _ActiveView.check
          ? CheckFormView(
              key: ValueKey('$_mode-$_formNonce'),
              mode: _mode,
              onImportPressed: _openImport,
              initialBlok: _prefillBlok,
              initialWilayah: _prefillWilayah,
              initialTahun: _prefillTahun,
            )
          : _ImportWithBack(mode: _mode, onBack: _backToCheck),
      floatingActionButton: _view == _ActiveView.check ? _BukuCatatanButton(onPressed: _openBukuCatatan) : null,
    );
  }
}

class _BukuCatatanButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BukuCatatanButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: BlokDataStore.instance.totalCount,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Badge(
          label: Text('$count'),
          isLabelVisible: count > 0,
          child: FloatingActionButton(
            onPressed: onPressed,
            tooltip: 'Buku Catatan Blok',
            child: const Icon(Icons.menu_book),
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
              Text('Import File - ${mode.label}', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        Expanded(child: ImportView(key: ValueKey(mode), mode: mode)),
      ],
    );
  }
}
