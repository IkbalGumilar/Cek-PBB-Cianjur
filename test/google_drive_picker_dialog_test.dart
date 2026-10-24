import 'dart:io';

import 'package:cek_pbb_app/blok_backup_scheduler.dart';
import 'package:cek_pbb_app/google_auth_service.dart';
import 'package:cek_pbb_app/google_drive_backup_policy.dart';
import 'package:cek_pbb_app/google_drive_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageValues = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorageValues.clear();
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return secureStorageValues[arguments['key']];
        case 'write':
          secureStorageValues[arguments['key'] as String] =
              arguments['value'] as String;
          return null;
        case 'delete':
          secureStorageValues.remove(arguments['key']);
          return null;
        case 'containsKey':
          return secureStorageValues.containsKey(arguments['key']);
        case 'deleteAll':
          secureStorageValues.clear();
          return null;
      }
      return null;
    });

    BlokBackupScheduler.instance.resetForTesting();
    GoogleAuthService.resetForTesting();
    GoogleDriveService.resetForTesting();
  });

  group('GoogleDriveBackupPolicy extractFileId tests', () {
    test('Mengekstrak ID dari URL file Google Drive standar', () {
      const url =
          'https://drive.google.com/file/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OIvE2up0Y/view?usp=sharing';
      expect(
        GoogleDriveBackupPolicy.extractFileId(url),
        '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OIvE2up0Y',
      );
    });

    test('Mengekstrak ID dari URL uc?export=download&id=...', () {
      const url =
          'https://drive.google.com/uc?export=download&id=1ABC_xyz-9876543210';
      expect(
        GoogleDriveBackupPolicy.extractFileId(url),
        '1ABC_xyz-9876543210',
      );
    });

    test('Mengekstrak ID dari URL folder Google Drive', () {
      const url =
          'https://drive.google.com/drive/folders/1Folder_ABC1234567890';
      expect(
        GoogleDriveBackupPolicy.extractFileId(url),
        '1Folder_ABC1234567890',
      );
    });

    test('Mengekstrak ID mentah (panjang >= 15 karakter)', () {
      const rawId = '1BxiMVs0XRA5nFMdKvBdBZj';
      expect(GoogleDriveBackupPolicy.extractFileId(rawId), rawId);
    });

    test('Mengembalikan null untuk teks kosong atau tidak valid', () {
      expect(GoogleDriveBackupPolicy.extractFileId(''), isNull);
      expect(GoogleDriveBackupPolicy.extractFileId('   '), isNull);
      expect(GoogleDriveBackupPolicy.extractFileId('pendek'), isNull);
    });
  });

  group('GoogleDriveItem formatting tests', () {
    test('formattedSize memformat ukuran berkas dengan tepat', () {
      const itemFolder = GoogleDriveItem(
        id: '1',
        name: 'Folder Data',
        isFolder: true,
      );
      expect(itemFolder.formattedSize, 'Folder');

      const itemB = GoogleDriveItem(
        id: '2',
        name: 'kecil.txt',
        size: 512,
      );
      expect(itemB.formattedSize, '512 B');

      const itemKb = GoogleDriveItem(
        id: '3',
        name: 'data.csv',
        size: 2048,
      );
      expect(itemKb.formattedSize, '2.0 KB');

      const itemMb = GoogleDriveItem(
        id: '4',
        name: 'cadangan.dkhp',
        size: 5 * 1024 * 1024,
      );
      expect(itemMb.formattedSize, '5.0 MB');
    });

    test('formattedModifiedDate memformat waktu dengan benar', () {
      final dt = DateTime(2026, 10, 24, 14, 30);
      final item = GoogleDriveItem(
        id: '5',
        name: 'dkhp.dkhp',
        modifiedTime: dt,
      );
      expect(item.formattedModifiedDate, contains('24/10/2026'));
    });
  });

  group('GoogleDriveService Mock Tests', () {
    test('listDkhpFiles mengembalikan mockItems jika tersedia', () async {
      GoogleDriveService.mockItems = [
        const GoogleDriveItem(
          id: 'test_1',
          name: 'dkhp_desa.dkhp',
          size: 10240,
        ),
        const GoogleDriveItem(
          id: 'test_2',
          name: 'tagihan.csv',
          size: 2048,
        ),
      ];

      final files = await GoogleDriveService.instance.listDkhpFiles();
      expect(files.length, 2);
      expect(files.first.name, 'dkhp_desa.dkhp');
      expect(files.last.name, 'tagihan.csv');
    });

    test('downloadFile menggunakan mockDownloader jika disetel', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_download.dkhp');
      await tempFile.writeAsString('mock content');

      GoogleDriveService.mockDownloader = (fileId, fileName) async {
        return tempFile;
      };

      final downloaded = await GoogleDriveService.instance.downloadFile(
        fileId: 'mock_123',
        fileName: 'mock.dkhp',
      );

      expect(downloaded.path, tempFile.path);
      expect(await downloaded.readAsString(), 'mock content');

      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });
  });

  group('GoogleDrivePickerDialog Widget Tests', () {
    testWidgets('Menampilkan UI Google Drive Dialog & Tab dengan benar',
        (tester) async {
      GoogleDriveService.mockItems = [
        const GoogleDriveItem(
          id: 'drive_1',
          name: 'cadangan_bobojong.dkhp',
          size: 1024 * 1024,
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GoogleDrivePickerDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('Berkas Drive'), findsOneWidget);
      expect(find.text('Tempel Link / ID'), findsOneWidget);
      expect(find.text('cadangan_bobojong.dkhp'), findsOneWidget);
      expect(find.text('Buka Aplikasi Drive'), findsOneWidget);
    });

    testWidgets('Berpindah ke Tab Tempel Link dan validasi input kosong',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GoogleDrivePickerDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap tab Tempel Link
      await tester.tap(find.text('Tempel Link / ID'));
      await tester.pumpAndSettle();

      expect(find.text('Buka Berkas via Link Google Drive'), findsOneWidget);
      expect(find.text('Unduh & Buka Berkas'), findsOneWidget);

      // Tekan tombol unduh tanpa input
      await tester.tap(find.text('Unduh & Buka Berkas'));
      await tester.pumpAndSettle();

      expect(
        find.text('Masukkan link atau ID berkas Google Drive.'),
        findsOneWidget,
      );
    });

    testWidgets('Memilih berkas Drive berhasil mengembalikan path',
        (tester) async {
      final tempFile =
          File('${Directory.systemTemp.path}/test_result.dkhp');
      tempFile.writeAsStringSync('dkhp zip bytes');

      GoogleDriveService.mockItems = [
        const GoogleDriveItem(
          id: 'file_99',
          name: 'master_2026.dkhp',
          size: 2048,
        ),
      ];

      GoogleDriveService.mockDownloader = (fileId, fileName) async {
        return tempFile;
      };

      String? resultPath;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  resultPath = await showGoogleDrivePickerDialog(ctx);
                },
                child: const Text('Buka Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Picker'));
      await tester.pumpAndSettle();

      expect(find.text('master_2026.dkhp'), findsOneWidget);

      // Tap baris berkas
      await tester.tap(find.text('master_2026.dkhp'));
      await tester.pumpAndSettle();

      expect(resultPath, tempFile.path);

      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });
  });
}
