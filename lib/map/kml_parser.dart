import '../blok_record.dart';
import '../dusun_data.dart';
import 'map_models.dart';

/// Utilitas Parser dan Generator KML (Keyhole Markup Language) Google.
class KmlParser {
  /// Mengekstrak titik dan polygon dari teks XML KML.
  static KmlParseResult parse(String kmlString, {List<BlokRecord>? dhkpRecords}) {
    final dots = <MapTaxDot>[];
    final dusunZones = <MapDusunZone>[];

    // Regex untuk Placemark
    final placemarkRegex = RegExp(
      r'<Placemark\b[^>]*>(.*?)</Placemark>',
      caseSensitive: false,
      dotAll: true,
    );
    final coordRegex = RegExp(
      r'<coordinates>(.*?)</coordinates>',
      caseSensitive: false,
      dotAll: true,
    );
    final nameRegex = RegExp(r'<name>(.*?)</name>', caseSensitive: false, dotAll: true);
    final descRegex = RegExp(r'<description>(.*?)</description>', caseSensitive: false, dotAll: true);
    final isPolygonRegex = RegExp(r'<Polygon\b', caseSensitive: false);

    final dhkpMap = <String, BlokRecord>{};
    if (dhkpRecords != null) {
      for (final r in dhkpRecords) {
        dhkpMap[r.nop.trim()] = r;
      }
    }

    final matches = placemarkRegex.allMatches(kmlString);
    int dotIndex = 0;

    for (final match in matches) {
      final content = match.group(1) ?? '';
      final name = nameRegex.firstMatch(content)?.group(1)?.trim() ?? '';
      final desc = descRegex.firstMatch(content)?.group(1)?.trim() ?? '';
      final coordMatch = coordRegex.firstMatch(content);
      if (coordMatch == null) continue;

      final coordText = coordMatch.group(1)?.trim() ?? '';
      final coords = _parseCoordinates(coordText);
      if (coords.isEmpty) continue;

      final isPolygon = isPolygonRegex.hasMatch(content);

      if (isPolygon) {
        // Ini adalah zona wilayah kedusunan / blok
        final zoneBounds = MapBounds.fromCoordinates(coords);
        final dusunNum = _inferDusunNumber(name, desc);
        dusunZones.add(MapDusunZone(
          dusunNumber: dusunNum,
          name: name.isNotEmpty ? name : 'Dusun $dusunNum',
          bloks: const [],
          bounds: zoneBounds,
          boundaryPolygon: coords,
        ));
      } else {
        // Ini adalah titik objek pajak (Point)
        dotIndex++;
        final pointCoord = coords.first;
        final nop = _extractExtendedData(content, 'NOP') ??
            _extractFromText(desc, r'NOP\s*[:=]\s*([0-9]{18})') ??
            _extractFromText(name, r'([0-9]{18})') ??
            '';

        final dhkpMatch = nop.isNotEmpty ? dhkpMap[nop] : null;
        final wpName = dhkpMatch?.namaWajibPajak ??
            _extractExtendedData(content, 'NAMA_WP') ??
            _extractFromText(desc, r'WP\s*[:=]\s*([^<\n]+)') ??
            (name.isNotEmpty ? name : 'Objek Pajak #$dotIndex');

        final blok = dhkpMatch?.blok ??
            _extractExtendedData(content, 'BLOK') ??
            (nop.length >= 13 ? nop.substring(10, 13) : '001');

        final urut = dhkpMatch?.wilayah ??
            (nop.length >= 17 ? nop.substring(13, 17) : dotIndex.toString().padLeft(4, '0'));

        final statusStr = dhkpMatch?.statusBayar ??
            _extractExtendedData(content, 'STATUS') ??
            'Belum Bayar';

        final isPaid = dhkpMatch?.isPaid ??
            (statusStr.toLowerCase().contains('lunas') ||
                statusStr.toLowerCase().contains('sudah'));
        final isFasum = dhkpMatch?.isTargetPemda ??
            desc.toLowerCase().contains('fasum') ||
            desc.toLowerCase().contains('pemda');

        final dusunNum = dhkpMatch != null
            ? (DusunData.instance.byBlok(dhkpMatch.blok)?.number ?? 1)
            : _inferDusunNumber(name, desc);

        // Relasi Alamat WP
        final alamatObj = dhkpMatch?.alamatObjek ?? _extractExtendedData(content, 'ALAMAT_OBJ') ?? '';
        final alamatWp = dhkpMatch?.alamatWp ?? _extractExtendedData(content, 'ALAMAT_WP') ?? '';

        MapCoordinate? ownerCoord;
        final ownerCoordStr = _extractExtendedData(content, 'OWNER_COORD');
        if (ownerCoordStr != null) {
          final oc = _parseCoordinates(ownerCoordStr);
          if (oc.isNotEmpty) ownerCoord = oc.first;
        }

        final dotStatus = isFasum
            ? MapDotStatus.fasum
            : (isPaid ? MapDotStatus.lunas : MapDotStatus.belumLunas);

        dots.add(MapTaxDot(
          id: 'dot_$dotIndex',
          nop: nop,
          namaWajibPajak: wpName,
          blok: blok,
          nomorUrut: urut,
          dusunNumber: dusunNum,
          coordinate: pointCoord,
          ownerCoordinate: ownerCoord,
          alamatObjek: alamatObj,
          alamatWp: alamatWp,
          jumlahPbb: dhkpMatch?.jumlahPbb ?? '',
          statusBayar: statusStr,
          isTargetPemda: isFasum,
          status: dotStatus,
          spptList: dhkpMatch != null ? [dhkpMatch] : const [],
        ));
      }
    }

    return KmlParseResult(
      dots: dots,
      dusunZones: dusunZones,
      rawKml: kmlString,
    );
  }

  /// Mengekspor daftar titik objek pajak ke format standar Google KML.
  static String exportToKml({
    required String villageName,
    required List<MapTaxDot> dots,
    List<MapDusunZone> zones = const [],
  }) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    sb.writeln('  <Document>');
    sb.writeln('    <name>Peta PBB Desa $villageName</name>');
    sb.writeln('    <description>Pemetaan Objek Pajak KML - Aplikasi Cek PBB Cianjur</description>');

    // Styles untuk titik warna
    sb.writeln('    <Style id="dot_lunas">');
    sb.writeln('      <IconStyle><color>ff00ff00</color><scale>1.1</scale></IconStyle>');
    sb.writeln('    </Style>');
    sb.writeln('    <Style id="dot_belum">');
    sb.writeln('      <IconStyle><color>ff0000ff</color><scale>1.1</scale></IconStyle>');
    sb.writeln('    </Style>');
    sb.writeln('    <Style id="dot_fasum">');
    sb.writeln('      <IconStyle><color>ff000000</color><scale>1.1</scale></IconStyle>');
    sb.writeln('    </Style>');

    // Kelompokkan per Dusun
    final dusunMap = <int, List<MapTaxDot>>{};
    for (final d in dots) {
      dusunMap.putIfAbsent(d.dusunNumber, () => []).add(d);
    }

    for (final entry in dusunMap.entries) {
      sb.writeln('    <Folder>');
      sb.writeln('      <name>Dusun ${entry.key}</name>');

      for (final dot in entry.value) {
        final style = dot.status == MapDotStatus.lunas
            ? '#dot_lunas'
            : (dot.status == MapDotStatus.fasum ? '#dot_fasum' : '#dot_belum');

        sb.writeln('      <Placemark>');
        sb.writeln('        <name>${_escapeXml(dot.namaWajibPajak)} (${dot.nomorUrut})</name>');
        sb.writeln('        <description>');
        sb.writeln('          <![CDATA[');
        sb.writeln('            <b>NOP:</b> ${dot.nop}<br/>');
        sb.writeln('            <b>Nama:</b> ${dot.namaWajibPajak}<br/>');
        sb.writeln('            <b>Blok:</b> ${dot.blok} | <b>Urut:</b> ${dot.nomorUrut}<br/>');
        sb.writeln('            <b>Status:</b> ${dot.status.label}<br/>');
        sb.writeln('            <b>PBB:</b> ${dot.jumlahPbb}<br/>');
        sb.writeln('            <b>Alamat Objek:</b> ${dot.alamatObjek}<br/>');
        sb.writeln('            <b>Alamat WP:</b> ${dot.alamatWp}');
        sb.writeln('          ]]>');
        sb.writeln('        </description>');
        sb.writeln('        <styleUrl>$style</styleUrl>');
        sb.writeln('        <ExtendedData>');
        sb.writeln('          <Data name="NOP"><value>${dot.nop}</value></Data>');
        sb.writeln('          <Data name="BLOK"><value>${dot.blok}</value></Data>');
        sb.writeln('          <Data name="STATUS"><value>${dot.statusBayar}</value></Data>');
        sb.writeln('          <Data name="ALAMAT_OBJ"><value>${_escapeXml(dot.alamatObjek)}</value></Data>');
        sb.writeln('          <Data name="ALAMAT_WP"><value>${_escapeXml(dot.alamatWp)}</value></Data>');
        if (dot.ownerCoordinate != null) {
          sb.writeln('          <Data name="OWNER_COORD"><value>${dot.ownerCoordinate!.longitude},${dot.ownerCoordinate!.latitude},0</value></Data>');
        }
        sb.writeln('        </ExtendedData>');
        sb.writeln('        <Point>');
        sb.writeln('          <coordinates>${dot.coordinate.longitude},${dot.coordinate.latitude},0</coordinates>');
        sb.writeln('        </Point>');
        sb.writeln('      </Placemark>');
      }
      sb.writeln('    </Folder>');
    }

    sb.writeln('  </Document>');
    sb.writeln('</kml>');
    return sb.toString();
  }

  /// Membuat data koordinat contoh yang realistis berbasis catatan DHKP
  /// untuk wilayah Desa Bobojong, Kec. Mande (-6.7535737, 107.260056).
  static KmlParseResult generateSampleBobojongMap(List<BlokRecord> dhkpRecords) {
    const centerLat = -6.7535737;
    const centerLng = 107.260056;

    // Dusun-dusun di Bobojong
    final dusunData = DusunData.instance;
    final dusunList = dusunData.allDusuns.isNotEmpty
        ? dusunData.allDusuns
        : DusunData.defaultBobojongDusuns;

    final zones = <MapDusunZone>[];

    // Konfigurasi koordinat geografis autentik sebaran 5 Kedusunan Desa Bobojong (WGS84)
    final authenticDusunZones = <int, List<MapCoordinate>>{
      1: const [
        // Dusun 1 (Bobojong - Sentra Barat)
        MapCoordinate(-6.770987, 107.22096),
        MapCoordinate(-6.770937, 107.220495),
        MapCoordinate(-6.770858, 107.220225),
        MapCoordinate(-6.769887, 107.217149),
        MapCoordinate(-6.76823, 107.211949),
        MapCoordinate(-6.766848, 107.208864),
        MapCoordinate(-6.766779, 107.208875),
        MapCoordinate(-6.76654, 107.209075),
        MapCoordinate(-6.766433, 107.209269),
        MapCoordinate(-6.765679, 107.211274),
        MapCoordinate(-6.762361, 107.23217),
        MapCoordinate(-6.762398, 107.232513),
        MapCoordinate(-6.762439, 107.23257),
        MapCoordinate(-6.763264, 107.23276),
        MapCoordinate(-6.76358, 107.232828),
        MapCoordinate(-6.763993, 107.232911),
        MapCoordinate(-6.764225, 107.232835),
        MapCoordinate(-6.768746, 107.23018),
      ],
      2: const [
        // Dusun 2 (Batulayang - Wilayah Barat Daya)
        MapCoordinate(-6.78165, 107.200599),
        MapCoordinate(-6.779463, 107.199692),
        MapCoordinate(-6.779407, 107.199675),
        MapCoordinate(-6.768278, 107.205228),
        MapCoordinate(-6.768214, 107.211755),
        MapCoordinate(-6.76999, 107.21746),
        MapCoordinate(-6.770125, 107.217889),
        MapCoordinate(-6.770426, 107.218847),
        MapCoordinate(-6.770919, 107.22029),
        MapCoordinate(-6.771254, 107.220884),
        MapCoordinate(-6.771313, 107.220973),
        MapCoordinate(-6.771468, 107.22105),
        MapCoordinate(-6.771721, 107.221095),
        MapCoordinate(-6.777538, 107.217811),
        MapCoordinate(-6.781149, 107.205864),
        MapCoordinate(-6.781465, 107.203875),
      ],
      3: const [
        // Dusun 3 (Cibogo - Koridor Tengah & Kantor Desa)
        MapCoordinate(-6.764197, 107.233073),
        MapCoordinate(-6.764074, 107.233024),
        MapCoordinate(-6.763354, 107.232792),
        MapCoordinate(-6.762997, 107.232718),
        MapCoordinate(-6.762594, 107.232652),
        MapCoordinate(-6.762455, 107.232638),
        MapCoordinate(-6.754791, 107.245314),
        MapCoordinate(-6.755706, 107.252796),
        MapCoordinate(-6.755801, 107.252835),
        MapCoordinate(-6.756378, 107.253059),
        MapCoordinate(-6.756501, 107.253098),
        MapCoordinate(-6.756861, 107.253198),
        MapCoordinate(-6.7575, 107.253306),
        MapCoordinate(-6.757583, 107.253238),
        MapCoordinate(-6.758001, 107.252442),
        MapCoordinate(-6.763344, 107.240365),
        MapCoordinate(-6.763703, 107.239328),
      ],
      4: const [
        // Dusun 4 (Cidamar - Koridor Timur)
        MapCoordinate(-6.758949, 107.257591),
        MapCoordinate(-6.757268, 107.253487),
        MapCoordinate(-6.756948, 107.253305),
        MapCoordinate(-6.756185, 107.25302),
        MapCoordinate(-6.75581, 107.252912),
        MapCoordinate(-6.74446, 107.260397),
        MapCoordinate(-6.744178, 107.260639),
        MapCoordinate(-6.74409, 107.260744),
        MapCoordinate(-6.74413, 107.261922),
        MapCoordinate(-6.744398, 107.26257),
        MapCoordinate(-6.744958, 107.26336),
        MapCoordinate(-6.749902, 107.267745),
        MapCoordinate(-6.750098, 107.267774),
        MapCoordinate(-6.750371, 107.267764),
        MapCoordinate(-6.750438, 107.267732),
        MapCoordinate(-6.755187, 107.262276),
        MapCoordinate(-6.757352, 107.25965),
      ],
      5: const [
        // Dusun 5 (Jangari - Wilayah Tepi Waduk Cirata)
        MapCoordinate(-6.748083, 107.267248),
        MapCoordinate(-6.745147, 107.263586),
        MapCoordinate(-6.744717, 107.263158),
        MapCoordinate(-6.744519, 107.26306),
        MapCoordinate(-6.744294, 107.26298),
        MapCoordinate(-6.744124, 107.262973),
        MapCoordinate(-6.743275, 107.262969),
        MapCoordinate(-6.742398, 107.26597),
        MapCoordinate(-6.74366, 107.268036),
        MapCoordinate(-6.744424, 107.269063),
        MapCoordinate(-6.744491, 107.26913),
        MapCoordinate(-6.744822, 107.269231),
        MapCoordinate(-6.746022, 107.26913),
      ],
    };

    for (int i = 0; i < dusunList.length; i++) {
      final d = dusunList[i];
      final boundary = authenticDusunZones[d.number] ?? [
        MapCoordinate(centerLat - 0.004, centerLng - 0.005),
        MapCoordinate(centerLat - 0.004, centerLng + 0.005),
        MapCoordinate(centerLat + 0.004, centerLng + 0.005),
        MapCoordinate(centerLat + 0.004, centerLng - 0.005),
      ];

      zones.add(MapDusunZone(
        dusunNumber: d.number,
        name: d.name.isNotEmpty ? d.name : 'Dusun ${d.number}',
        bloks: d.bloks,
        bounds: MapBounds.fromCoordinates(boundary),
        boundaryPolygon: boundary,
      ));
    }

    return KmlParseResult(
      dots: const [],
      dusunZones: zones,
    );
  }

  // --- Helper parsing internal ---

  static List<MapCoordinate> _parseCoordinates(String text) {
    final list = <MapCoordinate>[];
    final parts = text.replaceAll('\n', ' ').replaceAll('\t', ' ').split(' ');
    for (final p in parts) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      final tokens = trimmed.split(',');
      if (tokens.length >= 2) {
        final lng = double.tryParse(tokens[0]);
        final lat = double.tryParse(tokens[1]);
        if (lat != null && lng != null) {
          list.add(MapCoordinate(lat, lng));
        }
      }
    }
    return list;
  }

  static String? _extractExtendedData(String xml, String key) {
    final regex = RegExp(
      '<Data name="$key">\\s*<value>(.*?)</value>\\s*</Data>',
      caseSensitive: false,
      dotAll: true,
    );
    return regex.firstMatch(xml)?.group(1)?.trim();
  }

  static String? _extractFromText(String text, String pattern) {
    final regex = RegExp(pattern, caseSensitive: false);
    return regex.firstMatch(text)?.group(1)?.trim();
  }

  static int _inferDusunNumber(String name, String desc) {
    final full = '$name $desc'.toLowerCase();
    final match = RegExp(r'dusun\s*([1-9])').firstMatch(full);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '1') ?? 1;
    }
    return 1;
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

/// Hasil ekstraksi KML.
class KmlParseResult {
  final List<MapTaxDot> dots;
  final List<MapDusunZone> dusunZones;
  final String? rawKml;

  const KmlParseResult({
    required this.dots,
    required this.dusunZones,
    this.rawKml,
  });
}
