; =====================================================================
; Inno Setup Script: Cek PBB Cianjur (Edisi Desktop Windows)
; Selaras dengan Dokumentasi README.md Proyek
; Kustomisasi: 100% Bahasa Indonesia Penuh, Branding Resmi Kabupaten Cianjur,
;              dan Smart Uninstaller (Pembersihan Data Lokal Opsional).
; =====================================================================

#define MyAppName "Cek PBB Cianjur"
#define MyAppVersion "0.1.6-beta"
#define MyAppPublisher "Ikbal Gumilar"
#define MyAppURL "https://github.com/IkbalGumilar/Cek-PBB-Cianjur"
#define MyAppSupportURL "https://github.com/IkbalGumilar/Cek-PBB-Cianjur/issues"
#define MyAppUpdatesURL "https://github.com/IkbalGumilar/Cek-PBB-Cianjur/releases"
#define MyAppExeName "cek_pbb_app.exe"
#define AppDataPkgName "id.cianjur.pbb"

[Setup]
AppId={{9B7E3E5D-4921-4F25-9B21-8848CBE1A964}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppUpdatesURL}
AppComments=Aplikasi manajemen, pengecekan, monitoring, dan pelaporan Pajak Bumi dan Bangunan Perdesaan dan Perkotaan (PBB-P2) Kabupaten Cianjur.
AppContact=https://github.com/IkbalGumilar/Cek-PBB-Cianjur
AppCopyright=Hak Cipta (c) 2026 Ikbal Gumilar. Berlisensi Open Source.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; Mode instalasi ramah pengguna (per-user ke LocalAppData, tidak wajib admin)
PrivilegesRequired=lowest
ChangesAssociations=yes
ChangesEnvironment=yes

OutputDir=..\build
OutputBaseFilename=Cek-PBB-Cianjur-Setup-v{#MyAppVersion}

; Metadata Informasi Versi Windows
VersionInfoVersion=0.1.6.12
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Pemasang Resmi {#MyAppName} untuk Windows
VersionInfoTextVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion=0.1.6.12
VersionInfoCopyright=Hak Cipta (c) 2026 {#MyAppPublisher}

; Ikon & Grafis Wizard
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico
UninstallDisplayName={#MyAppName} (v{#MyAppVersion})
WizardImageFile=installer\assets\wizard_sidebar.bmp
WizardSmallImageFile=installer\assets\wizard_small.bmp
WizardStyle=modern

; Kompresi Maksimal
Compression=lzma2/ultra64
SolidCompression=yes

; Penanganan Aplikasi Berjalan
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "id"; MessagesFile: "installer\Indonesian.isl"

[Messages]
; Penyempurnaan Teks Khusus Aplikasi Sesuai README.md
SetupAppTitle=Pemasang {#MyAppName}
SetupWindowTitle=Pemasangan - {#MyAppName} v{#MyAppVersion}
WelcomeLabel1=Selamat Datang di Pemasang {#MyAppName}
WelcomeLabel2=Pemasang ini akan memandu Anda memasang {#MyAppName} v{#MyAppVersion} pada komputer ini.%n%nAplikasi ini dirancang khusus untuk memfasilitasi kerja kolektor dan staf desa/kelurahan di Kabupaten Cianjur dalam pengecekan tagihan, monitoring realisasi, dan pelaporan Pajak Bumi dan Bangunan (PBB-P2) serta arsip DHKP.%n%nAplikasi terhubung langsung dan aman ke portal resmi BAPENDA Kabupaten Cianjur.%n%nDisarankan untuk menutup aplikasi lain sebelum melanjutkan proses pemasangan.

WizardSelectDir=Pilih Lokasi Pemasangan
SelectDirDesc=Tentukan folder tujuan pemasangan {#MyAppName}.
SelectDirLabel3=Pemasang akan memasang {#MyAppName} ke folder berikut:
SelectDirBrowseLabel=Klik "Lanjut" untuk menyetujui folder ini, atau klik "Telusuri" jika Anda ingin memilih lokasi folder lain.

WizardSelectTasks=Pilih Pengaturan Tambahan
SelectTasksDesc=Pilih pintasan yang ingin dibuat di komputer Anda:
SelectTasksLabel2=Pilih tugas tambahan berikut, lalu klik "Lanjut":

ReadyLabel1=Pemasang telah siap memulai proses pemasangan {#MyAppName} di komputer Anda.
ReadyLabel2a=Klik "Pasang" untuk memulai proses pemasangan, atau klik "Kembali" jika Anda ingin memeriksa atau mengubah pengaturan.

WizardInstalling=Sedang Memasang {#MyAppName}
InstallingLabel=Mohon tunggu sementara Pemasang memasang dan mendaftarkan berkas {#MyAppName} di komputer Anda...

FinishedHeadingLabel=Pemasangan {#MyAppName} Selesai
FinishedLabel={#MyAppName} v{#MyAppVersion} telah berhasil dipasang di komputer Anda.%n%nAplikasi ini siap digunakan untuk membantu pengelolaan data PBB-P2 dan arsip DHKP Anda secara offline maupun online.
ClickFinish=Klik "Selesai" untuk menutup jendela pemasang.

; Pesan Penghapusan (Uninstaller)
ConfirmUninstall=Apakah Anda yakin ingin menghapus {#MyAppName} beserta seluruh komponennya dari komputer ini?
UninstallStatusLabel=Mohon tunggu sementara {#MyAppName} dihapus dari komputer Anda...
UninstalledAll={#MyAppName} telah berhasil dihapus dari komputer Anda.

[Tasks]
Name: "desktopicon"; Description: "Buat pintasan di &Layar Utama (Desktop)"; GroupDescription: "Pintasan Tambahan:"
Name: "startmenuicon"; Description: "Buat pintasan di &Menu Mulai (Start Menu)"; GroupDescription: "Pintasan Tambahan:"; Flags: unchecked

[InstallDelete]
; Bersihkan pintasan lama agar cache ikon Windows ter-reset sempurna
Type: files; Name: "{autodesktop}\{#MyAppName}.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}.lnk"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "runner\resources\app_icon.ico"; DestDir: "{app}"; DestName: "app_icon.ico"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\app_icon.ico"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Jalankan {#MyAppName} Sekarang"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\app_icon.ico"

; =====================================================================
; Logika Pascal Script untuk Smart Uninstaller & Shell Refresh
; =====================================================================
[Code]
// Deteksi apakah aplikasi sedang berjalan sebelum uninstalasi dimulai
function InitializeUninstall(): Boolean;
begin
  Result := True;
end;

// Penyegaran cache ikon shell Windows setelah instalasi selesai
procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    // Segarkan cache ikon shell Windows seketika
    Exec('cmd.exe', '/c ie4uinit.exe -show', '', SW_HIDE, ewNoWait, ErrorCode);
  end;
end;

// Penanganan langkah uninstalasi & konfirmasi pembersihan data lokal
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
  PromptMsg: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Lokasi data lokal aplikasi di Windows (%LOCALAPPDATA%\id.cianjur.pbb)
    DataDir := ExpandConstant('{localappdata}\{#AppDataPkgName}');
    
    if DirExists(DataDir) then
    begin
      PromptMsg := 'Apakah Anda ingin menghapus seluruh data lokal dan arsip DHKP?' + #13#10#13#10 +
                   'Lokasi Data Lokal: ' + DataDir + #13#10#13#10 +
                   '• Pilih [Ya] untuk membersihkan seluruh data lokal secara tuntas.' + #13#10 +
                   '• Pilih [Tidak] jika Anda ingin mempertahankan arsip database dan file .dkhp sebagai cadangan di komputer Anda.';
                   
      if MsgBox(PromptMsg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        // Hapus folder data lokal secara rekursif
        DelTree(DataDir, True, True, True);
      end;
    end;
  end;
end;
