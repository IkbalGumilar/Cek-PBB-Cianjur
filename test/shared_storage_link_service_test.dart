import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cek_pbb_app/shared_storage_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SharedStorageLinkService - URL Generation', () {
    test('createShareableWebLink menghasilkan format HTTPS GitHub Pages yang valid', () {
      final url = SharedStorageLinkService.createShareableWebLink(
        folder: 'https://drive.google.com/drive/folders/1ABC_test_folder_123',
        name: 'Dusun 4 Bobojong',
        sender: 'petugas@gmail.com',
      );

      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'ikbalgumilar.github.io');
      expect(uri.path, '/Cek-PBB-Cianjur/connect');
      expect(
        uri.queryParameters['folder'],
        'https://drive.google.com/drive/folders/1ABC_test_folder_123',
      );
      expect(uri.queryParameters['name'], 'Dusun 4 Bobojong');
      expect(uri.queryParameters['sender'], 'petugas@gmail.com');
    });

    test('createCustomSchemeLink menghasilkan format cekpbb://storage yang valid', () {
      final url = SharedStorageLinkService.createCustomSchemeLink(
        folder: '1ABC_test_folder_123',
        name: 'Blok 032',
      );

      final uri = Uri.parse(url);
      expect(uri.scheme, 'cekpbb');
      expect(uri.host, 'storage');
      expect(uri.queryParameters['folder'], '1ABC_test_folder_123');
      expect(uri.queryParameters['name'], 'Blok 032');
    });

    test('createInvitationMessage menyertakan teks ramah kolektor dan link yang benar', () {
      final message = SharedStorageLinkService.createInvitationMessage(
        folder: '1ABC_test_folder_123',
        name: 'Dusun 4 Bobojong',
        sender: 'Koordinator PBB',
      );

      expect(message, contains('Tautan Penyimpanan Bersama DHKP Cianjur'));
      expect(message, contains('Dusun 4 Bobojong'));
      expect(message, contains('Koordinator PBB'));
      expect(message, contains('https://ikbalgumilar.github.io/Cek-PBB-Cianjur/connect'));
    });
  });

  group('SharedStorageLinkService - Parsing', () {
    test('parseString mengenali format Custom Scheme cekpbb://storage', () {
      const raw = 'cekpbb://storage?folder=1XYZ987654321&name=Wilayah%20Dusun%204&sender=admin';
      final payload = SharedStorageLinkService.parseString(raw);

      expect(payload, isNotNull);
      expect(payload!.folder, '1XYZ987654321');
      expect(payload.name, 'Wilayah Dusun 4');
      expect(payload.sender, 'admin');
      expect(payload.cleanFolderId, '1XYZ987654321');
    });

    test('parseString mengenali format Web Universal Link GitHub Pages', () {
      const raw =
          'https://ikbalgumilar.github.io/Cek-PBB-Cianjur/connect?folder=https%3A%2F%2Fdrive.google.com%2Fdrive%2Ffolders%2F1FOLDER_ABC_DEF&name=DHKP%20Kolektor';
      final payload = SharedStorageLinkService.parseString(raw);

      expect(payload, isNotNull);
      expect(
        payload!.folder,
        'https://drive.google.com/drive/folders/1FOLDER_ABC_DEF',
      );
      expect(payload.name, 'DHKP Kolektor');
      expect(payload.cleanFolderId, '1FOLDER_ABC_DEF');
    });

    test('parseString mengenali link langsung Google Drive folder', () {
      const raw = 'https://drive.google.com/drive/folders/1DIRECT_DRIVE_FOLDER_999?usp=sharing';
      final payload = SharedStorageLinkService.parseString(raw);

      expect(payload, isNotNull);
      expect(payload!.cleanFolderId, '1DIRECT_DRIVE_FOLDER_999');
    });

    test('parseString mengembalikan null untuk string kosong atau invalid', () {
      expect(SharedStorageLinkService.parseString(null), isNull);
      expect(SharedStorageLinkService.parseString('   '), isNull);
      expect(SharedStorageLinkService.parseString('https://google.com/search?q=cekpbb'), isNull);
      expect(SharedStorageLinkService.parseString('random text string'), isNull);
    });
  });

  group('StorageLinkPayload equality', () {
    test('dua payload dengan folder dan name identik dianggap sama', () {
      const p1 = StorageLinkPayload(
        folder: 'https://drive.google.com/drive/folders/1ABCDEF',
        name: 'Dusun 4',
      );
      const p2 = StorageLinkPayload(
        folder: '1ABCDEF',
        name: 'Dusun 4',
      );

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
    });
  });
}
