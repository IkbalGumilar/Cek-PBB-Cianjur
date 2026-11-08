# DAFTAR FILE & ELEMEN HARDCODE DI DALAM APLIKASI
**Proyek:** Cek-PBB-Cianjur  
**Tanggal Audit:** 7 November 2026  
**Ruang Lingkup:** Seluruh berkas Dart di dalam direktori `lib/` (~125 file)

Dokumen ini memetakan seluruh nilai konstan, koordinat statis, URL server, kunci bawaan, dan nilai *fallback* yang masih tertulis langsung di dalam kode (*hardcode*), lengkap dengan alasan dan rekomendasi agar dapat dijadikan dinamis.

---

## 📌 DAFTAR ISI
1. [Kategori A: Geospasial & Peta Wilayah](#kategori-a-geospasial--peta-wilayah)
2. [Kategori B: Nilai Bawaan Wilayah (Bobojong / Mande)](#kategori-b-nilai-bawaan-wilayah-bobojong--mande)
3. [Kategori C: Alamat Server & Endpoint API Eksternal](#kategori-c-alamat-server--endpoint-api-eksternal)
4. [Kategori D: Kunci Kriptografi & Secret Enkripsi Bawaan](#kategori-d-kunci-kriptografi--secret-enkripsi-bawaan)
5. [Kategori E: Konten Statis Aplikasi & Batasan Sistem](#kategori-e-konten-statis-aplikasi--batasan-sistem)
6. [Tabel Rekapitulasi File](#tabel-rekapitulasi-file)

---

## Kategori A: Geospasial & Peta Wilayah
Bagian ini berkaitan langsung dengan fitur visualisasi peta yang baru dibuat.

### 1. `lib/map/dhkp_map_screen.dart`
* **Baris 18, 23, 28, 33, 38**: URL Tile Server Provider Peta:
  * Google Hybrid: `https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}`
  * Google Satellite: `https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}`
  * Google Roadmap: `https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}`
  * OpenStreetMap: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
  * Rupabumi Indonesia (BIG): `https://geoservices.big.go.id/rbi/rest/services/BASEMAP/Rupabumi_Indonesia/MapServer/tile/{z}/{y}/{x}`
* **Baris 121**: `_bobojongCenter = LatLng(-6.7535737, 107.260056)` (Pusat default Desa Bobojong).
* **Baris 124**: `_kantorDesaLocation = LatLng(-6.763587, 107.238769)` (Titik koordinat Kantor Desa Bobojong).
* **Baris 160**: `'assets/data/bobojong_batas_big.geojson'` (Berkas batas resmi Bobojong dari BIG).
* **Baris 194**: `'assets/data/wilayah_sekitar_big.geojson'` (Berkas desa sekitar di Mande & Karangtengah).
* **Baris 234**: `'assets/data/bobojong_buildings_osm.geojson'` (5.313 poligon bangunan dari OSM).
* **Baris 269**: `'assets/data/bobojong_roads_osm.geojson'` (Garis jalan dari OSM).
* **Baris 301**: `'assets/data/bobojong_waterways_osm.geojson'` (Aliran air sungai dari OSM).
* **Baris 1074**: Fallback nama desa `'BOBOJONG'` dan kecamatan `'MANDE'` jika belum ada wilayah aktif.

### 2. `lib/map/kml_parser.dart`
* **Baris 220–221**: `centerLat = -6.7535737; centerLng = 107.260056;`.
* **Baris 231–328**: `authenticDusunZones`: Koordinat poligon pembatas WGS84 untuk Dusun 1 (Bobojong), Dusun 2 (Batulayang), Dusun 3 (Cibogo), Dusun 4 (Cidamar), dan Dusun 5 (Jangari).
* *(Catatan: Titik objek pajak simulasi sebelumnya sudah dihapus sesuai instruksi).*

### 💡 Solusi Dinamisasi Kategori A: Paket Bundel `.dkhp` Offline-First
Karena aplikasi tidak disediakan server khusus (mengandalkan kemampuan mandiri per desa), solusinya adalah **mengemas seluruh data desa ke dalam satu berkas bundel `.dkhp` (arsip terkompresi/enkripsi)**:

```text
paket_desa_bobojong.dkhp (Arsip Bundel Mandiri)
├── manifest.json              --> Metadata desa, kode NOP, koordinat Kantor Desa, bounding box
├── data_dhkp.csv / .dat       --> Data tabular (NOP, Nama WP, Luas Bumi/Bangunan, Ketetapan)
├── peta/                      --> Folder Geospasial Dinamis:
│   ├── batas_desa.geojson     --> Batas resmi desa (pengganti bobojong_batas_big.geojson)
│   ├── batas_dusun.geojson/kml--> Batas tiap kedusunan (pengganti authenticDusunZones statis)
│   ├── persil_pbb.geojson/kml --> Poligon persil bidang tanah / titik koordinat NOP
│   ├── bangunan.geojson       --> Layer atap rumah (pengganti bobojong_buildings_osm.geojson)
│   └── infrastruktur.geojson  --> Garis jalan & sungai
└── foto/                      --> (Opsional) Foto bangunan/patok rumah WP per NOP
    ├── 320520000400100010.jpg
    └── kantor_desa.jpg
```

* **Manfaat:**
  1. **Pusat Peta & Kantor Desa Dinamis:** Aplikasi membaca koordinat dari `manifest.json`. Tombol "Fokuskan ke Kantor Desa" otomatis mengarah ke kantor desa mana pun yang dimuat.
  2. **Batas Dusun & Persil Dinamis:** Aplikasi membaca dari folder `peta/` di dalam bundel, sehingga **seluruh koordinat statis di `kml_parser.dart` dan `dhkp_map_screen.dart` dapat dihapus**.
  3. **Ukuran APK Ramping:** APK dasar tidak perlu membengkak oleh file GeoJSON ribuan poligon desa tertentu.
  4. **Tile Provider Peta Tetap Publik:** Basemap satelit tetap memanfaatkan penyedia web publik gratisan (Google Hybrid/Satellite, OSM, BIG) tanpa butuh biaya server.

---

## Kategori B: Nilai Bawaan Wilayah (Bobojong / Mande)
Nilai-nilai ini menjadi *default/fallback* saat aplikasi baru diinstal atau belum ada data DHKP yang diimpor.

### 1. `lib/nop_helper.dart`
* **Baris 4**: `defaultNopPrefix = '3205200004'` (Prefix NOP Bobojong).
* **Baris 6–9**: Nilai awal:
  * `_activeKecamatanCode = '200'` (Mande)
  * `_activeKelurahanCode = '004'` (Bobojong)
  * `_activeDesaName = 'BOBOJONG'`
  * `_activeKecamatanName = 'MANDE'`
* **Baris 54–61**: `resetNopPrefix()` yang mengembalikan ke konfigurasi Bobojong.
* **Baris 186**: Fallback kode kelurahan `'004' => 'BOBOJONG'`.

### 2. `lib/dusun_data.dart`
* **Baris 91–142**: `defaultBobojongDusuns` (Total 41 Blok resmi):
  * Dusun 1 (Bobojong): Blok 001, 002, 003, 004, 011, 012, 013, 014, 015, 016, 027 (11 blok)
  * Dusun 2 (Batulayang): Blok 005, 006, 007, 008, 009, 010, 019, 020, 021 (9 blok)
  * Dusun 3 (Cibogo): Blok 017, 018, 022, 023, 024, 025, 026, 028, 029, 030, 031, 041 (12 blok)
  * Dusun 4 (Cidamar): Blok 032, 033, 035, 036 (4 blok)
  * Dusun 5 (Jangari): Blok 034, 037, 038, 039, 040 (5 blok)
  * *(Catatan: Nilai ini hanya cadangan bawaan; saat berkas DHKP memuat manifest dusun sendiri, data ini akan ditimpa secara dinamis).*

### 3. `lib/blok_record.dart`
* **Baris 46–47**: Konstruktor default `this.kecamatan = 'MANDE'`, `this.kelurahan = 'BOBOJONG'`.

### 4. `lib/dhkp/blok_csv_codec.dart`
* **Baris 127–128 & 192–193**: Nilai fallback pembacaan kolom CSV: `_cellOrDefault(row, 13, 'MANDE')` dan `_cellOrDefault(row, 14, 'BOBOJONG')`.

### 5. `lib/file_importer.dart`
* **Baris 221 & 232**: Fallback saat impor dokumen teks/Excel bila kolom desa/kecamatan tidak terisi.

### 6. `lib/staff_portal_client.dart`
* **Baris 47 & 49**: Fallback `activeKecamatanName ?? 'MANDE'` dan `activeKelurahanName ?? 'BOBOJONG'`.
* **Baris 688**: Pilihan dropdown default `KolektifKelurahan(code: '3205200004', name: 'BOBOJONG')`.

### 7. `lib/startup_setup_screen.dart`
* **Baris 753**: Teks petunjuk input wizard: `hintText: 'Contoh: BOBOJONG'`.

### 💡 Solusi Dinamisasi Kategori B: Manifest Hierarki Kecamatan & Status Awal Bersih
Pendekatan yang disepakati untuk menghapus seluruh ketergantungan hardcode wilayah:

1. **Kondisi Awal Aplikasi Bersih (*Zero Default*):**
   * Saat aplikasi baru dipasang, data default kosong (tidak mengasumsikan Bobojong).
   * Pada wizard pertama kali buka (*First Run*), petugas **wajib memilih Kecamatan dan Desa tugasnya** dari daftar kamus resmi Cianjur yang sudah tersedia offline, sedangkan impor berkas DHKP bersifat opsional (bisa dilewati/skip).
   * Nilai pilihan ini disimpan ke `SharedPreferences` dan menjadi rujukan utama bagi `NopHelper`, `BlokRecord`, dan `BlokCsvCodec` menggantikan teks hardcode `'MANDE'` dan `'BOBOJONG'`.

2. **Format Manifest Berbasis 1 Kecamatan Penuh:**
   * Berkas `manifest.json` di dalam paket `.dkhp` memuat struktur utuh **1 Kecamatan**.
   * Di dalamnya memuat daftar seluruh desa dalam kecamatan tersebut, namun **hanya desa yang ditugaskan yang diisi lengkap** (kadus, pemetaan 41 blok resmi, dan detail rincian WP):

```json
{
  "versi_manifest": "2.0",
  "kabupaten": { "kode": "3205", "nama": "CIANJUR" },
  "kecamatan": {
    "kode": "200",
    "nama": "MANDE",
    "desa_list": [
      { "kode": "001", "nama": "MEKARJAYA" },
      { "kode": "002", "nama": "CIJAMBU" },
      { "kode": "003", "nama": "KADEMANGAN" },
      {
        "kode": "004",
        "nama": "BOBOJONG",
        "is_desa_aktif": true,
        "kantor_desa": { "lat": -6.763587, "lng": 107.238769 },
        "kadus": [
          {
            "id": 1,
            "nama": "Dusun 1",
            "alias": "Bobojong",
            "titik_fokus": { "lat": -6.770226, "lng": 107.213023, "zoom": 16.0 },
            "blok": ["001", "002", "003", "004", "011", "012", "013", "014", "015", "016", "027"]
          },
          {
            "id": 2,
            "nama": "Dusun 2",
            "alias": "Batulayang",
            "titik_fokus": { "lat": -6.778046, "lng": 107.204368, "zoom": 16.0 },
            "blok": ["005", "006", "007", "008", "009", "010", "019", "020", "021"]
          },
          {
            "id": 3,
            "nama": "Dusun 3",
            "alias": "Cibogo",
            "titik_fokus": { "lat": -6.766719, "lng": 107.224754, "zoom": 16.0 },
            "blok": ["017", "018", "022", "023", "024", "025", "026", "028", "029", "030", "031", "041"]
          },
          {
            "id": 4,
            "nama": "Dusun 4",
            "alias": "Cidamar",
            "titik_fokus": { "lat": -6.756057, "lng": 107.254834, "zoom": 16.0 },
            "blok": ["032", "033", "035", "036"]
          },
          {
            "id": 5,
            "nama": "Dusun 5",
            "alias": "Jangari",
            "titik_fokus": { "lat": -6.748191, "lng": 107.266108, "zoom": 16.0 },
            "blok": ["034", "037", "038", "039", "040"]
          }
        ]
      }
    ]
  }
}
```

3. **Keunggulan:**
   * Seluruh fallback statis di 7 file Dart Kategori B tidak lagi diperlukan.
   * Struktur data sudah siap jika sewaktu-waktu petugas ditugaskan memegang lebih dari satu desa dalam satu kecamatan.

---

## Kategori C: Alamat Server & Endpoint API Eksternal
URL pihak ketiga yang dituju oleh aplikasi untuk layanan cek tagihan, pembayaran, dan pembaruan.

### 1. `lib/pbb_client.dart`
* **Baris 78**: `https://cektagihan.cianjurkab.v-tax.id/portlet.php` (Portal Cek Tagihan PBB Cianjur).
* **Baris 80**: `https://cektagihan.cianjurkab.v-tax.id/image-2018/securimage_show.php` (Captcha).
* **Baris 137, 733**: `https://cektagihan.cianjurkab.v-tax.id/print-pdf.php` (Unduh PDF Tagihan).
* **Baris 316, 396, 755**: `https://cektagihan.cianjurkab.v-tax.id/stts-pdf-pbb.php` (Unduh Bukti Bayar / STTS).
* **Baris 782**: `https://cektagihan.cianjurkab.v-tax.id/svcGenerateQrcode.php` (Generate QRIS BJB).
* **Baris 830**: `https://cektagihan.cianjurkab.v-tax.id/svcGenerateVA.php` (Generate Virtual Account).

### 2. `lib/staff_portal_client.dart`
* **Baris 23**: `https://cianjurkab.v-tax.id` (Portal Petugas Bapenda Cianjur).

### 3. `lib/kendaraan/kendaraan_client.dart` & `lib/kendaraan/kendaraan_view.dart`
* `baseUrl = 'https://sambara-v2.bapenda.jabarprov.go.id'` (Gateway Pajak Kendaraan Sambara Bapenda Jabar).
* Baris 344: Informasi PKB Jabar `https://jabarprov.go.id/layanan/pembayaran-pajak-kendaraan-bermotor-pkb-1690533115`.
* Baris 355: Hotline WA Sambara `https://wa.me/6281122301818`.

### 4. `lib/desil/bansos_client.dart`
* **Baris 104**: `https://cekbansos.kemensos.go.id` (Portal Cek Bansos Kemensos RI).

### 5. `lib/update_checker.dart` & `lib/settings/about_app_screen.dart`
* `_githubOwner = 'IkbalGumilar'`; `_githubRepo = 'Cek-PBB-Cianjur'`.
* `https://api.github.com/repos/IkbalGumilar/Cek-PBB-Cianjur/releases`.
* `https://saweria.co/IkbalGumilar`.

### 6. `lib/cloud_sync/google_drive_service.dart` & `lib/google_auth_service.dart`
* Endpoint Google Drive API: `https://www.googleapis.com/drive/v3/files`.
* Endpoint OAuth2 Token: `https://oauth2.googleapis.com/token`.

### 7. `lib/connectivity_monitor.dart`
* **Baris 18**: `https://www.gstatic.com/generate_204` (Probe koneksi internet aktif).

### 8. `lib/bank_launcher.dart`
* **Baris 17–43**: Daftar 22 nama paket aplikasi Android (*package name*) perbankan & dompet digital (BJB DIGI `com.bjb.digi`, BCA Mobile `com.bca.mybca`, BRImo `id.co.bri.brimo`, Livin `com.bankmandiri.livin`, DANA `id.dana`, dll.).

---

## Kategori D: Kunci Kriptografi & Secret Enkripsi Bawaan
Kunci rahasia statis yang dipakai untuk kompatibilitas enkripsi paket berkas `.dkhp` lama.

### 1. `lib/dhkp/dhkp_crypto.dart`
* **Baris 20**: `_legacySecret = 'CekPBBCianjur-DKHP-Package-Secret-v1'` (Secret bawaan paket .dkhp lama tanpa password kustom).
* **Baris 14–15**: Magic Header byte: `[0x44, 0x4B, 0x48, 0x50]` ("DKHP") dan `[0x44, 0x4B, 0x48, 0x32]` ("DKH2").

### 2. `lib/backup_crypto.dart`
* **Baris 16**: `_appSecret = 'CekPBBCianjur-BukuCatatanBlok-kunci-v1'` (Kunci turunan backup CSV legacy).

### 3. `lib/blok_sync_service.dart`
* **Baris 98**: `_defaultSecret = 'CekPBBCianjur-PerubahanLog-kunci-v1'` (Kunci sinkronisasi log audit perubahan blok).

### 4. `lib/kendaraan/kendaraan_client.dart`
* **Baris 137**: `_hmacSecret = '8jV2BITnbT3LCXVDd/Sa1P05m9BYvBMqK/zrvI0CvkQ='` (Secret HMAC validasi gateway Samsat Sambara).

---

## Kategori E: Konten Statis Aplikasi & Batasan Sistem
Kumpulan data statis yang sengaja dibundel di dalam aplikasi untuk kebutuhan offline.

### 1. `lib/cianjur_wilayah_data.dart`
* **Baris 27–595**: Katalog statis seluruh 32 Kecamatan dan 360+ Desa/Kelurahan se-Kabupaten Cianjur beserta 3 digit kode NOP-nya.
* **Evaluasi**: Rencana ke depan file ini **dieliminasi dari bundel aplikasi**. Aplikasi tidak perlu memikul katalog seluruh kecamatan se-kabupaten karena struktur kecamatan & daftar desa langsung disediakan secara dinamis oleh berkas `manifest.json` di dalam paket `.dkhp` yang diimpor.

### 2. `lib/petugas_quote_banner.dart`
* **Baris 21–700**: 100 kutipan motivasi, pengingat amanah, dan pepeling bahasa Sunda untuk petugas pemungut PBB di lapangan.

### 3. `lib/settings/user_guide_data.dart`
* **Baris 1–1145**: Konten lengkap buku panduan interaktif, bab, topik penjelasan, dan FAQ.

### 4. `lib/kolektif_nop_berkas.dart`
* **Baris 18**: `const maksBarisBerkas = 5000;` (Batas pengaman jumlah baris pembacaan berkas daftar NOP).

### 💡 Solusi Dinamisasi Kategori E: Eliminasi Kamus Statis Wilayah
* **Kamus 32 Kecamatan (`cianjur_wilayah_data.dart`)**:
  * Tidak perlu dibundel permanen di dalam kode APK.
  * Aplikasi cukup membaca data kecamatan & daftar desa dari `manifest.json` pada paket `.dkhp` yang dimuat.
  * Ukuran kode aplikasi menjadi jauh lebih ramping (*lean*), modular, dan benar-benar agnostik terhadap wilayah mana pun.

---

## Tabel Rekapitulasi File

| No | File `.dart` | Kategori | Sifat Data | Dampak Dinamisasi |
|:---|:---|:---|:---|:---|
| 1 | [`lib/map/dhkp_map_screen.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/map/dhkp_map_screen.dart) | Peta & Geospasial | Koordinat Desa, Kantor Desa, GeoJSON | Mudah (dimuat dinamis via folder `peta/` di .dkhp) |
| 2 | [`lib/map/kml_parser.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/map/kml_parser.dart) | Peta & Geospasial | Poligon 5 Dusun Bobojong | Otomatis dinamis saat upload KML/GeoJSON dusun |
| 3 | [`lib/nop_helper.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/nop_helper.dart) | Wilayah Default | Bobojong / Mande (Kode 200/004) | Dinamis mengikuti desa aktif dari manifest DHKP |
| 4 | [`lib/dusun_data.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/dusun_data.dart) | Wilayah Default | 5 Dusun Bobojong & Blok 001-027 | Dinamis penuh dibaca dari manifest DHKP |
| 5 | [`lib/blok_record.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/blok_record.dart) | Wilayah Default | Fallback Bobojong / Mande | Membaca profil aktif sesi aplikasi |
| 6 | [`lib/dhkp/blok_csv_codec.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/dhkp/blok_csv_codec.dart) | Wilayah Default | Fallback Bobojong / Mande | Membaca profil aktif sesi aplikasi |
| 7 | [`lib/file_importer.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/file_importer.dart) | Wilayah Default | Fallback Bobojong / Mande | Membaca profil aktif sesi aplikasi |
| 8 | [`lib/staff_portal_client.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/staff_portal_client.dart) | Server & Wilayah | Endpoint V-Tax & default Bobojong | Otomatis ganti sesuai akun login |
| 9 | [`lib/pbb_client.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/pbb_client.dart) | Server API | Endpoint V-Tax Cianjur | Standar gateway resmi Cianjur (dipertahankan) |
| 10 | [`lib/kendaraan/kendaraan_client.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/kendaraan/kendaraan_client.dart) | Server & Kripto | Endpoint Sambara & HMAC Secret | Wajib statis agar lolos handshake Sambara |
| 11 | [`lib/desil/bansos_client.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/desil/bansos_client.dart) | Server API | Endpoint Cek Bansos Kemensos | Standar gateway resmi Kemensos |
| 12 | [`lib/update_checker.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/update_checker.dart) | Pembaruan | Repo GitHub IkbalGumilar | Standar repo rilis aplikasi |
| 13 | [`lib/bank_launcher.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/bank_launcher.dart) | Integrasi Bank | Package Name 22 Bank / E-Wallet | Kandidat intent Android |
| 14 | [`lib/dhkp/dhkp_crypto.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/dhkp/dhkp_crypto.dart) | Kriptografi | Legacy Secret v1 | Kompatibilitas mundur paket lama |
| 15 | [`lib/backup_crypto.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/backup_crypto.dart) | Kriptografi | App Secret v1 | Kompatibilitas mundur backup lama |
| 16 | [`lib/blok_sync_service.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/blok_sync_service.dart) | Kriptografi | Default Secret Log Sync | Proteksi integritas perubahan data |
| 17 | [`lib/cianjur_wilayah_data.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/cianjur_wilayah_data.dart) | Data Kamus | 32 Kecamatan & 360+ Desa | **Dieliminasi**: digantikan manifest DHKP |
| 18 | [`lib/petugas_quote_banner.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/petugas_quote_banner.dart) | Konten Teks | 100 Kata Mutiara Sunda | Koleksi offline penyemangat kerja |
| 19 | [`lib/settings/user_guide_data.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/settings/user_guide_data.dart) | Konten Panduan | Materi Panduan & FAQ | Dokumentasi panduan pengguna offline |
| 20 | [`lib/kolektif_nop_berkas.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/kolektif_nop_berkas.dart) | Batasan Sistem | Maksimal 5.000 baris file | Pengaman memori & rendering UI |

---

## Rekomendasi Langkah Lanjutan:
1. **Fitur Peta & Geospasial**:
   * Saat peta blok fisik Bapenda diperoleh (Senin), koordinat setiap persil akan dimasukkan melalui berkas KML/GeoJSON eksternal di dalam folder `peta/` pada paket `.dkhp`.
   * `authenticDusunZones` di `kml_parser.dart` dan koordinat pusat/kantor desa di `dhkp_map_screen.dart` digantikan sepenuhnya oleh data dari manifest dan poligon KML tersebut.
2. **Kamus Wilayah & Manifest**:
   * Kamus statis 32 kecamatan (`cianjur_wilayah_data.dart`) dipensiunkan/dilepas dari kode aplikasi.
   * Struktur kecamatan dan desa dibaca dinamis langsung dari `manifest.json` yang ada di dalam paket bundel `.dkhp`.
   * Aplikasi menjadi 100% agnostik wilayah, ringan, dan siap dipakai oleh kecamatan mana pun tanpa kompilasi ulang.
