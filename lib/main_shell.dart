import 'package:flutter/material.dart';

import 'app_header.dart';
import 'blok_catatan_screen.dart';
import 'blok_data_store.dart';
import 'check_form_view.dart';
import 'check_mode.dart';
import 'import_view.dart';
import 'theme_controller.dart';

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
