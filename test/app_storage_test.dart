import 'dart:io';
import 'dart:typed_data';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/download_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppStorage.resetForTesting();
  });

  tearDown(() {
    AppStorage.resetForTesting();
  });

  group('AppStorage & Unified Storage Mapping', () {
    test('appPackageName is id.cianjur.pbb', () {
      expect(AppStorage.appPackageName, 'id.cianjur.pbb');
    });

    test('resolves and creates directories properly', () async {
      final dataDir = await AppStorage.getDataDirectory();
      expect(await dataDir.exists(), isTrue);
      expect(dataDir.path.contains('id.cianjur.pbb'), isTrue);

      final mediaDir = await AppStorage.getMediaDirectory();
      expect(await mediaDir.exists(), isTrue);

      final dbFile = await AppStorage.getDatabaseFile();
      expect(dbFile.path, endsWith('blok_data.csv'));

      final photosDir = await AppStorage.getPhotosDirectory();
      expect(await photosDir.exists(), isTrue);
      expect(photosDir.path, endsWith('photos'));

      final docDir = await AppStorage.getDocumentsDirectory();
      expect(await docDir.exists(), isTrue);
      expect(docDir.path, endsWith('documents'));

      final backupDir = await AppStorage.getBackupsDirectory();
      expect(await backupDir.exists(), isTrue);
      expect(backupDir.path, endsWith('backups'));

      final cookiesDir = await AppStorage.getCookiesDirectory();
      expect(await cookiesDir.exists(), isTrue);
      expect(cookiesDir.path, endsWith('cookies'));
    });

    test('DownloadHelper mimeTypeFor returns correct mime types', () {
      expect(DownloadHelper.mimeTypeFor('test.pdf'), 'application/pdf');
      expect(DownloadHelper.mimeTypeFor('data.csv'), 'text/csv');
      expect(
        DownloadHelper.mimeTypeFor('sheet.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(
        DownloadHelper.mimeTypeFor('app.apk'),
        'application/vnd.android.package-archive',
      );
      expect(
        DownloadHelper.mimeTypeFor('backup.bak'),
        'application/octet-stream',
      );
      expect(
        DownloadHelper.mimeTypeFor('package.dkhp'),
        'application/octet-stream',
      );
    });

    test('DownloadHelper saves documents to desktop storage directory', () async {
      final testData = [1, 2, 3, 4, 5];
      final path = await DownloadHelper.saveBytes(
        Uint8List.fromList(testData),
        'test_unit_export.csv',
      );
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), testData);
      expect(path.contains('id.cianjur.pbb'), isTrue);
      await file.delete();
    });
  });
}
