import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bank_launcher.dart';
import 'va_result.dart';

const _kodeBankAntarBank = '910200';

class VaViewScreen extends StatefulWidget {
  final VaResult result;
  final String nop;
  final String tahun;
  final String paymentCode;

  const VaViewScreen({
    super.key,
    required this.result,
    required this.nop,
    required this.tahun,
    required this.paymentCode,
  });

  @override
  State<VaViewScreen> createState() => _VaViewScreenState();
}

class _VaViewScreenState extends State<VaViewScreen> {
  List<BankApp> _bankApps = [];
  final Map<String, Uint8List?> _icons = {};
  bool _loadingBankApps = true;

  // Sengaja dikunci sampai user salin kode VA/kode bayar dulu, supaya kodenya
  // sudah aman di clipboard sebelum pindah ke aplikasi bank lain — jadi tidak
  // bingung nyari nomor VA-nya lagi begitu sudah di aplikasi bank.
  bool _bankAppsUnlocked = false;

  @override
  void initState() {
    super.initState();
    _loadBankApps();
  }

  // Daftar aplikasi tampil & bisa langsung ditekan begitu ketahuan
  // terpasang (cepat, cuma cek PackageManager) — tidak menunggu ikonnya
  // selesai diambil. Ikon menyusul mengisi satu-satu di latar belakang;
  // sebelum ikonnya siap, tile tetap bisa ditekan, cuma tampil placeholder.
  Future<void> _loadBankApps() async {
    final apps = await BankLauncher.installedApps();
    if (!mounted) return;
    setState(() {
      _bankApps = apps;
      _loadingBankApps = false;
    });
    for (final app in apps) {
      BankLauncher.getAppIcon(app.packageName).then((icon) {
        if (!mounted) return;
        setState(() => _icons[app.packageName] = icon);
      });
    }
  }

  Future<void> _copyAndNotify(String text, String label, {bool unlockBankApps = false}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    if (unlockBankApps && !_bankAppsUnlocked) {
      setState(() => _bankAppsUnlocked = true);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label disalin.')));
  }

  Future<void> _openBankApp(BankApp app) async {
    if (!_bankAppsUnlocked) return;
    final opened = await BankLauncher.launch(app);
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka ${app.label}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Scaffold(
      appBar: AppBar(title: const Text('Virtual Account PBB')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NOP: ${widget.nop}', style: Theme.of(context).textTheme.titleMedium),
              Text('Tahun Pajak: ${widget.tahun}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nomor Virtual Account (Bank BJB)', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      SelectableText(
                        result.virtualAccount,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _copyAndNotify(
                          result.virtualAccount,
                          'Nomor Virtual Account',
                          unlockBankApps: true,
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('Salin Kode VA'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Nama: ${result.customerName}'),
              const SizedBox(height: 4),
              Text(
                'Jumlah: Rp. ${result.amount}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Masa Berlaku VA: ${result.expiredAt}', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              Card(
                color: Colors.blue.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kalau aplikasi bank Anda tidak punya pilihan langsung "Bank BJB", '
                        'gunakan menu Virtual Account/Multipayment Antar Bank dengan kombinasi:',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text('Kode Bank: $_kodeBankAntarBank')),
                          TextButton(
                            onPressed: () => _copyAndNotify(_kodeBankAntarBank, 'Kode Bank'),
                            child: const Text('Salin'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: Text('Kode Bayar: ${widget.paymentCode}')),
                          TextButton(
                            onPressed: () => _copyAndNotify(
                              widget.paymentCode,
                              'Kode Bayar',
                              unlockBankApps: true,
                            ),
                            child: const Text('Salin'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Buka Aplikasi Bank', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (!_bankAppsUnlocked)
                Text(
                  'Salin kode VA atau kode bayar dulu di atas untuk mengaktifkan.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              if (_loadingBankApps)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
              else if (_bankApps.isEmpty)
                const Text('Tidak ada aplikasi bank/e-wallet yang terdeteksi di perangkat ini.')
              else
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: _bankApps.map((app) => _BankAppTile(
                        app: app,
                        iconBytes: _icons[app.packageName],
                        enabled: _bankAppsUnlocked,
                        onTap: () => _openBankApp(app),
                      )).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankAppTile extends StatelessWidget {
  final BankApp app;
  final Uint8List? iconBytes;
  final bool enabled;
  final VoidCallback onTap;

  const _BankAppTile({
    required this.app,
    required this.iconBytes,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: iconBytes != null
                    ? Image.memory(
                        iconBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        color: enabled ? null : Colors.grey,
                        colorBlendMode: enabled ? null : BlendMode.saturation,
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: const Icon(Icons.account_balance),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                app.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
