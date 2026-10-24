import 'dart:async';

import 'package:flutter/material.dart';

import 'app_security_service.dart';

/// Layar Kunci Aplikasi (App Lock Screen ala m-Banking).
/// Ditampilkan menutupi layar saat aplikasi dalam kondisi terkunci.
class AppLockScreen extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const AppLockScreen({super.key, this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final AppSecurityService _service = AppSecurityService.instance;

  AppLockType _lockType = AppLockType.device;
  bool _isLoading = true;
  String _enteredPin = '';
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _initLockState();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initLockState() async {
    final type = await _service.getLockType();
    if (!mounted) return;
    setState(() {
      _lockType = type;
      _isLoading = false;
    });

    if (type == AppLockType.device) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerDeviceAuth();
      });
    }
  }

  void _startLockoutTimer(int seconds) {
    _lockoutUntil = DateTime.now().add(Duration(seconds: seconds));
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _lockoutUntil?.difference(DateTime.now()).inSeconds ?? 0;
      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _lockoutUntil = null;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = 'Terlalu banyak percobaan salah. Coba lagi dalam $remaining detik.';
        });
      }
    });
  }

  bool _isLockedOut() {
    if (_lockoutUntil == null) return false;
    return DateTime.now().isBefore(_lockoutUntil!);
  }

  Future<void> _triggerDeviceAuth() async {
    if (_isLockedOut()) return;

    final success = await _service.authenticateWithDevice();
    if (!mounted) return;

    if (success) {
      _failedAttempts = 0;
      widget.onUnlocked?.call();
    } else {
      setState(() {
        _errorMessage = 'Autentikasi belum berhasil. Ketuk tombol untuk mencoba lagi.';
      });
    }
  }

  Future<void> _handlePinDigit(String digit) async {
    if (_isLockedOut() || _enteredPin.length >= 6) return;

    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    if (_enteredPin.length == 6) {
      final success = await _service.verifyCustomPin(_enteredPin);
      if (!mounted) return;

      if (success) {
        _failedAttempts = 0;
        widget.onUnlocked?.call();
      } else {
        _failedAttempts++;
        setState(() {
          _enteredPin = '';
          if (_failedAttempts >= 5) {
            _startLockoutTimer(30);
          } else {
            _errorMessage = 'PIN salah. Sisa percobaan: ${5 - _failedAttempts}';
          }
        });
      }
    }
  }

  void _handlePinBackspace() {
    if (_isLockedOut() || _enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _handlePasswordSubmit() async {
    if (_isLockedOut()) return;

    final pwd = _passwordController.text;
    if (pwd.isEmpty) {
      setState(() => _errorMessage = 'Masukkan kata sandi terlebih dahulu.');
      return;
    }

    final success = await _service.verifyCustomPassword(pwd);
    if (!mounted) return;

    if (success) {
      _failedAttempts = 0;
      widget.onUnlocked?.call();
    } else {
      _failedAttempts++;
      setState(() {
        _passwordController.clear();
        if (_failedAttempts >= 5) {
          _startLockoutTimer(30);
        } else {
          _errorMessage = 'Kata sandi salah. Sisa percobaan: ${5 - _failedAttempts}';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo / Ikon Kunci
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            size: 40,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Cek PBB Cianjur',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _lockType == AppLockType.device
                              ? 'Gunakan Sidik Jari, Wajah, atau Kunci Layar HP'
                              : (_lockType == AppLockType.pin
                                  ? 'Masukkan 6 Digit PIN Keamanan'
                                  : 'Masukkan Kata Sandi Aplikasi'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Pesan Error / Lockout
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                        // Form Konten Sesuai Tipe Kunci
                        if (_lockType == AppLockType.device) _buildDeviceContent(theme),
                        if (_lockType == AppLockType.pin) _buildPinContent(theme),
                        if (_lockType == AppLockType.password) _buildPasswordContent(theme),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // --- Tampilan Kunci Perangkat / Biometrik ---
  Widget _buildDeviceContent(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            elevation: 2,
          ),
          onPressed: _isLockedOut() ? null : _triggerDeviceAuth,
          icon: const Icon(Icons.fingerprint_rounded, size: 28),
          label: const Text(
            'Buka dengan Biometrik / Kunci HP',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Mendukung Sensor Sidik Jari, Pengenalan Wajah,\ndan Kunci Layar (PIN / Pola) bawaan ponsel.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  // --- Tampilan PIN Kustom 6 Digit ---
  Widget _buildPinContent(ThemeData theme) {
    return Column(
      children: [
        // Indikator 6 Bulatan PIN
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            final isFilled = index < _enteredPin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: isFilled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),

        // Keypad Angka Ala m-Banking
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            children: [
              for (var row = 0; row < 3; row++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var col = 1; col <= 3; col++)
                        _buildKeypadButton(
                          digit: '${row * 3 + col}',
                          theme: theme,
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Tombol Kosong / Clear
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: TextButton(
                        onPressed: _enteredPin.isEmpty
                            ? null
                            : () => setState(() => _enteredPin = ''),
                        child: const Text('Hapus', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    _buildKeypadButton(digit: '0', theme: theme),
                    // Tombol Backspace
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: IconButton(
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: _enteredPin.isEmpty ? null : _handlePinBackspace,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadButton({required String digit, required ThemeData theme}) {
    return SizedBox(
      width: 68,
      height: 68,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
          padding: EdgeInsets.zero,
        ),
        onPressed: _isLockedOut() ? null : () => _handlePinDigit(digit),
        child: Text(
          digit,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // --- Tampilan Kata Sandi Kustom ---
  Widget _buildPasswordContent(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        children: [
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Kata Sandi Aplikasi',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onSubmitted: (_) => _handlePasswordSubmit(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isLockedOut() ? null : _handlePasswordSubmit,
              child: const Text('Buka Kunci', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
