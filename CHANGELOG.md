# Changelog - Cek PBB Cianjur

Dokumentasi perubahan, peningkatan, dan perbaikan pada setiap rilis aplikasi. Format mengacu pada [Keep a Changelog](https://keepachangelog.com/id/1.0.0/).

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

**Full Changelog**: https://github.com/IkbalGumilar/Cek-PBB-Cianjur/compare/v0.1.0-alpha.5...v0.1.0-beta
