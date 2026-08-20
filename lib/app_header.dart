import 'package:flutter/material.dart';

import 'check_mode.dart';
import 'settings_screen.dart';
import 'theme_controller.dart';

const kHeaderGreen = Color(0xFF2E7D32);

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final CheckMode activeMode;
  final ValueChanged<CheckMode> onModeChanged;
  final ThemeController themeController;
  final bool isOperator;
  final VoidCallback onMonitoringPressed;

  const AppHeader({
    super.key,
    required this.activeMode,
    required this.onModeChanged,
    required this.themeController,
    required this.onMonitoringPressed,
    this.isOperator = false,
  });

  static const _narrowThreshold = 480.0;

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(themeController: themeController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kHeaderGreen,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < _narrowThreshold;
            final logoAndName = _LogoAndName(isOperator: isOperator);
            final menu = _ModeMenu(
              activeMode: activeMode,
              onModeChanged: onModeChanged,
              onMonitoringPressed: onMonitoringPressed,
            );
            final settingsButton = IconButton(
              onPressed: () => _openSettings(context),
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Pengaturan',
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: logoAndName,
                              ),
                            ),
                            settingsButton,
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: menu,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const SizedBox(width: 8),
                        logoAndName,
                        const SizedBox(width: 24),
                        Expanded(child: menu),
                        settingsButton,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(120);
}

class _LogoAndName extends StatelessWidget {
  final bool isOperator;

  const _LogoAndName({required this.isOperator});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(6),
            child: Image(image: AssetImage('logo/kabupaten-cianjur.png')),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Cek PBB Cianjur',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isOperator) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Mode Operator — menerima laporan dari semua dusun',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'OPERATOR',
                style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeMenu extends StatelessWidget {
  final CheckMode activeMode;
  final ValueChanged<CheckMode> onModeChanged;
  final VoidCallback onMonitoringPressed;

  const _ModeMenu({
    required this.activeMode,
    required this.onModeChanged,
    required this.onMonitoringPressed,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      ...CheckMode.values.map((mode) {
        final selected = mode == activeMode;
        return ChoiceChip(
          label: Text(mode.label),
          selected: selected,
          onSelected: (_) => onModeChanged(mode),
          selectedColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? kHeaderGreen : Colors.white,
            fontWeight: FontWeight.bold,
          ),
          backgroundColor: kHeaderGreen.withValues(alpha: 0.4),
          side: const BorderSide(color: Colors.white70),
        );
      }),
      // Bukan mode tampilan seperti chip lain — ini navigasi ke alur
      // login + MFA Portal Staf (lihat MainShell._openMonitoring), jadi
      // sengaja tidak pernah "selected".
      ChoiceChip(
        label: const Text('Monitoring'),
        selected: false,
        onSelected: (_) => onMonitoringPressed(),
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        backgroundColor: kHeaderGreen.withValues(alpha: 0.4),
        side: const BorderSide(color: Colors.white70),
      ),
    ];

    // Scroll horizontal, bukan Wrap — Wrap membuat baris kedua begitu chip
    // tidak muat (mis. layar sempit + chip "Monitoring"), dan baris kedua itu
    // mendorong tinggi header melebihi preferredSize tetap milik AppHeader
    // sehingga overflow di bagian bawah header.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}
