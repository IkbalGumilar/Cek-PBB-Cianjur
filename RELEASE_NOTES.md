## 🌟 Ringkasan Rilis v0.1.5-beta

Pembaruan **Cek PBB Cianjur v0.1.5-beta (Build 11)** menghadirkan peningkatan arsitektur besar untuk mentransformasikan aplikasi menjadi platform GIS kadastral dan pengawasan PBB-P2 terpadu berskala kabupaten. 

Rilis ini membawa visualisasi peta spasial poligon GeoJSON dinamis, pengunduh dokumen STTS PDF massal otomatis dengan sinkronisasi cerdas (*delta sync*), analisis capaian realisasi bulanan interaktif, serta perluasan cakupan ke seluruh **32 Kecamatan dan 360 Desa/Kelurahan** di Kabupaten Cianjur.

---

## 🚀 Sorotan Fitur Baru & Peningkatan

### 1. 🗺️ Peta Spasial GIS & Pemetaan Objek Pajak Dinamis
* **Batas Wilayah Poligon GeoJSON Dinamis:** Menghapus seluruh dependensi koordinat desa statis/hardcoded. Aplikasi kini otomatis mengekstraksi batas poligon GeoJSON dan menghitung *bounding box* secara langsung di peta.
* **Penanda Kantor Desa Adaptif:** Marker Balai Desa otomatis tersembunyi secara cerdas jika koordinat referensi belum diatur pengguna.
* **Filter Kedusunan Mandiri (*Dynamic Dusun Chips*):** Pemilih chip dusun otomatis mengekstrak nomor dusun unik langsung dari data objek pajak aktif.
* **Visualisasi Titik Pajak (*Tax Dots WGS84*):** Rendering sebaran objek pajak berbasis koordinat autentik dengan indikator status visual yang jelas (*Sudah Bayar*, *Belum Bayar*, *Blacklist*, dan *Target Prioritas Pemda*).

### 2. ⚡ Pengecekan Massal & Pengunduhan STTS Digital Otomatis
* **Unduh STTS Digital Langsung:** Pengunduhan bukti bayar STTS PDF resmi kini terintegrasi langsung di layar Pengecekan Massal (`BatchCheckScreen`).
* **Sinkronisasi Hemat Kuota (*Delta Sync*):** Mekanisme cerdas hanya mengunduh file STTS untuk NOP yang terverifikasi LUNAS, menghemat kuota internet dan mencegah lonjakan beban ke server Bapenda.
* **Pengarsipan Subfolder Otomatis:** Berkas hasil pengecekan otomatis dikelompokkan ke dalam subfolder bertanggal per blok (`Blok_<nomor>/`), lengkap dengan file rekapitulasi `INFORMASI_BLOK_<nomor>.txt` dan arsip `.zip`.

### 3. 📊 Analisis Capaian Realisasi Bulanan & Penyortiran Cerdas
* **Lembar Rincian Bulanan (`DhkpRincianBulananSheet`):** Menu modal interaktif untuk membedah dinamika dan realisasi pembayaran pajak per bulan kalender.
* **Penyortiran Dinamis:** Kemudahan beralih urutan data secara instan berdasarkan kronologi tanggal bayar atau besaran nominal rupiah.
* **Ekspor Terstandarisasi:** Ekspor laporan capaian bulanan langsung ke format tabel CSV standar dan ringkasan teks rapi.

### 4. 🌐 Mesin Multi-Wilayah se-Kabupaten Cianjur (32 Kecamatan)
* **Cakupan Penuh Wilayah:** Mendukung penyiapan awal dan pengelolaan data untuk seluruh 32 kecamatan dan 360 desa/kelurahan di Kabupaten Cianjur.
* **Panduan Pengaturan Interaktif:** Wizard penyiapan wilayah adaptif (`StartupSetupScreen`) dan pengaturan wilayah (`WilayahSettingsScreen`) dengan penyimpanan lokal terenkripsi (*FlutterSecureStorage*).

### 5. 🔐 Penguatan Keamanan & Standar Kriptografi Modern
* **Format Paket DHKP V2 (`DKH2`):** Standar enkripsi baru menggunakan algoritma AES-256-GCM dengan penguatan derivasi kunci PBKDF2 (600.000 iterasi).
* **Autentikasi TOTP RFC 6238 Standar Industri:** Integrasi keamanan verifikasi dua langkah berbasis waktu (6 digit TOTP) lengkap dengan toleransi pergeseran waktu (*time-drift window*).

---

## 🛠️ Perbaikan Bug Kritis & Peningkatan Keandalan

* **Eliminasi Format Mata Uang Ganda:** Memperbaiki redundansi teks `"Rp Rp"` pada file ringkasan blok dengan parser mata uang terstandarisasi.
* **Sanitasi Nama Berkas Lintas Platform:** Membersihkan karakter kontrol baris baru (`\r`, `\n`) dan tabulasi (`\t`) pada nama wajib pajak guna mencegah kegagalan I/O pada Android Storage Access Framework (SAF) dan Windows.
* **Hierarki Subfolder Direktori Ekspor:** Memperbaiki direktori fallback ekspor pada pemeriksaan massal agar struktur subfolder bertanggal dan blok tetap terjaga.
* **Proteksi Inisialisasi PDF:** Membungkus parser `PdfDocument` dengan blok pengaman `try-catch` untuk menangkal crash saat menerima respons jaringan yang korup.
* **Normalisasi Tanggal Pembayaran:** Menghilangkan karakter baris baru liar pada hasil parsing tanggal pembayaran dari server portal.
* **Dynamic Chip Fallback:** Memperbaiki kestabilan chip dusun saat memuat paket data dengan metadata manifest minimal.

---

## 📦 Berkas Unduhan Rilis (Assets)

Seluruh paket biner rilis resmi tersedia di folder distribusi tunggal `dist/` dan siap diunduh:

| Nama Berkas | Platform / Arsitektur Target | Ukuran | Keterangan |
| :--- | :--- | :---: | :--- |
| `Cek-PBB-Cianjur-v0.1.5-beta-arm64-v8a.apk` | Android ARM 64-bit | 21.8 MB | Untuk smartphone Android modern |
| `Cek-PBB-Cianjur-v0.1.5-beta-armeabi-v7a.apk` | Android ARM 32-bit | 21.0 MB | Untuk smartphone Android lawas |
| `Cek-PBB-Cianjur-v0.1.5-beta-x86_64.apk` | Android x86_64 | 22.1 MB | Untuk emulator, ChromeOS, dan tablet Intel |
| `Cek-PBB-Cianjur-Setup-v0.1.5-beta.exe` | Windows Desktop x64 | 16.38 MB | Installer Resmi Inno Setup 7 (Shortcut & Uninstaller) |
| `Cek-PBB-Cianjur-Portable-v0.1.5-beta.zip` | Windows Desktop x64 | 20.07 MB | Paket portabel mandiri (tanpa perlu instalasi) |
| `Cek-PBB-Cianjur-Linux-x64-v0.1.5-beta.tar.gz` | Linux Desktop x64 | 18.0 MB | Paket portabel mandiri GTK3 terkompresi |

---

## 🔒 Nilai Hash Integritas Berkas (SHA-256 Checksums)

Gunakan daftar checksum resmi berikut untuk memverifikasi keaslian dan integritas berkas unduhan:

```
01140041304f1543729abeba2b7f78b8c5ac39cba1f313d06404c76af649ceb2  Cek-PBB-Cianjur-v0.1.5-beta-arm64-v8a.apk
88e515c62194ec02fc9bdf64aa5f1c6ed86810aef7c60f06268f1c40d4ce9223  Cek-PBB-Cianjur-v0.1.5-beta-armeabi-v7a.apk
69902c75b7cf8562a738941370fdd057d0c75640aa775af4b5ddbaaeb5aba067  Cek-PBB-Cianjur-v0.1.5-beta-x86_64.apk
348de085f4d74028571fe3d0cde9155b3e306cc855d3f52aefcb1a8173dbca1f  Cek-PBB-Cianjur-Setup-v0.1.5-beta.exe
242863b71eba773588c4909aa790de2bc69fe2fa194a53d773280ce9344d79f3  Cek-PBB-Cianjur-Portable-v0.1.5-beta.zip
ef81df554f6b378aefd3d783ece319af9d6c45d286bc88d667ae21cc4e691437  Cek-PBB-Cianjur-Linux-x64-v0.1.5-beta.tar.gz
```

---
*Diverifikasi & dikompilasi menggunakan Flutter 3.38+ / Dart 3.10+ (140/140 Unit & Widget Tests Lolos).*
