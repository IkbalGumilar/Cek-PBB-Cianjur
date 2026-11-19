import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'base_preferences_store.dart';

/// Checkpoint progres Cek Massal PBB agar dapat dijeda dan dilanjutkan kapan saja
/// dalam batas waktu 24 jam. Jika lebih dari 24 jam, pengecekan otomatis dimulai dari awal.
class BatchCheckCheckpoint {
  final String scopeKey;
  final int currentIndex;
  final int totalCount;
  final int savedAtMs;

  const BatchCheckCheckpoint({
    required this.scopeKey,
    required this.currentIndex,
    required this.totalCount,
    required this.savedAtMs,
  });

  DateTime get savedAt =>
      DateTime.fromMillisecondsSinceEpoch(savedAtMs, isUtc: true);

  bool isValidForResume({DateTime? now}) =>
      ProgressCheckpointStore.isWithinResumeWindow(savedAtMs, now: now);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'scopeKey': scopeKey,
    'currentIndex': currentIndex,
    'totalCount': totalCount,
    'savedAtMs': savedAtMs,
  };

  factory BatchCheckCheckpoint.fromJson(Map<String, dynamic> json) {
    return BatchCheckCheckpoint(
      scopeKey: (json['scopeKey'] as String?) ?? '',
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Checkpoint progres Sinkronisasi DHKP Portal Staf (berdasarkan halaman BB/SB)
/// dengan batas kedaluwarsa 24 jam.
class StaffSyncCheckpoint {
  final String scopeKey;
  final int nextPageBb;
  final int nextPageSb;
  final bool bbCompleted;
  final int savedAtMs;

  const StaffSyncCheckpoint({
    required this.scopeKey,
    required this.nextPageBb,
    required this.nextPageSb,
    required this.bbCompleted,
    required this.savedAtMs,
  });

  DateTime get savedAt =>
      DateTime.fromMillisecondsSinceEpoch(savedAtMs, isUtc: true);

  bool isValidForResume({DateTime? now}) =>
      ProgressCheckpointStore.isWithinResumeWindow(savedAtMs, now: now);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'scopeKey': scopeKey,
    'nextPageBb': nextPageBb,
    'nextPageSb': nextPageSb,
    'bbCompleted': bbCompleted,
    'savedAtMs': savedAtMs,
  };

  factory StaffSyncCheckpoint.fromJson(Map<String, dynamic> json) {
    return StaffSyncCheckpoint(
      scopeKey: (json['scopeKey'] as String?) ?? '',
      nextPageBb: (json['nextPageBb'] as num?)?.toInt() ?? 1,
      nextPageSb: (json['nextPageSb'] as num?)?.toInt() ?? 1,
      bbCompleted: (json['bbCompleted'] as bool?) ?? false,
      savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Penyimpanan persisten checkpoint progres untuk Cek Massal & Sinkronisasi DHKP.
///
/// Aturan batas waktu (24 jam):
/// - Jika terjeda `< 24 jam` $\rightarrow$ lanjutkan dari progres terakhir yang tersimpan.
/// - Jika terjeda `>= 24 jam` (lebih dari 1 hari) $\rightarrow$ checkpoint dianggap
///   kedaluwarsa, dihapus, dan proses dimulai dari awal.
class ProgressCheckpointStore extends BasePreferencesStore {
  ProgressCheckpointStore._();
  static final instance = ProgressCheckpointStore._();

  static const Duration maxResumeAge = Duration(hours: 24);
  static const String _batchCheckpointKey = 'batch_check_progress_checkpoint_v1';
  static const String _staffSyncCheckpointKey =
      'staff_dhkp_sync_progress_checkpoint_v1';

  /// Memeriksa apakah timestamp [savedAtMs] masih berada dalam rentang `< 24 jam`.
  static bool isWithinResumeWindow(int savedAtMs, {DateTime? now}) {
    if (savedAtMs <= 0) return false;
    final reference = (now ?? DateTime.now()).toUtc();
    final saved = DateTime.fromMillisecondsSinceEpoch(savedAtMs, isUtc: true);
    final elapsed = reference.difference(saved);
    if (elapsed.isNegative) return true;
    return elapsed < maxResumeAge;
  }

  /// Menyusun kunci cakupan deterministik untuk Cek Massal.
  static String buildBatchScopeKey({
    required String tahun,
    required String? scopeTitle,
    required String? blokNumber,
    required int totalCount,
    required String firstNop,
    required String lastNop,
  }) {
    final label = (scopeTitle != null && scopeTitle.trim().isNotEmpty)
        ? scopeTitle.trim()
        : (blokNumber ?? 'custom');
    return '$tahun|$label|$totalCount|$firstNop|$lastNop';
  }

  /// Menyusun kunci cakupan deterministik untuk Sinkronisasi DHKP Portal Staf.
  static String buildStaffSyncScopeKey({
    required String tahun,
    required String kecamatan,
    required String kelurahan,
    required String modeName,
    required List<String> bloks,
  }) {
    final sortedBloks = List<String>.from(bloks)..sort();
    return '$tahun|$kecamatan|$kelurahan|$modeName|${sortedBloks.join(',')}';
  }

  Future<void> saveBatchCheckpoint(BatchCheckCheckpoint checkpoint) async {
    await setString(_batchCheckpointKey, jsonEncode(checkpoint.toJson()));
  }

  /// Memuat checkpoint Cek Massal jika cocok dengan [scopeKey] dan masih `< 24 jam`.
  /// Jika kedaluwarsa (`>= 24 jam`), otomatis menghapus checkpoint lama dan mengembalikan `null`.
  Future<BatchCheckCheckpoint?> loadValidBatchCheckpoint(
    String scopeKey, {
    DateTime? now,
  }) async {
    final raw = await getString(_batchCheckpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cp = BatchCheckCheckpoint.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (!cp.isValidForResume(now: now)) {
        await clearBatchCheckpoint();
        return null;
      }
      if (cp.scopeKey != scopeKey || cp.currentIndex <= 0) {
        return null;
      }
      return cp;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearBatchCheckpoint() async {
    await remove(_batchCheckpointKey);
  }

  Future<void> saveStaffSyncCheckpoint(StaffSyncCheckpoint checkpoint) async {
    await setString(_staffSyncCheckpointKey, jsonEncode(checkpoint.toJson()));
  }

  /// Memuat checkpoint Sinkronisasi DHKP jika cocok dengan [scopeKey] dan masih `< 24 jam`.
  /// Jika kedaluwarsa (`>= 24 jam`), otomatis menghapus checkpoint lama dan mengembalikan `null`.
  Future<StaffSyncCheckpoint?> loadValidStaffSyncCheckpoint(
    String scopeKey, {
    DateTime? now,
  }) async {
    final raw = await getString(_staffSyncCheckpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cp = StaffSyncCheckpoint.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (!cp.isValidForResume(now: now)) {
        await clearStaffSyncCheckpoint();
        return null;
      }
      if (cp.scopeKey != scopeKey) {
        return null;
      }
      if (!cp.bbCompleted && cp.nextPageBb <= 1 && cp.nextPageSb <= 1) {
        return null;
      }
      return cp;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearStaffSyncCheckpoint() async {
    await remove(_staffSyncCheckpointKey);
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await clearBatchCheckpoint();
    await clearStaffSyncCheckpoint();
    resetPrefsForTesting();
  }
}
