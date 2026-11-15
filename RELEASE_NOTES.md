## 🌟 Ringkasan Rilis v0.1.7-beta (Build 13)

Pembaruan **Cek PBB Cianjur v0.1.7-beta (`0.1.7-beta+13`)** merupakan rilis penyempurnaan menyeluruh dari **v0.1.6-beta** yang berfokus pada **keamanan kriptografi & validasi data, desain antarmuka responsif Mobile–Desktop dengan sistem gerak aksesibel, generator & pemecahan paket `.dkhp` terenkripsi per Kedusunan (`DKH2`) lintas 32 kecamatan, analitik grafik multi-entitas, manajemen pin peta spasial, serta perampingan ukuran paket rilis**.

Rilis ini sudah diverifikasi dengan **0 isu analisis statis (`flutter analyze`)** dan **266/266 Unit & Widget Tests lolos**, serta dikompilasi dalam mode rilis ramping (`--obfuscate --split-debug-info --tree-shake-icons` + *strip* simbol biner).

---

## ✨ Ditingkatkan & Fitur Baru (v0.1.6-beta → v0.1.7-beta)

### 1. 🎨 Sistem Desain Responsif, Tema AMOLED & Sistem Gerak (`AppDesignSystem` + `AppMotion`)
* **Sistem Desain Terpadu (`lib/ui/app_design_system.dart`)**: Penambahan breakpoint responsif resmi (`Mobile < 600dp`, `Tablet 600–1023dp`, `Desktop >= 1024dp`), wadah adaptif `ResponsivePageContainer`, komponen `AppSemanticColors` (kontras terjaga di mode Terang, Gelap, maupun Hitam AMOLED `#000000`), `AppStatusBadge`, `AppEmptyStateCard`, `AppAlertBanner`, serta filter lipat *Progressive Disclosure* (`AppCollapsibleFilterSection`).
* **Sistem Gerak Halus & Aksesibilitas (`AppMotion` & `unity_lerp_widgets.dart`)**: Transisi halaman seragam dan animasi progres angka, batang grafik, serta garis tren dengan dukungan penuh preferensi **Kurangi Animasi / Reduced Motion** (`MediaQuery.maybeDisableAnimationsOf`).
* **Penyempurnaan Tata Letak Sempit (`360dp`) & Ergonomi Desktop**: Menghilangkan pemotongan label di layar ponsel kecil (`CheckFormView`, `DesilView`, `KendaraanView`, `BlokCatatanScreen`, `MonitoringSummaryCards`, 7 tab Pantauan Wilayah, dan Kolektif), sekaligus mengoptimalkan navigasi *drag* mouse/trackpad serta pintasan keyboard `Ctrl+P` / `Ctrl+C` di Desktop.

### 2. 🔐 Generate DHKP Universal, Pecah Paket per Kedusunan (`DKH2`) & Validasi Sandi Awal
* **Pecah Otomatis `.dkhp` per Dusun (`DhkpPackageHelper.packSplitDkhpByDusun`)**: Mendukung pemecahan data DHKP desa menjadi berkas `.dkhp` terenkripsi `DKH2` (`AES-256-GCM`, PBKDF2 600.000 iterasi) terpisah per kedusunan (misal 3 dusun maupun 5 dusun beserta Master Desa) lengkap dengan metadata `scope` wilayah di `manifest.json`.
* **Resolusi Wilayah Dinamis se-Kabupaten (`CianjurWilayahData` & `NopHelper`)**: Ekstraksi otomatis kode 3/7/10 digit kecamatan/desa untuk seluruh 32 kecamatan dan 337 desa/kelurahan tanpa ketergantungan nama wilayah hardcoded, serta dukungan memuat konfigurasi dari `manifest.json` paket `.dkhp` sebelumnya.
* **Validasi Sandi Enkripsi Minimal 8 Karakter Sejak Awal**: `DhkpCrypto.validateOptionalPassword` dan dialog **Generate DHKP Baru** kini menampilkan keterangan syarat minimal 8 karakter secara jelas sejak awal, langsung memfokuskan kolom sandi, dan memblokir proses sebelum memanggil Portal Staf atau menimpa data lokal jika sandi terlalu pendek.
* **Sinkronisasi Portal Staf Lebih Menyeluruh (`StaffDhkpSyncService`)**: Peningkatan sinkronisasi status lunas/belum lunas, metadata SPPT, dan penegakan ketat ruang lingkup kedusunan.

### 3. 📊 Analitik Grafik Multi-Entitas, Pratinjau Dokumen & Manajemen Pin Peta
* **Analitik Tren & Ringkasan DHKP Lanjutan (`DhkpGrafikView` & `DhkpGrafikAnalytics`)**: Penambahan *Semi-Circular Gauge*, *Mini Sparkline* KPI, tren pembayaran Jan–Des dengan mode **Per Dusun**, **Per Blok** (Top 5 Tertinggi, 5 Terendah, Pilih Manual maks 6 blok), **Per Desa dalam 1 Kecamatan** (maks 5 desa), serta perbandingan **Lintas Tahun**.
* **Manajemen Pin Peta & KML (`MapPinStore` & `MapNopPickerDialog`)**: Penyimpanan pin koordinat GPS multi-NOP dalam JSON lokal, dialog pemilih NOP langsung di peta, penggabungan impor pin, serta ekspor/impor KML.
* **Kalkulator Pajak & Pembaca Dokumen Terpadu**: Penguatan `DhkpNopKalkulatorDialog` (denda 1% vs 2%, tabungan cicilan & TTD digital WP, simulasi AJB/BPHTB) dan penyatuan alur pratinjau/cetak (`DocumentPreviewScreen`, `KolaseFotoScreen`, kartu hasil cek PBB) lengkap dengan *Unified Print* dan pintasan `Ctrl+P`.

### 4. 🛡️ Penguatan Keamanan Berlapis & Keandalan Siklus Hidup
* **Enkripsi V2 Berkas Sinkronisasi Perubahan (`CPBB` AES-256-GCM)**: Penggantian enkripsi legacy tiket perubahan `.bin` di `BlokSyncService` ke format terautentikasi AES-256-GCM dengan header AAD + PBKDF2 100.000 iterasi.
* **Isolasi Penuh `FlutterSecureStorage` & Backoff Lockout**: Seluruh hash kredensial, rahasia TOTP, `BackupPasswordStore`, dan penghitung kegagalan kunci layar hanya disimpan di keyring terenkripsi (`android:allowBackup="false"`) dengan *exponential backoff* persisten (30 detik hingga 30 menit).
* **Sanitasi Ekspor, Proteksi Jaringan & Self-Updater Terverifikasi**:
  * Anti *Formula Injection* (`=`, `+`, `-`, `@`, tab, newline) pada ekspor CSV/XLSX (`BaseTableExporter`, `BlokCsvCodec.encodeReportCsv`) serta *XML/CDATA escaping* pada KML (`KmlParser`).
  * Pencegahan *open redirect* (`StaffPortalClient.normalizeRedirectLocation`), validasi ketat tautan Google Drive, API geolokasi HTTPS murni (`LocationService`), pengamanan server OAuth loopback (`GoogleAuthService`), serta verifikasi **SHA-256 + magic bytes header + directory confinement** pada pembaruan mandiri (`UpdateChecker` / `ApkInstaller`).
  * Perbaikan pembersihan `TextEditingController.dispose()`, guard `mounted` setelah `await`, validasi inline di Pengaturan Keamanan, dan perbaikan keandalan dropdown wilayah pemantauan (`BankDropdown` / `DesaKelurahanDropdown`).

### 5. 🚀 Dokumentasi, Otomatisasi Windows & Perampingan Build
* **Galeri Perbandingan Mobile & Desktop + Panduan Windows**: `README.md` diperbarui dengan galeri berdampingan (22 Mobile + 58 Desktop screenshot) dan penambahan [`BUILD_WINDOWS.md`](BUILD_WINDOWS.md) lengkap dengan skrip dinamis [`tool/sync_windows_plugins.dart`](tool/sync_windows_plugins.dart).
* **Kompilasi Ramping & Terobfuskasi**: Penerapan `--obfuscate --split-debug-info --tree-shake-icons` + *R8 shrinking/minification* (Android) + `strip --strip-unneeded` (Linux) + filter bebas simbol debug pada [`tool/build_windows.bat`](tool/build_windows.bat) dan [`windows/installer.iss`](windows/installer.iss).

---

## 🔄 Diubah

* **Kenaikan Versi & Identitas Rilis**: Versi dinaikkan dari `0.1.6-beta` menjadi **`0.1.7-beta+13`** pada [`pubspec.yaml`](pubspec.yaml), [`windows/installer.iss`](windows/installer.iss) (`0.1.7.13`), [`tool/build_windows.bat`](tool/build_windows.bat), [`BUILD_WINDOWS.md`](BUILD_WINDOWS.md), dan [`README.md`](README.md).
* **Pembatasan Eksplisit Aset Bundel (`pubspec.yaml`)**: Mengganti entri folder `- assets/guide/` menjadi daftar eksplisit hanya **19 berkas `.webp`** yang dipakai aktif dan **5 berkas `.geojson`** yang dimuat peta.
* **Sinkronisasi Plugin Windows Dinamis (`tool/sync_windows_plugins.dart`)**: Diubah dari daftar statis & path lokal menjadi deteksi dinamis lewat `.flutter-plugins-dependencies` dan variabel lingkungan `%PUB_CACHE%` / `%LOCALAPPDATA%`.
* **Pipeline Rilis Windows (`tool/build_windows.bat`, `windows/installer.iss`, `.github/workflows/build-windows.yml`)**: Diubah agar otomatis menjalankan `--obfuscate --split-debug-info=build\symbols\windows --tree-shake-icons`, menyapu `*.pdb`/`*.ilk`/`*.exp`/`*.lib`/`*.obj`/`kernel_blob.bin` sebelum pengemasan, serta melaporkan ukuran Staging, ZIP, EXE, dan 5 berkas terbesar.
* **Layanan Geolokasi IP (`LocationService`)**: Endpoint HTTP teks biasa diganti ke endpoint HTTPS tervalidasi.

---

## 🗑️ Dihapus

* **Dependensi Paket Tak Terpakai (`pubspec.yaml`)**: Menghapus `cupertino_icons` (menghilangkan aset font `CupertinoIcons.ttf` dari seluruh paket biner) dan `timezone`.
* **Berkas Kode Mati (`lib/`)**: Menghapus `lib/captcha_ocr_helper.dart` dan `lib/wilayah_kerja_picker.dart` yang tidak pernah dipanggil oleh modul aktif maupun pengujian.
* **Aset Tak Terpakai di Bundel Aplikasi (`pubspec.yaml`)**:
  * Menghapus 3 berkas panduan dari bundel (`19_pengaturan_panduan.webp`, `21_kebijakan_privasi.webp`, `22_syarat_ketentuan.webp`).
  * Menghapus 3 berkas GeoJSON tak terpakai dari bundel (`bobojong_dusun_zones.geojson`, `bobojong_fasum_osm.geojson`, `bobojong_kampung_osm.geojson`).
* **Hardcode & Residu Tidak Aman**:
  * Menghapus nilai bawaan wilayah palsu `'MANDE'`/`'BOBOJONG'` di `BlokCsvCodec`.
  * Menghapus penyalinan rahasia ke `SharedPreferences` teks biasa serta kunci statis pada enkripsi baru log perubahan `CPBB` v2.
  * Menghapus hardcode path `Z:\`, jeda prompt manual di `tool/build_windows.bat`, serta `262 MB+` cache mati (`windows/flutter/ephemeral_old/`, `ephemeral_trash/`, `tool/__pycache__/`).

---

## 📦 Berkas Unduhan Rilis (Assets)

Seluruh 6 berkas rilis resmi tersedia di direktori `dist/` dengan kompilasi ramping (`--obfuscate --split-debug-info --tree-shake-icons`, simbol debug terpisah di `build/symbols/`):

| Nama Berkas | Platform / Arsitektur Target | Ukuran | Keterangan |
| :--- | :--- | :---: | :--- |
| `Cek-PBB-Cianjur-v0.1.7-beta-arm64-v8a.apk` | Android ARM 64-bit | 20.69 MB (19.73 MiB) | Split APK teroptimasi untuk smartphone Android 64-bit modern |
| `Cek-PBB-Cianjur-v0.1.7-beta-armeabi-v7a.apk` | Android ARM 32-bit | 19.72 MB (18.81 MiB) | Split APK teroptimasi untuk smartphone Android 32-bit |
| `Cek-PBB-Cianjur-v0.1.7-beta-x86_64.apk` | Android x86_64 | 20.95 MB (19.98 MiB) | Split APK untuk emulator, ChromeOS, dan tablet x86_64 |
| `Cek-PBB-Cianjur-Setup-v0.1.7-beta.exe` | Windows Desktop x64 | 16.22 MB (15.47 MiB) | Installer Resmi Inno Setup (Shortcut & Smart Uninstaller) |
| `Cek-PBB-Cianjur-Portable-v0.1.7-beta.zip` | Windows Desktop x64 | 19.67 MB (18.76 MiB) | Paket portabel mandiri x64 (siap ekstrak & jalankan) |
| `Cek-PBB-Cianjur-Linux-x64-v0.1.7-beta.tar.gz` | Linux Desktop x64 | 16.96 MB (16.18 MiB) | Arsip biner portabel GTK3 terkompresi (`44 MB` saat diekstrak) |

> [!NOTE]
> Ukuran berkas ikon terpangkas otomatis melalui *tree-shaking*: `MaterialIcons-Regular.otf` menyusut 96,5% (`1.645.184` → `58.372` byte di APK / `57.984` byte di Linux) dan `Font-Awesome-7-Brands-Regular-400.otf` menyusut 99,1% (`215.132` → `1.956` byte di APK).

---

## 🔒 Nilai Hash Integritas Berkas (SHA-256 Checksums)

Disimpan di `dist/Cek-PBB-Cianjur-v0.1.7-beta-checksums.sha256`:

```text
ebbcc2a14d9573b55c828fc1631b05eccd8e94907b13bb02d5da53bee34e8ea9  Cek-PBB-Cianjur-v0.1.7-beta-arm64-v8a.apk
a15285a611af7e676cc2147721725b1cbdccd3541b8caca3ede2014e6c46f5ee  Cek-PBB-Cianjur-v0.1.7-beta-armeabi-v7a.apk
b9dff54c423238e93ff0afc1761a5956dd7bb59ce64c695de617fa3ae222aaa8  Cek-PBB-Cianjur-v0.1.7-beta-x86_64.apk
0b2bd276740f2e6dceb0a75313f60ba76fb3ec202ea8d141adbc141614865164  Cek-PBB-Cianjur-Setup-v0.1.7-beta.exe
d41297b6c799dc44d2a83d1e4ca76e5edd90630b391068c64b81d03ba57cd369  Cek-PBB-Cianjur-Portable-v0.1.7-beta.zip
e761be68170a7fa33df99fa40db48df8f4c953f6f7cb370d6aa542652c1ee38c  Cek-PBB-Cianjur-Linux-x64-v0.1.7-beta.tar.gz
```

---
*Diverifikasi & dikompilasi menggunakan Flutter 3.47.5 / Dart 3.13.4 (`flutter analyze`: 0 isu; `flutter test`: 266/266 Unit & Widget Tests lolos).*
