import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_security_service.dart';

/// Halaman terpisah untuk pengaturan Keamanan Aplikasi.
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keamanan Aplikasi'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SecuritySettingsSection(),
          ],
        ),
      ),
    );
  }
}

/// Widget terpisah untuk pengaturan Keamanan Aplikasi.
class SecuritySettingsSection extends StatefulWidget {
  const SecuritySettingsSection({super.key});

  static String methodLabel(AppLockType method) => switch (method) {
    AppLockType.device => 'Sidik Jari / Kunci HP',
    AppLockType.pin => 'PIN 6 Angka',
    AppLockType.password => 'Kata Sandi',
  };

  @override
  State<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState extends State<SecuritySettingsSection> {
  bool _enabled = false;
  AppLockType _method = AppLockType.device;
  int _timeoutSeconds = 0;
  bool _biometricSupported = false;
  bool _hasPin = false;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    final service = AppSecurityService.instance;
    final enabled = await service.isLockEnabled();
    final method = await service.getLockType();
    final timeout = await service.getTimeoutSeconds();
    final bioSupported = await service.isDeviceSupported();
    final hasPin = await service.hasCustomPin();
    final hasPassword = await service.hasCustomPassword();

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _method = method;
      _timeoutSeconds = timeout;
      _biometricSupported = bioSupported;
      _hasPin = hasPin;
      _hasPassword = hasPassword;
    });
  }

  static String methodLabel(AppLockType method) =>
      SecuritySettingsSection.methodLabel(method);

  static String timeoutLabel(int seconds) => switch (seconds) {
    0 => 'Langsung saat keluar aplikasi',
    30 => 'Setelah 30 detik',
    60 => 'Setelah 1 menit',
    300 => 'Setelah 5 menit',
    900 => 'Setelah 15 menit',
    1800 => 'Setelah 30 menit',
    _ => 'Langsung saat keluar aplikasi',
  };

  Future<void> _toggleLock(bool enable) async {
    final service = AppSecurityService.instance;
    if (!enable) {
      final verified = await _verifyCurrentCredential();
      if (!verified || !mounted) return;
      await service.setLockEnabled(false);
      await _loadSecuritySettings();
      return;
    }

    if (_method == AppLockType.device) {
      if (!_biometricSupported) {
        if (!mounted) return;
        final configured = await _showPinSetupDialog();
        if (configured) {
          await service.setLockType(AppLockType.pin);
          await service.setLockEnabled(true);
          service.unlock();
          await _loadSecuritySettings();
        }
        return;
      }
      final ok = await service.authenticateWithDevice(
        reason: 'Konfirmasi kunci layar HP untuk mengaktifkan Kunci Aplikasi',
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gagal verifikasi kunci layar HP. Gunakan PIN 6 Angka sebagai gantinya.',
            ),
          ),
        );
        return;
      }
      await service.setLockEnabled(true);
      service.unlock();
      await _loadSecuritySettings();
    } else if (_method == AppLockType.pin) {
      if (!_hasPin) {
        final configured = await _showPinSetupDialog();
        if (!configured) return;
      }
      await service.setLockEnabled(true);
      service.unlock();
      await _loadSecuritySettings();
    } else if (_method == AppLockType.password) {
      if (!_hasPassword) {
        final configured = await _showPasswordSetupDialog();
        if (!configured) return;
      }
      await service.setLockEnabled(true);
      service.unlock();
      await _loadSecuritySettings();
    }
  }

  Future<bool> _verifyCurrentCredential() async {
    final service = AppSecurityService.instance;
    if (_method == AppLockType.device) {
      return await service.authenticateWithDevice(
        reason: 'Verifikasi identitas untuk mematikan Kunci Aplikasi',
      );
    }

    final controller = TextEditingController();
    final isPin = _method == AppLockType.pin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isPin ? 'Masukkan PIN Saat Ini' : 'Masukkan Kata Sandi'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          keyboardType: isPin ? TextInputType.number : TextInputType.text,
          maxLength: isPin ? 6 : null,
          inputFormatters:
              isPin ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            labelText: isPin ? 'PIN 6 Angka' : 'Kata Sandi',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final val = controller.text.trim();
              final valid = isPin
                  ? await service.verifyCustomPin(val)
                  : await service.verifyCustomPassword(val);
              if (!ctx.mounted) return;
              if (valid) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      isPin ? 'PIN tidak sesuai.' : 'Kata sandi salah.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Konfirmasi'),
          ),
        ],
      ),
    );
    controller.dispose();
    return ok == true;
  }

  Future<void> _showMethodDialog() async {
    final chosen = await showDialog<AppLockType>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Cara Buka Kunci'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AppLockType>(
              title: const Text('Sidik Jari / Kunci HP'),
              subtitle: Text(
                _biometricSupported
                    ? 'Gunakan sidik jari, wajah, atau pola bawaan HP'
                    : 'Tidak tersedia di perangkat ini',
              ),
              value: AppLockType.device,
              groupValue: _method,
              onChanged: _biometricSupported
                  ? (val) => Navigator.of(ctx).pop(val)
                  : null,
            ),
            RadioListTile<AppLockType>(
              title: const Text('PIN 6 Angka'),
              subtitle: const Text('Buka cepat dengan 6 angka pilihan Anda'),
              value: AppLockType.pin,
              groupValue: _method,
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
            RadioListTile<AppLockType>(
              title: const Text('Kata Sandi'),
              subtitle: const Text('Gunakan kombinasi huruf dan angka'),
              value: AppLockType.password,
              groupValue: _method,
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
          ],
        ),
      ),
    );

    if (chosen == null || chosen == _method || !mounted) return;

    final service = AppSecurityService.instance;
    if (chosen == AppLockType.pin && !_hasPin) {
      final ok = await _showPinSetupDialog();
      if (!ok) return;
    } else if (chosen == AppLockType.password && !_hasPassword) {
      final ok = await _showPasswordSetupDialog();
      if (!ok) return;
    } else if (chosen == AppLockType.device) {
      final ok = await service.authenticateWithDevice(
        reason: 'Verifikasi sidik jari atau kunci layar HP',
      );
      if (!ok) return;
    }

    await service.setLockType(chosen);
    service.unlock();
    await _loadSecuritySettings();
  }

  Future<bool> _showPinSetupDialog() async {
    final pin1Controller = TextEditingController();
    final pin2Controller = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Buat PIN 6 Angka'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pin1Controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Masukkan 6 angka PIN baru',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pin2Controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Ketik ulang 6 angka PIN',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final p1 = pin1Controller.text.trim();
                final p2 = pin2Controller.text.trim();
                if (!RegExp(r'^\d{6}$').hasMatch(p1)) {
                  setDialogState(
                    () => errorText = 'PIN harus terdiri dari tepat 6 angka.',
                  );
                  return;
                }
                if (p1 != p2) {
                  setDialogState(
                    () => errorText = 'Konfirmasi PIN tidak cocok.',
                  );
                  return;
                }
                await AppSecurityService.instance.setCustomPin(p1);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: const Text('Simpan PIN'),
            ),
          ],
        ),
      ),
    );

    pin1Controller.dispose();
    pin2Controller.dispose();
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN 6 angka berhasil disimpan.')),
      );
      await _loadSecuritySettings();
      return true;
    }
    return false;
  }

  Future<bool> _showPasswordSetupDialog() async {
    final pass1Controller = TextEditingController();
    final pass2Controller = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Buat Kata Sandi Kunci'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pass1Controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kata sandi baru (minimal 4 karakter)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pass2Controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Ketik ulang kata sandi',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final p1 = pass1Controller.text.trim();
                final p2 = pass2Controller.text.trim();
                if (p1.length < 4) {
                  setDialogState(
                    () => errorText = 'Kata sandi minimal 4 karakter.',
                  );
                  return;
                }
                if (p1 != p2) {
                  setDialogState(
                    () => errorText = 'Konfirmasi kata sandi tidak cocok.',
                  );
                  return;
                }
                await AppSecurityService.instance.setCustomPassword(p1);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: const Text('Simpan Sandi'),
            ),
          ],
        ),
      ),
    );

    pass1Controller.dispose();
    pass2Controller.dispose();
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kata sandi berhasil disimpan.')),
      );
      await _loadSecuritySettings();
      return true;
    }
    return false;
  }

  Future<void> _showTimeoutDialog() async {
    const options = [0, 30, 60, 300];
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Waktu Kunci Otomatis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (sec) => RadioListTile<int>(
                  title: Text(timeoutLabel(sec)),
                  value: sec,
                  groupValue: _timeoutSeconds,
                  onChanged: (val) => Navigator.of(ctx).pop(val),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (chosen != null && chosen != _timeoutSeconds) {
      await AppSecurityService.instance.setTimeoutSeconds(chosen);
      if (mounted) setState(() => _timeoutSeconds = chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Keamanan Aplikasi',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Lindungi data pajak warga di HP Anda agar tidak dibuka orang lain.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    _enabled ? Icons.lock_outlined : Icons.lock_open_outlined,
                    color: _enabled ? Colors.green : null,
                  ),
                  title: const Text('Kunci Aplikasi (App Lock)'),
                  subtitle: Text(
                    _enabled
                        ? 'Aktif • Menggunakan ${methodLabel(_method)}'
                        : 'Nonaktif • Aplikasi dapat langsung dibuka',
                  ),
                  value: _enabled,
                  onChanged: _toggleLock,
                ),
              ],
            ),
          ),
        ),
        if (_enabled) ...[
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fingerprint),
                    title: const Text('Cara Buka Kunci'),
                    subtitle: Text(methodLabel(_method)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showMethodDialog,
                  ),
                  if (_method == AppLockType.pin) ...[
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.dialpad),
                      title: Text(_hasPin ? 'Ubah PIN 6 Angka' : 'Atur PIN 6 Angka'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showPinSetupDialog,
                    ),
                  ],
                  if (_method == AppLockType.password) ...[
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.password_outlined),
                      title: Text(
                        _hasPassword ? 'Ubah Kata Sandi' : 'Atur Kata Sandi',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showPasswordSetupDialog,
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Waktu Kunci Otomatis'),
                    subtitle: Text(timeoutLabel(_timeoutSeconds)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showTimeoutDialog,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
