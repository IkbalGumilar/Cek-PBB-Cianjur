# Cek PBB Cianjur

Aplikasi untuk membantu staf desa/kelurahan di Kabupaten Cianjur mengecek dan mengurus status PBB (Pajak Bumi dan Bangunan) warga, dengan mengakses langsung portal resmi `cektagihan.cianjurkab.v-tax.id` — tanpa perlu buka situsnya satu per satu lewat browser.

**Tidak tersedia di Play Store / App Store** — didistribusikan manual antar perangkat staf desa (Android lewat sideload APK, Windows/Linux lewat berkas rilis di GitHub).

## Platform yang Didukung

| Platform | Status | Catatan |
|---|---|---|
| Android | Didukung penuh | Target utama, semua fitur tersedia |
| Windows | Didukung | Pembayaran hanya QRIS, lihat [Batasan per Platform](#batasan-per-platform) |
| Linux | Didukung | Sama seperti Windows |
| iOS | Tidak didukung | Harus lewat App Store, tidak cocok dengan alur sideload aplikasi ini |
| macOS | Tidak digarap | Belum jadi target rilis |

## Fitur Utama

- **Cek Tagihan** — cari tagihan PBB per NOP (input manual atau pakai kode pendek Blok + Nomor Wilayah), lihat rincian per tahun pajak (PBB, denda, kurang bayar, status bayar)
- **Cek Status Bayar** — cek cepat lunas/belum untuk satu NOP dan tahun tertentu
- **Cetak STTS/SPPT & Bukti Bayar** — unduh/pratinjau bukti bayar dalam bentuk PDF
- **Pembayaran QRIS** — generate kode QRIS dinamis per NOP + tahun (berlaku 1 jam, sekali pakai), tersedia di semua platform
- **Pembayaran Virtual Account (VA) Bank BJB** — *khusus Android* — generate nomor VA, salin ke clipboard, dan buka langsung aplikasi m-banking/e-wallet yang terpasang di HP (ikon aplikasi diambil langsung dari sistem, bukan aset yang dibundel)
- **Cek Massal (Import)** — cek banyak NOP sekaligus dari teks tempel atau berkas (.txt/.csv/.xlsx/.xls), hasil pembayaran otomatis tercatat ke Buku Catatan Blok
- **Buku Catatan Blok** — rekap pembayaran per blok/wilayah kerja, dengan filter tahun & urutan, cetak ulang bukti bayar, hapus baris yang salah tercatat, total otomatis, dan ekspor ke PDF/Excel/CSV
- **Backup harian otomatis** — kalau ada data baru, dibackup otomatis setiap hari ke berkas terenkripsi
- **Periksa Pembaruan dalam aplikasi** — cek versi terbaru dari rilis GitHub lengkap dengan catatan pembaruannya, lihat [Pembaruan Aplikasi](#pembaruan-aplikasi)
- Semua dokumen (hasil cek, bukti bayar, laporan, backup) tersimpan di satu folder: `Dokumen/Cek PBB Cianjur` (Android) atau `Downloads/Cek PBB Cianjur` (Windows/Linux)

## Cara Menggunakan

### 1. Cek Tagihan / Cek Status Bayar

Layar utama punya dua mode yang bisa dipilih lewat chip di header: **Cek Tagihan** dan **Cek Status Bayar**.

1. Isi **Blok** dan **Nomor Wilayah** tanpa nol di depan — aplikasi otomatis melengkapinya jadi NOP penuh 18 digit. Contoh: Blok `1`, Nomor Wilayah `1` → otomatis jadi `...0010001...`.
2. Khusus mode **Cek Status Bayar**, isi juga **Tahun Pajak** yang mau dicek.
3. Lihat gambar **kode verifikasi (captcha)** yang tampil, lalu ketik ulang di kolom **Kode Verifikasi**. Kalau gambarnya kurang jelas, tekan **Ganti Captcha** untuk minta gambar baru.
4. Tekan **Cek**.
5. Kalau blok yang diketik belum pernah dicek sebelumnya di perangkat ini, aplikasi akan tanya sekali apakah blok tersebut termasuk wilayah kerja Anda — jawaban ini menentukan blok apa saja yang muncul di Buku Catatan Blok nanti (bisa diubah kapan saja lewat Pengaturan).

**Hasil Cek Tagihan** ditampilkan sebagai tabel per tahun pajak (PBB, Denda, Kurang Bayar, Status, tombol bayar), plus tombol **Cetak PDF** untuk mengunduh STTS/SPPT dan total kurang bayar di bagian bawah.

**Hasil Cek Status Bayar** ditampilkan sebagai kartu berwarna (hijau = sudah bayar, oranye = belum bayar). Kalau sudah bayar, ada tombol ikon mata untuk melihat/mencetak bukti bayarnya.

### 2. Pembayaran QRIS (semua platform)

Di tabel hasil Cek Tagihan, tekan **Bayar QRIS** pada baris tahun yang mau dibayar. Setelah konfirmasi, aplikasi menampilkan kode QR, jumlah tagihan, ID transaksi, dan batas waktu (berlaku 1 jam, sekali pakai). Pindai kode QR itu pakai aplikasi dompet digital/mobile banking apa pun yang mendukung QRIS.

### 3. Pembayaran Virtual Account (khusus Android)

Kalau baris tahun tersebut punya opsi VA, tombol **Bayar VA** akan muncul di sebelah tombol QRIS (kolom ini tidak muncul di Windows/Linux). Setelah konfirmasi:

1. Nomor Virtual Account Bank BJB ditampilkan — tekan **Salin Kode VA** untuk menyalinnya.
2. Kalau aplikasi bank Anda tidak punya opsi "Bank BJB" langsung, ada kombinasi **Kode Bank** (910200) + **Kode Bayar** di bawahnya untuk dipakai lewat menu Virtual Account/Multipayment Antar Bank.
3. Bagian **Buka Aplikasi Bank** menampilkan ikon aplikasi m-banking/e-wallet yang terdeteksi terpasang di HP — sengaja terkunci (abu-abu) sampai Anda menyalin kode VA atau kode bayar dulu, supaya kodenya sudah aman di clipboard sebelum berpindah aplikasi. Setelah disalin, tinggal ketuk ikon aplikasi bank yang mau dipakai, lalu tempel kode VA-nya di sana.

### 4. Cek Massal (Import banyak NOP sekaligus)

Di mode **Cek Status Bayar**, tekan ikon unggah di sebelah kolom Nomor Wilayah untuk membuka layar Import. Ada dua cara mengisi daftar NOP:

- **Tempel teks** — satu NOP per baris, atau dipisah koma. Boleh format lengkap 18 digit atau kode pendek (5-7 digit, sama seperti Blok+Nomor Wilayah).
- **Pilih Berkas** — unggah `.txt`, `.csv`, atau `.xlsx`/`.xls` berisi daftar NOP.

Teks yang diketik otomatis tersimpan sebagai draft (tidak hilang kalau aplikasi ditutup). Setelah daftar siap, tentukan tahun pajaknya lalu mulai proses cek — captcha akan diminta satu per satu untuk tiap NOP dalam daftar, dan hasil "Sudah Bayar" otomatis tercatat ke Buku Catatan Blok.

### 5. Buku Catatan Blok

Tombol melingkar (FAB) dengan ikon buku di layar utama membuka rekap semua NOP yang statusnya "Sudah Bayar", hasil dari Cek Status Bayar maupun Cek Massal.

- Filter berdasarkan **Blok** (atau "Semua Blok" untuk gabungan semua wilayah kerja Anda) dan **Tahun**, plus pilihan urutan tampilan.
- Tekan salah satu baris untuk **Cetak Bukti Bayar** ulang — otomatis membuka Cek Status Bayar dengan Blok/Nomor Wilayah/Tahun yang sudah terisi.
- Setiap baris juga punya ikon **Hapus** untuk mengoreksi catatan yang salah tercatat (mis. salah impor) — akan diminta konfirmasi dulu karena bersifat permanen.
- **Unduh Laporan** menyimpan rekap ke folder Dokumen dalam format CSV/Excel/PDF pilihan Anda.
- **Bagikan Laporan** *(khusus Android)* langsung membuka share sheet Android (WhatsApp, email, dll).

### 6. Pengaturan

Ikon roda gigi di header membuka Pengaturan, berisi:

- **Tema** — Ikuti Sistem, Terang, Gelap, atau Hitam AMOLED (hemat baterai di layar OLED).
- **Data Blok** — ekspor seluruh data blok tersimpan sebagai berkas backup terenkripsi (`.bak`), impor kembali (restore) dari berkas backup — hanya bisa dipulihkan di perangkat dengan wilayah kerja yang sama; backup dari wilayah lain otomatis ditolak — dan atur daftar Blok mana saja yang termasuk wilayah kerja Anda (menentukan apa yang muncul di Buku Catatan Blok).
- **Bagikan Aplikasi** — di Android, membagikan berkas APK aplikasi ini langsung lewat share sheet; di Windows/Linux, menyalin **link halaman unduhan** (rilis GitHub) ke clipboard supaya penerima mengunduh sendiri versi yang sesuai sistem operasinya.
- **Tentang Aplikasi** — info aplikasi, versi terpasang, tombol **Periksa Pembaruan**, dan halaman Lisensi Open Source.

### 7. Notifikasi Status Jaringan

Aplikasi memantau koneksi internet dan kesehatan server portal PBB secara berkala. Kalau ada masalah (tidak ada internet, internet lambat, atau server sedang bermasalah), muncul pil peringatan mengambang di bagian atas layar secara otomatis.

## Pembaruan Aplikasi

Aplikasi bisa mengecek versi terbaru langsung dari [halaman rilis GitHub repo ini](https://github.com/IkbalGumilar/Cek-PBB-Cianjur/releases/latest) — lewat menu **Pengaturan → Tentang Aplikasi → Periksa Pembaruan**, atau otomatis setiap aplikasi dibuka (maksimal sekali per 24 jam, muncul sebagai banner kecil kalau ada versi baru).

Alurnya **berbeda per platform**:

- **Android** — unduh berkas APK dari rilis GitHub, lalu aplikasi otomatis membuka installer sistem Android untuk konfirmasi pasang (perlu izin "Instal aplikasi tidak dikenal" diaktifkan sekali di Android 8+, aplikasi akan menuntun ke layar izinnya kalau belum aktif).
- **Windows/Linux** — aplikasi **hanya mengunduh** berkas rilis terbaru ke folder Downloads, **tidak** memasang dirinya sendiri secara otomatis (tidak ada cara aman & generik lintas platform untuk itu tanpa hak admin/root). Setelah unduhan selesai, jalankan/ekstrak berkasnya sendiri untuk memperbarui.

Deteksi versi & catatan pembaruan (log "apa yang ditambahkan/diperbaiki/dihapus") diambil dari deskripsi rilis GitHub apa adanya — jadi setiap merilis versi baru, isi deskripsi rilisnya dengan jelas karena itu yang akan tampil di aplikasi.

**Konvensi penamaan berkas rilis** (supaya terdeteksi otomatis oleh pengecek pembaruan):

| Platform | Asset dicari berdasarkan |
|---|---|
| Android | nama berkas berakhiran `.apk` |
| Windows | nama berkas mengandung kata `windows`, atau berakhiran `.exe`/`.msix` |
| Linux | nama berkas mengandung kata `linux`, atau berakhiran `.AppImage`/`.tar.gz`/`.deb` |

## Batasan per Platform

- **Pembayaran VA & "Buka Aplikasi Bank"** hanya tersedia di Android — fitur ini bergantung pada kemampuan mendeteksi & membuka aplikasi m-banking/e-wallet lain yang terpasang di HP, sesuatu yang tidak relevan di desktop. Di Windows/Linux, kolom VA tidak ditampilkan sama sekali; pembayaran hanya lewat QRIS.
- **Pembaruan otomatis (pasang sendiri)** hanya berjalan di Android — lihat [Pembaruan Aplikasi](#pembaruan-aplikasi) di atas.
- **Bagikan Aplikasi** berbentuk berkas APK di Android, dan link halaman rilis GitHub di Windows/Linux.
- **macOS** belum digarap sama sekali (folder scaffold `macos/` ada dari `flutter create` tapi belum dikonfigurasi, termasuk entitlement jaringan sandbox-nya) — jangan build/rilis untuk macOS sebelum ini dibenahi.

## Teknologi

- [Flutter](https://flutter.dev/) / Dart — Android, Windows, Linux
- Kode native Kotlin (`android/app/src/main/kotlin/.../MainActivity.kt`, khusus Android) untuk: penyimpanan berkas ke folder publik, share berkas, deteksi & buka aplikasi bank/e-wallet, ambil ikon aplikasi asli dari sistem, dan buka installer sistem untuk pembaruan
- Package penting: `dio` + `cookie_jar` (sesi HTTP ke portal resmi & pengecekan rilis GitHub), `html` (parsing respons HTML), `pdf` + `printing`, `excel`, `csv`, `file_picker`, `shared_preferences`, `package_info_plus`, `connectivity_plus`, `url_launcher`

## Build

### Android

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

### Windows / Linux

```bash
flutter pub get
flutter build windows --release   # di mesin Windows
flutter build linux --release     # di mesin Linux (butuh ninja, cmake, libgtk-3-dev)
```

> Build Windows harus dijalankan di mesin Windows (atau lewat CI, mis. GitHub Actions runner `windows-latest`) — Flutter tidak mendukung cross-compile ke Windows dari Linux/macOS.

### Penting: keystore rilis (Android)

Build release Android **butuh** `android/key.properties` yang menunjuk ke berkas keystore (`.jks`). Berkas ini **sengaja tidak disertakan** di repo (lihat `.gitignore`) karena berisi kredensial penandatanganan aplikasi.

Format `android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=nama-file-keystore.jks
```

**Jangan pernah membuat keystore baru** untuk build berikutnya kalau aplikasi sudah terpasang di HP staf — kunci penandatanganan harus tetap sama selamanya, karena Android menolak update aplikasi kalau tanda tangannya beda (harus uninstall dulu, dan data lokal yang belum dibackup akan hilang). Simpan berkas keystore & password-nya di tempat aman di luar repo.

## Catatan

- Aplikasi ini mengambil data langsung dari portal resmi pemerintah (bukan API publik yang terdokumentasi), jadi bisa terdampak kalau ada perubahan di sisi vendor/portal.
- Bukan aplikasi resmi terbitan Bapenda/Pemkab Cianjur — dibangun untuk mempermudah kerja staf desa dalam mengecek PBB warga.
