# Changelog - Cek PBB Cianjur

Dokumentasi perubahan, peningkatan, dan perbaikan pada setiap rilis aplikasi. Format mengacu pada [Keep a Changelog](https://keepachangelog.com/id/1.0.0/).

---

## [v0.1.4-beta] - 2026-11-03

### 🚀 Fitur Baru & Peningkatan Aplikasi
- **Sinkronisasi DHKP Langsung dari Portal Staf**:
  - Pilihan mode sinkronisasi: **Keseluruhan DHKP (Belum Bayar & Sudah Bayar)** dan **Hanya Pelunasan (Sudah Bayar Saja)**.
  - Pengambilan data berkecepatan tinggi: request paralel (`Future.wait`) tanpa jeda per halaman dengan pemrosesan *batch upsert* dan deduplikasi di memori.
  - Deteksi NOP/SPPT baru hanya diambil dari daftar *Sudah Bayar* guna mencegah data tidak valid dari NOP nonaktif di daftar tunggakan.
  - Laporan popup hasil sinkronisasi interaktif yang merinci daftar NOP baru lunas serta SPPT baru.
  - Integrasi notifikasi Android: mengetuk notifikasi selesai sinkronisasi kini langsung membuka aplikasi dan menampilkan popup laporan hasil.

### 📦 Pencadangan & Paket Laporan (.dat)
- **Fokus Data Perubahan & Bukti Foto**: Pencadangan dan paket laporan `.dat` kini dikhususkan untuk mencadangkan data perubahan dan foto bukti lapangan (opsi *Hanya DHKP* dihapus).
- **Subfolder Cadangan Google Drive**: Berkas cadangan `.dat` ke Google Drive kini tersimpan rapi di dalam subfolder `backup` pada folder utama.
- **Penyederhanaan Arsitektur**: Menghapus metode sinkronisasi langsung via Google Drive & Folder Bersama, digantikan sepenuhnya oleh sinkronisasi langsung ke Portal Staf.
- **Dukungan Tautan & Akun Google**: Tetap mempertahankan pengambilan paket laporan via tautan Google Drive dan login akun Google di Android.

### 🛡️ Perbaikan Bug & Keandalan
- **Proteksi Integritas NOP**: Menghapus aksi penghapusan NOP dari aplikasi agar data objek pajak lokal selalu konsisten dengan basis data server Bapenda.
- **Visualisasi Grafik DHKP**: Memperbaiki bug kalkulasi dan rendering pada grafik analitik DHKP.

---

## [v0.1.3-beta] - 2026-11-02

### 🚀 Fitur Baru & Peningkatan Aplikasi
- **Dukungan Paket DHKP Multi-Tahun (2015–2026)**: Optimalisasi pembacaan dan parsing paket data DHKP terenkripsi untuk seluruh kedusunan dan desa secara konsisten dari 2015 hingga 2026.
- **Stempel Waktu Riwayat Pembayaran Lengkap**: Pencatatan riwayat pelunasan kini menyertakan tanggal, bulan, tahun, dan waktu lengkap (jam, menit, detik WIB).
- **Pembatasan Filter Tahun (Anti-OOM)**: Pengecekan analitik dan grafik DHKP kini dibatasi per tahun spesifik (default ke tahun terbaru) guna mencegah kelebihan alokasi memori pada ponsel.
- **Lokalisasi Installer Windows**: Penambahan berkas penerjemahan resmi Bahasa Indonesia (`Indonesian.isl`) pada wizard pemasangan Inno Setup Windows.

### 🛡️ Perbaikan Bug & Keandalan
- **Persistensi Sesi & Kuki Portal Staf**:
  - Memperbaiki kegagalan `hasActiveSession()` akibat ketidakcocokan tanda petik tunggal (`id='user-menu'`) dari server V-Tax.
  - Mengintegrasikan singleton `_sharedCookieJar` agar sesi login staf bertahan lintas navigasi dan restart aplikasi.
  - Menambahkan proteksi `_checkExistingSession()` di layar login untuk mencegah penimpaan kuki aktif oleh pengambilan captcha tamu.
  - Memperbaiki alur navigasi pasca-MFA (`pushAndRemoveUntil`) agar tombol kembali di Menu Petugas langsung kembali ke menu utama tanpa memicu layar login berulang.
- **Tabel Rangking Realisasi Desa & Kecamatan**:
  - Mengatasi crash `AssertionError` panjang sel vs header pada tabel capaian realisasi di `MonitoringResultView`.
  - Inferensi header otomatis 5 kolom dan pemfilteran baris toolbar 1-sel pada `StaffPortalParser.parseGenericTable`.
  - Penambahan parameter `namaKecamatan` (`n`) pada request `fetchRangkingRealisasi`.
- **Desain UI Login Portal Staf**:
  - Mengembalikan tata letak login ke desain asli yang bersih dengan logo resmi Kabupaten Cianjur di bagian atas header.

---

## [v0.1.2-beta] - 2026-11-01

### 🚀 Fitur Baru
- **Tur Fitur Interaktif (*Feature Tour & Dynamic Spotlight*)**: Sistem onboarding overlay interaktif dengan spotlight dinamis 60 FPS yang melacak bounding box widget secara real-time bahkan saat layar bergeser. Dilengkapi navigasi langkah titik berpusat (*centered step dots*), animasi sorotan mulus, dan kartu petunjuk yang adaptif terhadap tinggi layar ponsel.
- **Panduan Visual Interaktif (*Visual User Guide*)**: Modul panduan grafis terintegrasi di Pengaturan (`user_guide_screen.dart`) dengan 19 bab tutorial dan 84 titik pinpoint interaktif pada tangkapan layar asli aplikasi. Mendukung pencarian kata kunci instan, filter kategori, dan penampil gambar *pan & zoom* interaktif.
- **Pratinjau Spreadsheet & Parsing Multi-Format**: Penampil spreadsheet bawaan (`SpreadsheetViewerScreen`) yang mendukung pembacaan dan paginasi berkas Excel (`.xlsx`, `.xls`), CSV (`.csv`), serta paket data DHKP terenkripsi (`.dkhp`, `.dhkp`, `.dat`) lengkap dengan pencarian dan filter per kolom.
- **Widget Layar Utama Android (*AppWidget DHKP*)**: Penyedia widget interaktif (`DhkpGrafikWidgetProvider`) untuk homescreen Android yang menampilkan metrik capaian realisasi DHKP dan progres target secara langsung tanpa harus membuka aplikasi.
- **Layanan Pengecekan Massal di Latar Belakang (*Foreground Service*)**: Integrasi `BatchCheckForegroundService` dan notifikasi progres persisten (`batch_notification_service.dart`) sehingga pengecekan ratusan NOP dapat terus berjalan stabil saat ponsel terkunci atau pengguna berpindah aplikasi tanpa terhenti oleh sistem Android.
- **Paket Instalasi Mandiri Windows (*Inno Setup & Portable ZIP*)**: Konfigurasi installer resmi Windows (`installer.iss`) dengan Inno Setup 6 (branding Cianjur, shortcut desktop, opsi uninstaller bersih) serta skrip otomatisasi `tool/build_windows.bat` untuk merilis paket portabel `.zip` dan file setup `.exe`.

### 🔄 Perubahan & Peningkatan
- **Adaptivitas Diagram DHKP Desktop & Geser Mouse (*Mouse Drag*)**:
  - Komponen `DhkpScrollableBars` kini mendukung drag mouse desktop (`PointerDeviceKind.mouse`), scroll horizontal via roda mouse (`PointerScrollEvent`), serta scrollbar interaktif.
  - Mode responsif baru **Pas Layar (*Fit Screen*)** yang otomatis memuat seluruh 41 blok berdampingan tanpa terpotong pada layar desktop (lebar $\ge 800$px).
  - Tombol toggle persisten ("Pas Layar" $\leftrightarrow$ "Bisa Digeser") di toolbar dan header kartu diagram dengan penyimpanan preferensi lokal.
  - Penyesuaian tipografi dinamis untuk label persentase (7.5pt – 9.5pt) dan label nomor blok miring ($-45^\circ$) agar tetap terbaca rapi.
- **Penyempurnaan Galeri Dokumentasi (*README Overhaul*)**:
  - Penambahan badge rilis `v0.1.2-beta`, galeri tangkapan layar resolusi tinggi (19 tangkapan layar fitur), serta instruksi kompilasi lintas platform lengkap.
- **Sinkronisasi Multi-Agent**:
  - Penambahan sistem koordinasi multi-agen di `Docs/sync_agent/` (`BOARD.md` dan `INBOX_WINDOWS.md`) untuk menyinkronkan alur rilis antar mesin Linux dan Windows.

### 🏗️ Restrukturisasi & Kualitas Kode (Refactor)
- **Modularisasi Berkas Monolitik (*SOLID & Feature-First*)**:
  - Dekopel `lib/dhkp/dhkp_crypto.dart` (DKH2 AES-256-GCM 600k PBKDF2 iterasi, legacy decryptor, dan validasi header).
  - Dekopel `lib/dhkp/blok_csv_codec.dart` (codec standar CSV 18-kolom dan fallback 4-kolom).
  - Pemisahan layar Buku Catatan Blok (~2.000+ baris) ke dalam modul terisolasi: `blok_catatan_models.dart`, `blok_catatan_dialogs.dart`, dan `blok_catatan_widgets.dart`.
  - Pemisahan modul grafik DHKP ke dalam `dhkp_grafik_analytics.dart`, `dhkp_chart_widgets.dart`, dan `dhkp_grafik_exporter.dart`.
  - Pemisahan klien Portal Staf ke dalam `staff_portal_models.dart` dan `staff_portal_parser.dart`.
  - Optimalisasi `BlokDataStore.upsertAll` dengan algoritma indeks map $O(N + M)$ yang jauh lebih cepat.
- **Rangkaian Pengujian Regresi (*Unit & Widget Test Suite*)**:
  - Penambahan 39 pengujian otomatis mencakup kriptografi DHKP, parsing HTML/JSON portal staf, kalkulasi metrik analitik, tur fitur, dan panduan visual.
- **Modernisasi Komponen UI**:
  - Migrasi komponen usang `RadioListTile` ke `RadioGroup` pada pengaturan keamanan, formulir pencarian, dan dialog pencadangan.

### 🛡️ Perbaikan Bug & Kompatibilitas
- **Peringatan Deprecations MSVC STL1011 (Windows)**: Penambahan flag `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` pada `windows/CMakeLists.txt` untuk memastikan kompilasi lancar dengan Visual Studio 2022/MSVC terbaru.
- **Penanganan Tata Letak Tur Fitur**: Memperbaiki pemotongan dialog kartu tur pada layar horizontal (*landscape*) atau layar kecil dengan kalkulasi batas viewport dinamis.
- **Penyelarasan Indikator Dot Tur**: Memperbaiki posisi titik indikator navigasi langkah tur agar selalu berada di posisi tengah kartu.

---

## [v0.1.1-beta] - 2026-10-27

### 🚀 Fitur Baru
- **Buka Berkas Otomatis dari WhatsApp / File Manager**: Integrasi Intent-Filter Android (`ACTION_VIEW` dan `ACTION_SEND`) sehingga berkas `.dkhp`, `.dhkp`, dan `.dat` dapat langsung dibuka dan diimpor ke aplikasi hanya dengan mengetuk berkas di chat WhatsApp atau pengelola berkas.
- **Deteksi Arsitektur Perangkat (ABI-Aware APK)**: Pembaruan aplikasi kini otomatis mengenali arsitektur CPU perangkat pengguna (`arm64-v8a`, `armeabi-v7a`, `x86_64`) dan mengunduh berkas APK yang paling sesuai dan optimal.

### 🔄 Perubahan & Peningkatan
- **Penyempurnaan Pembaruan Aplikasi (In-App Update)**:
  - Dukungan penuh deteksi rilis GitHub berlabel `beta` dan `alpha` serta penanganan format versi dengan nomor build (`+build`).
  - Pembersihan berkas gagal unduh secara otomatis (`deleteOnError: true`).
  - Pengecekan keberadaan berkas sebelum mengunduh ulang guna menghemat kuota pengguna.
  - Tombol interaktif "Pasang Sekarang" jika jendela konfirmasi installer sistem sempat tertutup.

### 🛡️ Perbaikan Bug
- **Format Mata Uang Rupiah**: Memperbaiki teks duplikat awalan `Rp Rp` pada struk/cetak tanda terima dan laporan blok.
- **Pembaruan Data DHKP**: Sinkronisasi data DHKP terbaru Dusun 3 dan pembagian blok terkait.

---

## [v0.1.0-beta] - 2026-10-25

### 🚀 Fitur Baru
- **Kunci Aplikasi & Biometrik**: Proteksi akses layar menggunakan sensor sidik jari, Face Unlock, atau PIN 6-digit dengan proteksi anti brute-force.
- **Format Arsip DHKP Terenkripsi (`.dkhp`)**: Format distribusi data baru terenkripsi PBKDF2-HMAC-SHA256 (600.000 iterasi) + AES-256-GCM dengan otentikasi integritas header AAD.
- **Filter Lanjutan Buku Catatan Blok**: Penyaringan data instan berdasarkan status bayar (*Sudah/Belum Bayar*), *Blacklist* tunggakan ≥ 5 tahun, dan *Target Pemda* (pokok PBB ≥ Rp 1,5 juta).
- **Ringkasan Metrik Realisasi Pajak**: Dashboard ringkasan langsung pada header Catatan Blok yang menghitung total ketetapan, realisasi penerimaan, dan persentase capaian.
- **Catatan Lapangan & Dokumentasi Foto**: Penambahan catatan khusus dan lampiran foto lapangan per NOP langsung di aplikasi, lengkap dengan pratinjau interaktif (*zoom & pan*).
- **Kolase Foto Objek Pajak / SPPT**: Pembuat dokumen kolase foto otomatis per blok kerja yang dapat langsung diekspor ke PDF siap cetak atau dibagikan ke WhatsApp.
- **Pemotong & Penyesuai Foto (*Image Cropper*)**: Alat bantu pemotong dan rotasi orientasi foto sebelum disimpan ke basis data atau dimasukkan ke dokumen kolase.
- **Integrasi Google Drive In-App**: Dialog penjelajah dan pengunduh berkas Drive langsung di dalam aplikasi via Google Drive REST API v3 tanpa bergantung pada aplikasi pihak ketiga.
- **Fallback File Manager Lokal**: Alternatif pemilihan berkas dari penyimpanan internal HP secara otomatis jika layanan Drive sedang luring.
- **Sinkronisasi Delta Multi-Petugas**: Riwayat pencatatan perubahan data blok dan sinkronisasi berkas delta terenkripsi antar-kolektor secara aman.
- **Pencadangan Otomatis & Rotasi Retensi**: Penjadwalan pencadangan data otomatis berkala (pukul 02:00) ke penyimpanan lokal dan Drive dengan kebijakan retensi 3 berkas teranyar.
- **Mode Operator**: Mode pengawasan fleksibel untuk memantau data seluruh blok tanpa batasan dusun kerja standar.
- **Tema Adaptif Luminansi**: Kontras teks otomatis pada Header Tab Menu berbasis tingkat kecerahan latar belakang (*"jika terang jadi gelap, jika kelam jadi terang"*), memenuhi standar WCAG AAA.
- **Personalisasi Warna Aksen & Material You**: Pilihan preset warna aksen, pemilih RGB bebas (*lerp* dinamis), dan dukungan Dynamic Color di Android 12+.
- **Rilis Split APK Android**: Distribusi paket APK modular per arsitektur CPU (`arm64-v8a`, `armeabi-v7a`, `x86_64`) untuk memangkas ukuran unduhan (~20-25 MB).
- **Paket Portabel Linux Desktop**: Kompilasi rilis mandiri desktop Linux dalam bentuk arsip `.tar.gz`.

### 🔄 Perubahan & Peningkatan
- **Skema Kriptografi Cadangan**: Migrasi dari enkripsi lama AES-256-CBC ke PBKDF2 (600.000 iterasi) + AES-256-GCM. Kunci lama kini berstatus *read-only* hanya untuk membuka cadangan historis.
- **Navigasi Tabel Catatan Blok**: Pengaktifan gestur geser horizontal (*horizontal scroll*) di seluruh permukaan tabel Android untuk mencegah layar macet atau tersendat.
- **Posisi Indikator Titik DHKP**: Pemindahan indikator status DHKP ke sudut kiri atas agar tidak terhalang oleh kamera *punch-hole* atau *notch* ponsel.
- **Logika Kalkulasi Persentase**: Rumus capaian realisasi disesuaikan murni membagi kategori lunas vs belum lunas tanpa terdistorsi oleh data filter Target Pemda.
- **Tampilan Tab Menu Header**: Penghapusan latar abu-abu/tint buram pada pil tab, diganti pil putih bersih di mode terang dengan teks kontras tinggi.
- **Penamaan Berkas Rilis Resmi**: Berkas instalasi hasil build diubah dari nama bawaan framework menjadi nama resmi aplikasi (`Cek-PBB-Cianjur-<abi>.apk` dan `Cek-PBB-Cianjur-Linux-x64`).
- **Pembaruan Pemetaan Wilayah**: Penambahan Blok 041 ke dalam pembagian wilayah kerja Dusun 3.

### 🛡️ Keamanan & Perbaikan Bug
- **Proteksi Layar Sensitif (`FLAG_SECURE`)**: Pencegahan tangkapan layar (*screenshot*) dan perekaman layar (*screen recording*) pada Android untuk melindungi data pribadi wajib pajak.
- **Penyimpanan Kredensial Aman**: Migrasi seluruh kata sandi, token OAuth, dan hash PIN dari SharedPreferences ke `FlutterSecureStorage` (Android Keystore / OS Keyring).
- **Counter PIN Persisten**: Penghitung kegagalan input PIN kini tersimpan di secure storage dengan jeda waktu eksponensial dan tidak dapat di-reset dengan cara menutup paksa aplikasi.
- **Resolusi App Lock Loop**: Memperbaiki masalah perulangan verifikasi kunci layar yang sempat terjadi saat aplikasi dipanggil kembali dari latar belakang.

### 🗑️ Fitur Dihapus
- **Format Cadangan Lama (`.bak`)**: Dihentikan dan digantikan sepenuhnya oleh format paket terotentikasi `.dkhp`.
- **Loop Auto-Retry HTTP Tak Terbatas**: Dihapus guna mencegah pemborosan kuota internet dan baterai saat peladen BAPENDA sedang mengalami gangguan.
- **Eksperimen WebView Kendaraan Sambara**: Dihapus total karena endpoint web sumber sudah tidak aktif dan digantikan oleh modul native.
- **Penyimpanan Data di Folder Publik**: Penyimpanan berkas data blok dan *cookie* sesi di folder publik eksternal (`Android/data/...`) dihapus dan dipindahkan seluruhnya ke penyimpanan internal privat aplikasi.

---

**Full Changelog**: https://github.com/IkbalGumilar/Cek-PBB-Cianjur/compare/v0.1.3-beta...v0.1.4-beta
