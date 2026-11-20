import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_security_service.dart';
import '../backup_password_store.dart';
import '../blok_backup_scheduler.dart';
import '../user_friendly_error.dart';

/// Halaman terpisah untuk pengaturan Keamanan Aplikasi.
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keamanan Aplikasi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [SecuritySettingsSection()],
        ),
      ),
    );
  }
}

/// Widget terpisah untuk pengaturan Keamanan Aplikasi.
class SecuritySettingsSection extends StatefulWidget {
  const SecuritySettingsSection({super.key});

  static String methodLabel(AppLockType method) => switch (method) {
    AppLockType.device => Platform.isWindows
        ? 'Windows Hello / Kunci Perangkat'
        : 'Sidik Jari / Kunci Perangkat',
    AppLockType.pin => 'PIN 6 Angka',
    AppLockType.password => 'Kata Sandi',
  };

  @override
  State<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState extends State<SecuritySettingsSection> {
  bool _enabled = false;
  AppLockType _method = Platform.isLinux ? AppLockType.pin : AppLockType.device;
  int _timeoutSeconds = 0;
  bool _biometricSupported = false;
  bool _hasPin = false;
  bool _hasPassword = false;
  bool _hasBackupPassword = false;
  String _googleAccount = '';

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
    final hasBackupPass = await BackupPasswordStore.instance.hasPassword();
    final googleAcc = await BlokBackupScheduler.instance.getGoogleAccount();

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _method = (Platform.isLinux && method == AppLockType.device)
          ? AppLockType.pin
          : method;
      _timeoutSeconds = timeout;
      _biometricSupported = bioSupported;
      _hasPin = hasPin;
      _hasPassword = hasPassword;
      _hasBackupPassword = hasBackupPass;
      _googleAccount = googleAcc;
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
      if (Platform.isLinux || !_biometricSupported) {
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
        reason: Platform.isWindows
            ? 'Konfirmasi Windows Hello atau kunci perangkat untuk mengaktifkan Kunci Aplikasi'
            : 'Konfirmasi kunci perangkat untuk mengaktifkan Kunci Aplikasi',
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gagal verifikasi kunci perangkat. Gunakan PIN 6 Angka sebagai gantinya.',
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
      await service.setLockType(AppLockType.pin);
      await service.setLockEnabled(true);
      service.unlock();
      await _loadSecuritySettings();
    } else if (_method == AppLockType.password) {
      if (!_hasPassword) {
        final configured = await _showPasswordSetupDialog();
        if (!configured) return;
      }
      await service.setLockType(AppLockType.password);
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
    String? errorText;
    bool isSubmitting = false;

    bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(
              isPin ? 'Masukkan PIN Saat Ini' : 'Masukkan Kata Sandi',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  enabled: !isSubmitting,
                  keyboardType: isPin
                      ? TextInputType.number
                      : TextInputType.text,
                  maxLength: isPin ? 6 : null,
                  inputFormatters: isPin
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : null,
                  decoration: InputDecoration(
                    labelText: isPin ? 'PIN 6 Angka' : 'Kata Sandi',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final val = controller.text.trim();
                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });
                        try {
                          final valid = isPin
                              ? await service.verifyCustomPin(val)
                              : await service.verifyCustomPassword(val);
                          if (!ctx.mounted) return;
                          if (valid) {
                            Navigator.of(ctx).pop(true);
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                              errorText = isPin
                                  ? 'PIN tidak sesuai.'
                                  : 'Kata sandi salah.';
                            });
                          }
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDialogState(() {
                            isSubmitting = false;
                            errorText =
                                'Gagal memverifikasi: ${friendlyErrorMessage(e)}';
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Konfirmasi'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
    return ok == true;
  }

  Future<void> _showMethodDialog() async {
    final chosen = await showDialog<AppLockType>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih Cara Buka Kunci'),
        content: RadioGroup<AppLockType>(
          groupValue: _method,
          onChanged: (val) => Navigator.of(ctx).pop(val),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!Platform.isLinux)
                RadioListTile<AppLockType>(
                  title: Text(methodLabel(AppLockType.device)),
                  subtitle: Text(
                    _biometricSupported
                        ? (Platform.isWindows
                              ? 'Gunakan Windows Hello atau kunci layar perangkat'
                              : 'Gunakan sidik jari, wajah, atau kunci bawaan perangkat')
                        : 'Tidak tersedia di perangkat ini',
                  ),
                  value: AppLockType.device,
                  enabled: _biometricSupported,
                ),
              const RadioListTile<AppLockType>(
                title: Text('PIN 6 Angka'),
                subtitle: Text('Buka cepat dengan 6 angka pilihan Anda'),
                value: AppLockType.pin,
              ),
              const RadioListTile<AppLockType>(
                title: Text('Kata Sandi'),
                subtitle: Text('Gunakan kombinasi huruf dan angka'),
                value: AppLockType.password,
              ),
            ],
          ),
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
        reason: Platform.isWindows
            ? 'Verifikasi Windows Hello atau kunci perangkat'
            : 'Verifikasi sidik jari atau kunci perangkat',
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
    bool isSubmitting = false;

    bool? result;
    try {
      result = await showDialog<bool>(
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
                  enabled: !isSubmitting,
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
                  enabled: !isSubmitting,
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
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final p1 = pin1Controller.text.trim();
                        final p2 = pin2Controller.text.trim();
                        if (!RegExp(r'^\d{6}$').hasMatch(p1)) {
                          setDialogState(
                            () => errorText =
                                'PIN harus terdiri dari tepat 6 angka.',
                          );
                          return;
                        }
                        if (p1 != p2) {
                          setDialogState(
                            () => errorText = 'Konfirmasi PIN tidak cocok.',
                          );
                          return;
                        }
                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });
                        try {
                          await AppSecurityService.instance.setCustomPin(p1);
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDialogState(() {
                            isSubmitting = false;
                            errorText =
                                'Gagal menyimpan PIN: ${friendlyErrorMessage(e)}';
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan PIN'),
              ),
            ],
          ),
        ),
      );
    } finally {
      pin1Controller.dispose();
      pin2Controller.dispose();
    }
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
    bool isSubmitting = false;

    bool? result;
    try {
      result = await showDialog<bool>(
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
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Kata sandi baru (minimal 4 karakter)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass2Controller,
                  obscureText: true,
                  enabled: !isSubmitting,
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
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
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
                            () => errorText =
                                'Konfirmasi kata sandi tidak cocok.',
                          );
                          return;
                        }
                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });
                        try {
                          await AppSecurityService.instance.setCustomPassword(
                            p1,
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDialogState(() {
                            isSubmitting = false;
                            errorText =
                                'Gagal menyimpan kata sandi: ${friendlyErrorMessage(e)}';
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan Sandi'),
              ),
            ],
          ),
        ),
      );
    } finally {
      pass1Controller.dispose();
      pass2Controller.dispose();
    }
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
        content: RadioGroup<int>(
          groupValue: _timeoutSeconds,
          onChanged: (val) => Navigator.of(ctx).pop(val),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (sec) => RadioListTile<int>(
                    title: Text(timeoutLabel(sec)),
                    value: sec,
                  ),
                )
                .toList(),
          ),
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
    final hasGoogleAccount = _googleAccount.isNotEmpty;

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
                  'Lindungi data pajak warga di perangkat Anda agar tidak dibuka orang lain.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    _enabled ? Icons.lock_outlined : Icons.lock_open_outlined,
                    color: _enabled ? Colors.green : null,
                  ),
                  title: const Text('Kunci Pengaman Aplikasi'),
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
                    leading: Icon(
                      Platform.isLinux
                          ? Icons.pin_outlined
                          : (Platform.isWindows
                                ? Icons.verified_user_outlined
                                : Icons.fingerprint),
                    ),
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
                      title: Text(
                        _hasPin ? 'Ubah PIN 6 Angka' : 'Atur PIN 6 Angka',
                      ),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.enhanced_encryption_outlined,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Keamanan & Pemulihan Cadangan (.dkhp)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hasGoogleAccount
                      ? 'Setiap berkas cadangan (.dkhp) dilindungi enkripsi secara otomatis. Karena Akun Google ($_googleAccount) sedang terhubung, cadangan dari menu Pencadangan Data diamankan dengan kunci cadangan Akun Google agar dapat langsung dipulihkan saat Anda berganti perangkat. Kata Sandi Cadangan kustom atau Kunci Pemulihan di bawah digunakan untuk ekspor paket lokal dan cadangan tanpa Akun Google.'
                      : 'Setiap berkas cadangan (.dkhp) dilindungi enkripsi secara otomatis menggunakan Kata Sandi Cadangan kustom Anda (jika diatur) atau Kunci Pemulihan perangkat ini. Anda juga dapat menghubungkan Akun Google di menu Pencadangan Data agar kunci cadangan tersinkron otomatis antarperangkat.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: Text(
                    _hasBackupPassword
                        ? 'Ubah Kata Sandi Cadangan (.dkhp)'
                        : 'Atur Kata Sandi Cadangan (.dkhp)',
                  ),
                  subtitle: Text(
                    _hasBackupPassword
                        ? 'Aktif • Ekspor lokal & cadangan non-Google hanya dapat dibuka dengan kata sandi ini'
                        : (hasGoogleAccount
                              ? 'Tidak diatur • Cadangan Google memakai kunci Akun Google; ekspor lokal memakai Kunci Pemulihan'
                              : 'Tidak diatur • Cadangan baru diamankan dengan Kunci Pemulihan perangkat ini'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showBackupPasswordSetupDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('Lihat Kunci Pemulihan'),
                  subtitle: Text(
                    _hasBackupPassword
                        ? 'Hanya untuk membuka cadangan lama yang dibuat tanpa kata sandi kustom'
                        : 'Simpan di tempat aman untuk membuka cadangan perangkat ini di perangkat lain',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showRecoveryKeyDialog,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showRecoveryKeyDialog() async {
    String recoveryKey;
    try {
      recoveryKey = await BackupPasswordStore.instance.ensureRecoveryKey();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal mengakses Kunci Pemulihan dari penyimpanan aman perangkat: ${friendlyErrorMessage(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key_rounded, size: 36),
        title: const Text('Kunci Pemulihan Cadangan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simpan Kunci Pemulihan ini di tempat aman. Kunci ini dipakai untuk membuka berkas cadangan (.dkhp) lokal yang dibuat tanpa Kata Sandi Kustom saat dipulihkan di perangkat lain. Jika kunci ini hilang, berkas tersebut tidak dapat dibuka. (Catatan: Berkas yang dibuat dengan Kata Sandi Kustom hanya dapat dibuka dengan kata sandi tersebut, dan cadangan saat Akun Google terhubung terbuka otomatis dengan Akun Google yang sama.)',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(
              recoveryKey,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: recoveryKey));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kunci Pemulihan disalin ke papan klip.'),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Salin Kunci'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackupPasswordSetupDialog() async {
    final controller = TextEditingController();
    var obscure = true;
    String? errorText;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Kata Sandi Cadangan (.dkhp)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masukkan kata sandi minimal 8 karakter untuk mengamankan berkas cadangan .dkhp Anda:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Kata Sandi Cadangan (min. 8 karakter)',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (_hasBackupPassword)
                TextButton(
                  onPressed: () async {
                    await BackupPasswordStore.instance.clear();
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('Gunakan Kunci Pemulihan'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.length < 8) {
                    setDialogState(() {
                      errorText = 'Minimal 8 karakter.';
                    });
                    return;
                  }
                  await BackupPasswordStore.instance.save(text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );
      if (saved == true && mounted) {
        await _loadSecuritySettings();
      }
    } finally {
      controller.dispose();
    }
  }
}
