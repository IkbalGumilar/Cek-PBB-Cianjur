import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'monitoring_hub_screen.dart';
import 'staff_portal/staff_authenticator_store.dart';
import 'staff_portal/totp_helper.dart';
import 'staff_portal_client.dart';
import 'theme_controller.dart';
import 'ui/app_design_system.dart';

/// Layar verifikasi MFA (kode Google Authenticator) — tahap kedua login
/// portal staf, dibuka setelah [StaffLoginScreen] berhasil lolos tahap
/// username/password/captcha. Memakai instance [StaffPortalClient] yang sama
/// supaya sesi (cookie) yang sudah terbentuk tetap tersambung.
///
/// Dilengkapi generator TOTP otomatis lokal (RFC 6238), kartu status token 30 detik,
/// dukungan hubungkan kunci via salin-tempel (copas) atau impor berkas gambar QR,
/// serta fitur Auto-Fill dan Auto-Verify saat kunci sudah tersimpan.
class StaffMfaScreen extends StatefulWidget {
  final StaffPortalClient client;
  final ThemeController themeController;
  final StaffAuthenticatorStore? authenticatorStore;
  final bool enablePeriodicTimer;

  const StaffMfaScreen({
    super.key,
    required this.client,
    required this.themeController,
    this.authenticatorStore,
    this.enablePeriodicTimer = true,
  });

  @override
  State<StaffMfaScreen> createState() => _StaffMfaScreenState();
}

class _StaffMfaScreenState extends State<StaffMfaScreen> {
  late final StaffAuthenticatorStore _authStore;
  final _otpController = TextEditingController();

  bool _submitting = false;
  String? _errorText;

  // Status Google Authenticator Terintegrasi
  bool _hasSecret = false;
  String? _currentTotpCode;
  int _remainingSeconds = 30;
  double _progressRatio = 1.0;
  String _accountLabel = '';
  bool _autoVerifyEnabled = true;
  bool _autoVerifyTriggered = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _authStore = widget.authenticatorStore ?? StaffAuthenticatorStore();
    _loadAuthenticatorState();
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    if (!widget.enablePeriodicTimer) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateTotpTick();
    });
  }

  Future<void> _loadAuthenticatorState() async {
    try {
      final hasSecret = await _authStore.hasSecret();
      final autoVerify = await _authStore.isAutoVerifyEnabled();
      final label = await _authStore.getAccountLabel();

      if (!mounted) return;
      setState(() {
        _hasSecret = hasSecret;
        _autoVerifyEnabled = autoVerify;
        _accountLabel = label;
      });

      if (hasSecret) {
        await _updateTotpTick(forceNewCode: true);
        _maybeTriggerAutoVerify();
      }
    } catch (_) {}
  }

  Future<void> _updateTotpTick({bool forceNewCode = false}) async {
    final rem = TotpHelper.getRemainingSeconds();
    final ratio = TotpHelper.getProgressRatio();

    String? code = _currentTotpCode;
    if (forceNewCode || _currentTotpCode == null || rem == 30) {
      code = await _authStore.getCurrentCode();
    }

    if (!mounted) return;
    setState(() {
      _remainingSeconds = rem;
      _progressRatio = ratio;
      _currentTotpCode = code;
    });
  }

  void _maybeTriggerAutoVerify() {
    if (_hasSecret &&
        _autoVerifyEnabled &&
        !_autoVerifyTriggered &&
        _currentTotpCode != null) {
      _autoVerifyTriggered = true;
      _otpController.text = _currentTotpCode!;
      // Panggil auto-verify pada frame berikutnya setelah widget terpasang sempurna
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_submitting) {
          _verify();
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
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
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => MonitoringHubScreen(
              client: widget.client,
              themeController: widget.themeController,
            ),
          ),
          (route) => route.isFirst,
        );
      } else {
        setState(() {
          _errorText = result.errorMessage;
          _otpController.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = 'Gagal verifikasi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showConnectDialog({String? initialKey}) async {
    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConnectAuthenticatorDialog(
        store: _authStore,
        initialKey: initialKey,
        enablePeriodicTimer: widget.enablePeriodicTimer,
      ),
    );

    if (success == true) {
      await _loadAuthenticatorState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kunci Google Authenticator berhasil dihubungkan.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _importQrFromImage() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.image);
      if (res.isEmpty || res.first.path == null) return;
      final bytes = await File(res.first.path!).readAsBytes();
      if (bytes.isEmpty) return;

      final qrText = TotpHelper.decodeQrFromImageBytes(bytes);
      if (qrText == null || qrText.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak ditemukan QR Code yang terbaca pada berkas gambar. '
              'Pastikan gambar memuat QR Code Google Authenticator yang jelas dan utuh.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      await _showConnectDialog(initialKey: qrText);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membaca gambar QR: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSecret() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kunci Authenticator?'),
        content: const Text(
          'Kunci 2FA akan dihapus dari penyimpanan aman perangkat ini. '
          'Anda harus memasukkan kode secara manual dari aplikasi HP di kemudian hari.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authStore.clearSecret();
      await _loadAuthenticatorState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunci Authenticator telah dihapus.')),
      );
    }
  }

  void _copyTotpCode() {
    if (_currentTotpCode != null) {
      Clipboard.setData(ClipboardData(text: _currentTotpCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kode $_currentTotpCode disalin ke clipboard.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _fillTotpCode() {
    if (_currentTotpCode != null) {
      _otpController.text = _currentTotpCode!;
      setState(() => _errorText = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi MFA')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ResponsivePageContainer(
            isCompactForm: true,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Kartu Status Google Authenticator Terintegrasi / Promosi Hubungkan Kunci
                if (_hasSecret)
                  _buildConnectedTokenCard(colorScheme)
                else
                  _buildConnectPromoCard(colorScheme),

                const SizedBox(height: 20),

                // 2. Form Input Manual / Auto-Fill
                Text(
                  'Masukkan kode 6 digit yang dihasilkan aplikasi Google Authenticator:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 22,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'Kode Verifikasi 6 Digit',
                    hintText: '000000',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.pin),
                    suffixIcon: _otpController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _otpController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitting ? null : _verify(),
                ),
                const SizedBox(height: 8),

                FilledButton.icon(
                  icon: _submitting
                      ? const SizedBox.shrink()
                      : const Icon(Icons.login_rounded),
                  label: _submitting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Text('Verifikasi & Masuk'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _submitting ? null : _verify,
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  AppAlertBanner(
                    message: _errorText!,
                    tone: AppStatusTone.danger,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Kartu token aktif saat Secret Key sudah tersimpan
  Widget _buildConnectedTokenCard(ColorScheme colorScheme) {
    final isUrgent = _remainingSeconds <= 5;
    final countdownColor = isUrgent ? Colors.red : colorScheme.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Kartu
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.verified_user_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Google Authenticator Terhubung',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (_accountLabel.isNotEmpty)
                        Text(
                          _accountLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  tooltip: 'Opsi Kunci 2FA',
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showConnectDialog();
                    } else if (val == 'qr') {
                      _importQrFromImage();
                    } else if (val == 'delete') {
                      _confirmDeleteSecret();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Ganti / Tempel Kunci'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'qr',
                      child: Row(
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Ganti via Gambar QR'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Hapus Kunci',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Token Display & Countdown Ring
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KODE 2FA AKTIF',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: _fillTotpCode,
                          borderRadius: BorderRadius.circular(6),
                          child: Text(
                            _currentTotpCode != null
                                ? TotpHelper.formatCodeWithSpace(
                                    _currentTotpCode!,
                                  )
                                : '------',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Circular Countdown
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _progressRatio,
                          strokeWidth: 3.5,
                          backgroundColor: colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                          color: countdownColor,
                        ),
                        Text(
                          '$_remainingSeconds',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: countdownColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Baris Tombol Aksi & Toggle Auto-Verify
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.input_rounded, size: 18),
                  label: const Text('Isi ke Kolom'),
                  onPressed: _fillTotpCode,
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Salin Kode',
                  onPressed: _copyTotpCode,
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Auto-Login',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: _autoVerifyEnabled,
                      onChanged: (val) async {
                        await _authStore.setAutoVerifyEnabled(val);
                        if (!mounted) return;
                        setState(() => _autoVerifyEnabled = val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu promosi saat Secret Key belum tersimpan
  Widget _buildConnectPromoCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_clock_rounded,
                    color: colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Hubungkan Google Authenticator',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Simpan Secret Key atau impor gambar QR 2FA agar kode 6 digit terisi dan terverifikasi secara otomatis setiap kali login Monitoring.',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Hubungkan Kunci (Copas)'),
                  onPressed: () => _showConnectDialog(),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Impor Gambar QR'),
                  onPressed: _importQrFromImage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog untuk memasukkan Secret Key Base32, tautan ekspor, atau impor gambar QR
class _ConnectAuthenticatorDialog extends StatefulWidget {
  final StaffAuthenticatorStore store;
  final String? initialKey;
  final bool enablePeriodicTimer;

  const _ConnectAuthenticatorDialog({
    required this.store,
    this.initialKey,
    this.enablePeriodicTimer = true,
  });

  @override
  State<_ConnectAuthenticatorDialog> createState() =>
      _ConnectAuthenticatorDialogState();
}

class _ConnectAuthenticatorDialogState
    extends State<_ConnectAuthenticatorDialog> {
  late final TextEditingController _keyController;
  final _labelController = TextEditingController();

  List<TotpAccount> _parsedAccounts = [];
  TotpAccount? _selectedAccount;
  String? _validationError;
  String? _livePreviewCode;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initialKey);
    if (widget.initialKey != null && widget.initialKey!.isNotEmpty) {
      _processInput(widget.initialKey!);
    }
    if (widget.enablePeriodicTimer) {
      _previewTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _refreshPreviewCode();
      });
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _keyController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _refreshPreviewCode() {
    if (_selectedAccount != null) {
      try {
        final code = TotpHelper.generateTotp(
          secretBase32: _selectedAccount!.secret,
        );
        if (mounted && code != _livePreviewCode) {
          setState(() => _livePreviewCode = code);
        }
      } catch (_) {}
    }
  }

  void _processInput(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() {
        _parsedAccounts = [];
        _selectedAccount = null;
        _validationError = null;
        _livePreviewCode = null;
      });
      return;
    }

    try {
      final accounts = TotpHelper.parseImportInput(text);
      final first = accounts.first;
      final code = TotpHelper.generateTotp(secretBase32: first.secret);

      setState(() {
        _parsedAccounts = accounts;
        _selectedAccount = first;
        _validationError = null;
        _livePreviewCode = code;
        if (_labelController.text.trim().isEmpty) {
          _labelController.text = first.displayName;
        }
      });
    } on FormatException catch (e) {
      setState(() {
        _parsedAccounts = [];
        _selectedAccount = null;
        _validationError = e.message;
        _livePreviewCode = null;
      });
    } catch (e) {
      setState(() {
        _parsedAccounts = [];
        _selectedAccount = null;
        _validationError = 'Kunci tidak valid: $e';
        _livePreviewCode = null;
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text != null) {
      final text = data!.text!.trim();
      _keyController.text = text;
      _processInput(text);
    }
  }

  Future<void> _pickQrImage() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.image);
      if (!mounted || res.isEmpty || res.first.path == null) return;
      final bytes = await File(res.first.path!).readAsBytes();
      if (!mounted || bytes.isEmpty) return;

      final qrText = TotpHelper.decodeQrFromImageBytes(bytes);
      if (qrText == null || qrText.trim().isEmpty) {
        setState(() {
          _validationError =
              'Tidak ditemukan QR Code yang terbaca pada gambar tersebut. '
              'Pastikan gambar jelas dan memuat QR Code Google Authenticator yang utuh.';
          _livePreviewCode = null;
          _selectedAccount = null;
          _parsedAccounts = [];
        });
        return;
      }

      _keyController.text = qrText;
      _processInput(qrText);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validationError = 'Gagal membaca gambar QR: $e';
      });
    }
  }

  Future<void> _save() async {
    if (_selectedAccount == null) return;
    final label = _labelController.text.trim();

    await widget.store.saveSecret(
      _selectedAccount!.secret,
      accountName: label.isNotEmpty ? label : _selectedAccount!.name,
      issuer: _selectedAccount!.issuer.isNotEmpty
          ? _selectedAccount!.issuer
          : 'BAPENDA',
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isValid = _selectedAccount != null;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.vpn_key_rounded),
          SizedBox(width: 8),
          Expanded(child: Text('Hubungkan Authenticator')),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tempelkan Secret Key Base32 / tautan ekspor, atau pilih berkas gambar QR Code:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _keyController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Secret Key / Tautan Ekspor',
                  hintText: 'Contoh: JBSWY3DPEHPK3PXP atau otpauth://...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    tooltip: 'Hapus Teks',
                    onPressed: _keyController.text.isEmpty
                        ? null
                        : () {
                            _keyController.clear();
                            _processInput('');
                          },
                  ),
                ),
                onChanged: _processInput,
              ),

              const SizedBox(height: 8),

              // Tombol Tempel & Impor Gambar QR
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: const Text('Tempel Teks'),
                      onPressed: _pasteFromClipboard,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.image_search_rounded, size: 18),
                      label: const Text('Pilih Gambar QR'),
                      onPressed: _pickQrImage,
                    ),
                  ),
                ],
              ),

              if (_parsedAccounts.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Ditemukan ${_parsedAccounts.length} akun dalam data ekspor. Pilih akun:',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<TotpAccount>(
                  initialValue: _selectedAccount,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: _parsedAccounts.map((acc) {
                    return DropdownMenuItem(
                      value: acc,
                      child: Text(acc.displayName),
                    );
                  }).toList(),
                  onChanged: (acc) {
                    if (acc != null) {
                      setState(() {
                        _selectedAccount = acc;
                        _labelController.text = acc.displayName;
                        _refreshPreviewCode();
                      });
                    }
                  },
                ),
              ],

              const SizedBox(height: 12),

              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label Akun (Opsional)',
                  hintText: 'Misal: BAPENDA (admin)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // Live Preview Card
              if (isValid && _livePreviewCode != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Kunci Valid — Pratinjau Kode:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        TotpHelper.formatCodeWithSpace(_livePreviewCode!),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pastikan angka ini sesuai dengan yang tampil di aplikasi Google Authenticator Anda saat ini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_validationError != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: isValid ? _save : null,
          child: const Text('Simpan Kunci'),
        ),
      ],
    );
  }
}
