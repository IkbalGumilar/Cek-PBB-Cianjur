import 'package:flutter/material.dart';

import 'check_mode.dart';
import 'settings_screen.dart';
import 'theme_controller.dart';

const kHeaderGreen = Color(0xFF2E7D32);

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final CheckMode activeMode;
  final ValueChanged<CheckMode> onModeChanged;
  final ThemeController themeController;

  const AppHeader({
    super.key,
    required this.activeMode,
    required this.onModeChanged,
    required this.themeController,
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
            final logoAndName = _LogoAndName();
            final menu = _ModeMenu(
              activeMode: activeMode,
              onModeChanged: onModeChanged,
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
  const _LogoAndName();

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
      ],
    );
  }
}

class _ModeMenu extends StatelessWidget {
  final CheckMode activeMode;
  final ValueChanged<CheckMode> onModeChanged;

  const _ModeMenu({required this.activeMode, required this.onModeChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: CheckMode.values.map((mode) {
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
      }).toList(),
    );
  }
}
