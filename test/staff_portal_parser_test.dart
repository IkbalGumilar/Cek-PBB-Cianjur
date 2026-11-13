import 'dart:convert';

import 'package:cek_pbb_app/dhkp/blok_catatan_models.dart';
import 'package:cek_pbb_app/staff_portal/staff_portal_models.dart';
import 'package:cek_pbb_app/staff_portal/staff_portal_parser.dart';
import 'package:cek_pbb_app/staff_portal_token_extractor.dart';
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
      'parseGenericTable handles toolbar/export button row above <th> headers',
      () {
        const html = '''
        <table border="1">
          <tr><td align="right"><input type="button" value="Ekspor ke Excel"></td></tr>
          <tr><th>No</th><th>Kelurahan</th><th>Baku</th><th>Realisasi</th><th>%</th></tr>
          <tr><td>1</td><td>BOBOJONG</td><td>232.798.953</td><td>109.341.563</td><td>46,97</td></tr>
          <tr><td></td><td>TOTAL</td><td>232.798.953</td><td>109.341.563</td><td>46,97</td></tr>
        </table>
      ''';
        final result = StaffPortalParser.parseGenericTable(html);
        expect(result.errorMessage, isNull);
        expect(result.headers, ['No', 'Kelurahan', 'Baku', 'Realisasi', '%']);
        expect(result.rows, hasLength(2));
        expect(result.rows[0], [
          '1',
          'BOBOJONG',
          '232.798.953',
          '109.341.563',
          '46,97',
        ]);
        expect(result.rows[1], [
          '',
          'TOTAL',
          '232.798.953',
          '109.341.563',
          '46,97',
        ]);
      },
    );

    test(
      'parseGenericTable infers 5-column ranking headers when only td data rows exist',
      () {
        const html = '''
        <table>
          <tr><td>&nbsp;</td></tr>
          <tr><td>1</td><td>BOBOJONG</td><td>232.798.953</td><td>109.341.563</td><td>46,97</td></tr>
          <tr><td></td><td>TOTAL</td><td>232.798.953</td><td>109.341.563</td><td>46,97</td></tr>
        </table>
      ''';
        final result = StaffPortalParser.parseGenericTable(html);
        expect(result.errorMessage, isNull);
        expect(result.headers, [
          'No',
          'Desa / Kelurahan',
          'Pagu / Ketetapan',
          'Realisasi',
          '% Realisasi',
        ]);
        expect(result.rows, hasLength(2));
        expect(result.rows[0].length, 5);
        expect(result.rows[1].length, 5);
      },
    );

    test('parseGenericTable normalizes row lengths to match header length', () {
      const html = '''
        <table>
          <tr><th>A</th><th>B</th><th>C</th><th>D</th></tr>
          <tr><td>1</td><td>2</td></tr>
          <tr><td>1</td><td>2</td><td>3</td><td>4</td><td>5</td></tr>
        </table>
      ''';
      final result = StaffPortalParser.parseGenericTable(html);
      expect(result.headers, ['A', 'B', 'C', 'D', 'Kolom 5']);
      expect(result.rows[0], ['1', '2', '', '', '']);
      expect(result.rows[1], ['1', '2', '3', '4', '5']);
    });

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

    test('parseSummaryTotals parses metrics from HTML IDs correctly', () {
      const htmlSudahBayar = '''
        <div>
          <b>Jumlah OP :</b> <span id="tot_jumlah_op">1.973</span>
          <b>Pokok Ketetapan :</b> <span id="tot_pokok">244.684.372</span>
          <b>Pokok Pembayaran :</b> <span id="tot_pokok_pembayaran">244.684.372</span>
          <b>Denda :</b> <span id="tot_denda">599.695</span>
          <b>Total Penerimaan :</b> <span id="tot_penerimaan">245.284.067</span>
        </div>
      ''';
      final s = StaffPortalParser.parseSummaryTotals(htmlSudahBayar);
      expect(s, isNotNull);
      expect(s!.jumlahOp, 1973);
      expect(s.pokokKetetapan, 244684372);
      expect(s.pokokPembayaran, 244684372);
      expect(s.denda, 599695);
      expect(s.totalPenerimaan, 245284067);

      const htmlBelumBayar = '''
        <div>
          <b>Jumlah OP :</b> <span id="bb_tot_jumlah_op">4.200</span>
          <b>Pokok Ketetapan :</b> <span id="bb_tot_pokok">500.000.000</span>
          <b>Estimasi Denda :</b> <span id="bb_tot_denda">15.000.000</span>
          <b>Estimasi Total :</b> <span id="bb_tot_penerimaan">515.000.000</span>
        </div>
      ''';
      final bb = StaffPortalParser.parseSummaryTotals(htmlBelumBayar);
      expect(bb, isNotNull);
      expect(bb!.jumlahOp, 4200);
      expect(bb.pokokKetetapan, 500000000);
      expect(bb.denda, 15000000);
      expect(bb.totalPenerimaan, 515000000);
    });

    test(
      'parseExcelQueueTable parses queue items, download links, and hapus IDs',
      () {
        const htmlQueue = '''
        <div id="frame-tbl-monitoring" class="tbl-monitoring">
          <table width="100%" cellspacing="2" cellpadding="7" border="0">
            <tbody>
              <tr>
                <th>NO</th><th>Tanggal</th><th>Filter</th><th>Status</th><th>Download</th><th>Hapus</th>
              </tr>
              <tr>
                <td align="center">1</td>
                <td align="center">27-10-2025 11:05:18</td>
                <td><ul><li>Tanggal: 01-01-25</li><li>Kel: BOBOJONG</li></ul></td>
                <td align="center"><img src="accept.png"></td>
                <td align="center"><a href="https://cianjurkab.v-tax.id/download?file=sudah_bayar_01.xlsx">Download</a></td>
                <td align="center"><a href="javascript:void(0)" onclick="javascript:hapus('abc123cpm')">Hapus</a></td>
              </tr>
              <tr>
                <td align="center">2</td>
                <td align="center">27-10-2025 10:00:00</td>
                <td><ul><li>Filter 2</li></ul></td>
                <td align="center">Processing...</td>
                <td align="center"></td>
                <td align="center"><a href="javascript:void(0)" onclick="javascript:hapus('def456cpm')">Hapus</a></td>
              </tr>
              <tr>
                <td colspan="6" align="center"><div>1 - 2 dari 2</div></td>
              </tr>
            </tbody>
          </table>
        </div>
      ''';

        final queue = StaffPortalParser.parseExcelQueueTable(htmlQueue);
        expect(queue.errorMessage, isNull);
        expect(queue.items, hasLength(2));
        expect(queue.paginationText, '1 - 2 dari 2');

        final item1 = queue.items[0];
        expect(item1.no, '1');
        expect(item1.tanggal, '27-10-2025 11:05:18');
        expect(item1.filterSummary, 'Tanggal: 01-01-25 • Kel: BOBOJONG');
        expect(item1.isProcessing, isFalse);
        expect(item1.fileName, 'sudah_bayar_01.xlsx');
        expect(item1.hapusId, 'abc123cpm');

        final item2 = queue.items[1];
        expect(item2.no, '2');
        expect(item2.isProcessing, isTrue);
        expect(item2.fileName, isNull);
        expect(item2.hapusId, 'def456cpm');
      },
    );

    test(
      'parseMonitoringKelurahanOptions extracts kelurahan options from select',
      () {
        const html = '''
        <table>
          <tr>
            <td>Desa/Kelurahan</td>
            <td><select id="kelurahan-1">
              <option value="3205200004">BOBOJONG</option>
              <option value="3205200001">JAMALI</option>
            </select></td>
          </tr>
        </table>
      ''';
        final options = StaffPortalParser.parseMonitoringKelurahanOptions(html);
        expect(options, hasLength(2));
        expect(options[0].code, '3205200004');
        expect(options[0].name, 'BOBOJONG');
        expect(options[1].code, '3205200001');
        expect(options[1].name, 'JAMALI');
      },
    );

    test(
      'StaffPortalTokenExtractor extracts IDKEC and IDKEL from Monitoring HTML',
      () {
        const html = '''
        var IDKEC = '3205200';
        var IDKEL = '3205200004';
        var ROLE  = 'rmKelurahan';
      ''';
        expect(
          StaffPortalTokenExtractor.extractMonitoringIdKec(html),
          '3205200',
        );
        expect(
          StaffPortalTokenExtractor.extractMonitoringIdKel(html),
          '3205200004',
        );
      },
    );

    test('availableDhkpYears contains 2015 s.d. current year', () {
      final years = availableDhkpYears();
      expect(years.first, 2015);
      expect(years.contains(2015), isTrue);
      expect(years.contains(2016), isTrue);
      expect(years.contains(2022), isTrue);
      expect(years.contains(2026), isTrue);
      expect(years.last, greaterThanOrEqualTo(2026));
    });

    test(
      'StaffPortalClient session detection recognizes both single and double quoted user-menu',
      () {
        const singleQuoteHtml = '''
        <div id='user-menu'> Jam Server : <span>...</span> User: MANDE_BOBOJONG (<a href='main.php?param=bG9nb3V0PTE='>logout</a>)</div>
      ''';
        const doubleQuoteHtml = '''
        <div id="user-menu"> Jam Server : <span>...</span> User: MANDE_BOBOJONG (<a href="main.php?param=bG9nb3V0PTE=">logout</a>)</div>
      ''';
        const unauthenticatedHtml = '''
        <body class='login-page'><div id='header'>PBB-P2 KABUPATEN CIANJUR</div></body>
      ''';

        bool isSessionActive(String html) =>
            html.contains('user-menu') && html.contains('logout');

        expect(isSessionActive(singleQuoteHtml), isTrue);
        expect(isSessionActive(doubleQuoteHtml), isTrue);
        expect(isSessionActive(unauthenticatedHtml), isFalse);
      },
    );

    test('isSessionExpired detects 302 redirects to login and login forms', () {
      expect(
        StaffPortalParser.isSessionExpired(
          '',
          statusCode: 302,
          location: 'https://cianjurkab.v-tax.id/plogin.php',
        ),
        isTrue,
      );
      expect(
        StaffPortalParser.isSessionExpired(
          '',
          statusCode: 302,
          location: '/main.php',
        ),
        isTrue,
      );
      expect(
        StaffPortalParser.isSessionExpired(
          '<form action="plogin.php"><input name="usr"><input name="pwd"></form>',
        ),
        isTrue,
      );
      expect(
        StaffPortalParser.isSessionExpired(
          '<div>Sesi Anda telah berakhir, silahkan login kembali</div>',
        ),
        isTrue,
      );
      expect(
        StaffPortalParser.isSessionExpired(
          '<table><tr><td>1</td><td>320520000400100010</td></tr></table>',
        ),
        isFalse,
      );
    });

    test(
      'parseGenericTable handles session expiration and thousand-formatted pagination',
      () {
        final expired = StaffPortalParser.parseGenericTable(
          '<form action="plogin.php"><input name="cImage"></form>',
        );
        expect(expired.errorMessage, contains('kedaluwarsa'));

        const htmlWithDots = '''
        <table>
          <tr><th>No</th><th>NOP</th></tr>
          <tr><td>1</td><td>320520000400100010</td></tr>
        </table>
        <div id="paging-tbl">&nbsp;1 - 50 dari 15.515&nbsp;<span id="next-page" onclick="setPage('2','2')"></span></div>
      ''';
        final res = StaffPortalParser.parseGenericTable(htmlWithDots);
        expect(res.errorMessage, isNull);
        expect(res.pageStart, 1);
        expect(res.pageEnd, 50);
        expect(res.totalRecords, 15515);
        expect(res.hasNextPage, isTrue);
      },
    );

    test('kolektif and excel queue parsers recognize session expiration', () {
      final qRes = StaffPortalParser.parseExcelQueueTable(
        '<html><body>Silahkan login kembali</body></html>',
      );
      expect(qRes.errorMessage, contains('kedaluwarsa'));

      final grpRes = StaffPortalParser.parseKolektifGroupsJson(
        '<html><form action="plogin.php"></form></html>',
      );
      expect(grpRes.errorMessage, contains('kedaluwarsa'));

      final memRes = StaffPortalParser.parseKolektifMemberJson(
        '<html><form action="plogin.php"></form></html>',
      );
      expect(memRes.errorMessage, contains('kedaluwarsa'));

      final actRes = StaffPortalParser.parseKolektifActionJson(
        '<html><form action="plogin.php"></form></html>',
      );
      expect(actRes.success, isFalse);
      expect(actRes.message, contains('kedaluwarsa'));
      expect(actRes.responsDikenali, isFalse);
    });
  });
}
