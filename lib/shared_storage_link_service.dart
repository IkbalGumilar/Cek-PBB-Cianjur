import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blok_backup_scheduler.dart';
import 'google_drive_backup_policy.dart';
import 'native_file_helper.dart';

/// Model payload data yang dibawa oleh Deep Link tautan penyimpanan bersama.
class StorageLinkPayload {
  final String folder;
  final String? name;
  final String? sender;

  const StorageLinkPayload({required this.folder, this.name, this.sender});

  /// Mengambil ID folder murni (jika link berupa URL Google Drive).
  String get cleanFolderId {
    final extracted = GoogleDriveBackupPolicy.extractFolderId(folder);
    return extracted ?? folder.trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageLinkPayload &&
          runtimeType == other.runtimeType &&
          cleanFolderId == other.cleanFolderId &&
          name == other.name;

  @override
  int get hashCode => cleanFolderId.hashCode ^ (name?.hashCode ?? 0);
}

/// Service untuk menangani Deep Linking (App Links & Custom Scheme `cekpbb://storage`)
/// untuk berbagi folder penyimpanan bersama Google Drive antar-kolektor PBB.
class SharedStorageLinkService {
  SharedStorageLinkService._();
  static final instance = SharedStorageLinkService._();

  static const String deepLinkScheme = 'cekpbb';
  static const String deepLinkHost = 'storage';
  static const String webHost = 'ikbalgumilar.github.io';
  static const String webPath = '/Cek-PBB-Cianjur/connect';

  static const MethodChannel _deepLinkChannel = MethodChannel(
    'id.cianjur.cekpbb.cek_pbb_app/deeplink',
  );

  bool _initialized = false;
  BuildContext? _activeContext;

  /// Membuat tautan universal berbasis Web (GitHub Pages) yang otomatis berwarna biru
  /// dan dapat di-klik di WhatsApp/Telegram.
  static String createShareableWebLink({
    required String folder,
    String? name,
    String? sender,
  }) {
    final params = <String, String>{'folder': folder.trim()};
    if (name != null && name.trim().isNotEmpty) {
      params['name'] = name.trim();
    }
    if (sender != null && sender.trim().isNotEmpty) {
      params['sender'] = sender.trim();
    }
    return Uri.https(webHost, webPath, params).toString();
  }

  /// Membuat tautan Custom Scheme khusus aplikasi `cekpbb://storage`.
  static String createCustomSchemeLink({
    required String folder,
    String? name,
    String? sender,
  }) {
    final params = <String, String>{'folder': folder.trim()};
    if (name != null && name.trim().isNotEmpty) {
      params['name'] = name.trim();
    }
    if (sender != null && sender.trim().isNotEmpty) {
      params['sender'] = sender.trim();
    }
    return Uri(
      scheme: deepLinkScheme,
      host: deepLinkHost,
      queryParameters: params,
    ).toString();
  }

  /// Format teks undangan rapi siap kirim ke WhatsApp/Telegram.
  static String createInvitationMessage({
    required String folder,
    String? name,
    String? sender,
  }) {
    final webLink = createShareableWebLink(
      folder: folder,
      name: name,
      sender: sender,
    );
    final buffer = StringBuffer();
    buffer.writeln('🏛️ *Tautan Penyimpanan Bersama DHKP Cianjur*');
    if (name != null && name.trim().isNotEmpty) {
      buffer.writeln('Wilayah / Kategori: *${name.trim()}*');
    }
    if (sender != null && sender.trim().isNotEmpty) {
      buffer.writeln('Dari: ${sender.trim()}');
    }
    buffer.writeln();
    buffer.writeln(
      'Klik tautan berikut dari HP Anda untuk langsung menautkan folder penyimpanan bersama di aplikasi Cek PBB Cianjur:',
    );
    buffer.writeln(webLink);
    buffer.writeln();
    buffer.writeln(
      '_(Otomatis membuka aplikasi dan mengonfigurasi sinkronisasi cadangan DHKP & foto)_',
    );
    return buffer.toString();
  }

  /// Mem-parsing raw string URI menjadi [StorageLinkPayload].
  /// Mendukung format `cekpbb://storage`, Web URL `ikbalgumilar.github.io/Cek-PBB-Cianjur/connect`,
  /// atau langsung link Google Drive `drive.google.com/drive/folders/...`.
  static StorageLinkPayload? parseString(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      // 1. Format custom scheme cekpbb://storage?folder=...
      if (uri.scheme == deepLinkScheme && uri.host == deepLinkHost) {
        final folder = uri.queryParameters['folder'];
        if (folder != null && folder.trim().isNotEmpty) {
          return StorageLinkPayload(
            folder: folder.trim(),
            name: uri.queryParameters['name'],
            sender: uri.queryParameters['sender'],
          );
        }
      }

      // 2. Format Web Universal Link https://ikbalgumilar.github.io/Cek-PBB-Cianjur/connect?folder=...
      if (uri.host == webHost && uri.path.startsWith(webPath)) {
        final folder = uri.queryParameters['folder'];
        if (folder != null && folder.trim().isNotEmpty) {
          return StorageLinkPayload(
            folder: folder.trim(),
            name: uri.queryParameters['name'],
            sender: uri.queryParameters['sender'],
          );
        }
      }

      // 3. Format link murni Google Drive folders
      final driveFolderId = GoogleDriveBackupPolicy.extractFolderId(trimmed);
      if (driveFolderId != null) {
        return StorageLinkPayload(folder: trimmed);
      }
    }

    return null;
  }

  /// Membagikan tautan folder bersama lewat share sheet HP (atau salin ke clipboard di Desktop).
  static Future<void> shareStorageLink({
    required BuildContext context,
    required String folder,
    String? name,
    String? sender,
  }) async {
    final message = createInvitationMessage(
      folder: folder,
      name: name,
      sender: sender,
    );

    if (Platform.isAndroid) {
      await NativeFileHelper.shareText(
        text: message,
        title: 'Bagikan Tautan Folder Bersama',
      );
    } else {
      await Clipboard.setData(ClipboardData(text: message));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tautan undangan folder bersama disalin ke papan klip.',
            ),
          ),
        );
      }
    }
  }

  /// Inisialisasi pendengar Deep Link saat aplikasi berjalan di [context].
  Future<void> init(BuildContext context) async {
    _activeContext = context;
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) return;

    try {
      _deepLinkChannel.setMethodCallHandler((call) async {
        if (call.method == 'onDeepLink') {
          final link = call.arguments as String?;
          if (link != null && link.isNotEmpty) {
            final payload = parseString(link);
            if (payload != null && _activeContext != null) {
              await handlePayload(_activeContext!, payload);
            }
          }
        }
      });

      // Cek apakah aplikasi dibuka pertama kali lewat deep link saat dingin (cold start)
      final initialLink = await _deepLinkChannel.invokeMethod<String>(
        'getInitialLink',
      );
      if (initialLink != null && initialLink.isNotEmpty) {
        final payload = parseString(initialLink);
        if (payload != null && _activeContext != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_activeContext != null) {
              handlePayload(_activeContext!, payload);
            }
          });
        }
      }
    } catch (_) {}
  }

  /// Memperbarui context aktif bila halaman berganti
  void updateContext(BuildContext context) {
    _activeContext = context;
  }

  /// Menampilkan dialog konfirmasi penautan penyimpanan bersama ke pengguna.
  static Future<bool> handlePayload(
    BuildContext context,
    StorageLinkPayload payload,
  ) async {
    final currentLink = await BlokBackupScheduler.instance
        .getGoogleDriveFolderLink();
    final currentClean =
        GoogleDriveBackupPolicy.extractFolderId(currentLink) ??
        currentLink.trim();

    if (currentClean.isNotEmpty && currentClean == payload.cleanFolderId) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Penyimpanan bersama ini sudah terhubung (${payload.name ?? 'Folder Bersama'}).',
            ),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
      return true;
    }

    if (!context.mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConfirmStorageLinkDialog(payload: payload),
    );

    if (confirmed != true || !context.mounted) return false;

    final account = await BlokBackupScheduler.instance.getGoogleAccount();
    if (account.isEmpty) {
      // Jika akun Google belum terhubung, simpan link dan minta pengguna menghubungkan akun
      final success = await BlokBackupScheduler.instance
          .setGoogleDriveFolderLink(payload.folder);
      if (!context.mounted) return false;

      if (!success) {
        // Tampilkan info bahwa akun Google diperlukan
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text('Hubungkan Akun Google'),
              ],
            ),
            content: const Text(
              'Tautan folder bersama telah siap. Silakan hubungkan Akun Google Anda di menu Pengaturan > Penyimpanan Cadangan agar sinkronisasi otomatis aktif.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        );
        return false;
      }
    } else {
      final success = await BlokBackupScheduler.instance
          .setGoogleDriveFolderLink(payload.folder);
      if (!context.mounted) return false;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Penyimpanan bersama "${payload.name ?? 'DHKP Bersama'}" berhasil ditautkan!',
            ),
            backgroundColor: Colors.green.shade800,
          ),
        );
        return true;
      }
    }

    return false;
  }
}

/// Dialog konfirmasi penautan penyimpanan bersama.
class _ConfirmStorageLinkDialog extends StatelessWidget {
  final StorageLinkPayload payload;

  const _ConfirmStorageLinkDialog({required this.payload});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folderId = payload.cleanFolderId;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.cloud_sync_outlined, color: Colors.teal),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tautkan Penyimpanan Bersama',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aplikasi mendeteksi undangan tautan penyimpanan bersama untuk sinkronisasi data DHKP:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.teal.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (payload.name != null && payload.name!.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.label_outline,
                          size: 16,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          payload.name!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.folder_shared_outlined,
                        size: 16,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'ID Folder: $folderId',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? Colors.tealAccent
                                : Colors.teal.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (payload.sender != null && payload.sender!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Dikirim oleh: ${payload.sender}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Setelah ditautkan, pembaruan catatan status pembayaran dan bukti foto lapangan akan otomatis tersinkronisasi dengan kolektor lain di folder ini.',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Tautkan Sekarang'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
