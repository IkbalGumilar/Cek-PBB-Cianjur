; =====================================================================
; Inno Setup Script: Cek PBB Cianjur (Windows Desktop Edition)
; Kustomisasi: Antarmuka Bahasa Indonesia, Branding Cianjur,
;              dan Smart Uninstaller (Pembersihan Data Lokal Opsional).
; =====================================================================

#define MyAppName "Cek PBB Cianjur"
#define MyAppVersion "0.1.2-beta"
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
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes

; Mode instalasi ramah pengguna (per-user ke LocalAppData, tidak butuh admin, langsung masuk wizard)
PrivilegesRequired=lowest
ChangesAssociations=yes
ChangesEnvironment=yes

OutputDir=..\build
OutputBaseFilename=Cek-PBB-Cianjur-Setup-v{#MyAppVersion}

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
Name: "default"; MessagesFile: "compiler:Default.isl"

[Messages]
; Terjemahan Bahasa Indonesia untuk Antarmuka Installer
SetupAppTitle=Pemasang {#MyAppName}
SetupWindowTitle=Pemasangan - {#MyAppName} v{#MyAppVersion}
WelcomeLabel1=Selamat Datang di Pemasang {#MyAppName}
WelcomeLabel2=Pemasang ini akan memandu Anda memasang {#MyAppName} pada komputer ini.%n%nAplikasi ini dikembangkan untuk manajemen & pemantauan data PBB-P2 Kabupaten Cianjur.%n%nDisarankan untuk menutup aplikasi lain sebelum melanjutkan.
WizardSelectDir=Pilih Lokasi Pemasangan
SelectDirDesc=Tentukan folder tujuan pemasangan {#MyAppName}.
SelectDirLabel3=Setup akan memasang {#MyAppName} ke folder berikut:
SelectDirBrowseLabel=Klik "Lanjut" untuk menggunakan folder ini, atau klik "Telusuri" untuk memilih folder lain.
WizardSelectTasks=Pilih Pengaturan Tambahan
SelectTasksDesc=Pilih pintasan yang ingin dibuat:
SelectTasksLabel2=Pilih tugas tambahan yang ingin dijalankan, lalu klik "Lanjut":
ReadyLabel1=Setup telah siap memulai proses pemasangan {#MyAppName} di komputer Anda.
WizardInstalling=Sedang Memasang
InstallingLabel=Mohon tunggu sementara Setup mengekstrak berkas {#MyAppName}...
FinishedHeadingLabel=Pemasangan {#MyAppName} Berhasil
FinishedLabel={#MyAppName} telah berhasil dipasang di komputer Anda. Aplikasi kini siap digunakan.
ClickFinish=Klik "Selesai" untuk menutup jendela pemasangan.

; Pesan Uninstaller
ConfirmUninstall=Apakah Anda yakin ingin menghapus {#MyAppName} beserta seluruh komponennya dari komputer ini?
UninstallStatusLabel=Mohon tunggu sementara {#MyAppName} dihapus...
UninstalledAll={#MyAppName} telah berhasil dihapus dari komputer Anda.

[Tasks]
Name: "desktopicon"; Description: "Buat pintasan di &Desktop"; GroupDescription: "Pintasan Tambahan:"
Name: "startmenuicon"; Description: "Buat pintasan di &Start Menu"; GroupDescription: "Pintasan Tambahan:"; Flags: unchecked

[InstallDelete]
; Hapus pintasan lama agar cache ikon Windows ter-reset sempurna
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
    // Trigger pembaruan icon cache shell
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
                   'Lokasi Data: ' + DataDir + #13#10#13#10 +
                   '• Pilih [Ya] untuk membersihkan data lokal secara tuntas.' + #13#10 +
                   '• Pilih [Tidak] jika Anda ingin mempertahankan arsip database/file .dkhp sebagai cadangan.';
                   
      if MsgBox(PromptMsg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        // Hapus folder data lokal secara rekursif
        DelTree(DataDir, True, True, True);
      end;
    end;
  end;
end;
