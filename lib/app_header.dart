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
  final VoidCallback onDesilPressed;
  final VoidCallback onKendaraanPressed;
  final bool desilSelected;
  final bool kendaraanSelected;

  const AppHeader({
    super.key,
    required this.activeMode,
    required this.onModeChanged,
    required this.themeController,
    required this.onMonitoringPressed,
    required this.onDesilPressed,
    required this.onKendaraanPressed,
    this.desilSelected = false,
    this.kendaraanSelected = false,
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
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: primaryColor,
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
              onDesilPressed: onDesilPressed,
              onKendaraanPressed: onKendaraanPressed,
              desilSelected: desilSelected,
              kendaraanSelected: kendaraanSelected,
            );
            final settingsButton = IconButton(
              onPressed: () => _openSettings(context),
              icon: Icon(Icons.settings, color: onPrimary),
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
        Text(
          'Cek PBB Cianjur',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
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
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
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
  final VoidCallback onDesilPressed;
  final VoidCallback onKendaraanPressed;
  final bool desilSelected;
  final bool kendaraanSelected;

  const _ModeMenu({
    required this.activeMode,
    required this.onModeChanged,
    required this.onMonitoringPressed,
    required this.onDesilPressed,
    required this.onKendaraanPressed,
    required this.desilSelected,
    required this.kendaraanSelected,
  });

  Widget _buildHeaderChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    required Color primaryColor,
    required Color onPrimary,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Latar belakang pil: putih bersih di mode terang (tidak abu-abu),
    // atau permukaan kontainer gelap di mode gelap.
    final chipBgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final isBgBright = chipBgColor.computeLuminance() > 0.5;

    // Warna teks adaptif sesuai preferensi:
    // "jika terang jadi gelap, jika kelam jadi terang"
    const darkTextColor = Color(0xFF1F1F1F);
    const lightTextColor = Colors.white;

    // Teks chip terpilih: memakai primaryColor bila kontrasnya mencukupi,
    // atau warna gelap/terang kontras tinggi bila warna aksen terlalu pucat.
    final selectedTextColor = isBgBright
        ? (primaryColor.computeLuminance() > 0.4 ? darkTextColor : primaryColor)
        : (primaryColor.computeLuminance() < 0.2
              ? lightTextColor
              : primaryColor);

    // Teks chip belum terpilih: adaptif terhadap terang/kelamnya latar belakang
    final unselectedTextColor = isBgBright ? darkTextColor : lightTextColor;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: selected,
      checkmarkColor: selectedTextColor,
      color: WidgetStateProperty.all<Color>(chipBgColor),
      selectedColor: chipBgColor,
      backgroundColor: chipBgColor,
      labelStyle: TextStyle(
        color: selected ? selectedTextColor : unselectedTextColor,
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.08),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final chips = <Widget>[
      ...CheckMode.values.map((mode) {
        final selected =
            !desilSelected && !kendaraanSelected && mode == activeMode;
        return _buildHeaderChip(
          context: context,
          label: mode.label,
          selected: selected,
          onSelected: () => onModeChanged(mode),
          primaryColor: primaryColor,
          onPrimary: onPrimary,
        );
      }),
      // Bukan mode tampilan seperti chip lain — ini navigasi ke alur
      // login + MFA Portal Staf (lihat MainShell._openMonitoring), jadi
      // sengaja tidak pernah "selected".
      _buildHeaderChip(
        context: context,
        label: 'Monitoring',
        selected: false,
        onSelected: onMonitoringPressed,
        primaryColor: primaryColor,
        onPrimary: onPrimary,
      ),
      _buildHeaderChip(
        context: context,
        label: 'Cek Kendaraan',
        selected: kendaraanSelected,
        onSelected: onKendaraanPressed,
        primaryColor: primaryColor,
        onPrimary: onPrimary,
      ),
      _buildHeaderChip(
        context: context,
        label: 'Cek Desil',
        selected: desilSelected,
        onSelected: onDesilPressed,
        primaryColor: primaryColor,
        onPrimary: onPrimary,
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
