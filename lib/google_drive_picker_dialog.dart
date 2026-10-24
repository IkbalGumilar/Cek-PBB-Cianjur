import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'blok_backup_scheduler.dart';
import 'google_auth_service.dart';
import 'google_drive_backup_policy.dart';

/// Representasi item berkas atau folder di Google Drive.
class GoogleDriveItem {
  final String id;
  final String name;
  final int size;
  final DateTime? modifiedTime;
  final String mimeType;
  final bool isFolder;

  const GoogleDriveItem({
    required this.id,
    required this.name,
    this.size = 0,
    this.modifiedTime,
    this.mimeType = '',
    this.isFolder = false,
  });

  String get formattedSize {
    if (isFolder) return 'Folder';
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedModifiedDate {
    if (modifiedTime == null) return '';
    final dt = modifiedTime!.toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}

/// Service komunikasi langsung ke Google Drive API v3 (REST API resmi) dan downloader berkas.
class GoogleDriveService {
  GoogleDriveService._();
  static final instance = GoogleDriveService._();

  final http.Client _httpClient = http.Client();

  @visibleForTesting
  static List<GoogleDriveItem>? mockItems;

  @visibleForTesting
  static Future<File> Function(String fileId, String fileName)? mockDownloader;

  @visibleForTesting
  static void resetForTesting() {
    mockItems = null;
    mockDownloader = null;
  }

  /// Mengambil daftar berkas DHKP dan data tabel dari Google Drive pengguna via REST API v3.
  Future<List<GoogleDriveItem>> listDkhpFiles({String? folderId}) async {
    if (mockItems != null) return mockItems!;

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders();
    if (authHeaders == null) {
      return [];
    }

    final queries = <String>['trashed = false'];
    if (folderId != null && folderId.isNotEmpty) {
      queries.add("'$folderId' in parents");
    }

    final q = queries.join(' and ');
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files').replace(
      queryParameters: {
        'q': q,
        'pageSize': '50',
        'fields': 'files(id, name, mimeType, size, modifiedTime)',
        'orderBy': 'folder desc, modifiedTime desc',
      },
    );

    try {
      final response = await _httpClient
          .get(uri, headers: authHeaders)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data =
            json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (data['files'] is List) {
          final list = data['files'] as List;
          final items = <GoogleDriveItem>[];
          for (final item in list) {
            if (item is Map) {
              final name = item['name'] as String? ?? '';
              final mime = item['mimeType'] as String? ?? '';
              final isFolder = mime == 'application/vnd.google-apps.folder';
              final lower = name.toLowerCase();
              final isRelevant = isFolder ||
                  lower.endsWith('.dkhp') ||
                  lower.endsWith('.zip') ||
                  lower.endsWith('.csv') ||
                  lower.endsWith('.xlsx') ||
                  lower.endsWith('.xls') ||
                  lower.endsWith('.txt');
              if (isRelevant) {
                items.add(
                  GoogleDriveItem(
                    id: item['id'] as String? ?? '',
                    name: name,
                    size: int.tryParse(item['size']?.toString() ?? '') ?? 0,
                    modifiedTime: DateTime.tryParse(
                      item['modifiedTime']?.toString() ?? '',
                    ),
                    mimeType: mime,
                    isFolder: isFolder,
                  ),
                );
              }
            }
          }
          return items;
        }
        return [];
      } else {
        String errorMsg =
            'Google Drive REST API merespons status ${response.statusCode}';
        try {
          final errJson = json.decode(response.body);
          if (errJson is Map && errJson['error'] is Map) {
            final m = errJson['error']['message'] as String?;
            if (m != null && m.isNotEmpty) {
              errorMsg = m;
            }
          }
        } catch (_) {}
        if (response.statusCode == 403) {
          throw Exception(
            'Google Drive API (403): $errorMsg\n\n'
            'Solusi: Aktifkan "Google Drive API" di Google Cloud Console (Library), atau gunakan tombol File Manager HP.',
          );
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('Gagal mengambil daftar berkas Google Drive: $e');
      rethrow;
    }
  }

  /// Mengunduh berkas Google Drive ke direktori sementara lokal via REST API v3.
  Future<File> downloadFile({
    required String fileId,
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    if (mockDownloader != null) {
      return await mockDownloader!(fileId, fileName);
    }

    final tempDir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final targetFile = File('${tempDir.path}/gdrive_$safeName');

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders();
    if (authHeaders != null) {
      final url = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final request = http.Request('GET', url);
      request.headers.addAll(authHeaders);

      final streamedResponse = await _httpClient.send(request);
      if (streamedResponse.statusCode != 200) {
        throw Exception(
            'Gagal mengunduh berkas Drive (Status ${streamedResponse.statusCode}).');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = targetFile.openWrite();

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null && contentLength > 0) {
          onProgress(receivedBytes, contentLength);
        }
      }
      await sink.flush();
      await sink.close();
      return targetFile;
    }

    return await downloadFromPublicId(
      fileId,
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  /// Mengunduh berkas dari link atau ID publik Google Drive.
  Future<File> downloadFromPublicId(
    String fileId, {
    String? fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    if (mockDownloader != null) {
      return await mockDownloader!(fileId, fileName ?? 'file.dkhp');
    }

    final tempDir = await getTemporaryDirectory();
    final actualName = (fileName != null && fileName.isNotEmpty)
        ? fileName
        : 'dkhp_drive_$fileId.dkhp';
    final targetFile = File('${tempDir.path}/$actualName');

    final url = Uri.parse(
        'https://drive.google.com/uc?export=download&id=$fileId&confirm=t');
    final request = http.Request('GET', url);
    final streamedResponse = await _httpClient.send(request);

    final contentLength = streamedResponse.contentLength ?? 0;
    int receivedBytes = 0;
    final sink = targetFile.openWrite();

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (onProgress != null && contentLength > 0) {
        onProgress(receivedBytes, contentLength);
      }
    }
    await sink.flush();
    await sink.close();

    // Periksa jika respons merupakan halaman HTML peringatan scan virus Google
    if (await targetFile.exists() && await targetFile.length() < 50000) {
      final bytes = await targetFile.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      if (content.contains('<html') &&
          (content.contains('confirm=') ||
              content.contains('uc-download-link'))) {
        final confirmMatch =
            RegExp(r'confirm=([0-9a-zA-Z_-]+)').firstMatch(content);
        if (confirmMatch != null) {
          final confirmCode = confirmMatch.group(1);
          final confirmUrl = Uri.parse(
              'https://drive.google.com/uc?export=download&confirm=$confirmCode&id=$fileId');
          final retryRequest = http.Request('GET', confirmUrl);
          final retryStream = await _httpClient.send(retryRequest);
          final retryLength = retryStream.contentLength ?? 0;
          int retryReceived = 0;
          final retrySink = targetFile.openWrite();
          await for (final chunk in retryStream.stream) {
            retrySink.add(chunk);
            retryReceived += chunk.length;
            if (onProgress != null && retryLength > 0) {
              onProgress(retryReceived, retryLength);
            }
          }
          await retrySink.flush();
          await retrySink.close();
        }
      }
    }

    return targetFile;
  }
}

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

  Future<void> _loadAccountAndFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final account = await BlokBackupScheduler.instance.getGoogleAccount();
      _currentAccount = account;

      // Jika ada akun terhubung atau ada mock test, muat berkas
      if (_currentAccount.isNotEmpty || GoogleDriveService.mockItems != null) {
        final folderLink =
            await BlokBackupScheduler.instance.getGoogleDriveFolderLink();
        final folderId = GoogleDriveBackupPolicy.extractFolderId(folderLink);
        final files =
            await GoogleDriveService.instance.listDkhpFiles(folderId: folderId);
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
              'Akses Google Drive API ditolak (403). Pastikan "Google Drive API" sudah diaktifkan di Google Cloud Console, atau pilih berkas langsung melalui File Manager HP di bawah.';
        } else if (errStr.contains('SocketException') ||
            errStr.contains('Failed host lookup') ||
            errStr.contains('ClientException')) {
          friendlyError =
              'Gagal terhubung ke Google Drive (Koneksi jaringan bermasalah). Silakan periksa koneksi atau gunakan File Manager HP.';
        } else {
          friendlyError =
              'Gagal memuat berkas Google Drive: ${errStr.replaceFirst('Exception: ', '')}';
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
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dkhp', 'zip', 'csv', 'xlsx', 'xls', 'txt'],
      );
      if (!mounted) return;
      if (files.isNotEmpty && files.first.path != null) {
        Navigator.of(context).pop(files.first.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka berkas: $e')),
        );
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

  Future<void> _downloadAndSelect(GoogleDriveItem item) async {
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
      setState(() => _error = 'Masukkan link atau ID berkas Google Drive.');
      return;
    }

    final fileId = GoogleDriveBackupPolicy.extractFileId(raw);
    if (fileId == null || fileId.isEmpty) {
      setState(() => _error = 'Link atau ID Google Drive tidak valid.');
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
        _error = 'Gagal mengunduh berkas dari link Google Drive: $e';
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
    if (lower.endsWith('.dkhp')) {
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
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _downloading
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.cloud_outlined),
                  text: 'Berkas Drive',
                ),
                Tab(
                  icon: Icon(Icons.link),
                  text: 'Tempel Link / ID',
                ),
              ],
            ),
            if (_downloading) ...[
              Container(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.downloading,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mengunduh "${_downloadFileName ?? 'berkas'}"...',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_downloadProgress != null)
                          Text(
                            '${(_downloadProgress! * 100).toInt()}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress),
                  ],
                ),
              ),
            ],
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
                      icon: const FaIcon(FontAwesomeIcons.googleDrive, size: 16),
                      label: const Text('Buka Google Drive (File Manager HP)'),
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Menghubungkan ke Google Drive...'),
          ],
        ),
      );
    }

    if (_currentAccount.isEmpty && GoogleDriveService.mockItems == null) {
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
                'Hubungkan akun Google Anda untuk melihat dan memilih berkas DHKP (.dkhp, .zip, .csv) langsung dari Drive.',
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
              const Icon(Icons.folder_open_outlined,
                  size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Belum Ada Berkas DHKP Terdeteksi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Jika berkas Anda berada di folder lain atau akses REST API terhalang izin server, Anda dapat langsung memilih berkas dari Google Drive menggunakan File Manager HP.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickViaSystemFileManager,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const FaIcon(FontAwesomeIcons.googleDrive, size: 16),
                label: const Text('Buka Drive via File Manager HP'),
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
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        FaIcon(FontAwesomeIcons.googleDrive,
                            color: Colors.blue, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Buka via File Manager HP',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                'Pilih Google Drive di menu samping HP tanpa hambatan API',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 13, color: Colors.blue),
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
            'Buka Berkas via Link Google Drive',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tempel link berkas Google Drive publik/bersama yang berisi data DHKP (.dkhp, .zip, .csv).',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _linkController,
            decoration: InputDecoration(
              labelText: 'Link atau ID Berkas Google Drive',
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
                    'Pastikan izin akses berkas di Google Drive diatur ke "Siapa saja yang memiliki link" (Anyone with the link) agar aplikasi dapat mengunduhnya secara langsung.',
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

  BorderRadius circularBorder(double radius) =>
      BorderRadius.circular(radius);
}
