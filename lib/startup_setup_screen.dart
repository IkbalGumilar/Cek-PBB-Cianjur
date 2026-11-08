import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cianjur_wilayah_data.dart';
import 'file_importer.dart';
import 'main_shell.dart';
import 'nop_helper.dart';
import 'services/location_service.dart';
import 'theme_controller.dart';

/// Widget Wizard Interaktif dengan animasi untuk memandu pengguna saat pertama kali
/// membuka aplikasi:
/// - Langkah 1: Sapaan Hangat & Sambutan ("Sampurasun!").
/// - Langkah 2: Identitas Wilayah Kerja Desa (Kecamatan, Desa, dan Prefix NOP 10 Digit).
/// - Langkah 3: Data Master DHKP (Opsional — dapat diunggah atau dilewati) & Mulai Masuk Beranda.
class StartupSetupScreen extends StatefulWidget {
  final ThemeController? themeController;
  final bool isStandaloneSettings;

  const StartupSetupScreen({
    super.key,
    this.themeController,
    this.isStandaloneSettings = false,
  });

  @override
  State<StartupSetupScreen> createState() => _StartupSetupScreenState();
}

class _StartupSetupScreenState extends State<StartupSetupScreen>
    with SingleTickerProviderStateMixin {
  static const _prefSetupKey = 'startup_setup_completed';
  static const _prefDesaNameKey = 'startup_desa_name';
  static const _prefKecCodeKey = 'startup_kec_code';
  static const _prefKelCodeKey = 'startup_kel_code';
  static const _prefKecNameKey = 'startup_kec_name';

  late final PageController _pageController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  int _currentStep = 0;

  // State Form Wilayah & DHKP (Tanpa default hardcode)
  String? _selectedKecCode;
  String? _selectedDesaCode;
  bool _isManualDesa = false;
  bool _isDetectingLocation = false;

  late final TextEditingController _desaNameController;
  late final TextEditingController _kelCodeController;
  late final TextEditingController _tahunPajakController;

  File? _pickedDhkpFile;
  bool _saving = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.isStandaloneSettings ? 1 : 0;
    _pageController = PageController(initialPage: _currentStep);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutBack),
    );

    _desaNameController = TextEditingController();
    _kelCodeController = TextEditingController();
    _tahunPajakController = TextEditingController(
      text: '${DateTime.now().year}',
    );

    _loadSavedPreferences();
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kec = prefs.getString(_prefKecCodeKey);
      final desa = prefs.getString(_prefDesaNameKey);
      final kel = prefs.getString(_prefKelCodeKey);

      if (mounted) {
        setState(() {
          if (kec != null && kec.isNotEmpty) {
            _selectedKecCode = kec;
          }
          if (kel != null && kel.isNotEmpty) {
            _kelCodeController.text = kel;
            _selectedDesaCode = kel;
          }
          if (desa != null && desa.isNotEmpty) {
            _desaNameController.text = desa;
          }
          if (_selectedKecCode != null) {
            _syncDesaSelection();
          }
        });
      }
    } catch (_) {}
  }

  void _syncDesaSelection() {
    if (_selectedKecCode == null) return;
    final kec = findKecamatanByCode(_selectedKecCode!);
    if (kec == null || kec.desaList.isEmpty) {
      _isManualDesa = true;
      _selectedDesaCode = 'custom';
      return;
    }

    if (_selectedDesaCode == null) return;

    final hasMatchingDesa =
        kec.desaList.any((d) => d.code == _selectedDesaCode);
    if (!hasMatchingDesa) {
      _isManualDesa = true;
      _selectedDesaCode = 'custom';
    } else {
      _isManualDesa = false;
      final desa = kec.desaList.firstWhere((d) => d.code == _selectedDesaCode);
      _desaNameController.text = desa.name;
      _kelCodeController.text = desa.code;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _desaNameController.dispose();
    _kelCodeController.dispose();
    _tahunPajakController.dispose();
    super.dispose();
  }

  String get _calculatedNopPrefix {
    if (_selectedKecCode == null || _kelCodeController.text.trim().isEmpty) {
      return '32.05.---.---';
    }
    final cleanKel = _kelCodeController.text
        .replaceAll(RegExp(r'[^0-9]'), '')
        .padLeft(3, '0');
    return calculateNopPrefix(_selectedKecCode!, cleanKel);
  }

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _handleAutoDetectLocation() async {
    setState(() {
      _isDetectingLocation = true;
    });

    try {
      // 1. Minta izin aplikasi (Notifikasi, Penyimpanan, Lokasi)
      final perms = await LocationService.instance.requestAllAppPermissions();

      if (!perms.locationGranted && (Platform.isAndroid || Platform.isIOS)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin lokasi belum diberikan. Silakan pilih Kecamatan & Desa secara manual atau aktifkan izin lokasi.',
            ),
            backgroundColor: Color(0xFFD97706),
          ),
        );
        return;
      }

      // 2. Deteksi wilayah kerja saat ini via GPS / Geolocation
      final result = await LocationService.instance.detectCurrentWilayah();
      if (!mounted) return;

      if (result != null) {
        setState(() {
          _selectedKecCode = result.kecCode;
          _selectedDesaCode = result.desaCode;
          _desaNameController.text = result.desaName;
          _kelCodeController.text = result.desaCode;
          _isManualDesa = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lokasi terdeteksi (${result.sourceDescription}): Desa ${result.desaName}, Kec. ${result.kecName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak dapat mendeteksi koordinat wilayah secara presisi. Silakan pilih dari daftar kecamatan di bawah.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mendeteksi lokasi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDetectingLocation = false;
        });
      }
    }
  }

  Future<void> _pickDhkpFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'dat', 'dkhp', 'txt'],
      );
      if (files.isNotEmpty && files.first.path != null) {
        final file = File(files.first.path!);
        setState(() {
          _pickedDhkpFile = file;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih berkas DHKP: $e')),
      );
    }
  }

  Future<void> _saveAndProceed() async {
    setState(() {
      _saving = true;
      _statusMessage = 'Menyiapkan wilayah kerja & basis data...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      final kecCode = _selectedKecCode ?? '010';
      final kec = findKecamatanByCode(kecCode);
      final kecName = kec?.name ?? 'Kec. $kecCode';
      final desaName = _desaNameController.text.trim().toUpperCase();
      final kelCode = _kelCodeController.text.trim().padLeft(3, '0');

      setActiveWilayah(
        kecCode: kecCode,
        kelCode: kelCode,
        desaName: desaName,
        kecName: kecName,
      );

      await prefs.setString(_prefKecCodeKey, kecCode);
      await prefs.setString(_prefDesaNameKey, desaName);
      await prefs.setString(_prefKelCodeKey, kelCode);
      await prefs.setString(_prefKecNameKey, kecName);
      await prefs.setBool(_prefSetupKey, true);

      // Jika ada berkas DHKP yang dipilih, impor ke basis data lokal (opsional)
      if (_pickedDhkpFile != null) {
        setState(() {
          _statusMessage = 'Mengimpor data master DHKP...';
        });
        try {
          await FileImporter.importFrom(_pickedDhkpFile!.path);
        } catch (e) {
          debugPrint('FileImporter error on startup: $e');
        }
      }

      if (!mounted) return;

      if (widget.isStandaloneSettings && Navigator.canPop(context)) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, _, _) => MainShell(
              themeController: widget.themeController ?? ThemeController(),
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan menyimpan setup: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isStandaloneSettings
              ? 'Pengaturan Wilayah Kerja'
              : 'Setup Awal Wilayah Kerja Desa',
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        leading: widget.isStandaloneSettings
            ? const BackButton()
            : _currentStep > 0
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Kembali ke langkah sebelumnya',
                    onPressed: () => _goToStep(_currentStep - 1),
                  )
                : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Indikator Langkah Wizard (Stepper Header)
            _buildStepIndicator(context),

            // Konten Wizard (PageView)
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Terpandu via tombol
                children: [
                  _buildStep1Greeting(context),
                  _buildStep2Wilayah(context),
                  _buildStep3Dhkp(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Indikator visual progres langkah wizard
  Widget _buildStepIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stepLabels = ['Sambutan', 'Wilayah Kerja', 'Master DHKP'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final isCurrent = _currentStep == index;
              final isPassed = _currentStep > index;

              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? colorScheme.primaryContainer
                              : isPassed
                                  ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
                                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrent
                                ? colorScheme.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCurrent
                                    ? colorScheme.primary
                                    : isPassed
                                        ? colorScheme.secondary
                                        : colorScheme.outline.withValues(alpha: 0.3),
                              ),
                              child: Center(
                                child: isPassed
                                    ? Icon(
                                        Icons.check,
                                        size: 14,
                                        color: colorScheme.onSecondary,
                                      )
                                    : Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                stepLabels[index],
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isCurrent
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (index < 2) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colorScheme.outlineVariant,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // LANGKAH 1: SAPAAN HANGAT & SAMBUTAN AWAL
  // ==========================================
  Widget _buildStep1Greeting(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // Logo dengan animasi denyut halus
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 100,
                  height: 100,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'logo/kabupaten-cianjur.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.account_balance_rounded,
                      size: 54,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Sapaan Khas & Ramah
              Text(
                'Sampurasun!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Selamat Datang di Cek PBB Cianjur',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Aplikasi pendamping cerdas untuk kolektor, staf desa, dan warga dalam memeriksa ketetapan, memantau realisasi pembayaran, dan mengelola piutang PBB-P2 se-Kabupaten Cianjur.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 24),

              // Kartu Sorotan Fitur
              _buildFeatureHighlightCard(
                context,
                icon: Icons.domain_verification_rounded,
                iconColor: Colors.teal.shade600,
                title: 'Multi-Desa & Multi-Kecamatan (32 Kecamatan)',
                subtitle:
                    'Siap digunakan langsung untuk desa mana pun di Kabupaten Cianjur dengan katalog NOP prefix resmi.',
              ),
              const SizedBox(height: 10),
              _buildFeatureHighlightCard(
                context,
                icon: Icons.table_view_rounded,
                iconColor: Colors.indigo.shade600,
                title: 'Otomatisasi Pembagian Blok & DHKP',
                subtitle:
                    'Pembagian dusun dan blok wilayah otomatis terbaca saat berkas DHKP dimuat ke sistem lokal.',
              ),
              const SizedBox(height: 10),
              _buildFeatureHighlightCard(
                context,
                icon: Icons.bolt_rounded,
                iconColor: Colors.amber.shade800,
                title: 'Cepat & Fleksibel Tanpa Hambatan',
                subtitle:
                    'Dapat langsung digunakan memeriksa tagihan online walau berkas DHKP belum diunggah.',
              ),

              const SizedBox(height: 16),

              // Card Izin Akses Aplikasi (Notifikasi, Penyimpanan, Lokasi)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Izin Akses Aplikasi',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionInfoRow(
                      context,
                      icon: Icons.notifications_active_outlined,
                      title: 'Notifikasi',
                      desc: 'Pengingat jatuh tempo PBB & info sinkronisasi data.',
                    ),
                    const SizedBox(height: 8),
                    _buildPermissionInfoRow(
                      context,
                      icon: Icons.folder_open_rounded,
                      title: 'Penyimpanan',
                      desc: 'Membaca paket DHKP (.dkhp/Excel) & ekspor laporan PDF.',
                    ),
                    const SizedBox(height: 8),
                    _buildPermissionInfoRow(
                      context,
                      icon: Icons.location_on_outlined,
                      title: (Platform.isAndroid || Platform.isIOS) ? 'Lokasi GPS' : 'Lokasi Jaringan (IP)',
                      desc: (Platform.isAndroid || Platform.isIOS)
                          ? 'Deteksi otomatis wilayah kerja & titik objek pajak di peta.'
                          : 'Deteksi otomatis wilayah kerja via jaringan internet (IP Geolocation).',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Tombol Mulai Wizard
              FilledButton.icon(
                key: const ValueKey('btn_mulai_wizard'),
                onPressed: () {
                  LocationService.instance.requestAllAppPermissions().ignore();
                  _goToStep(1);
                },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Mulai Konfigurasi Wilayah Kerja'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureHighlightCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionInfoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // LANGKAH 2: WILAYAH KERJA ADMINISTRATIF
  // ==========================================
  Widget _buildStep2Wilayah(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final kec = _selectedKecCode != null ? findKecamatanByCode(_selectedKecCode!) : null;
    final desaList = kec?.desaList ?? const <DesaOption>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader(
                context,
                icon: Icons.domain_rounded,
                title: '1. Identitas Wilayah Administratif',
                subtitle:
                    'Pilih kecamatan dan desa/kelurahan resmi tempat Anda bertugas di Kabupaten Cianjur.',
              ),
              const SizedBox(height: 16),

              // Banner Deteksi Lokasi Otomatis via GPS
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0.5),
                      colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.my_location_rounded,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Deteksi Otomatis Lokasi Kerja',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (Platform.isAndroid || Platform.isIOS)
                          ? 'Aktifkan izin lokasi agar sistem langsung mendeteksi posisi Anda saat ini dan mengisi otomatis pilihan Kecamatan serta Desa tempat Anda bertugas di Cianjur.'
                          : 'Pada perangkat Desktop (Windows/Linux), sistem mendeteksi lokasi wilayah kerja Anda secara otomatis melalui jaringan internet (IP Geolocation).',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      key: const ValueKey('btn_auto_detect_location'),
                      onPressed: _isDetectingLocation ? null : _handleAutoDetectLocation,
                      icon: _isDetectingLocation
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.gps_fixed_rounded, size: 16),
                      label: Text(
                        _isDetectingLocation
                            ? 'Mendeteksi Posisi...'
                            : '📍 Deteksi Lokasi Saya Sekarang',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Dropdown Kecamatan (32 Kecamatan)
                      DropdownButtonFormField<String>(
                        key: const ValueKey('dropdown_kecamatan'),
                        isExpanded: true,
                        initialValue: _selectedKecCode,
                        hint: const Text('Pilih Kecamatan...'),
                        decoration: const InputDecoration(
                          labelText: 'Kecamatan (Kabupaten Cianjur) *',
                          prefixIcon: Icon(Icons.apartment_rounded),
                          border: OutlineInputBorder(),
                        ),
                        items: cianjurWilayahCatalog.map((k) {
                          return DropdownMenuItem<String>(
                            value: k.code,
                            child: Text(
                              'Kec. ${k.name} (${k.code})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedKecCode = val;
                              _selectedDesaCode = null;
                              _desaNameController.text = '';
                              _kelCodeController.text = '';
                              _isManualDesa = false;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Dropdown Desa / Kelurahan
                      if (_selectedKecCode == null)
                        DropdownButtonFormField<String>(
                          key: const ValueKey('dropdown_desa_placeholder'),
                          isExpanded: true,
                          hint: const Text('Pilih Kecamatan terlebih dahulu'),
                          decoration: const InputDecoration(
                            labelText: 'Desa / Kelurahan Kerja *',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [],
                          onChanged: null,
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey('dropdown_desa_$_selectedKecCode'),
                          isExpanded: true,
                          initialValue: _selectedDesaCode,
                          hint: const Text('Pilih Desa / Kelurahan...'),
                          decoration: const InputDecoration(
                            labelText: 'Desa / Kelurahan Kerja *',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            ...desaList.map((d) {
                              return DropdownMenuItem<String>(
                                value: d.code,
                                child: Text(
                                  'Desa ${d.name} (${d.code})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                            const DropdownMenuItem<String>(
                              value: 'custom',
                              child: Text(
                                'Lainnya / Masukkan Kode Manual',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedDesaCode = val;
                                if (val == 'custom') {
                                  _isManualDesa = true;
                                } else {
                                  _isManualDesa = false;
                                  final d = desaList.firstWhere(
                                    (element) => element.code == val,
                                    orElse: () => DesaOption(
                                      code: val,
                                      name: _desaNameController.text,
                                    ),
                                  );
                                  _desaNameController.text = d.name;
                                  _kelCodeController.text = d.code;
                                }
                              });
                            }
                          },
                        ),

                      // Input manual jika memilih custom
                      if (_isManualDesa) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _desaNameController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Nama Desa / Kelurahan Manual',
                            hintText: 'Contoh: BOBOJONG',
                            prefixIcon: Icon(Icons.edit_note_rounded),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _kelCodeController,
                          keyboardType: TextInputType.number,
                          maxLength: 3,
                          decoration: const InputDecoration(
                            labelText: 'Kode Desa (3 Digit)',
                            hintText: 'Contoh: 004',
                            prefixIcon: Icon(Icons.tag_rounded),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Kartu NOP Prefix 10 Digit Interaktif
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      const Flexible(
                                        child: Text(
                                          'Prefix NOP 10 Digit (Otomatis)',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Kec. $_selectedKecCode - Desa ${_kelCodeController.text.padLeft(3, '0')} (${_desaNameController.text})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _calculatedNopPrefix,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Navigasi Langkah 2
              Row(
                children: [
                  if (!widget.isStandaloneSettings)
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () => _goToStep(0),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Kembali'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (!widget.isStandaloneSettings) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (context) {
                        final bool isWilayahValid = _selectedKecCode != null &&
                            ((!_isManualDesa &&
                                    _selectedDesaCode != null &&
                                    _selectedDesaCode != 'custom') ||
                                (_isManualDesa &&
                                    _desaNameController.text.trim().isNotEmpty &&
                                    _kelCodeController.text.trim().isNotEmpty));

                        return FilledButton.icon(
                          key: const ValueKey('btn_lanjut_ke_dhkp'),
                          onPressed: isWilayahValid ? () => _goToStep(2) : null,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Lanjut ke Data DHKP'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // LANGKAH 3: DATA MASTER DHKP & SELESAI
  // ==========================================
  Widget _buildStep3Dhkp(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader(
                context,
                icon: Icons.table_chart_rounded,
                title: '2. Data Master DHKP (Ketetapan SPPT)',
                subtitle:
                    'Muat berkas DHKP resmi (.xlsx, .csv, atau .dat). Bagian ini opsional — dapat dilewati dan diimpor nanti.',
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Area Pilih Berkas DHKP
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickDhkpFile,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 24,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _pickedDhkpFile != null
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                              width: _pickedDhkpFile != null ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _pickedDhkpFile != null
                                    ? Icons.task_alt_rounded
                                    : Icons.cloud_upload_outlined,
                                size: 38,
                                color: _pickedDhkpFile != null
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _pickedDhkpFile != null
                                    ? 'Berkas DHKP Terpilih'
                                    : 'Pilih Berkas DHKP (Excel / CSV / DAT)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _pickedDhkpFile != null
                                    ? 'Ketuk untuk mengganti berkas yang dipilih'
                                    : 'Mendukung format .xlsx, .xls, .csv, .dat, .dkhp',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_pickedDhkpFile != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file_outlined,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _pickedDhkpFile!.uri.pathSegments.last,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    setState(() => _pickedDhkpFile = null),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _tahunPajakController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tahun Pajak Ketetapan',
                          hintText: '2026',
                          prefixIcon: Icon(Icons.calendar_today_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Info opsionalitas DHKP
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Jika belum memiliki berkas DHKP, Anda dapat langsung melanjutkan. Fitur pencarian NOP online tetap berfungsi!',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Tombol Simpan & Selesai
              if (_saving) ...[
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        _statusMessage ?? 'Memproses...',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () => _goToStep(1),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Kembali'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        key: const ValueKey('btn_simpan_selesai'),
                        onPressed: _saving ? null : _saveAndProceed,
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: const Text('Simpan & Mulai Gunakan Aplikasi'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('btn_lewati_dhkp'),
                  onPressed: _saving ? null : _saveAndProceed,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Lewati Langkah Ini & Selesaikan'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
