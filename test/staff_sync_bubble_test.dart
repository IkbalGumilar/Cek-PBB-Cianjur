import 'dart:async';

import 'package:cek_pbb_app/batch_notification_service.dart';
import 'package:cek_pbb_app/monitoring/monitoring_wilayah_screen.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_sync_manager.dart';
import 'package:cek_pbb_app/monitoring/staff_dhkp_sync_service.dart';
import 'package:cek_pbb_app/monitoring/staff_sync_bubble_overlay.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStaffPortalClient extends StaffPortalClient {
  Completer<MonitoringTableResult>? fetchCompleter;

  @override
  Future<MonitoringTableResult> fetchSudahBayar({
    required String tglBayarAwal,
    required String tglBayarAkhir,
    String tahunAwal = '',
    String tahunAkhir = '',
    String bukuMin = '',
    String bukuMax = '',
    String bank = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String kodeBayarKolektif = '',
    String va = '',
    String qris = '',
    String operator = '',
    String tglPelimpahanAwal = '',
    String tglPelimpahanAkhir = '',
    String kelurahan = '3205200004',
    String kecamatan = '3205200',
    int page = 1,
  }) async {
    if (fetchCompleter != null) {
      return fetchCompleter!.future;
    }
    return const MonitoringTableResult(
      headers: ['No', 'NOP', 'Nama WP', 'Pokok', 'Tgl Bayar'],
      rows: [],
      hasNextPage: false,
    );
  }

  @override
  Future<MonitoringTableResult> fetchBelumBayar({
    required String tglCutoff,
    String tahunAwal = '',
    String tahunAkhir = '',
    String nop = '',
    String namaWp = '',
    String kodeBayarIndividu = '',
    String bukuMin = '',
    String bukuMax = '',
    String kelurahan = '3205200004',
    String kecamatan = '3205200',
    int page = 1,
  }) async {
    return const MonitoringTableResult(
      headers: ['No', 'NOP', 'Nama WP', 'Pokok'],
      rows: [],
      hasNextPage: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MonitoringWilayahScreen.isCurrentlyOpen = false;
    StaffDhkpSyncManager.instance.reset();
    StaffDhkpSyncService.lastOutcome = null;
  });

  tearDown(() {
    MonitoringWilayahScreen.isCurrentlyOpen = false;
    StaffDhkpSyncManager.instance.reset();
    StaffDhkpSyncService.lastOutcome = null;
  });

  group('StaffDhkpSyncManager', () {
    test('initial state has no bubble and is not syncing', () {
      final mgr = StaffDhkpSyncManager.instance;
      expect(mgr.isSyncing, isFalse);
      expect(mgr.isSheetOpen, isFalse);
      expect(mgr.isPaused, isFalse);
      expect(mgr.isCancelled, isFalse);
      expect(mgr.isCompleted, isFalse);
      expect(mgr.isDismissed, isFalse);
      expect(mgr.shouldShowBubble, isFalse);
    });

    test('pause, cancel, and dismiss update manager state properly', () {
      final mgr = StaffDhkpSyncManager.instance;

      mgr.togglePause();
      expect(mgr.isPaused, isTrue);

      mgr.togglePause();
      expect(mgr.isPaused, isFalse);

      mgr.cancelSync();
      expect(mgr.isCancelled, isTrue);

      mgr.dismiss();
      expect(mgr.isDismissed, isTrue);
      expect(mgr.isCompleted, isFalse);
      expect(mgr.progress, isNull);
      expect(mgr.shouldShowBubble, isFalse);
    });
  });

  group('StaffSyncBubbleOverlay Widget Tests', () {
    testWidgets('renders nothing (SizedBox.shrink) when shouldShowBubble is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: Stack(
              children: [
                Text('Home Screen'),
                StaffSyncBubbleOverlay(),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Home Screen'), findsOneWidget);
      expect(find.byType(StaffSyncBubbleOverlay), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
    });

    testWidgets('renders floating bubble when sync is active and sheet is hidden', (tester) async {
      final mgr = StaffDhkpSyncManager.instance;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const StaffSyncBubbleOverlay(),
            ],
          ),
          home: const Scaffold(
            body: Text('Home Screen'),
          ),
        ),
      );

      final fakeClient = _FakeStaffPortalClient();
      final completer = Completer<MonitoringTableResult>();
      fakeClient.fetchCompleter = completer;

      // Start sync using fake client
      mgr.startSync(
        context: rootNavigatorKey.currentContext!,
        client: fakeClient,
        tahun: '2026',
        bloks: ['001'],
        kelurahan: '3205200004',
        kecamatan: '3205200',
        blokLabel: 'Blok 1',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mgr.isSheetOpen, isTrue);

      // Hide sheet -> floating bubble should now appear!
      mgr.hideSheet();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mgr.isSheetOpen, isFalse);
      expect(mgr.shouldShowBubble, isTrue);
      expect(find.byType(StaffSyncBubbleOverlay), findsOneWidget);

      // Tapping bubble re-opens modal sheet
      await tester.tap(find.byIcon(Icons.sync_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mgr.isSheetOpen, isTrue);
      expect(mgr.shouldShowBubble, isFalse);

      completer.complete(const MonitoringTableResult(headers: [], rows: []));
      await tester.pump();
    });

    testWidgets('tapping completed bubble directly opens report dialog and staff portal', (tester) async {
      final mgr = StaffDhkpSyncManager.instance;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const StaffSyncBubbleOverlay(),
            ],
          ),
          home: const Scaffold(
            body: Text('Home Screen'),
          ),
        ),
      );

      final fakeClient = _FakeStaffPortalClient();
      final completer = Completer<MonitoringTableResult>();
      fakeClient.fetchCompleter = completer;

      mgr.startSync(
        context: rootNavigatorKey.currentContext!,
        client: fakeClient,
        tahun: '2026',
        bloks: ['001'],
        kelurahan: '3205200004',
        kecamatan: '3205200',
        blokLabel: 'Blok 1',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Hide sheet
      mgr.hideSheet();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mgr.shouldShowBubble, isTrue);

      // Complete sync
      completer.complete(const MonitoringTableResult(headers: [], rows: []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mgr.isCompleted, isTrue);
      expect(mgr.shouldShowBubble, isTrue);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Tapping completed bubble should navigate to MonitoringWilayahScreen and open report dialog
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MonitoringWilayahScreen), findsOneWidget);
      expect(MonitoringWilayahScreen.isCurrentlyOpen, isTrue);

      await tester.pump();
      expect(find.text('Laporan Hasil Sinkronisasi'), findsOneWidget);
    });

    testWidgets('completed bubble auto-dismisses after 4 seconds if not tapped', (tester) async {
      final mgr = StaffDhkpSyncManager.instance;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const StaffSyncBubbleOverlay(),
            ],
          ),
          home: const Scaffold(
            body: Text('Home Screen'),
          ),
        ),
      );

      final fakeClient = _FakeStaffPortalClient();
      final completer = Completer<MonitoringTableResult>();
      fakeClient.fetchCompleter = completer;

      mgr.startSync(
        context: rootNavigatorKey.currentContext!,
        client: fakeClient,
        tahun: '2026',
        bloks: ['001'],
        kelurahan: '3205200004',
        kecamatan: '3205200',
        blokLabel: 'Blok 1',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Hide sheet
      mgr.hideSheet();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mgr.shouldShowBubble, isTrue);

      // Complete sync
      completer.complete(const MonitoringTableResult(headers: [], rows: []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mgr.isCompleted, isTrue);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Advance clock by 5 seconds to trigger auto-dismiss timer
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      // Bubble must be completely dismissed and progress cleared!
      expect(mgr.shouldShowBubble, isFalse);
      expect(mgr.progress, isNull);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('dragging the bubble updates its position without crashing', (tester) async {
      final mgr = StaffDhkpSyncManager.instance;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const StaffSyncBubbleOverlay(),
            ],
          ),
          home: const Scaffold(
            body: Text('Home Screen'),
          ),
        ),
      );

      final fakeClient = _FakeStaffPortalClient();
      final completer = Completer<MonitoringTableResult>();
      fakeClient.fetchCompleter = completer;

      mgr.startSync(
        context: rootNavigatorKey.currentContext!,
        client: fakeClient,
        tahun: '2026',
        bloks: ['001'],
        kelurahan: '3205200004',
        kecamatan: '3205200',
        blokLabel: 'Blok 1',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      mgr.hideSheet();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mgr.shouldShowBubble, isTrue);

      // Perform drag gesture on the bubble
      await tester.drag(find.byType(StaffSyncBubbleOverlay), const Offset(-50, -20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mgr.shouldShowBubble, isTrue);

      completer.complete(const MonitoringTableResult(headers: [], rows: []));
      await tester.pump();
    });
  });

  group('BatchNotificationService Notification Tap Routing Tests', () {
    testWidgets('staff_sync_completed payload navigates to MonitoringWilayahScreen and opens report', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: Text('Root Screen'),
          ),
        ),
      );

      StaffDhkpSyncService.lastOutcome = const StaffDhkpSyncOutcome(
        blokLabel: 'Semua Blok',
        tahun: '2026',
        totalCheckedRows: 100,
        updatedPaidCount: 5,
        newSpptCount: 2,
      );

      BatchNotificationService.instance.onNotificationTapped(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'staff_sync_completed',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MonitoringWilayahScreen), findsOneWidget);
      expect(MonitoringWilayahScreen.isCurrentlyOpen, isTrue);

      // Verify report dialog was shown
      await tester.pump();
      expect(find.text('Laporan Hasil Sinkronisasi'), findsOneWidget);
    });

    testWidgets('staff_sync_in_progress payload navigates to MonitoringWilayahScreen without report', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: Text('Root Screen'),
          ),
        ),
      );

      BatchNotificationService.instance.onNotificationTapped(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'staff_sync_in_progress',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MonitoringWilayahScreen), findsOneWidget);
      expect(MonitoringWilayahScreen.isCurrentlyOpen, isTrue);
      // No report dialog should be shown
      expect(find.text('Laporan Hasil Sinkronisasi'), findsNothing);
    });

    testWidgets('staff_sync_cancelled payload navigates to MonitoringWilayahScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: Text('Root Screen'),
          ),
        ),
      );

      BatchNotificationService.instance.onNotificationTapped(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'staff_sync_cancelled',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MonitoringWilayahScreen), findsOneWidget);
      expect(MonitoringWilayahScreen.isCurrentlyOpen, isTrue);
    });
  });
}
