import 'package:flutter/material.dart';

import 'spreadsheet_parser.dart';

class SpreadsheetDataView extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final bool isDkhp;
  final SpreadsheetTable? table;
  final List<List<String>> pageRows;
  final int startIndex;
  final int totalRows;
  final String searchQuery;
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final VoidCallback onRetry;
  final void Function(int rowIndex, List<String> rowValues) onRowSelected;

  const SpreadsheetDataView({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.isDkhp,
    required this.table,
    required this.pageRows,
    required this.startIndex,
    required this.totalRows,
    required this.searchQuery,
    required this.horizontalController,
    required this.verticalController,
    required this.onRetry,
    required this.onRowSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Memuat dan memvalidasi lembar kerja...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      final isBiometricError =
          isDkhp && errorMessage!.toLowerCase().contains('sidik jari');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBiometricError
                    ? Icons.fingerprint_rounded
                    : Icons.error_outline_rounded,
                size: 54,
                color: isBiometricError ? Colors.blue : Colors.red,
              ),
              const SizedBox(height: 14),
              Text(
                isBiometricError
                    ? 'Autentikasi Diperlukan'
                    : 'Tidak Dapat Membaca Berkas',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: Icon(
                  isBiometricError
                      ? Icons.fingerprint_rounded
                      : Icons.refresh_rounded,
                  size: 18,
                ),
                label: Text(
                  isBiometricError ? 'Pindai Sidik Jari' : 'Coba Lagi',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (table == null || totalRows == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 44, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              searchQuery.isNotEmpty
                  ? 'Tidak ada baris data yang cocok.'
                  : 'Lembar kerja ini tidak memiliki data.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final currentTable = table!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scrollbar(
      controller: verticalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: verticalController,
        scrollDirection: Axis.vertical,
        child: Scrollbar(
          controller: horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              headingRowHeight: 40,
              dataRowMinHeight: 38,
              dataRowMaxHeight: 48,
              columnSpacing: 18,
              horizontalMargin: 12,
              headingRowColor: WidgetStatePropertyAll(
                theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.7,
                ),
              ),
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                  width: 1,
                ),
                verticalInside: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              columns: [
                const DataColumn(
                  label: Text(
                    '#',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                ...currentTable.headers.map(
                  (header) => DataColumn(
                    label: Text(
                      header,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
              rows: List<DataRow>.generate(pageRows.length, (rowIndex) {
                final globalRowIndex = startIndex + rowIndex;
                final rowValues = pageRows[rowIndex];
                final isEven = rowIndex % 2 == 0;

                return DataRow(
                  color: WidgetStatePropertyAll(
                    isEven
                        ? (isDark
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.black.withValues(alpha: 0.015))
                        : Colors.transparent,
                  ),
                  onSelectChanged: (_) =>
                      onRowSelected(globalRowIndex, rowValues),
                  cells: [
                    DataCell(
                      Text(
                        '${globalRowIndex + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    ...List<DataCell>.generate(currentTable.headers.length, (
                      columnIndex,
                    ) {
                      final value = columnIndex < rowValues.length
                          ? rowValues[columnIndex]
                          : '';
                      final isNumeric = RegExp(r'^[0-9]+$').hasMatch(value);
                      return DataCell(
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: isNumeric ? 'monospace' : null,
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class SpreadsheetPaginationBar extends StatelessWidget {
  final int rowsPerPage;
  final int totalPages;
  final int effectivePage;
  final int totalRows;
  final int startIndex;
  final int endIndex;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const SpreadsheetPaginationBar({
    super.key,
    required this.rowsPerPage,
    required this.totalPages,
    required this.effectivePage,
    required this.totalRows,
    required this.startIndex,
    required this.endIndex,
    required this.onRowsPerPageChanged,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${startIndex + 1}-$endIndex dari $totalRows',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const Spacer(),
          DropdownButton<int>(
            value: rowsPerPage,
            underline: const SizedBox.shrink(),
            isDense: true,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
            items: const [
              DropdownMenuItem(value: 25, child: Text('25 baris')),
              DropdownMenuItem(value: 50, child: Text('50 baris')),
              DropdownMenuItem(value: 100, child: Text('100 baris')),
              DropdownMenuItem(value: 200, child: Text('200 baris')),
            ],
            onChanged: (value) {
              if (value != null) onRowsPerPageChanged(value);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: effectivePage > 1 ? onPrevious : null,
          ),
          Text(
            '$effectivePage / $totalPages',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: effectivePage < totalPages ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class SpreadsheetImportBanner extends StatelessWidget {
  final SpreadsheetTable? table;
  final VoidCallback onImport;

  const SpreadsheetImportBanner({
    super.key,
    required this.table,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Paket Data DHKP Siap Dipasang',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${table?.rowCount ?? 0} data tercatat dalam berkas cadangan ini.',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.file_download_rounded, size: 18),
            label: const Text('Impor ke Buku Catatan'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}
