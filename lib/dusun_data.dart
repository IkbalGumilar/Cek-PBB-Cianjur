import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Model wilayah kerja dusun dinamis berbasis manifest berkas `.dkhp`.
///
/// Setiap dusun memiliki nomor, nama, dan daftar kode blok (3 digit, mis. "017")
/// yang menjadi wilayah tanggung jawabnya.
class Dusun {
  final int number;
  final String name;
  final List<String> bloks;

  const Dusun({
    required this.number,
    String? name,
    required this.bloks,
  }) : name = name ?? 'Dusun $number';

  String get label => name.isNotEmpty ? name : 'Dusun $number';

  Map<String, dynamic> toJson() => {
    'number': number,
    'name': name,
    'bloks': bloks,
  };

  factory Dusun.fromJson(Map<String, dynamic> json) {
    return Dusun(
      number: (json['number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String?,
      bloks:
          (json['bloks'] as List?)
              ?.map((e) => e.toString().padLeft(3, '0'))
              .toList() ??
          [],
    );
  }
}

/// Batasan cakupan wilayah / peran (Pembatas Wilayah) yang dimuat dari manifest `.dkhp`.
///
/// - `role == 'desa'`: Akses tingkat desa penuh (seluruh dusun dan seluruh blok).
/// - `role == 'dusun'`: Pembatas aktif khusus kepala dusun / petugas wilayah dusun tertentu.
///   Aplikasi mengunci akses sehingga pengguna hanya dapat melihat dan mengelola blok di dusunnya saja.
class DusunScope {
  final String role; // 'desa' atau 'dusun'
  final int? dusunNumber;
  final String? dusunName;
  final List<String> allowedBloks;

  const DusunScope({
    this.role = 'desa',
    this.dusunNumber,
    this.dusunName,
    this.allowedBloks = const [],
  });

  bool get isDusunScope => role == 'dusun' && dusunNumber != null;

  Map<String, dynamic> toJson() => {
    'role': role,
    if (dusunNumber != null) 'dusunNumber': dusunNumber,
    if (dusunName != null) 'dusunName': dusunName,
    if (allowedBloks.isNotEmpty) 'allowedBloks': allowedBloks,
  };

  factory DusunScope.fromJson(Map<String, dynamic> json) {
    return DusunScope(
      role: json['role']?.toString() ?? 'desa',
      dusunNumber: (json['dusunNumber'] as num?)?.toInt(),
      dusunName: json['dusunName']?.toString(),
      allowedBloks:
          (json['allowedBloks'] as List?)
              ?.map((e) => e.toString().padLeft(3, '0'))
              .toList() ??
          const [],
    );
  }
}

/// Pengelola data wilayah dan pembatas (boundary) dusun dinamis.
///
/// Tidak lagi menggunakan daftar hardcode, melainkan membaca konfigurasi
/// manifest dari paket `.dkhp` yang diimpor atau persisted di SharedPreferences.
class DusunData {
  DusunData._();
  static final DusunData instance = DusunData._();

  static const _prefDusunsKey = 'dusun_data_list_manifest';
  static const _prefScopeKey = 'dusun_data_scope_manifest';

  /// Cadangan bawaan bila belum ada manifest .dkhp yang pernah dimuat.
  static const List<Dusun> defaultBobojongDusuns = [
    Dusun(
      number: 1,
      bloks: [
        '001',
        '002',
        '003',
        '004',
        '011',
        '012',
        '013',
        '014',
        '015',
        '016',
        '027',
      ],
    ),
    Dusun(
      number: 2,
      bloks: ['005', '006', '007', '008', '009', '010', '019', '020', '021'],
    ),
    Dusun(
      number: 3,
      bloks: [
        '017',
        '018',
        '022',
        '023',
        '024',
        '025',
        '026',
        '028',
        '029',
        '030',
        '031',
        '041',
      ],
    ),
    Dusun(number: 4, bloks: ['032', '033', '035', '036']),
    Dusun(number: 5, bloks: ['034', '037', '038', '039', '040']),
  ];

  List<Dusun> _allDusuns = List.of(defaultBobojongDusuns);
  DusunScope _scope = const DusunScope(role: 'desa');
  bool _initialized = false;

  /// Inisialisasi data dusun dan pembatas dari SharedPreferences.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dusunsJson = prefs.getString(_prefDusunsKey);
      if (dusunsJson != null && dusunsJson.isNotEmpty) {
        final decoded = jsonDecode(dusunsJson);
        if (decoded is List) {
          final list =
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map((j) => Dusun.fromJson(j))
                  .where((d) => d.bloks.isNotEmpty)
                  .toList();
          if (list.isNotEmpty) {
            _allDusuns = list;
          }
        }
      }

      final scopeJson = prefs.getString(_prefScopeKey);
      if (scopeJson != null && scopeJson.isNotEmpty) {
        final decoded = jsonDecode(scopeJson);
        if (decoded is Map<String, dynamic>) {
          _scope = DusunScope.fromJson(decoded);
        }
      }
    } catch (_) {}
    _initialized = true;
  }

  /// Memperbarui daftar Dusun dari manifest paket .dkhp dan menyimpannya.
  Future<void> setDusuns(List<Dusun> dusuns) async {
    _allDusuns = List.of(dusuns);
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_allDusuns.map((d) => d.toJson()).toList());
      await prefs.setString(_prefDusunsKey, encoded);
    } catch (_) {}
  }

  /// Menetapkan pembatas wilayah (misalnya mengunci ke Dusun tertentu).
  Future<void> setScope(DusunScope scope) async {
    _scope = scope;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_scope.toJson());
      await prefs.setString(_prefScopeKey, encoded);
    } catch (_) {}
  }

  /// Menghapus pembatas wilayah (kembali ke cakupan seluruh desa).
  Future<void> clearScope() async {
    _scope = const DusunScope(role: 'desa');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefScopeKey);
    } catch (_) {}
  }

  /// Mengembalikan true bila aplikasi saat ini dibatasi (dikunci) ke Dusun tertentu.
  bool get isDusunLocked => _scope.isDusunScope;

  /// Nomor Dusun yang dikunci saat pembatas aktif.
  int? get lockedDusunNumber => isDusunLocked ? _scope.dusunNumber : null;

  /// Detail objek pembatas saat ini.
  DusunScope get scope => _scope;

  /// Daftar dusun aktif saat ini. Bila terkunci ke satu dusun, hanya mengembalikan dusun tersebut.
  List<Dusun> get currentDusuns {
    if (isDusunLocked && _scope.dusunNumber != null) {
      final locked = byNumber(_scope.dusunNumber!);
      if (locked != null) return [locked];
      if (_scope.allowedBloks.isNotEmpty) {
        return [
          Dusun(
            number: _scope.dusunNumber!,
            name: _scope.dusunName ?? 'Dusun ${_scope.dusunNumber}',
            bloks: _scope.allowedBloks,
          ),
        ];
      }
    }
    return List.unmodifiable(_allDusuns);
  }

  /// Seluruh daftar dusun yang diketahui tanpa memandang pembatas.
  List<Dusun> get allDusuns => List.unmodifiable(_allDusuns);

  /// Mencari dusun berdasarkan nomornya.
  Dusun? byNumber(int number) {
    for (final dusun in _allDusuns) {
      if (dusun.number == number) return dusun;
    }
    return null;
  }

  /// Mencari dusun mana yang menaungi kode blok tertentu.
  Dusun? byBlok(String blok) {
    final cleanBlok = blok.padLeft(3, '0');
    for (final dusun in _allDusuns) {
      if (dusun.bloks.contains(cleanBlok)) return dusun;
    }
    return null;
  }
}

/// Akses kompatibel mundur ke daftar dusun aktif.
List<Dusun> get dusunList => DusunData.instance.currentDusuns;

/// Akses kompatibel mundur untuk mencari dusun berdasarkan nomor.
Dusun? dusunByNumber(int number) => DusunData.instance.byNumber(number);
