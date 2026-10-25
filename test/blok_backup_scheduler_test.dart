import 'dart:io';

import 'package:cek_pbb_app/app_storage.dart';
import 'package:cek_pbb_app/backup_password_store.dart';
import 'package:cek_pbb_app/blok_backup_scheduler.dart';
import 'package:cek_pbb_app/blok_data_store.dart';
import 'package:cek_pbb_app/blok_record.dart';
import 'package:cek_pbb_app/dkhp_package_helper.dart';
import 'package:cek_pbb_app/google_auth_service.dart';
import 'package:cek_pbb_app/google_drive_backup_policy.dart';
import 'package:cek_pbb_app/settings_screen.dart';
import 'package:cek_pbb_app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _backupPassword = 'test-password-for-backups';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final secureStorageValues = <String, String>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStorageValues.clear();
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return secureStorageValues[arguments['key']];
        case 'write':
          secureStorageValues[arguments['key'] as String] =
              arguments['value'] as String;
          return null;
        case 'delete':
          secureStorageValues.remove(arguments['key']);
          return null;
        case 'containsKey':
          return secureStorageValues.containsKey(arguments['key']);
        case 'deleteAll':
          secureStorageValues.clear();
          return null;
      }
      return null;
    });
    await BackupPasswordStore.instance.save(_backupPassword);
    tempDir = await Directory.systemTemp.createTemp('backup_scheduler_test_');
    AppStorage.setMockDirectories(dataDir: tempDir, mediaDir: tempDir);
    BlokDataStore.instance.resetForTesting();
    BlokBackupScheduler.instance.resetForTesting();
    GoogleAuthService.resetForTesting();
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    AppStorage.resetForTesting();
    BlokDataStore.instance.resetForTesting();
    BlokBackupScheduler.instance.resetForTesting();
    GoogleAuthService.resetForTesting();
  });

  group('BlokBackupScheduler - Preferensi', () {
    test('nilai default preferensi cadangan sesuai spesifikasi', () async {
      final scheduler = BlokBackupScheduler.instance;
      expect(await scheduler.getFrequencyDays(), 1); // 1 = Harian pk 02:00
      expect(await scheduler.getOnlyDkhpData(), true); // Hemat memori tanpa foto
      expect(await scheduler.getGoogleAccount(), '');
      expect(await scheduler.getOverCellular(), false); // Wi-Fi saja
      expect(await scheduler.getLastBackupTime(), isNull);
      expect(await scheduler.getLastBackupSize(), isNull);
      expect(await scheduler.isDirty(), false);
    });

    test('update preferensi tersimpan permanen di SharedPreferences', () async {
      final scheduler = BlokBackupScheduler.instance;

      await scheduler.setFrequencyDays(7);
      expect(await scheduler.getFrequencyDays(), 7);

      await scheduler.setOnlyDkhpData(false);
      expect(await scheduler.getOnlyDkhpData(), false);

      await scheduler.setGoogleAccount('bapenda@cianjur.go.id');
      expect(await scheduler.getGoogleAccount(), 'bapenda@cianjur.go.id');

      await scheduler.setOverCellular(true);
      expect(await scheduler.getOverCellular(), true);

      await scheduler.markDirty();
      expect(await scheduler.isDirty(), true);

      await scheduler.clearDirty();
      expect(await scheduler.isDirty(), false);
    });
  });

  group('BlokBackupScheduler - Logika Penjadwalan ala WhatsApp (02:00)', () {
    final scheduler = BlokBackupScheduler.instance;

    test('frekuensi 0 (manual) tidak pernah otomatis due', () {
      final now = DateTime(2026, 10, 23, 2, 30);
      final last = DateTime(2026, 10, 20, 2, 0);
      expect(
        scheduler.isBackupDue(now: now, lastBackupTime: last, frequencyDays: 0),
        isFalse,
      );
    });

    test('belum pernah backup (lastBackupTime == null) selalu due jika frekuensi > 0', () {
      final now = DateTime(2026, 10, 23, 10, 0);
      expect(
        scheduler.isBackupDue(now: now, lastBackupTime: null, frequencyDays: 1),
        isTrue,
      );
    });

    test('frekuensi 1 hari: hari yang sama tidak due lagi', () {
      final last = DateTime(2026, 10, 23, 2, 0);
      final now = DateTime(2026, 10, 23, 14, 0); // Hari yang sama jam 14:00
      expect(
        scheduler.isBackupDue(now: now, lastBackupTime: last, frequencyDays: 1),
        isFalse,
      );
    });

    test('frekuensi 1 hari: berbeda hari dan sudah lewat pk 02:00 pagi -> due', () {
      final last = DateTime(2026, 10, 22, 2, 0);
      final now = DateTime(2026, 10, 23, 2, 5); // Hari berikutnya jam 02:05
      expect(
        scheduler.isBackupDue(now: now, lastBackupTime: last, frequencyDays: 1),
        isTrue,
      );
    });

    test('frekuensi 1 hari: berbeda hari tapi sebelum pk 02:00 pagi dan belum 24 jam -> tidak due', () {
      final last = DateTime(2026, 10, 22, 2, 0);
      final now = DateTime(2026, 10, 23, 1, 15); // Jam 01:15 (baru 23 jam 15 menit)
      expect(
        scheduler.isBackupDue(now: now, lastBackupTime: last, frequencyDays: 1),
        isFalse,
      );
    });

    test('frekuensi 1 hari: berbeda hari sebelum pk 02:00 tapi selisih sudah >= 24 jam -> due', () {
      final last = DateTime(2026, 10, 21, 23, 0);
      final now = DateTime(2026, 10, 23, 1, 0); // Selisih 26 jam
      expect(
        scheduler.isBackupDue(now: now, lastBackupTime: last, frequencyDays: 1),
        isTrue,
      );
    });

    test('frekuensi mingguan (7 hari), 14 hari, dan 30 hari', () {
      final last = DateTime(2026, 10, 10, 10, 0);

      // 6 hari kemudian -> belum 7 hari
      expect(
        scheduler.isBackupDue(
          now: DateTime(2026, 10, 16, 10, 0),
          lastBackupTime: last,
          frequencyDays: 7,
        ),
        isFalse,
      );

      // 7 hari kemudian -> due
      expect(
        scheduler.isBackupDue(
          now: DateTime(2026, 10, 17, 10, 0),
          lastBackupTime: last,
          frequencyDays: 7,
        ),
        isTrue,
      );

      // 14 hari
      expect(
        scheduler.isBackupDue(
          now: DateTime(2026, 10, 23, 10, 0),
          lastBackupTime: last,
          frequencyDays: 14,
        ),
        isFalse, // 13 hari
      );
      expect(
        scheduler.isBackupDue(
          now: DateTime(2026, 10, 24, 10, 0),
          lastBackupTime: last,
          frequencyDays: 14,
        ),
        isTrue, // 14 hari
      );
    });
  });

  group('BlokBackupScheduler - Kebijakan Retensi Maksimal 3 Berkas', () {
    test('jika cadangan melebihi 3 berkas, berkas terlama otomatis dihapus', () async {
      final scheduler = BlokBackupScheduler.instance;
      final backupsDir = await AppStorage.getBackupsDirectory();

      // Buat 4 berkas dummy cadangan dengan timestamp berbeda
      final file1 = File('${backupsDir.path}/cadangan_1.dkhp');
      await file1.writeAsString('backup-1');
      await file1.setLastModified(DateTime(2026, 10, 20, 2, 0));

      final file2 = File('${backupsDir.path}/cadangan_2.dkhp');
      await file2.writeAsString('backup-2');
      await file2.setLastModified(DateTime(2026, 10, 21, 2, 0));

      final file3 = File('${backupsDir.path}/cadangan_3.dkhp');
      await file3.writeAsString('backup-3');
      await file3.setLastModified(DateTime(2026, 10, 22, 2, 0));

      final file4 = File('${backupsDir.path}/cadangan_4.dkhp');
      await file4.writeAsString('backup-4');
      await file4.setLastModified(DateTime(2026, 10, 23, 2, 0));

      // Verifikasi awal: ada 4 berkas
      var currentFiles = await scheduler.getLocalBackups();
      expect(currentFiles.length, 4);

      // Pangkas ke maksimal 3 berkas
      final remaining = await scheduler.pruneOldBackups(maxFiles: 3);
      expect(remaining.length, 3);

      // File terlama (cadangan_1.dkhp) harus sudah terhapus
      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isTrue);
      expect(file3.existsSync(), isTrue);
      expect(file4.existsSync(), isTrue);

      // Tambahkan file ke-5
      final file5 = File('${backupsDir.path}/cadangan_5.dkhp');
      await file5.writeAsString('backup-5');
      await file5.setLastModified(DateTime(2026, 10, 24, 2, 0));

      await scheduler.pruneOldBackups(maxFiles: 3);

      // Sekarang cadangan_2.dkhp juga harus terhapus, tersisa file 3, 4, 5
      expect(file2.existsSync(), isFalse);
      expect(file3.existsSync(), isTrue);
      expect(file4.existsSync(), isTrue);
      expect(file5.existsSync(), isTrue);

      final finalFiles = await scheduler.getLocalBackups();
      expect(finalFiles.length, 3);
      // Urutan getLocalBackups: terbaru ke terlama
      expect(finalFiles.first.path, file5.path);
      expect(finalFiles.last.path, file3.path);
    });
  });

  group('BlokBackupScheduler - Eksekusi Cadangan performBackup & runIfNeeded', () {
    test('runIfNeeded melewati backup jika belum ada data DHKP yang dimuat', () async {
      final scheduler = BlokBackupScheduler.instance;
      await BackupPasswordStore.instance.clear();
      await scheduler.setFrequencyDays(1);
      await scheduler.markDirty();

      expect(await scheduler.runIfNeeded(), isFalse);
      expect(await scheduler.isDirty(), isTrue);
    });

    test('performBackup dengan onlyDkhpData true mengekspor paket perubahan dkhp tanpa kata sandi manual dan merotasi retensi', () async {
      final scheduler = BlokBackupScheduler.instance;
      await BackupPasswordStore.instance.clear();

      // Isi BlokDataStore dengan dummy record
      await BlokDataStore.instance.upsert(
        BlokRecord(
          namaWajibPajak: 'Haji Sulaiman',
          nop: '320520000402600100',
          tahunBayar: '2026',
          tanggalBayar: '2026-05-10',
          jumlahPbb: '150000',
          statusBayar: 'Sudah Bayar',
          catatan: 'Lunas via Teller',
        ),
      );

      expect(await scheduler.isDirty(), true);

      // Eksekusi cadangan
      final file = await scheduler.performBackup(onlyDkhpData: true);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(file.path.endsWith('.dkhp'), isTrue);

      // Cek status setelah cadangan
      expect(await scheduler.isDirty(), false);
      expect(await scheduler.getLastBackupTime(), isNotNull);
      expect(await scheduler.getLastBackupSize(), greaterThan(0));
      expect(await scheduler.getLastBackupPath(), file.path);

      // Cek isi berkas .dkhp dengan unpack (tanpa kata sandi manual)
      final records = await DhkpPackageHelper.unpackDkhp(
        file.path,
        requireBaseDhkp: true,
      );
      expect(records.any((r) => r.namaWajibPajak == 'Haji Sulaiman'), isTrue);
    });

    test('runIfNeeded menghormati jadwal dan status dirty tanpa memerlukan kata sandi manual', () async {
      final scheduler = BlokBackupScheduler.instance;
      await BackupPasswordStore.instance.clear();

      // Pastikan ada berkas DHKP dasar yang dimuat
      await BlokDataStore.instance.upsert(
        const BlokRecord(
          namaWajibPajak: 'Asep Sunandar',
          nop: '320520000402600150',
          tahunBayar: '2026',
          tanggalBayar: '2026-06-01',
          jumlahPbb: '95000',
          statusBayar: 'Sudah Bayar',
          catatan: 'Lunas',
        ),
      );

      // Frekuensi 0 -> tidak jalan
      await scheduler.setFrequencyDays(0);
      expect(await scheduler.runIfNeeded(), isFalse);

      // Set frekuensi harian 1 dan tandai dirty
      await scheduler.setFrequencyDays(1);
      await scheduler.markDirty();

      // Belum pernah backup sama sekali dan dirty -> jalan otomatis tanpa password
      final ran = await scheduler.runIfNeeded();
      expect(ran, isTrue);

      // Langsung panggil lagi hari yang sama dan sudah tidak dirty -> tidak jalan
      final ranAgain = await scheduler.runIfNeeded();
      expect(ranAgain, isFalse);
    });
  });

  group('SettingsScreen & BackupSettingsScreen - UI & Interaksi', () {
    testWidgets('menampilkan bagian cadangan data DHKP dan komponen pengaturannya', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ThemeController();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            themeController: controller,
            isMaterialYouSupported: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buka menu Pencadangan Data
      await tester.tap(find.text('Pencadangan Data'));
      await tester.pumpAndSettle();

      // Verifikasi judul dan deskripsi cadangan
      expect(find.text('Cadangan Data DHKP'), findsOneWidget);
      expect(find.text('Cadangan Terakhir'), findsOneWidget);
      expect(find.text('Cadangkan Sekarang'), findsOneWidget);
      expect(find.text('Cadangkan Otomatis'), findsOneWidget);
      expect(find.textContaining('Akun Google'), findsOneWidget);
      expect(find.text('Hanya Data DHKP Saja'), findsOneWidget);
      expect(find.text('Cadangkan Lewat'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('tombol Cadangkan Sekarang berhasil membuat cadangan dan menampilkan SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Tambahkan data dummy
      await BlokDataStore.instance.upsert(
        BlokRecord(
          namaWajibPajak: 'Wajib Pajak Desa',
          nop: '320520000402600200',
          tahunBayar: '2026',
          tanggalBayar: '',
          jumlahPbb: '75000',
          statusBayar: 'Belum Bayar',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: BackupSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final backupBtn = find.text('Cadangkan Sekarang');
      expect(backupBtn, findsOneWidget);

      await tester.tap(backupBtn);
      await tester.pump();

      await tester.runAsync(() async {
        while (find.text('Sedang Mencadangkan...').evaluate().isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('Berkas Cadangan'), findsOneWidget);
      expect(find.textContaining('Cadangan data DHKP berhasil disimpan'), findsOneWidget);
      expect(find.textContaining('cadangan_dkhp_data_'), findsOneWidget);
    });

    testWidgets('dialog frekuensi otomatis dapat mengubah frekuensi cadangan', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: BackupSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap opsi Cadangkan Otomatis
      await tester.tap(find.text('Cadangkan Otomatis'));
      await tester.pumpAndSettle();

      // Dialog terbuka dengan pilihan frekuensi
      expect(find.text('Frekuensi Cadangan Otomatis'), findsOneWidget);
      expect(find.text('Mingguan (setiap 7 hari)'), findsOneWidget);
      expect(find.text('Setiap 14 hari'), findsOneWidget);
      expect(find.text('Bulanan (setiap 30 hari)'), findsOneWidget);
      expect(find.text('Jangan pernah (Hanya manual)'), findsOneWidget);

      // Pilih Mingguan (setiap 7 hari)
      await tester.tap(find.text('Mingguan (setiap 7 hari)'));
      await tester.pumpAndSettle();

      // Nilai tersimpan di scheduler
      expect(await BlokBackupScheduler.instance.getFrequencyDays(), 7);
      expect(find.text('Mingguan (setiap 7 hari)'), findsOneWidget);
    });
  });

  group('GoogleDriveBackupPolicy - Kebijakan Keamanan & Pembatasan Folder Khusus', () {
    test('hanya scope terbatas (drive.appdata, drive.file, drive.readonly) yang diizinkan dan scope penuh dilarang', () {
      expect(
        GoogleDriveBackupPolicy.isScopeAllowed(GoogleDriveBackupPolicy.allowedScopeAppData),
        isTrue,
      );
      expect(
        GoogleDriveBackupPolicy.isScopeAllowed(GoogleDriveBackupPolicy.allowedScopeDriveFile),
        isTrue,
      );
      expect(
        GoogleDriveBackupPolicy.isScopeAllowed(GoogleDriveBackupPolicy.allowedScopeDriveReadonly),
        isTrue,
      );

      // Scope penuh baca-tulis seluruh Drive dilarang keras demi privasi pengguna
      expect(
        GoogleDriveBackupPolicy.isScopeAllowed('https://www.googleapis.com/auth/drive'),
        isFalse,
      );
    });

    test('hanya folder khusus "Cek PBB Cianjur" dan "appDataFolder" yang diizinkan', () {
      expect(GoogleDriveBackupPolicy.isFolderAllowed('Cek PBB Cianjur'), isTrue);
      expect(GoogleDriveBackupPolicy.isFolderAllowed('appDataFolder'), isTrue);

      // Folder kustom spesifik diizinkan jika dicocokkan dengan ID-nya
      expect(
        GoogleDriveBackupPolicy.isFolderAllowed('1ABC_custom_folder_id', customFolderId: '1ABC_custom_folder_id'),
        isTrue,
      );

      // Folder lain dilarang diakses
      expect(GoogleDriveBackupPolicy.isFolderAllowed('root'), isFalse);
      expect(GoogleDriveBackupPolicy.isFolderAllowed('Dokumen Pribadi'), isFalse);
      expect(GoogleDriveBackupPolicy.isFolderAllowed('Foto Liburan'), isFalse);
      expect(GoogleDriveBackupPolicy.isFolderAllowed(''), isFalse);
    });

    test('extractFolderId mengekstrak ID folder dari berbagai format URL Google Drive', () {
      // Format URL share link biasa
      expect(
        GoogleDriveBackupPolicy.extractFolderId(
          'https://drive.google.com/drive/folders/1aBcDeFgHiJkLmNoPqRsTuVwXyZ?usp=sharing',
        ),
        '1aBcDeFgHiJkLmNoPqRsTuVwXyZ',
      );

      // Format URL dengan user session /u/0/
      expect(
        GoogleDriveBackupPolicy.extractFolderId(
          'https://drive.google.com/drive/u/0/folders/1XYZ_987-abc12345678',
        ),
        '1XYZ_987-abc12345678',
      );

      // Format ID mentah
      expect(
        GoogleDriveBackupPolicy.extractFolderId('1aBcDeFgHiJkLmNoPqRsTuVwXyZ'),
        '1aBcDeFgHiJkLmNoPqRsTuVwXyZ',
      );

      // Teks acak tidak valid
      expect(GoogleDriveBackupPolicy.extractFolderId('bukan link folder'), isNull);
      expect(GoogleDriveBackupPolicy.extractFolderId(''), isNull);
    });

    test('validateAccess melempar SecurityException bila mencoba mengakses folder lain atau scope terlarang', () {
      // Akses valid
      expect(
        () => GoogleDriveBackupPolicy.validateAccess(
          targetFolder: 'Cek PBB Cianjur',
          requestedScopes: [GoogleDriveBackupPolicy.allowedScopeDriveFile],
        ),
        returnsNormally,
      );

      // Pelanggaran folder
      expect(
        () => GoogleDriveBackupPolicy.validateAccess(
          targetFolder: 'FolderLain',
          requestedScopes: [GoogleDriveBackupPolicy.allowedScopeDriveFile],
        ),
        throwsA(isA<SecurityException>()),
      );

      // Pelanggaran scope
      expect(
        () => GoogleDriveBackupPolicy.validateAccess(
          targetFolder: 'Cek PBB Cianjur',
          requestedScopes: ['https://www.googleapis.com/auth/drive'],
        ),
        throwsA(isA<SecurityException>()),
      );
    });

    test('BlokBackupScheduler menyediakan konfigurasi folder khusus Google Drive', () {
      final scheduler = BlokBackupScheduler.instance;
      expect(scheduler.googleDriveDedicatedFolder, 'Cek PBB Cianjur');
      expect(
        scheduler.googleDriveAllowedScopes,
        contains(GoogleDriveBackupPolicy.allowedScopeDriveFile),
      );
      expect(
        scheduler.googleDriveAllowedScopes,
        contains(GoogleDriveBackupPolicy.allowedScopeAppData),
      );
    });

    testWidgets('dialog Akun Google menampilkan jaminan keamanan folder khusus dan larangan akses berkas lain', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: BackupSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap opsi Akun Google
      final googleTile = find.textContaining('Akun Google');
      await tester.ensureVisible(googleTile);
      await tester.tap(googleTile);
      await tester.pumpAndSettle();

      // Dialog terbuka dengan jaminan privasi dan pembatasan folder khusus
      expect(find.text(GoogleDriveBackupPolicy.privacyNoticeTitle), findsOneWidget);
      expect(find.text(GoogleDriveBackupPolicy.privacyNoticeBody), findsOneWidget);
      expect(find.textContaining('Cek PBB Cianjur'), findsWidgets);
      expect(find.text('Izin Akses Google Drive'), findsOneWidget);

      // Verifikasi TIDAK ADA input manual (tidak ada TextField)
      expect(find.byType(TextField), findsNothing);

      // Simulasikan login resmi Google Auth dengan izin Google Drive
      GoogleAuthService.mockUser = const GoogleAuthUser(
        email: 'petugas@gmail.com',
        displayName: 'Petugas PBB',
        photoUrl: 'https://avatar.google.com/petugas.png',
        id: '12345678',
      );

      final loginBtn = find.textContaining('Masuk & Izinkan Google Drive');
      expect(loginBtn, findsOneWidget);
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      // Email tersimpan dan kartu terupdate
      expect(await BlokBackupScheduler.instance.getGoogleAccount(), 'petugas@gmail.com');
      expect(await BlokBackupScheduler.instance.getGoogleDisplayName(), 'Petugas PBB');
      expect(find.textContaining('petugas@gmail.com'), findsWidgets);
      expect(find.textContaining('Folder: Cek PBB Cianjur'), findsOneWidget);
    });

    test('syarat link folder bersama: harus terhubung akun Google terlebih dahulu', () async {
      final scheduler = BlokBackupScheduler.instance;
      // 1. Akun Google masih kosong
      expect(await scheduler.getGoogleAccount(), isEmpty);

      // Coba set link folder bersama -> harus gagal
      final failedSet = await scheduler.setGoogleDriveFolderLink(
        'https://drive.google.com/drive/folders/1ABC_shared_folder_xyz123',
      );
      expect(failedSet, isFalse);
      expect(await scheduler.getGoogleDriveFolderLink(), isEmpty);
      expect(await scheduler.getEffectiveGoogleDriveFolder(), 'Cek PBB Cianjur');

      // 2. Hubungkan akun Google terlebih dahulu
      await scheduler.setGoogleAccount('petugas@gmail.com');
      expect(await scheduler.getGoogleAccount(), 'petugas@gmail.com');

      // Sekarang set link folder bersama -> harus berhasil
      final successSet = await scheduler.setGoogleDriveFolderLink(
        'https://drive.google.com/drive/folders/1ABC_shared_folder_xyz123',
      );
      expect(successSet, isTrue);
      expect(
        await scheduler.getGoogleDriveFolderLink(),
        'https://drive.google.com/drive/folders/1ABC_shared_folder_xyz123',
      );
      expect(
        await scheduler.getEffectiveGoogleDriveFolder(),
        '1ABC_shared_folder_xyz123',
      );

      // 3. Jika akun Google dilepas, link folder bersama otomatis ikut dibersihkan
      await scheduler.setGoogleAccount('');
      expect(await scheduler.getGoogleAccount(), isEmpty);
      expect(await scheduler.getGoogleDriveFolderLink(), isEmpty);
      expect(await scheduler.getEffectiveGoogleDriveFolder(), 'Cek PBB Cianjur');
    });

    testWidgets('UI folder bersama disabled saat belum login, dan aktif setelah akun terhubung', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: BackupSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Folder Bersama tampil tapi dalam keadaan dinonaktifkan (karena belum login)
      expect(find.text('Folder Bersama Google Drive'), findsOneWidget);
      expect(
        find.textContaining('Hubungkan akun Google terlebih dahulu untuk mengatur folder bersama'),
        findsOneWidget,
      );

      // Hubungkan akun Google via UI dialog dengan Google Auth
      GoogleAuthService.mockUser = const GoogleAuthUser(
        email: 'petugas@gmail.com',
        displayName: 'Petugas PBB',
        photoUrl: 'https://avatar.google.com/petugas.png',
        id: '12345678',
      );

      final googleTile = find.textContaining('Akun Google');
      await tester.ensureVisible(googleTile);
      await tester.tap(googleTile);
      await tester.pumpAndSettle();

      final loginBtn = find.textContaining('Masuk & Izinkan Google Drive');
      expect(loginBtn, findsOneWidget);
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      // Sekarang Folder Bersama aktif
      expect(find.textContaining('Gunakan folder bawaan'), findsOneWidget);
      final folderTile = find.widgetWithText(ListTile, 'Folder Bersama Google Drive');
      await tester.ensureVisible(folderTile);
      await tester.tap(folderTile);
      await tester.pumpAndSettle();

      // Dialog Folder Bersama terbuka
      expect(find.text('Folder Bersama'), findsOneWidget);
      expect(find.text('Syarat Hak Akses Folder'), findsOneWidget);
      expect(find.text(GoogleDriveBackupPolicy.editorRequirementNotice), findsOneWidget);

      // Masukkan link folder bersama
      await tester.enterText(
        find.byType(TextField),
        'https://drive.google.com/drive/folders/1ABC_shared_folder_9999',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      // Link tersimpan dan UI menampilkan folder aktif
      expect(
        await BlokBackupScheduler.instance.getEffectiveGoogleDriveFolder(),
        '1ABC_shared_folder_9999',
      );
      expect(find.textContaining('1ABC_shared_folder_9999'), findsWidgets);
    });
  });
}
