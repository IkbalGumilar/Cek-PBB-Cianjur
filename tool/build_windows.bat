@echo off
setlocal enabledelayedexpansion
echo =====================================================================
echo  BUILD CEK PBB CIANJUR (WINDOWS RELEASE ^& PACKAGING)
echo =====================================================================
echo.

set "PROJECT_DIR=%~dp0.."
set "APP_VERSION=v0.1.5-beta"
cd /d "%PROJECT_DIR%"

echo [0/4] Menyinkronkan dependensi plugin Windows di ephemeral...
call dart run tool\sync_windows_plugins.dart
if errorlevel 1 (
    echo [WARNING] Sinkronisasi plugin via Dart mengalami kendala, melanjutkan build...
)

echo.
echo [1/4] Kompilasi rilis Flutter Windows langsung di direktori kerja Z:...
if not exist "build\native_assets\windows" mkdir "build\native_assets\windows"
call flutter build windows --release
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
echo [3/3] Memeriksa compiler Inno Setup...
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

echo.
echo [4/4] Menghitung checksum SHA-256 untuk artefak Windows...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$checksumFile = 'build\Cek-PBB-Cianjur-%APP_VERSION%-checksums.sha256'; " ^
    "$lines = @(); " ^
    "if (Test-Path 'build\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe') { " ^
    "  $h = (Get-FileHash 'build\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe' -Algorithm SHA256).Hash.ToLower(); " ^
    "  $lines += ('{0}  Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe' -f $h); " ^
    "} " ^
    "if (Test-Path 'build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip') { " ^
    "  $h = (Get-FileHash 'build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip' -Algorithm SHA256).Hash.ToLower(); " ^
    "  $lines += ('{0}  Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip' -f $h); " ^
    "} " ^
    "$lines | Out-File -FilePath $checksumFile -Encoding utf8; " ^
    "Get-Content $checksumFile"

if not exist "dist" mkdir "dist"
if exist "build\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe" copy /y "build\Cek-PBB-Cianjur-Setup-%APP_VERSION%.exe" "dist\" >nul
if exist "build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip" copy /y "build\Cek-PBB-Cianjur-Windows-x64-%APP_VERSION%.zip" "dist\" >nul

echo.
echo =====================================================================
echo  BUILD SELESAI! Seluruh artefak tersimpan di direktori dist\ dan build\
echo =====================================================================
