import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../blok_backup_scheduler.dart';
import '../blok_data_store.dart';
import '../dkhp_package_helper.dart';
import '../google_auth_service.dart';
import '../google_drive_backup_policy.dart';
import '../cloud_sync/google_account_sync_service.dart';
import '../google_drive_picker_dialog.dart';
import '../incoming_file_service.dart';
import '../native_file_helper.dart';
import '../unity_lerp_widgets.dart';
import '../user_friendly_error.dart';
import 'google_drive_settings_dialogs.dart';

/// Halaman terpisah untuk pengaturan Pencadangan Data DHKP.
class BackupSettingsScreen extends StatelessWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pencadangan Data')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [BackupSettingsSection()],
        ),
      ),
    );
  }
}

/// Widget terpisah untuk pengaturan Pencadangan Data DHKP.
class BackupSettingsSection extends StatefulWidget {
  const BackupSettingsSection({super.key});

  static String frequencyLabel(int days) => switch (days) {
    0 => 'Jangan pernah (Hanya manual)',
    1 => 'Harian (setiap pukul 02.00 pagi)',
    7 => 'Mingguan (setiap 7 hari)',
    14 => 'Setiap 14 hari',
    30 => 'Bulanan (setiap 30 hari)',
    _ => 'Harian (setiap pukul 02.00 pagi)',
  };

  @override
  State<BackupSettingsSection> createState() => _BackupSettingsSectionState();
}

class _BackupSettingsSectionState extends State<BackupSettingsSection> {
  int _frequencyDays = 1;
  String _googleAccount = '';
  String _googleDisplayName = '';
  String _googlePhotoUrl = '';
  bool _overCellular = true;
  String _dhkpFingerprint = '';
  int _totalNop = 0;
  int _changedNopCount = 0;
  DateTime? _lastBackupTime;
  int? _lastBackupSize;
  List<File> _localBackups = const [];
  bool _isBackingUp = false;
  String _busyMessage = '';

  static const List<String> _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
  }

  Future<void> _loadBackupSettings() async {
    final scheduler = BlokBackupScheduler.instance;
    final freq = await scheduler.getFrequencyDays();
    final acc = await scheduler.getGoogleAccount();
    final name = await scheduler.getGoogleDisplayName();
    final photo = await scheduler.getGooglePhotoUrl();
    final cell = await scheduler.getOverCellular();
    final records = await BlokDataStore.instance.loadAll();
    final fingerprint = DhkpPackageHelper.computeDhkpFingerprint(records);
    final changedCount = DhkpPackageHelper.extractChangedRecords(
      records,
    ).length;
    final lastTime = await scheduler.getLastBackupTime();
    final lastSize = await scheduler.getLastBackupSize();
    final localFiles = await scheduler.getLocalBackups();
    if (!mounted) return;
    setState(() {
      _frequencyDays = freq;
      _googleAccount = acc;
      _googleDisplayName = name;
      _googlePhotoUrl = photo;
      _overCellular = cell;
      _dhkpFingerprint = fingerprint;
      _totalNop = records.length;
      _changedNopCount = changedCount;
      _lastBackupTime = lastTime;
      _lastBackupSize = lastSize;
      _localBackups = localFiles;
    });
  }

  static String frequencyLabel(int days) =>
      BackupSettingsSection.frequencyLabel(days);

  String _formatBackupDate(DateTime? dt) {
    if (dt == null) return 'Belum pernah dicadangkan';
    final d = dt.day;
    final m = _monthNames[dt.month - 1];
    final y = dt.year;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d $m $y, $hh.$mm';
  }

  String _formatBackupFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> _performBackup({bool enforcePreviousDhkpMatch = true}) async {
    setState(() {
      _isBackingUp = true;
      _busyMessage = _googleAccount.isNotEmpty
          ? 'Mengecek & menggabungkan data terbaru dari perangkat lain...'
          : 'Menyimpan cadangan perubahan DHKP...';
    });
    try {
      if (_googleAccount.isNotEmpty) {
        await BlokBackupScheduler.instance.checkAndMergeCloudUpdatesIfNeeded(
          force: true,
        );
        if (mounted) {
          setState(() {
            _busyMessage = 'Menyimpan cadangan perubahan DHKP...';
          });
        }
      }
      final file = await BlokBackupScheduler.instance.performBackup(
        enforcePreviousDhkpMatch: enforcePreviousDhkpMatch,
      );
      await _loadBackupSettings();
      if (!mounted) return;
      if (file != null) {
        final size = file.existsSync() ? file.lengthSync() : 0;
        final sizeText = _formatBackupFileSize(size);
        String cloudInfo = '';
        if (_googleAccount.isNotEmpty) {
          if (mounted) {
            setState(() {
              _busyMessage = 'Mengunggah berkas cadangan ke Google Drive...';
            });
          }
          try {
            final mainFolderId = await GoogleDriveService.instance
                .ensureDedicatedFolder();
            final backupFolderId = await GoogleDriveService.instance
                .ensureBackupSubfolder(parentFolderId: mainFolderId);
            final uploadedFileId = await GoogleDriveService.instance.uploadFile(
              file: file,
              folderId: backupFolderId,
            );
            if (uploadedFileId != null && uploadedFileId.isNotEmpty) {
              await BlokBackupScheduler.instance.recordUploadedCloudFile(
                fileId: uploadedFileId,
                modifiedTime: DateTime.now(),
              );
              cloudInfo =
                  '\nDisinkronkan ke Google Drive ($_googleAccount/backup)';
            } else {
              cloudInfo =
                  '\n(Tersimpan di perangkat, gagal unggah ke Google Drive)';
            }
          } catch (cloudErr) {
            cloudInfo =
                '\n(Tersimpan di perangkat, kendala Drive: ${friendlyErrorMessage(cloudErr, fallback: 'Gagal mengunggah ke Google Drive.')})';
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cadangan data DHKP berhasil disimpan ($sizeText).$cloudInfo',
            ),
            backgroundColor: Colors.green[800],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuat berkas cadangan.')),
        );
      }
    } on DhkpBackupValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _busyMessage = '';
        });
      }
      if (!mounted) return;
      if (enforcePreviousDhkpMatch && e.message.contains('berbeda')) {
        final startNew = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Wilayah / Data DHKP Berbeda'),
            content: const Text(
              'Berkas DHKP saat ini berbeda dengan cadangan sebelumnya '
              '(misalnya karena perpindahan wilayah kerja atau tahun baru).\n\n'
              'Mulai riwayat cadangan baru untuk DHKP ini? Cadangan wilayah lama di Google Drive tetap aman.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buat Cadangan Baru'),
              ),
            ],
          ),
        );
        if (startNew == true && mounted) {
          await _performBackup(enforcePreviousDhkpMatch: false);
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red[800],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat cadangan: ${friendlyErrorMessage(e)}'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _busyMessage = '';
        });
      }
    }
  }

  Future<void> _restoreFromDriveDialog() async {
    try {
      final filePath = await showGoogleDrivePickerDialog(context);
      if (filePath == null || !mounted) return;
      await _restoreFromFilePath(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal memuat berkas cadangan: ${friendlyErrorMessage(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _confirmAndRestoreLocalBackup(File file) async {
    if (_isBackingUp) return;
    final fileName = friendlyFileName(file.path);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pulihkan Cadangan?'),
        content: Text(
          'Data DHKP akan dipulihkan dari berkas "$fileName". Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _restoreFromFilePath(file.path);
    }
  }

  Future<void> _restoreFromFilePath(String path, {String? password}) async {
    setState(() {
      _isBackingUp = true;
      _busyMessage = 'Memulihkan & mencocokkan berkas DHKP...';
    });
    try {
      int count;
      if (password == null) {
        final masterKey = await GoogleAccountSyncService.instance
            .getOrCreateBackupMasterKey();
        if (masterKey != null && masterKey.isNotEmpty) {
          try {
            count = await BlokDataStore.instance.importCsv(
              path,
              password: masterKey,
              requireBaseDhkp: true,
            );
          } on DkhpPasswordException {
            // Fallback untuk cadangan lama (sebelum Master Key akun Google)
            // atau berkas .dkhp dengan sandi manual.
            count = await BlokDataStore.instance.importCsv(
              path,
              requireBaseDhkp: true,
            );
          }
        } else {
          count = await BlokDataStore.instance.importCsv(
            path,
            requireBaseDhkp: true,
          );
        }
      } else {
        count = await BlokDataStore.instance.importCsv(
          path,
          password: password,
          requireBaseDhkp: true,
        );
      }
      await _loadBackupSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil memulihkan $count data DHKP.'),
          backgroundColor: Colors.green[800],
        ),
      );
    } on DkhpPasswordException {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _busyMessage = '';
        });
      }
      if (!mounted) return;
      final enteredPassword = await IncomingFileService.promptBackupPassword(
        context,
      );
      if (enteredPassword != null && enteredPassword.isNotEmpty && mounted) {
        await _restoreFromFilePath(path, password: enteredPassword);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal memulihkan cadangan: ${friendlyErrorMessage(e)}',
          ),
          backgroundColor: Colors.red[800],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _busyMessage = '';
        });
      }
    }
  }

  Future<void> _showFrequencyDialog() async {
    const options = [1, 7, 14, 30, 0];
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frekuensi Cadangan Otomatis'),
        content: RadioGroup<int>(
          groupValue: _frequencyDays,
          onChanged: (val) => Navigator.of(ctx).pop(val),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (days) => RadioListTile<int>(
                    title: Text(frequencyLabel(days)),
                    value: days,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (chosen != null && chosen != _frequencyDays) {
      await BlokBackupScheduler.instance.setFrequencyDays(chosen);
      if (mounted) {
        setState(() => _frequencyDays = chosen);
      }
    }
  }

  Future<void> _showGoogleAccountDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => GoogleAccountDialog(
        initialEmail: _googleAccount,
        initialDisplayName: _googleDisplayName,
        initialPhotoUrl: _googlePhotoUrl,
      ),
    );

    if (result == null || result == 'cancel') return;

    if (result == 'remove') {
      await GoogleAuthService.instance.signOut();
      if (mounted) {
        setState(() {
          _googleAccount = '';
          _googleDisplayName = '';
          _googlePhotoUrl = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Akun Google dilepas dari pencadangan otomatis.'),
          ),
        );
      }
      await _loadBackupSettings();
      return;
    }

    final email = result;
    await BlokBackupScheduler.instance.setGoogleAccount(email);
    if (mounted) {
      setState(() => _googleAccount = email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            email.isEmpty
                ? 'Akun Google telah dilepas.'
                : 'Akun Google berhasil dihubungkan ($email)',
          ),
        ),
      );
      await _loadBackupSettings();
    }
  }

  Future<void> _showNetworkDialog() async {
    final chosen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadangkan Melalui'),
        content: RadioGroup<bool>(
          groupValue: _overCellular,
          onChanged: (val) => Navigator.of(ctx).pop(val),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: Text('Hanya Wi-Fi'),
                subtitle: Text('Hemat kuota internet seluler'),
                value: false,
              ),
              RadioListTile<bool>(
                title: Text('Wi-Fi atau Seluler'),
                subtitle: Text('Tetap mencadangkan saat memakai paket data'),
                value: true,
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null && chosen != _overCellular) {
      await BlokBackupScheduler.instance.setOverCellular(chosen);
      if (mounted) setState(() => _overCellular = chosen);
    }
  }

  Future<void> _openBackupLocation(File file) async {
    try {
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Berkas cadangan tidak ditemukan.')),
        );
        return;
      }
      await NativeFileHelper.showInFileManager(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal membuka lokasi berkas: ${friendlyErrorMessage(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _shareBackupFile(File file) async {
    try {
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final fileName = friendlyFileName(file.path);
      if (Platform.isAndroid) {
        await NativeFileHelper.shareBytes(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'application/octet-stream',
        );
      } else {
        await NativeFileHelper.showInFileManager(file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal membagikan berkas: ${friendlyErrorMessage(e)}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteBackupFile(File file) async {
    final fileName = friendlyFileName(file.path);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Cadangan?'),
        content: Text('Berkas $fileName akan dihapus dari perangkat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isBackingUp = true;
        _busyMessage = 'Menghapus berkas cadangan...';
      });
      try {
        if (await file.exists()) {
          await file.delete();
        }
        await _loadBackupSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Berkas cadangan berhasil dihapus.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal menghapus berkas: ${friendlyErrorMessage(e)}',
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isBackingUp = false;
            _busyMessage = '';
          });
        }
      }
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
                    Icon(Icons.cloud_sync_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Cadangan Data DHKP',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Cadangan hanya menyimpan data perubahan (blok & nomor NOP yang diubah beserta gambar dokumentasinya) dan wajib cocok dengan berkas DHKP yang sedang aktif.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cadangan Terakhir',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatBackupDate(_lastBackupTime),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_lastBackupSize != null && _lastBackupSize! > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Ukuran: ${_formatBackupFileSize(_lastBackupSize!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_dhkpFingerprint.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Data tercatat: $_changedNopCount perubahan dari $_totalNop objek pajak',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                      if (_googleAccount.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Google Drive: $_googleAccount (Folder: ${GoogleDriveBackupPolicy.dedicatedFolderName})',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                      SmoothActivityBanner(
                        isActive: _isBackingUp && _busyMessage.isNotEmpty,
                        message: _busyMessage,
                        icon: Icons.cloud_sync_outlined,
                        margin: const EdgeInsets.only(top: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isBackingUp ? null : _performBackup,
                          icon: _isBackingUp
                              ? const Icon(
                                  Icons.hourglass_top_outlined,
                                  size: 18,
                                )
                              : const Icon(Icons.backup_outlined),
                          label: Text(
                            _isBackingUp
                                ? 'Sedang Mencadangkan...'
                                : 'Cadangkan Sekarang',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBackingUp
                              ? null
                              : _restoreFromDriveDialog,
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            size: 18,
                          ),
                          label: const Text('Pulihkan / Muat Berkas DHKP'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Cadangkan Otomatis'),
                  subtitle: Text(frequencyLabel(_frequencyDays)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showFrequencyDialog,
                ),
                if (isMobilePlatform) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.wifi_outlined),
                    title: const Text('Cadangkan Lewat'),
                    subtitle: Text(
                      _overCellular ? 'Wi-Fi atau Seluler' : 'Hanya Wi-Fi',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showNetworkDialog,
                  ),
                ],
              ],
            ),
          ),
        ),
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
                  leading: _googlePhotoUrl.isNotEmpty
                      ? CircleAvatar(
                          radius: 14,
                          backgroundImage: NetworkImage(_googlePhotoUrl),
                          onBackgroundImageError: (_, _) {},
                        )
                      : const Icon(Icons.add_to_drive_outlined),
                  title: Text(
                    _googleDisplayName.isNotEmpty
                        ? 'Akun Google ($_googleDisplayName)'
                        : 'Akun Google (Google Drive)',
                  ),
                  subtitle: Text(
                    !GoogleAuthService.instance.isSupportedPlatform
                        ? 'Masuk akun Google tidak didukung di platform ini'
                        : (_googleAccount.isEmpty
                              ? 'Belum terhubung • Folder "${GoogleDriveBackupPolicy.dedicatedFolderName}/backup"'
                              : '$_googleAccount • Folder backup aktif'),
                  ),
                  trailing: GoogleAuthService.instance.isSupportedPlatform
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: GoogleAuthService.instance.isSupportedPlatform
                      ? _showGoogleAccountDialog
                      : null,
                ),
              ],
            ),
          ),
        ),
        if (_localBackups.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Berkas Cadangan',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          ..._localBackups.map((file) {
            final fileName = friendlyFileName(file.path);
            final size = file.existsSync() ? file.lengthSync() : 0;
            final modTime = file.existsSync() ? file.lastModifiedSync() : null;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(top: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                title: Text(
                  fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_formatBackupDate(modTime)} • ${_formatBackupFileSize(size)}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.restore_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      tooltip: 'Pulihkan cadangan ini',
                      onPressed: _isBackingUp
                          ? null
                          : () => _confirmAndRestoreLocalBackup(file),
                    ),
                    IconButton(
                      icon: Icon(
                        isDesktopPlatform
                            ? Icons.folder_open_outlined
                            : Icons.share_outlined,
                        size: 20,
                      ),
                      tooltip: isDesktopPlatform
                          ? 'Buka Lokasi Berkas'
                          : 'Bagikan berkas cadangan',
                      onPressed: _isBackingUp
                          ? null
                          : () => isDesktopPlatform
                                ? _openBackupLocation(file)
                                : _shareBackupFile(file),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red,
                      ),
                      tooltip: 'Hapus berkas ini',
                      onPressed: _isBackingUp
                          ? null
                          : () => _deleteBackupFile(file),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
