# Catatan Perubahan untuk Komit (Commit Changelog)
**Proyek:** Cek PBB Cianjur  
**Versi Rilis:** v0.1.3-beta (Build +9)  
**Rentang:** Dari Perbaikan Pengecekan Masal hingga Pembaruan Portal Staf & Engine DHKP  
**Tanggal:** 2 November 2026  

---

## 📋 Ringkasan Utama (Executive Summary)
Pembaruan versi `0.1.3-beta` ini berfokus pada stabilitas sistem, performa, dan keandalan fitur inti aplikasi:
1. Peningkatan ketahanan koneksi dan mitigasi *rate-limit* pada modul pengecekan masal NOP.
2. Optimalisasi engine DHKP untuk pembacaan paket data multi-tahun (2015–2026) dengan proteksi alokasi memori (*anti-OOM*).
3. Pemulihan tata letak antarmuka Portal Staf dan penyempurnaan logo resmi Kabupaten Cianjur.
4. Perbaikan *crash assertion* pada tabel Rangking Realisasi wilayah.
5. Perbaikan menyeluruh persistensi sesi kuki login staf dan pembersihan tumpukan navigasi kembali (*back button*).
6. Penambahan modul bahasa Indonesia resmi untuk *installer* Windows.

---

## 1. ⚡ Pengecekan Masal & Klien PBB (`pbb_client.dart`)
* **Ketahanan Koneksi & Rate-Limit:**
  * Penambahan toleransi *timeout* dinamis dan *retry* adaptif saat memproses banyak NOP secara paralel/berurutan.
  * Deteksi dini respons pembatasan server dan *challenge* captcha untuk mencegah pemblokiran alamat IP oleh server Bapenda.
* **Format Riwayat Pelunasan Warga:**
  * Penyimpanan catatan pembayaran kini dilengkapi stempel waktu terperinci:
    `Sudah Bayar Tanggal [DD] Bulan [MM] Tahun [YYYY] Jam [HH:mm:ss] WIB`.

---

## 2. 📊 Engine DHKP & Analitik Grafik (`dhkp/`, `dhkp_grafik_view.dart`)
* **Dukungan Paket Multi-Tahun (2015–2026):**
  * Peningkatan kemampuan pembacaan dan parsing paket terenkripsi (`.dkhp` / `.dhkp`) secara konsisten dari arsip 2015 hingga 2026.
  * Pengujian komprehensif struktur paket data di [`test/dhkp_packages_2015_2026_test.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/test/dhkp_packages_2015_2026_test.dart) (32 pengujian otomatis).
* **Pembatasan Filter Tahun (Anti-OOM):**
  * Menonaktifkan opsi "Pilih Semua Tahun Sekaligus" guna mencegah lonjakan konsumsi RAM ponsel (*Out Of Memory*).
  * Filter tahun kini default ke data tahun terbaru dengan kontrol pemilihan tahun tunggal yang presisi (2015 s.d. 2026).
* **Penyempurnaan Visualisasi Grafik Multi-Tahun:**
  * Penambahan kontrol filter tahun di diagram batang DHKP (`dhkp_grafik_view.dart`) untuk komparasi capaian target vs realisasi antar-tahun.

---

## 3. 🏢 Portal Staf & Monitoring Wilayah (`cianjurkab.v-tax.id`)
* **Pemulihan Desain Antarmuka Login Staf:**
  * Penyesuaian tata letak kembali ke desain asli yang bersih dan konsisten.
  * Logo Kabupaten Cianjur diposisikan di bagian atas *header* sesuai identitas resmi daerah tanpa ornamen tiruan berlebih.
* **Perbaikan *Crash* Tabel "Rangking Realisasi":**
  * Mengatasi `AssertionError: !rows.any((DataRow row) => row.cells.length != columns.length)` pada tampilan tabel capaian realisasi di `MonitoringResultView`.
  * Parser [`StaffPortalParser.parseGenericTable`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/staff_portal/staff_portal_parser.dart) kini memprioritaskan elemen `<th>`, mengabaikan baris tombol/toolbar 1-sel di atas tabel, menginferensi 5 header resmi (*No, Desa/Kelurahan, Pagu/Ketetapan, Realisasi, % Realisasi*), serta menormalisasi jumlah sel pada setiap baris data.
  * Penambahan parameter `namaKecamatan` (`n`) pada pemanggilan `fetchRangkingRealisasi` agar filter wilayah terkirim akurat.
* **Perbaikan Sesi Kuki & Cache Login Portal Staf:**
  * **Akurasi Validasi Sesi:** Memperbaiki `hasActiveSession()` yang sebelumnya memeriksa string kaku `id="user-menu"` (gagal karena server V-Tax menggunakan tanda petik tunggal `id='user-menu'`). Sekarang mendukung deteksi fleksibel tanda petik tunggal maupun ganda serta penanganan redirect `302`.
  * **Penyimpanan Kuki Terpusat:** Menggunakan `_sharedCookieJar` tunggal berbasis `PersistCookieJar` agar kuki sesi tetap awet dan tidak bentrok antar instance klien.
  * **Pencegahan Kuki Tertimpa (*Cookie Guard*):** Menambahkan `_checkExistingSession()` pada [`StaffLoginScreen`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/staff_login_screen.dart). Jika sesi aktif sudah ada, aplikasi tidak akan meminta captcha baru (yang berpotensi menimpa kuki login yang valid), melainkan langsung masuk ke Hub Monitoring.
  * **Pembersihan Alur Navigasi (*Back Button*):** Mengganti navigasi pasca-MFA di [`StaffMfaScreen`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/lib/staff_mfa_screen.dart) dengan `Navigator.pushAndRemoveUntil(..., (route) => route.isFirst)`. Saat pengguna menekan tombol kembali di Menu Petugas, aplikasi langsung kembali ke halaman utama dan tidak lagi menampilkan layar login berulang.

---

## 4. 📦 Windows Installer & Lokalisasi
* Pembaruan skrip Inno Setup ([`windows/installer.iss`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/windows/installer.iss)) untuk paket instalasi mandiri Windows versi 0.1.3-beta.
* Penambahan modul bahasa Indonesia resmi ([`windows/installer/Indonesian.isl`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/windows/installer/Indonesian.isl)) untuk wizard instalasi Windows.

---

## 5. 🧪 Kualitas Kode & Rangkaian Pengujian (Test Suite)
* **Unit Tests Parser & Sesi:** 17/17 pengujian di [`test/staff_portal_parser_test.dart`](file:///home/ikbal/Documents/Cek-PBB-Cianjur/test/staff_portal_parser_test.dart) lulus, mencakup tabel ranking, toolbar skipping, normalisasi baris, dan deteksi petik tunggal/ganda sesi login.
* **Analisis Statis:** `flutter analyze lib/ test/` menghasilkan **0 issues (bersih)**.

---

## 📁 Daftar Berkas Terubah (Changed Files)
```text
M  CHANGELOG.md
M  README.md
M  pubspec.yaml
M  lib/blok_catatan_screen.dart
M  lib/blok_data_store.dart
M  lib/blok_record.dart
M  lib/dhkp/blok_catatan_models.dart
M  lib/dhkp_grafik_view.dart
M  lib/monitoring/monitoring_form_fields.dart
M  lib/monitoring/monitoring_result_table.dart
M  lib/monitoring/monitoring_tab_scaffold.dart
M  lib/monitoring/tab_belum_bayar.dart
M  lib/monitoring/tab_belum_bayar_kolektif.dart
M  lib/monitoring/tab_piutang.dart
M  lib/monitoring/tab_rangking_realisasi.dart
M  lib/monitoring/tab_realisasi.dart
M  lib/monitoring/tab_sudah_bayar.dart
M  lib/monitoring/tab_sudah_bayar_kolektif.dart
M  lib/pbb_client.dart
M  lib/staff_login_screen.dart
M  lib/staff_mfa_screen.dart
M  lib/staff_portal/staff_portal_models.dart
M  lib/staff_portal/staff_portal_parser.dart
M  lib/staff_portal_client.dart
M  lib/staff_portal_token_extractor.dart
M  test/staff_portal_parser_test.dart
M  test/stts_in_memory_test.dart
M  tool/build_windows.bat
M  windows/installer.iss
M  windows/installer/assets/wizard_sidebar.bmp
A  lib/monitoring/monitoring_excel_queue_view.dart
A  lib/monitoring/monitoring_summary_cards.dart
A  windows/installer/Indonesian.isl
A  PERUBAHAN_COMMIT.md
```

---

## 💡 Rekomendasi Pesan Komit (Commit Message Suggestion)

### Opsi 1: Satu Komit Komprehensif
```text
feat: bump to v0.1.3-beta, overhaul monitoring parsing, persist staff session, and optimize DHKP engine

- Fix staff portal session loss caused by single-quoted HTML user-menu parsing
- Implement shared PersistCookieJar and navigation stack cleanup post-MFA
- Fix assertion error on Rangking Realisasi table in MonitoringResultView
- Restore original staff login UI layout with official Cianjur header logo
- Enhance DHKP package engine for multi-year archives (2015-2026)
- Enforce single-year DHKP filtering (default latest year) to prevent memory exhaustion
- Add full timestamp (date, time, minute, second) to taxpayer payment records
- Add Inno Setup Indonesian translation and Windows installer updates
- Bump app version to 0.1.3-beta+9 in pubspec, Android, Windows, and README
- Add 50+ regression unit tests (100% pass, 0 analyze issues)
```

### Opsi 2: Komit Bertahap per Modul
1. `fix(batch-check): improve PbbClient timeout handling and add full payment timestamps`
2. `feat(dhkp): enhance multi-year package engine and enforce single-year filter to prevent OOM`
3. `fix(monitoring): resolve Rangking Realisasi table row-header assertion error and add kecamatan parameter`
4. `fix(staff-portal): fix session cookie persistence, avoid captcha overwrite, and clean navigation stack`
5. `style(staff-portal): restore classic login layout with official Cianjur logo`
6. `feat(windows): add Indonesian translation file for Inno Setup installer`
7. `chore(release): bump version to v0.1.3-beta+9 and update documentation`
