@echo off
setlocal enabledelayedexpansion
echo =====================================================================
echo  BUILD CEK PBB CIANJUR (WINDOWS RELEASE ^& PACKAGING)
echo =====================================================================
echo.

set "PROJECT_DIR=%~dp0.."
set "APP_VERSION=v1.1.0"
cd /d "%PROJECT_DIR%"

echo [0/4] Mengunduh dependensi ^& memastikan plugin Windows tersinkron...
call flutter pub get
if errorlevel 1 (
    echo [WARNING] flutter pub get gagal atau symlink tidak tersedia, mencoba sinkronisasi manual plugin...
)
call dart run tool\sync_windows_plugins.dart
if errorlevel 1 (
    echo [WARNING] Sinkronisasi plugin via Dart mengalami kendala, melanjutkan build...
)

echo.
echo [1/4] Kompilasi rilis Flutter Windows (ramping ^& terobfuskasi) di %CD%...
if not exist "build\native_assets\windows" mkdir "build\native_assets\windows"
if not exist "build\symbols\windows" mkdir "build\symbols\windows"
set "DART_DEFINE_ARGS="
if exist "env.desktop.json" (
    echo [INFO] Menggunakan kredensial Google OAuth Desktop dari env.desktop.json
    set "DART_DEFINE_ARGS=--dart-define-from-file=env.desktop.json"
) else (
    echo [WARNING] env.desktop.json tidak ditemukan. Login Google Drive Desktop tidak akan memiliki client_secret.
)
call flutter build windows --release --obfuscate --split-debug-info=build\symbols\windows --tree-shake-icons %DART_DEFINE_ARGS%
if errorlevel 1 (
    echo [ERROR] Gagal mengompilasi aplikasi Windows!
    exit /b 1
)

echo.
echo [2/4] Mengarsipkan paket Portable ZIP...
if not exist "build" mkdir "build"
REM Bersihkan residu debug dan cache agar biner rilis benar-benar bersih dan ramping
if exist "build\windows\x64\runner\Release\data\flutter_assets\kernel_blob.bin" del /f /q "build\windows\x64\runner\Release\data\flutter_assets\kernel_blob.bin"
del /s /q "build\windows\x64\runner\Release\*.pdb" 2>nul
del /s /q "build\windows\x64\runner\Release\*.ilk" 2>nul
del /s /q "build\windows\x64\runner\Release\*.exp" 2>nul
del /s /q "build\windows\x64\runner\Release\*.lib" 2>nul
del /s /q "build\windows\x64\runner\Release\*.obj" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip' -Force"
if errorlevel 1 (
    echo [WARNING] Gagal membuat berkas zip portable.
) else (
    echo [OK] Paket Portable ZIP berhasil dibuat di build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip
)

echo.
echo [3/4] Memeriksa compiler Inno Setup...
set "ISCC="
if exist "C:\Program Files\Inno Setup 7\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 7\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
) else (
    where iscc.exe >nul 2>&1
    if not errorlevel 1 set "ISCC=iscc.exe"
)

if defined ISCC (
    echo Menyusun installer mandiri EXE dengan Inno Setup...
    "%ISCC%" "windows\installer.iss"
    if errorlevel 1 (
        echo [ERROR] Inno Setup gagal menyusun installer EXE.
    ) else (
        echo [OK] Installer EXE berhasil dibuat di direktori build!
    )
) else (
    echo [INFO] Inno Setup tidak ditemukan. Installer EXE dilewati.
    echo Paket Portable ZIP tetap tersedia di folder build.
)

if not exist "dist" mkdir "dist"
if exist "build\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe" move /y "build\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe" "dist\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe" >nul
if exist "build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip" move /y "build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip" "dist\Cek-PBB-Cianjur-Portable-%APP_VERSION%.zip" >nul

echo.
echo [4/4] Menghitung checksum SHA-256 ^& ringkasan ukuran rilis...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$rel = 'build\windows\x64\runner\Release'; " ^
    "$setup = 'dist\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe'; " ^
    "$zip = 'dist\Cek-PBB-Cianjur-Portable-%APP_VERSION%.zip'; " ^
    "$checksumFile = 'dist\Cek-PBB-Cianjur-%APP_VERSION%-checksums.sha256'; " ^
    "$lines = @(); " ^
    "if (Test-Path $setup) { $lines += ('{0}  Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe' -f (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()); } " ^
    "if (Test-Path $zip) { $lines += ('{0}  Cek-PBB-Cianjur-Portable-%APP_VERSION%.zip' -f (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()); } " ^
    "$lines | Out-File -FilePath $checksumFile -Encoding utf8; " ^
    "Get-Content $checksumFile; " ^
    "$relFiles = Get-ChildItem $rel -Recurse -File; " ^
    "$relMb = [math]::Round((($relFiles | Measure-Object Length -Sum).Sum / 1MB), 2); " ^
    "Write-Host ('[SIZE] Release staging: {0} MB ({1} berkas)' -f $relMb, $relFiles.Count); " ^
    "if (Test-Path $zip) { Write-Host ('[SIZE] Portable ZIP   : {0} MB' -f [math]::Round(((Get-Item $zip).Length / 1MB), 2)); } " ^
    "if (Test-Path $setup) { Write-Host ('[SIZE] Installer EXE  : {0} MB' -f [math]::Round(((Get-Item $setup).Length / 1MB), 2)); } " ^
    "Write-Host '[SIZE] 5 berkas terbesar di Release:'; " ^
    "$relFiles | Sort-Object Length -Descending | Select-Object -First 5 | ForEach-Object { Write-Host ('  - {0,6:N2} MB  {1}' -f ($_.Length / 1MB), $_.FullName.Replace((Resolve-Path $rel).Path + '\', '')) }"

echo.
echo =====================================================================
echo  BUILD SELESAI! Seluruh artefak tersimpan di direktori dist\
echo  Simbol debug terpisah tersimpan di build\symbols\windows
echo =====================================================================
