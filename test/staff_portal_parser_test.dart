import 'dart:convert';

import 'package:cek_pbb_app/staff_portal/staff_portal_models.dart';
import 'package:cek_pbb_app/staff_portal/staff_portal_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffPortalModels helpers', () {
    test(
      'rapikanNamaWilayah collapses spaced single-letter region names only',
      () {
        expect(rapikanNamaWilayah('M A N D E'), 'MANDE');
        expect(rapikanNamaWilayah('J A M A L I'), 'JAMALI');
        expect(rapikanNamaWilayah('CIKIDANGBAYABANG'), 'CIKIDANGBAYABANG');
        expect(rapikanNamaWilayah('KARANG TENGAH'), 'KARANG TENGAH');
      },
    );

    test('parseAngkaServer handles English thousands commas and decimals', () {
      expect(parseAngkaServer('87,453'), 87453);
      expect(parseAngkaServer('590,540.00'), 590540);
      expect(parseAngkaServer('Rp 1,250,000.50'), 1250000);
      expect(parseAngkaServer('-'), 0);
    });
  });

  group('StaffPortalParser', () {
    test('extractErrorMessage reads .err-msg when present', () {
      const htmlWithErr =
          '<html><body><div class="err-msg"> Kata sandi salah </div></body></html>';
      const htmlNoErr = '<html><body><div>OK</div></body></html>';
      expect(
        StaffPortalParser.extractErrorMessage(htmlWithErr),
        'Kata sandi salah',
      );
      expect(StaffPortalParser.extractErrorMessage(htmlNoErr), isNull);
    });

    test('parseBankJson parses bank list from msg array', () {
      final body = jsonEncode({
        'msg': [
          {'CDC_B_ID': '110', 'CDC_B_NAME': 'BJB'},
          {'CDC_B_ID': '995', 'CDC_B_NAME': 'POS INDONESIA'},
        ],
      });
      final banks = StaffPortalParser.parseBankJson(body);
      expect(banks, hasLength(2));
      expect(banks[0].id, '110');
      expect(banks[0].name, 'BJB');
      expect(banks[1].id, '995');
      expect(banks[1].name, 'POS INDONESIA');
    });

    test(
      'parseGenericTable selects largest table and extracts headers & rows',
      () {
        const html = '''
        <table><tr><td>Kecil</td></tr></table>
        <table>
          <tr><th>No</th><th>NOP</th><th>Nama WP</th></tr>
          <tr><td>1</td><td>320520000401701540</td><td>BUDI</td></tr>
          <tr><td>2</td><td>320520000403005840</td><td>SITI</td></tr>
        </table>
      ''';
        final result = StaffPortalParser.parseGenericTable(html);
        expect(result.errorMessage, isNull);
        expect(result.headers, ['No', 'NOP', 'Nama WP']);
        expect(result.rows, hasLength(2));
        expect(result.rows.first, ['1', '320520000401701540', 'BUDI']);
      },
    );

    test(
      'parseKolektifGroupsJson extracts group actions, kelurahan code, and fields',
      () {
        final body = jsonEncode({
          'data': [
            [
              '<button class="btn-edit-group" group-id="GRP-001" status="0"></button>'
                  '<button class="btn-delete-group" group-id="GRP-001"></button>',
              'GRUP RT 01',
              'PAK RT',
              '08123456789',
              '12',
              '9876543210',
              '<span class="badge">Draft</span>',
              'MANDE',
              '<div class="nm-kel">BOBOJONG</div><div class="kd-kel">3205200004</div>',
              'Kolektif Tahap 1',
              '2026-12-31',
            ],
          ],
        });

        final res = StaffPortalParser.parseKolektifGroupsJson(body);
        expect(res.errorMessage, isNull);
        expect(res.groups, hasLength(1));
        final g = res.groups.first;
        expect(g.id, 'GRP-001');
        expect(g.statusCode, '0');
        expect(g.canEdit, isTrue);
        expect(g.canDelete, isTrue);
        expect(g.canPrintSurat, isFalse);
        expect(g.namaGroup, 'GRUP RT 01');
        expect(g.kelurahan, 'BOBOJONG');
        expect(g.kelurahanCode, '3205200004');
      },
    );

    test(
      'parseKolektifMemberJson extracts checkbox nop/year and computes totals',
      () {
        final body = jsonEncode({
          'data': [
            [
              '<input type="checkbox" value="320520000401701540" year="2026">',
              '32.05.200.004.017-0154.0',
              '2026',
              '30-09-2026',
              'AHMAD',
              'MANDE',
              'BOBOJONG',
              '100,000.00',
              '2,000.00',
              '102,000.00',
            ],
          ],
        });

        final res = StaffPortalParser.parseKolektifMemberJson(body);
        expect(res.errorMessage, isNull);
        expect(res.members, hasLength(1));
        expect(res.members.first.nop, '320520000401701540');
        expect(res.members.first.tahunPajak, '2026');
        expect(res.totalPokok, 100000);
        expect(res.totalDenda, 2000);
        expect(res.totalBayar, 102000);
      },
    );

    test('parseKolektifActionJson handles JSON and non-JSON responses', () {
      final ok = StaffPortalParser.parseKolektifActionJson(
        '{"success": true, "message": "Grup berhasil dibuat"}',
      );
      expect(ok.success, isTrue);
      expect(ok.responsDikenali, isTrue);
      expect(ok.message, 'Grup berhasil dibuat');

      final nonJson = StaffPortalParser.parseKolektifActionJson(
        '<html>502 Bad Gateway</html>',
      );
      expect(nonJson.success, isFalse);
      expect(nonJson.responsDikenali, isFalse);
    });
  });
}
