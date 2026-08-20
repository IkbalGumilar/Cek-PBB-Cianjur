import 'dart:io';

import 'package:cek_pbb_app/staff_portal_token_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Menguji [StaffPortalTokenExtractor] terhadap potongan HTML ASLI yang
/// dikirim pengguna (lihat test/fixtures/*.html) — bukan HTML rekaan. Ini
/// membuktikan kode regex-nya benar tanpa perlu login ke server sungguhan,
/// yang tidak bisa didebug sembarangan karena akunnya akun staf final.
///
/// Yang TIDAK dibuktikan test ini: apakah token-token itu masih valid saat
/// benar-benar dikirim ke server (bisa saja terikat sesi/kedaluwarsa), dan
/// apakah bentuk respons JSON Pembayaran Kolektif tebakannya benar — itu
/// cuma bisa dipastikan lewat tes langsung di aplikasi.
void main() {
  late String monitoringHtml;
  late String kolektifHtml;

  setUpAll(() {
    monitoringHtml = File('test/fixtures/monitoring_wilayah.html').readAsStringSync();
    kolektifHtml = File('test/fixtures/pembayaran_kolektif.html').readAsStringSync();
  });

  group('Monitoring Wilayah — extractLoadQ', () {
    final cases = {
      'onSubmitSudahBayar': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzIzJywndWlkJzondTQ2OCd9',
      'onSubmitBelumBayar': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzIzJywndWlkJzondTQ2OCd9',
      'showModelRealisasi1': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzMnLCd1aWQnOid1NDY4Jywnc3JjaCc6Jyd9',
      'showModelPiutang': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzMnLCd1aWQnOid1NDY4Jywnc3JjaCc6Jyd9',
      'onSubmitSudahBayarKolektif': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzIzJywndWlkJzondTQ2OCd9',
      'onSubmitBelumBayarKolektif': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzIzJywndWlkJzondTQ2OCd9',
      'showRangkingRealisasi': 'eydhJzonYVBCQicsICdtJzonbU1vbml0b3JpbmdXaWxheWFoVjMnLCAncyc6JzUnLCd1aWQnOid1NDY4Jywnc3JjaCc6Jyd9',
    };

    for (final entry in cases.entries) {
      test('${entry.key} → q token ditemukan & cocok', () {
        final q = StaffPortalTokenExtractor.extractLoadQ(monitoringHtml, entry.key);
        expect(q, entry.value);
      });
    }
  });

  group('Monitoring Wilayah — extractFuncMode', () {
    final cases = {
      'onSubmitSudahBayar':
          'MHprcHFPR21UZ1BwVEIwelZ5enkzaDdIR21XRC90UHNKUWZoMmpuSUFNWVRwT1dVc29CSTJzSmRBamdaT3QyL3F6R0kyT1h3MEFNS3cyMUpGTnFGNWc9PTo68Or2tbeipMjc8dw9uyXueg==',
      'onSubmitBelumBayar':
          'TmgxU2diYnlOaFFPU3I2WGJmNHo3b00wN0hVMUpKd3pJLzFEaXhQMTRoQS91WFhjdWNKb1ZRTHNJMmllWWgvbTRjckFlZjIvRG41YW1Wa3I4WldCZnc9PTo6fgHQNJQZ1tzhN6ljdKDZtg==',
      'showModelRealisasi1':
          'U1hGWldua3dtU1JhVEtnRjBzNk1pcS96aW95MGswTkxsR3NJdkowei84QnZ0NXlCdThSaXRRai91akNvc0draEF0QXluVHVIa3JCVWdaT1ZkalpwbVFKYTBQelpxeUt1UmdId3FudGorWnM9OjooG6cnSAzlOAZl/G9JYd7b',
      'showModelPiutang':
          'WEZ0aFJlYkZQL1pBMkpKbDdCVGlXaVpuTmpaejY5aVJZV2VaSjNkbk5DZkN2UVRlZGZNZDRxN3BzSjhMQnhOcllLdmd5SmQzRUFlckw5eXBGWmZKemNSUnFCTURNYXVpQW02YmpWLzNRL289Ojq53SoAxUHfcEW1OXMyA8-Q',
      'onSubmitSudahBayarKolektif':
          'NUlOVnd6aGFRUFRIVHB6OHJHcElXRkJWMkhKQ2lUMWdmbXgyWjN0bjhiWTJUb21kQnRSYWIwRVRWV040alQ5R09FNWVsNzNxZ1ZIMGpqWk1TWXNudmEvTlJLTSt2cVJodjIxTWF0cmlNTVU9OjovX2u2dnJ39siOdqA4fmKY',
      'onSubmitBelumBayarKolektif':
          'K04yZlJDak5VM3RJRmR2QkhrYmgzS3h1enNrNE9ZdnhDYXRyajlPN3MrRUJNU1dRT3hUS3ZFRE5WSWdzRHRNSjI4U1BVa0ZLbnBrZGZhSTdSRVRFVGZhTWxXVFgxYzdlOWVRVHViVlYvTlU9OjoLmJdAc753GIv3R5sGBTmS',
      'showRangkingRealisasi':
          'cEtMaTNGUTR3djQ3SzNlcy9uRUNMSFZ2dnoxcVR0OXdWVlphTUhkRlFFL3dlL1ozbWNGaEVTYlpOVmszR2Q3VDNJbkxvbUxJanQzeDd5UFp0TnZ4WVc2T1BxZ2QwVWo4Zm56MnExUnkxM1g1Umk0RXV1VVRXakl2SE94bmtESks6OmeRbdZ6MeizJwX71QoXnWk=',
      'showBank':
          'cDRRR09lWTJZdW5KRmRmdkNkT3NlZnB0YnhRVmZLaUVIZjF6Wnp1UDZKTVN5aGRIaHNoMUpNZVVIYmcwOW5iWHpuMjBLaStNQWorK0pCV3hua1dHQUE9PTo65qP8Gx836M7SHl0j6L3BMA==',
    };

    for (final entry in cases.entries) {
      test('${entry.key} → funcMode token ditemukan & cocok', () {
        final funcMode = StaffPortalTokenExtractor.extractFuncMode(monitoringHtml, entry.key);
        expect(funcMode, entry.value);
      });
    }
  });

  test('fungsi yang tidak ada di halaman → null, bukan salah ambil dari fungsi lain', () {
    expect(StaffPortalTokenExtractor.extractLoadQ(monitoringHtml, 'fungsiTidakAda'), isNull);
    expect(StaffPortalTokenExtractor.extractFuncMode(monitoringHtml, 'fungsiTidakAda'), isNull);
  });

  group('Pembayaran Kolektif', () {
    test('extractGlobalQ menemukan token q global', () {
      final q = StaffPortalTokenExtractor.extractGlobalQ(kolektifHtml);
      expect(q, 'eydhJzonYVBCQicsICdtJzonbTE3OScsICd1JzonTUFOREVfQk9CT0pPTkcnLCAndWlkJzondTQ2OCd9');
    });

    test('extractFuncMode menemukan funcMode reloadDataGroup', () {
      final funcMode = StaffPortalTokenExtractor.extractFuncMode(kolektifHtml, 'reloadDataGroup', window: 800);
      expect(
        funcMode,
        'OUdObTJ0OHhFeC8vYW10NTNtZFY3QjlyOHpQYjA4SHMxYlhzUm5lTXRXNWRCWTB1V2djRENnZVRQMnJhMThQNVk1TDE4bG5jQnV6czUyWVVNK2F2MXc9PTo6TgKXPGtZPWED62APtMML1Q==',
      );
    });

    test('extractKolektifUserId menemukan userID dari URL ajax DataTables', () {
      final userId = StaffPortalTokenExtractor.extractKolektifUserId(kolektifHtml);
      expect(userId, 'u468');
    });
  });
}
