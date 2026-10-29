import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_sort.dart';
import 'package:sinapsis/features/creations/data_table/presentation/data_table_state.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Ordenar»: las columnas, con el ✓ en la elegida —o en «Orden original»—,
/// y hacia dónde, con los segmentados de siempre. Cada toque vale en el
/// acto: la tabla de atrás se reordena mientras la hoja sigue abierta.
Future<void> showTableSortSheet(
  BuildContext context, {
  required String creationId,
  required StudyTable table,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => TableSortSheet(creationId: creationId, table: table),
);

class TableSortSheet extends ConsumerWidget {
  const TableSortSheet({
    required this.creationId,
    required this.table,
    super.key,
  });

  final String creationId;
  final StudyTable table;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = dataTableAccent.of(context);
    final sort = ref.watch(dataTableSortProvider(creationId));
    final notifier = ref.read(dataTableSortProvider(creationId).notifier);

    Widget option(
      String key,
      String label, {
      required bool chosen,
      required VoidCallback onTap,
    }) => ListTile(
      key: Key(key),
      title: Text(label),
      selected: chosen,
      selectedColor: theme.colorScheme.onSurface,
      trailing: chosen ? Icon(Icons.check_rounded, color: accent) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.f43TableSortBy,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              CreationCloseButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          option(
            'data-table-sort-original',
            l10n.f43TableSortOriginal,
            chosen: sort == null,
            onTap: () => notifier.state = null,
          ),
          for (final (index, column) in table.columns.indexed)
            option(
              'data-table-sort-column-$index',
              column.name,
              chosen: sort?.column == index,
              onTap: () => notifier.state = TableSort(
                index,
                ascending: sort?.ascending ?? true,
              ),
            ),
          if (sort != null) ...[
            const SizedBox(height: 16),
            CreationSegmented<bool>(
              keyPrefix: 'data-table-direction',
              segments: [
                CreationSegment(
                  value: true,
                  id: 'asc',
                  label: l10n.f43TableAscending,
                ),
                CreationSegment(
                  value: false,
                  id: 'desc',
                  label: l10n.f43TableDescending,
                ),
              ],
              selected: sort.ascending,
              onChanged: (ascending) =>
                  notifier.state = TableSort(sort.column, ascending: ascending),
            ),
          ],
        ],
      ),
    );
  }
}

/// Una celda entera: su columna, de qué fila es y el valor completo, para
/// leerlo y copiarlo.
Future<void> showTableCellSheet(
  BuildContext context, {
  required String column,
  required String value,
  required int rowNumber,
  String? rowLabel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => TableCellSheet(
    column: column,
    value: value,
    rowNumber: rowNumber,
    rowLabel: rowLabel,
  ),
);

class TableCellSheet extends StatelessWidget {
  const TableCellSheet({
    required this.column,
    required this.value,
    required this.rowNumber,
    this.rowLabel,
    super.key,
  });

  final String column;
  final String value;
  final int rowNumber;

  /// Lo que identifica a la fila —el valor de su primera columna—, si la
  /// celda es de otra.
  final String? rowLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = rowLabel;
    return SingleChildScrollView(
      key: const Key('data-table-cell-sheet'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label == null || label.isEmpty
                          ? l10n.f43TableRow(rowNumber)
                          : '${l10n.f43TableRow(rowNumber)} · $label',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      header: true,
                      child: Text(column, style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CreationCloseButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(value, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const Key('data-table-cell-copy'),
              onPressed: () => unawaited(_copy(context)),
              icon: const Icon(Icons.copy_rounded),
              label: Text(l10n.f43TableCellCopy),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = AppLocalizations.of(context)!.f43TableCellCopied;
    await Clipboard.setData(ClipboardData(text: value));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }
}
