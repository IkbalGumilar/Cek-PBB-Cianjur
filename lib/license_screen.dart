import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Layar daftar Lisensi Open Source (bukan showLicensePage() bawaan Flutter)
/// dibuat manual dari LicenseRegistry untuk menampilkan data lisensi asli
/// semua package yang dipakai aplikasi ini.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  late final Future<Map<String, List<LicenseParagraph>>> _future =
      _loadLicensesByPackage();

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
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
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
                    builder: (_) => _PackageLicenseScreen(
                      packageName: name,
                      paragraphs: data[name]!,
                    ),
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

class _PackageLicenseScreen extends StatelessWidget {
  final String packageName;
  final List<LicenseParagraph> paragraphs;

  const _PackageLicenseScreen({
    required this.packageName,
    required this.paragraphs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(packageName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final paragraph in paragraphs)
            Padding(
              padding: EdgeInsets.only(
                left: paragraph.indent > 0 ? paragraph.indent * 16.0 : 0,
                bottom: 12,
              ),
              child: Text(
                paragraph.text,
                textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                    ? TextAlign.center
                    : TextAlign.start,
              ),
            ),
        ],
      ),
    );
  }
}
