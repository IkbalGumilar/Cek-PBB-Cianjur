# Cek PBB Cianjur

[![Version](https://img.shields.io/badge/Version-v0.1.5--beta-orange.svg)](https://github.com/IkbalGumilar/Cek-PBB-Cianjur/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-green.svg)]()
[![Security](https://img.shields.io/badge/Security-AES--256--GCM%20%7C%20PBKDF2-red.svg)]()
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

Aplikasi manajemen, pengecekan, monitoring, dan pelaporan Pajak Bumi dan Bangunan Perdesaan dan Perkotaan (PBB-P2) yang dirancang khusus untuk memfasilitasi kerja kolektor dan staf desa/kelurahan di Kabupaten Cianjur. Aplikasi ini terhubung langsung secara terenkripsi ke portal resmi BAPENDA Kabupaten Cianjur tanpa memerlukan navigasi manual antarmuka peramban web.

> [!NOTE]
> **Distribusi Mandiri (Sideload & Multi-Platform)**  
> Aplikasi ini didistribusikan secara mandiri melalui [GitHub Releases](https://github.com/IkbalGumilar/Cek-PBB-Cianjur/releases/latest) berupa paket **APK teroptimasi per arsitektur (*Split per ABI*)** untuk Android, paket **Installer Mandiri Inno Setup (`.exe`)** & **Portable (`.zip`)** untuk Windows x64, serta paket biner portabel untuk Linux Desktop.

---

## 📱 Galeri Tangkapan Layar Aplikasi

<p align="center">
  <img src="docs/images/01_cek_tagihan.png" width="220" alt="Cek Tagihan PBB" />
  &nbsp;&nbsp;
  <img src="docs/images/02_cek_status_bayar.png" width="220" alt="Status Bayar & QRIS" />
  &nbsp;&nbsp;
  <img src="docs/images/10_pantauan_wilayah.png" width="220" alt="Monitoring Realisasi Wilayah" />
  &nbsp;&nbsp;
  <img src="docs/images/19_pengaturan_panduan.png" width="220" alt="Buku Panduan Interaktif" />
</p>

---

## Daftar Isi
- [Fitur Utama](#-fitur-utama)
- [Arsitektur Keamanan](#-arsitektur-keamanan)
- [Matriks Dukungan Platform](#-matriks-dukungan-platform)
- [Panduan Modul & Alur Kerja](#-panduan-modul--alur-kerja)
  - [1. Pengecekan PBB-P2 & Pembayaran Multi-Kanal](#1-pengecekan-pbb-p2--pembayaran-multi-kanal)
  - [2. Cek Banyak NOP Sekaligus & Unduh STTS Otomatis](#2-cek-banyak-nop-sekaligus--unduh-stts-otomatis)
  - [3. Manajemen DHKP, Kolase Foto & Penyimpanan "Save As"](#3-manajemen-dhkp-kolase-foto--penyimpanan-save-as)
  - [4. Peta Spasial Objek Pajak DHKP (Citra Satelit & KML)](#4-peta-spasial-objek-pajak-dhkp-citra-satelit--kml)
  - [5. Diagram Capaian & Rincian Pelunasan Bulanan](#5-diagram-capaian--rincian-pelunasan-bulanan)
  - [6. Multi-Wilayah (32 Kecamatan) & Startup Setup Wizard](#6-multi-wilayah-32-kecamatan--startup-setup-wizard)
  - [7. Monitoring Wilayah & Portal Staf (MFA Otomatis)](#7-monitoring-wilayah--portal-staf-mfa-otomatis)
  - [8. Pembayaran Kolektif & Surat Pengantar](#8-pembayaran-kolektif--surat-pengantar)
  - [9. Cek Pajak Kendaraan Bermotor (Jawa Barat)](#9-cek-pajak-kendaraan-bermotor-jawa-barat)
  - [10. Cek Desil & Bantuan Sosial (Kemensos)](#10-cek-desil--bantuan-sosial-kemensos)
  - [11. Layar Pembuka Resmi (Splash Screen)](#11-layar-pembuka-resmi-splash-screen)
  - [12. Buku Panduan Penggunaan & Pusat Bantuan Interaktif](#12-buku-panduan-penggunaan--pusat-bantuan-interaktif)
  - [13. Kustomisasi Tema, Keamanan & Pencadangan Data](#13-kustomisasi-tema-keamanan--pencadangan-data)
- [Alur Pembaruan Otomatis](#-alur-pembaruan-otomatis)
- [Panduan Pengembangan & Kompilasi](#-panduan-pengembangan--kompilasi)
- [Pernyataan Privasi & Penafian](#-pernyataan-privasi--penafian)

---

## 🌟 Fitur Utama

- **Pengecekan NOP Cepat & Akurat**: Cukup ketik format ringkas Blok dan Nomor Wilayah (misal: Blok `1` Nomor `1`), sistem otomatis memformat menjadi NOP 18 digit resmi BAPENDA (`32.03...`).
- **Pembayaran Multi-Kanal**:
  - **QRIS Dinamis**: Kode QR berlaku 1 jam sekali pakai, kompatibel dengan seluruh aplikasi dompet digital & m-banking di Indonesia (semua platform).
  - **Virtual Account Bank BJB**: Pembuatan nomor VA instan dengan integrasi pembuka aplikasi perbankan lokal yang terpasang di perangkat *(khusus Android)*.
- **Cek Massal & Pengunduhan STTS Per Blok Otomatis**:
  - Pengecekan status bayar ratusan NOP secara serentak dalam satu proses terpadu.
  - Opsi unduh berkas STTS otomatis bagi seluruh NOP yang telah lunas langsung ke folder blok bertanggal (`STTS Blok <blok> - <hari>, <tgl>-<bln>-<thn>`).
  - Pembuatan berkas ringkasan otomatis `INFORMASI_BLOK_<blok>.txt` yang memuat statistik penerimaan, status pelunasan, dan status pengunduhan file STTS per NOP.
- **Peta Spasial Objek Pajak DHKP (Google Satelit & KML)**:
  - Pemetaan titik objek pajak interaktif di atas citra satelit Google Maps langsung tanpa poligon dummy yang menutupi atap rumah.
  - Visualisasi kode warna status bayar: 🟢 Lunas, 🔴 Belum Bayar, 🟡 Multi-SPPT Sebagian, ⚫ Target Pemda.
  - Relasi spasial antara lokasi objek pajak dan alamat pemilik (garis trajektori dan penyorotan rumah pemilik jika objek terpisah).
  - Navigasi adaptif: tombol fokus batas wilayah dan fokus landmark kantor desa resmi hanya aktif saat koordinat sah tersedia.
- **Diagram Capaian & Rincian Pelunasan Bulanan**:
  - Visualisasi grafik capaian persentase, pendapatan masuk, sisa tagihan, dan tren bulanan ala Microsoft Excel / Power BI.
  - Rincian pelunasan bulanan interaktif: klik bulan tertentu untuk melihat daftar wajib pajak yang lunas lengkap dengan jam pelunasan dan 6 mode pengurutan fleksibel.
  - Mode Pas Layar (*Fit-to-Screen*) dan Mode Geser (*Scrollable*) dengan dukungan navigasi mouse desktop.
- **Sistem Penyimpanan "Save As" Bebas Izin**:
  - Seluruh ekspor dokumen (PDF, CSV, Excel, Kolase Foto, Backup `.dkhp`) menggunakan dialog native OS (*Storage Access Framework*).
  - Bebas memilih folder penyimpanan mana saja tanpa memerlukan izin akses penyimpanan runtime Android (`MANAGE_EXTERNAL_STORAGE`).
- **Dukungan Multi-Wilayah (32 Kecamatan se-Kabupaten Cianjur)**:
  - Wizard penyiapan awal (*Startup Setup Wizard*) interaktif bertahap dengan sapaan khas Sunda *"Sampurasun!"*.
  - Katalog lengkap seluruh 32 kecamatan dan desa se-Kabupaten Cianjur terurut alfabetis (A–Z).
  - Pengaturan wilayah mandiri dan peralihan desa cepat di menu utama.
- **Portal Monitoring Staf BAPENDA & Otomatisasi MFA**:
  - Akses aman bagi staf berwenang dengan autentikasi dua faktor (Google Authenticator MFA).
  - Generator TOTP lokal terenkripsi (RFC 6238) dengan fitur Auto-Login tanpa membuka aplikasi autentikator eksternal.
  - Mode sinkronisasi khusus pelunasan baru (*paidOnly*) dengan preset rentang tanggal (7 hari s/d 1 tahun) yang menghemat waktu sinkronisasi hingga 95%.
- **Buku Panduan & Pusat Bantuan Interaktif**:
  - Modul dokumentasi visual 19 bab dengan 84 titik pin koordinat interaktif, pencarian cepat, filter kategori, mode zoom layar penuh, dan FAQ lengkap.
- **Layar Pembuka (Splash Screen) Resmi & Elegan**:
  - Animasi pembuka resmi dengan lambang Kabupaten Cianjur dan identitas kelembagaan Bapenda, dilengkapi fitur *tap-to-skip*.
- **OCR Offline Lokal (Edge ML)**:
  - Pemindaian berkas NOP dari gambar fisik STTS/SPPT tanpa koneksi internet *(khusus Android)*.
  - Pemindaian KTP/KK untuk input NIK 16 digit pada modul Bansos.
  - Pemindaian Plat Nomor Kendaraan (TNKB) dengan deteksi warna permukaan plat.
- **Sinkronisasi Multi-Petugas & Cloud Backup**:
  - Terintegrasi langsung dengan Google Drive API untuk mengunduh dan menyinkronkan data antar-kolektor.
  - Protokol delta sync terenkripsi untuk penggabungan perubahan catatan tanpa menimpa data rekan kerja.
  - Penjadwalan cadangan harian otomatis berkala (pukul 02:00) dengan kebijakan rotasi retensi 3 berkas terlama.
- **Keamanan Sistem Berlapis**:
  - Proteksi kunci biometrik (sidik jari/wajah), PIN 6-digit terenkripsi, atau kata sandi aplikasi dengan auto-lockout cerdas.
  - Enkripsi arsip `.dkhp` standar militer (PBKDF2-HMAC-SHA256 600.000 iterasi + AES-256-GCM).
  - Pengaktifan `FLAG_SECURE` pada Android untuk mencegah perekaman layar dan tangkapan layar tanpa izin.

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
   - Dilengkapi integritas header terverifikasi (*Authenticated Additional Data* / AAD); manipulasi bit sekecil apa pun akan langsung ditolak sistem.
2. **Penyimpanan Kredensial Aman**:
   - Kredensial sesi Portal Staf, kata sandi cadangan, dan hash PIN disimpan eksklusif di dalam **`FlutterSecureStorage`** (menggunakan Android Keystore System / Windows Credential Manager / Linux Keyring).
   - Pencegahan serangan brute-force PIN dengan penghitung kegagalan (*failed attempts counter*) persisten yang kebal terhadap penutupan paksa aplikasi.
3. **Perlindungan Tampilan & Obfuscation**:
   - Mengaktifkan `FLAG_SECURE` pada *window manager* Android untuk memblokir tangkapan layar dan perekaman layar pada area data sensitif.
   - Kompilasi rilis memanfaatkan **R8 / ProGuard** (`isMinifyEnabled = true`, `isShrinkResources = true`) untuk mengacak struktur kode (*obfuscation*) dan memangkas ukuran biner.

---

## 💻 Matriks Dukungan Platform

| Fitur / Modul | Android | Windows Desktop | Linux Desktop | Catatan |
|---|:---:|:---:|:---:|---|
| **Cek Tagihan & Status Bayar PBB** | ✅ | ✅ | ✅ | Berjalan penuh di semua platform |
| **Pembayaran QRIS Dinamis** | ✅ | ✅ | ✅ | Berlaku nasional via aplikasi e-wallet/m-banking |
| **Pembayaran Virtual Account (VA)** | ✅ | ❌ | ❌ | Tergantung *intent* pemanggil m-banking lokal Android |
| **Cek Massal & Unduh STTS Otomatis** | ✅ | ✅ | ✅ | Pengunduhan batch STTS & pembuatan rekap TXT blok |
| **Manajemen DHKP & Catatan Blok** | ✅ | ✅ | ✅ | Sinkronisasi lokal & ekspor PDF/Excel/CSV |
| **Peta Spasial DHKP (Satelit & KML)** | ✅ | ✅ | ✅ | Pemetaan koordinat, trajektori alamat & status warna |
| **Diagram Capaian & Rincian Bulanan** | ✅ | ✅ | ✅ | Mode Pas Layar/Geser, rincian lunas & 6 mode sortir |
| **Penyimpanan Bebas Izin ("Save As")** | ✅ | ✅ | ✅ | Dialog native SAF/OS tanpa izin runtime berlebih |
| **Dukungan Multi-Wilayah (32 Kec)** | ✅ | ✅ | ✅ | Wizard penyiapan awal & katalog lengkap Cianjur |
| **Monitoring Portal Staf & MFA Otomatis**| ✅ | ✅ | ✅ | Login terenkripsi dengan generator TOTP lokal aman |
| **Buku Panduan Interaktif** | ✅ | ✅ | ✅ | 19 bab tutorial, 84 pinpoint visual, FAQ |
| **Tur Fitur Spotlight 60 FPS** | ✅ | ✅ | ✅ | Mengikuti target scroll secara dinamis |
| **Google Drive File Picker** | ✅ | ✅ | ✅ | Terintegrasi via Google Drive REST API |
| **Pencadangan Otomatis (02:00)** | ✅ | ✅ | ✅ | Berjalan di latar belakang dengan rotasi retensi |
| **Scan OCR (NOP, NIK, Plat Nomor)** | ✅ | ❌ | ❌ | Memanfaatkan engine Google ML Kit di perangkat |
| **Cek Desil & Bansos Kemensos** | ✅ | ✅ | ✅ | Input manual (semua OS) / Scan NIK (Android) |
| **Cek Pajak Kendaraan Jabar** | ✅ | ✅ | ✅ | Input manual (semua OS) / Scan Plat (Android) |
| **Kunci Biometrik / PIN / Password** | ✅ | ✅ | ✅ | Terintegrasi dengan sistem keamanan perangkat |
| **Buka Berkas (.dkhp, .dhkp, .dat)** | ✅ | ❌ | ❌ | Buka langsung dari WhatsApp / Pengelola Berkas Android |
| **Pembaruan Otomatis (In-App Update)** | ✅ | ✅ | ⚠️ | Android: Pasang mandiri (Auto-ABI); Windows: Auto-exec EXE |

---

## 📖 Panduan Modul & Alur Kerja

### 1. Pengecekan PBB-P2 & Pembayaran Multi-Kanal

Modul utama untuk memeriksa ketetapan pajak perorangan dan memproses pembayaran resmi secara instan.

| Cek Tagihan Rinci | Cek Status Bayar Ringkas |
| :---: | :---: |
| <img src="docs/images/01_cek_tagihan.png" width="280" alt="Cek Tagihan PBB-P2" /> | <img src="docs/images/02_cek_status_bayar.png" width="280" alt="Cek Status Bayar PBB-P2" /> |

1. Masukkan **Blok** dan **Nomor Wilayah** (sistem otomatis melengkapi kode 18 digit resmi `32.03...`).
2. Masukkan kode captcha, lalu tekan **Cek**:
   - **Mode Cek Tagihan**: Menampilkan rincian tunggakan multi-tahun (Ketetapan Pokok, Denda, Sisa Kurang Bayar, Jatuh Tempo) dan opsi cetak SPPT/STTS.
   - **Mode Cek Status Bayar**: Menampilkan kartu status ringkas (*Lunas* atau *Belum Bayar*). Bukti bayar dapat langsung dicetak atau diunduh sebagai PDF resmi.
3. **Pembayaran QRIS**: Tekan tombol *Bayar QRIS* pada baris tahun yang diinginkan. Pindai kode QR menggunakan dompet digital (GoPay, OVO, Dana, ShopeePay) atau m-banking.
4. **Pembayaran VA (Android)**: Tekan *Bayar VA*, salin nomor Virtual Account Bank BJB, lalu tekan pintasan aplikasi m-banking.

---

### 2. Cek Banyak NOP Sekaligus & Unduh STTS Otomatis

Memfasilitasi penagihan massal per RT/RW atau kelompok wajib pajak dalam satu langkah praktis dengan otomasi pengarsipan berkas.

<p align="center">
  <img src="docs/images/03_cek_banyak_nop.png" width="300" alt="Cek Banyak NOP Sekaligus" />
</p>

- **Pengecekan Paralel Cepat**: Masukkan daftar NOP atau nomor wilayah secara beruntun. Sistem mengeksekusi pengecekan multi-thread secara efisien.
- **Opsi Unduh STTS Otomatis**:
  - Saat saklar *Unduh dengan STTS* diaktifkan sebelum memulai cek, sistem memunculkan dialog penyimpanan (*Save As*) untuk memilih lokasi folder penyimpanan (misalnya folder `Download`).
  - Aplikasi secara otomatis membuat subfolder terstruktur per blok bertanggal:
    `STTS Blok <blok> - <Hari>, <tgl>-<bln>-<thn>` (contoh: `STTS Blok 001 - Minggu, 08-11-2026`).
  - Untuk setiap NOP yang berstatus lunas, sistem otomatis mengunduh salinan berkas resmi Surat Tanda Terima Setoran (STTS) dalam format PDF langsung ke dalam subfolder tersebut.
- **Ringkasan Catatan Blok (`INFORMASI_BLOK_<blok>.txt`)**:
  - Di dalam subfolder hasil unduhan, aplikasi menyusun berkas laporan teks komprehensif berisi statistik penerimaan blok, rekap jumlah lunas vs belum bayar, total rupiah realisasi, serta catatan status keberhasilan pengunduhan berkas STTS per wajib pajak.

---

### 3. Manajemen DHKP, Kolase Foto & Penyimpanan "Save As"

Buku kerja digital bagi kolektor desa untuk mencatat realisasi lapangan, foto objek pajak, riwayat penagihan, dan ekspor dokumen mandiri.

<p align="center">
  <img src="docs/images/06_dhkp_catatan.png" width="320" alt="Buku Catatan Blok DHKP" />
</p>

- **Filter 5 Kategori Status**:
  - **Semua Data**: Menampilkan keseluruhan basis data DHKP blok wilayah kerja.
  - **Sudah Bayar**: Objek pajak yang telah terverifikasi lunas di BAPENDA.
  - **Belum Bayar**: Objek pajak dengan kewajiban pembayaran aktif.
  - **Target Pemda**: Objek pajak bernominal besar/prioritas pengawasan pemerintah daerah.
  - **Blacklist (≥ 5 Tahun)**: Objek pajak menunggak kronis lebih dari 5 tahun.
- **Pembaruan Lapangan**: Unggah foto objek/SPPT, beri catatan khusus kolektor, dan simpan status penagihan.
- **Penyimpanan Bebas Izin ("Save As")**:
  - Seluruh operasi ekspor (laporan cetak PDF, rekapitulasi Excel, CSV DHKP, berkas backup terenkripsi `.dkhp`, hingga kolase foto) memanfaatkan antarmuka pemilih penyimpanan native sistem operasi (*Storage Access Framework*).
  - Pengguna bebas menentukan folder penyimpanan mana pun (memori internal, kartu SD, folder dokumen, atau media OTG) tanpa membutuhkan izin akses penyimpanan luas runtime Android (`MANAGE_EXTERNAL_STORAGE`).
- **Ekspor Kolase Foto**: Penggabungan foto-foto fisik SPPT objek pajak per blok ke dalam dokumen laporan PDF tertata rapi siap cetak untuk pengarsipan desa.

---

### 4. Peta Spasial Objek Pajak DHKP (Citra Satelit & KML)

Pemetaan spasial interaktif objek pajak di atas citra satelit Google Maps beresolusi tinggi dengan akurasi koordinat berbasis data riil.

- **Inisialisasi Bersih (*Clean Slate*)**: Peta dirancang tanpa koordinat tiruan atau poligon buatan yang menutupi kontur atap rumah warga. Area peta dimulai secara bersih sesuai data spasial autentik wilayah kerja Anda.
- **Dukungan Berkas KML**: Impor berkas `.kml` batas dusun/desa atau hasil ukur persil tanah untuk memplot koordinat objek pajak secara presisi.
- **Kode Warna Status Pembayaran Spasial**:
  - 🟢 **Hijau (Lunas)**: Objek pajak telah melunasi kewajiban tahun berjalan.
  - 🔴 **Merah (Belum Bayar)**: Objek pajak masih memiliki tunggakan pajak aktif.
  - 🟡 **Kuning (Multi-SPPT)**: Objek pajak memiliki beberapa SPPT dengan pelunasan sebagian.
  - ⚫ **Hitam / Abu Gelap (Target Pemda)**: Objek pajak bernilai ketetapan besar dalam pengawasan khusus.
- **Visualisasi Relasi Objek & Alamat Pemilik**: Apabila lokasi objek tanah terpisah dari domisili tempat tinggal pemilik, pengetukan titik objek menampilkan garis trajektori dan sorotan khusus ke alamat rumah pemilik tanah.
- **Kontrol Navigasi Adaptif**: Tombol pemusatan batas wilayah desa (*Fit Bounds*) dan tombol fokus kantor desa hanya muncul ketika koordinat wilayah sah tersedia, menjamin navigasi peta selalu akurat dan responsif.

---

### 5. Diagram Capaian & Rincian Pelunasan Bulanan

Dashboard analitik visual untuk memantau performa realisasi penerimaan pajak se-desa maupun per blok kerja secara terperinci.

- **Mode Pas Layar (Dirapatkan)**: Pada layar desktop lebar ($\ge 800$ px), grafik otomatis dirapatkan agar seluruh puluhan blok se-desa termuat 100% pas dalam satu pandangan layar tanpa terpotong.
- **Mode Bisa Digeser (Scrollable)**: Dilengkapi interaksi kontrol mouse desktop lengkap:
  - **Klik & Seret (*Mouse Drag*)**: Geser diagram ke kiri atau ke kanan secara halus.
  - **Roda Mouse (*Mouse Wheel*)**: Menggulirkan roda mouse di atas diagram otomatis menggeser grafik secara horizontal.
  - **Scrollbar Horizontal**: Penggeser interaktif yang dapat ditarik dengan kursor.
- **Rincian Pelunasan Bulanan Interaktif**:
  - Mengetuk bar diagram bulan tertentu akan membuka dialog rincian seluruh wajib pajak yang melunasi pembayaran pada bulan bersangkutan.
  - Memuat informasi waktu transaksi lengkap hingga ke jam dan menit, nama wajib pajak, nominal pokok, denda, dan total setor.
  - Dilengkapi **6 mode pengurutan fleksibel**: Waktu Transaksi (Terbaru $\leftrightarrow$ Terlama), Nomor NOP (Urut Maju $\leftrightarrow$ Mundur), dan Nominal Setor (Terbesar $\leftrightarrow$ Terkecil).
  - Opsi ekspor langsung rekap bulanan ke berkas cetak atau laporan digital.

---

### 6. Multi-Wilayah (32 Kecamatan) & Startup Setup Wizard

Fleksibilitas penggunaan untuk seluruh wilayah kerja pemerintahan desa di Kabupaten Cianjur.

- **Wizard Penyiapan Awal (*Startup Setup Wizard*)**:
  - Pengguna baru dipandu melalui alur sambutan interaktif bersuasana ramah dengan sapaan khas *"Sampurasun!"*.
  - Tahapan penyiapan memandu pemilihan wilayah bertingkat: memilih Kecamatan, Desa/Kelurahan, dan melengkapi preferensi profil petugas.
- **Katalog Lengkap 32 Kecamatan**:
  - Mencakup seluruh 32 kecamatan se-Kabupaten Cianjur (Agrabinta, Bojongpicung, Campaka, Campaka Mulya, Cianjur, Cibeber, Cibinong, Cidaun, Cijati, Cikadu, Cikalongkulon, Cilaku, Cipanas, Ciranjang, Cugenang, Gekbrong, Haurwangi, Kadupandak, Karangtengah, Leles, Mande, Naringgul, Pacet, Pagelaran, Pasirkuda, Sindangbarang, Sukaluyu, Sukanagara, Sukaresmi, Takokak, Tanggeung, dan Warungkondang) beserta seluruh daftar desa/kelurahannya yang tersusun alfabetis rapi.
- **Peralihan Desa Cepat**: Petugas lintas wilayah dapat beralih ke desa binaan lain kapan saja melalui menu Pengaturan tanpa menghapus arsip kerja desa sebelumnya.

---

### 7. Monitoring Wilayah & Portal Staf (MFA Otomatis)

Modul administratif terotentikasi bagi staf desa/kelurahan yang memiliki akun portal resmi BAPENDA.

| Login Staf & Captcha | Verifikasi Google Authenticator MFA | Hub Menu Petugas |
| :---: | :---: | :---: |
| <img src="docs/images/07_login_portal_staf.png" width="240" alt="Login Portal Staf" /> | <img src="docs/images/08_verifikasi_mfa.png" width="240" alt="Verifikasi MFA" /> | <img src="docs/images/09_hub_petugas.png" width="240" alt="Hub Petugas" /> |

| Pantauan Realisasi Wilayah | Ranking Capaian Wilayah |
| :---: | :---: |
| <img src="docs/images/10_pantauan_wilayah.png" width="300" alt="Pantauan Wilayah" /> | <img src="docs/images/11_pantauan_ranking.png" width="300" alt="Ranking Wilayah" /> |

- **Otomatisasi Verifikasi Dua Langkah (MFA RFC 6238)**:
  - Dilengkapi generator TOTP internal aman yang dapat mengkalkulasi kode verifikasi 6-digit secara lokal dari kunci rahasia terenkripsi di Keystore perangkat.
  - Fitur *Auto-Login* memungkinkan proses verifikasi masuk portal berlangsung instan tanpa perlu repot membuka aplikasi Google Authenticator eksternal.
- **Sinkronisasi Khusus Pelunasan Baru (*Paid-Only Sync*)**:
  - Fitur pembaruan cerdas yang hanya menarik data objek pajak berstatus lunas dalam rentang waktu yang dipilih (7 hari, 14 hari, 30 hari, 3 bulan, 6 bulan, hingga 1 tahun).
  - Menghemat penggunaan kuota internet dan mempercepat waktu tunggu sinkronisasi hingga 95% dibandingkan sinkronisasi data menyeluruh.
- **7 Tab Rekapitulasi Wilayah Lengkap**:
  - Memantau rincian *Sudah Bayar*, *Belum Bayar*, *Realisasi*, *Piutang*, *Kolektif Sudah Bayar*, *Kolektif Belum Bayar*, serta *Ranking Realisasi Wilayah* antar-desa/kecamatan.

---

### 8. Pembayaran Kolektif & Surat Pengantar

Pengelolaan draf penagihan kolektif massal dan pencetakan surat pengantar pembayaran resmi.

| Daftar Grup Kolektif | Menu Aksi & Finalisasi | Kelola Anggota NOP |
| :---: | :---: | :---: |
| <img src="docs/images/12_pembayaran_kolektif.png" width="240" alt="Daftar Grup Kolektif" /> | <img src="docs/images/13_kolektif_aksi_menu.png" width="240" alt="Menu Aksi Kolektif" /> | <img src="docs/images/14_kelola_anggota.png" width="240" alt="Kelola Anggota NOP" /> |

- Pembuatan grup penagihan baru per RT/RW atau Dusun.
- Impor massal anggota NOP dari berkas CSV/Excel.
- Finalisasi draf penagihan, penerbitan kode bayar kolektif, dan pencetakan Surat Pengantar Setoran resmi.

---

### 9. Cek Pajak Kendaraan Bermotor (Jawa Barat)

Layanan terintegrasi untuk memeriksa kewajiban Pajak Kendaraan Bermotor (PKB) Samsat Jawa Barat.

<p align="center">
  <img src="docs/images/04_cek_kendaraan.png" width="300" alt="Cek Pajak Kendaraan Bermotor" />
</p>

- Masukkan nomor polisi kendaraan dan pilih warna plat (Hitam/Putih, Kuning, Merah).
- Didukung fitur **Scan Plat Nomor (OCR Offline)** menggunakan kamera perangkat *(khusus Android)*.
- Menyajikan rincian PKB Pokok, Denda, SWDKLLJ, PNBP STNK/TNKB, total bayar, dan tanggal jatuh tempo.

---

### 10. Cek Desil & Bantuan Sosial (Kemensos)

Verifikasi status ekonomi dan data kepesertaan bantuan sosial warga terpadu.

<p align="center">
  <img src="docs/images/05_cek_desil.png" width="300" alt="Cek Desil & Bansos Kemensos" />
</p>

- Masukkan 16 digit NIK atau gunakan fitur **Scan NIK KTP/KK (OCR Offline)** *(khusus Android)*.
- Menampilkan kategori desil kesejahteraan serta status keaktifan bansos: **Sembako / BPNT**, **Program Keluarga Harapan (PKH)**, **PBI-JK (BPJS Kesehatan Gratis)**, dan **KPD**.

---

### 11. Layar Pembuka Resmi (Splash Screen)

Pengalaman visual pembuka aplikasi yang profesional dan representatif.

- Menampilkan lambang resmi Pemerintah Kabupaten Cianjur dan identitas kelembagaan Badan Pendapatan Daerah.
- Transisi animasi mulus yang dilengkapi fitur sentuh layar (*tap-to-skip*) untuk langsung menuju ke halaman utama tanpa jeda tunggu.

---

### 12. Buku Panduan Penggunaan & Pusat Bantuan Interaktif

Modul edukasi visual mandiri yang memandu pengguna memahami seluruh fitur aplikasi secara rinci.

<p align="center">
  <img src="docs/images/19_pengaturan_panduan.png" width="320" alt="Buku Panduan Penggunaan Interaktif" />
</p>

- **19 Bab Layar Fitur Terpadu**: Dari pengecekan NOP, DHKP, monitoring staf, hingga pengaturan keamanan.
- **84 Titik Pin Interaktif**: Menunjukkan letak tombol dan fungsinya langsung pada gambar antarmuka asli.
- **Pencarian Cepat & Filter Kategori**: Temukan panduan fitur tertentu dalam hitungan detik.
- **Mode Layar Penuh & FAQ**: Pembesaran gambar beresolusi tinggi dan tanya-jawab seputar kendala umum.

---

### 13. Kustomisasi Tema, Keamanan & Pencadangan Data

Pengaturan kenyamanan visual, perlindungan privasi perangkat, dan pemulihan arsip data.

| Pengaturan Utama | Kustomisasi Tema & Warna | Keamanan Biometrik / PIN |
| :---: | :---: | :---: |
| <img src="docs/images/15_pengaturan_utama.png" width="240" alt="Pengaturan Utama" /> | <img src="docs/images/16_pengaturan_tema.png" width="240" alt="Kustomisasi Tema" /> | <img src="docs/images/17_pengaturan_keamanan.png" width="240" alt="Keamanan Aplikasi" /> |

| Pencadangan & Pemulihan | Tentang Aplikasi & Profil |
| :---: | :---: |
| <img src="docs/images/18_pengaturan_pencadangan.png" width="300" alt="Pencadangan & Cloud" /> | <img src="docs/images/20_pengaturan_tentang.png" width="300" alt="Tentang Aplikasi & Saweria" /> |

- **Kustomisasi Tema**: Pilihan mode Terang, Gelap, Hitam AMOLED, serta 8 warna aksen dinamis atau pemilih warna kustom.
- **Keamanan Aplikasi**: Penguncian otomatis berbasis Sidik Jari/Wajah, PIN 6-digit, atau Kata Sandi dengan proteksi lockout anti brute-force.
- **Pencadangan & Pemulihan**: Ekspor-impor berkas `.dkhp` terenkripsi AES-256-GCM, sinkronisasi Google Drive, dan cadangan otomatis pukul 02:00 dini hari.
- **Tentang Aplikasi**: Informasi versi, profil pengembang, tautan GitHub, donasi Saweria, dan pengecekan pembaruan.

---

## 🚀 Alur Pembaruan Otomatis

Aplikasi dilengkapi mekanisme pemantauan rilis yang terhubung langsung ke REST API GitHub:
1. Pengecekan otomatis berjalan maksimal sekali setiap 24 jam saat aplikasi dibuka, atau dapat dipicu manual melalui **Pengaturan → Tentang Aplikasi → Periksa Pembaruan**.
2. **Deteksi Versi SemVer Cerdas**: Mendukung pembaruan rilis stabil maupun versi uji coba (`beta` / `alpha`), dengan verifikasi nomor build (`+build`) dan proteksi dari berkas unduhan yang korup (`deleteOnError`).
3. **Pencocokan Arsitektur CPU (ABI-Aware APK)**: Pada Android, aplikasi mendeteksi arsitektur perangkat secara native (`Build.SUPPORTED_ABIS`) sehingga ponsel 64-bit modern otomatis mengunduh paket `arm64-v8a.apk`, ponsel 32-bit mengunduh `armeabi-v7a.apk`, dan emulator mengunduh `x86_64.apk`.
4. **Android**: Aplikasi mengunduh berkas `.apk` langsung ke cache privat, membuka installer sistem secara otomatis via `FileProvider`, dan menyediakan tombol buka ulang jika jendela konfirmasi sempat tertutup.
5. **Windows**: Mengunduh pembaruan dan secara otomatis mengeksekusi installer `.exe` baru atau mengekstrak paket portabel `.zip`.

---

## 🛠️ Panduan Pengembangan & Kompilasi

### Prasyarat
- Flutter SDK versi `>= 3.22.0`
- Dart SDK versi `>= 3.4.0`
- Android Studio / Android SDK Platform Tools (API 34)
- Visual Studio Community 2022 dengan C++ Desktop Development & Inno Setup 6/7 (khusus Windows)
- GCC / Clang, CMake, Ninja, dan `libgtk-3-dev` (khusus Linux Desktop)

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
     - `app-arm64-v8a-release.apk` (~21.8 MB - Smartphone Android 64-bit modern)
     - `app-armeabi-v7a-release.apk` (~19.5 MB - Perangkat Android 32-bit legacy)
     - `app-x86_64-release.apk` (~23.2 MB - Emulator / Tablet Intel)
     > [!TIP]
     > **Efisiensi Memori & Instalasi Cepat (`useLegacyPackaging`)**  
     > Berkas APK dikonfigurasi dengan `packaging { jniLibs { useLegacyPackaging = true } }`. Pustaka biner native C++ dan Flutter dieksekusi langsung tanpa memerlukan ekstraksi duplikasi di penyimpanan internal perangkat pengguna.
   - **Android Universal APK (Berkas gabungan seluruh ABI)**:
     ```bash
     flutter build apk --release
     ```
   - **Windows Desktop (Otomatis Portable ZIP + Installer Inno Setup EXE)**:
     Cukup jalankan satu skrip otomatis dari root proyek:
     ```cmd
     tool\build_windows.bat
     ```
     Atau kompilasi manual:
     ```cmd
     flutter build windows --release
     "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer.iss
     ```
     Hasil biner rilis:
     - `build\Cek-PBB-Cianjur-Setup-v0.1.5-beta.exe` (Installer Mandiri)
     - `build\Cek-PBB-Cianjur-Windows-x64-v0.1.5-beta.zip` (Portable ZIP)
   - **Linux Desktop**:
     ```bash
     flutter build linux --release
     ```
     Biner rilis dan pustaka pendukung dihasilkan di direktori `build/linux/x64/release/bundle/`.

> [!IMPORTANT]
> **Penandatanganan Rilis Android (Keystore)**  
> Kompilasi rilis Android membutuhkan konfigurasi berkas `android/key.properties` yang merujuk pada berkas keystore penandatanganan (`.jks`). Berkas ini tidak disertakan di dalam repositori publik demi menjaga integritas dan keamanan aplikasi.

---

## ⚖️ Pernyataan Privasi & Penafian

1. **Independensi Pengembang**: Aplikasi ini dikembangkan secara independen oleh pengembang sebagai alat bantu kerja operasional lapangan bagi petugas/kolektor desa di lingkungan Kabupaten Cianjur. Aplikasi ini bukan merupakan aplikasi resmi yang diterbitkan secara kelembagaan oleh Badan Pendapatan Daerah (BAPENDA) Kabupaten Cianjur.
2. **Kerahasiaan Data**: Seluruh pemrosesan teks, OCR dokumen, dan verifikasi NIK/NOP berlangsung secara luring (*on-device offline processing*) di perangkat masing-masing pengguna. Tidak ada data pribadi warga, dokumen KTP/KK, foto objek pajak, atau kata sandi yang dikirimkan ke peladen pihak ketiga selain transmisi resmi langsung ke portal BAPENDA dan Kemensos.
3. **Hak Cipta Layanan**: Hak cipta nama, logo daerah, serta infrastruktur portal layanan publik sepenuhnya merupakan milik Pemerintah Kabupaten Cianjur dan kementerian terkait.

---

## 📄 Lisensi

Proyek ini didistribusikan di bawah lisensi terbuka **GNU General Public License v3.0 (GPL-3.0)**. Lihat berkas [LICENSE](LICENSE) untuk ketentuan lengkapnya.
