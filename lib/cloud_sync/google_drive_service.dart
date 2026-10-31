import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../blok_backup_scheduler.dart';
import '../google_auth_service.dart';
import '../google_drive_backup_policy.dart';

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

  static bool get hasMockItems => mockItems != null;

  @visibleForTesting
  static Future<File> Function(String fileId, String fileName)? mockDownloader;

  @visibleForTesting
  static Future<String?> Function(String folderName, {String? parentFolderId})?
  mockFolderFinder;

  @visibleForTesting
  static Future<String?> Function(String folderName, {String? parentFolderId})?
  mockFolderCreator;

  @visibleForTesting
  static Future<String?> Function({
    required File file,
    String? folderId,
    String? customFileName,
    String mimeType,
  })?
  mockUploader;

  @visibleForTesting
  static void resetForTesting() {
    mockItems = null;
    mockDownloader = null;
    mockFolderFinder = null;
    mockFolderCreator = null;
    mockUploader = null;
  }

  /// Mencari folder di Google Drive berdasarkan nama.
  Future<String?> findFolder(
    String folderName, {
    String? parentFolderId,
  }) async {
    if (mockFolderFinder != null) {
      return await mockFolderFinder!(
        folderName,
        parentFolderId: parentFolderId,
      );
    }

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders();
    if (authHeaders == null) return null;

    final queries = <String>[
      "mimeType = 'application/vnd.google-apps.folder'",
      "name = '$folderName'",
      "trashed = false",
    ];
    if (parentFolderId != null && parentFolderId.isNotEmpty) {
      queries.add("'$parentFolderId' in parents");
    }

    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files').replace(
      queryParameters: {
        'q': queries.join(' and '),
        'fields': 'files(id, name)',
        'pageSize': '1',
      },
    );

    try {
      final res = await _httpClient
          .get(uri, headers: authHeaders)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data =
            json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final files = data['files'] as List?;
        if (files != null && files.isNotEmpty) {
          final first = files.first;
          if (first is Map && first['id'] is String) {
            return first['id'] as String;
          }
        }
      }
    } catch (e) {
      debugPrint('findFolder error: $e');
    }
    return null;
  }

  /// Membuat folder baru di Google Drive pengguna.
  Future<String?> createFolder(
    String folderName, {
    String? parentFolderId,
  }) async {
    if (mockFolderCreator != null) {
      return await mockFolderCreator!(
        folderName,
        parentFolderId: parentFolderId,
      );
    }

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders();
    if (authHeaders == null) return null;

    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files');
    final bodyMap = <String, dynamic>{
      'name': folderName,
      'mimeType': 'application/vnd.google-apps.folder',
    };
    if (parentFolderId != null && parentFolderId.isNotEmpty) {
      bodyMap['parents'] = [parentFolderId];
    }

    final headers = {
      ...authHeaders,
      'Content-Type': 'application/json; charset=UTF-8',
    };

    try {
      final res = await _httpClient
          .post(uri, headers: headers, body: json.encode(bodyMap))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data =
            json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return data['id'] as String?;
      } else {
        debugPrint('createFolder failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      debugPrint('createFolder error: $e');
    }
    return null;
  }

  /// Memastikan folder khusus "Cek PBB Cianjur" ada di Google Drive pengguna.
  /// Jika belum ada, otomatis membuat folder baru.
  /// Mengembalikan ID folder Google Drive yang valid, atau null jika gagal.
  Future<String?> ensureDedicatedFolder({
    String folderName = GoogleDriveBackupPolicy.dedicatedFolderName,
  }) async {
    try {
      final existingId = await findFolder(folderName);
      if (existingId != null && existingId.isNotEmpty) {
        await BlokBackupScheduler.instance.setGoogleDriveFolderId(existingId);
        return existingId;
      }

      final newId = await createFolder(folderName);
      if (newId != null && newId.isNotEmpty) {
        await BlokBackupScheduler.instance.setGoogleDriveFolderId(newId);
        return newId;
      }
    } catch (e) {
      debugPrint('ensureDedicatedFolder error: $e');
    }
    return null;
  }

  /// Mengunggah berkas ke Google Drive (ke dalam folder khusus atau folder bersama).
  /// Otomatis memastikan folder target ada (membuat jika belum ada).
  Future<String?> uploadFile({
    required File file,
    String? folderId,
    String? customFileName,
    String mimeType = 'application/octet-stream',
  }) async {
    if (mockUploader != null) {
      return await mockUploader!(
        file: file,
        folderId: folderId,
        customFileName: customFileName,
        mimeType: mimeType,
      );
    }

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders(
      interactiveIfNeeded: true,
    );
    if (authHeaders == null) {
      throw Exception('Akun Google belum terhubung atau token kadaluarsa.');
    }

    String? targetFolderId = folderId;
    if (targetFolderId == null || targetFolderId.isEmpty) {
      targetFolderId = await ensureDedicatedFolder();
    }

    final fileName = customFileName ?? file.uri.pathSegments.last;
    final metadata = <String, dynamic>{'name': fileName};
    if (targetFolderId != null && targetFolderId.isNotEmpty) {
      metadata['parents'] = [targetFolderId];
    }

    final boundary =
        '----BoundaryUpload${DateTime.now().millisecondsSinceEpoch}';
    final metadataJson = json.encode(metadata);

    final fileBytes = await file.readAsBytes();

    final headerBytes = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadataJson\r\n'
      '--$boundary\r\n'
      'Content-Type: $mimeType\r\n\r\n',
    );
    final footerBytes = utf8.encode('\r\n--$boundary--\r\n');

    final fullBody = <int>[...headerBytes, ...fileBytes, ...footerBytes];

    final uri = Uri.parse(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size',
    );

    final req = http.Request('POST', uri);
    req.headers.addAll(authHeaders);
    req.headers['Content-Type'] = 'multipart/related; boundary=$boundary';
    req.headers['Content-Length'] = fullBody.length.toString();
    req.bodyBytes = fullBody;

    final streamedRes = await _httpClient
        .send(req)
        .timeout(const Duration(seconds: 45));
    final res = await http.Response.fromStream(streamedRes);

    if (res.statusCode == 200 || res.statusCode == 201) {
      final resData =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return resData['id'] as String?;
    } else {
      String errorMsg = 'Google Drive upload error ${res.statusCode}';
      try {
        final errJson = json.decode(res.body);
        if (errJson is Map && errJson['error'] is Map) {
          final m = errJson['error']['message'] as String?;
          if (m != null && m.isNotEmpty) {
            errorMsg = m;
          }
        }
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  static bool isSupportedDkhpFileName(String name, {bool isFolder = false}) {
    if (isFolder) return true;
    final lower = name.trim().toLowerCase();
    return lower.endsWith('.dkhp') ||
        lower.endsWith('.dhkp') ||
        lower.endsWith('.dat') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.txt');
  }

  List<GoogleDriveItem> _parseDriveItems(Map<String, dynamic> data) {
    final items = <GoogleDriveItem>[];
    if (data['files'] is List) {
      final list = data['files'] as List;
      for (final item in list) {
        if (item is Map) {
          final name = item['name'] as String? ?? '';
          final mime = item['mimeType'] as String? ?? '';
          final isFolder = mime == 'application/vnd.google-apps.folder';
          if (isSupportedDkhpFileName(name, isFolder: isFolder)) {
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
    }
    return items;
  }

  /// Mengambil daftar berkas DHKP (.dhkp / .dkhp) dan data tabel dari Google Drive pengguna via REST API v3.
  Future<List<GoogleDriveItem>> listDkhpFiles({String? folderId}) async {
    if (mockItems != null) return mockItems!;

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders(
      interactiveIfNeeded: true,
    );
    if (authHeaders == null) {
      return [];
    }

    String? targetFolderId = folderId;
    if (targetFolderId == null || targetFolderId.isEmpty) {
      final sharedLink = await BlokBackupScheduler.instance
          .getGoogleDriveFolderLink();
      targetFolderId = GoogleDriveBackupPolicy.extractFolderId(sharedLink);
      if (targetFolderId == null || targetFolderId.isEmpty) {
        // Cek apakah folder "Cek PBB Cianjur" ada, jika tidak ada maka buat folder baru
        targetFolderId = await ensureDedicatedFolder();
      }
    }

    final queries = <String>['trashed = false'];
    if (targetFolderId != null && targetFolderId.isNotEmpty) {
      queries.add("'$targetFolderId' in parents");
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
            json.decode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>;
        final itemsById = <String, GoogleDriveItem>{};
        for (final item in _parseDriveItems(data)) {
          if (item.id.isNotEmpty) {
            itemsById[item.id] = item;
          }
        }

        // Jika berada di level utama (folderId == null), cari juga berkas .dhkp / .dkhp
        // yang mungkin ditaruh pengguna di luar folder ID baru (misal di folder "Cek PBB Cianjur"
        // lain atau di root Drive) agar selalu terdeteksi.
        if (folderId == null || folderId.isEmpty) {
          try {
            final fallbackUri =
                Uri.parse('https://www.googleapis.com/drive/v3/files').replace(
                  queryParameters: {
                    'q':
                        "trashed = false and mimeType != 'application/vnd.google-apps.folder' and (name contains '.dhkp' or name contains '.dkhp' or name contains 'dhkp' or name contains 'dkhp')",
                    'pageSize': '50',
                    'fields': 'files(id, name, mimeType, size, modifiedTime)',
                    'orderBy': 'modifiedTime desc',
                  },
                );
            final fallbackRes = await _httpClient
                .get(fallbackUri, headers: authHeaders)
                .timeout(const Duration(seconds: 12));
            if (fallbackRes.statusCode == 200) {
              final fallbackData =
                  json.decode(utf8.decode(fallbackRes.bodyBytes))
                      as Map<String, dynamic>;
              for (final item in _parseDriveItems(fallbackData)) {
                if (item.id.isNotEmpty) {
                  itemsById.putIfAbsent(item.id, () => item);
                }
              }
            }
          } catch (_) {}
        }

        return itemsById.values.toList();
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

    final authHeaders = await GoogleAuthService.instance.getAuthHeaders(
      interactiveIfNeeded: true,
    );
    if (authHeaders != null) {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      );
      final request = http.Request('GET', url);
      request.headers.addAll(authHeaders);

      final streamedResponse = await _httpClient.send(request);
      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Gagal mengunduh berkas Drive (Status ${streamedResponse.statusCode}).',
        );
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
      'https://drive.google.com/uc?export=download&id=$fileId&confirm=t',
    );
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
        final confirmMatch = RegExp(
          r'confirm=([0-9a-zA-Z_-]+)',
        ).firstMatch(content);
        if (confirmMatch != null) {
          final confirmCode = confirmMatch.group(1);
          final confirmUrl = Uri.parse(
            'https://drive.google.com/uc?export=download&confirm=$confirmCode&id=$fileId',
          );
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
