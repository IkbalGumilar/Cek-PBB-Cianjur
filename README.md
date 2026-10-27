# Cek PBB Cianjur

[![Version](https://img.shields.io/badge/Version-v0.1.1--beta-orange.svg)](https://github.com/IkbalGumilar/Cek-PBB-Cianjur/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-green.svg)]()
[![Security](https://img.shields.io/badge/Security-AES--256--GCM%20%7C%20PBKDF2-red.svg)]()
[![License](https://img.shields.io/badge/License-Open%20Source-blue.svg)](LICENSE)

Aplikasi manajemen, pengecekan, dan monitoring Pajak Bumi dan Bangunan Perdesaan dan Perkotaan (PBB-P2) yang dirancang khusus untuk memfasilitasi kerja kolektor dan staf desa/kelurahan di Kabupaten Cianjur. Aplikasi ini terhubung langsung secara terenkripsi ke portal resmi BAPENDA Kabupaten Cianjur tanpa memerlukan navigasi manual antarmuka peramban web.

> [!NOTE]
> **Distribusi Mandiri (Sideload)**  
> Aplikasi ini tidak didistribusikan melalui Google Play Store atau Apple App Store. Distribusi berkas resmi dilakukan secara internal melalui [GitHub Releases](https://github.com/IkbalGumilar/Cek-PBB-Cianjur/releases/latest) berupa paket APK teroptimasi per arsitektur (*Split per ABI*) untuk Android serta paket biner mandiri untuk Windows dan Linux.

---

## Daftar Isi
- [Fitur Utama](#-fitur-utama)
- [Arsitektur Keamanan](#-arsitektur-keamanan)
- [Matriks Dukungan Platform](#-matriks-dukungan-platform)
- [Panduan Modul Aplikasi](#-panduan-modul-aplikasi)
  - [1. Pengecekan PBB-P2 & Pembayaran](#1-pengecekan-pbb-p2--pembayaran)
  - [2. Manajemen Data DHKP & Buku Catatan Blok](#2-manajemen-data-dhkp--buku-catatan-blok)
  - [3. Kolase Foto SPPT / Objek Pajak](#3-kolase-foto-sppt--objek-pajak)
  - [4. Sinkronisasi & Integrasi Google Drive](#4-sinkronisasi--integrasi-google-drive)
  - [5. Monitoring Wilayah & Portal Staf (MFA)](#5-monitoring-wilayah--portal-staf-mfa)
  - [6. Cek Desil & Bantuan Sosial (Kemensos)](#6-cek-desil--bantuan-sosial-kemensos)
  - [7. Cek Pajak Kendaraan Bermotor (Jawa Barat)](#7-cek-pajak-kendaraan-bermotor-jawa-barat)
  - [8. Kustomisasi Tema & Tampilan](#8-kustomisasi-tema--tampilan)
- [Alur Pembaruan Otomatis](#-alur-pembaruan-otomatis)
- [Panduan Pengembangan & Kompilasi](#-panduan-pengembangan--kompilasi)
- [Pernyataan Privasi & Penafian](#-pernyataan-privasi--penafian)

---

## 🌟 Fitur Utama

- **Pengecekan NOP Cepat & Akurat**: Cukup ketik format ringkas Blok dan Nomor Wilayah (misal: Blok `1` Nomor `1`), sistem otomatis memformat menjadi NOP 18 digit resmi BAPENDA (`32.03...`).
- **Pembayaran Multi-Kanal**:
  - **QRIS Dinamis**: Kode QR berlaku 1 jam sekali pakai, kompatibel dengan seluruh aplikasi dompet digital & m-banking di Indonesia (semua platform).
  - **Virtual Account Bank BJB**: Pembuatan nomor VA instan dengan integrasi pembuka aplikasi perbankan lokal yang terpasang di perangkat *(khusus Android)*.
- **Manajemen DHKP (Daftar Himpunan Ketetapan Pajak)**:
  - Pelacakan 4 indikator metrik utama: **Sudah Bayar**, **Belum Bayar**, **Target Pemda**, dan **Blacklist (Menunggak ≥ 5 Tahun)**.
  - Pencatatan riwayat penagihan, status objek pajak, foto lokasi/bukti bayar dengan zoom interaktif, dan penambahan catatan khusus kolektor.
  - **Ekspor Kolase Foto**: Penggabungan foto objek pajak/SPPT per blok ke dalam dokumen laporan siap cetak atau dibagikan ke instansi pembina.
- **Asosiasi Berkas Cerdas (WhatsApp & File Manager)**:
  - Berkas arsip `.dkhp`, `.dhkp`, maupun laporan perubahan `.dat` dapat diketuk langsung dari chat WhatsApp atau pengelola berkas Android untuk membuka aplikasi dan memuat/memulihkan data secara otomatis via Intent-Filter native.
- **Sinkronisasi Multi-Petugas & Cloud Backup**:
  - Terintegrasi langsung dengan Google Drive API untuk mengunduh dan menyinkronkan data antar-kolektor.
  - Protokol delta sync terenkripsi untuk penggabungan perubahan catatan tanpa menimpa data rekan kerja.
  - Penjadwalan cadangan harian otomatis berkala (pukul 02:00) dengan kebijakan rotasi retensi 3 berkas terlama.
- **OCR Offline Lokal (Edge ML)**:
  - Pemindaian berkas NOP dari gambar fisik STTS/SPPT tanpa memerlukan koneksi internet *(khusus Android)*.
  - Pemindaian KTP/KK untuk input NIK 16 digit pada modul Bansos.
  - Pemindaian Plat Nomor Kendaraan (TNKB) dengan deteksi warna permukaan plat.
- **Portal Monitoring Staf BAPENDA**:
  - Akses aman berbasis kredensial staf + autentikasi dua faktor (Google Authenticator MFA).
  - Monitoring piutang, realisasi per wilayah (Kecamatan/Kelurahan), rangking realisasi, dan pencetakan surat pengantar pembayaran kolektif.
- **Kemanan Sistem Berlapis**:
  - Proteksi kunci biometrik (sidik jari/wajah), PIN 6-digit terenkripsi, atau kata sandi aplikasi dengan auto-lockout cerdas.
  - Enkripsi arsip `.dkhp` standar militer (PBKDF2-HMAC-SHA256 600.000 iterasi + AES-256-GCM).
  - Pengaktifan `FLAG_SECURE` pada Android untuk mencegah perekaman layar dan tangkapan layar tanpa izin.
- **Performa Responsif & Efisiensi Penyimpanan**:
  - Distribusi biner terpisah (*Split-per-ABI*) menghasilkan ukuran aplikasi yang sangat ramping (~20-25 MB) sehingga menghemat memori penyimpanan dan kuota internet perangkat petugas di lapangan.
  - Animasi transisi pemuatan interaktif (*smooth activity & loading indicator*) pada seluruh alur kerja pengecekan NOP, pengelolaan DHKP, dan ekspor laporan.

---

## 🛡️ Arsitektur Keamanan

Aplikasi ini memprioritaskan kerahasiaan dan integritas data wajib pajak melalui implementasi standar kriptografi modern:

```
[Arsip Paket Data (.dkhp)]
         │
         ▼
[PBKDF2-HMAC-SHA256 (600.000 Iterasi + Salt Kriptografis)]
         │
         ▼ (Turunkan Kunci 256-bit)
[Enkripsi Terotentikasi: AES-256-GCM]
         │
         ├── Header AAD (Authenticated Additional Data: Magic Byte, Versi, Metadata)
         ├── Tag Autentikasi 128-bit (Pencegahan Manipulasi / Integritas Data)
         └── Data Terkompresi (CSV DHKP, Catatan Kolektor, Delta Sinkronisasi)
```

1. **Enkripsi Kunci & Arsip (`.dkhp`)**:
   - Seluruh data lokal dan cadangan diekspor menggunakan format kontainer terotentikasi AES-256-GCM.
   - Kata sandi master diolah menggunakan algoritma derivasi kunci **PBKDF2-HMAC-SHA256** dengan minimal **600.000 iterasi** dan salt acak unik per berkas.
   - Dilengkapi integritas header terverifikasi (*Authenticated Additional Data* / AAD); perubahan bit sekecil apa pun pada berkas akan ditolak otomatis.
2. **Penyimpanan Kredensial Aman**:
   - Kredensial sesi Portal Staf, kata sandi cadangan, dan hash PIN disimpan secara eksklusif di dalam **`FlutterSecureStorage`** (menggunakan Android Keystore System / Windows Credential Manager / Linux Secret Service / Keyring).
   - Pencegahan serangan brute-force PIN dengan penghitung kegagalan (*failed attempts counter*) persisten yang tidak dapat di-reset dengan menutup paksa aplikasi.
3. **Perlindungan Tampilan & Obfuscation**:
   - Mengaktifkan `FLAG_SECURE` pada *window manager* Android untuk menolak tangkapan layar (*screenshot*) dan perekaman layar (*screen recording*) pada area sensitif.
   - Proses kompilasi rilis memanfaatkan **R8 / ProGuard** (`isMinifyEnabled = true`, `isShrinkResources = true`) untuk mengacak struktur kode (*obfuscation*) dan mereduksi ukuran biner.

---

## 💻 Matriks Dukungan Platform

| Fitur / Modul | Android | Windows Desktop | Linux Desktop | Catatan |
|---|:---:|:---:|:---:|---|
| **Cek Tagihan & Status Bayar PBB** | ✅ | ✅ | ✅ | Berjalan penuh di semua platform |
| **Pembayaran QRIS Dinamis** | ✅ | ✅ | ✅ | Berlaku nasional via aplikasi e-wallet/bank apa pun |
| **Pembayaran Virtual Account (VA)** | ✅ | ❌ | ❌ | Tergantung *intent* pemanggil m-banking lokal di Android |
| **Manajemen DHKP & Catatan Blok** | ✅ | ✅ | ✅ | Sinkronisasi lokal & ekspor PDF/Excel/CSV |
| **Google Drive File Picker** | ✅ | ✅ | ✅ | Terintegrasi via Google Drive REST API |
| **Pencadangan Otomatis (02:00)** | ✅ | ✅ | ✅ | Berjalan di latar belakang dengan rotasi retensi |
| **Scan OCR (NOP, NIK, Plat Nomor)** | ✅ | ❌ | ❌ | Memanfaatkan engine Google ML Kit di perangkat |
| **Monitoring Portal Staf & MFA** | ✅ | ✅ | ✅ | Login terenkripsi dengan Google Authenticator |
| **Cek Desil & Bansos Kemensos** | ✅ | ✅ | ✅ | Input manual (semua OS) / Scan NIK (Android) |
| **Cek Pajak Kendaraan Jabar** | ✅ | ✅ | ✅ | Input manual (semua OS) / Scan Plat (Android) |
| **Kunci Biometrik / PIN / Password** | ✅ | ✅ | ✅ | Terintegrasi dengan sistem keamanan perangkat |
| **Buka Berkas (.dkhp, .dhkp, .dat)** | ✅ | ❌ | ❌ | Buka langsung dari WhatsApp / Pengelola Berkas Android |
| **Pembaruan Otomatis (In-App Update)** | ✅ | ⚠️ | ⚠️ | Android: Pasang mandiri (Auto-ABI); Desktop: Unduh biner |

---

## 📖 Panduan Modul Aplikasi

### 1. Pengecekan PBB-P2 & Pembayaran
1. Pilih tab **Cek Tagihan** atau **Cek Status Bayar** pada bilah menu atas.
2. Masukkan **Blok** dan **Nomor Wilayah** (tanpa angka nol pembuka). Sistem secara dinamis menghasilkan NOP 18 digit resmi.
3. Masukkan kode captcha yang tertera pada layar. Tekan tombol **Ganti Captcha** bila gambar tidak jelas.
4. Tekan **Cek**:
   - **Mode Cek Tagihan**: Menampilkan rincian tunggakan multi-tahun (Ketetapan Pokok, Denda, Sisa Kurang Bayar) dan opsi cetak STTS/SPPT.
   - **Mode Cek Status Bayar**: Menampilkan kartu status ringkas (*Lunas* atau *Belum Bayar*). Bila lunas, bukti bayar dapat langsung dicetak atau diunduh sebagai PDF.
5. **Pembayaran QRIS**: Tekan tombol *Bayar QRIS* pada baris tahun yang diinginkan. Pindai kode QR yang muncul menggunakan dompet digital atau aplikasi perbankan Anda.
6. **Pembayaran VA (Android)**: Tekan *Bayar VA*, salin nomor Virtual Account Bank BJB, lalu tekan ikon m-banking Anda untuk menyelesaikan transaksi.

### 2. Manajemen Data DHKP & Buku Catatan Blok
Akses tombol mengambang (FAB) berikon buku di pojok kanan bawah untuk membuka modul DHKP:
- **Filter 4 Metrik Instan**:
  - **Semua Data**: Menampilkan keseluruhan basis data DHKP blok wilayah kerja.
  - **Sudah Bayar**: Objek pajak yang telah terverifikasi lunas di sistem BAPENDA.
  - **Belum Bayar**: Objek pajak yang masih memiliki kewajiban pembayaran aktif.
  - **Target Pemda**: Wajib pajak dengan ketetapan prioritas pemantauan pemerintah daerah.
  - **Blacklist (≥ 5 Tahun)**: Wajib pajak dengan tunggakan kronis lebih dari 5 tahun berturut-turut.
- **Pembaruan Lapangan**: Kolektor dapat menambahkan foto objek/SPPT, menyematkan catatan penagihan khusus, dan memperbarui status langsung dari lapangan.
- **Mode Operator**: Dapat diaktifkan melalui menu Lisensi/Pengaturan untuk membuka pengawasan lintas dusun/wilayah tanpa batasan satu blok kerja.

### 3. Kolase Foto SPPT / Objek Pajak
Fitur khusus untuk pelaporan dokumentasi fisik penagihan:
1. Buka menu **Gabungkan Beberapa Gambar** dari layar DHKP.
2. Pilih cakupan wilayah atau blok kerja tertentu.
3. Sistem secara otomatis menyusun foto-foto objek pajak dan SPPT yang telah diunggah ke dalam tata letak kisi (*grid photo workstation*) yang rapi dan seragam.
4. Ekspor hasil kolase menjadi dokumen PDF beresolusi tinggi atau bagikan langsung ke pimpinan via WhatsApp/Email.

### 4. Sinkronisasi & Integrasi Google Drive
Menghubungkan data kerja antar-perangkat petugas secara aman:
- **Unggah Data Mandiri**: Kolektor dapat mengimpor berkas basis data DHKP baru dari penyimpanan internal atau langsung memilih berkas dari folder Google Drive tanpa bergantung pada pengelola berkas bawaan HP.
- **Sinkronisasi Delta**: Hanya mengirimkan dan mengunduh perbedaan catatan/status terbaru yang dibuat antar-petugas di lapangan.
- **Pencadangan Terjadwal**: Sistem secara otomatis mengekspor basis data terenkripsi setiap hari pada pukul 02:00 dini hari dan membatasi penyimpanan lokal maksimal 3 berkas cadangan teranyar.

### 5. Monitoring Wilayah & Portal Staf (MFA)
Modul administratif resmi bagi staf yang memiliki akun BAPENDA Cianjur:
- **Autentikasi Dua Langkah**: Dilengkapi verifikasi token berbasis waktu (TOTP) Google Authenticator dengan pintasan pembuka aplikasi otomatis.
- **7 Tab Rekap Wilayah**:
  1. *Sudah Bayar* (pencarian rentang tanggal realisasi, NOP, kolektor, atau bank).
  2. *Belum Bayar* (penghitungan akumulasi piutang hingga tanggal cutoff).
  3. *Realisasi*, *Piutang*, *Sudah Bayar Kolektif*, *Belum Bayar Kolektif*, dan *Rangking Realisasi Wilayah*.
- **Manajemen Pembayaran Kolektif**: Pembuatan grup penagihan draft, pengelolaan daftar anggota NOP (mendukung impor massal CSV/Excel dengan validasi pemisahan kolom NOP 18 angka), cetak surat pengantar, dan finalisasi penerbitan kode bayar resmi.

### 6. Cek Desil & Bantuan Sosial (Kemensos)
Terintegrasi untuk memverifikasi data kelayakan sosial warga:
- Masukkan 16 digit NIK atau gunakan fitur **Scan NIK (OCR Offline)** melalui kamera/galeri.
- Masukkan kode verifikasi captcha layanan DTSEN.
- Menampilkan status desil ekonomi serta kepesertaan bansos aktif: **Sembako / BPNT**, **Program Keluarga Harapan (PKH)**, **PBI-JK (BPJS Kesehatan Gratis)**, dan **KPD**.

### 7. Cek Pajak Kendaraan Bermotor (Jawa Barat)
Pengecekan kewajiban PKB Jawa Barat secara instan:
- Masukkan kode nomor polisi (huruf depan, angka, huruf belakang) dan pilih warna plat kendaraan.
- Mendukung pemindaian plat nomor otomatis via **Scan Plat (OCR Offline)**.
- Menampilkan rincian Pajak Kendaraan Bermotor (PKB), Bea Balik Nama (BBNKB), SWDKLLJ, PNBP STNK/TNKB, total tagihan, dan tanggal jatuh tempo pajak tahunan/lima tahunan.

### 8. Kustomisasi Tema & Tampilan
- **Kontras Tinggi Adaptif**: Bilah tab menu navigasi dirancang dengan pil putih bersih di mode terang dan kontainer gelap di mode gelap. Warna teks secara cerdas menyesuaikan tingkat kecerahan latar belakang (*"jika terang jadi gelap, jika kelam jadi terang"*), menjamin keterbacaan tajam dengan rasio kontras melebihi standar WCAG AAA.
- **Palet Warna Aksen**: Pengaturan warna aksen fleksibel dengan pilihan preset (Hijau PBB, Biru Cianjur, Ungu, Merah Marun, Oranye, Teal, Cokelat Kopi, Slate Gray) atau pengaturan bebas menggunakan pemilih RGB dinamis berbasis interpolasi lerp halus.
- **Pilihan Mode**: Mendukung mode *Terang*, *Gelap*, *Hitam AMOLED* murni untuk efisiensi daya layar OLED, serta *Material You* (Dynamic Color) pada Android 12+.

---

## 🚀 Alur Pembaruan Otomatis
 
Aplikasi dilengkapi mekanisme pemantauan rilis berkala yang terhubung ke REST API GitHub:
1. Pengecekan otomatis berjalan maksimal sekali setiap 24 jam saat aplikasi dibuka, atau dapat dipicu manual melalui **Pengaturan → Tentang Aplikasi → Periksa Pembaruan**.
2. **Deteksi Versi SemVer Cerdas**: Mendukung pembaruan rilis stabil maupun versi uji coba (`beta` / `alpha`), dengan pemfilteran nomor build (`+build`) dan proteksi dari berkas unduhan yang korup (`deleteOnError`).
3. **Pencocokan Arsitektur CPU (ABI-Aware APK)**: Pada Android, aplikasi mendeteksi arsitektur perangkat secara native (`Build.SUPPORTED_ABIS`) sehingga ponsel 64-bit modern otomatis mengunduh paket `arm64-v8a.apk`, ponsel 32-bit mengunduh `armeabi-v7a.apk`, dan emulator mengunduh `x86_64.apk`.
4. **Android**: Aplikasi mengunduh berkas `.apk` langsung ke cache privat, membuka installer sistem secara otomatis via `FileProvider`, dan menyediakan tombol buka ulang jika jendela konfirmasi sempat tertutup.
5. **Windows & Linux**: Aplikasi mengunduh paket biner rilis ke folder `Downloads/Cek PBB Cianjur` dan memberikan instruksi ekstraksi berkas kepada pengguna.

---

## 🛠️ Panduan Pengembangan & Kompilasi

### Prasyarat
- Flutter SDK versi `>= 3.22.0`
- Dart SDK versi `>= 3.4.0`
- Android Studio / Android SDK Platform Tools (API 34)
- GCC / Clang, CMake, Ninja, dan `libgtk-3-dev` (khusus build desktop Linux)
- Visual Studio Community dengan C++ Desktop Development (khusus build Windows)

### Langkah Kompilasi

1. **Kloning Repositori**:
   ```bash
   git clone https://github.com/IkbalGumilar/Cek-PBB-Cianjur.git
   cd Cek-PBB-Cianjur
   ```

2. **Pasang Dependensi**:
   ```bash
   flutter pub get
   ```

3. **Kompilasi Biner Rilis**:
   - **Android Split APK (Rekomendasi untuk efisiensi ukuran berkas)**:
     ```bash
     flutter build apk --release --split-per-abi
     ```
     Menghasilkan paket APK terpisah berdasarkan arsitektur CPU pada direktori `build/app/outputs/flutter-apk/`:
     - `app-arm64-v8a-release.apk` (Mayoritas smartphone Android 64-bit modern)
     - `app-armeabi-v7a-release.apk` (Perangkat Android 32-bit legacy)
     - `app-x86_64-release.apk` (Emulator / Tablet Intel)
   - **Android Universal APK (Berkas gabungan seluruh ABI)**:
     ```bash
     flutter build apk --release
     ```
   - **Linux Desktop**:
     ```bash
     flutter build linux --release
     ```
     Biner rilis dan pustaka pendukung dihasilkan di direktori `build/linux/x64/release/bundle/`. Dapat dipaketkan menjadi arsip `.tar.gz` portabel untuk distribusi mandiri.
   - **Windows Desktop**:
     ```bash
     flutter build windows --release
     ```
     Biner rilis dihasilkan di direktori `build/windows/x64/runner/Release/`.

> [!IMPORTANT]
> **Penandatanganan Rilis Android (Keystore)**  
> Kompilasi rilis Android membutuhkan konfigurasi berkas `android/key.properties` yang merujuk pada berkas keystore penandatanganan (`.jks`). Berkas ini tidak disertakan di dalam repositori demi menjaga integritas dan keamanan aplikasi. Jangan pernah mengganti keystore yang telah dipakai pada perangkat produksi agar pengguna tidak mengalami kegagalan saat memperbarui aplikasi.

---

## ⚖️ Pernyataan Privasi & Penafian

1. **Independensi Pengembang**: Aplikasi ini dikembangkan secara independen oleh pengembang sebagai alat bantu kerja operasional lapangan bagi petugas/kolektor desa di lingkungan Kabupaten Cianjur. Aplikasi ini bukan merupakan aplikasi resmi yang diterbitkan secara kelembagaan oleh Badan Pendapatan Daerah (BAPENDA) Kabupaten Cianjur.
2. **Kerahasiaan Data**: Seluruh pemrosesan teks, OCR dokumen, dan verifikasi NIK/NOP berlangsung secara luring (*on-device offline processing*) di perangkat masing-masing pengguna. Tidak ada data pribadi warga, dokumen KTP/KK, foto objek pajak, atau kata sandi yang dikirimkan ke peladen pihak ketiga selain transmisi resmi langsung ke portal BAPENDA dan Kemensos.
3. **Hak Cipta Layanan**: Hak cipta nama, logo daerah, serta infrastruktur portal layanan publik sepenuhnya merupakan milik Pemerintah Kabupaten Cianjur dan kementerian terkait.
