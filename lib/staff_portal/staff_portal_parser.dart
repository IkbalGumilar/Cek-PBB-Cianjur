import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'staff_portal_models.dart';

/// Parser murni (stateless) untuk membongkar respons HTML dan JSON dari Portal Staf (`cianjurkab.v-tax.id`).
class StaffPortalParser {
  StaffPortalParser._();

  static String? extractErrorMessage(String html) {
    final document = html_parser.parse(html);
    final text = document.querySelector('.err-msg')?.text.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static List<BankOption> parseBankJson(String body) {
    try {
      final decoded = jsonDecode(body);
      final list = decoded is Map ? decoded['msg'] : null;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map(
            (m) =>
                BankOption(id: '${m['CDC_B_ID']}', name: '${m['CDC_B_NAME']}'),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// Baca ringkasan angka (KPI/Totals) dari HTML hasil query Monitoring Wilayah
  /// (baik tab Sudah Bayar, Belum Bayar, maupun Realisasi).
  static MonitoringSummaryTotals? parseSummaryTotals(String html) {
    if (html.isEmpty) return null;
    final document = html_parser.parse(html);

    String? getText(String id) =>
        document.querySelector('#$id')?.text.trim();

    // 1. Coba tab Sudah Bayar
    var jumlahOpRaw = getText('tot_jumlah_op');
    var pokokKetetapanRaw = getText('tot_pokok');
    var pokokBayarRaw = getText('tot_pokok_pembayaran');
    var dendaRaw = getText('tot_denda');
    var totalRaw = getText('tot_penerimaan');

    // 2. Coba tab Belum Bayar
    if (jumlahOpRaw == null || jumlahOpRaw.isEmpty) {
      jumlahOpRaw = getText('bb_tot_jumlah_op');
      pokokKetetapanRaw = getText('bb_tot_pokok');
      dendaRaw = getText('bb_tot_denda');
      totalRaw = getText('bb_tot_penerimaan');
    }

    // 3. Coba tab Realisasi
    if ((pokokBayarRaw == null || pokokBayarRaw.isEmpty) &&
        (pokokKetetapanRaw == null || pokokKetetapanRaw.isEmpty)) {
      pokokBayarRaw = getText('rea_pokok');
      dendaRaw = getText('rea_denda');
      totalRaw = getText('rea_penerimaan');
    }

    // Fallback: regex scan jika tag berada dalam potongan HTML tanpa body utuh
    jumlahOpRaw ??= RegExp(r'''id=["'](?:bb_)?tot_jumlah_op["'][^>]*>([^<]+)<''', caseSensitive: false).firstMatch(html)?.group(1);
    pokokKetetapanRaw ??= RegExp(r'''id=["'](?:bb_)?tot_pokok["'][^>]*>([^<]+)<''', caseSensitive: false).firstMatch(html)?.group(1);
    pokokBayarRaw ??= RegExp(r'''id=["'](?:tot_pokok_pembayaran|rea_pokok)["'][^>]*>([^<]+)<''', caseSensitive: false).firstMatch(html)?.group(1);
    dendaRaw ??= RegExp(r'''id=["'](?:tot_denda|bb_tot_denda|rea_denda)["'][^>]*>([^<]+)<''', caseSensitive: false).firstMatch(html)?.group(1);
    totalRaw ??= RegExp(r'''id=["'](?:tot_penerimaan|bb_tot_penerimaan|rea_penerimaan)["'][^>]*>([^<]+)<''', caseSensitive: false).firstMatch(html)?.group(1);

    final summary = MonitoringSummaryTotals(
      jumlahOp: parseAngkaServer(jumlahOpRaw ?? ''),
      pokokKetetapan: parseAngkaServer(pokokKetetapanRaw ?? ''),
      pokokPembayaran: parseAngkaServer(pokokBayarRaw ?? ''),
      denda: parseAngkaServer(dendaRaw ?? ''),
      totalPenerimaan: parseAngkaServer(totalRaw ?? ''),
    );

    return summary.isNotEmpty ? summary : null;
  }

  /// Ambil tabel hasil dari HTML respons server V-Tax.
  /// Mendukung tabel multi-row header, tombol ekspor di atas tabel,
  /// pemisahan table header vs data, dan normalisasi panjang sel per baris
  /// agar DataTable Flutter tidak pernah crash karena mismatch sel.
  static MonitoringTableResult parseGenericTable(String html) {
    final document = html_parser.parse(html);
    final summary = parseSummaryTotals(html);
    final tables = document.querySelectorAll('table');
    if (tables.isEmpty) {
      final text = document.body?.text.trim();
      return MonitoringTableResult(
        errorMessage: (text == null || text.isEmpty) ? 'Tidak ada data.' : text,
        summary: summary,
      );
    }

    // Cari tabel utama yang memiliki sel terbanyak
    tables.sort(
      (a, b) => b
          .querySelectorAll('td, th')
          .length
          .compareTo(a.querySelectorAll('td, th').length),
    );
    final table = tables.first;
    final trs = table.querySelectorAll('tr');
    if (trs.isEmpty) {
      return MonitoringTableResult(errorMessage: 'Tidak ada data.', summary: summary);
    }

    // 1. Cari baris header: prioritaskan <tr> yang memiliki elemen <th>
    dom.Element? headerTr;
    final thRows = trs.where((tr) => tr.querySelectorAll('th').isNotEmpty).toList();
    if (thRows.isNotEmpty) {
      headerTr = thRows.reduce(
        (a, b) =>
            a.querySelectorAll('th').length >= b.querySelectorAll('th').length ? a : b,
      );
    }

    // 2. Kumpulkan calon baris data (kecualikan baris header)
    final candidateRows = <List<String>>[];
    for (final tr in trs) {
      if (tr == headerTr) continue;
      final cells = tr
          .querySelectorAll('td')
          .map((c) => c.text.trim())
          .toList();
      if (cells.isNotEmpty) {
        candidateRows.add(cells);
      }
    }

    // Hitung jumlah kolom data terbanyak (maxCols) dari baris kandidat
    var maxCols = 0;
    for (final r in candidateRows) {
      if (r.length > maxCols) maxCols = r.length;
    }

    List<String> headers = [];
    if (headerTr != null) {
      headers = headerTr
          .querySelectorAll('th, td')
          .map((c) => c.text.trim())
          .toList();
    }

    // Jika tidak ada baris <th> atau baris <th> hanya berisi 1 sel sedangkan data multi-kolom
    if (headers.isEmpty || (maxCols > 1 && headers.length <= 1)) {
      if (candidateRows.isNotEmpty && candidateRows.first.length == maxCols) {
        headers = candidateRows.removeAt(0);
      } else if (maxCols == 5) {
        headers = [
          'No',
          'Desa / Kelurahan',
          'Pagu / Ketetapan',
          'Realisasi',
          '% Realisasi',
        ];
      } else if (maxCols > 0) {
        headers = List.generate(
          maxCols,
          (i) => i == 0 ? 'No' : 'Kolom ${i + 1}',
        );
      }
    }

    // Jika maxCols lebih banyak daripada header yang ada, lengkapi header
    if (maxCols > headers.length) {
      for (var i = headers.length; i < maxCols; i++) {
        headers.add('Kolom ${i + 1}');
      }
    }

    // Bersihkan dan normalisasi panjang sel setiap baris data
    final normalizedRows = <List<String>>[];
    for (final r in candidateRows) {
      // Abaikan baris tombol/judul yang hanya 1 sel jika tabel adalah multi-kolom
      if (maxCols > 1 && r.length <= 1) {
        continue;
      }
      if (headers.isNotEmpty) {
        if (r.length < headers.length) {
          normalizedRows.add([...r, ...List.filled(headers.length - r.length, '')]);
        } else if (r.length > headers.length) {
          normalizedRows.add(r.sublist(0, headers.length));
        } else {
          normalizedRows.add(r);
        }
      } else {
        normalizedRows.add(r);
      }
    }

    if (normalizedRows.isEmpty) {
      return MonitoringTableResult(errorMessage: 'Tidak ada data.', summary: summary);
    }
    return MonitoringTableResult(headers: headers, rows: normalizedRows, summary: summary);
  }

  /// Parsing tabel antrean unduhan berkas Excel dari server V-Tax.
  static MonitoringExcelQueueResult parseExcelQueueTable(String html) {
    if (html.isEmpty) {
      return const MonitoringExcelQueueResult(errorMessage: 'Tidak ada data antrean.');
    }
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');
    if (tables.isEmpty) {
      final text = document.body?.text.trim();
      return MonitoringExcelQueueResult(
        errorMessage: (text == null || text.isEmpty) ? 'Tidak ada data antrean.' : text,
      );
    }

    var queueTable = tables.firstWhere(
      (t) {
        final text = t.text.toLowerCase();
        return text.contains('tanggal') && (text.contains('download') || text.contains('filter'));
      },
      orElse: () => tables.first,
    );

    final trs = queueTable.querySelectorAll('tr');
    if (trs.isEmpty) {
      return const MonitoringExcelQueueResult(errorMessage: 'Tabel antrean kosong.');
    }

    final items = <MonitoringExcelQueueItem>[];
    String? paginationText;

    for (final tr in trs) {
      final tds = tr.querySelectorAll('td');
      if (tds.isEmpty) continue;

      if (tds.length < 5) {
        final rowText = tds.map((c) => c.text.trim()).join(' ').trim();
        if (rowText.contains('dari') || RegExp(r'\d+\s*-\s*\d+').hasMatch(rowText)) {
          paginationText = rowText;
        }
        continue;
      }

      final no = tds[0].text.trim();
      final tanggal = tds[1].text.trim();

      final lis = tds[2].querySelectorAll('li');
      final filterSummary = lis.isNotEmpty
          ? lis.map((li) => li.text.trim()).where((s) => s.isNotEmpty).join(' • ')
          : tds[2].text.trim().replaceAll(RegExp(r'\s+'), ' ');

      final statusHtml = tds[3].innerHtml;
      final statusText = tds[3].text.trim().toLowerCase();
      final isProcessing = statusText.contains('process') ||
          statusText.contains('loading') ||
          statusHtml.contains('Processing') ||
          (!statusHtml.contains('accept.png') && !tds[4].innerHtml.contains('download'));

      final dlAnchor = tds[4].querySelector('a');
      final downloadUrl = dlAnchor?.attributes['href']?.trim();
      String? fileName;
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        final match = RegExp(r'file=([^&"\s]+)').firstMatch(downloadUrl);
        fileName = match?.group(1);
      }

      String? hapusId;
      final hapusAnchor = tds.length > 5 ? tds[5].querySelector('a') : null;
      final hapusOnclick =
          hapusAnchor?.attributes['onclick'] ??
          (tds.length > 5 ? tds[5].innerHtml : '');
      final hapusMatch = RegExp(
        r"""hapus\s*\(\s*['"]([a-zA-Z0-9_\-]+)['"]\s*\)""",
      ).firstMatch(hapusOnclick);
      hapusId = hapusMatch?.group(1);

      items.add(
        MonitoringExcelQueueItem(
          no: no,
          tanggal: tanggal,
          filterSummary: filterSummary,
          isProcessing: isProcessing,
          downloadUrl: downloadUrl,
          fileName: fileName,
          hapusId: hapusId,
        ),
      );
    }

    if (items.isEmpty && paginationText == null) {
      final msg = queueTable.text.trim();
      return MonitoringExcelQueueResult(
        errorMessage: msg.isNotEmpty ? msg : 'Belum ada berkas ekspor dalam antrean.',
      );
    }

    return MonitoringExcelQueueResult(
      items: items,
      paginationText: paginationText,
    );
  }

  static List<KolektifKelurahan> parseKolektifKelurahanOptions(String html) {
    final document = html_parser.parse(html);
    final options = <KolektifKelurahan>[];
    for (final selector in [
      'select#data-kelurahan-group-2',
      'select#data-kelurahan',
    ]) {
      for (final option in document.querySelectorAll('$selector option')) {
        final code = option.attributes['value']?.trim() ?? '';
        if (code.isEmpty) continue;
        if (options.any((o) => o.code == code)) continue;
        options.add(KolektifKelurahan(code: code, name: option.text.trim()));
      }
      if (options.isNotEmpty) break;
    }
    return options;
  }

  /// Parsing pilihan Desa/Kelurahan dari tag <select id="kelurahan-..."> di halaman Monitoring Wilayah.
  static List<KolektifKelurahan> parseMonitoringKelurahanOptions(String html) {
    final document = html_parser.parse(html);
    final options = <KolektifKelurahan>[];
    for (final select in document.querySelectorAll('select[id*="kelurahan"]')) {
      for (final option in select.querySelectorAll('option')) {
        final code = option.attributes['value']?.trim() ?? '';
        final text = option.text.trim();
        if (code.isEmpty || code == 'null' || text.isEmpty) continue;
        if (options.any((o) => o.code == code)) continue;
        options.add(KolektifKelurahan(code: code, name: text));
      }
    }
    return options;
  }

  static String parseKecamatanNameFromJson(String body, String code) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['msg'] is! List) return '';
      for (final item in decoded['msg'] as List) {
        if (item is Map && '${item['id']}'.trim() == code) {
          return rapikanNamaWilayah('${item['name']}');
        }
      }
    } on FormatException {
      return '';
    }
    return '';
  }

  static KolektifMemberListResult parseKolektifMemberJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['data'] is! List) {
        return const KolektifMemberListResult(
          errorMessage: 'Format respons daftar anggota tidak dikenali.',
        );
      }
      final members = (decoded['data'] as List).whereType<List>().map((row) {
        String cell(int i) => i < row.length ? stripHtml('${row[i]}') : '';
        final checkbox = row.isNotEmpty
            ? html_parser
                  .parseFragment('${row[0]}')
                  .querySelector('input[value]')
            : null;
        return KolektifMember(
          nop: checkbox?.attributes['value']?.trim().isNotEmpty == true
              ? checkbox!.attributes['value']!.trim()
              : cell(1),
          tahunPajak: checkbox?.attributes['year']?.trim().isNotEmpty == true
              ? checkbox!.attributes['year']!.trim()
              : cell(2),
          jatuhTempo: cell(3),
          namaWp: cell(4),
          kecamatan: cell(5),
          kelurahan: cell(6),
          pokok: cell(7),
          denda: cell(8),
          total: cell(9),
        );
      }).toList();
      if (members.isEmpty) {
        return const KolektifMemberListResult(
          errorMessage: 'Grup ini belum punya anggota.',
        );
      }
      return KolektifMemberListResult(members: members);
    } on FormatException {
      return const KolektifMemberListResult(
        errorMessage:
            'Gagal membaca daftar anggota — format respons tidak sesuai dugaan.',
      );
    }
  }

  static KolektifActionResult parseKolektifActionJson(String body) {
    final trimmed = body.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final message = decoded['message']?.toString();
        return KolektifActionResult(
          success: decoded['success'] == true,
          message: (message == null || message.isEmpty) ? null : message,
          rawBody: trimmed,
        );
      }
    } on FormatException {
      // Bukan JSON — jatuh ke penanganan di bawah.
    }
    final cuplikan = trimmed.length > 300
        ? '${trimmed.substring(0, 300)}…'
        : trimmed;
    return KolektifActionResult(
      success: false,
      message:
          'Server menjawab dengan format yang tidak dikenali, jadi hasilnya belum pasti. '
          'Periksa dulu daftar grup sebelum mencoba lagi.\n\nJawaban server:\n$cuplikan',
      rawBody: trimmed,
      responsDikenali: false,
    );
  }

  static KolektifListResult parseKolektifGroupsJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['data'] is! List) {
        return const KolektifListResult(
          errorMessage: 'Format respons daftar grup tidak dikenali.',
        );
      }
      final rows = (decoded['data'] as List).whereType<List>();
      final groups = rows.map((row) {
        String cell(int i) => i < row.length ? stripHtml('${row[i]}') : '';
        final aksi = _parseKolektifAksiCell(row.isNotEmpty ? '${row[0]}' : '');
        final kel = _parseKolektifKelurahanCell(
          row.length > 8 ? '${row[8]}' : '',
        );
        return KolektifGroup(
          id: aksi.id,
          statusCode: aksi.statusCode,
          canDelete: aksi.canDelete,
          canEdit: aksi.canEdit,
          canPrintSurat: aksi.canPrintSurat,
          kelurahanCode: kel.kode,
          namaGroup: cell(1),
          namaKolektor: cell(2),
          hpKolektor: cell(3),
          anggota: cell(4),
          kodeBayar: cell(5),
          status: cell(6),
          kecamatan: cell(7),
          kelurahan: kel.nama,
          keterangan: cell(9),
          tanggalKadaluarsa: cell(10),
        );
      }).toList();
      if (groups.isEmpty) {
        return const KolektifListResult(errorMessage: 'Tidak ada data.');
      }
      return KolektifListResult(groups: groups);
    } on FormatException {
      return const KolektifListResult(
        errorMessage:
            'Gagal membaca daftar grup — format respons tidak sesuai dugaan.',
      );
    }
  }

  static ({
    String id,
    String statusCode,
    bool canDelete,
    bool canEdit,
    bool canPrintSurat,
  })
  _parseKolektifAksiCell(String cellHtml) {
    if (cellHtml.isEmpty) {
      return (
        id: '',
        statusCode: '',
        canDelete: false,
        canEdit: false,
        canPrintSurat: false,
      );
    }
    final fragment = html_parser.parseFragment(cellHtml);
    final id =
        (fragment.querySelector('[group-id]')?.attributes['group-id'] ??
                fragment.querySelector('[group_id]')?.attributes['group_id'] ??
                '')
            .trim();
    final statusCode =
        fragment.querySelector('[status]')?.attributes['status'] ?? '';
    final punyaId = id.isNotEmpty;
    return (
      id: id,
      statusCode: statusCode.trim(),
      canDelete: punyaId && fragment.querySelector('.btn-delete-group') != null,
      canEdit: punyaId && fragment.querySelector('.btn-edit-group') != null,
      canPrintSurat:
          punyaId && fragment.querySelector('.btn-cetak-info-group') != null,
    );
  }

  static ({String nama, String kode}) _parseKolektifKelurahanCell(
    String cellHtml,
  ) {
    if (cellHtml.isEmpty) return (nama: '', kode: '');
    final fragment = html_parser.parseFragment(cellHtml);
    final nama = fragment.querySelector('.nm-kel')?.text.trim();
    final kode = fragment.querySelector('.kd-kel')?.text.trim();
    if (nama != null || kode != null) {
      return (nama: nama ?? '', kode: kode ?? '');
    }
    return (nama: stripHtml(cellHtml), kode: '');
  }

  static String stripHtml(String value) =>
      (html_parser.parseFragment(value).text ?? value).trim();
}
