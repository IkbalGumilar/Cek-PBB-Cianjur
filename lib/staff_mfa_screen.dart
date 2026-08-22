import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bank_launcher.dart';
import 'monitoring_hub_screen.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';

const _authenticatorPackage = 'com.google.android.apps.authenticator2';
final _authenticatorPlayStoreUrl = Uri.parse(
  'https://play.google.com/store/apps/details?id=$_authenticatorPackage',
);

/// Layar verifikasi MFA (kode Google Authenticator) — tahap kedua login
/// portal staf, dibuka setelah [StaffLoginScreen] berhasil lolos tahap
/// username/password/captcha. Memakai instance [StaffPortalClient] yang sama
/// supaya sesi (cookie) yang sudah terbentuk tetap tersambung. [themeController]
/// cuma diteruskan ke [MonitoringHubScreen] (butuh itu untuk akses Pengaturan
/// dari sana) — tidak dipakai apa pun di layar ini sendiri.
class StaffMfaScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController themeController;

  const StaffMfaScreen({
    super.key,
    required this.client,
    required this.themeController,
  });

  @override
  State<StaffMfaScreen> createState() => _StaffMfaScreenState();
}

class _StaffMfaScreenState extends State<StaffMfaScreen> {
  final _otpController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  // null = masih dicek. Dipakai buat tile "Cara Memasukkan Kode Dengan
  // Google Authenticator" di bawah — sama sistemnya dengan tile buka
  // aplikasi bank di layar VA (BankLauncher: cek terpasang, ambil ikon asli
  // dari sistem, buka langsung), bukan link ke halaman bantuan seperti versi
  // web aslinya.
  bool? _authenticatorInstalled;
  Uint8List? _authenticatorIcon;

  @override
  void initState() {
    super.initState();
    _checkAuthenticatorApp();
  }

  Future<void> _checkAuthenticatorApp() async {
    final installed = await BankLauncher.isInstalled(_authenticatorPackage);
    if (!mounted) return;
    setState(() => _authenticatorInstalled = installed);
    if (installed) {
      final icon = await BankLauncher.getAppIcon(_authenticatorPackage);
      if (!mounted) return;
      setState(() => _authenticatorIcon = icon);
    }
  }

  Future<void> _openAuthenticatorApp() async {
    if (_authenticatorInstalled == true) {
      final opened = await BankLauncher.launchPackage(_authenticatorPackage);
      if (!mounted || opened) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuka Google Authenticator.')),
      );
    } else {
      await launchUrl(
        _authenticatorPlayStoreUrl,
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() => _errorText = 'Kode verifikasi wajib diisi.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final result = await widget.client.verifyMfa(otp);
      if (!mounted) return;
      if (result.success) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Login Berhasil'),
            content: const Text('Anda berhasil masuk ke Portal Staf.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MonitoringHubScreen(
              client: widget.client,
              themeController: widget.themeController,
            ),
          ),
        );
      } else {
        setState(() {
          _errorText = result.errorMessage;
          _otpController.clear();
        });
      }
    } catch (e) {
      setState(() => _errorText = 'Gagal verifikasi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi MFA')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Masukkan kode yang telah dibuat di aplikasi Google Authenticator',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Kode Verifikasi',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitting ? null : _verify(),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _submitting ? null : _verify,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Verifikasi'),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              _AuthenticatorAppTile(
                installed: _authenticatorInstalled,
                iconBytes: _authenticatorIcon,
                onTap: _openAuthenticatorApp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sama persis judulnya dengan link "Cara Memasukkan Kode Dengan Google
/// Authenticator" di halaman web asli, tapi ketuk di sini langsung buka
/// aplikasi Google Authenticator (kalau sudah terpasang) atau halaman Play
/// Store-nya (kalau belum) — bukan halaman bantuan statis.
class _AuthenticatorAppTile extends StatelessWidget {
  final bool? installed;
  final Uint8List? iconBytes;
  final VoidCallback onTap;

  const _AuthenticatorAppTile({
    required this.installed,
    required this.iconBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: installed == null ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: iconBytes != null
                  ? Image.memory(
                      iconBytes!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 32,
                      height: 32,
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: const Icon(Icons.security, size: 20),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Cara Memasukkan Kode Dengan Google Authenticator',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
