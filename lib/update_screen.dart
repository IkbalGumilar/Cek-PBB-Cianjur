import 'dart:io';

import 'package:flutter/material.dart';

import 'apk_installer.dart';
import 'update_info.dart';

enum _Stage { idle, downloading, downloaded, needPermission }

class UpdateScreen extends StatefulWidget {
  final UpdateInfo info;

  const UpdateScreen({super.key, required this.info});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  _Stage _stage = _Stage.idle;
  double _progress = 0;
  File? _downloadedFile;
  String? _error;

  // Android: unduh lalu langsung buka installer sistem (pasang sendiri).
  // Windows/Linux: cuma unduh ke folder Downloads — tidak ada mekanisme
  // pasang-sendiri yang aman/generik lintas platform, jadi user menjalankan
  // berkasnya sendiri setelah selesai diunduh.
  bool get _canSelfInstall => Platform.isAndroid;

  String get _downloadFileName {
    final url = widget.info.apkDownloadUrl;
    final urlName = url.split('/').last;
    return urlName.contains('.')
        ? urlName
        : 'CekPBBCianjur-${widget.info.version}';
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      final file =
          _downloadedFile ??
          await ApkInstaller.download(
            widget.info.apkDownloadUrl,
            fileName: _downloadFileName,
            onProgress: (received, total) {
              if (total <= 0 || !mounted) return;
              setState(() => _progress = received / total);
            },
          );
      _downloadedFile = file;
      if (!mounted) return;
      setState(() => _stage = _Stage.downloaded);

      if (!_canSelfInstall) return;

      final status = await ApkInstaller.install(file.path);
      if (!mounted) return;
      if (status == 'NEED_PERMISSION') {
        setState(() => _stage = _Stage.needPermission);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = e.toString();
      });
    }
  }

  Future<void> _retryInstallAfterPermission() async {
    final file = _downloadedFile;
    if (file == null) return;
    final status = await ApkInstaller.install(file.path);
    if (!mounted || status == 'NEED_PERMISSION') return;
    setState(() => _stage = _Stage.downloaded);
  }

  String _formatSize(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return Scaffold(
      appBar: AppBar(title: const Text('Pembaruan Aplikasi')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.system_update, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Versi ${info.version} tersedia',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${_formatSize(info.apkSize)} · Dirilis ${_formatDate(info.publishedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Catatan Pembaruan',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    info.changelog.isNotEmpty
                        ? info.changelog
                        : 'Tidak ada catatan pembaruan untuk rilis ini.',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              if (_stage == _Stage.needPermission) ...[
                Card(
                  color: Colors.orange.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aktifkan dulu izin "Instal aplikasi tidak dikenal" untuk Cek PBB Cianjur, '
                          'lalu kembali ke sini dan tekan "Pasang Sekarang" lagi.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: ApkInstaller.openInstallPermissionSettings,
                          child: const Text('Buka Pengaturan Izin'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _retryInstallAfterPermission,
                  icon: const Icon(Icons.install_mobile),
                  label: const Text('Pasang Sekarang'),
                ),
              ] else if (_stage == _Stage.downloading) ...[
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Mengunduh... ${(_progress * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                ),
              ] else if (_stage == _Stage.downloaded) ...[
                if (_canSelfInstall)
                  const Text(
                    'Berkas sudah diunduh, menunggu konfirmasi instal...',
                    textAlign: TextAlign.center,
                  )
                else
                  Card(
                    color: Colors.green.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Berkas pembaruan sudah diunduh:'),
                          const SizedBox(height: 4),
                          SelectableText(
                            _downloadedFile?.path ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Jalankan/ekstrak berkas ini sendiri untuk memasang pembaruan.',
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _downloadAndInstall,
                  icon: const Icon(Icons.download),
                  label: Text(
                    _canSelfInstall ? 'Unduh & Pasang' : 'Unduh Pembaruan',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
