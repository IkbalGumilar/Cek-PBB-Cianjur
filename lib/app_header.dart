import 'package:flutter/material.dart';

import 'check_mode.dart';
import 'feature_tour/feature_tour.dart';
import 'settings_screen.dart';
import 'theme_controller.dart';
import 'ui/app_design_system.dart';

const kHeaderGreen = Color(0xFF2E7D32);

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final CheckMode activeMode;
  final ValueChanged<CheckMode> onModeChanged;
  final ThemeController themeController;
  final bool isOperator;
  final VoidCallback onMonitoringPressed;
  final VoidCallback onDesilPressed;
  final VoidCallback onKendaraanPressed;
  final VoidCallback? onHelpPressed;
  final GlobalKey? modeMenuKey;
  final GlobalKey? settingsButtonKey;
  final bool desilSelected;
  final bool kendaraanSelected;
  final double? viewportWidth;

  const AppHeader({
    super.key,
    required this.activeMode,
    required this.onModeChanged,
    required this.themeController,
    required this.onMonitoringPressed,
    required this.onDesilPressed,
    required this.onKendaraanPressed,
    this.onHelpPressed,
    this.modeMenuKey,
    this.settingsButtonKey,
    this.desilSelected = false,
    this.kendaraanSelected = false,
    this.isOperator = false,
    this.viewportWidth,
  });

  static const _narrowThreshold = 640.0;

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
    final scheme = Theme.of(context).colorScheme;
    final primaryColor = scheme.primary;
    final onPrimary = scheme.onPrimary;
    return Material(
      color: primaryColor,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < _narrowThreshold;
            final logoAndName = _LogoAndName(isOperator: isOperator);
            final Widget menu = _ModeMenu(
              key: modeMenuKey,
              activeMode: activeMode,
              onModeChanged: onModeChanged,
              onMonitoringPressed: onMonitoringPressed,
              onDesilPressed: onDesilPressed,
              onKendaraanPressed: onKendaraanPressed,
              desilSelected: desilSelected,
              kendaraanSelected: kendaraanSelected,
            );
            final helpButton = onHelpPressed != null
                ? FeatureTourHelpButton(
                    onPressed: onHelpPressed!,
                    color: onPrimary,
                  )
                : null;
            final settingsButton = IconButton(
              key: settingsButtonKey,
              onPressed: () => _openSettings(context),
              icon: Icon(Icons.settings, color: onPrimary),
              tooltip: 'Pengaturan Aplikasi',
            );

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 8 : 16,
                vertical: isNarrow ? 4 : 8,
              ),
              child: isNarrow
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: logoAndName,
                              ),
                            ),
                            ?helpButton,
                            settingsButton,
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                          child: menu,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const SizedBox(width: 4),
                        logoAndName,
                        const SizedBox(width: 20),
                        Expanded(child: menu),
                        const SizedBox(width: 8),
                        ?helpButton,
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
  Size get preferredSize {
    if (viewportWidth != null && viewportWidth! >= _narrowThreshold) {
      return const Size.fromHeight(68);
    }
    return const Size.fromHeight(114);
  }
}

class _LogoAndName extends StatelessWidget {
  final bool isOperator;

  const _LogoAndName({required this.isOperator});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(
          radius: 19,
          backgroundColor: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(5),
            child: Image(image: AssetImage('logo/kabupaten-cianjur.png')),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Cek PBB Cianjur',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.15,
            ),
          ),
        ),
        if (isOperator) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Mode Operator — menerima laporan dari semua dusun',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
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
    super.key,
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
    IconData? leadingIcon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Latar belakang chip terpilih vs belum terpilih dibuat kontras jelas
    final chipBgColor = selected
        ? (isDark
              ? Color.alphaBlend(
                  primaryColor.withValues(alpha: 0.28),
                  const Color(0xFF1E2620),
                )
              : Colors.white)
        : (isDark
              ? const Color(0xFF262626)
              : Colors.white.withValues(alpha: 0.88));
    final isBgBright = chipBgColor.computeLuminance() > 0.5;

    const darkTextColor = Color(0xFF1F1F1F);
    const lightTextColor = Colors.white;

    final selectedTextColor = isBgBright
        ? (primaryColor.computeLuminance() > 0.4 ? darkTextColor : primaryColor)
        : (primaryColor.computeLuminance() < 0.25
              ? lightTextColor
              : primaryColor);

    final unselectedTextColor = isBgBright
        ? darkTextColor.withValues(alpha: 0.82)
        : lightTextColor.withValues(alpha: 0.88);

    return ChoiceChip(
      avatar: (!selected && leadingIcon != null)
          ? Icon(leadingIcon, size: 15, color: unselectedTextColor)
          : null,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: selected,
      checkmarkColor: selectedTextColor,
      color: WidgetStateProperty.all<Color>(chipBgColor),
      selectedColor: chipBgColor,
      backgroundColor: chipBgColor,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      ),
      labelStyle: TextStyle(
        color: selected ? selectedTextColor : unselectedTextColor,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 13,
      ),
      side: BorderSide(
        color: selected
            ? (isDark ? primaryColor : darkTextColor.withValues(alpha: 0.25))
            : (isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.08)),
        width: selected ? 1.5 : 1.0,
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
        leadingIcon: Icons.shield_outlined,
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 8),
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
