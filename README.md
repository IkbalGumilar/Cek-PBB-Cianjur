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
- **Monitoring (Portal Staf)** — khusus staf berakun Portal Staf (`cianjurkab.v-tax.id`): login + verifikasi MFA, lihat Monitoring Wilayah (Sudah/Belum Bayar, Realisasi, Piutang, Sudah/Belum Bayar Kolektif, Rangking Realisasi) dan kelola Pembayaran Kolektif (lihat daftar, tambah grup, kelola anggota, hapus grup), dengan hasil yang bisa diunduh/dibagikan/dicetak sebagai PDF/Excel/CSV — lihat [Monitoring (Portal Staf)](#8-monitoring-portal-staf)
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

### 8. Monitoring (Portal Staf)

Chip **Monitoring** di header membuka portal staf terpisah (`cianjurkab.v-tax.id`) — beda dari Cek Tagihan/Cek Status Bayar yang publik tanpa login, menu ini khusus untuk staf yang punya akun Portal Staf.

**Login & Verifikasi MFA**

1. Login pertama: isi **Username**, **Password**, dan kode **captcha** yang tampil, lalu tekan **Login**.
2. Kalau kredensial & captcha benar, lanjut ke layar **Verifikasi MFA** — masukkan kode 6 digit dari aplikasi Google Authenticator. Di bawah kolom kode ada tile "Cara Memasukkan Kode Dengan Google Authenticator" yang menampilkan ikon Google Authenticator asli (kalau aplikasinya terpasang di perangkat) dan bisa ditekan untuk langsung membuka aplikasi itu; kalau belum terpasang, tile ini membuka halaman Play Store-nya.
3. Setelah verifikasi berhasil, sesi login tersimpan di perangkat — buka aplikasi dan tekan Monitoring lagi lain kali tidak perlu login ulang selama sesi di server belum berakhir. Tekan ikon **Keluar** di layar Monitoring untuk logout manual.
4. Username & password tersimpan otomatis setelah login pertama berhasil (bukan sejak awal) — login kedua dan seterusnya kolom Username/Password sudah terisi sendiri, tinggal isi captcha & kode MFA saja.

**Monitoring Wilayah** — 7 tab meniru modul asli, field per tab dicocokkan langsung dengan nama field aslinya. Wilayah otomatis mengikuti akun staf yang login (tidak perlu pilih kecamatan/kelurahan sendiri):

- **Sudah Bayar** — filter rentang Tanggal Pembayaran (default 30 hari terakhir), Tahun Pajak, Buku, Bank, NOP, Nama WP, Petugas Pembayaran, Kode Bayar Individu/Kolektif, VA, QRIS.
- **Belum Bayar** — filter Tanggal Cutoff (menghitung semua piutang belum bayar sampai tanggal tersebut — butuh waktu lebih lama dari tab lain karena tidak ada batas tanggal awal), Tahun Pajak, Buku, NOP, Nama WP, Kode Bayar.
- **Realisasi**, **Piutang**, **Sudah Bayar Kolektif**, **Belum Bayar Kolektif**, **Rangking Realisasi** — field masing-masing tab sama persis dengan modul aslinya.

Hasil tabel setiap tab ditampilkan 10 baris dulu, dengan tombol **Muat 10 Data Lagi** untuk menambah tampilan bertahap (supaya hasil dengan ratusan/ribuan baris tidak langsung dirender semua sekaligus). Di atas tabel ada tiga ikon aksi:

- **Unduh** — simpan hasil ke folder Dokumen dalam format PDF/Excel/CSV pilihan Anda.
- **Bagikan** *(khusus Android)* — kirim langsung lewat share sheet dalam format yang sama.
- **Cetak** — buka pratinjau PDF hasilnya, bisa langsung dicetak/dibagikan/diunduh dari layar pratinjau itu.

**Pembayaran Kolektif** — daftar grup pembayaran kolektif: filter Bulan, Status, Tahun, Tanggal Awal/Akhir. Selain melihat daftar, tersedia dua aksi:

Ketuk baris grup untuk membuka aksinya (tabelnya lebar dan harus digeser mendatar, jadi aksi tidak ditaruh di kolom paling kiri yang gampang hilang dari layar):

- **Tambah Group** — buat grup baru (Nama Group, Keterangan, Kolektor, No HP Kolektor, Kecamatan, Kelurahan). Grup baru berstatus **Draft**.
- **Ubah Group** — ubah nama, keterangan, kolektor, atau no HP. Kecamatan & Kelurahan dikunci saat mengubah, sama seperti di sistem aslinya.
- **Kelola Anggota** — tambah NOP ke grup (diketik atau diunggah dari berkas) dan keluarkan NOP yang terlanjur masuk. Hanya bisa diubah selama grup berstatus **Draft**; di luar itu daftarnya hanya bisa dilihat.
- **Cetak Surat Pengantar** — buka dokumen resmi grup langsung dari server (muncul untuk grup yang sudah final atau sudah dibayar).
- **Hapus Group** — hanya muncul pada grup yang memang masih boleh dihapus (Draft atau Expired). Wajib mengisi **Alasan Penghapusan**.

Semua tombol aksi itu **hanya muncul kalau sistem aslinya juga memunculkannya** untuk grup tersebut — aplikasi membaca tombol apa saja yang dirender server, bukan menyimpulkan sendiri dari statusnya.

Di layar **Kelola Anggota**: NOP boleh ditulis lengkap 18 angka atau disingkat blok+nomor wilayah 5–7 angka (contoh `17154` → blok 017 nomor 0154), dipisah koma kalau lebih dari satu — sebelum terkirim, layar konfirmasi menampilkan NOP lengkap hasil uraiannya untuk dicocokkan. Daftarnya tampil 10 baris dulu dengan tombol **Muat 10 Data Lagi**, atau tombol **Ke Bawah** untuk langsung membuka semuanya dan melompat ke bagian bawah. Di paling bawah ada **Total Keseluruhan** (Pokok, Denda, Total Bayar) yang selalu dihitung dari seluruh anggota, bukan hanya baris yang sedang terlihat. Hasilnya bisa **Unduh / Bagikan / Cetak** sebagai PDF/Excel/CSV, lengkap dengan baris totalnya.

**Unggah Berkas (CSV/Excel)** — daftar NOP juga bisa diambil dari berkas `.csv`, `.xlsx`, `.xls`, atau `.txt` (sistem aslinya hanya menerima CSV). Berkasnya dibaca di aplikasi, bukan dikirim mentah ke server, sehingga sebelum ada yang terkirim Anda lebih dulu melihat:

- kolom mana yang dipakai sebagai NOP (ditebak otomatis, bisa diganti sendiri);
- daftar **NOP 18 angka** yang benar-benar akan dikirim — termasuk tanda untuk NOP yang berasal dari singkatan, karena awalan wilayahnya dilengkapi dari kelurahan grup;
- NOP yang dilewati: **sudah jadi anggota**, **ganda di dalam berkas**, atau **tidak terbaca** (baris judul kolom ikut ke sini);
- peringatan kalau berkas Excel menyimpan NOP sebagai angka — Excel hanya menyimpan 15 angka pertama dengan tepat, jadi digit belakang NOP 18 angka bisa sudah berubah di berkasnya.

NOP dikirim satu per satu dengan indikator kemajuan dan tombol **Hentikan**. Setelah selesai, hasilnya dilaporkan **satu golongan per notifikasi, berurutan** — bukan digabung jadi satu pesan: (1) **Ditambahkan**, (2) **Sudah Bayar — Tidak Dimasukkan**, (3) **Tidak Ditemukan — Tidak Dimasukkan**, masing-masing dengan daftar NOP-nya. Kalau server menjawab hal di luar ketiga golongan itu, muncul notifikasi keempat **Perlu Diperiksa** berisi jawaban server apa adanya — sengaja tidak dipaksa masuk salah satu golongan di atas. Ringkasannya bisa dilihat ulang dan disalin dari kartu hasil.

Tahun pajak dan buku yang dipakai adalah yang tertulis di layar Kelola Anggota, berlaku untuk seluruh isi berkas.

**Tambah Group** dan **Hapus Group** tidak bisa dibatalkan: grup yang dibuat tercatat di server pemerintah, dan penghapusan tercatat permanen di *Log History Penghapusan* lengkap dengan alasan serta nama akun yang menghapus. Karena itu alurnya sengaja dibuat dua langkah — isi form dulu, lalu muncul layar konfirmasi yang menampilkan persis apa yang akan dikirim sebelum ada yang benar-benar terkirim. Menambah/mengeluarkan anggota dan mengubah data grup sebaliknya masih bisa diperbaiki selama grup Draft, jadi cukup satu konfirmasi.

Saat menghapus grup, **Alasan Penghapusan** bisa dipilih dari beberapa alasan siap pakai yang langsung mengisi kolomnya (dan masih bisa disunting) — alasan itu tersimpan permanen di log pemerintah, jadi kalimat yang seragam lebih berguna daripada ketikan seadanya.

Yang **tidak** tersedia di aplikasi: **Finalkan** dan **Generate VA** (keduanya menerbitkan kode bayar sungguhan), serta penambahan **massal** — di sistem aslinya, mengosongkan kolom NOP lalu menekan tambah akan memasukkan seluruh NOP yang belum bayar di satu kelurahan sekaligus; aplikasi ini selalu mengirim NOP yang tertulis, termasuk lewat unggah berkas, sehingga jalur itu tertutup.

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
- Package penting: `dio` + `cookie_jar` (sesi HTTP ke portal resmi, portal staf & pengecekan rilis GitHub — sesi login Portal Staf tersimpan ke berkas supaya bertahan lewat restart aplikasi), `flutter_secure_storage` (kredensial Portal Staf tersimpan aman di perangkat), `html` (parsing respons HTML), `pdf` + `printing`, `excel`, `csv`, `file_picker`, `shared_preferences`, `package_info_plus`, `connectivity_plus`, `url_launcher`

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
