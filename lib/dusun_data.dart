import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Model wilayah kerja dusun dinamis berbasis manifest berkas `.dkhp`.
///
/// Setiap dusun memiliki nomor, nama, dan daftar kode blok (3 digit, mis. "017")
/// yang menjadi wilayah tanggung jawabnya.
class Dusun {
  final int number;
  final String name;
  final String? alias;
  final List<String> bloks;
  final double? focusLat;
  final double? focusLng;
  final double? focusZoom;

  const Dusun({
    required this.number,
    String? name,
    this.alias,
    required this.bloks,
    this.focusLat,
    this.focusLng,
    this.focusZoom,
  }) : name = name ?? 'Dusun $number';

  String get label => alias != null && alias!.isNotEmpty
      ? 'Dusun $number ($alias)'
      : (name.isNotEmpty ? name : 'Dusun $number');

  Map<String, dynamic> toJson() => {
    'number': number,
    'name': name,
    if (alias != null) 'alias': alias,
    'bloks': bloks,
    if (focusLat != null && focusLng != null)
      'titik_fokus': {
        'lat': focusLat,
        'lng': focusLng,
        if (focusZoom != null) 'zoom': focusZoom,
      },
  };

  factory Dusun.fromJson(Map<String, dynamic> json) {
    double? fLat;
    double? fLng;
    double? fZoom;
    if (json['titik_fokus'] is Map) {
      final tf = json['titik_fokus'] as Map;
      fLat = (tf['lat'] as num?)?.toDouble();
      fLng = (tf['lng'] as num?)?.toDouble();
      fZoom = (tf['zoom'] as num?)?.toDouble();
    }
    return Dusun(
      number: (json['number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String?,
      alias: json['alias'] as String?,
      bloks:
          (json['bloks'] as List?)
              ?.map((e) => e.toString().padLeft(3, '0'))
              .toList() ??
          [],
      focusLat: fLat,
      focusLng: fLng,
      focusZoom: fZoom,
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
  static const _prefKantorLatKey = 'dusun_data_kantor_lat';
  static const _prefKantorLngKey = 'dusun_data_kantor_lng';

  double? _kantorDesaLat;
  double? _kantorDesaLng;

  double? get kantorDesaLat => _kantorDesaLat;
  double? get kantorDesaLng => _kantorDesaLng;

  Future<void> setKantorDesaLocation(double lat, double lng) async {
    _kantorDesaLat = lat;
    _kantorDesaLng = lng;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKantorLatKey, lat);
      await prefs.setDouble(_prefKantorLngKey, lng);
    } catch (_) {}
  }

  Future<void> clearKantorDesaLocation() async {
    _kantorDesaLat = null;
    _kantorDesaLng = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKantorLatKey);
      await prefs.remove(_prefKantorLngKey);
    } catch (_) {}
  }

  /// Cadangan bawaan bila belum ada manifest .dkhp yang pernah dimuat.
  static const List<Dusun> defaultBobojongDusuns = [
    Dusun(
      number: 1,
      name: 'Dusun Bobojong',
      alias: 'Bobojong',
      focusLat: -6.770226,
      focusLng: 107.213023,
      focusZoom: 16.0,
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
      name: 'Dusun Batulayang',
      alias: 'Batulayang',
      focusLat: -6.778046,
      focusLng: 107.204368,
      focusZoom: 16.0,
      bloks: ['005', '006', '007', '008', '009', '010', '019', '020', '021'],
    ),
    Dusun(
      number: 3,
      name: 'Dusun Cibogo',
      alias: 'Cibogo',
      focusLat: -6.766719,
      focusLng: 107.224754,
      focusZoom: 16.0,
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
    Dusun(
      number: 4,
      name: 'Dusun Cidamar',
      alias: 'Cidamar',
      focusLat: -6.756057,
      focusLng: 107.254834,
      focusZoom: 16.0,
      bloks: ['032', '033', '035', '036'],
    ),
    Dusun(
      number: 5,
      name: 'Dusun Jangari',
      alias: 'Jangari',
      focusLat: -6.748191,
      focusLng: 107.266108,
      focusZoom: 16.0,
      bloks: ['034', '037', '038', '039', '040'],
    ),
  ];

  List<Dusun> _allDusuns = [];
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
          final list = decoded
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

      _kantorDesaLat = prefs.getDouble(_prefKantorLatKey);
      _kantorDesaLng = prefs.getDouble(_prefKantorLngKey);
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
