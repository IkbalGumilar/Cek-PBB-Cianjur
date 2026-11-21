# Catatan Perubahan (Changelog)

Semua perubahan penting pada proyek **Cek PBB Cianjur** didokumentasikan pada berkas ini dengan standar [Semantic Versioning](https://semver.org/).

---

## [1.1.0+15] - 2026-11-21

### Fitur Baru
- **Kategori & Mark Merah `Bermasalah` (Khusus Target Desa)**:
  - Menambahkan kategori status **`Bermasalah`** beserta lencana merah di tabel DHKP dan pita merah di dialog *Informasi Data Pembayaran*.
  - Menambahkan tombol **`Tandai Bermasalah`** / **`Hapus Tanda Bermasalah`** dengan dialog konfirmasi di deretan tombol aksi bawah dialog rincian (otomatis menutup dialog setelah konfirmasi).
  - Objek **Target Pemda** tidak dapat ditandai sebagai bermasalah; objek yang sudah ditandai **Bermasalah** menampilkan kotak **Catatan** (alasan bermasalah) dan **Mark Bermasalah** tanpa tombol/kotak Celengan Warga maupun Kalkulator.
  - Mendukung filter kategori **`Bermasalah`** pada tampilan tabel, cetak laporan PDF, ekspor Excel/CSV, backup `.dkhp`, serta mempertahankannya saat generate ulang DHKP.
- **Multi-Filter Kategori DHKP & Penggabungan Filter `Nihil (Rp 0)`**:
  - Menu filter kategori kini mendukung pemilihan ganda (*multi-filter*) menggunakan ikon radio: secara bawaan seluruh radio menyala (`Semua Data`), menekan **`Semua Data`** mematikan/menyalakan semua kategori sekaligus, dan tersedia tombol cepat **`Hanya`** di sisi kanan tiap baris untuk memilih 1 kategori dalam sekali klik.
  - Menghapus tombol terpisah `Tanpa Rp 0` dan menggabungkan **`Nihil (Rp 0)`** ke dalam daftar filter kategori tanpa emote (*`Semua Data`, `Nihil (Rp 0)`, `Target Pemda`, `Sudah Bayar`, `Belum Bayar`, `Blacklist`, `Bermasalah`*).
  - Menambahkan dialog **`Peringatan: Data Kosong`** saat mencoba mencetak laporan (`Cetak Laporan` / `Ctrl+P`) ketika filter aktif tidak memiliki data.
- **Smart Cloud Merger Antar-Perangkat (Pengecekan Tiap 3 Jam)**:
  - Menambahkan pemeriksaan ringan metadata Google Drive setiap **3 jam** (`BlokBackupScheduler.startPeriodicCloudMergeChecker` & `checkAndMergeCloudUpdatesIfNeeded`) serta saat aplikasi dibuka kembali.
  - Bila dua perangkat memakai Akun Google yang sama dan perangkat lain mengunggah cadangan perubahan `.dkhp` terbaru, aplikasi otomatis mengunduh dan menggabungkannya (*delta merge*) ke database lokal tanpa menimpa status lunas/bermasalah maupun kunci wilayah kerja (`DusunScope`).

### Peningkatan UI/UX & Konsistensi Istilah
- **Penyeragaman Istilah & Bahasa**: Menyeragamkan istilah `"Portal Staf"` $\rightarrow$ `"Portal Petugas"`, `"Rangking"` $\rightarrow$ `"Peringkat"`, `"Nama Group"` $\rightarrow$ `"Nama Grup"`, `"Kadaluarsa"` $\rightarrow$ `"Kedaluwarsa"`, dan `"Tanggal Cutoff"` $\rightarrow$ `"Tanggal Batas"`.
- **Polesan Tampilan**: Menghapus duplikasi informasi kartu PBI dan status di modul Desil (`lib/desil/desil_view.dart`) serta penyesuaian kompatibilitas tata letak Desktop & Mobile.

### Optimasi Performa (60fps & Background Isolate)
- **Background Isolate Offloading**: Memindahkan enkripsi/dekripsi PBKDF2-HMAC-SHA256 (600.000 iterasi) + AES-256-GCM (`DhkpCrypto`), pemotongan & downscale gambar (`ImageCropHelper`), parsing Excel/CSV (`SpreadsheetParser`), pembacaan NOP import kolektif (`KolektifImportScreen`), serta decoding GeoJSON & parsing KML (`DhkpMapScreen`) ke `Isolate.run` agar thread UI tetap responsif.
- **Optimasi Tabel, Pencarian & Peta**: Memoization konteks ruang lingkup dan pengelompokan Grafik DHKP, penyaringan di memori tanpa I/O disk berulang pada setiap ketikan pencarian di Buku Catatan DHKP, pembatasan `AnimatedBuilder` hanya pada marker peta terpilih, `polygonCulling: true`, serta penghapusan widget `SelectableText` per sel demi satu `SelectionArea`.
- **Efisiensi I/O & Cek Massal**: Pengindeksan $O(1)$ (`_keyToIndex`) pada `BlokDataStore`, penggunaan ulang byte PDF STTS saat cek status bayar massal tanpa request ulang, serta single-pass HTML DOM parsing pada `StaffPortalParser`.

### Rilis Biner (`1.1.0+15`)
- **Android Split APK**: `Cek-PBB-Cianjur-v1.1.0-arm64-v8a.apk` (`21,0 MB`), `Cek-PBB-Cianjur-v1.1.0-armeabi-v7a.apk` (`20,1 MB`), `Cek-PBB-Cianjur-v1.1.0-x86_64.apk` (`21,3 MB`).
- **Windows Desktop**: `Cek-PBB-Cianjur-Setup-v1.1.0.exe` (`16 MB`) & `Cek-PBB-Cianjur-Portable-v1.1.0.zip` (`19 MB`).
- **Linux Desktop**: `Cek-PBB-Cianjur-Linux-x64-v1.1.0.tar.gz` (`17 MB`).
- **Checksum**: `Cek-PBB-Cianjur-v1.1.0-checksums.sha256`.

---

## [1.0.0+14] - 2026-11-20

### Rilis Stabil Perdana Multi-Platform
- Layanan Cek Tagihan, Cek Status Bayar, Cek Banyak Data, QRIS & Virtual Account Bank bjb, serta unduhan SPPT Digital & STTS PDF untuk 32 Kecamatan / 337 Desa/Kelurahan se-Kabupaten Cianjur (`32.05`).
- Manajemen Buku Catatan DHKP luring/daring, Kalkulator Denda (1% vs 2%), Cicilan/Celengan Warga dengan kanvas TTD digital, Simulasi AJB, Target & Pacing Realisasi, serta ekspor PDF/Excel/CSV.
- Analitik Grafik DHKP interaktif, Peta Spasial GIS (`flutter_map`), Portal Petugas V-Tax (Captcha OCR, TOTP MFA, Sinkronisasi & Generate Split `DKH2`), Pembayaran Kolektif, Cek PKB Jabar, Cek Desil Bansos, Pembaca PDF Camelot, Penampil Spreadsheet, Kolase F4, Buku Panduan 19 layar, Kunci Aplikasi & Pencadangan Google Drive terenkripsi AES-256-GCM (`DKH2`).
