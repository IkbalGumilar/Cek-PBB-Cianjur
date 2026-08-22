import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'staff_credentials_store.dart';
import 'staff_mfa_screen.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';

/// Layar login Portal Staf (cianjurkab.v-tax.id) — BEDA dari alur Cek Tagihan
/// / Cek Status Bayar di layar utama (yang itu portal publik, tanpa login).
/// Tahap pertama dari alur 2 langkah: username + password + captcha di sini,
/// lanjut verifikasi MFA di [StaffMfaScreen]. [themeController] cuma
/// diteruskan ke layar-layar berikutnya (butuh itu untuk akses Pengaturan) —
/// tidak dipakai apa pun di layar ini sendiri.
class StaffLoginScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController themeController;

  const StaffLoginScreen({
    super.key,
    required this.client,
    required this.themeController,
  });

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();

  Uint8List? _captchaBytes;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  String? _errorText;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
    _prefillSavedCredentials();
  }

  // Login pertama harus diketik manual — belum ada yang tersimpan. Begitu
  // login pertama berhasil (lihat _login), username & password disimpan
  // terenkripsi lewat StaffCredentialsStore, jadi login kedua dan seterusnya
  // form ini sudah terisi otomatis (captcha tetap harus diisi manual).
  Future<void> _prefillSavedCredentials() async {
    final saved = await StaffCredentialsStore.instance.read();
    if (saved == null || !mounted) return;
    _usernameController.text = saved.username;
    _passwordController.text = saved.password;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _errorText = null;
    });
    try {
      final bytes = await widget.client.fetchLoginCaptcha();
      if (!mounted) return;
      setState(() => _captchaBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal ambil captcha: $e');
    } finally {
      if (mounted) setState(() => _loadingCaptcha = false);
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final captcha = _captchaController.text.trim();

    if (username.isEmpty || password.isEmpty || captcha.isEmpty) {
      setState(
        () =>
            _errorText = 'Username, password, dan kode verifikasi wajib diisi.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final result = await widget.client.login(
        username: username,
        password: password,
        captchaCode: captcha,
      );
      if (!mounted) return;
      if (result.needsMfa) {
        await StaffCredentialsStore.instance.save(
          username: username,
          password: password,
        );
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StaffMfaScreen(
              client: widget.client,
              themeController: widget.themeController,
            ),
          ),
        );
      } else {
        setState(() => _errorText = result.errorMessage);
        _captchaController.clear();
        await _loadCaptcha();
      }
    } catch (e) {
      setState(() => _errorText = 'Gagal login: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Portal Staf')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: _loadingCaptcha
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      )
                    : _captchaBytes != null
                    ? Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Image.memory(_captchaBytes!, height: 84),
                      )
                    : const Text('Captcha belum dimuat'),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _loadingCaptcha ? null : _loadCaptcha,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ganti Captcha'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _captchaController,
                decoration: const InputDecoration(
                  labelText: 'Kode Verifikasi',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitting ? null : _login(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _login,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Login'),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
