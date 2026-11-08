import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../blok_data_store.dart';
import '../blok_record.dart';
import '../dusun_data.dart';
import '../nop_helper.dart';
import '../services/location_service.dart';
import 'kml_parser.dart';
import 'map_models.dart';

/// Pilihan provider layer peta langsung (Pilihan Layer Peta).
enum LiveMapProvider {
  googleHybrid(
    'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
    'Google Satelit (Hybrid: Foto + Jalan)',
    Icons.satellite_alt_rounded,
  ),
  googleSatellite(
    'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    'Google Satelit (Foto Udara Murni)',
    Icons.photo_camera_back_rounded,
  ),
  googleRoadmap(
    'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
    'Google Peta Jalan (Roadmap)',
    Icons.map_rounded,
  ),
  openStreetMap(
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'OpenStreetMap (Vektor Bebas)',
    Icons.public_rounded,
  ),
  rbiBig(
    'https://geoservices.big.go.id/rbi/rest/services/BASEMAP/Rupabumi_Indonesia/MapServer/tile/{z}/{y}/{x}',
    'Peta Rupabumi Indonesia (BIG)',
    Icons.account_balance_rounded,
  );

  final String urlTemplate;
  final String label;
  final IconData icon;

  const LiveMapProvider(this.urlTemplate, this.label, this.icon);
}

/// Model informasi desa tetangga di Kecamatan Mande & Karangtengah untuk layer putih (masking).
class NeighborDesaInfo {
  final String name;
  final String? kecamatan;
  final List<LatLng> polygon;
  final LatLng center;

  const NeighborDesaInfo({
    required this.name,
    this.kecamatan,
    required this.polygon,
    required this.center,
  });
}

/// Layar Navigasi Peta Objek Pajak Langsung (Peta Objek Pajak DHKP).
class DhkpMapScreen extends StatefulWidget {
  final List<BlokRecord>? initialRecords;
  final int? initialDusun;
  final String? initialBlok;
  final List<MapTaxDot>? initialDots;
  final List<MapDusunZone>? initialZones;

  const DhkpMapScreen({
    super.key,
    this.initialRecords,
    this.initialDusun,
    this.initialBlok,
    this.initialDots,
    this.initialZones,
  });

  @override
  State<DhkpMapScreen> createState() => _DhkpMapScreenState();
}

class _DhkpMapScreenState extends State<DhkpMapScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;
  AnimationController? _mapMoveAnimationController;

  List<MapTaxDot> _allDots = [];
  List<MapDusunZone> _zones = [];

  int? _selectedDusun;
  String? _selectedBlok;
  MapDotStatus? _filterStatus;
  MapTaxDot? _selectedDot;

  LiveMapProvider _activeProvider = LiveMapProvider.googleHybrid;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Batas Wilayah Resmi Badan Informasi Geospasial (BIG)
  bool _showDesaBoundary = true;
  bool _showNeighborMask = true; // Layer putih desa lain di Kec. Mande & Karangtengah (aktif default)
  List<LatLng> _desaBoundaryPoints = [];
  List<NeighborDesaInfo> _neighborDesas = [];
  MapBounds? _desaBounds;

  // Layer Bangunan & Rumah Warga (OpenStreetMap)
  bool _showOsmBuildings = false;
  List<Polygon> _osmBuildingPolygons = [];

  // Layer Jalan & Gang Desa (OpenStreetMap)
  bool _showOsmRoads = false;
  List<Polyline> _osmRoadPolylines = [];

  // Layer Sungai & Perairan (OpenStreetMap)
  bool _showOsmWaterways = false;
  List<Polyline> _osmWaterPolylines = [];

  // Titik pusat koordinat Kabupaten Cianjur (Alun-Alun / Pusat Pemda Cianjur)
  static const LatLng _cianjurCenter = LatLng(-6.8219, 107.1398);

  /// Titik pusat dinamis wilayah kerja yang aktif.
  /// Urutan prioritas:
  /// 1. Koordinat kantor desa jika tersedia dari manifest DHKP
  /// 2. Koordinat centroid kecamatan aktif dari katalog 32 kecamatan Cianjur
  /// 3. Koordinat pusat Kabupaten Cianjur
  LatLng _getActiveWilayahCenter() {
    final dLat = DusunData.instance.kantorDesaLat;
    final dLng = DusunData.instance.kantorDesaLng;
    if (dLat != null && dLng != null) {
      return LatLng(dLat, dLng);
    }
    final kecCentroid = kecamatanCentroids[activeKecamatanCode];
    if (kecCentroid != null) {
      return LatLng(kecCentroid.lat, kecCentroid.lng);
    }
    return _cianjurCenter;
  }

  /// Mengembalikan titik kantor desa dinamis dari manifest DHKP bila tersedia,
  /// atau null jika belum dikonfigurasi.
  LatLng? get _effectiveKantorDesa {
    final dLat = DusunData.instance.kantorDesaLat;
    final dLng = DusunData.instance.kantorDesaLng;
    if (dLat != null && dLng != null) {
      return LatLng(dLat, dLng);
    }
    return null;
  }

  /// Mengembalikan titik fokus dusun dinamis dari manifest DHKP bila tersedia
  LatLng? _getDusunFocus(int dNum) {
    try {
      final d = DusunData.instance.allDusuns.firstWhere((d) => d.number == dNum);
      if (d.focusLat != null && d.focusLng != null) {
        return LatLng(d.focusLat!, d.focusLng!);
      }
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _selectedDusun = widget.initialDusun;
    _selectedBlok = widget.initialBlok;
    _allDots = widget.initialDots != null ? List.of(widget.initialDots!) : [];
    _zones = widget.initialZones != null ? List.of(widget.initialZones!) : [];

    _loadData();
  }

  @override
  void dispose() {
    _mapMoveAnimationController?.dispose();
    _pulseController.dispose();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Peta secara bawaan bersih tanpa titik atau zonasi dummy hingga berkas spasial/KML dimuat
    if (!mounted) return;
    setState(() {
      _allDots = widget.initialDots != null ? List.of(widget.initialDots!) : [];
      _zones = widget.initialZones != null ? List.of(widget.initialZones!) : [];
      _selectedDusun = widget.initialDusun;
      _selectedBlok = widget.initialBlok;
      _selectedDot = null;
      _desaBoundaryPoints = [];
      _desaBounds = null;
      _neighborDesas = [];
      _osmBuildingPolygons = [];
      _osmRoadPolylines = [];
      _osmWaterPolylines = [];
    });

    if (_allDots.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitDesaBounds();
      });
    }
  }

  MapDusunZone? get _currentZone {
    if (_selectedDusun == null) return null;
    return _zones.cast<MapDusunZone?>().firstWhere(
      (z) => z?.dusunNumber == _selectedDusun,
      orElse: () => null,
    );
  }

  List<MapTaxDot> get _visibleDots {
    if (_selectedDusun == null) return _allDots;
    return _allDots.where((d) => d.dusunNumber == _selectedDusun).toList();
  }

  List<String> get _currentZoneBloks {
    final zone = _currentZone;
    if (zone != null && zone.bloks.isNotEmpty) {
      return zone.bloks;
    }
    return _visibleDots.map((d) => d.blok).toSet().toList()..sort();
  }

  // Hitung statistik status di dusun aktif
  int get _countTotal => _visibleDots.length;
  int get _countLunas =>
      _visibleDots.where((d) => d.status == MapDotStatus.lunas).length;
  int get _countBelum =>
      _visibleDots.where((d) => d.status == MapDotStatus.belumLunas).length;
  int get _countSebagian =>
      _visibleDots.where((d) => d.status == MapDotStatus.sebagian).length;
  int get _countFasum =>
      _visibleDots.where((d) => d.status == MapDotStatus.fasum).length;

  Future<void> _pickKmlFile() async {
    try {
      final currentRecords =
          widget.initialRecords ?? await BlokDataStore.instance.loadAll();
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kml', 'xml'],
      );
      if (files.isNotEmpty && files.first.path != null) {
        final file = File(files.first.path!);
        final text = await file.readAsString();
        final parseResult =
            KmlParser.parse(text, dhkpRecords: currentRecords);
        if (parseResult.dots.isNotEmpty) {
          setState(() {
            _allDots = parseResult.dots;
            if (parseResult.dusunZones.isNotEmpty) {
              _zones = parseResult.dusunZones;
            }
            _selectedDot = null;
          });
          // Geser kamera ke titik pertama hasil KML
          final firstDot = parseResult.dots.first;
          _mapController.move(firstDot.coordinate.toLatLng(), 16.0);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Berhasil memuat berkas KML: ${parseResult.dots.length} objek pajak terpetakan!'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Berkas KML tidak memuat koordinat objek pajak yang valid.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat KML: $e')),
        );
      }
    }
  }

  void _selectDusun(int dusunNum) {
    setState(() {
      _selectedDusun = dusunNum;
      _selectedBlok = null;
      _selectedDot = null;
    });

    final focusCoord = _getDusunFocus(dusunNum);
    if (focusCoord != null) {
      _animatedMapMove(focusCoord, 16.0);
    } else {
      final zone = _currentZone;
      if (zone != null) {
        if (zone.boundaryPolygon.isNotEmpty) {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(
                zone.boundaryPolygon.map((c) => c.toLatLng()).toList(),
              ),
              padding: const EdgeInsets.only(
                top: 95,
                bottom: 110,
                left: 32,
                right: 64,
              ),
              maxZoom: 16.5,
            ),
          );
        } else {
          _animatedMapMove(zone.bounds.center.toLatLng(), 15.5);
        }
      } else {
        final dots =
            _allDots.where((d) => d.dusunNumber == dusunNum).toList();
        if (dots.isNotEmpty) {
          final b = MapBounds.fromCoordinates(
              dots.map((d) => d.coordinate).toList());
          _animatedMapMove(b.center.toLatLng(), 16.0);
        }
      }
    }
  }

  void _selectBlok(String? blok) {
    setState(() {
      _selectedBlok = blok;
      _selectedDot = null;
    });

    if (blok != null) {
      final matching =
          _visibleDots.where((d) => d.blok == blok).toList();
      if (matching.isNotEmpty) {
        final coords = matching.map((d) => d.coordinate).toList();
        final bBounds = MapBounds.fromCoordinates(coords);
        _mapController.move(bBounds.center.toLatLng(), 16.5);
      }
    }
  }

  void _selectDot(MapTaxDot dot) {
    setState(() {
      _selectedDot = dot;
    });
    _animatedMapMove(dot.coordinate.toLatLng(), _mapController.camera.zoom);
  }

  void _sorotRumahPemilik(MapTaxDot dot) {
    if (dot.ownerCoordinate == null) return;
    final ownerLatLng = dot.ownerCoordinate!.toLatLng();
    _animatedMapMove(ownerLatLng, 17.0);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🎯 Menyorot rumah pemilik: ${dot.namaWajibPajak} (${dot.alamatWp})',
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFFD97706),
      ),
    );
  }

  void _fitDesaBounds() {
    if (_desaBoundaryPoints.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(_desaBoundaryPoints),
          padding: const EdgeInsets.only(
            top: 95,
            bottom: 110,
            left: 28,
            right: 62,
          ),
          maxZoom: 16.0,
        ),
      );
    } else if (_desaBounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(_desaBounds!.minLat, _desaBounds!.minLng),
            LatLng(_desaBounds!.maxLat, _desaBounds!.maxLng),
          ),
          padding: const EdgeInsets.only(
            top: 95,
            bottom: 110,
            left: 28,
            right: 62,
          ),
          maxZoom: 16.0,
        ),
      );
    } else if (_allDots.isNotEmpty) {
      if (_allDots.length == 1) {
        _mapController.move(_allDots.first.coordinate.toLatLng(), 16.0);
      } else {
        final coords = _allDots.map((d) => d.coordinate).toList();
        final b = MapBounds.fromCoordinates(coords);
        if ((b.maxLat - b.minLat).abs() < 0.0001 &&
            (b.maxLng - b.minLng).abs() < 0.0001) {
          _mapController.move(b.center.toLatLng(), 16.0);
        } else {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds(
                LatLng(b.minLat, b.minLng),
                LatLng(b.maxLat, b.maxLng),
              ),
              padding: const EdgeInsets.only(
                top: 95,
                bottom: 110,
                left: 28,
                right: 62,
              ),
              maxZoom: 16.0,
            ),
          );
        }
      }
    }
  }

  /// Animasi pergerakan kamera halus (fly-to / gliding camera) ala Google Maps.
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    _mapMoveAnimationController?.stop();
    _mapMoveAnimationController?.dispose();

    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: camera.zoom,
      end: destZoom,
    );
    final rotateTween = Tween<double>(
      begin: camera.rotation,
      end: 0.0,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 950),
      vsync: this,
    );
    _mapMoveAnimationController = controller;

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
      if (rotateTween.evaluate(animation) != 0.0) {
        _mapController.rotate(rotateTween.evaluate(animation));
      }
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
        if (_mapMoveAnimationController == controller) {
          _mapMoveAnimationController = null;
        }
      }
    });

    controller.forward();
  }

  /// Fokus langsung ke koordinat Kantor Desa dengan animasi terbang halus ala Google Maps GPS.
  void _focusKantorDesa() {
    final kantorPos = _effectiveKantorDesa;
    if (kantorPos == null) return;
    HapticFeedback.lightImpact();

    final currentCenter = _mapController.camera.center;
    final currentZoom = _mapController.camera.zoom;
    final isAlreadyClose =
        (currentCenter.latitude - kantorPos.latitude).abs() < 0.0008 &&
        (currentCenter.longitude - kantorPos.longitude).abs() < 0.0008;

    double targetZoom = 16.8;
    if (isAlreadyClose && currentZoom < 18.0) {
      // Jika kamera sudah berada di kantor desa, lakukan zoom in bertahap
      targetZoom = (currentZoom + 1.0).clamp(16.0, 18.5);
    }

    _animatedMapMove(kantorPos, targetZoom);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.account_balance_rounded,
                color: Color(0xFFF1C40F), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Menuju lokasi Kantor Desa $activeDesaName...',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
  }

  void _showLayerControlSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(context);
            final isDarkSheet = theme.brightness == Brightness.dark;
            final bgCard = isDarkSheet ? const Color(0xFF1E293B) : Colors.white;
            final txtPrimary = isDarkSheet ? Colors.white : const Color(0xFF1E293B);
            final txtSecondary = isDarkSheet ? Colors.white70 : Colors.blueGrey;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2)),
                ],
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 4),
                        decoration: BoxDecoration(
                          color: isDarkSheet ? Colors.white24 : Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header Bar with Close Button ("biarkan user yg tutup")
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 10, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_rounded, color: Color(0xFF3498DB), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Pengaturan Layer Peta',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: txtPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE67E22)
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFFE67E22),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Text(
                                        'EKSPERIMENTAL',
                                        style: TextStyle(
                                          color: Color(0xFFE67E22),
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Pilih layer sesuai kebutuhan, ketuk tutup jika selesai',
                                  style: TextStyle(fontSize: 11, color: txtSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Tutup',
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          // SECTION: PILIHAN PETA DASAR
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                            child: Text(
                              'PILIHAN PETA DASAR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: txtSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ...LiveMapProvider.values.map((p) {
                            final isSel = p == _activeProvider;
                            return InkWell(
                              onTap: () {
                                setState(() => _activeProvider = p);
                                setSheetState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      p.icon,
                                      size: 20,
                                      color: isSel ? const Color(0xFF2E86DE) : txtSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        p.label,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                          color: isSel ? const Color(0xFF2E86DE) : txtPrimary,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      isSel
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      size: 19,
                                      color: isSel ? const Color(0xFF2E86DE) : Colors.grey.shade400,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Divider(height: 1),
                          ),
                          // SECTION: GARIS BATAS & FITUR WILAYAH
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                            child: Text(
                              'GARIS BATAS & FITUR WILAYAH',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: txtSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          // 1. Batas Desa Bobojong (BIG)
                          InkWell(
                            onTap: () {
                              setState(() => _showDesaBoundary = !_showDesaBoundary);
                              setSheetState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _showDesaBoundary
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color: _showDesaBoundary ? const Color(0xFFE74C3C) : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Batas Desa Bobojong (BIG)',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: txtPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Garis merah putus-putus batas resmi BIG',
                                          style: TextStyle(fontSize: 11, color: txtSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 2. Layer Putih Wilayah Sekitar
                          InkWell(
                            onTap: () {
                              setState(() => _showNeighborMask = !_showNeighborMask);
                              setSheetState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _showNeighborMask
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color: _showNeighborMask ? const Color(0xFF3498DB) : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Layer Putih Wilayah Sekitar (Mande & Karangtengah)',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: txtPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Masking desa tetangga agar Bobojong kontras',
                                          style: TextStyle(fontSize: 11, color: txtSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 3. Bangunan & Rumah Warga (OSM)
                          InkWell(
                            onTap: () {
                              setState(() => _showOsmBuildings = !_showOsmBuildings);
                              setSheetState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _showOsmBuildings
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color: _showOsmBuildings ? const Color(0xFFE67E22) : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Bangunan & Rumah Warga (OSM)',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: txtPrimary,
                                          ),
                                        ),
                                        Text(
                                          _osmBuildingPolygons.isNotEmpty
                                              ? '${_osmBuildingPolygons.length} poligon atap rumah Desa Bobojong'
                                              : '5.313 poligon atap rumah Desa Bobojong',
                                          style: TextStyle(fontSize: 11, color: txtSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 4. Jalan & Gang Desa (OSM)
                          InkWell(
                            onTap: () {
                              setState(() => _showOsmRoads = !_showOsmRoads);
                              setSheetState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _showOsmRoads
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color: _showOsmRoads ? const Color(0xFFF39C12) : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Jalan & Gang Desa (OSM)',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: txtPrimary,
                                          ),
                                        ),
                                        Text(
                                          _osmRoadPolylines.isNotEmpty
                                              ? '${_osmRoadPolylines.length} ruas jalan & gang lingkungan'
                                              : '161 ruas jalan & gang lingkungan',
                                          style: TextStyle(fontSize: 11, color: txtSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 5. Sungai & Perairan (OSM)
                          InkWell(
                            onTap: () {
                              setState(() => _showOsmWaterways = !_showOsmWaterways);
                              setSheetState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    _showOsmWaterways
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 20,
                                    color: _showOsmWaterways ? const Color(0xFF2980B9) : Colors.grey,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Sungai & Perairan (OSM)',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: txtPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Sungai Cibalagung, Citarum & Waduk Cirata',
                                          style: TextStyle(fontSize: 11, color: txtSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                      child: SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Tutup Panel Layer', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C3E50),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final desaName = activeDesaName.isNotEmpty ? activeDesaName : 'BOBOJONG';
    final kecName =
        activeKecamatanName.isNotEmpty ? activeKecamatanName : 'MANDE';

    // Filter dots sesuai blok dan status
    final filteredDots = _visibleDots.where((dot) {
      if (_selectedBlok != null && dot.blok != _selectedBlok) return false;
      if (_filterStatus != null && dot.status != _filterStatus) return false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F141C) : const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Cari NOP atau Nama Wajib Pajak...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (query) {
                  if (query.trim().isEmpty) return;
                  final q = query.toLowerCase();
                  final match = _visibleDots.cast<MapTaxDot?>().firstWhere(
                        (d) =>
                            d!.namaWajibPajak.toLowerCase().contains(q) ||
                            d.nop.contains(q),
                        orElse: () => null,
                      );
                  if (match != null) {
                    _selectDot(match);
                  }
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.satellite_alt_rounded,
                          size: 18, color: Color(0xFFF1C40F)),
                      const SizedBox(width: 6),
                      Text(
                        (_zones.isNotEmpty || _allDots.isNotEmpty) &&
                                _selectedDusun != null
                            ? 'Peta Objek Pajak: Dusun $_selectedDusun'
                            : ((_zones.isEmpty && _allDots.isEmpty)
                                ? 'Peta Wilayah'
                                : 'Peta Objek Pajak'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE67E22).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFE67E22),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'EKSPERIMENTAL',
                          style: TextStyle(
                            color: Color(0xFFF39C12),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    (_allDots.isEmpty && _zones.isEmpty)
                        ? 'Peta Dasar Satelit (Belum ada berkas DHKP dimuat)'
                        : 'Desa $desaName, Kec. $kecName - ${_currentZone?.name ?? (_selectedDusun != null ? "Dusun $_selectedDusun" : "Semua Wilayah")} (Satelit Google)',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
        actions: [
          // Pemilih Lapisan Peta & Pengaturan Garis Batas Wilayah (Modal Bottom Sheet interaktif)
          IconButton(
            key: const ValueKey('btn_switch_layer_map'),
            icon: const Icon(Icons.layers_rounded),
            tooltip: 'Pengaturan Layer & Batas Wilayah',
            onPressed: _showLayerControlSheet,
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Tutup Pencarian' : 'Cari Wajib Pajak',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Unggah Berkas KML',
            onPressed: _pickKmlFile,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. PETA LIVE INTERAKTIF SEUTUHNYA (FLUTTER MAP FULL SCREEN)
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _getActiveWilayahCenter(),
                initialZoom: 13.0,
                minZoom: 11.0,
                maxZoom: 19.0,
                onTap: (tapPosition, point) {
                  // Tutup kartu jika mengetuk sembarang area peta
                  if (_selectedDot != null) {
                    setState(() => _selectedDot = null);
                  }
                },
              ),
              children: [
                // 1.1 Layer Ubin Peta Langsung Google Maps / BIG (Streaming Bebas)
                TileLayer(
                  urlTemplate: _activeProvider.urlTemplate,
                  userAgentPackageName: 'id.cianjur.pbb',
                  maxZoom: 19,
                ),

                // 1.2 Layer Putih Transparan pada Desa Sekitar di Kecamatan Mande & Karangtengah (Masking Wilayah)
                // Desa Bobojong dibiarkan normal (tanpa layer putih) agar terlihat jelas & kontras
                if (_showNeighborMask && _neighborDesas.isNotEmpty)
                  PolygonLayer(
                    polygons: _neighborDesas
                        .map(
                          (n) => Polygon(
                            points: n.polygon,
                            color: Colors.white.withValues(alpha: 0.65),
                            borderColor:
                                Colors.blueGrey.withValues(alpha: 0.45),
                            borderStrokeWidth: 1.2,
                          ),
                        )
                        .toList(),
                  ),

                // 1.3 Label Nama Desa-Desa Sekitar di Kecamatan Mande & Karangtengah
                if (_showNeighborMask && _neighborDesas.isNotEmpty)
                  MarkerLayer(
                    markers: _neighborDesas
                        .map(
                          (n) => Marker(
                            point: n.center,
                            width: 150,
                            height: 38,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.90),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        Colors.blueGrey.withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 3,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Desa ${n.name}',
                                      style: TextStyle(
                                        fontSize: 9.2,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey.shade800,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (n.kecamatan != null && n.kecamatan!.isNotEmpty)
                                      Text(
                                        'Kec. ${n.kecamatan}',
                                        style: TextStyle(
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blueGrey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),

                // 1.4 Layer Bangunan & Rumah Warga Desa Bobojong (OpenStreetMap)
                if (_showOsmBuildings && _osmBuildingPolygons.isNotEmpty)
                  PolygonLayer(
                    polygons: _osmBuildingPolygons,
                  ),

                // 1.5 Layer Sungai & Perairan (OpenStreetMap)
                if (_showOsmWaterways && _osmWaterPolylines.isNotEmpty)
                  PolylineLayer(
                    polylines: _osmWaterPolylines,
                  ),

                // 1.6 Layer Jalan & Gang Desa (OpenStreetMap)
                if (_showOsmRoads && _osmRoadPolylines.isNotEmpty)
                  PolylineLayer(
                    polylines: _osmRoadPolylines,
                  ),

                // 1.7 Garis Batas Wilayah Resmi Desa Bobojong (BIG)
                if (_showDesaBoundary && _desaBoundaryPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _desaBoundaryPoints,
                        color: const Color(0xFFE74C3C), // Merah Elegan Batas Resmi
                        strokeWidth: 2.8,
                        borderColor: Colors.white,
                        borderStrokeWidth: 1.2,
                        pattern:
                            StrokePattern.dashed(segments: const [10, 5]),
                      ),
                    ],
                  ),


                // 1.3 Garis Trajektori ke Rumah Pemilik (jika terpisah)
                if (_selectedDot != null &&
                    _selectedDot!.hasSeparateOwnerLocation)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          _selectedDot!.coordinate.toLatLng(),
                          _selectedDot!.ownerCoordinate!.toLatLng(),
                        ],
                        color: const Color(0xFFF59E0B),
                        strokeWidth: 3.0,
                      ),
                    ],
                  ),

                // 1.4 Marker Rumah Pemilik (Beacon)
                if (_selectedDot != null &&
                    _selectedDot!.hasSeparateOwnerLocation)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedDot!.ownerCoordinate!.toLatLng(),
                        width: 140,
                        height: 50,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xE6000000),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFFF59E0B), width: 1),
                              ),
                              child: Text(
                                '🏠 ${_selectedDot!.namaWajibPajak}',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.location_on_rounded,
                                color: Color(0xFFF59E0B), size: 22),
                          ],
                        ),
                      ),
                    ],
                  ),

                // 1.5 Landmark Presisi: Kantor Desa (hanya jika koordinat terkonfigurasi)
                if (_effectiveKantorDesa != null)
                  MarkerLayer(
                    markers: [
                      // Landmark Presisi: Kantor Desa
                      Marker(
                        point: _effectiveKantorDesa!,
                      width: 170,
                      height: 95,
                      child: GestureDetector(
                        onTap: _focusKantorDesa,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xE61E293B),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFFF1C40F), width: 1.2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                '🏛️ Kantor Desa $activeDesaName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) {
                                final pulse = _pulseController.value;
                                return SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Lingkaran gelombang radar (pulse wave ripple ala Google Maps GPS)
                                      Container(
                                        width: 22 + (pulse * 20),
                                        height: 22 + (pulse * 20),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFF1C40F)
                                              .withValues(
                                                  alpha: 0.35 * (1.0 - pulse)),
                                          border: Border.all(
                                            color: const Color(0xFFF1C40F)
                                                .withValues(
                                                    alpha: 0.70 * (1.0 - pulse)),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      // Lingkaran tengah ikon instansi pemerintahan
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF2C3E50),
                                          border: Border.all(
                                            color: const Color(0xFFF1C40F),
                                            width: 2.0,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black45,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.account_balance_rounded,
                                            color: Color(0xFFF1C40F),
                                            size: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    ...filteredDots.map((dot) {
                    final isSelected = _selectedDot?.id == dot.id;
                    final dotColor = dot.status.color;
                    final size = isSelected ? 34.0 : 26.0;

                    return Marker(
                      point: dot.coordinate.toLatLng(),
                      width: size,
                      height: size,
                      child: GestureDetector(
                        onTap: () => _selectDot(dot),
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            final pulse =
                                isSelected ? _pulseController.value : 0.0;
                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFF1C40F)
                                      : Colors.white,
                                  width: isSelected ? 2.5 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? const Color(0xFFF1C40F)
                                            .withValues(alpha: 0.6 + pulse * 0.3)
                                        : dotColor.withValues(alpha: 0.5),
                                    blurRadius: isSelected ? 12 : 5,
                                    spreadRadius: isSelected ? 3 : 1,
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: dot.status == MapDotStatus.fasum
                                  ? const Icon(Icons.account_balance_rounded,
                                      size: 12, color: Colors.white)
                                  : Text(
                                      dot.nomorUrut.length >= 2
                                          ? dot.nomorUrut.substring(
                                              dot.nomorUrut.length - 2)
                                          : dot.nomorUrut,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    );
                  }),
                ],
              ),
              ],
            ),
          ),

          // 2. Panel Navigasi: Pemilih Kedusunan & Blok (hanya jika ada data DHKP)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: (_allDots.isEmpty && _zones.isEmpty)
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xE61A2232)
                          : Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFF1C40F).withValues(alpha: 0.35),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.map_outlined,
                          color: Color(0xFFF1C40F),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Peta Belum Memuat Koordinat ($activeDesaName)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 1),
                              const Text(
                                'Belum ada koordinat objek pajak atau batas spasial yang dimuat. Silakan unggah berkas KML untuk menampilkan sebaran.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _pickKmlFile,
                          icon: const Icon(Icons.file_upload_outlined, size: 16),
                          label: const Text('Unggah KML', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Selector Dusun
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xE61A2232)
                              : Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFF1C40F).withValues(alpha: 0.4),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Text(
                              '🗺️ ${_currentZone?.name.toUpperCase() ?? "SEMUA WILAYAH"}:',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: Color(0xFFF1C40F),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: const Text('Semua'),
                                        selected: _selectedDusun == null,
                                        onSelected: (val) {
                                          if (val) {
                                            setState(() {
                                              _selectedDusun = null;
                                              _selectedBlok = null;
                                              _selectedDot = null;
                                            });
                                            _fitDesaBounds();
                                          }
                                        },
                                        selectedColor: const Color(0xFFF1C40F),
                                        labelStyle: TextStyle(
                                          fontSize: 11,
                                          fontWeight: _selectedDusun == null
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: _selectedDusun == null ? Colors.black : null,
                                        ),
                                      ),
                                    ),
                                    ...() {
                                      final currentDusuns = DusunData.instance.currentDusuns;
                                      if (currentDusuns.isNotEmpty) {
                                        return currentDusuns.map((d) {
                                          final dNum = d.number;
                                          final aliasName = d.alias ?? (d.name.startsWith('Dusun ') ? d.name.substring(6) : d.name);
                                          final label = aliasName.isNotEmpty && aliasName != '$dNum'
                                              ? 'Dusun $dNum ($aliasName)'
                                              : 'Dusun $dNum';
                                          final isCurrent = _selectedDusun == dNum;
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: ChoiceChip(
                                              label: Text(label),
                                              selected: isCurrent,
                                              onSelected: (val) {
                                                if (val) _selectDusun(dNum);
                                              },
                                              selectedColor: const Color(0xFFF1C40F),
                                              labelStyle: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isCurrent
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isCurrent ? Colors.black : null,
                                              ),
                                            ),
                                          );
                                        }).toList();
                                      }
                                      if (_zones.isNotEmpty) {
                                        return _zones.map((z) {
                                          final dNum = z.dusunNumber;
                                          final aliasName = z.name.startsWith('Dusun ') ? z.name.substring(6) : z.name;
                                          final label = aliasName.isNotEmpty && aliasName != '$dNum'
                                              ? 'Dusun $dNum ($aliasName)'
                                              : 'Dusun $dNum';
                                          final isCurrent = _selectedDusun == dNum;
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: ChoiceChip(
                                              label: Text(label),
                                              selected: isCurrent,
                                              onSelected: (val) {
                                                if (val) _selectDusun(dNum);
                                              },
                                              selectedColor: const Color(0xFFF1C40F),
                                              labelStyle: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isCurrent
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isCurrent ? Colors.black : null,
                                              ),
                                            ),
                                          );
                                        }).toList();
                                      }
                                      final dotDusunNums = _allDots
                                          .map((d) => d.dusunNumber)
                                          .where((n) => n > 0)
                                          .toSet()
                                          .toList()
                                        ..sort();
                                      if (dotDusunNums.isNotEmpty) {
                                        return dotDusunNums.map((dNum) {
                                          final isCurrent = _selectedDusun == dNum;
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: ChoiceChip(
                                              label: Text('Dusun $dNum'),
                                              selected: isCurrent,
                                              onSelected: (val) {
                                                if (val) _selectDusun(dNum);
                                              },
                                              selectedColor: const Color(0xFFF1C40F),
                                              labelStyle: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isCurrent
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isCurrent ? Colors.black : null,
                                              ),
                                            ),
                                          );
                                        }).toList();
                                      }
                                      return <Widget>[];
                                    }(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Selector Blok di dalam Dusun Aktif
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('Semua Blok'),
                              selected: _selectedBlok == null,
                              onSelected: (_) => _selectBlok(null),
                            ),
                            const SizedBox(width: 6),
                            ..._currentZoneBloks.map((b) {
                              final isSel = _selectedBlok == b;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text('Blok $b'),
                                  selected: isSel,
                                  onSelected: (val) => _selectBlok(val ? b : null),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),

          // 3. TOMBOL CEPAT KANAN (Fokus Batas Desa, Re-center, Zoom In, Zoom Out)
          Positioned(
            right: 14,
            bottom: _selectedDot != null ? 220 : 70,
            child: Column(
              children: [
                if (_desaBoundaryPoints.isNotEmpty ||
                    _desaBounds != null ||
                    _allDots.isNotEmpty) ...[
                  FloatingActionButton.small(
                    key: const ValueKey('btn_fit_desa_boundary'),
                    heroTag: 'btn_fit_desa_boundary',
                    backgroundColor: isDark
                        ? const Color(0xEE1A2234)
                        : Colors.white.withValues(alpha: 0.94),
                    tooltip: 'Fokus ke Seluruh Batas Wilayah',
                    onPressed: _fitDesaBounds,
                    child: const Icon(Icons.crop_free_rounded,
                        color: Color(0xFFE74C3C)),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_effectiveKantorDesa != null) ...[
                  FloatingActionButton.small(
                    key: const ValueKey('btn_fokus_kantor_desa'),
                    heroTag: 'btn_fokus_kantor_desa',
                    backgroundColor: isDark
                        ? const Color(0xEE1A2234)
                        : Colors.white.withValues(alpha: 0.94),
                    tooltip: 'Fokuskan ke Kantor Desa',
                    onPressed: _focusKantorDesa,
                    child: const Icon(Icons.account_balance_rounded,
                        color: Color(0xFFF1C40F)),
                  ),
                  const SizedBox(height: 8),
                ],
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_in',
                  backgroundColor: isDark
                      ? const Color(0xEE1A2234)
                      : Colors.white.withValues(alpha: 0.94),
                  tooltip: 'Perbesar Peta (+)',
                  onPressed: () {
                    final currentZ = _mapController.camera.zoom;
                    _animatedMapMove(_mapController.camera.center, currentZ + 1);
                  },
                  child: const Icon(Icons.add_rounded),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_out',
                  backgroundColor: isDark
                      ? const Color(0xEE1A2234)
                      : Colors.white.withValues(alpha: 0.94),
                  tooltip: 'Perkecil Peta (-)',
                  onPressed: () {
                    final currentZ = _mapController.camera.zoom;
                    _animatedMapMove(_mapController.camera.center, currentZ - 1);
                  },
                  child: const Icon(Icons.remove_rounded),
                ),
              ],
            ),
          ),

          // 4. HUD INDIKATOR STATUS (Badge Counter Filter)
          if (_allDots.isNotEmpty)
            Positioned(
              left: 14,
              bottom: _selectedDot != null ? 220 : 16,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xDD0D131D)
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL: $_countTotal',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusPill(MapDotStatus.lunas, _countLunas),
                  const SizedBox(width: 8),
                  _buildStatusPill(MapDotStatus.belumLunas, _countBelum),
                  const SizedBox(width: 8),
                  _buildStatusPill(MapDotStatus.sebagian, _countSebagian),
                  const SizedBox(width: 8),
                  _buildStatusPill(MapDotStatus.fasum, _countFasum),
                ],
              ),
            ),
          ),

          // 5. Panel Rincian Objek Pajak
          if (_selectedDot != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: _buildDetailCard(_selectedDot!, isDark),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(MapDotStatus status, int count) {
    final isSelected = _filterStatus == status;
    return InkWell(
      onTap: () {
        setState(() {
          _filterStatus = isSelected ? null : status;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? status.color.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border:
              isSelected ? Border.all(color: status.color, width: 1.2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 4, backgroundColor: status.color),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: status.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu Rincian Objek Pajak
  Widget _buildDetailCard(MapTaxDot dot, bool isDark) {
    final isOwnerSame = dot.isOwnerAddressSame;

    return Card(
      elevation: 14,
      color: isDark ? const Color(0xF21A2234) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFF1C40F), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Kartu
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: dot.status.color,
                  child: Icon(dot.status.icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dot.namaWajibPajak,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'NOP: ${dot.nop}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedDot = null),
                ),
              ],
            ),
            const Divider(height: 16),

            // Baris Rincian PBB & Status
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    label: 'STATUS BAYAR',
                    value: dot.status.label,
                    valueColor: dot.status.color,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: 'POKOK PBB',
                    value: dot.jumlahPbb.isNotEmpty ? dot.jumlahPbb : '-',
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: 'BLOK / NO URUT',
                    value: 'Blok ${dot.blok} (#${dot.nomorUrut})',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Relasi Alamat WP
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isOwnerSame
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isOwnerSame
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.amber.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isOwnerSame ? Icons.home_rounded : Icons.landscape_rounded,
                    size: 20,
                    color: isOwnerSame ? Colors.green : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOwnerSame
                              ? '🏠 Rumah Tempat Tinggal WP'
                              : '🌾 Objek Terpisah (Sawah/Kebun/Tanah)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                isOwnerSame ? Colors.green : Colors.amber.shade800,
                          ),
                        ),
                        Text(
                          isOwnerSame
                              ? 'Alamat Objek: ${dot.alamatObjek.isNotEmpty ? dot.alamatObjek : 'Desa Bobojong'}'
                              : 'Alamat Pemilik: ${dot.alamatWp.isNotEmpty ? dot.alamatWp : 'Luar Wilayah Objek'}',
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!isOwnerSame && dot.ownerCoordinate != null)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.my_location_rounded, size: 14),
                      label: const Text('Sorot Pemilik',
                          style: TextStyle(fontSize: 10)),
                      onPressed: () => _sorotRumahPemilik(dot),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: Colors.blueGrey,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
