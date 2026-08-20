import 'package:shared_preferences/shared_preferences.dart';

/// Jumlah blok yang tersedia untuk desa ini saat ini (blok 1 s.d. 41) — lihat
/// juga [nop_helper.dart]. Perlu diperbarui kalau suatu saat aplikasi ini
/// dipakai desa lain dengan jumlah blok berbeda.
const totalBlokCount = 41;

/// Menyimpan blok mana saja yang termasuk wilayah kerja user perangkat ini —
/// dipakai untuk menyaring "Buku Catatan Blok" supaya hanya menampilkan blok
/// yang relevan, karena tidak semua user bertugas di blok yang sama.
///
/// Setiap blok punya dua status: "sudah diputuskan" (decided) dan, kalau
/// sudah diputuskan, "termasuk wilayah kerja" (whitelisted) atau tidak. Blok
/// yang belum diputuskan akan ditanyakan lewat dialog konfirmasi saat pertama
/// kali user mengecek NOP di blok tersebut.
class BlokWhitelistStore {
  BlokWhitelistStore._();
  static final instance = BlokWhitelistStore._();

  static const _whitelistKey = 'blok_whitelist';
  static const _decidedKey = 'blok_decided';

  Set<String>? _whitelist;
  Set<String>? _decided;

  Future<void> _ensureLoaded() async {
    if (_whitelist != null && _decided != null) return;
    final prefs = await SharedPreferences.getInstance();
    _whitelist = (prefs.getStringList(_whitelistKey) ?? []).toSet();
    _decided = (prefs.getStringList(_decidedKey) ?? []).toSet();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_whitelistKey, _whitelist!.toList());
    await prefs.setStringList(_decidedKey, _decided!.toList());
  }

  /// [blok] diformat 3 digit, mis. "028".
  Future<bool> isDecided(String blok) async {
    await _ensureLoaded();
    return _decided!.contains(blok);
  }

  /// Tetapkan status satu blok — dipakai baik oleh dialog konfirmasi otomatis
  /// maupun oleh daftar centang manual di Setelan.
  Future<void> decide(String blok, bool included) async {
    await _ensureLoaded();
    _decided!.add(blok);
    if (included) {
      _whitelist!.add(blok);
    } else {
      _whitelist!.remove(blok);
    }
    await _persist();
  }

  Future<Set<String>> loadWhitelist() async {
    await _ensureLoaded();
    return Set.from(_whitelist!);
  }
}
