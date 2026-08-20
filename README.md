# Cek PBB Cianjur

Aplikasi Android untuk membantu staf desa/kelurahan di Kabupaten Cianjur mengecek dan mengurus status PBB (Pajak Bumi dan Bangunan) warga, dengan mengakses langsung portal resmi `cektagihan.cianjurkab.v-tax.id`.

Aplikasi ini **tidak tersedia di Play Store** — didistribusikan manual (sideload) antar perangkat staf desa.

## Fitur Utama

- **Cek Tagihan** — cari tagihan PBB per NOP (input manual atau pakai kode pendek Blok + Nomor Wilayah), lihat rincian per tahun pajak (PBB, denda, kurang bayar, status bayar)
- **Cek Status Bayar** — cek cepat lunas/belum untuk satu NOP
- **Cetak STTS/SPPT** — unduh bukti bayar dalam bentuk PDF
- **Pembayaran QRIS** — generate kode QRIS dinamis per NOP + tahun (berlaku 1 jam, sekali pakai)
- **Pembayaran Virtual Account (VA) Bank BJB** — generate nomor VA, salin ke clipboard, dan buka langsung aplikasi m-banking/e-wallet yang terpasang di HP (mendeteksi ikon aplikasi asli dari sistem)
- **Cek massal** — cek banyak NOP sekaligus, hasil pembayaran otomatis tercatat ke Buku Catatan Blok
- **Buku Catatan Blok** — rekap pembayaran per blok/wilayah kerja, dengan filter tahun, total otomatis, dan ekspor ke PDF/Excel/CSV
- **Backup harian otomatis** — kalau ada data baru, dibackup otomatis ke folder `Dokumen/Cek PBB Cianjur` setiap hari
- Semua dokumen (hasil cek, bukti bayar, laporan, backup) tersimpan di satu folder publik: `Dokumen/Cek PBB Cianjur`

## Teknologi

- [Flutter](https://flutter.dev/) / Dart — target utama: Android (minSdk 24, targetSdk 36)
- Kode native Kotlin (`android/app/src/main/kotlin/.../MainActivity.kt`) untuk: penyimpanan berkas ke folder publik, share berkas, deteksi & buka aplikasi bank/e-wallet, ambil ikon aplikasi asli dari sistem
- Package penting: `dio` + `cookie_jar` (sesi HTTP ke portal resmi), `html` (parsing respons HTML), `pdf`, `excel`, `csv`, `shared_preferences`

## Build

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

### Penting: keystore rilis

Build release **butuh** `android/key.properties` yang menunjuk ke berkas keystore (`.jks`). Berkas ini **sengaja tidak disertakan** di repo (lihat `.gitignore`) karena berisi kredensial penandatanganan aplikasi.

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
