import 'package:flutter/material.dart';

import '../staff_portal_client.dart';
import 'monitoring_form_fields.dart';
import 'monitoring_result_table.dart';

/// Kerangka bersama untuk 7 tab Monitoring Wilayah: mengelola state loading,
/// error handling seragam, badge wilayah, tombol submit "Tampilkan",
/// dan visualisasi hasil [MonitoringResultView].
class MonitoringTabScaffold extends StatefulWidget {
  final String reportTitle;
  final Future<MonitoringTableResult?> Function() onFetch;
  final List<Widget> Function(BuildContext context, bool loading) formBuilder;

  const MonitoringTabScaffold({
    super.key,
    required this.reportTitle,
    required this.onFetch,
    required this.formBuilder,
  });

  @override
  State<MonitoringTabScaffold> createState() => _MonitoringTabScaffoldState();
}

class _MonitoringTabScaffoldState extends State<MonitoringTabScaffold> {
  bool _loading = false;
  MonitoringTableResult? _result;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final res = await widget.onFetch();
      if (!mounted) return;
      if (res != null) {
        setState(() => _result = res);
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _result = MonitoringTableResult(
          errorMessage: 'Gagal memuat data: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WilayahBadge(),
          ...widget.formBuilder(context, _loading),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Text('Tampilkan'),
          ),
          MonitoringResultView(
            result: _result,
            loading: false,
            reportTitle: widget.reportTitle,
          ),
        ],
      ),
    );
  }
}
