import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blok_batch_check_tracker.dart';
import 'blok_data_store.dart';
import 'nop_helper.dart';
import 'pbb_client.dart';
import 'result_screen.dart';
import 'tax_record.dart';
import 'unity_lerp_widgets.dart';

class BatchCheckScreen extends StatefulWidget {
  final List<TaxRecord> records;
  final String tahun;
  final PbbClient? client;
  final Duration pacingDelay;
  final int cooldownBatchSize;
  final Duration cooldownDuration;
  final bool autoStart;

  const BatchCheckScreen({
    super.key,
    required this.records,
    required this.tahun,
    this.client,
    this.pacingDelay = const Duration(milliseconds: 750),
    this.cooldownBatchSize = 50,
    this.cooldownDuration = const Duration(seconds: 3),
    this.autoStart = true,
  });

  @override
  State<BatchCheckScreen> createState() => _BatchCheckScreenState();
}

class _BatchCheckScreenState extends State<BatchCheckScreen> {
  late final PbbClient _client;
  final ScrollController _scrollController = ScrollController();

  int _currentIndex = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isCooldown = false;
  bool _isCompleted = false;
  String _statusMessage = 'Menyiapkan pengecekan...';

  TaxRecord? get _current =>
      _currentIndex < widget.records.length ? widget.records[_currentIndex] : null;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? PbbClient();
    if (widget.autoStart && widget.records.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runBatch();
      });
    }
  }

  @override
  void dispose() {
    _isRunning = false;
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    const itemExtent = 64.0;
    final targetOffset = (_currentIndex * itemExtent) - 100.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxScroll);
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _runBatch() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _isPaused = false;
    });

    while (_currentIndex < widget.records.length && _isRunning) {
      if (_isPaused) break;

      final record = widget.records[_currentIndex];
      if (mounted) {
        setState(() {
          _statusMessage = 'Sedang memeriksa NOP ${record.nop}...';
        });
        _scrollToCurrent();
      }

      // Jeda aman per NOP (750 ms) untuk mencegah beban berlebih ke server
      if (widget.pacingDelay > Duration.zero) {
        await Future<void>.delayed(widget.pacingDelay);
      }
      if (!_isRunning || _isPaused || !mounted) break;

      try {
        final result = await _client.checkStatusViaDocument(
          record.nop,
          tahun: widget.tahun,
        );
        if (!mounted) return;
        record.status = result.status;
        record.rawText = result.rawText;
        if (result.namaWajibPajak != null &&
            result.namaWajibPajak!.trim().isNotEmpty) {
          record.namaWajibPajak = result.namaWajibPajak;
        }

        if (record.isPaid) {
          await BlokDataStore.instance.updateStatusBayarFromCheck(
            nop: record.nop,
            tahun: widget.tahun,
            result: result,
          );
        }
        await BlokBatchCheckTracker.instance.recordChecked(record.nop);
      } catch (e) {
        if (!mounted) return;
        record.status = 'Gagal Cek';
        record.rawText = e.toString();
        await BlokBatchCheckTracker.instance.recordChecked(record.nop);
      }

      if (!mounted) return;
      setState(() {
        _currentIndex++;
      });

      // Cooldown berkala (misal setiap 50 NOP jeda 3 detik) agar server Bapenda tetap aman
      if (widget.cooldownBatchSize > 0 &&
          _currentIndex > 0 &&
          _currentIndex % widget.cooldownBatchSize == 0 &&
          _currentIndex < widget.records.length &&
          _isRunning &&
          !_isPaused) {
        final totalSecs = widget.cooldownDuration.inSeconds;
        if (totalSecs > 0) {
          for (int s = totalSecs; s > 0; s--) {
            if (!_isRunning || _isPaused || !mounted) break;
            setState(() {
              _isCooldown = true;
              _statusMessage = 'Cooldown $s detik...';
            });
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        } else if (widget.cooldownDuration > Duration.zero) {
          await Future<void>.delayed(widget.cooldownDuration);
        }
        if (mounted) {
          setState(() {
            _isCooldown = false;
          });
        }
      }
    }

    if (!mounted) return;
    if (_currentIndex >= widget.records.length) {
      setState(() {
        _isRunning = false;
        _isCompleted = true;
        _statusMessage = 'Semua NOP selesai diperiksa.';
      });
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) _goToResult();
    } else {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _pause() {
    setState(() {
      _isPaused = true;
      _isRunning = false;
      _isCooldown = false;
      _statusMessage = 'Pengecekan dijeda.';
    });
  }

  void _resume() {
    _runBatch();
  }

  void _skipCurrent() {
    if (_currentIndex < widget.records.length) {
      widget.records[_currentIndex].status = 'Dilewati';
      setState(() {
        _currentIndex++;
      });
      if (_isRunning && !_isPaused) {
        _runBatch();
      }
    }
  }

  void _goToResult() {
    _isRunning = false;
    _isPaused = false;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(records: widget.records),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (!_isRunning) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hentikan Pengecekan Massal?'),
        content: const Text(
          'Pengecekan sedang berjalan. Data yang sudah dicek tetap tersimpan di database lokal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjutkan Cek'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hentikan & Keluar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _isRunning = false;
      _isPaused = false;
      return true;
    }
    return false;
  }

  Widget _buildCounterBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: LerpAnimatedCounter(
        value: count,
        formatter: (v) => '$label: ${v.round()}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme scheme) {
    final s = status.toLowerCase();
    if (s.contains('sudah') || s.contains('lunas')) return Colors.green;
    if (s.contains('belum')) return Colors.orange;
    if (s.contains('blacklist')) return Colors.deepPurple;
    if (s.contains('lewat')) return Colors.grey;
    if (s.contains('gagal') || s.contains('error')) return Colors.red;
    return scheme.outline;
  }

  IconData _statusIcon(String status) {
    final s = status.toLowerCase();
    if (s.contains('sudah') || s.contains('lunas')) return Icons.check_circle;
    if (s.contains('belum')) return Icons.schedule;
    if (s.contains('blacklist')) return Icons.block;
    if (s.contains('lewat')) return Icons.skip_next;
    if (s.contains('gagal') || s.contains('error')) return Icons.error_outline;
    return Icons.radio_button_unchecked;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.records.length;
    final sudahBayarCount = widget.records.where((r) => r.isPaid).length;
    final belumBayarCount = widget.records
        .where((r) =>
            r.isChecked &&
            !r.isPaid &&
            r.status != 'Blacklist' &&
            r.status != 'Dilewati' &&
            r.status != 'Gagal Cek')
        .length;
    final blacklistCount =
        widget.records.where((r) => r.status.contains('Blacklist')).length;
    final gagalCount =
        widget.records.where((r) => r.status.contains('Gagal Cek')).length;
    final dilewatiCount =
        widget.records.where((r) => r.status == 'Dilewati').length;
    final sisaCount = (total - _currentIndex).clamp(0, total);
    final scheme = Theme.of(context).colorScheme;

    final progressVal = total == 0 ? 0.0 : (_currentIndex / total).clamp(0.0, 1.0);

    return PopScope(
      canPop: !_isRunning,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Cek Massal (${_currentIndex.clamp(0, total)}/$total)',
          ),
          actions: [
            if (_currentIndex > 0)
              TextButton.icon(
                onPressed: _goToResult,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Hasil'),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  // Progress and Counters Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LerpAnimatedProgress(
                          value: progressVal,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildCounterBadge(
                              label: 'Sudah',
                              count: sudahBayarCount,
                              color: Colors.green,
                            ),
                            _buildCounterBadge(
                              label: 'Belum',
                              count: belumBayarCount,
                              color: Colors.orange,
                            ),
                            if (blacklistCount > 0)
                              _buildCounterBadge(
                                label: 'Blacklist',
                                count: blacklistCount,
                                color: Colors.deepPurple,
                              ),
                            if (gagalCount > 0)
                              _buildCounterBadge(
                                label: 'Gagal',
                                count: gagalCount,
                                color: Colors.red,
                              ),
                            if (dilewatiCount > 0)
                              _buildCounterBadge(
                                label: 'Lewat',
                                count: dilewatiCount,
                                color: Colors.grey,
                              ),
                            _buildCounterBadge(
                              label: 'Sisa',
                              count: sisaCount,
                              color: scheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Active Item & Controls Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      color: scheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (_isCooldown)
                                  const Icon(Icons.hourglass_top,
                                      size: 18, color: Colors.cyan)
                                else if (_isRunning)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else if (_isPaused)
                                  const Icon(Icons.pause_circle_outline,
                                      size: 18, color: Colors.orange)
                                else if (_isCompleted)
                                  const Icon(Icons.check_circle_outline,
                                      size: 18, color: Colors.green)
                                else
                                  const Icon(Icons.pending_outlined,
                                      size: 18, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _statusMessage,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: _isCooldown
                                              ? Colors.cyan.shade700
                                              : scheme.onSurfaceVariant,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (_current != null) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _current!.nop,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.05,
                                              ),
                                        ),
                                        if (_current!.namaWajibPajak != null &&
                                            _current!
                                                .namaWajibPajak!.isNotEmpty)
                                          Text(
                                            _current!.namaWajibPajak!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (nopBlok(_current!.nop).isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Blok ${nopBlok(_current!.nop)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            // Action controls
                            Row(
                              children: [
                                if (_isRunning) ...[
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: _pause,
                                      icon: const Icon(Icons.pause, size: 18),
                                      label: const Text('Jeda'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _goToResult,
                                      icon: const Icon(Icons.stop_circle_outlined,
                                          size: 18),
                                      label: const Text('Hentikan'),
                                    ),
                                  ),
                                ] else if (!_isCompleted) ...[
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _resume,
                                      icon: const Icon(Icons.play_arrow,
                                          size: 18),
                                      label: const Text('Lanjutkan'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _skipCurrent,
                                    child: const Text('Lewati'),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.outlined(
                                    tooltip: 'Lihat Hasil Sementara',
                                    onPressed: _goToResult,
                                    icon: const Icon(Icons.fact_check_outlined,
                                        size: 18),
                                  ),
                                ] else ...[
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _goToResult,
                                      icon: const Icon(Icons.check_circle,
                                          size: 18),
                                      label: const Text('Buka Hasil Pengecekan'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Live Records List
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Daftar NOP (${widget.records.length})',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'Tahun Pajak: ${widget.tahun}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),

                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      itemCount: widget.records.length,
                      itemBuilder: (context, index) {
                        final item = widget.records[index];
                        final isCurrent = index == _currentIndex && _isRunning;
                        final color = _statusColor(item.status, scheme);
                        final icon = _statusIcon(item.status);

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? scheme.primaryContainer.withValues(alpha: 0.3)
                                : scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent
                                  ? scheme.primary
                                  : scheme.outlineVariant.withValues(alpha: 0.3),
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isCurrent ? Icons.sync : icon,
                              color: isCurrent ? scheme.primary : color,
                              size: 20,
                            ),
                            title: Text(
                              item.nop,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: item.namaWajibPajak != null &&
                                    item.namaWajibPajak!.isNotEmpty
                                ? Text(
                                    item.namaWajibPajak!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                item.status.isEmpty
                                    ? (isCurrent ? 'Memeriksa...' : 'Antrean')
                                    : item.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
