import 'dart:typed_data';

import 'package:cek_pbb_app/batch_check_screen.dart';
import 'package:cek_pbb_app/captcha_ocr_helper.dart';
import 'package:cek_pbb_app/check_mode.dart';
import 'package:cek_pbb_app/pbb_client.dart';
import 'package:cek_pbb_app/tax_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1x1 transparent PNG bytes yang valid untuk Image.memory di widget test
final kTransparentImage = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

class FakePbbClient extends PbbClient {
  final Uint8List captchaBytes;
  final PbbResult Function(String nop, String tahun, String captchaCode)? onCheck;

  FakePbbClient({
    Uint8List? captchaBytes,
    this.onCheck,
  }) : captchaBytes = captchaBytes ?? kTransparentImage;

  @override
  Future<Uint8List> fetchCaptchaImage(CheckMode mode) async {
    return captchaBytes;
  }

  @override
  Future<PbbResult> checkStatusBayar({
    required String nop,
    required String tahun,
    required String captchaCode,
  }) async {
    if (onCheck != null) {
      return onCheck!(nop, tahun, captchaCode);
    }
    return PbbResult('Sudah Bayar', 'Lunas', namaWajibPajak: 'AHMAD');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    CaptchaOcrHelper.ocrRunnerForTesting = null;
  });

  testWidgets('menampilkan NOP, tahun, counter live, checkbox eksperimental, dan pre-fill OCR captcha otomatis', (tester) async {
    CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => 'misled';

    final records = [
      TaxRecord(nop: '320520000401701540'),
      TaxRecord(nop: '320520000401701550'),
    ];

    final client = FakePbbClient();

    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2024',
          client: client,
        ),
      ),
    );

    // Tunggu fetch captcha & ocr selesai
    await tester.pumpAndSettle();

    // Verifikasi judul dan NOP
    expect(find.text('Cek Status Bayar (1/2)'), findsOneWidget);
    expect(find.text('320520000401701540'), findsOneWidget);
    expect(find.text('Blok 017'), findsOneWidget);
    expect(find.text('Tahun Pajak: 2024'), findsOneWidget);

    // Verifikasi counter live
    expect(find.text('Sudah: 0'), findsOneWidget);
    expect(find.text('Belum: 0'), findsOneWidget);
    expect(find.text('Sisa: 2'), findsOneWidget);

    // Verifikasi checkbox auto-complete eksperimental
    expect(find.text('Auto-complete CAPTCHA'), findsOneWidget);
    expect(find.text('Eksperimental'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    // Verifikasi badge OCR tebakan muncul dan TextField terisi otomatis
    expect(find.text('Tebakan OCR: "misled"'), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, 'misled');

    // Verifikasi seluruh teks terseleksi agar mudah diganti jika keliru
    expect(textField.controller?.selection.baseOffset, 0);
    expect(textField.controller?.selection.extentOffset, 6);
  });

  testWidgets('uncheck checkbox mematikan OCR dan menghapus tebakan eksperimental', (tester) async {
    CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => 'misled';

    final records = [
      TaxRecord(nop: '320520000401701540'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2024',
          client: FakePbbClient(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tebakan OCR: "misled"'), findsOneWidget);

    // Uncheck checkbox
    await tester.tap(find.text('Auto-complete CAPTCHA'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(find.text('Tebakan OCR: "misled"'), findsNothing);
  });

  testWidgets('initialAutoOcr false tidak menjalankan OCR sama sekali', (tester) async {
    bool ocrCalled = false;
    CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async {
      ocrCalled = true;
      return 'misled';
    };

    final records = [
      TaxRecord(nop: '320520000401701540'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2024',
          client: FakePbbClient(),
          initialAutoOcr: false,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(ocrCalled, isFalse);
    expect(find.text('Tebakan OCR: "misled"'), findsNothing);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, isEmpty);
  });

  testWidgets('tombol clear icon menghapus teks captcha dan memfokuskan kembali', (tester) async {
    CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => 'misled';

    final records = [
      TaxRecord(nop: '320520000401701540'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2024',
          client: FakePbbClient(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byTooltip('Hapus teks'), findsOneWidget);

    // Tap tombol hapus
    await tester.tap(find.byTooltip('Hapus teks'));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, isEmpty);
  });

  testWidgets('cek & lanjut memperbarui status, counter, dan berpindah ke NOP berikutnya', (tester) async {
    CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => 'pugged';

    final records = [
      TaxRecord(nop: '320520000401701540'),
      TaxRecord(nop: '320520000401701550'),
    ];

    final client = FakePbbClient(
      onCheck: (nop, tahun, captcha) {
        return PbbResult('Sudah Bayar', 'Lunas', namaWajibPajak: 'AHMAD');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2024',
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tekan Cek & Lanjut
    await tester.tap(find.text('Cek & Lanjut'));
    await tester.pumpAndSettle();

    // Harus sudah berpindah ke NOP kedua (2/2)
    expect(find.text('Cek Status Bayar (2/2)'), findsOneWidget);
    expect(find.text('320520000401701550'), findsOneWidget);

    // Counter harus terupdate
    expect(find.text('Sudah: 1'), findsOneWidget);
    expect(find.text('Belum: 0'), findsOneWidget);
    expect(find.text('Sisa: 1'), findsOneWidget);
    expect(records[0].isPaid, isTrue);
  });

  testWidgets('tombol Lewati menandai status record dan memperbarui counter Lewat', (tester) async {
    CaptchaOcrHelper.ocrRunnerForTesting = (bytes) async => 'duping';

    final records = [
      TaxRecord(nop: '320520000401701540'),
      TaxRecord(nop: '320520000401701550'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: BatchCheckScreen(
          records: records,
          tahun: '2024',
          client: FakePbbClient(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Lewati
    await tester.tap(find.text('Lewati'));
    await tester.pumpAndSettle();

    // Harus sudah berpindah ke NOP kedua
    expect(find.text('Cek Status Bayar (2/2)'), findsOneWidget);
    expect(records[0].status, 'Dilewati');

    // Badge Lewat harus muncul
    expect(find.text('Lewat: 1'), findsOneWidget);
    expect(find.text('Sisa: 1'), findsOneWidget);
  });
}
