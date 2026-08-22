import 'package:flutter/material.dart';

import 'connectivity_monitor.dart';

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusConfig({
    required this.label,
    required this.icon,
    required this.color,
  });
}

const _statusConfigs = {
  NetworkStatus.noInternet: _StatusConfig(
    label: 'Tidak ada koneksi internet',
    icon: Icons.wifi_off,
    color: Color(0xFFB3261E),
  ),
  NetworkStatus.slowInternet: _StatusConfig(
    label: 'Internet lambat',
    icon: Icons.signal_wifi_statusbar_connected_no_internet_4,
    color: Color(0xFFE58A00),
  ),
  NetworkStatus.serverError: _StatusConfig(
    label: 'Server sedang bermasalah',
    icon: Icons.dns_outlined,
    color: Color(0xFFB3261E),
  ),
};

/// Pill mengambang di atas layar (mirip Dynamic Island) yang muncul otomatis
/// saat koneksi internet bermasalah atau server situs PBB tidak merespons.
class NetworkStatusOverlay extends StatelessWidget {
  const NetworkStatusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkStatus>(
      valueListenable: ConnectivityMonitor.instance.status,
      builder: (context, status, _) {
        final config = _statusConfigs[status];
        final visible = config != null;

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 24,
          right: 24,
          child: IgnorePointer(
            ignoring: !visible,
            child: Center(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                offset: visible ? Offset.zero : const Offset(0, -1.5),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: visible ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: config?.color ?? Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          config?.icon ?? Icons.circle,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            config?.label ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
