import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Pelacak riwayat pengecekan massal per NOP untuk mencegah pengecekan berulang
/// yang membebani server Bapenda dalam 24 jam terakhir.
///
/// Siklus pengecekan direset otomatis setiap jam 02:00 pagi (seperti jadwal backup).
class BlokBatchCheckTracker {
  BlokBatchCheckTracker._();
  static final BlokBatchCheckTracker instance = BlokBatchCheckTracker._();

  static const _prefKey = 'blok_batch_check_tracker_timestamps_v1';

  Map<String, DateTime> _timestamps = {};
  bool _initialized = false;

  /// Waktu awal siklus harian saat ini (reset setiap jam 02:00 pagi).
  DateTime get currentCycleStart {
    final now = DateTime.now();
    final today2am = DateTime(now.year, now.month, now.day, 2, 0);
    if (now.isBefore(today2am)) {
      return today2am.subtract(const Duration(days: 1));
    }
    return today2am;
  }

  /// Waktu siklus reset berikutnya (jam 02:00 berikutnya).
  DateTime get nextCycleReset {
    final now = DateTime.now();
    final today2am = DateTime(now.year, now.month, now.day, 2, 0);
    if (now.isBefore(today2am)) {
      return today2am;
    }
    return today2am.add(const Duration(days: 1));
  }

  /// Format teks waktu reset berikutnya untuk tampilan pengguna.
  String get nextResetFormatted {
    final reset = nextCycleReset;
    final dayStr = reset.day == DateTime.now().day ? 'hari ini' : 'besok';
    final padMonth = reset.month.toString().padLeft(2, '0');
    final padDay = reset.day.toString().padLeft(2, '0');
    return '$dayStr jam 02:00 ($padDay/$padMonth)';
  }

  /// Inisialisasi data tracker dari SharedPreferences.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final cutoff = DateTime.now().subtract(const Duration(days: 3));
          final map = <String, DateTime>{};
          decoded.forEach((key, val) {
            final dt = DateTime.tryParse(val.toString());
            if (dt != null && dt.isAfter(cutoff)) {
              map[key] = dt;
            }
          });
          _timestamps = map;
        }
      }
    } catch (_) {}
    _initialized = true;
  }

  /// Memeriksa apakah NOP tertentu sudah dicek pada siklus hari ini (sejak jam 02:00 terakhir).
  bool isCheckedToday(String nop) {
    final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');
    final dt = _timestamps[cleanNop];
    if (dt == null) return false;
    return dt.isAfter(currentCycleStart);
  }

  /// Mendapatkan waktu terakhir NOP diperiksa (jika ada).
  DateTime? getLastChecked(String nop) {
    final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');
    return _timestamps[cleanNop];
  }

  /// Mencatat bahwa NOP baru saja diperiksa.
  Future<void> recordChecked(String nop) async {
    if (!_initialized) await init();
    final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');
    _timestamps[cleanNop] = DateTime.now();
    await _persist();
  }

  /// Mencatat beberapa NOP sekaligus.
  Future<void> recordAllChecked(Iterable<String> nops) async {
    if (!_initialized) await init();
    final now = DateTime.now();
    for (final nop in nops) {
      final cleanNop = nop.replaceAll(RegExp(r'[^0-9]'), '');
      _timestamps[cleanNop] = now;
    }
    await _persist();
  }

  /// Mengosongkan data riwayat (untuk pengujian / reset manual).
  Future<void> clearHistory() async {
    _timestamps.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      final cutoff = DateTime.now().subtract(const Duration(days: 3));
      _timestamps.forEach((key, dt) {
        if (dt.isAfter(cutoff)) {
          map[key] = dt.toIso8601String();
        }
      });
      await prefs.setString(_prefKey, jsonEncode(map));
    } catch (_) {}
  }
}
