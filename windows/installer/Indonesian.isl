; =====================================================================
; Inno Setup 7 - Berkas Bahasa Indonesia Resmi (Indonesian.isl)
; Disesuaikan untuk Cek PBB Cianjur (Pengguna 100% Lokal Indonesia)
; Standar Terminologi: Microsoft Indonesian Style Guide & Glosarium Resmi
; =====================================================================

[LangOptions]
LanguageName=Indonesian
LanguageID=$0421
LanguageCodePage=0

[Messages]

; *** Judul Aplikasi
SetupAppTitle=Pemasang
SetupWindowTitle=Pemasangan - %1
UninstallAppTitle=Hapus Pemasangan
UninstallAppFullTitle=Hapus Pemasangan %1

; *** Pesan Umum
InformationTitle=Informasi
ConfirmTitle=Konfirmasi
ErrorTitle=Kesalahan

; *** SetupLdr
SetupLdrStartupMessage=Pemasang ini akan memasang %1 di komputer Anda. Apakah Anda ingin melanjutkan?
LdrCannotCreateTemp=Tidak dapat membuat berkas sementara. Pemasangan dibatalkan.
LdrCannotExecTemp=Tidak dapat menjalankan berkas di dalam folder sementara. Pemasangan dibatalkan.
HelpTextNote=

; *** Pesan Kesalahan Awal
LastErrorMessage=%1.%n%nKesalahan %2: %3
SetupFileMissing=Berkas %1 tidak ditemukan di dalam folder pemasangan. Silakan unduh ulang salinan aplikasi.
SetupFileCorrupt=Berkas pemasang rusak. Silakan unduh ulang salinan aplikasi.
SetupFileCorruptOrWrongVer=Berkas pemasang rusak atau tidak kompatibel dengan versi ini. Silakan unduh ulang salinan aplikasi.
InvalidParameter=Parameter yang diberikan pada baris perintah tidak valid:%n%n%1
SetupAlreadyRunning=Pemasang sedang berjalan di sistem ini.
WindowsVersionNotSupported=Aplikasi ini tidak mendukung versi Windows yang sedang berjalan di komputer Anda.
WindowsServicePackRequired=Aplikasi ini memerlukan %1 Service Pack %2 atau yang lebih baru.
NotOnThisPlatform=Aplikasi ini tidak dapat dijalankan pada %1.
OnlyOnThisPlatform=Aplikasi ini hanya dapat dijalankan pada %1.
OnlyOnTheseArchitectures=Aplikasi ini hanya dapat dipasang pada versi Windows untuk arsitektur prosesor berikut:%n%n%1
WinVersionTooLowError=Aplikasi ini memerlukan %1 versi %2 atau yang lebih baru.
WinVersionTooHighError=Aplikasi ini tidak dapat dipasang pada %1 versi %2 atau yang lebih baru.
AdminPrivilegesRequired=Anda harus masuk sebagai administrator untuk memasang aplikasi ini.
PowerUserPrivilegesRequired=Anda harus masuk sebagai administrator atau anggota grup Power Users untuk memasang aplikasi ini.
SetupAppRunningError=Pemasang mendeteksi bahwa %1 sedang berjalan.%n%nSilakan tutup seluruh jendela aplikasi tersebut terlebih dahulu, lalu klik OK untuk melanjutkan, atau klik Batal untuk keluar.
UninstallAppRunningError=Program penghapus mendeteksi bahwa %1 sedang berjalan.%n%nSilakan tutup seluruh jendela aplikasi tersebut terlebih dahulu, lalu klik OK untuk melanjutkan, atau klik Batal untuk keluar.

; *** Mode Pemasangan
PrivilegesRequiredOverrideTitle=Pilih Mode Pemasangan
PrivilegesRequiredOverrideInstruction=Pilih mode pemasangan yang diinginkan
PrivilegesRequiredOverrideText1=%1 dapat dipasang untuk seluruh pengguna komputer (memerlukan hak administrator), atau hanya untuk Anda saja.
PrivilegesRequiredOverrideText2=%1 dapat dipasang hanya untuk Anda saja, atau untuk seluruh pengguna komputer (memerlukan hak administrator).
PrivilegesRequiredOverrideAllUsers=Pasang untuk &semua pengguna
PrivilegesRequiredOverrideAllUsersRecommended=Pasang untuk &semua pengguna (disarankan)
PrivilegesRequiredOverrideCurrentUser=Pasang hanya untuk &saya
PrivilegesRequiredOverrideCurrentUserRecommended=Pasang hanya untuk &saya (disarankan)

; *** Kesalahan Lain-lain
ErrorCreatingDir=Pemasang tidak dapat membuat folder "%1".
ErrorTooManyFilesInDir=Tidak dapat membuat berkas di dalam folder "%1" karena folder tersebut berisi terlalu banyak berkas.

; *** Pesan Umum Pemasang
ExitSetupTitle=Keluar dari Pemasang
ExitSetupMessage=Pemasangan belum selesai. Jika Anda keluar sekarang, aplikasi belum terpasang di komputer Anda.%n%nAnda dapat menjalankan pemasang ini lagi kapan saja.%n%nApakah Anda yakin ingin keluar dari pemasang?
AboutSetupMenuItem=&Tentang Pemasang...
AboutSetupTitle=Tentang Pemasang
AboutSetupMessage=%1 %2%n%3%n%nSitus web resmi %1:%n%4
AboutSetupNote=
TranslatorNote=

; *** Tombol-tombol Antarmuka
ButtonBack=< &Kembali
ButtonNext=&Lanjut >
ButtonInstall=&Pasang
ButtonOK=OK
ButtonCancel=Batal
ButtonYes=&Ya
ButtonYesToAll=Ya untuk &Semua
ButtonNo=&Tidak
ButtonNoToAll=T&idak untuk Semua
ButtonFinish=&Selesai
ButtonBrowse=&Telusuri...
ButtonWizardBrowse=T&elusuri...
ButtonNewFolder=&Buat Folder Baru

; *** Pemilihan Bahasa
SelectLanguageTitle=Pilih Bahasa Pemasangan
SelectLanguageLabel=Pilih bahasa yang akan digunakan selama proses pemasangan.

; *** Teks Wizard Umum
ClickNext=Klik Lanjut untuk melanjutkan, atau klik Batal untuk keluar dari pemasangan.
BeveledLabel=
BrowseDialogTitle=Telusuri Folder
BrowseDialogLabel=Pilih folder dari daftar di bawah ini, lalu klik OK.
NewFolderName=Folder Baru

; *** Halaman Selamat Datang
WelcomeLabel1=Selamat Datang di Pemasang [name]
WelcomeLabel2=Pemasang ini akan memandu Anda memasang [name/ver] di komputer Anda.%n%nDisarankan untuk menutup aplikasi lain sebelum melanjutkan proses pemasangan.

; *** Halaman Lisensi & Perjanjian
WizardLicense=Perjanjian Lisensi
LicenseLabel=Harap baca informasi penting berikut sebelum melanjutkan.
LicenseLabel3=Harap baca Perjanjian Lisensi berikut. Anda harus menyetujui ketentuan ini sebelum melanjutkan pemasangan.
LicenseAccepted=Saya &menyetujui perjanjian ini
LicenseNotAccepted=Saya &tidak menyetujui perjanjian ini

; *** Halaman Informasi
WizardInfoBefore=Informasi Aplikasi
InfoBeforeLabel=Harap baca ringkasan informasi berikut sebelum melanjutkan.
InfoBeforeClickLabel=Jika Anda sudah siap melanjutkan, klik Lanjut.
WizardInfoAfter=Informasi Aplikasi
InfoAfterLabel=Harap baca informasi berikut sebelum melanjutkan.
InfoAfterClickLabel=Jika Anda sudah siap melanjutkan, klik Lanjut.

; *** Halaman Pemilihan Folder Tujuan
WizardSelectDir=Pilih Lokasi Pemasangan
SelectDirDesc=Di mana [name] sebaiknya dipasang?
SelectDirLabel3=Pemasang akan memasang [name] ke dalam folder berikut.
SelectDirBrowseLabel=Untuk melanjutkan, klik Lanjut. Jika Anda ingin memilih folder lain, klik Telusuri.
DiskSpaceGBLabel=Memerlukan setidaknya [gb] GB ruang kosong pada penyimpanan.
DiskSpaceMBLabel=Memerlukan setidaknya [mb] MB ruang kosong pada penyimpanan.
CannotInstallToNetworkDrive=Pemasang tidak dapat memasang ke drive jaringan.
CannotInstallToUNCPath=Pemasang tidak dapat memasang ke jalur UNC.
InvalidPath=Anda harus memasukkan jalur lengkap disertai huruf drive, contohnya:%n%nC:\Aplikasi%n%natau jalur UNC berupa:%n%n\\server\berbagi
InvalidDrive=Drive atau jalur penyimpanan yang Anda pilih tidak tersedia atau tidak dapat diakses. Silakan pilih lokasi lain.
DiskSpaceWarningTitle=Ruang Penyimpanan Tidak Mencukupi
DiskSpaceWarning=Pemasang memerlukan setidaknya %1 KB ruang kosong untuk memasang, tetapi drive yang dipilih hanya memiliki sisa %2 KB.%n%nApakah Anda ingin tetap melanjutkan?
DirNameTooLong=Nama folder atau jalurnya terlalu panjang.
InvalidDirName=Nama folder tidak valid.
BadDirName32=Nama folder tidak boleh memuat karakter berikut:%n%n%1
DirExistsTitle=Folder Sudah Ada
DirExists=Folder:%n%n%1%n%nsudah ada. Apakah Anda tetap ingin memasang ke folder tersebut?
DirDoesntExistTitle=Folder Belum Ada
DirDoesntExist=Folder:%n%n%1%n%nbelum ada. Apakah Anda ingin membuat folder tersebut sekarang?

; *** Halaman Pemilihan Komponen
WizardSelectComponents=Pilih Komponen
SelectComponentsDesc=Komponen apa saja yang ingin dipasang?
SelectComponentsLabel2=Pilih komponen yang ingin dipasang; hilangkan tanda centang pada komponen yang tidak diinginkan. Klik Lanjut jika sudah siap.
FullInstallation=Pemasangan Lengkap
CompactInstallation=Pemasangan Ringkas
CustomInstallation=Pemasangan Kustom
NoUninstallWarningTitle=Komponen Sudah Terpasang
NoUninstallWarning=Pemasang mendeteksi komponen berikut telah terpasang di komputer Anda:%n%n%1%n%nMenghilangkan centang pada komponen ini tidak akan menghapus komponen tersebut.%n%nApakah Anda ingin tetap melanjutkan?
ComponentSize1=%1 KB
ComponentSize2=%1 MB
ComponentsDiskSpaceGBLabel=Pilihan komponen saat ini memerlukan setidaknya [gb] GB ruang penyimpanan.
ComponentsDiskSpaceMBLabel=Pilihan komponen saat ini memerlukan setidaknya [mb] MB ruang penyimpanan.

; *** Halaman Pengaturan Tambahan (Tasks)
WizardSelectTasks=Pilih Pengaturan Tambahan
SelectTasksDesc=Pintasan apa saja yang ingin dibuat di komputer Anda?
SelectTasksLabel2=Pilih pengaturan tambahan yang ingin dijalankan saat memasang [name], lalu klik Lanjut.

; *** Halaman Menu Mulai (Start Menu)
WizardSelectProgramGroup=Pilih Folder Menu Mulai
SelectStartMenuFolderDesc=Di folder mana pintasan aplikasi sebaiknya dibuat?
SelectStartMenuFolderLabel3=Pemasang akan membuat pintasan aplikasi pada folder Menu Mulai berikut.
SelectStartMenuFolderBrowseLabel=Untuk melanjutkan, klik Lanjut. Jika Anda ingin memilih folder lain, klik Telusuri.
MustEnterGroupName=Anda harus memasukkan nama folder.
GroupNameTooLong=Nama folder atau jalur terlalu panjang.
InvalidGroupName=Nama folder tidak valid.
BadGroupName=Nama folder tidak boleh memuat karakter berikut:%n%n%1
NoProgramGroupCheck2=&Jangan buat folder di Menu Mulai

; *** Halaman Siap Pasang
WizardReady=Siap Memasang
ReadyLabel1=Pemasang telah siap memulai proses pemasangan [name] di komputer Anda.
ReadyLabel2a=Klik Pasang untuk memulai proses pemasangan, atau klik Kembali jika Anda ingin meninjau atau mengubah pengaturan lokasi.
ReadyLabel2b=Klik Pasang untuk melanjutkan pemasangan.
ReadyMemoUserInfo=Informasi pengguna:
ReadyMemoDir=Lokasi tujuan:
ReadyMemoType=Tipe pemasangan:
ReadyMemoComponents=Komponen terpilih:
ReadyMemoGroup=Folder Menu Mulai:
ReadyMemoTasks=Pengaturan tambahan:

; *** Halaman Mempersiapkan Pemasangan
WizardPreparing=Mempersiapkan Pemasangan
PreparingDesc=Pemasang sedang mempersiapkan pemasangan [name] di komputer Anda.
PreviousInstallNotCompleted=Proses pemasangan atau penghapusan aplikasi sebelumnya belum selesai secara tuntas. Anda perlu memuat ulang (restart) komputer untuk menyelesaikannya.%n%nSetelah komputer dimulai ulang, jalankan kembali pemasang ini untuk melanjutkan pemasangan [name].
CannotContinue=Pemasang tidak dapat melanjutkan. Silakan klik Batal untuk keluar.
ApplicationsFound=Aplikasi berikut sedang menggunakan berkas yang perlu diperbarui oleh Pemasang. Disarankan agar Anda mengizinkan Pemasang menutup aplikasi-aplikasi ini secara otomatis.
ApplicationsFound2=Aplikasi berikut sedang menggunakan berkas yang perlu diperbarui oleh Pemasang. Disarankan agar Anda mengizinkan Pemasang menutup aplikasi-aplikasi ini secara otomatis. Setelah proses selesai, Pemasang akan mencoba membukanya kembali.
CloseApplications=&Tutup aplikasi secara otomatis
DontCloseApplications=&Jangan tutup aplikasi
ErrorCloseApplications=Pemasang tidak dapat menutup seluruh aplikasi secara otomatis. Disarankan untuk menutup seluruh aplikasi yang bersangkutan sebelum melanjutkan.
PrepareToInstallNeedsRestart=Pemasang perlu memuat ulang komputer Anda. Setelah komputer dimulai ulang, jalankan kembali Pemasang untuk menyelesaikan pemasangan [name].%n%nApakah Anda ingin memuat ulang komputer sekarang?

; *** Halaman Pemasangan Berjalan
WizardInstalling=Sedang Memasang
InstallingLabel=Mohon tunggu sementara Pemasang memasang [name] di komputer Anda...

; *** Halaman Pemasangan Selesai
FinishedHeadingLabel=Pemasangan [name] Selesai
FinishedLabelNoIcons=Pemasang telah selesai memasang [name] di komputer Anda.
FinishedLabel=Pemasang telah selesai memasang [name] di komputer Anda. Aplikasi kini siap digunakan melalui pintasan yang telah dibuat.
ClickFinish=Klik Selesai untuk menutup jendela pemasang.
FinishedRestartLabel=Untuk menyelesaikan pemasangan [name], komputer Anda harus dimuat ulang (restart). Apakah Anda ingin memuat ulang sekarang?
FinishedRestartMessage=Untuk menyelesaikan pemasangan [name], komputer Anda harus dimuat ulang (restart).%n%nApakah Anda ingin memuat ulang sekarang?
ShowReadmeCheck=Ya, saya ingin melihat catatan rilis (README)
YesRadio=&Ya, muat ulang komputer sekarang
NoRadio=&Tidak, saya akan memuat ulang komputer nanti
RunEntryExec=Jalankan %1
RunEntryShellExec=Buka %1

; *** Status Pemasangan
StatusClosingApplications=Menutup aplikasi yang berjalan...
StatusCreateDirs=Membuat direktori...
StatusExtractFiles=Mengekstrak berkas...
StatusDownloadFiles=Mengunduh berkas...
StatusCreateIcons=Membuat pintasan...
StatusCreateIniEntries=Membuat entri konfigurasi...
StatusCreateRegistryEntries=Mendaftarkan entri registri...
StatusRegisterFiles=Mendaftarkan modul sistem...
StatusSavingUninstall=Menyimpan informasi penghapusan...
StatusRunProgram=Menyelesaikan proses pemasangan...
StatusRestartingApplications=Membuka kembali aplikasi...
StatusRollback=Mengembalikan perubahan sistem...

; *** Pembatalan dan Penanganan Masalah
SetupAborted=Pemasangan belum selesai sepenuhnya.%n%nSilakan perbaiki kendala yang terjadi lalu jalankan kembali pemasang.
AbortRetryIgnoreSelectAction=Pilih tindakan
AbortRetryIgnoreRetry=&Coba lagi
AbortRetryIgnoreIgnore=&Abaikan kesalahan dan lanjutkan
AbortRetryIgnoreCancel=Batalkan pemasangan
RetryCancelSelectAction=Pilih tindakan
RetryCancelRetry=&Coba lagi
RetryCancelCancel=Batal

; *** Kesalahan Berkas & Eksekusi
ErrorInternal2=Kesalahan internal: %1
ErrorFunctionFailedNoCode=%1 gagal dijalankan.
ErrorFunctionFailed=%1 gagal dijalankan; kode %2.
ErrorFunctionFailedWithMessage=%1 gagal dijalankan; kode %2.%n%3
ErrorExecutingProgram=Tidak dapat menjalankan berkas:%n%1
ErrorCreatingTemp=Terjadi kesalahan saat membuat berkas pada folder tujuan:
ErrorReadingSource=Terjadi kesalahan saat membaca berkas sumber:
ErrorCopying=Terjadi kesalahan saat menyalin berkas:
ErrorReplacingExistingFile=Terjadi kesalahan saat mengganti berkas yang sudah ada:

; *** Keterangan Tampilan Uninstaller
UninstallDisplayNameMark=%1 (%2)
UninstallDisplayNameMarks=%1 (%2, %3)
UninstallDisplayNameMark32Bit=32-bit
UninstallDisplayNameMark64Bit=64-bit
UninstallDisplayNameMarkAllUsers=Semua pengguna
UninstallDisplayNameMarkCurrentUser=Pengguna saat ini

; *** Pesan Program Penghapus (Uninstaller)
UninstallNotFound=Berkas "%1" tidak ditemukan. Penghapusan tidak dapat dilakukan.
UninstallOpenError=Berkas "%1" tidak dapat dibuka. Penghapusan tidak dapat dilakukan.
UninstallUnsupportedVer=Berkas catatan penghapusan "%1" memiliki format yang tidak dikenali. Penghapusan dibatalkan.
UninstallUnknownEntry=Entri tidak dikenal (%1) ditemukan pada catatan penghapusan.
ConfirmUninstall=Apakah Anda yakin ingin menghapus %1 beserta seluruh komponen aplikasinya dari komputer ini?
UninstallOnlyOnWin64=Pemasangan ini hanya dapat dihapus pada Windows 64-bit.
OnlyAdminCanUninstall=Penghapusan aplikasi ini hanya dapat dilakukan oleh pengguna dengan hak akses administrator.
UninstallStatusLabel=Mohon tunggu sementara %1 dihapus dari komputer Anda...
UninstalledAll=%1 telah berhasil dihapus dari komputer Anda.
UninstalledMost=Penghapusan %1 telah selesai.%n%nBeberapa berkas atau folder sisa tidak dapat dihapus secara otomatis dan dapat Anda bersihkan secara manual.
UninstalledAndNeedsRestart=Untuk menyelesaikan penghapusan %1 secara tuntas, komputer Anda harus dimuat ulang (restart).%n%nApakah Anda ingin memuat ulang komputer sekarang?
UninstallDataCorrupted=Berkas "%1" rusak. Penghapusan tidak dapat dilakukan.

; *** Tahap Uninstalasi
ConfirmDeleteSharedFileTitle=Hapus Berkas Bersama?
ConfirmDeleteSharedFile2=Sistem menunjukkan bahwa berkas bersama berikut sudah tidak digunakan oleh program lain. Apakah Anda ingin menghapusnya?%n%nJika ada program lain yang masih membutuhkannya dan berkas dihapus, program tersebut mungkin tidak akan berjalan dengan normal. Jika ragu, pilih Tidak. Membiarkan berkas ini di sistem Anda tidak berbahaya.
SharedFileNameLabel=Nama berkas:
SharedFileLocationLabel=Lokasi:
WizardUninstalling=Status Penghapusan
StatusUninstalling=Menghapus %1...

; *** Alasan Pemblokiran Shutdown
ShutdownBlockReasonInstallingApp=Sedang memasang %1.
ShutdownBlockReasonUninstallingApp=Sedang menghapus %1.

; *** Kustom Pesan
[CustomMessages]
NameAndVersion=%1 versi %2
AdditionalIcons=Pintasan tambahan:
CreateDesktopIcon=Buat pintasan di &Layar Utama (Desktop)
CreateQuickLaunchIcon=Buat pintasan di &Bilah Tugas Cepat (Quick Launch)
ProgramOnTheWeb=%1 di Web
UninstallProgram=Hapus Pemasangan %1
LaunchProgram=Jalankan %1
AssocFileExtension=&Tautkan %1 dengan ekstensi berkas %2
AssocingFileExtension=Menautkan %1 dengan ekstensi berkas %2...
AutoStartProgramGroupDescription=Jalankan otomatis saat komputer menyala:
AutoStartProgram=Jalankan %1 secara otomatis saat masuk ke Windows
AddonHostProgramNotFound=%1 tidak ditemukan pada folder yang Anda pilih.%n%nApakah Anda ingin tetap melanjutkan?
