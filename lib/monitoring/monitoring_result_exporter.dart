import 'dart:typed_data';

import '../base_table_exporter.dart';
import '../staff_portal_client.dart';

export '../base_table_exporter.dart' show AppExportFormat;

typedef MonitoringExportFormat = AppExportFormat;

/// Ekspor hasil tabel generik Monitoring Wilayah (headers+rows apa adanya
/// dari server, beda-beda tiap tab) ke CSV/Excel/PDF — mewarisi pustaka
/// & pola encoding bersama dari [BaseTableExporter].
class MonitoringResultExporter extends BaseTableExporter {
  static Future<Uint8List> build(
    MonitoringExportFormat format,
    MonitoringTableResult result,
    String title,
  ) {
    return BaseTableExporter.buildFormatted(
      format: format,
      title: title,
      headers: result.headers,
      rows: result.rows,
    );
  }

  /// [prefix] memisahkan berkas antar-modul yang sama-sama memakai pengekspor
  /// ini (mis. `monitoring_…` vs `anggota_…`), supaya berkas unduhan tidak
  /// tercampur di folder Dokumen.
  static String fileName(
    MonitoringExportFormat format,
    String title, {
    String prefix = 'monitoring',
  }) {
    return BaseTableExporter.formatFileName(
      prefix: prefix,
      identifier: title,
      format: format,
    );
  }
}
