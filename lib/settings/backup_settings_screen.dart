import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../blok_backup_scheduler.dart';
import '../blok_data_store.dart';
import '../dkhp_package_helper.dart';
import '../google_auth_service.dart';
import '../google_drive_backup_policy.dart';
import '../google_drive_picker_dialog.dart';
import '../legal_document_screen.dart';
import '../native_file_helper.dart';
import '../shared_storage_link_service.dart';
import '../unity_lerp_widgets.dart';

/// Halaman terpisah untuk pengaturan Pencadangan Data DHKP.
class BackupSettingsScreen extends StatelessWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pencadangan Data'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            BackupSettingsSection(),
          ],
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
  String _googleFolderLink = '';
  bool _overCellular = true;
  bool _onlyDkhpData = true;
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
    final folderLink = await scheduler.getGoogleDriveFolderLink();
    final cell = await scheduler.getOverCellular();
    final onlyDkhp = await scheduler.getOnlyDkhpData();
    final records = await BlokDataStore.instance.loadAll();
    final fingerprint = DhkpPackageHelper.computeDhkpFingerprint(records);
    final changedCount = DhkpPackageHelper.extractChangedRecords(records).length;
    final lastTime = await scheduler.getLastBackupTime();
    final lastSize = await scheduler.getLastBackupSize();
    final localFiles = await scheduler.getLocalBackups();
    if (!mounted) return;
    setState(() {
      _frequencyDays = freq;
      _googleAccount = acc;
      _googleDisplayName = name;
      _googlePhotoUrl = photo;
      _googleFolderLink = folderLink;
      _overCellular = cell;
      _onlyDkhpData = onlyDkhp;
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

  Future<void> _performBackup() async {
    setState(() {
      _isBackingUp = true;
      _busyMessage = 'Menyimpan cadangan perubahan DHKP...';
    });
    try {
      final file = await BlokBackupScheduler.instance.performBackup(
        onlyDkhpData: _onlyDkhpData,
        enforcePreviousDhkpMatch: true,
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
            final sharedFolderId = _googleFolderLink.isNotEmpty
                ? GoogleDriveBackupPolicy.extractFolderId(_googleFolderLink)
                : null;
            final uploaded = await GoogleDriveService.instance.uploadFile(
              file: file,
              folderId: sharedFolderId,
            );
            if (uploaded != null) {
              cloudInfo = '\nDisinkronkan ke Google Drive ($_googleAccount)';
            } else {
              cloudInfo = '\n(Tersimpan di HP, gagal unggah ke Google Drive)';
            }
          } catch (cloudErr) {
            cloudInfo = '\n(Tersimpan di HP, kendala Drive: $cloudErr)';
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
          const SnackBar(
            content: Text(
              'Gagal membuat berkas cadangan.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat cadangan: $e'),
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
        SnackBar(content: Text('Gagal memuat berkas cadangan: $e')),
      );
    }
  }

  Future<void> _restoreFromFilePath(String path) async {
    setState(() {
      _isBackingUp = true;
      _busyMessage = 'Memulihkan & mencocokkan berkas DHKP...';
    });
    try {
      final count = await BlokDataStore.instance.importCsv(
        path,
        requireBaseDhkp: true,
      );
      await _loadBackupSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil memulihkan $count data DHKP.'),
          backgroundColor: Colors.green[800],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memulihkan cadangan: $e'),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (days) => RadioListTile<int>(
                  title: Text(frequencyLabel(days)),
                  value: days,
                  groupValue: _frequencyDays,
                  onChanged: (val) => Navigator.of(ctx).pop(val),
                ),
              )
              .toList(),
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
      builder: (ctx) => _GoogleAccountDialog(
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
          _googleFolderLink = '';
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

  Future<void> _showGoogleFolderDialog() async {
    if (_googleAccount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hubungkan akun Google terlebih dahulu sebelum mengatur folder bersama.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _GoogleFolderDialog(
        currentAccount: _googleAccount,
        initialLink: _googleFolderLink,
      ),
    );

    if (result == null || result == 'cancel') return;

    if (result == 'reset') {
      await BlokBackupScheduler.instance.setGoogleDriveFolderLink('');
      if (mounted) {
        setState(() => _googleFolderLink = '');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Folder bersama direset ke folder bawaan "${GoogleDriveBackupPolicy.dedicatedFolderName}".',
            ),
          ),
        );
      }
    } else {
      final success =
          await BlokBackupScheduler.instance.setGoogleDriveFolderLink(result);
      if (!mounted) return;
      if (success) {
        setState(() => _googleFolderLink = result);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Folder bersama Google Drive berhasil disimpan.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link folder Google Drive tidak valid.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showNetworkDialog() async {
    final chosen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadangkan Melalui'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              title: const Text('Hanya Wi-Fi'),
              subtitle: const Text('Hemat kuota internet seluler'),
              value: false,
              groupValue: _overCellular,
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
            RadioListTile<bool>(
              title: const Text('Wi-Fi atau Seluler'),
              subtitle: const Text('Tetap mencadangkan saat memakai paket data'),
              value: true,
              groupValue: _overCellular,
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
          ],
        ),
      ),
    );

    if (chosen != null && chosen != _overCellular) {
      await BlokBackupScheduler.instance.setOverCellular(chosen);
      if (mounted) setState(() => _overCellular = chosen);
    }
  }

  Future<void> _shareBackupFile(File file) async {
    try {
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final fileName = file.uri.pathSegments.last;
      if (Platform.isAndroid) {
        await NativeFileHelper.shareBytes(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'application/octet-stream',
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berkas tersimpan di: ${file.path}'),
            action: SnackBarAction(
              label: 'Salin Lokasi',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: file.path));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan berkas: $e')),
        );
      }
    }
  }

  Future<void> _deleteBackupFile(File file) async {
    final fileName = file.uri.pathSegments.last;
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

    if (confirm == true) {
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
            SnackBar(content: Text('Gagal menghapus berkas: $e')),
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
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                          'Sidik Jari DHKP: ${_dhkpFingerprint.substring(0, 8).toUpperCase()} ($_changedNopCount perubahan dari $_totalNop NOP)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                      if (_googleAccount.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _googleFolderLink.isNotEmpty
                              ? 'Google Drive: $_googleAccount (Folder Bersama)'
                              : 'Google Drive: $_googleAccount (Folder: ${GoogleDriveBackupPolicy.dedicatedFolderName})',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
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
                              ? const Icon(Icons.hourglass_top_outlined, size: 18)
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
                          onPressed: _isBackingUp ? null : _restoreFromDriveDialog,
                          icon: const Icon(Icons.cloud_download_outlined, size: 18),
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
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.table_chart_outlined),
                  title: const Text('Hanya Data DHKP Saja'),
                  subtitle: const Text(
                    'Tanpa gambar dokumentasi agar ukuran berkas lebih hemat',
                  ),
                  value: _onlyDkhpData,
                  onChanged: (val) async {
                    await BlokBackupScheduler.instance.setOnlyDkhpData(val);
                    if (mounted) setState(() => _onlyDkhpData = val);
                  },
                ),
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
                    _googleAccount.isEmpty
                        ? 'Belum terhubung • Folder "${GoogleDriveBackupPolicy.dedicatedFolderName}"'
                        : '$_googleAccount • ${_googleFolderLink.isNotEmpty ? 'Folder bersama aktif' : 'Folder "${GoogleDriveBackupPolicy.dedicatedFolderName}"'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showGoogleAccountDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: _googleAccount.isNotEmpty,
                  leading: Icon(
                    Icons.folder_shared_outlined,
                    color: _googleAccount.isNotEmpty
                        ? null
                        : Theme.of(context).disabledColor,
                  ),
                  title: const Text('Folder Bersama Google Drive'),
                  subtitle: Text(
                    _googleAccount.isEmpty
                        ? 'Hubungkan akun Google terlebih dahulu untuk mengatur folder bersama'
                        : (_googleFolderLink.isEmpty
                            ? 'Gunakan folder bawaan ("${GoogleDriveBackupPolicy.dedicatedFolderName}")'
                            : 'Folder bersama aktif: ${GoogleDriveBackupPolicy.extractFolderId(_googleFolderLink) ?? _googleFolderLink}'),
                  ),
                  trailing: _googleFolderLink.isNotEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.share_outlined,
                                size: 20,
                                color: Colors.blue,
                              ),
                              tooltip: 'Bagikan Tautan Folder Bersama',
                              onPressed: () {
                                SharedStorageLinkService.shareStorageLink(
                                  context: context,
                                  folder: _googleFolderLink,
                                  sender: _googleAccount,
                                );
                              },
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        )
                      : const Icon(Icons.chevron_right),
                  onTap:
                      _googleAccount.isEmpty ? null : _showGoogleFolderDialog,
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
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 4),
          ..._localBackups.map((file) {
            final fileName = file.uri.pathSegments.last;
            final size = file.existsSync() ? file.lengthSync() : 0;
            final modTime =
                file.existsSync() ? file.lastModifiedSync() : null;
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
                      icon: const Icon(Icons.share_outlined, size: 20),
                      tooltip: 'Bagikan berkas cadangan',
                      onPressed: () => _shareBackupFile(file),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red,
                      ),
                      tooltip: 'Hapus berkas ini',
                      onPressed: () => _deleteBackupFile(file),
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

class _GoogleAccountDialog extends StatefulWidget {
  final String initialEmail;
  final String initialDisplayName;
  final String initialPhotoUrl;

  const _GoogleAccountDialog({
    required this.initialEmail,
    this.initialDisplayName = '',
    this.initialPhotoUrl = '',
  });

  @override
  State<_GoogleAccountDialog> createState() => _GoogleAccountDialogState();
}

class _GoogleAccountDialogState extends State<_GoogleAccountDialog> {
  bool _loading = false;
  String? _errorMessage;

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
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
                      onBackgroundImageError:
                          widget.initialPhotoUrl.isNotEmpty ? (_, _) {} : null,
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
                  color:
                      isDark ? Colors.blueGrey.shade900 : Colors.blue.shade50,
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
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor:
                        isDark ? Colors.grey.shade800 : Colors.white,
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
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
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
                          style:
                              const TextStyle(color: Colors.red, fontSize: 11),
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

class _GoogleFolderDialog extends StatefulWidget {
  final String currentAccount;
  final String initialLink;

  const _GoogleFolderDialog({
    required this.currentAccount,
    required this.initialLink,
  });

  @override
  State<_GoogleFolderDialog> createState() => _GoogleFolderDialogState();
}

class _GoogleFolderDialogState extends State<_GoogleFolderDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLink);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initialLink.isNotEmpty;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.folder_shared_outlined, color: Colors.blue),
          SizedBox(width: 8),
          Text('Folder Bersama'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Syarat Hak Akses Folder',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          GoogleDriveBackupPolicy.editorRequirementNotice,
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Akun Google: ${widget.currentAccount}\n\n'
              'Tempel link folder Google Drive bersama tempat menyimpan cadangan:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link Folder Google Drive',
                hintText: 'https://drive.google.com/drive/folders/...',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (hasInitial) ...[
          IconButton(
            tooltip: 'Bagikan Tautan ke Kolektor Lain',
            icon: const Icon(Icons.share_outlined, color: Colors.blue),
            onPressed: () {
              final link = _controller.text.trim();
              if (link.isNotEmpty) {
                SharedStorageLinkService.shareStorageLink(
                  context: context,
                  folder: link,
                  sender: widget.currentAccount,
                );
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('reset'),
            child: const Text('Gunakan Bawaan'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
