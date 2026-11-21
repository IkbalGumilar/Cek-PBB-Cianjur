import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_storage.dart';
import 'blok_data_store.dart';
import 'check_mode.dart';
import 'cianjur_wilayah_data.dart';
import 'feature_tour/feature_tour.dart';
import 'nop_helper.dart';
import 'nop_scanner.dart';
import 'pbb/check_result_cards.dart';
import 'pbb_client.dart';
import 'tagihan_result.dart';
import 'ui/app_design_system.dart';
import 'unity_lerp_widgets.dart';
import 'user_friendly_error.dart';

class CheckFormView extends StatefulWidget {
  final CheckMode mode;
  final VoidCallback onImportPressed;
  final void Function(String blok, String wilayah, String tahun)?
  onOpenStatusBayar;
  final String? initialBlok;
  final String? initialWilayah;
  final String? initialTahun;
  final ScrollController? scrollController;
  final PbbClient? client;
  final GlobalKey? headerMenuKey;
  final GlobalKey? headerSettingsKey;
  final GlobalKey? dhkpFabKey;
  final GlobalKey? emergencyFabKey;
  final bool isActive;
  final ValueChanged<VoidCallback>? onRegisterShowTour;

  const CheckFormView({
    super.key,
    required this.mode,
    required this.onImportPressed,
    this.onOpenStatusBayar,
    this.initialBlok,
    this.initialWilayah,
    this.initialTahun,
    this.scrollController,
    this.client,
    this.headerMenuKey,
    this.headerSettingsKey,
    this.dhkpFabKey,
    this.emergencyFabKey,
    this.isActive = true,
    this.onRegisterShowTour,
  });

  @override
  State<CheckFormView> createState() => _CheckFormViewState();
}

class _CheckFormViewState extends State<CheckFormView> {
  late final PbbClient _client;
  final _nopScanner = NopScanner();
  final _blokController = TextEditingController();
  final _wilayahController = TextEditingController();
  final _tahunController = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final _captchaController = TextEditingController();
  final _blokFocusNode = FocusNode();
  final _wilayahFocusNode = FocusNode();
  final _tahunFocusNode = FocusNode();
  final _captchaFocusNode = FocusNode();
  late final ScrollController _scrollController =
      widget.scrollController ?? ScrollController();

  final _blokWilayahInputKey = GlobalKey(debugLabel: 'tour_blok_wilayah');
  final _scanButtonKey = GlobalKey(debugLabel: 'tour_scan_sppt');
  final _importButtonKey = GlobalKey(debugLabel: 'tour_import_file');
  final _tahunInputKey = GlobalKey(debugLabel: 'tour_tahun_pajak');
  final _captchaAreaKey = GlobalKey(debugLabel: 'tour_captcha_area');
  final _captchaInputKey = GlobalKey(debugLabel: 'tour_captcha_input');
  final _submitButtonKey = GlobalKey(debugLabel: 'tour_submit_cek');

  Uint8List? _captchaBytes;
  bool _loadingCaptcha = false;
  bool _scanningOcr = false;
  bool _ready = true;
  bool _submitting = false;
  int _validationShakeTrigger = 0;
  PbbResult? _statusBayarResult;
  TagihanResult? _tagihanResult;
  String? _errorText;
  String? _blokError;
  String? _wilayahError;
  String? _tahunError;
  String? _captchaError;

  @override
  void initState() {
    super.initState();
    activeWilayahRevision.addListener(_onWilayahChanged);
    _loadSavedWilayah();
    _client = widget.client ?? PbbClient();
    _blokController.text = widget.initialBlok ?? '';
    _wilayahController.text = widget.initialWilayah ?? '';
    if (widget.initialTahun != null) {
      _tahunController.text = widget.initialTahun!;
    }
    widget.onRegisterShowTour?.call(showTour);
    _loadCaptcha();
  }

  void _onWilayahChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedWilayah() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kec = prefs.getString('startup_kec_code');
      final kel = prefs.getString('startup_kel_code');
      final desa = prefs.getString('startup_desa_name');
      if (kec != null && kel != null) {
        final kecObj = findKecamatanByCode(kec);
        setActiveWilayah(
          kecCode: kec,
          kelCode: kel,
          desaName:
              desa ?? (kecObj != null ? lookupCatalogDesaName(kec, kel) : null),
          kecName: kecObj?.name,
        );
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(CheckFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onRegisterShowTour != widget.onRegisterShowTour) {
      widget.onRegisterShowTour?.call(showTour);
    }
    if (oldWidget.mode != widget.mode) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      setState(() {
        _statusBayarResult = null;
        _tagihanResult = null;
        _errorText = null;
        _blokError = null;
        _wilayahError = null;
        _tahunError = null;
        _captchaError = null;
      });
      _loadCaptcha();
    } else if (!oldWidget.isActive && widget.isActive && _ready) {
      _maybeStartAutoTour();
    }
  }

  @override
  void dispose() {
    activeWilayahRevision.removeListener(_onWilayahChanged);
    _blokController.dispose();
    _wilayahController.dispose();
    _tahunController.dispose();
    _captchaController.dispose();
    _blokFocusNode.dispose();
    _wilayahFocusNode.dispose();
    _tahunFocusNode.dispose();
    _captchaFocusNode.dispose();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  /// Pindai gambar (kamera atau galeri) lalu isi kolom Blok & Nomor Wilayah
  /// dari NOP pertama yang berhasil dikenali OCR.
  Future<void> _scanAndFill() async {
    if (!isMobilePlatform) return;
    // Pilih sumber gambar
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scan NOP dari Dokumen'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Kamera'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Galeri'),
            ),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    setState(() {
      _scanningOcr = true;
      _errorText = null;
    });
    try {
      final nops = await _nopScanner.scan(source: source);
      if (!mounted) return;
      if (nops == null || nops.isEmpty) {
        setState(() => _errorText = 'NOP tidak ditemukan pada dokumen.');
        return;
      }

      if (nops.length == 1) {
        final nop = nops.first;
        final blok = nopBlok(nop);
        final wilayah = nopWilayah(nop);
        _blokController.text = int.tryParse(blok)?.toString() ?? blok;
        _wilayahController.text = int.tryParse(wilayah)?.toString() ?? wilayah;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('NOP berhasil dideteksi: $nop')));
      } else {
        if (widget.mode == CheckMode.tagihan) {
          final selectedNop = await showDialog<String>(
            context: context,
            builder: (ctx) {
              String? tempSelected;
              return StatefulBuilder(
                builder: (context, setState) {
                  return AlertDialog(
                    title: const Text('Pilih NOP'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lebih dari 1 NOP ditemukan dari dokumen.\n'
                          'Pilih NOP mana yang ingin Anda cek:',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 300,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: RadioGroup<String>(
                            groupValue: tempSelected,
                            onChanged: (value) {
                              setState(() => tempSelected = value);
                            },
                            child: ListView.builder(
                              itemCount: nops.length,
                              itemBuilder: (context, index) {
                                final n = nops[index];
                                return RadioListTile<String>(
                                  value: n,
                                  title: Text(
                                    '${index + 1}. $n',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  contentPadding: const EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: tempSelected == null
                            ? null
                            : () => Navigator.pop(ctx, tempSelected),
                        child: const Text('Lanjutkan'),
                      ),
                    ],
                  );
                },
              );
            },
          );
          if (!mounted) return;
          if (selectedNop != null) {
            final blok = nopBlok(selectedNop);
            final wilayah = nopWilayah(selectedNop);
            _blokController.text = int.tryParse(blok)?.toString() ?? blok;
            _wilayahController.text =
                int.tryParse(wilayah)?.toString() ?? wilayah;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('NOP dipilih: $selectedNop')),
            );
          }
        } else {
          // Di mode Status Bayar, tawarkan pindah ke Cek Massal
          final checkMassal = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Lebih dari 1 NOP Ditemukan'),
              content: Text(
                'Ada ${nops.length} NOP yang berhasil dibaca dari dokumen.\n\n'
                'Apakah Anda ingin memasukkan semuanya ke menu "Cek Massal" '
                'untuk dicek secara massal?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Tidak, pakai NOP pertama saja'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ya, cek massal'),
                ),
              ],
            ),
          );
          if (!mounted) return;

          if (checkMassal == true) {
            // Tambahkan ke file draft NOP untuk ImportView
            final dir = await AppStorage.getDataDirectory();
            final file = File('${dir.path}/draft_nop.txt');
            final existing = await file.exists()
                ? await file.readAsString()
                : '';
            final existingSet = existing
                .split(RegExp(r'[,\n\r]+'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet();

            final toAdd = nops.where((n) => !existingSet.contains(n)).toList();
            if (toAdd.isNotEmpty) {
              final newContent = [
                existing.trim(),
                ...toAdd,
              ].where((e) => e.isNotEmpty).join('\n');
              await file.writeAsString(newContent);
            }

            if (!mounted) return;
            widget.onImportPressed();
          } else if (checkMassal == false) {
            final nop = nops.first;
            final blok = nopBlok(nop);
            final wilayah = nopWilayah(nop);
            _blokController.text = int.tryParse(blok)?.toString() ?? blok;
            _wilayahController.text =
                int.tryParse(wilayah)?.toString() ?? wilayah;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dipakai NOP pertama: $nop')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorText = friendlyErrorMessage(
            e,
            fallback:
                'Gagal memindai dokumen. Coba ambil foto lebih jelas dan terang.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scanningOcr = false);
    }
  }

  Future<void> _loadCaptcha({bool clearError = true}) async {
    setState(() {
      _loadingCaptcha = true;
      if (clearError) _errorText = null;
    });
    try {
      final bytes = await _client.fetchCaptchaImage(widget.mode);
      if (!mounted) return;
      setState(() => _captchaBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorText = friendlyErrorMessage(
          e,
          fallback:
              'Gagal memuat gambar kode. Periksa koneksi internet lalu coba lagi.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingCaptcha = false;
          _ready = true;
        });
        if (widget.isActive) {
          _maybeStartAutoTour();
        }
      }
    }
  }

  void _maybeStartAutoTour() {
    if (!mounted || !widget.isActive || !_ready) return;
    if (widget.mode == CheckMode.tagihan) {
      FeatureTourController.startTourIfNeeded(
        context: context,
        tourId: 'check_tagihan_view',
        steps: _buildTourSteps(fullTour: true),
      );
    } else {
      FeatureTourController.startTourIfNeeded(
        context: context,
        tourId: 'check_status_bayar_view',
        steps: _buildTourSteps(fullTour: false),
      );
    }
  }

  void showTour() {
    if (!mounted || !_ready) return;
    FeatureTourController.showTour(
      context: context,
      tourId: widget.mode == CheckMode.tagihan
          ? 'check_tagihan_view'
          : 'check_status_bayar_view',
      steps: _buildTourSteps(fullTour: true),
    );
  }

  List<FeatureTourStep> _buildTourSteps({required bool fullTour}) {
    final isTagihan = widget.mode == CheckMode.tagihan;
    final currentYear = DateTime.now().year;
    final supportsVa = Platform.isAndroid;
    final steps = <FeatureTourStep>[];

    if (fullTour && widget.headerMenuKey != null) {
      steps.add(
        FeatureTourStep(
          targetKey: widget.headerMenuKey!,
          title: 'Menu Layanan Utama',
          description: supportsVa
              ? 'Pindah layanan kapan saja: Cek Tagihan (QRIS/VA), Cek Status Bayar, Monitoring petugas, Cek Kendaraan, dan Cek Desil.'
              : 'Pindah layanan kapan saja: Cek Tagihan (QRIS), Cek Status Bayar, Monitoring petugas, Cek Kendaraan, dan Cek Desil.',
          actionHint: isMobilePlatform
              ? 'Geser baris menu ke samping jika layar berukuran kecil.'
              : 'Pilih tab layanan di bagian atas untuk langsung berpindah.',
          icon: Icons.apps_rounded,
        ),
      );
    }

    if (fullTour) {
      steps.add(
        FeatureTourStep(
          targetKey: _blokWilayahInputKey,
          title: 'Wilayah Aktif, Blok & Nomor Wilayah',
          description:
              'Ketuk "Ganti Desa" untuk mengganti desa, atau buka Pengaturan → Wilayah Kerja untuk ganti kecamatan. Isi Blok dan Nomor Wilayah tanpa nol di depan.',
          actionHint: 'Contoh: Blok 017 Nomor 0154 cukup diisi 17 dan 154.',
          icon: Icons.pin_outlined,
        ),
      );

      if (isMobilePlatform) {
        steps.add(
          FeatureTourStep(
            targetKey: _scanButtonKey,
            title: 'Pindai Foto SPPT Otomatis',
            description:
                'Potret lembar SPPT dari kamera atau galeri agar aplikasi otomatis membaca dan mengisi kolom Blok & Nomor Wilayah.',
            actionHint:
                'Jika ditemukan lebih dari satu NOP, Anda bisa memilih satu atau langsung cek massal.',
            icon: Icons.document_scanner_outlined,
          ),
        );
      }
    }

    if (!isTagihan) {
      steps.add(
        FeatureTourStep(
          targetKey: _importButtonKey,
          title: 'Cek Massal dari Berkas',
          description: isMobilePlatform
              ? 'Periksa status lunas banyak NOP sekaligus dari Excel, CSV, TXT, atau foto daftar. Bisa berjalan di latar belakang dan memperbarui DHKP.'
              : 'Periksa status lunas banyak NOP sekaligus dari berkas Excel, CSV, atau TXT. Bisa berjalan di latar belakang dan memperbarui DHKP.',
          actionHint:
              'Dari halaman Data DHKP, petugas dusun juga dapat memeriksa seluruh blok sekaligus.',
          icon: Icons.upload_file_rounded,
        ),
      );

      steps.add(
        FeatureTourStep(
          targetKey: _tahunInputKey,
          title: 'Kolom Tahun Pajak',
          description:
              'Isi tahun pajak yang ingin diperiksa bukti bayarnya. Secara bawaan terisi tahun berjalan dan dapat diubah ke tahun sebelumnya.',
          actionHint:
              'Isi 4 digit angka tahun, misalnya $currentYear atau ${currentYear - 1}.',
          icon: Icons.calendar_today_outlined,
        ),
      );
    }

    if (fullTour) {
      steps.add(
        FeatureTourStep(
          targetKey: _captchaAreaKey,
          title: 'Kode Pengaman Bapenda',
          description:
              'Menampilkan gambar huruf/angka pengaman dari Bapenda. Jika kurang jelas, tekan "Ganti Kode Gambar" untuk memuat gambar baru.',
          actionHint:
              'Gambar kode otomatis diperbarui setiap kali pengecekan selesai.',
          icon: Icons.refresh_rounded,
        ),
      );

      steps.add(
        FeatureTourStep(
          targetKey: _captchaInputKey,
          title: 'Isi Kode Verifikasi',
          description:
              'Ketikkan huruf atau angka yang tampil pada gambar kode pengaman di atas.',
          actionHint:
              'Tekan Enter/Go atau tombol Cek di bawah untuk memulai pencarian.',
          icon: Icons.keyboard_alt_outlined,
        ),
      );
    }

    steps.add(
      FeatureTourStep(
        targetKey: _submitButtonKey,
        title: isTagihan ? 'Cek Rincian Tagihan' : 'Cek Status Pembayaran',
        description: isTagihan
            ? (supportsVa
                  ? 'Tampilkan nama wajib pajak, rincian tagihan per tahun, denda, serta pembayaran langsung lewat QRIS atau Virtual Account.'
                  : 'Tampilkan nama wajib pajak, rincian tagihan per tahun, denda, serta pembayaran langsung lewat QRIS.')
            : 'Periksa status lunas tahun pajak terpilih. Jika lunas, bukti bayar resmi dapat dilihat atau diunduh dan Data DHKP otomatis diperbarui.',
        actionHint: 'Hasil pemeriksaan tampil langsung di bawah kartu formulir.',
        icon: Icons.search_rounded,
      ),
    );

    if (fullTour && widget.dhkpFabKey != null) {
      steps.add(
        FeatureTourStep(
          targetKey: widget.dhkpFabKey!,
          title: 'Tombol Data DHKP',
          description:
              'Buka Data DHKP desa untuk melihat daftar wajib pajak per blok, grafik pelunasan, kolase foto STTS, hingga ekspor laporan.',
          actionHint:
              'Angka di sudut tombol menunjukkan jumlah data wajib pajak tersimpan.',
          icon: Icons.table_chart_outlined,
        ),
      );
    }

    if (isMobilePlatform && widget.emergencyFabKey?.currentContext != null) {
      steps.add(
        FeatureTourStep(
          targetKey: widget.emergencyFabKey!,
          title: 'Kontak Darurat 112 Cianjur',
          description:
              'Akses cepat ke Cianjur Siaga 112, Polres, BPBD, RSUD/PSC 119, Damkar, PLN, SP4N-LAPOR!, serta kontak darurat desa.',
          actionHint:
              'Kontak darurat desa tambahan otomatis tersinkron ke akun Google.',
          icon: Icons.emergency_rounded,
        ),
      );
    }

    if (fullTour && widget.headerSettingsKey != null) {
      steps.add(
        FeatureTourStep(
          targetKey: widget.headerSettingsKey!,
          title: 'Pengaturan Aplikasi',
          description:
              'Buka Pengaturan untuk mengatur tema tampilan, keamanan, pencadangan, dan wilayah kerja, atau mengulang panduan fitur.',
          actionHint:
              'Ketuk ikon tanda tanya (?) di sebelahnya kapan saja untuk membuka panduan layar aktif.',
          icon: Icons.settings_outlined,
        ),
      );
    }

    return steps;
  }

  void _scrollAfterResult() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleBlokSubmitted() {
    final blokDigits = _blokController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (blokDigits.isEmpty) {
      setState(() => _blokError = 'Data belum diisi');
      _blokFocusNode.requestFocus();
      return;
    }
    if (_blokError != null || _errorText != null) {
      setState(() {
        _blokError = null;
        _errorText = null;
      });
    }
    _wilayahFocusNode.requestFocus();
  }

  void _handleWilayahSubmitted() {
    final wilayahDigits = _wilayahController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    if (wilayahDigits.isEmpty) {
      setState(() => _wilayahError = 'Data belum diisi');
      _wilayahFocusNode.requestFocus();
      return;
    }
    if (_wilayahError != null || _errorText != null) {
      setState(() {
        _wilayahError = null;
        _errorText = null;
      });
    }
    if (widget.mode == CheckMode.statusBayar) {
      _tahunFocusNode.requestFocus();
    } else {
      _captchaFocusNode.requestFocus();
    }
  }

  void _handleTahunSubmitted() {
    final tahunDigits = _tahunController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (tahunDigits.isEmpty) {
      setState(() => _tahunError = 'Data belum diisi');
      _tahunFocusNode.requestFocus();
      return;
    }
    if (_tahunError != null || _errorText != null) {
      setState(() {
        _tahunError = null;
        _errorText = null;
      });
    }
    _captchaFocusNode.requestFocus();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final blokDigits = _blokController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final wilayahDigits = _wilayahController.text.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final tahun = _tahunController.text.trim();
    final tahunDigits = tahun.replaceAll(RegExp(r'[^0-9]'), '');
    final manualCaptcha = _captchaController.text.trim();

    final blokError = blokDigits.isEmpty ? 'Data belum diisi' : null;
    final wilayahError = wilayahDigits.isEmpty ? 'Data belum diisi' : null;
    final String? tahunError;
    if (widget.mode == CheckMode.statusBayar) {
      if (tahunDigits.isEmpty) {
        tahunError = 'Data belum diisi';
      } else if (tahunDigits.length != 4) {
        tahunError = 'Tahun harus 4 digit angka';
      } else {
        tahunError = null;
      }
    } else {
      tahunError = null;
    }
    final captchaError = manualCaptcha.isEmpty ? 'Data belum diisi' : null;

    final nop = buildNop(
      blok: _blokController.text,
      wilayah: _wilayahController.text,
    );

    if (blokError != null ||
        wilayahError != null ||
        tahunError != null ||
        captchaError != null ||
        nop.isEmpty) {
      setState(() {
        _blokError = blokError;
        _wilayahError = wilayahError;
        _tahunError = tahunError;
        _captchaError = captchaError;
        _errorText = 'Lengkapi dulu semua kolom yang wajib diisi.';
        _validationShakeTrigger++;
      });
      if (blokError != null) {
        _blokFocusNode.requestFocus();
      } else if (wilayahError != null) {
        _wilayahFocusNode.requestFocus();
      } else if (tahunError != null) {
        _tahunFocusNode.requestFocus();
      } else if (captchaError != null) {
        _captchaFocusNode.requestFocus();
      }
      return;
    }

    FocusScope.of(context).unfocus(); // Singkirkan keyboard saat mulai cek
    setState(() {
      _blokError = null;
      _wilayahError = null;
      _tahunError = null;
      _captchaError = null;
    });

    await _submitManual(nop: nop, tahun: tahunDigits, captcha: manualCaptcha);
  }

  Future<void> _submitManual({
    required String nop,
    required String tahun,
    required String captcha,
  }) async {
    setState(() {
      _submitting = true;
      _errorText = null;
      _statusBayarResult = null;
      _tagihanResult = null;
    });

    try {
      if (widget.mode == CheckMode.statusBayar) {
        final result = await _client.checkStatusBayar(
          nop: nop,
          tahun: tahun,
          captchaCode: captcha,
        );
        if (!mounted) return;
        setState(() => _statusBayarResult = result);
        if (result.isPaid) {
          final outcome = await _recordIfInWilayah(
            nop: nop,
            tahun: tahun,
            result: result,
          );
          if (!mounted) return;
          if (outcome != null) {
            final msg = outcome.changedFromUnpaid
                ? 'Data DHKP diperbarui: Status menjadi Sudah Bayar!'
                : (outcome.wasExisting
                      ? 'Data DHKP sudah tercatat Sudah Bayar.'
                      : 'Data baru berhasil dicatat ke DHKP (Sudah Bayar).');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(msg)),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        final result = await _client.checkTagihan(
          nop: nop,
          captchaCode: captcha,
        );
        if (!mounted) return;
        setState(() => _tagihanResult = result);
      }

      _captchaController.clear();
      await _loadCaptcha();
      _scrollAfterResult();
    } on CaptchaError catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.message);
      _captchaController.clear();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await _loadCaptcha(clearError: false);
      if (mounted) _captchaFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorText = friendlyErrorMessage(
          e,
          fallback: 'Gagal memeriksa tagihan PBB. Silakan coba lagi.',
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Catat / perbarui hasil "Sudah Bayar" ke Buku Catatan Data DHKP.
  Future<DhkpCheckUpdateOutcome?> _recordIfInWilayah({
    required String nop,
    required String tahun,
    required PbbResult result,
  }) async {
    return await BlokDataStore.instance.updateStatusBayarFromCheck(
      nop: nop,
      tahun: tahun,
      result: result,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Memuat...'),
            ],
          ),
        ),
      );
    }

    final isTagihan = widget.mode == CheckMode.tagihan;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isTagihan
                                  ? Icons.receipt_long_outlined
                                  : Icons.verified_outlined,
                              color: scheme.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isTagihan
                                      ? 'Cek Tagihan PBB'
                                      : 'Cek Status Bayar PBB',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isTagihan
                                      ? (Platform.isAndroid
                                            ? 'Lihat rincian tunggakan dan bayar lewat QRIS atau VA'
                                            : 'Lihat rincian tunggakan dan bayar lewat QRIS')
                                      : 'Periksa bukti lunas pembayaran PBB per tahun',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildQuickWilayahSelector(context),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, inputConstraints) {
                          final isCompactInput =
                              inputConstraints.maxWidth < 460;
                          final fieldsRow = Row(
                            key: _blokWilayahInputKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _blokController,
                                  focusNode: _blokFocusNode,
                                  textInputAction: TextInputAction.next,
                                  onEditingComplete: () {},
                                  decoration: InputDecoration(
                                    labelText: 'Blok',
                                    hintText: 'Contoh: 17',
                                    border: const OutlineInputBorder(),
                                    counterText: '',
                                    errorText: _blokError,
                                    errorMaxLines: 2,
                                  ),
                                  keyboardType: TextInputType.number,
                                  maxLength: 3,
                                  onChanged: (val) {
                                    if (_blokError != null &&
                                        val
                                            .replaceAll(RegExp(r'[^0-9]'), '')
                                            .isNotEmpty) {
                                      setState(() => _blokError = null);
                                    }
                                  },
                                  onSubmitted: (_) => _handleBlokSubmitted(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _wilayahController,
                                  focusNode: _wilayahFocusNode,
                                  textInputAction: TextInputAction.next,
                                  onEditingComplete: () {},
                                  decoration: InputDecoration(
                                    labelText: 'Nomor Wilayah',
                                    hintText: 'Contoh: 154',
                                    border: const OutlineInputBorder(),
                                    counterText: '',
                                    errorText: _wilayahError,
                                    errorMaxLines: 2,
                                  ),
                                  keyboardType: TextInputType.number,
                                  maxLength: 4,
                                  onChanged: (val) {
                                    if (_wilayahError != null &&
                                        val
                                            .replaceAll(RegExp(r'[^0-9]'), '')
                                            .isNotEmpty) {
                                      setState(() => _wilayahError = null);
                                    }
                                  },
                                  onSubmitted: (_) => _handleWilayahSubmitted(),
                                ),
                              ),
                            ],
                          );

                          if (!isCompactInput) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: fieldsRow),
                                if (isMobilePlatform) ...[
                                  const SizedBox(width: 8),
                                  _scanningOcr
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : IconButton.filledTonal(
                                          key: _scanButtonKey,
                                          onPressed: _scanAndFill,
                                          icon: const Icon(
                                            Icons.document_scanner_outlined,
                                          ),
                                          tooltip:
                                              'Pindai Nomor dari Foto SPPT',
                                        ),
                                ],
                                if (!isTagihan) ...[
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    key: _importButtonKey,
                                    onPressed: widget.onImportPressed,
                                    icon: const Icon(Icons.upload_file),
                                    tooltip: 'Periksa Banyak Data dari File',
                                  ),
                                ],
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              fieldsRow,
                              if (isMobilePlatform || !isTagihan) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    if (isMobilePlatform)
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          key: _scanButtonKey,
                                          onPressed: _scanningOcr
                                              ? null
                                              : _scanAndFill,
                                          icon: _scanningOcr
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons
                                                      .document_scanner_outlined,
                                                  size: 18,
                                                ),
                                          label: const Text('Pindai SPPT'),
                                        ),
                                      ),
                                    if (isMobilePlatform && !isTagihan)
                                      const SizedBox(width: 8),
                                    if (!isTagihan)
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          key: _importButtonKey,
                                          onPressed: widget.onImportPressed,
                                          icon: const Icon(
                                            Icons.upload_file,
                                            size: 18,
                                          ),
                                          label: const Text('Impor Berkas'),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cukup isi angka tanpa nol di depan (contoh: Blok 1, Nomor 1).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (widget.mode == CheckMode.statusBayar) ...[
                        const SizedBox(height: 14),
                        TextField(
                          key: _tahunInputKey,
                          controller: _tahunController,
                          focusNode: _tahunFocusNode,
                          textInputAction: TextInputAction.next,
                          onEditingComplete: () {},
                          decoration: InputDecoration(
                            labelText: 'Tahun Pajak',
                            border: const OutlineInputBorder(),
                            errorText: _tahunError,
                            errorMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            if (_tahunError != null &&
                                val
                                    .replaceAll(RegExp(r'[^0-9]'), '')
                                    .isNotEmpty) {
                              setState(() => _tahunError = null);
                            }
                          },
                          onSubmitted: (_) => _handleTahunSubmitted(),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Column(
                        key: _captchaAreaKey,
                        children: [
                          Center(
                            child: _loadingCaptcha
                                ? const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: CircularProgressIndicator(),
                                  )
                                : _captchaBytes != null
                                ? Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.memory(
                                      _captchaBytes!,
                                      height: 84,
                                    ),
                                  )
                                : const Text('Gambar kode belum muncul'),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton.icon(
                              onPressed: _loadingCaptcha || _submitting
                                  ? null
                                  : () => _loadCaptcha(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Ganti Kode Gambar'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _captchaController,
                        builder: (context, value, _) {
                          return TextField(
                            key: _captchaInputKey,
                            controller: _captchaController,
                            focusNode: _captchaFocusNode,
                            textInputAction: TextInputAction.go,
                            onEditingComplete: () {},
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'Kode Verifikasi',
                              hintText: 'Ketik huruf pada gambar di atas',
                              border: const OutlineInputBorder(),
                              errorText: _captchaError,
                              errorMaxLines: 2,
                              suffixIcon: value.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      tooltip: 'Hapus teks',
                                      onPressed: () {
                                        _captchaController.clear();
                                        _captchaFocusNode.requestFocus();
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (val) {
                              if (_captchaError != null &&
                                  val.trim().isNotEmpty) {
                                setState(() => _captchaError = null);
                              }
                            },
                            onSubmitted: (_) => _submitting ? null : _submit(),
                          );
                        },
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 14),
                        LerpShakePosition(
                          shakeTrigger: _validationShakeTrigger,
                          child: AppAlertBanner(
                            message: _errorText!,
                            tone: AppBadgeTone.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      LerpPunchScale(
                        punchOnTap: !_submitting,
                        punch: 0.04,
                        child: FilledButton.icon(
                          key: _submitButtonKey,
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.search),
                          label: const Text('Cek'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_statusBayarResult != null) ...[
                const SizedBox(height: 16),
                AppAnimatedReveal(
                  child: StatusBayarResultCard(
                    result: _statusBayarResult!,
                    nop: buildNop(
                      blok: _blokController.text,
                      wilayah: _wilayahController.text,
                    ),
                    tahun: _tahunController.text.trim(),
                    client: _client,
                  ),
                ),
              ],
              if (_tagihanResult != null) ...[
                const SizedBox(height: 16),
                AppAnimatedReveal(
                  child: TagihanResultCard(
                    result: _tagihanResult!,
                    nop: buildNop(
                      blok: _blokController.text,
                      wilayah: _wilayahController.text,
                    ),
                    client: _client,
                    onOpenStatusBayar: widget.onOpenStatusBayar,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickWilayahSelector(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                ),
                children: [
                  TextSpan(
                    text: 'Wilayah: ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: 'Kec. $activeKecamatanName • ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: 'Desa $activeDesaName ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: '($activeNopPrefix)',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showSwitchDesaBottomSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ganti Desa',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSwitchDesaBottomSheet(BuildContext context) {
    final kec = findKecamatanByCode(activeKecamatanCode);
    final desaList = kec?.desaList ?? const <DesaOption>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pilih Desa untuk Cek Pajak',
                            style: Theme.of(ctx).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Kecamatan: $activeKecamatanName ($activeKecamatanCode)',
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: desaList.length,
                    itemBuilder: (context, index) {
                      final d = desaList[index];
                      final isSelected = d.code == activeKelurahanCode;
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? scheme.primary : scheme.outline,
                          size: 20,
                        ),
                        title: Text(
                          'Desa ${d.name} (${d.code})',
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? scheme.primary : null,
                          ),
                        ),
                        subtitle: Text(
                          'Prefix NOP: 3205$activeKecamatanCode${d.code}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        trailing: isSelected
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Aktif',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setActiveWilayah(
                            kecCode: activeKecamatanCode,
                            kelCode: d.code,
                            desaName: d.name,
                            kecName: activeKecamatanName,
                          );
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('startup_kel_code', d.code);
                          await prefs.setString('startup_desa_name', d.name);

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            setState(() {});
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Desa aktif diubah ke ${d.name} (3205$activeKecamatanCode${d.code})',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: scheme.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ingin mengganti Kecamatan ($activeKecamatanName)? Silakan buka menu Pengaturan Wilayah.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
