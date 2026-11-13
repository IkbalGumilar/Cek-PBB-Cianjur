import 'package:cek_pbb_app/nop_helper.dart';
import 'package:cek_pbb_app/nop_scanner.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dynamic Wilayah and NOP Helper Tests', () {
    setUp(() {
      resetNopPrefix();
    });

    tearDown(() {
      resetNopPrefix();
    });

    test('default nopPrefix points to Bobojong (3205200004)', () {
      expect(nopPrefix, '3205200004');
      expect(activeNopPrefix, '3205200004');
    });

    test(
      'activeNopPrefix setter updates prefix and resetNopPrefix restores default',
      () {
        activeNopPrefix = '3205200001'; // Mekarjaya
        expect(nopPrefix, '3205200001');

        // Invalid length ignored
        activeNopPrefix = '123';
        expect(nopPrefix, '3205200001');

        resetNopPrefix();
        expect(nopPrefix, '3205200004');
      },
    );

    test('expandNop uses active prefix and optional custom prefix', () {
      // Shorthand 5 digit: 2 digit blok (17 -> 017), 3 digit wilayah (154 -> 0154)
      expect(expandNop('17154'), '320520000401701540');

      // With custom prefix parameter
      expect(expandNop('17154', '3205200002'), '320520000201701540');

      // With activeNopPrefix changed
      activeNopPrefix = '3205200009'; // Jamali
      expect(expandNop('17154'), '320520000901701540');
    });

    test('buildNop uses active prefix and optional custom prefix', () {
      expect(buildNop(blok: '17', wilayah: '154'), '320520000401701540');
      expect(
        buildNop(blok: '17', wilayah: '154', prefix: '3205200003'),
        '320520000301701540',
      );
    });

    test('lookupMandeKelurahanName maps all 12 verified villages', () {
      expect(lookupMandeKelurahanName('001'), 'MEKARJAYA');
      expect(lookupMandeKelurahanName('002'), 'SUKAMANAH');
      expect(lookupMandeKelurahanName('003'), 'KADEMANGAN');
      expect(lookupMandeKelurahanName('004'), 'BOBOJONG');
      expect(lookupMandeKelurahanName('005'), 'CIKIDANGBAYABANG');
      expect(lookupMandeKelurahanName('006'), 'MANDE');
      expect(lookupMandeKelurahanName('007'), 'MURNISARI');
      expect(lookupMandeKelurahanName('008'), 'MULYASARI');
      expect(lookupMandeKelurahanName('009'), 'JAMALI');
      expect(lookupMandeKelurahanName('010'), 'CIANDAM');
      expect(lookupMandeKelurahanName('011'), 'KUTAWARINGIN');
      expect(lookupMandeKelurahanName('012'), 'LEUWIKOJA');
      expect(lookupMandeKelurahanName('999'), 'Desa 999');
    });

    test('lookupKecamatanName maps 200 to MANDE', () {
      expect(lookupKecamatanName('200'), 'MANDE');
      expect(lookupKecamatanName('010'), 'Kecamatan 010');
    });

    test(
      'NopScanParser extracts NOPs across different villages in Cianjur',
      () {
        const text = '''
      Pajak Bumi dan Bangunan
      NOP: 32.05.200.001.005-0012.0
      Atau desa lain: 320520000901701540
      NOP Singkat: 17154
      ''';
        final results = NopScanParser.extract(text);
        expect(results.contains('320520000100500120'), isTrue);
        expect(results.contains('320520000901701540'), isTrue);
        expect(results.contains('320520000401701540'), isTrue);
      },
    );

    test('StaffPortalClient setCustomWilayah updates active parameters', () {
      final client = StaffPortalClient();
      expect(client.activeKecamatanCode, '3205200');
      expect(client.activeKecamatanName, 'MANDE');
      expect(client.activeKelurahanCode, '3205200004');
      expect(client.activeKelurahanName, 'BOBOJONG');

      client.setCustomWilayah(
        kecamatanCode: '3205010',
        kecamatanName: 'AGRABINTA',
        kelurahanCode: '3205010001',
        kelurahanName: 'AGRABINTA DESA',
      );

      expect(client.activeKecamatanCode, '3205010');
      expect(client.activeKecamatanName, 'AGRABINTA');
      expect(client.activeKelurahanCode, '3205010001');
      expect(client.activeKelurahanName, 'AGRABINTA DESA');
    });
  });
}
