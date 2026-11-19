import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_storage.dart';
import '../blok_catatan_screen.dart';
import '../blok_data_store.dart';
import '../cianjur_wilayah_data.dart';
import '../dhkp/blok_catatan_dialogs.dart';
import '../dkhp_package_helper.dart';
import '../dusun_data.dart';
import '../incoming_file_service.dart';
import '../nop_helper.dart';
import '../staff_portal_client.dart';
import 'staff_dhkp_generate_service.dart';

/// Membuka dialog Generate Paket DHKP Baru dari Portal Staf (tanpa menghapus
/// database lokal sebelum berkas `.dkhp` dipasang).
Future<void> showStaffDhkpGenerateDialog(
  BuildContext context, {
  required StaffPortalClient client,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StaffDhkpGenerateDialog(client: client),
  );
}

class _DusunFormEntry {
  final TextEditingController nameController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController bloksController;

  _DusunFormEntry({
    required String name,
    String lat = '',
    String lng = '',
    String bloks = '',
  }) : nameController = TextEditingController(text: name),
       latController = TextEditingController(text: lat),
       lngController = TextEditingController(text: lng),
       bloksController = TextEditingController(text: bloks);

  void dispose() {
    nameController.dispose();
    latController.dispose();
    lngController.dispose();
    bloksController.dispose();
  }
}

class StaffDhkpGenerateDialog extends StatefulWidget {
  final StaffPortalClient client;

  const StaffDhkpGenerateDialog({super.key, required this.client});

  @override
  State<StaffDhkpGenerateDialog> createState() =>
      _StaffDhkpGenerateDialogState();
}

class _StaffDhkpGenerateDialogState extends State<StaffDhkpGenerateDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _tahunAwalController;
  late TextEditingController _tahunAkhirController;
  late TextEditingController _kecamatanController;
  late TextEditingController _desaController;
  late TextEditingController _kantorLatController;
  late TextEditingController _kantorLngController;
  late TextEditingController _encryptionPasswordController;
  final _passwordFieldKey = GlobalKey();
  final _passwordFocusNode = FocusNode();

  String _kecamatanCode = '';
  String _kelurahanCode = '';

  final List<_DusunFormEntry> _dusunEntries = [];
  bool _filterByDusunBlocks = true;
  bool _exportSplitByDusun = true;
  bool _includeMasterInSplit = true;
  bool _obscurePassword = true;

  bool _isProcessing = false;
  StaffDhkpGenerateProgress? _progress;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _tahunAwalController = TextEditingController(text: '2015');
    _tahunAkhirController = TextEditingController(
      text: '${DateTime.now().year}',
    );

    final kecName = widget.client.activeKecamatanName.isNotEmpty
        ? widget.client.activeKecamatanName
        : (activeKecamatanName.isNotEmpty ? activeKecamatanName : 'MANDE');
    final desaName = widget.client.activeKelurahanName.isNotEmpty
        ? widget.client.activeKelurahanName
        : (activeDesaName.isNotEmpty ? activeDesaName : 'BOBOJONG');

    _kecamatanCode = widget.client.activeKecamatanCode.isNotEmpty
        ? extractKecamatanCode3(widget.client.activeKecamatanCode)
        : activeKecamatanCode;
    _kelurahanCode = widget.client.activeKelurahanCode.isNotEmpty
        ? extractKelurahanCode3(widget.client.activeKelurahanCode)
        : activeKelurahanCode;

    _kecamatanController = TextEditingController(text: kecName);
    _desaController = TextEditingController(text: desaName);
    _encryptionPasswordController = TextEditingController();

    final kantorLat = DusunData.instance.kantorDesaLat ?? -6.763587;
    final kantorLng = DusunData.instance.kantorDesaLng ?? 107.238769;
    _kantorLatController = TextEditingController(text: kantorLat.toString());
    _kantorLngController = TextEditingController(text: kantorLng.toString());

    _initDefaultDusuns();
  }

  void _initDefaultDusuns() {
    final existingDusuns = DusunData.instance.allDusuns;
    final sourceDusuns = existingDusuns.isNotEmpty
        ? existingDusuns
        : DusunData.defaultBobojongDusuns;

    for (final d in sourceDusuns) {
      _dusunEntries.add(
        _DusunFormEntry(
          name: d.name,
          lat: d.focusLat?.toString() ?? '',
          lng: d.focusLng?.toString() ?? '',
          bloks: d.bloks
              .map((b) => int.tryParse(b)?.toString() ?? b)
              .join(', '),
        ),
      );
    }

    if (_dusunEntries.isEmpty) {
      _dusunEntries.add(_DusunFormEntry(name: 'Dusun 1', bloks: '1, 2, 3'));
    }
  }

  @override
  void dispose() {
    _tahunAwalController.dispose();
    _tahunAkhirController.dispose();
    _kecamatanController.dispose();
    _desaController.dispose();
    _kantorLatController.dispose();
    _kantorLngController.dispose();
    _encryptionPasswordController.dispose();
    _passwordFocusNode.dispose();
    for (final e in _dusunEntries) {
      e.dispose();
    }
    super.dispose();
  }

  ({
    String kecCode3,
    String kelCode3,
    String vtaxKecCode,
    String vtaxKelCode,
    String kecName,
    String desaName,
  })
  _currentResolvedWilayah() {
    return StaffDhkpGenerateService.resolveWilayahParameters(
      kelurahanCode: _kelurahanCode,
      kecamatanCode: _kecamatanCode,
      desaName: _desaController.text,
      kecamatanName: _kecamatanController.text,
      clientKelurahanCode: widget.client.activeKelurahanCode,
      clientKecamatanCode: widget.client.activeKecamatanCode,
    );
  }

  Future<void> _showCatalogWilayahPicker() async {
    final resolved = _currentResolvedWilayah();
    KecamatanOption selectedKec =
        findKecamatanByCode(resolved.kecCode3) ??
        findKecamatanByName(resolved.kecName) ??
        cianjurWilayahCatalog.first;
    DesaOption selectedDesa =
        findDesaByCode(selectedKec.code, resolved.kelCode3) ??
        (selectedKec.desaList.isNotEmpty
            ? selectedKec.desaList.first
            : const DesaOption(code: '001', name: 'DESA'));

    final picked = await showDialog<(KecamatanOption, DesaOption)>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Pilih Wilayah Kabupaten Cianjur'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<KecamatanOption>(
                      initialValue: selectedKec,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Kecamatan (32 Kecamatan)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final k in cianjurWilayahCatalog)
                          DropdownMenuItem(
                            value: k,
                            child: Text('${k.name} (3205${k.code})'),
                          ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setDialogState(() {
                          selectedKec = val;
                          selectedDesa = val.desaList.first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<DesaOption>(
                      initialValue: selectedDesa,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Desa / Kelurahan',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final d in selectedKec.desaList)
                          DropdownMenuItem(
                            value: d,
                            child: Text(
                              '${d.name} (3205${selectedKec.code}${d.code})',
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setDialogState(() {
                          selectedDesa = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, (selectedKec, selectedDesa)),
                  child: const Text('Gunakan Wilayah Ini'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      final (kec, desa) = picked;
      setState(() {
        _kecamatanCode = kec.code;
        _kelurahanCode = desa.code;
        _kecamatanController.text = kec.name;
        _desaController.text = desa.name;
      });
    }
  }

  void _addDusun() {
    setState(() {
      final nextNum = _dusunEntries.length + 1;
      _dusunEntries.add(_DusunFormEntry(name: 'Dusun $nextNum', bloks: ''));
    });
  }

  void _removeDusun(int index) {
    if (_dusunEntries.length <= 1) return;
    setState(() {
      final removed = _dusunEntries.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _pickManifestFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dkhp', 'dhkp', 'dat', 'json', 'zip'],
      );

      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;


      Map<String, dynamic>? manifest;
      final lower = path.toLowerCase();
      if (lower.endsWith('.json')) {
        final text = await File(path).readAsString();
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) manifest = decoded;
      } else {
        manifest = await DhkpPackageHelper.readBackupManifest(path);
        if (manifest == null &&
            await DhkpCrypto.isPasswordProtectedFile(path) &&
            mounted) {
          final pwd = await IncomingFileService.promptBackupPassword(context);
          if (pwd != null && pwd.isNotEmpty) {
            manifest = await DhkpPackageHelper.readBackupManifest(
              path,
              password: pwd,
            );
          }
        }
      }

      if (manifest == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gagal menemukan berkas manifest.json yang valid di dalam file tersebut.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 1. Ekstrak Wilayah (Nama & Kode Kecamatan/Desa)
      final kec = manifest['kecamatan'] as Map?;
      final desa = manifest['desa'] as Map?;
      final kecName = kec?['nama']?.toString();
      final desaName = desa?['nama']?.toString();
      final kecKode =
          kec?['kode']?.toString() ?? kec?['kode_vtax']?.toString() ?? '';
      final desaKode =
          desa?['kode']?.toString() ??
          desa?['kode_vtax']?.toString() ??
          desa?['prefix_nop']?.toString() ??
          '';

      if (kecKode.isNotEmpty) {
        _kecamatanCode = extractKecamatanCode3(kecKode);
      }
      if (desaKode.isNotEmpty) {
        _kelurahanCode = extractKelurahanCode3(desaKode);
      }
      if (kecName != null && kecName.isNotEmpty) {
        _kecamatanController.text = kecName;
      } else if (_kecamatanCode.isNotEmpty) {
        _kecamatanController.text = lookupKecamatanName(_kecamatanCode);
      }
      if (desaName != null && desaName.isNotEmpty) {
        _desaController.text = desaName;
      } else if (_kelurahanCode.isNotEmpty) {
        _desaController.text = lookupKelurahanName(
          _kelurahanCode,
          kecamatanCode: _kecamatanCode,
        );
      }

      // 2. Ekstrak Koordinat Kantor Desa
      final kantor =
          (manifest['geospasial'] as Map?)?['kantor_desa'] as Map? ??
          (desa?['kantor_desa'] as Map?);
      if (kantor != null) {
        final lat = kantor['lat']?.toString();
        final lng = kantor['lng']?.toString();
        if (lat != null && lat.isNotEmpty) _kantorLatController.text = lat;
        if (lng != null && lng.isNotEmpty) _kantorLngController.text = lng;
      }

      // 3. Ekstrak Daftar Dusun & Blok (dukung key 'dusuns' maupun 'kadus')
      final rawDusuns =
          (manifest['dusuns'] as List?) ?? (manifest['kadus'] as List?);
      if (rawDusuns != null && rawDusuns.isNotEmpty) {
        for (final e in _dusunEntries) {
          e.dispose();
        }
        _dusunEntries.clear();

        for (final item in rawDusuns) {
          if (item is Map) {
            final name =
                item['name']?.toString() ??
                item['nama']?.toString() ??
                'Dusun ${item['number'] ?? (_dusunEntries.length + 1)}';
            final titikFokus = item['titik_fokus'] as Map?;
            final lat =
                titikFokus?['lat']?.toString() ??
                item['focusLat']?.toString() ??
                '';
            final lng =
                titikFokus?['lng']?.toString() ??
                item['focusLng']?.toString() ??
                '';
            final bloksList =
                (item['bloks'] as List?) ?? (item['daftar_blok'] as List?);
            final bloksStr = bloksList != null
                ? bloksList
                      .map(
                        (b) =>
                            int.tryParse(b.toString())?.toString() ??
                            b.toString(),
                      )
                      .join(', ')
                : '';

            _dusunEntries.add(
              _DusunFormEntry(name: name, lat: lat, lng: lng, bloks: bloksStr),
            );
          }
        }
      }

      final tahunManifest =
          manifest['tahun']?.toString() ??
          manifest['tahun_pajak']?.toString() ??
          manifest['tahunPajak']?.toString();
      if (tahunManifest != null && tahunManifest.isNotEmpty) {
        _tahunAkhirController.text = tahunManifest;
      }

      setState(() {});

      if (!mounted) return;
      final resolved = _currentResolvedWilayah();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Manifest dimuat: Desa ${resolved.desaName} (${resolved.vtaxKelCode}) • ${_dusunEntries.length} Dusun',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan membaca berkas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Dusun> _buildDusunsFromForm() {
    final list = <Dusun>[];
    for (var i = 0; i < _dusunEntries.length; i++) {
      final entry = _dusunEntries[i];
      final name = entry.nameController.text.trim();
      final lat = double.tryParse(entry.latController.text.trim());
      final lng = double.tryParse(entry.lngController.text.trim());

      final bloksTokens =
          entry.bloksController.text
              .split(RegExp(r'[,;]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map((s) {
                final num = int.tryParse(s);
                return num != null
                    ? num.toString().padLeft(3, '0')
                    : s.padLeft(3, '0');
              })
              .toSet()
              .toList()
            ..sort();

      list.add(
        Dusun(
          number: i + 1,
          name: name.isNotEmpty ? name : 'Dusun ${i + 1}',
          bloks: bloksTokens,
          focusLat: lat,
          focusLng: lng,
        ),
      );
    }
    return list;
  }

  static Future<void> _copyGeneratedFilesToDirectory(
    BuildContext hostContext, {
    SplitDkhpExportResult? split,
    File? masterFile,
  }) async {
    final files = <File>[
      if (split != null)
        for (final entry in split.allEntries) entry.file
      else
        ?masterFile,
    ];
    if (files.isEmpty) return;

    final selectedDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Pilih Folder Tujuan Simpan Paket .dkhp',
    );
    if (selectedDir == null || selectedDir.trim().isEmpty) return;

    final destDir = Directory(selectedDir);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    var copiedCount = 0;
    for (final file in files) {
      final fileName = file.uri.pathSegments.last;
      final targetPath = '${destDir.path}${Platform.pathSeparator}$fileName';
      if (file.path != targetPath) {
        await file.copy(targetPath);
      }
      copiedCount++;
    }

    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext).showSnackBar(
      SnackBar(
        content: Text(
          '✅ $copiedCount berkas .dkhp terenkripsi berhasil disalin ke: ${destDir.path}',
        ),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  bool _validateFormBeforeAction() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (isValid) return true;

    final pwdError = DhkpCrypto.validateOptionalPassword(
      _encryptionPasswordController.text,
    );
    if (pwdError != null) {
      final fieldContext = _passwordFieldKey.currentContext;
      if (fieldContext != null) {
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 250),
          alignment: 0.4,
        );
      }
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(
            Icons.password_rounded,
            color: Colors.orange,
            size: 40,
          ),
          title: const Text('Kata Sandi Belum Memenuhi Syarat'),
          content: Text(pwdError),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Perbaiki'),
            ),
          ],
        ),
      ).then((_) {
        if (mounted) _passwordFocusNode.requestFocus();
      });
    }
    return false;
  }

  Future<void> _splitExistingLocalDhkp() async {
    if (!_validateFormBeforeAction()) return;
    final dusuns = _buildDusunsFromForm();
    if (dusuns.isEmpty) return;

    final localRecords = await BlokDataStore.instance.loadAll();
    if (!mounted) return;
    if (localRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Data DHKP lokal masih kosong. Silakan Generate DHKP terlebih dahulu.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final resolved = _currentResolvedWilayah();
    final kantorLat = double.tryParse(_kantorLatController.text.trim());
    final kantorLng = double.tryParse(_kantorLngController.text.trim());
    final customPwd = _encryptionPasswordController.text.trim();

    final selectedDirPath = await FilePicker.getDirectoryPath(
      dialogTitle:
          'Pilih Folder Tujuan Split ${dusuns.length} File Dusun (.dkhp)',
    );
    final targetDir =
        (selectedDirPath != null && selectedDirPath.trim().isNotEmpty)
        ? Directory(selectedDirPath)
        : await AppStorage.getBackupsDirectory();

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _progress = StaffDhkpGenerateProgress(
        currentPage: 1,
        estimatedTotalPages: 1,
        checkedRecords: localRecords.length,
        belumBayarCount: 0,
        sudahBayarCount: 0,
        currentStatus:
            'Memecah & mengenkripsi ${dusuns.length} berkas .dkhp Kedusunan...',
      );
    });

    try {
      await DusunData.instance.setDusuns(dusuns);
      if (kantorLat != null && kantorLng != null) {
        await DusunData.instance.setKantorDesaLocation(kantorLat, kantorLng);
      }
      await saveActiveWilayah(
        kecCode: resolved.kecCode3,
        kelCode: resolved.kelCode3,
        desaName: resolved.desaName,
        kecName: resolved.kecName,
      );

      final splitResult = await DhkpPackageHelper.packSplitDkhpByDusun(
        outputDirectory: targetDir,
        records: localRecords,
        dusuns: dusuns,
        kecamatanCode: resolved.kecCode3,
        kecamatanName: resolved.kecName,
        kelurahanCode: resolved.kelCode3,
        desaName: resolved.desaName,
        kantorDesaLat: kantorLat,
        kantorDesaLng: kantorLng,
        tahunPajak: _tahunAkhirController.text.trim(),
        password: customPwd.isNotEmpty ? customPwd : null,
        includeMasterDesa: _includeMasterInSplit,
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });

      await _showSplitResultDialog(splitResult, desaName: resolved.desaName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memecah paket .dkhp: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showSplitResultDialog(
    SplitDkhpExportResult split, {
    required String desaName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(
          Icons.enhanced_encryption_rounded,
          color: Colors.teal,
          size: 44,
        ),
        title: Text(
          'Split ${split.dusunEntries.length} Dusun Selesai (Terenkripsi)',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wilayah: Desa $desaName • Enkripsi: DKH2 (AES-256-GCM)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Folder: ${split.outputDirectory.path}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Divider(),
                if (split.masterEntry != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '📦 [MASTER DESA] ${split.masterEntry!.file.uri.pathSegments.last}\n'
                      '   └─ ${split.masterEntry!.recordCount} SPPT (${split.masterEntry!.blokList.length} blok)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (final d in split.dusunEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '🔐 [Dusun #${d.dusunNumber} - ${d.label}] ${d.file.uri.pathSegments.last}\n'
                      '   └─ ${d.recordCount} SPPT • Blok: ${d.blokList.isEmpty ? "-" : d.blokList.join(", ")}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (split.unassignedRecordCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '⚠️ Terdapat ${split.unassignedRecordCount} SPPT pada blok (${split.unassignedBloks.join(", ")}) yang belum dimasukkan ke dusun mana pun.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () =>
                _copyGeneratedFilesToDirectory(context, split: split),
            icon: const Icon(Icons.folder_copy_outlined, size: 18),
            label: const Text('Salin ke Folder Lain...'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _installGeneratedDkhpFile(
    BuildContext hostContext, {
    required File file,
    String? password,
  }) async {
    if (!hostContext.mounted) return false;
    final fileName = file.uri.pathSegments.last;

    DhkpInstallPlan plan;
    try {
      plan = await DhkpPackageHelper.inspectInstallPlan(
        file.path,
        password: password,
      );
    } catch (e) {
      if (hostContext.mounted) {
        ScaffoldMessenger.of(hostContext).showSnackBar(
          SnackBar(
            content: Text('Gagal memeriksa berkas DHKP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (!hostContext.mounted) return false;
    final confirmed = await confirmDhkpInstallPlanIfNeeded(
      hostContext,
      plan,
      fileName: fileName,
    );
    if (!confirmed || !hostContext.mounted) return false;

    showDialog<void>(
      context: hostContext,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Memasang berkas DHKP ke aplikasi...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final records = await DhkpPackageHelper.unpackDkhp(
        file.path,
        password: password,
      );
      await BlokDataStore.instance.loadAll();
      BlokCatatanScreen.refreshIfOpen();

      if (hostContext.mounted) {
        Navigator.of(hostContext, rootNavigator: true).pop();
        ScaffoldMessenger.of(hostContext).showSnackBar(
          SnackBar(
            content: Text(
              buildDhkpInstallSuccessMessage(
                plan: plan,
                recordCount: records.length,
                isDat: false,
              ),
            ),
            backgroundColor: Colors.teal.shade800,
          ),
        );
      }
      return true;
    } catch (e) {
      if (hostContext.mounted) {
        Navigator.of(hostContext, rootNavigator: true).pop();
        ScaffoldMessenger.of(hostContext).showSnackBar(
          SnackBar(
            content: Text('Gagal memasang berkas DHKP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _startGenerate() async {
    if (!_validateFormBeforeAction()) return;

    final tAwal = _tahunAwalController.text.trim();
    final tAkhir = _tahunAkhirController.text.trim();
    final labelTahun = tAwal == tAkhir ? tAwal : '$tAwal s/d $tAkhir';
    final resolvedWilayah = _currentResolvedWilayah();

    final dusuns = _buildDusunsFromForm();
    final allConfiguredBlocks = <String>{};
    for (final d in dusuns) {
      for (final b in d.bloks) {
        final cb = b.padLeft(3, '0');
        if (cb.isNotEmpty) allConfiguredBlocks.add(cb);
      }
    }

    final cakupanKet = (_filterByDusunBlocks && allConfiguredBlocks.isNotEmpty)
        ? 'Hanya blok terdaftar pada dusun (${allConfiguredBlocks.length} blok: ${allConfiguredBlocks.join(", ")})'
        : 'Semua blok se-desa (tanpa filter blok dusun)';
    final splitKet = _exportSplitByDusun
        ? 'Otomatis dipecah ke ${dusuns.length} file .dkhp Kedusunan${_includeMasterInSplit ? " + 1 Master Desa" : ""} (Terenkripsi DKH2 AES-256-GCM)'
        : '1 berkas Master Desa (.dkhp Terenkripsi DKH2 AES-256-GCM)';
    final previewPwd = _encryptionPasswordController.text.trim();
    final kunciKet = previewPwd.isNotEmpty
        ? '\n🔑 Kunci Enkripsi: Kata Sandi Kustom (${previewPwd.length} karakter)'
        : '\n🔑 Kunci Enkripsi: Kunci Pemulihan / Sandi Backup aktif (otomatis)';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Expanded(child: Text('Konfirmasi Generate Paket DHKP')),
          ],
        ),
        content: Text(
          'Anda akan mengunduh data SPPT Tahun $labelTahun dari Portal Staf untuk:\n'
          '• Kecamatan: ${resolvedWilayah.kecName} (${resolvedWilayah.vtaxKecCode})\n'
          '• Desa/Kel.: ${resolvedWilayah.desaName} (${resolvedWilayah.vtaxKelCode})\n\n'
          '📌 Cakupan: $cakupanKet\n'
          '🔐 Paket Keluaran: $splitKet$kunciKet\n\n'
          '🛡️ Data DHKP di aplikasi saat ini TIDAK akan dihapus atau ditimpa selama proses generate. '
          'Pemasangan/penimpaan hanya dilakukan setelah generate selesai dan Anda memilih memasang berkas .dkhp.\n\n'
          'Lanjutkan proses generate?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Ya, Mulai Generate'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final kantorLat = double.tryParse(_kantorLatController.text.trim());
    final kantorLng = double.tryParse(_kantorLngController.text.trim());
    final customPwd = _encryptionPasswordController.text.trim();
    final effectivePwd = customPwd.isNotEmpty ? customPwd : null;

    setState(() {
      _isProcessing = true;
      _cancelled = false;
      _progress = null;
    });

    final outcome = await StaffDhkpGenerateService.instance.generateAndApply(
      client: widget.client,
      tahunAwal: tAwal,
      tahunAkhir: tAkhir,
      kelurahanCode: resolvedWilayah.kelCode3,
      kecamatanCode: resolvedWilayah.kecCode3,
      desaName: resolvedWilayah.desaName,
      kecamatanName: resolvedWilayah.kecName,
      dusuns: dusuns,
      filterByDusunBlocks: _filterByDusunBlocks,
      kantorDesaLat: kantorLat,
      kantorDesaLng: kantorLng,
      targetPemdaThreshold: 2000000,
      exportSplitByDusun: _exportSplitByDusun,
      includeMasterInSplit: _includeMasterInSplit,
      encryptionPassword: effectivePwd,
      applyToLocalDb: false,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
      shouldCancel: () => _cancelled,
    );

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
    });

    if (outcome.success) {
      final split = outcome.splitExportResult;
      final masterFile = outcome.generatedMasterFile;
      final hostContext = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      if (!hostContext.mounted) return;
      await showDialog<void>(
        context: hostContext,
        builder: (c) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Colors.green,
            size: 48,
          ),
          title: const Text('Paket DHKP Berhasil Digenerate!'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tahun Pajak: ${outcome.tahun}'),
                  Text(
                    'Wilayah: Desa ${outcome.desaName}, Kec. ${outcome.kecamatanName} (3205${outcome.kecamatanCode}${outcome.kelurahanCode})',
                  ),
                  const Divider(),
                  Text(
                    '• Total SPPT Terbit: ${outcome.totalRecords} objek pajak',
                  ),
                  Text('• Sudah Bayar: ${outcome.sudahBayarCount} NOP'),
                  Text('• Belum Bayar: ${outcome.belumBayarCount} NOP'),
                  Text(
                    '• Target Pemda (>= 2 Juta): ${outcome.targetPemdaCount} NOP',
                  ),
                  Text('• Terdeteksi: ${outcome.totalBloks} Blok aktif'),
                  if (split != null) ...[
                    const Divider(),
                    Text(
                      '🔐 Paket .dkhp Terenkripsi (${split.dusunEntries.length} Dusun${split.masterEntry != null ? " + 1 Master" : ""}):',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lokasi: ${split.outputDirectory.path}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    if (split.masterEntry != null)
                      Text(
                        '• [MASTER] ${split.masterEntry!.file.uri.pathSegments.last} (${split.masterEntry!.recordCount} NOP)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    for (final d in split.dusunEntries)
                      Text(
                        '• [Dusun #${d.dusunNumber} - ${d.label}] ${d.file.uri.pathSegments.last} (${d.recordCount} NOP)',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ] else if (masterFile != null) ...[
                    const Divider(),
                    const Text(
                      '🔐 Berkas Master .dkhp Terenkripsi:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${masterFile.uri.pathSegments.last}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Lokasi: ${masterFile.parent.path}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Data lokal aplikasi belum berubah. Ketuk "Pasang File DHKP" di bawah untuk memasangnya sekarang '
                    '(jika tahun pajak masih kosong langsung terisi/diperbarui; jika tahun sama sudah terisi akan meminta konfirmasi timpa).',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (split != null || masterFile != null)
              OutlinedButton.icon(
                onPressed: () => _copyGeneratedFilesToDirectory(
                  hostContext,
                  split: split,
                  masterFile: masterFile,
                ),
                icon: const Icon(Icons.folder_copy_outlined, size: 18),
                label: const Text('Simpan ke Folder Lain...'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup Saja'),
            ),
            if (masterFile != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                ),
                onPressed: () async {
                  Navigator.pop(c);
                  await _installGeneratedDkhpFile(
                    hostContext,
                    file: masterFile,
                    password: effectivePwd,
                  );
                },
                icon: const Icon(Icons.download_done_rounded, size: 18),
                label: const Text('Pasang File DHKP'),
              ),
          ],
        ),
      );
    } else if (outcome.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proses generate DHKP dibatalkan.')),
      );
    } else {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 48,
          ),
          title: const Text('Gagal Generate DHKP'),
          content: Text(
            outcome.errorMessage ?? 'Terjadi kesalahan tidak dikenal.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isProcessing) {
      final p = _progress;
      final ratio = p?.ratio ?? 0.0;
      final status =
          p?.currentStatus ?? 'Menghubungkan ke Portal Staf Bapenda...';

      return AlertDialog(
        title: const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Menyusun DHKP Master...')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: ratio > 0 ? ratio : null),
            const SizedBox(height: 12),
            Text(status, style: const TextStyle(fontSize: 13)),
            if (p != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tercatat: ${p.belumBayarCount} Belum Bayar • ${p.sudahBayarCount} Sudah Bayar',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _cancelled = true;
              });
            },
            child: const Text('Batalkan', style: TextStyle(color: Colors.red)),
          ),
        ],
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generate Paket DHKP Baru',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Unduh SPPT dari Portal Staf & buat berkas .dkhp tanpa menghapus data lokal.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // FORM BODY
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TOMBOL MUAT DARI BERKAS MANIFEST
                      OutlinedButton.icon(
                        onPressed: _pickManifestFile,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text(
                          '📁 Muat Otomatis dari Berkas .dkhp / .dat (Hanya Ambil Manifest)',
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // TAHUN PAJAK (RENTANG TAHUN) & KECAMATAN
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _tahunAwalController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Tahun Awal',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          hintText: '2015',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Wajib'
                                            : null,
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text(
                                        's/d',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _tahunAkhirController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Tahun Akhir',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          hintText: '2026',
                                        ),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                            ? 'Wajib'
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _tahunAwalController.text =
                                              '${DateTime.now().year}';
                                          _tahunAkhirController.text =
                                              '${DateTime.now().year}';
                                        });
                                      },
                                      child: Chip(
                                        label: Text(
                                          'Tahun Ini (${DateTime.now().year})',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _tahunAwalController.text = '2015';
                                          _tahunAkhirController.text =
                                              '${DateTime.now().year}';
                                        });
                                      },
                                      child: Chip(
                                        label: Text(
                                          '2015 - ${DateTime.now().year}',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _kecamatanController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Kecamatan',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Wajib diisi'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // DESA & TOMBOL PILIH KATALOG WILAYAH
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _desaController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Desa / Kelurahan',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Wajib diisi'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _showCatalogWilayahPicker,
                            icon: const Icon(
                              Icons.location_searching_rounded,
                              size: 16,
                            ),
                            label: const Text('Pilih Wilayah'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          final resolved = _currentResolvedWilayah();
                          return Text(
                            'Kode V-Tax Bapenda: ${resolved.vtaxKelCode} (Kec. ${resolved.kecName} [${resolved.kecCode3}] • Desa ${resolved.desaName} [${resolved.kelCode3}])',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _kantorLatController,
                              decoration: const InputDecoration(
                                labelText: 'Latitude Kantor Desa',
                                border: OutlineInputBorder(),
                                isDense: true,
                                hintText: '-6.763587',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _kantorLngController,
                              decoration: const InputDecoration(
                                labelText: 'Longitude Kantor Desa',
                                border: OutlineInputBorder(),
                                isDense: true,
                                hintText: '107.238769',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // DAFTAR DUSUN & BLOK
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Pembagian Dusun & Blok (${_dusunEntries.length} Dusun)',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addDusun,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Dusun'),
                          ),
                        ],
                      ),
                      Text(
                        'Tuliskan nama dusun, koordinat fokus, dan daftar bloknya (pisahkan dengan koma). Misal 3 dusun dipecah 3, atau Desa Bobojong 5 dusun dipecah 5.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // KARTU FORM DUSUN
                      ..._dusunEntries.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Dusun #${idx + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (_dusunEntries.length > 1)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Hapus Dusun',
                                        onPressed: () => _removeDusun(idx),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: item.nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Nama Dusun',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    hintText: 'Dusun ${idx + 1}',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: item.latController,
                                        decoration: const InputDecoration(
                                          labelText: 'Lat Fokus',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: item.lngController,
                                        decoration: const InputDecoration(
                                          labelText: 'Lng Fokus',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: item.bloksController,
                                  decoration: const InputDecoration(
                                    labelText: 'Daftar Blok (pisahkan koma)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    hintText: '1, 2, 3, 4, 11, 12, ...',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 10),

                      // OPSI FILTER CAKUPAN BLOK BERDASARKAN DUSUN
                      Material(
                        color: isDark
                            ? Colors.grey.shade900
                            : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text(
                              'Hanya ambil blok yang terdaftar pada form dusun di atas',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              'Jika dicentang dan Anda hanya mengisi Dusun 1, maka hanya data blok Dusun 1 yang disimpan. '
                              'Bila tidak dicentang, seluruh blok se-desa akan diambil.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                            value: _filterByDusunBlocks,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _filterByDusunBlocks = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // OPSI SPLIT (PECAH) PAKET .DKHP TERENKRIPSI PER KEDUSUNAN
                      Material(
                        color: Colors.teal.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: Colors.teal.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.call_split_rounded,
                                    color: Colors.teal.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Split (Pecah) & Enkripsi File .dkhp per Kedusunan (${_dusunEntries.length} Dusun)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  'Otomatis pecah menjadi ${_dusunEntries.length} berkas .dkhp Kedusunan saat selesai Generate',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Setiap berkas .dkhp dienkripsi (DKH2 AES-256-GCM) dan berisi manifest sesuai input serta terkunci khusus untuk blok dusun masing-masing.',
                                  style: TextStyle(fontSize: 11),
                                ),
                                value: _exportSplitByDusun,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _exportSplitByDusun = val);
                                  }
                                },
                              ),
                              if (_exportSplitByDusun)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                    'Sertakan 1 berkas Master Desa utuh (DHKP_MASTER_...dkhp)',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _includeMasterInSplit,
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(
                                        () => _includeMasterInSplit = val,
                                      );
                                    }
                                  },
                                ),
                              const SizedBox(height: 6),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _encryptionPasswordController,
                                builder: (context, val, _) {
                                  final trimmedLen = val.text.trim().length;
                                  final isReady =
                                      trimmedLen >=
                                      DhkpCrypto.minPasswordLength;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                        key: _passwordFieldKey,
                                        controller:
                                            _encryptionPasswordController,
                                        focusNode: _passwordFocusNode,
                                        obscureText: _obscurePassword,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        validator: DhkpCrypto
                                            .validateOptionalPassword,
                                        decoration: InputDecoration(
                                          labelText:
                                              'Kata Sandi Enkripsi .dkhp (Opsional, min. ${DhkpCrypto.minPasswordLength} karakter)',
                                          hintText:
                                              'Minimal ${DhkpCrypto.minPasswordLength} karakter, atau kosongkan',
                                          helperText:
                                              'Jika diisi, wajib minimal ${DhkpCrypto.minPasswordLength} karakter. Kosongkan untuk memakai Kunci Pemulihan aktif.',
                                          helperMaxLines: 2,
                                          errorMaxLines: 2,
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                          prefixIcon: const Icon(
                                            Icons.lock_outline_rounded,
                                            size: 18,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                              size: 18,
                                            ),
                                            onPressed: () {
                                              setState(
                                                () => _obscurePassword =
                                                    !_obscurePassword,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      if (isReady) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '✓ Kata sandi memenuhi syarat ($trimmedLen karakter).',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _splitExistingLocalDhkp,
                                icon: const Icon(
                                  Icons.content_cut_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  'Pecah (Split) Data DHKP Aktif Sekarang ke ${_dusunEntries.length} File Dusun (.dkhp)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(38),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),


                      // INFO BUKU 1, 2, 3 & TARGET PEMDA
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.shade700.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              color: Colors.amber.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Khusus Buku 1, 2, 3 (PBB Pedesaan s/d Rp 2.000.000): Data diambil langsung dari tabel Bapenda dengan metode santai/lambat (jeda aman) agar stabil dan tidak terputus. Target Pemda (>= Rp 2.000.000) otomatis dipisahkan.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // INFO MODE AMAN (TIDAK MENIMPA SAAT GENERATE)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: Colors.teal.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mode Aman: Data DHKP lokal tidak dihapus/ditimpa saat proses generate. '
                                'Pemasangan dilakukan setelah berkas .dkhp selesai dibuat (tahun baru memperbarui tanpa menimpa tahun lama; tahun sama meminta konfirmasi timpa).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.teal.shade800,
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
            ),

            // FOOTER ACTIONS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                    ),
                    onPressed: _startGenerate,
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('Mulai Generate Paket DHKP'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
