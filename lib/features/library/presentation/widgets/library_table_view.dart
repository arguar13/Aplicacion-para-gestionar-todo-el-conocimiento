import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La biblioteca como una tabla, al estilo de una base de datos de Notion:
/// una fila por elemento, una columna por propiedad, y encabezados que
/// ordenan al tocarlos.
///
/// Solo dos columnas son realmente ordenables —Título y Capturado—, porque
/// son las únicas que tienen un [LibrarySort] que les corresponde. Tipo,
/// Espacio, Etiquetas y Estado son propiedades reales de cada elemento,
/// pero no una forma de ordenar que el repositorio sepa resolver, así que
/// se muestran sin flecha de orden en vez de fingir un ordenamiento que no
/// existe.
class LibraryTableView extends ConsumerWidget {
  const LibraryTableView({required this.items, super.key});

  final List<KnowledgeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(libraryQueryNotifierProvider);
    final notifier = ref.read(libraryQueryNotifierProvider.notifier);
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final spaceNames = {for (final s in spaces) s.id: s.name};
    final locale = Localizations.localeOf(context).toString();
    final dateFormat = DateFormat.yMMMd(locale);

    // `sortColumnIndex`/`sortAscending` de `DataTable` solo tienen sentido
    // para las dos columnas que de verdad se pueden ordenar: en cualquier
    // otra combinación de `sortBy` —relevancia de una búsqueda, por
    // ejemplo— ningún encabezado se marca como activo, en vez de mentir
    // marcando uno al azar.
    final sortColumnIndex = switch (query.sortBy) {
      LibrarySort.title => 0,
      LibrarySort.capturedAt => 5,
      _ => null,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        child: DataTable(
          sortColumnIndex: sortColumnIndex,
          sortAscending: !query.descending,
          columns: [
            DataColumn(
              label: Text(l10n.libraryColumnTitle),
              onSort: (_, ascending) =>
                  notifier.sortBy(LibrarySort.title, descending: !ascending),
            ),
            DataColumn(label: Text(l10n.libraryColumnType)),
            DataColumn(label: Text(l10n.libraryColumnSpace)),
            DataColumn(label: Text(l10n.libraryColumnTags)),
            DataColumn(label: Text(l10n.libraryColumnStatus)),
            DataColumn(
              label: Text(l10n.libraryColumnCaptured),
              onSort: (_, ascending) => notifier.sortBy(
                LibrarySort.capturedAt,
                descending: !ascending,
              ),
            ),
          ],
          rows: [
            for (final item in items)
              DataRow(
                onSelectChanged: (_) =>
                    context.push('${RoutePaths.library}/${item.id}'),
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(item.title, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.source.kind.icon, size: 16),
                        const SizedBox(width: 6),
                        Text(item.source.kind.label(l10n)),
                      ],
                    ),
                  ),
                  DataCell(Text(spaceNames[item.spaceId] ?? '—')),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        item.tags.isEmpty
                            ? '—'
                            : item.tags.map((t) => t.name).join(', '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(item.processingState.label(l10n) ?? '—')),
                  DataCell(Text(dateFormat.format(item.source.capturedAt))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
