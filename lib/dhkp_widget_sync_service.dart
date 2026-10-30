import 'dart:convert';
import 'package:flutter/services.dart';
import 'blok_data_store.dart';
import 'blok_record.dart';
import 'dusun_data.dart';

/// Layanan untuk mensinkronisasi data ringkasan DHKP ke Home Screen Widget Android.
///
/// Mengirimkan data agregat (Realisasi per Dusun, Lunas vs Piutang,
/// Porsi Kontribusi Dusun, dan Tren Bulanan Jan–Des) ke SharedPreferences &
/// memicu pembaruan canvas grafik pada RemoteViews widget secara langsung.
class DhkpWidgetSyncService {
  static const MethodChannel _channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/widget');

  static DateTime? _parsePaymentDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty || s == '2026') return null;
    try {
      return DateTime.parse(s);
    } catch (_) {}
    final dmy = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(s);
    if (dmy != null) {
      final d = int.tryParse(dmy.group(1)!);
      final m = int.tryParse(dmy.group(2)!);
      final y = int.tryParse(dmy.group(3)!);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  /// Memuat catatan dari basis data lokal dan mengirimkan ringkasan ke Home Widget.
  static Future<void> syncFromDatabase() async {
    try {
      final records = await BlokDataStore.instance.loadAll();
      if (records.isNotEmpty) {
        await syncFromRecords(records);
      }
    } catch (_) {}
  }

  /// Menghitung ringkasan data DHKP dan meneruskannya ke Android AppWidgetProvider.
  static Future<void> syncFromRecords(List<BlokRecord> records) async {
    if (records.isEmpty) return;

    try {
      await DusunData.instance.init();
      final dusuns = DusunData.instance.currentDusuns;

      int totalNominal = 0;
      int lunasNominal = 0;
      int totalNop = records.length;
      int lunasNop = 0;

      // Inisialisasi statistik per Dusun
      final dusunStats = <int, Map<String, dynamic>>{};
      for (final d in dusuns) {
        dusunStats[d.number] = {
          'name': d.label,
          'targetRp': 0,
          'lunasRp': 0,
          'lunasNop': 0,
          'totalNop': 0,
        };
      }

      // Inisialisasi tren bulanan 12 bulan
      final monthNominals = List<int>.filled(12, 0);
      final monthCounts = List<int>.filled(12, 0);
      const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];

      for (final r in records) {
        final val = r.jumlahPbbValue;
        totalNominal += val;

        if (r.isPaid) {
          lunasNominal += val;
          lunasNop++;

          if (r.tanggalBayar.isNotEmpty) {
            final dt = _parsePaymentDate(r.tanggalBayar);
            if (dt != null && dt.month >= 1 && dt.month <= 12) {
              monthNominals[dt.month - 1] += val;
              monthCounts[dt.month - 1]++;
            }
          }
        }

        // Cari dusun yang menaungi blok catatan ini
        final d = DusunData.instance.byBlok(r.blok);
        final dNum = d?.number ?? 1;
        final dStat = dusunStats.putIfAbsent(dNum, () => {
          'name': d?.label ?? 'Dusun $dNum',
          'targetRp': 0,
          'lunasRp': 0,
          'lunasNop': 0,
          'totalNop': 0,
        });

        dStat['targetRp'] = (dStat['targetRp'] as int) + val;
        dStat['totalNop'] = (dStat['totalNop'] as int) + 1;
        if (r.isPaid) {
          dStat['lunasRp'] = (dStat['lunasRp'] as int) + val;
          dStat['lunasNop'] = (dStat['lunasNop'] as int) + 1;
        }
      }

      final lunasPct = totalNominal > 0 ? (lunasNominal / totalNominal * 100.0) : 0.0;
      final belumBayarNominal = totalNominal - lunasNominal;
      final belumBayarNop = totalNop - lunasNop;

      final dusunListJson = <Map<String, dynamic>>[];
      final sortedDusunKeys = dusunStats.keys.toList()..sort();
      for (final k in sortedDusunKeys) {
        final m = dusunStats[k]!;
        final targetRp = m['targetRp'] as int;
        final lunasRp = m['lunasRp'] as int;
        final pct = targetRp > 0 ? (lunasRp / targetRp * 100.0) : 0.0;
        dusunListJson.add({
          'name': m['name'],
          'targetRp': targetRp,
          'lunasRp': lunasRp,
          'belumBayarRp': targetRp - lunasRp,
          'lunasPct': pct,
          'lunasNop': m['lunasNop'],
          'totalNop': m['totalNop'],
        });
      }

      final monthsJson = <Map<String, dynamic>>[];
      for (int i = 0; i < 12; i++) {
        monthsJson.add({
          'month': monthNames[i],
          'nominal': monthNominals[i],
          'count': monthCounts[i],
        });
      }

      final payload = {
        'totalNominal': totalNominal,
        'lunasNominal': lunasNominal,
        'belumBayarNominal': belumBayarNominal,
        'totalNop': totalNop,
        'lunasNop': lunasNop,
        'belumBayarNop': belumBayarNop,
        'lunasPct': lunasPct,
        'dusuns': dusunListJson,
        'months': monthsJson,
      };

      final jsonStr = jsonEncode(payload);
      await _channel.invokeMethod('updateWidgetData', {'data': jsonStr});
    } catch (_) {}
  }

  /// Memicu refresh penggambaran ulang pada seluruh instance widget di launcher.
  static Future<void> refreshWidget() async {
    try {
      await _channel.invokeMethod('refreshWidget');
    } catch (_) {}
  }
}
