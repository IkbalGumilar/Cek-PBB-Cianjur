import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'main.dart' show RestartWidget;
import 'operator_mode_store.dart';

/// Nama package pustaka pihak ketiga yang jadi "tempat sembunyi" 2 saklar
/// rahasia Mode Operator — sengaja diletakkan di bawah teks lisensi asli
/// package ini (bukan langsung kelihatan di daftar Lisensi Open Source),
/// supaya tidak ketemu tanpa sengaja.
const _hiddenSwitchPackage = 'path_provider';

/// Layar daftar Lisensi Open Source versi sendiri (bukan showLicensePage()
/// bawaan Flutter) — dibuat manual dari LicenseRegistry supaya bisa disisipi
/// 2 saklar tersembunyi pada satu halaman detail lisensi tertentu. Isinya
/// tetap data lisensi asli semua package yang dipakai aplikasi ini, hanya
/// cara menampilkannya yang dibuat sendiri.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  late final Future<Map<String, List<LicenseParagraph>>> _future = _loadLicensesByPackage();

  Future<Map<String, List<LicenseParagraph>>> _loadLicensesByPackage() async {
    final map = <String, List<LicenseParagraph>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        map.putIfAbsent(package, () => []).addAll(entry.paragraphs);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lisensi Open Source')),
      body: FutureBuilder<Map<String, List<LicenseParagraph>>>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final packages = data.keys.toList()..sort();
          return ListView.builder(
            itemCount: packages.length,
            itemBuilder: (context, index) {
              final name = packages[index];
              return ListTile(
                title: Text(name),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _PackageLicenseScreen(packageName: name, paragraphs: data[name]!),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PackageLicenseScreen extends StatefulWidget {
  final String packageName;
  final List<LicenseParagraph> paragraphs;

  const _PackageLicenseScreen({required this.packageName, required this.paragraphs});

  @override
  State<_PackageLicenseScreen> createState() => _PackageLicenseScreenState();
}

class _PackageLicenseScreenState extends State<_PackageLicenseScreen> {
  bool _switch1 = false;
  bool _switch2 = false;

  Future<void> _onSwitchChanged() async {
    if (!_switch1 || !_switch2) return;
    await OperatorModeStore.instance.enable();
    if (!mounted) return;
    RestartWidget.restartApp(context);
  }

  @override
  Widget build(BuildContext context) {
    final isHidden = widget.packageName == _hiddenSwitchPackage;
    return Scaffold(
      appBar: AppBar(title: Text(widget.packageName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final paragraph in widget.paragraphs)
            Padding(
              padding: EdgeInsets.only(left: paragraph.indent > 0 ? paragraph.indent * 16.0 : 0, bottom: 12),
              child: Text(
                paragraph.text,
                textAlign: paragraph.indent == LicenseParagraph.centeredIndent ? TextAlign.center : TextAlign.start,
              ),
            ),
          if (isHidden) ...[
            const SizedBox(height: 40),
            Opacity(
              opacity: 0.3,
              child: Column(
                children: [
                  Switch(
                    value: _switch1,
                    onChanged: (value) {
                      setState(() => _switch1 = value);
                      _onSwitchChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  Switch(
                    value: _switch2,
                    onChanged: (value) {
                      setState(() => _switch2 = value);
                      _onSwitchChanged();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
