import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'blok_backup_scheduler.dart';
import 'cloud_sync/google_drive_service.dart';
import 'google_auth_service.dart';
import 'google_drive_backup_policy.dart';
import 'unity_lerp_widgets.dart';

export 'cloud_sync/google_drive_service.dart';

/// Menampilkan dialog pemilih berkas Google Drive interaktif.
/// Mengembalikan path berkas lokal yang telah diunduh, atau `null` jika dibatalkan.
Future<String?> showGoogleDrivePickerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => const GoogleDrivePickerDialog(),
  );
}

class GoogleDrivePickerDialog extends StatefulWidget {
  const GoogleDrivePickerDialog({super.key});

  @override
  State<GoogleDrivePickerDialog> createState() =>
      _GoogleDrivePickerDialogState();
}

class _GoogleDrivePickerDialogState extends State<GoogleDrivePickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _linkController = TextEditingController();

  bool _loading = false;
  bool _downloading = false;
  bool _uploading = false;
  double? _downloadProgress;
  String? _downloadFileName;
  String? _error;
  List<GoogleDriveItem> _items = [];
  String _currentAccount = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAccountAndFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountAndFiles({String? customFolderId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final account = await BlokBackupScheduler.instance.getGoogleAccount();
      _currentAccount = account;

      // Jika ada akun terhubung atau ada mock test, muat berkas
      if (_currentAccount.isNotEmpty || GoogleDriveService.hasMockItems) {
        final folderLink = await BlokBackupScheduler.instance
            .getGoogleDriveFolderLink();
        final folderId =
            customFolderId ??
            GoogleDriveBackupPolicy.extractFolderId(folderLink);
        final files = await GoogleDriveService.instance.listDkhpFiles(
          folderId: folderId,
        );
        if (mounted) {
          setState(() {
            _items = files;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        String friendlyError;
        if (errStr.contains('403')) {
          friendlyError =
              'Akses folder Google Drive belum diizinkan. Anda tetap dapat memilih berkas langsung dari penyimpanan perangkat di bawah.';
        } else if (errStr.contains('SocketException') ||
            errStr.contains('Failed host lookup') ||
            errStr.contains('ClientException')) {
          friendlyError =
              'Gagal terhubung ke Google Drive karena koneksi internet sedang bermasalah. Silakan periksa sinyal atau pilih berkas dari perangkat.';
        } else {
          friendlyError =
              'Belum dapat memuat daftar berkas dari Google Drive. Silakan coba lagi atau pilih berkas dari penyimpanan perangkat.';
        }
        setState(() {
          _error = friendlyError;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickViaSystemFileManager() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (!mounted) return;
      if (files.isNotEmpty && files.first.path != null) {
        final path = files.first.path!;
        if (!GoogleDriveService.isSupportedDkhpFileName(files.first.name)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Format berkas belum didukung. Silakan pilih berkas data DHKP atau tabel Excel.',
              ),
            ),
          );
          return;
        }
        Navigator.of(context).pop(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal membuka berkas: $e')));
      }
    }
  }

  Future<void> _connectGoogleAccount() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await GoogleAuthService.instance.signIn();
      if (!mounted) return;
      if (user != null) {
        _currentAccount = user.email;
        // Otomatis pastikan folder khusus "Cek PBB Cianjur" ada di Google Drive
        unawaited(GoogleDriveService.instance.ensureDedicatedFolder());
        await _loadAccountAndFiles();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal menghubungkan akun Google: $e';
        _loading = false;
      });
    }
  }

  Future<void> _uploadLocalFileToDrive() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      if (picked.isEmpty || picked.first.path == null) return;

      final file = File(picked.first.path!);
      final fileName = picked.first.name;
      if (!GoogleDriveService.isSupportedDkhpFileName(fileName)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Format berkas belum didukung. Silakan pilih berkas data DHKP atau tabel Excel.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _uploading = true;
        _error = null;
      });

      await GoogleDriveService.instance.uploadFile(
        file: file,
        customFileName: fileName,
      );

      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Berkas "$fileName" berhasil diunggah ke Google Drive.',
          ),
          backgroundColor: Colors.green[800],
        ),
      );
      await _loadAccountAndFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Gagal mengunggah berkas: $e';
      });
    }
  }

  Future<void> _downloadAndSelect(GoogleDriveItem item) async {
    if (item.isFolder) {
      await _loadAccountAndFiles(customFolderId: item.id);
      return;
    }

    setState(() {
      _downloading = true;
      _downloadFileName = item.name;
      _downloadProgress = 0.0;
      _error = null;
    });

    try {
      final file = await GoogleDriveService.instance.downloadFile(
        fileId: item.id,
        fileName: item.name,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Gagal mengunduh berkas "${item.name}": $e';
      });
    }
  }

  Future<void> _downloadFromLink() async {
    final raw = _linkController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Masukkan tautan berkas Google Drive.');
      return;
    }

    final fileId = GoogleDriveBackupPolicy.extractFileId(raw);
    if (fileId == null || fileId.isEmpty) {
      setState(() => _error = 'Tautan Google Drive tidak dikenali.');
      return;
    }

    setState(() {
      _downloading = true;
      _downloadFileName = 'berkas_drive_$fileId';
      _downloadProgress = null;
      _error = null;
    });

    try {
      final file = await GoogleDriveService.instance.downloadFile(
        fileId: fileId,
        fileName: 'dkhp_drive_$fileId.dkhp',
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Gagal mengunduh berkas dari tautan Google Drive: $e';
      });
    }
  }

  Future<void> _openDriveApp() async {
    final uri = Uri.parse('https://drive.google.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka Google Drive.')),
      );
    }
  }

  Widget _buildFileIcon(GoogleDriveItem item) {
    if (item.isFolder) {
      return const Icon(Icons.folder, color: Colors.amber, size: 28);
    }
    final lower = item.name.toLowerCase();
    if (lower.endsWith('.dkhp') || lower.endsWith('.dhkp')) {
      return const Icon(Icons.inventory_2, color: Colors.teal, size: 28);
    }
    if (lower.endsWith('.zip')) {
      return const Icon(Icons.folder_zip, color: Colors.indigo, size: 28);
    }
    if (lower.endsWith('.csv') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.xls')) {
      return const Icon(Icons.table_chart, color: Colors.green, size: 28);
    }
    return const Icon(Icons.insert_drive_file, color: Colors.blue, size: 28);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: circularBorder(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Dialog
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.googleDrive,
                    color: Colors.blue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Drive',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _currentAccount.isNotEmpty
                              ? _currentAccount
                              : 'Pilih dan buka berkas langsung dari Drive',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_currentAccount.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.upload_file_outlined),
                      tooltip: 'Unggah Berkas ke Google Drive',
                      onPressed: (_downloading || _uploading)
                          ? null
                          : _uploadLocalFileToDrive,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _downloading || _uploading
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.cloud_outlined), text: 'Berkas Drive'),
                Tab(icon: Icon(Icons.link), text: 'Tempel Tautan'),
              ],
            ),
            SmoothActivityBanner(
              isActive: _uploading,
              message: 'Mengunggah berkas ke Google Drive...',
              icon: Icons.cloud_upload_outlined,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            ),
            SmoothActivityBanner(
              isActive: _downloading,
              message: 'Mengunduh "${_downloadFileName ?? 'berkas'}"...',
              subtitle: _downloadProgress != null
                  ? '${(_downloadProgress! * 100).toInt()}% selesai'
                  : 'Menyiapkan unduhan dari Google Drive...',
              icon: Icons.downloading_rounded,
              progress: _downloadProgress,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _pickViaSystemFileManager,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      icon: const FaIcon(
                        FontAwesomeIcons.googleDrive,
                        size: 16,
                      ),
                      label: const Text(
                        'Pilih Berkas dari Penyimpanan Perangkat',
                      ),
                    ),
                  ],
                ),
              ),
            // Body Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Berkas Drive
                  _buildDriveFilesTab(),
                  // Tab 2: Tempel Link
                  _buildLinkTab(),
                ],
              ),
            ),
            // Footer Action
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _openDriveApp,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Buka Aplikasi Drive'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _downloading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveFilesTab() {
    if (_loading) {
      return const SmoothLoadingCard(
        icon: Icons.cloud_sync_outlined,
        title: 'Menghubungkan ke Google Drive...',
        subtitle:
            'Memuat daftar berkas data DHKP dan cadangan dari Google Drive Anda...',
        badgeText: 'Memuat daftar berkas Drive',
      );
    }

    if (_currentAccount.isEmpty && !GoogleDriveService.hasMockItems) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_circle_outlined,
                size: 56,
                color: Colors.blue,
              ),
              const SizedBox(height: 12),
              const Text(
                'Akun Google Belum Terhubung',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hubungkan akun Google Anda untuk melihat dan memilih berkas data DHKP langsung dari Google Drive.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _connectGoogleAccount,
                icon: const FaIcon(FontAwesomeIcons.google, size: 16),
                label: const Text('Hubungkan Akun Google'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              const Text(
                'Belum Ada Berkas DHKP Terdeteksi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Jika berkas berada di folder lain, Anda dapat langsung memilihnya dari aplikasi Google Drive atau penyimpanan perangkat.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _uploadLocalFileToDrive,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Unggah Berkas ke Folder Ini'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _pickViaSystemFileManager,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const FaIcon(FontAwesomeIcons.googleDrive, size: 16),
                label: const Text('Pilih dari Penyimpanan Perangkat'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadAccountAndFiles,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Muat Ulang'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAccountAndFiles,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, idx) {
          if (idx == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Material(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickViaSystemFileManager,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        FaIcon(
                          FontAwesomeIcons.googleDrive,
                          color: Colors.blue,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih dari Penyimpanan Perangkat',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Pilih berkas langsung dari folder perangkat atau menu Google Drive',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 13,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final item = _items[idx - 1];
          return ListTile(
            leading: _buildFileIcon(item),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${item.formattedSize} • ${item.formattedModifiedDate}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _downloading
                ? null
                : const Icon(Icons.download, size: 20, color: Colors.blue),
            onTap: _downloading ? null : () => _downloadAndSelect(item),
          );
        },
      ),
    );
  }

  Widget _buildLinkTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Buka Berkas via Tautan Google Drive',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tempel tautan berkas Google Drive bersama yang berisi data DHKP.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _linkController,
            decoration: InputDecoration(
              labelText: 'Tautan Berkas Google Drive',
              hintText: 'https://drive.google.com/file/d/...',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => _linkController.clear(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _downloading ? null : _downloadFromLink,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Unduh & Buka Berkas'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pastikan akses berkas di Google Drive diatur ke "Siapa saja yang memiliki link" agar aplikasi dapat mengunduhnya secara langsung.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BorderRadius circularBorder(double radius) => BorderRadius.circular(radius);
}
