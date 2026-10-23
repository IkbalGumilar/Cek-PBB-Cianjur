import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cek_pbb_app/kendaraan/kendaraan_client.dart';
import 'package:cek_pbb_app/kendaraan/kendaraan_view.dart';

class FakeKendaraanClient extends KendaraanClient {
  FakeKendaraanClient({this.stubbedInfo, this.stubbedError});

  final KendaraanInfo? stubbedInfo;
  final KendaraanException? stubbedError;
  String? capturedDepan;
  String? capturedAngka;
  String? capturedBelakang;
  String? capturedWarna;

  @override
  Future<KendaraanInfo> check({
    required String platDepan,
    required String angka,
    required String platBelakang,
    required String warna,
  }) async {
    capturedDepan = platDepan;
    capturedAngka = angka;
    capturedBelakang = platBelakang;
    capturedWarna = warna;
    if (stubbedError != null) throw stubbedError!;
    return stubbedInfo ??
        KendaraanInfo.fromJson({
          'informasi-umum': {
            'merk': 'HONDA',
            'model': 'BEAT',
            'nomor-polisi': '$platDepan $angka $platBelakang',
            'warna': 'HITAM',
            'jenis': 'Roda 2',
            'tahun-buatan': '2022',
          },
          'informasi-pkb-pnbp': {
            'wilayah': 'CIANJUR',
            'tanggal-pajak': '2026-08-01',
            'tanggal-stnk': '2027-08-01',
          },
          'pembayaran-pkb-pnbp': {
            'total': 320000,
          },
        });
  }
}

void main() {
  Widget buildTestableWidget({KendaraanClient? client}) {
    return MaterialApp(
      home: Scaffold(
        body: KendaraanView(client: client),
      ),
    );
  }

  testWidgets('renders input fields for front, number, and suffix', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    expect(find.text('Info Kendaraan Bermotor'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('shows validation message if plate inputs are empty', (tester) async {
    await tester.pumpWidget(buildTestableWidget());

    final submitButton = find.widgetWithText(FilledButton, 'Lihat Info');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(
      find.text('Isi nomor polisi lengkap: huruf, angka, dan huruf belakang.'),
      findsOneWidget,
    );
  });

  testWidgets('submits plate and displays vehicle info on success', (tester) async {
    final client = FakeKendaraanClient();
    await tester.pumpWidget(buildTestableWidget(client: client));

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'F');
    await tester.enterText(textFields.at(1), '6286');
    await tester.enterText(textFields.at(2), 'WA');

    final submitButton = find.widgetWithText(FilledButton, 'Lihat Info');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(client.capturedDepan, 'F');
    expect(client.capturedAngka, '6286');
    expect(client.capturedBelakang, 'WA');
    expect(find.text('HONDA'), findsOneWidget);
    expect(find.text('BEAT'), findsOneWidget);
  });

  testWidgets('displays error message when vehicle is not found', (tester) async {
    final client = FakeKendaraanClient(
      stubbedError: const KendaraanException(
        'Data kendaraan tidak ditemukan.',
        kind: KendaraanErrorKind.notFound,
        code: 76,
      ),
    );
    await tester.pumpWidget(buildTestableWidget(client: client));

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'F');
    await tester.enterText(textFields.at(1), '9999');
    await tester.enterText(textFields.at(2), 'ZZZ');

    final submitButton = find.widgetWithText(FilledButton, 'Lihat Info');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Data kendaraan tidak ditemukan.'), findsOneWidget);
  });
}
