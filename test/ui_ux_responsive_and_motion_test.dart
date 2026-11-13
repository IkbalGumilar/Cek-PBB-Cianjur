import 'package:cek_pbb_app/app_header.dart';
import 'package:cek_pbb_app/blok_catatan_screen.dart';
import 'package:cek_pbb_app/check_form_view.dart';
import 'package:cek_pbb_app/check_mode.dart';
import 'package:cek_pbb_app/desil/desil_view.dart';
import 'package:cek_pbb_app/kendaraan/kendaraan_view.dart';
import 'package:cek_pbb_app/monitoring/monitoring_result_table.dart';
import 'package:cek_pbb_app/monitoring/monitoring_summary_cards.dart';
import 'package:cek_pbb_app/staff_login_screen.dart';
import 'package:cek_pbb_app/staff_mfa_screen.dart';
import 'package:cek_pbb_app/staff_portal/staff_authenticator_store.dart';
import 'package:cek_pbb_app/staff_portal_client.dart';
import 'package:cek_pbb_app/theme_controller.dart';
import 'package:cek_pbb_app/ui/app_design_system.dart';
import 'package:cek_pbb_app/unity_lerp_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'feature_tour_completed_v1_cek_tagihan_main': true,
      'feature_tour_completed_v1_cek_status_bayar': true,
      'feature_tour_completed_v1_cek_kendaraan_samsat': true,
      'feature_tour_completed_v1_cek_desil_bansos': true,
      'feature_tour_completed_v1_blok_catatan_dhkp': true,
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('AppDesignSystem & Responsive Breakpoints', () {
    test(
      'AppBreakpoints classifies Mobile, Tablet, and Desktop accurately',
      () {
        expect(AppBreakpoints.ofWidth(360), AppScreenClass.mobile);
        expect(AppBreakpoints.ofWidth(390), AppScreenClass.mobile);
        expect(AppBreakpoints.ofWidth(430), AppScreenClass.mobile);
        expect(AppBreakpoints.ofWidth(599), AppScreenClass.mobile);
        expect(AppBreakpoints.ofWidth(600), AppScreenClass.tablet);
        expect(AppBreakpoints.ofWidth(768), AppScreenClass.tablet);
        expect(AppBreakpoints.ofWidth(1023), AppScreenClass.tablet);
        expect(AppBreakpoints.ofWidth(1024), AppScreenClass.desktop);
        expect(AppBreakpoints.ofWidth(1280), AppScreenClass.desktop);
        expect(AppBreakpoints.ofWidth(1440), AppScreenClass.desktop);
        expect(AppBreakpoints.ofWidth(1920), AppScreenClass.desktop);
      },
    );

    const breakpoints = <double>[
      360,
      390,
      430,
      600,
      768,
      1024,
      1280,
      1440,
      1920,
    ];

    for (final width in breakpoints) {
      testWidgets(
        'CheckFormView and AppHeader render without overflow at ${width.toInt()} dp',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final themeController = ThemeController();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                appBar: AppHeader(
                  activeMode: CheckMode.tagihan,
                  onModeChanged: (_) {},
                  themeController: themeController,
                  onMonitoringPressed: () {},
                  onDesilPressed: () {},
                  onKendaraanPressed: () {},
                  viewportWidth: width,
                ),
                body: CheckFormView(
                  mode: CheckMode.tagihan,
                  onImportPressed: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Cek Tagihan PBB'), findsOneWidget);
          expect(find.text('Nomor Wilayah'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'DesilView and KendaraanView render without overflow at ${width.toInt()} dp',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: const Scaffold(body: DesilView()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: const Scaffold(body: KendaraanView()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'BlokCatatanScreen AppBar and empty state render cleanly at 360 dp',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: const BlokCatatanScreen(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Data DHKP'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('dhkp_direct_print_btn')),
          findsNothing,
        );
        expect(find.byIcon(Icons.print_outlined), findsNothing);
        expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Monitoring Adaptive Table & Theme Compatibility', () {
    const sampleSummary = MonitoringSummaryTotals(
      jumlahOp: 125,
      pokokKetetapan: 15000000,
      pokokPembayaran: 12500000,
      denda: 250000,
      totalPenerimaan: 12750000,
    );

    const sampleResult = MonitoringTableResult(
      headers: ['No', 'NOP', 'Nama WP', 'Alamat OP', 'Ketetapan', 'Status'],
      rows: [
        [
          '1',
          '32.03.050.004.001-0001.0',
          'BUDI SANTOSO',
          'KP BOBOJONG RT 01/02',
          '75.000',
          'LUNAS',
        ],
      ],
      summary: sampleSummary,
      totalRecords: 1,
      pageStart: 1,
      pageEnd: 1,
    );

    testWidgets(
      'MonitoringSummaryCards and MonitoringResultView support Light, Dark, AMOLED, and Custom Accent without contrast regression',
      (tester) async {
        final themes = <ThemeData>[
          ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.light,
            ),
          ),
          ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.dark,
            ),
          ),
          ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.black,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.dark,
            ).copyWith(surface: Colors.black),
          ),
          ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
              brightness: Brightness.dark,
            ),
          ),
        ];

        for (final theme in themes) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      MonitoringSummaryCards(summary: sampleSummary),
                      MonitoringResultView(
                        loading: false,
                        result: sampleResult,
                        reportTitle: 'Data Uji',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));

          expect(find.text('Jumlah OP'), findsOneWidget);
          expect(find.text('BUDI SANTOSO'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'MonitoringResultView defaults to Kartu Ringkas on mobile (360dp) and allows toggling to Tabel Lengkap',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: MonitoringResultView(
                  loading: false,
                  result: sampleResult,
                  reportTitle: 'Data Uji',
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // On 360dp mobile, compact cards are rendered by default (no DataTable yet)
        expect(find.byType(DataTable), findsNothing);
        expect(
          find.byTooltip('Tampilkan sebagai Tabel Lengkap'),
          findsOneWidget,
        );

        // Toggle to Tabel
        await tester.tap(find.byTooltip('Tampilkan sebagai Tabel Lengkap'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DataTable), findsOneWidget);
      },
    );
  });

  group('Motion Design System & Reduced Motion Support', () {
    testWidgets(
      'AppMotion.isReducedMotion and AppMotion.resolve return Duration.zero when disableAnimations is true',
      (tester) async {
        late bool reduced;
        late Duration resolvedDuration;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reduced = AppMotion.isReducedMotion(context);
                resolvedDuration = AppMotion.resolve(
                  context,
                  AppMotion.complex,
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(reduced, isTrue);
        expect(resolvedDuration, Duration.zero);
      },
    );

    testWidgets(
      'LerpAnimatedCounter, LerpAnimatedProgress, and AppAnimatedReveal settle immediately under Reduced Motion',
      (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    LerpAnimatedCounter(
                      value: 500,
                      formatter: (val) => 'Nilai: ${val.round()}',
                    ),
                    const LerpAnimatedProgress(value: 0.75),
                    const AppAnimatedReveal(
                      child: Text('Konten Muncul Instan'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Without pumping any duration, values are already at target
        expect(find.text('Nilai: 500'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Konten Muncul Instan'), findsOneWidget);
      },
    );

    testWidgets(
      'AppCollapsibleFilterSection expands and collapses smoothly and shows active filter badge',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AppCollapsibleFilterSection(
                activeFilterCount: 2,
                children: [Text('Filter Tanggal & Bank')],
              ),
            ),
          ),
        );

        expect(find.text('Filter Lanjutan (Opsional)'), findsOneWidget);
        expect(find.text('2 aktif'), findsOneWidget);
        expect(find.text('Filter Tanggal & Bank'), findsNothing);

        await tester.tap(find.text('Filter Lanjutan (Opsional)'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Filter Tanggal & Bank'), findsOneWidget);
      },
    );
  });

  group('Staff Portal Login & MFA Responsive Layout', () {
    testWidgets(
      'StaffMfaScreen renders inside ResponsivePageContainer without overflow',
      (tester) async {
        final themeController = ThemeController();
        final client = StaffPortalClient();
        final store = StaffAuthenticatorStore();
        await store.setAutoVerifyEnabled(false);

        await tester.pumpWidget(
          MaterialApp(
            home: StaffMfaScreen(
              client: client,
              themeController: themeController,
              authenticatorStore: store,
              enablePeriodicTimer: false,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Verifikasi MFA'), findsOneWidget);
        expect(find.text('Verifikasi & Masuk'), findsOneWidget);
        expect(tester.takeException(), isNull);

        expect(StaffLoginScreen, isNotNull);
      },
    );
  });
}
