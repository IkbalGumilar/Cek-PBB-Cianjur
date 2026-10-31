import 'dart:convert';

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

  /// Ambil tabel terbesar (paling banyak sel `<td>`) dari HTML respons —
  /// kolomnya dibaca apa adanya dari header tabel, tidak di-hardcode.
  static MonitoringTableResult parseGenericTable(String html) {
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');
    if (tables.isEmpty) {
      final text = document.body?.text.trim();
      return MonitoringTableResult(
        errorMessage: (text == null || text.isEmpty) ? 'Tidak ada data.' : text,
      );
    }
    tables.sort(
      (a, b) => b
          .querySelectorAll('td')
          .length
          .compareTo(a.querySelectorAll('td').length),
    );
    final table = tables.first;
    final trs = table.querySelectorAll('tr');
    if (trs.isEmpty) {
      return const MonitoringTableResult(errorMessage: 'Tidak ada data.');
    }

    final headers = trs.first
        .querySelectorAll('th, td')
        .map((c) => c.text.trim())
        .toList();
    final rows = trs
        .skip(1)
        .map(
          (tr) => tr.querySelectorAll('td').map((c) => c.text.trim()).toList(),
        )
        .where((r) => r.isNotEmpty)
        .toList();

    if (rows.isEmpty) {
      return const MonitoringTableResult(errorMessage: 'Tidak ada data.');
    }
    return MonitoringTableResult(headers: headers, rows: rows);
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
