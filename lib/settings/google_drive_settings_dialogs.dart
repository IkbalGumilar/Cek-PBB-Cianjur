import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../google_auth_service.dart';
import '../google_drive_backup_policy.dart';
import '../google_drive_picker_dialog.dart';
import '../legal_document_screen.dart';
import '../user_friendly_error.dart';

class GoogleAccountDialog extends StatefulWidget {
  final String initialEmail;
  final String initialDisplayName;
  final String initialPhotoUrl;

  const GoogleAccountDialog({
    super.key,
    required this.initialEmail,
    this.initialDisplayName = '',
    this.initialPhotoUrl = '',
  });

  @override
  State<GoogleAccountDialog> createState() => _GoogleAccountDialogState();
}

class _GoogleAccountDialogState extends State<GoogleAccountDialog> {
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    if (_loading) {
      unawaited(GoogleAuthService.instance.cancelPendingDesktopSignIn());
    }
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final user = await GoogleAuthService.instance.signIn();
      if (!mounted) return;
      if (user != null) {
        unawaited(GoogleDriveService.instance.ensureDedicatedFolder());
        Navigator.of(context).pop(user.email);
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = friendlyErrorMessage(
          e,
          fallback: 'Gagal menghubungkan Akun Google. Silakan coba lagi.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initialEmail.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.green),
          SizedBox(width: 8),
          Text('Akun Google & Drive'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 20, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          GoogleDriveBackupPolicy.privacyNoticeTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          GoogleDriveBackupPolicy.privacyNoticeBody,
                          style: TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LegalDocumentScreen(
                                  initialType: LegalDocumentType.privacyPolicy,
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Baca Kebijakan Privasi »',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (hasInitial) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.teal.shade100,
                      backgroundImage: widget.initialPhotoUrl.isNotEmpty
                          ? NetworkImage(widget.initialPhotoUrl)
                          : null,
                      onBackgroundImageError: widget.initialPhotoUrl.isNotEmpty
                          ? (_, _) {}
                          : null,
                      child: widget.initialPhotoUrl.isEmpty
                          ? const Icon(
                              Icons.account_circle,
                              color: Colors.teal,
                              size: 28,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.initialDisplayName.isNotEmpty)
                            Text(
                              widget.initialDisplayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          Text(
                            widget.initialEmail,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Terhubung ke Google Drive',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cadangan disimpan di folder "${GoogleDriveBackupPolicy.dedicatedFolderName}".',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blueGrey.shade900
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.blueGrey.shade700
                        : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.add_to_drive_outlined,
                          size: 18,
                          color: isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade800,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Izin Akses Google Drive',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hubungkan akun Google agar berkas cadangan DHKP otomatis disimpan ke folder "${GoogleDriveBackupPolicy.dedicatedFolderName}" di Google Drive Anda.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _handleGoogleSignIn,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const FaIcon(
                          FontAwesomeIcons.google,
                          color: Colors.red,
                          size: 18,
                        ),
                  label: Text(
                    _loading
                        ? 'Menghubungkan...'
                        : 'Masuk & Izinkan Google Drive',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor: isDark
                        ? Colors.grey.shade800
                        : Colors.white,
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (hasInitial)
          TextButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text(
              'Putuskan Akun',
              style: TextStyle(color: Colors.red),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: Text(hasInitial ? 'Tutup' : 'Batal'),
        ),
      ],
    );
  }
}
