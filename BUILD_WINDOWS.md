# Panduan & Instruksi Build Windows (`v0.1.7-beta`)

Dokumen ini berisi instruksi lengkap untuk mem-build aplikasi **Cek PBB Cianjur (`0.1.7-beta+13`)** pada sistem operasi **Windows (x64)** — baik secara manual lewat **CMD/PowerShell** maupun sebagai **prompt siap salin** untuk agen AI di lingkungan Windows.

---

## 1. Prasyarat Sistem Windows

Pastikan perangkat Windows memiliki komponen berikut sebelum memulai build:

1. **Flutter SDK** versi `>= 3.38.0` (Dart SDK `^3.12.2` sesuai [`pubspec.yaml`](pubspec.yaml)) dan sudah masuk ke `PATH`.
2. **Visual Studio 2022** (Community / Professional / Enterprise) dengan workload **Desktop development with C++**, termasuk:
   - *MSVC v143 - VS 2022 C++ x64/x86 build tools*
   - *Windows 10/11 SDK*
   - *C++ CMake tools for Windows*
3. **Inno Setup 6 atau 7** (untuk menghasilkan installer `.exe` dari [`windows/installer.iss`](windows/installer.iss)).
   - Lokasi standar yang otomatis dideteksi skrip [`tool/build_windows.bat`](tool/build_windows.bat):
     - `C:\Program Files\Inno Setup 7\ISCC.exe`
     - `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
     - `C:\Program Files\Inno Setup 6\ISCC.exe`
     - atau `iscc.exe` di `PATH`

Verifikasi kesiapan toolchain di terminal Windows:

```cmd
flutter doctor -v
```

Pastikan bagian **Visual Studio - develop Windows apps** berstatus `[✓]` (tanpa error komponen C++ / SDK).

---

## 2. Instruksi Siap Salin untuk Agen AI / Antigravity di Windows

Salin dan kirimkan instruksi berikut jika Anda ingin meminta agen di mesin Windows untuk memeriksa lingkungan dan menjalankan build rilis Windows secara otomatis:

```text
Tolong build aplikasi Cek PBB Cianjur versi v0.1.7-beta (0.1.7-beta+13) di Windows dari direktori proyek ini dengan langkah berikut:

1. Periksa kesiapan lingkungan dengan menjalankan `flutter doctor -v` dan pastikan Visual Studio C++ Desktop toolchain terdeteksi serta berada di root proyek (`pubspec.yaml` menunjukkan `version: 0.1.7-beta+13`).
2. Jika proyek berada di shared folder / mapped drive (seperti `Z:\`) atau sebelumnya pernah dipakai di Linux, bersihkan cache lama Windows dengan menghapus folder `build\windows` (bila ada) dan jalankan:
   - `flutter pub get`
   - `dart run tool\sync_windows_plugins.dart --force`
3. Verifikasi kesehatan kode dan seluruh pengujian unit/widget dengan menjalankan:
   - `flutter analyze`
   - `flutter test`
   Pastikan tidak ada error analisis statis maupun kegagalan tes.
4. Jalankan skrip pengemasan rilis Windows otomatis:
   - `tool\build_windows.bat`
   (Skrip ini akan memanggil `flutter build windows --release --obfuscate --split-debug-info=build\symbols\windows --tree-shake-icons`, menghapus residu debug `.pdb`/`.ilk`/`.exp`/`.lib`/`.obj`/`kernel_blob.bin`, mengarsipkan Portable ZIP, mengompilasi installer Inno Setup `windows\installer.iss`, memindahkan artefak ke folder `dist\`, membuat file checksum SHA-256, dan menampilkan laporan ukuran).
5. Verifikasi seluruh berkas keluaran berikut benar-benar terbuat di `dist\` dan bebas file `.pdb` / residu debug di `build\windows\x64\runner\Release\`:
   - `dist\Cek-PBB-Cianjur-Portable-v0.1.7-beta.zip`
   - `dist\Cek-PBB-Cianjur-Setup-v0.1.7-beta.exe` (jika Inno Setup terpasang)
   - `dist\Cek-PBB-Cianjur-v0.1.7-beta-checksums.sha256`
   Serta pastikan `build\windows\x64\runner\Release\cek_pbb_app.exe` terbentuk dengan sukses.
6. Laporkan ringkasan hasil build, ukuran folder Release dan masing-masing artefak di `dist\`, 5 berkas terbesar, isi `checksums.sha256`, serta kendala apa pun jika ada langkah yang gagal.
```

---

## 3. Build Otomatis via CMD / PowerShell (Direkomendasikan)

Buka **Command Prompt (CMD)** atau **PowerShell** di folder root proyek `Cek-PBB-Cianjur` (misalnya `Z:\` atau `C:\Users\<nama>\Cek-PBB-Cianjur`), lalu jalankan:

```cmd
flutter analyze
flutter test
tool\build_windows.bat
```

### Keluaran Artefak (`dist\`)
Setelah [`tool/build_windows.bat`](tool/build_windows.bat) selesai, seluruh artefak rilis tersimpan di folder `dist\`:
- **`dist\Cek-PBB-Cianjur-Setup-v0.1.7-beta.exe`** — Installer resmi Windows berbahasa Indonesia (Inno Setup, mode per-user tanpa wajib hak Admin, dilengkapi *Smart Uninstaller* & filter bebas simbol debug).
- **`dist\Cek-PBB-Cianjur-Portable-v0.1.7-beta.zip`** — Arsip portabel Windows x64 siap ekstrak & jalankan.
- **`dist\Cek-PBB-Cianjur-v0.1.7-beta-checksums.sha256`** — Daftar hash SHA-256 untuk verifikasi integritas & *self-updater*.

Hasil kompilasi biner mentah & peta simbol terpisah:
- `build\windows\x64\runner\Release\cek_pbb_app.exe` (bebas `.pdb`/`.lib`/`.exp`)
- `build\symbols\windows\` (simbol debug terpisah untuk `flutter symbolize`)

---

## 4. Build Manual Langkah demi Langkah

Jika ingin menjalankan kompilasi tanpa skrip batch:

```cmd
:: 1. Ambil dependensi paket
flutter pub get

:: 2. (Wajib jika bekerja di mapped/network drive seperti Z:\)
dart run tool\sync_windows_plugins.dart --force

:: 3. Pastikan direktori output tersedia dan jalankan analisis & tes
if not exist "build\native_assets\windows" mkdir "build\native_assets\windows"
if not exist "build\symbols\windows" mkdir "build\symbols\windows"
flutter analyze
flutter test

:: 4. Kompilasi binary release x64 yang ramping & terobfuskasi
flutter build windows --release --obfuscate --split-debug-info=build\symbols\windows --tree-shake-icons

:: 5. Bersihkan residu linker/debug di folder Release sebelum pengemasan
if exist "build\windows\x64\runner\Release\data\flutter_assets\kernel_blob.bin" del /f /q "build\windows\x64\runner\Release\data\flutter_assets\kernel_blob.bin"
del /s /q "build\windows\x64\runner\Release\*.pdb" "build\windows\x64\runner\Release\*.ilk" "build\windows\x64\runner\Release\*.exp" "build\windows\x64\runner\Release\*.lib" "build\windows\x64\runner\Release\*.obj" 2>nul

:: 6. (Opsional) Susun Installer EXE via Inno Setup
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "windows\installer.iss"
```

---

## 5. Catatan & Penanganan Masalah Umum (Troubleshooting)

1. **Error Symlink Plugin di Shared Folder / Mapped Drive (`Z:\`, SMB, VirtIOFS)**  
   Windows sering menolak pembuatan *symbolic link* pada drive jaringan sehingga CMake gagal menemukan plugin di `windows\flutter\ephemeral\.plugin_symlinks\`. Jalankan:
   ```cmd
   dart run tool\sync_windows_plugins.dart --force
   ```
   Skrip ini otomatis membaca semua plugin Windows dari `.flutter-plugins-dependencies` dan menyalin isi foldernya secara langsung dari `PUB_CACHE` / `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev`.

2. **Konflik Cache setelah Pindah dari Linux ke Windows**  
   Jika repositori dibagikan langsung antara host Linux dan VM Windows, berkas di `windows\flutter\ephemeral\` atau cache CMake lama bisa menyimpan path Linux (`/home/...`). Bersihkan sebelum build ulang:
   ```cmd
   rmdir /s /q build\windows 2>nul
   rmdir /s /q windows\flutter\ephemeral 2>nul
   flutter pub get
   dart run tool\sync_windows_plugins.dart --force
   ```

3. **Pemeriksaan Versi Konsisten (`0.1.7-beta+13`)**  
   Pastikan keempat referensi versi ini selalu selaras saat merilis pembaruan berikutnya:
   - [`pubspec.yaml`](pubspec.yaml) → `version: 0.1.7-beta+13`
   - [`tool/build_windows.bat`](tool/build_windows.bat) → `set "APP_VERSION=v0.1.7-beta"`
   - [`windows/installer.iss`](windows/installer.iss) → `#define MyAppVersion "0.1.7-beta"` dan `VersionInfoVersion=0.1.7.13` / `VersionInfoProductVersion=0.1.7.13`
   - [`README.md`](README.md) → badge versi & panduan kompilasi Windows.
