import 'package:shared_preferences/shared_preferences.dart';

import 'dusun_data.dart';

/// Menyimpan dusun mana yang jadi wilayah kerja perangkat ini. Blok yang
/// termasuk wilayah kerja diturunkan dari [Dusun.bloks] milik dusun terpilih
/// (lihat dusun_data.dart) — user cukup pilih satu dusun, tidak perlu
/// centang blok satu per satu lagi.
///
/// Kalau belum ada dusun dipilih, hasil "Sudah Bayar" tidak dicatat ke Buku
/// Catatan Blok sama sekali — pengecekan & pembayaran tetap jalan seperti
/// biasa, cuma tidak ada riwayat yang tersimpan.
class WilayahKerjaStore {
  WilayahKerjaStore._();
  static final instance = WilayahKerjaStore._();

  static const _dusunKey = 'wilayah_kerja_dusun';
  static const _askedKey = 'wilayah_kerja_asked';

  int? _selectedDusun;
  bool _asked = false;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _selectedDusun = prefs.getInt(_dusunKey);
    _asked = prefs.getBool(_askedKey) ?? false;
    _loaded = true;
  }

  Future<int?> selectedDusun() async {
    await _ensureLoaded();
    return _selectedDusun;
  }

  /// Sudah pernah ditanya wilayah kerjanya saat aplikasi pertama kali
  /// dijalankan (baik memilih dusun maupun melewati) — supaya dialog awal
  /// tidak muncul berulang-ulang tiap aplikasi dibuka.
  Future<bool> hasBeenAsked() async {
    await _ensureLoaded();
    return _asked;
  }

  Future<void> markAsked() async {
    await _ensureLoaded();
    _asked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
  }

  Future<void> setSelectedDusun(int? dusunNumber) async {
    await _ensureLoaded();
    _selectedDusun = dusunNumber;
    final prefs = await SharedPreferences.getInstance();
    if (dusunNumber == null) {
      await prefs.remove(_dusunKey);
    } else {
      await prefs.setInt(_dusunKey, dusunNumber);
    }
  }

  /// Blok-blok yang termasuk wilayah kerja sesuai dusun terpilih. Kosong
  /// kalau belum ada dusun dipilih.
  Future<Set<String>> whitelistedBloks() async {
    final dusunNumber = await selectedDusun();
    if (dusunNumber == null) return {};
    return dusunByNumber(dusunNumber)?.bloks.toSet() ?? {};
  }
}
