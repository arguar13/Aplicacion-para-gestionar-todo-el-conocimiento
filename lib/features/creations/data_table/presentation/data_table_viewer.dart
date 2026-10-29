import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverLayoutDimensions;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table_json.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_export.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_sort.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_values.dart';
import 'package:sinapsis/features/creations/data_table/presentation/data_table_geometry.dart';
import 'package:sinapsis/features/creations/data_table/presentation/data_table_sheets.dart';
import 'package:sinapsis/features/creations/data_table/presentation/data_table_state.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/presentation/creation_actions.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El visor de una tabla de datos (F43, punto 5 del plan):
///
/// - **la primera columna fija** y las demás con desplazamiento lateral; los
///   **encabezados siempre a la vista** al bajar;
/// - las filas alternan dos tonos del tema, para seguirlas con la vista;
/// - **tocar una celda que no entra** la abre entera, para leerla y
///   copiarla;
/// - **ordenar por columna**: tocar un encabezado ordena por él —otra vez, al
///   revés—, o desde «Ordenar», con el ✓ en lo elegido; los números se
///   ordenan como números, las fechas como fechas y el texto como en un
///   diccionario;
/// - «Copiar la tabla» y «Exportar a CSV» están en la barra de arriba.
class DataTableViewer extends ConsumerStatefulWidget {
  const DataTableViewer({required this.creation, super.key});

  final StudyCreation creation;

  @override
  ConsumerState<DataTableViewer> createState() => _DataTableViewerState();
}

class _DataTableViewerState extends ConsumerState<DataTableViewer> {
  late StudyTable _table = StudyTableJson.decode(
    widget.creation.decodedContent,
  );

  final _headScroll = ScrollController();
  final _bodyScroll = ScrollController();
  final _fixedRows = ScrollController();
  final _bodyRows = ScrollController();
  late final _ScrollLink _horizontal;
  late final _ScrollLink _vertical;

  /// Si las columnas se corrieron: la fija lleva una sombra al costado.
  var _shifted = false;

  DataTableStyles? _styles;
  double? _available;
  DataTableGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    _horizontal = _ScrollLink(_headScroll, _bodyScroll);
    _vertical = _ScrollLink(_fixedRows, _bodyRows);
    _bodyScroll.addListener(_onHorizontal);
  }

  @override
  void didUpdateWidget(DataTableViewer old) {
    super.didUpdateWidget(old);
    if (old.creation.content != widget.creation.content) {
      _table = StudyTableJson.decode(widget.creation.decodedContent);
      _geometry = null;
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _bodyScroll.removeListener(_onHorizontal);
    for (final controller in [
      _headScroll,
      _bodyScroll,
      _fixedRows,
      _bodyRows,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onHorizontal() {
    final shifted = _bodyScroll.hasClients && _bodyScroll.offset > 0.5;
    if (shifted != _shifted) setState(() => _shifted = shifted);
  }

  void _sortBy(int column) {
    final notifier = ref.read(
      dataTableSortProvider(widget.creation.id).notifier,
    );
    notifier.state = TableSort.toggled(notifier.state, column);
  }

  void _openCell(int row, int column) {
    final values = _table.rows[row];
    unawaited(
      showTableCellSheet(
        context,
        column: _table.columns[column].name,
        value: values[column],
        rowLabel: column == 0 ? null : values.first,
        rowNumber: row + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final table = _table;
    if (table.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.f43TableEmpty,
            key: const Key('data-table-empty'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }
    final sort = ref.watch(dataTableSortProvider(widget.creation.id));
    final order = tableRowOrder(
      table,
      sort,
      TableCollator(widget.creation.languageCode),
    );
    final styles = DataTableStyles.of(context);
    final accent = dataTableAccent.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryBar(
          table: table,
          sort: sort,
          accent: accent,
          onSort: () => unawaited(
            showTableSortSheet(
              context,
              creationId: widget.creation.id,
              table: table,
            ),
          ),
          onClear: () =>
              ref
                      .read(dataTableSortProvider(widget.creation.id).notifier)
                      .state =
                  null,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final available = constraints.maxWidth;
                    if (_geometry == null ||
                        styles != _styles ||
                        available != _available) {
                      _styles = styles;
                      _available = available;
                      _geometry = DataTableGeometry.measure(
                        table,
                        styles,
                        available: available,
                      );
                    }
                    return _grid(
                      context,
                      table,
                      _geometry!,
                      styles,
                      order,
                      sort,
                      accent,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    StudyTable table,
    DataTableGeometry geometry,
    DataTableStyles styles,
    List<int> order,
    TableSort? sort,
    Color accent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final divider = scheme.outlineVariant.withValues(alpha: 0.7);
    final firstWidth = geometry.firstWidth;
    final edge = BoxDecoration(
      border: Border(right: BorderSide(color: divider)),
      boxShadow: _shifted
          ? [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(2, 0),
              ),
            ]
          : null,
    );

    Widget header(int column) => _HeaderCell(
      key: ValueKey('data-table-header-$column'),
      column: table.columns[column],
      width: geometry.widths[column],
      height: geometry.headerHeight,
      style: styles.header,
      sort: sort?.column == column ? sort : null,
      accent: accent,
      onTap: () => _sortBy(column),
    );

    Widget cell(int position, int column) {
      final row = order[position];
      final value = table.rows[row][column];
      final cut = geometry.truncated[row][column];
      return _Cell(
        key: ValueKey('data-table-cell-$row-$column'),
        value: value,
        column: table.columns[column],
        width: geometry.widths[column],
        height: geometry.heights[row],
        style: styles.cellAt(column, numeric: table.columns[column].isNumeric),
        stripe: position.isOdd,
        truncated: cut,
        onTap: cut ? () => _openCell(row, column) : null,
      );
    }

    double extent(int position, SliverLayoutDimensions _) =>
        geometry.heights[order[position]];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Los encabezados, siempre arriba.
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border(bottom: BorderSide(color: divider)),
          ),
          child: Row(
            children: [
              DecoratedBox(decoration: edge, child: header(0)),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('data-table-head-scroll'),
                  controller: _headScroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var c = 1; c < table.columns.length; c++) header(c),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // La primera columna, fija.
              DecoratedBox(
                decoration: edge,
                child: SizedBox(
                  width: firstWidth,
                  child: ListView.builder(
                    key: const Key('data-table-fixed'),
                    controller: _fixedRows,
                    itemCount: order.length,
                    itemExtentBuilder: extent,
                    itemBuilder: (context, position) => cell(position, 0),
                  ),
                ),
              ),
              // Las demás, que se desplazan de costado.
              Expanded(
                child: Scrollbar(
                  controller: _bodyScroll,
                  notificationPredicate: (n) => n.depth == 0,
                  child: SingleChildScrollView(
                    key: const Key('data-table-body-scroll'),
                    controller: _bodyScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: geometry.restWidth,
                      child: ListView.builder(
                        key: const Key('data-table-body'),
                        controller: _bodyRows,
                        itemCount: order.length,
                        itemExtentBuilder: extent,
                        itemBuilder: (context, position) => Row(
                          children: [
                            for (var c = 1; c < table.columns.length; c++)
                              cell(position, c),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cuántas filas y columnas tiene, cómo está ordenada —con su ✕ para volver
/// al orden de la IA— y «Ordenar».
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.table,
    required this.sort,
    required this.accent,
    required this.onSort,
    required this.onClear,
  });

  final StudyTable table;
  final TableSort? sort;
  final Color accent;
  final VoidCallback onSort;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = sort;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            l10n.f43TableSize(table.rows.length, table.columns.length),
            key: const Key('data-table-size'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (sorted != null)
                InputChip(
                  key: const Key('data-table-sorted'),
                  avatar: Icon(
                    sorted.ascending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: accent,
                  ),
                  label: Text(
                    table.columns[sorted.column].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  tooltip: sorted.ascending
                      ? l10n.f43TableSortedAsc(
                          table.columns[sorted.column].name,
                        )
                      : l10n.f43TableSortedDesc(
                          table.columns[sorted.column].name,
                        ),
                  shape: const StadiumBorder(),
                  onDeleted: onClear,
                  deleteButtonTooltipMessage: l10n.f43TableSortOriginal,
                ),
              TextButton.icon(
                key: const Key('data-table-sort'),
                onPressed: onSort,
                icon: const Icon(Icons.sort_rounded),
                label: Text(l10n.f43TableSort),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.width,
    required this.height,
    required this.style,
    required this.sort,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final TableColumn column;
  final double width;
  final double height;
  final TextStyle style;

  /// Cómo ordena esta columna, si es la elegida.
  final TableSort? sort;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final sorted = sort;
    final numeric = column.isNumeric;
    return Semantics(
      button: true,
      label: sorted == null
          ? column.name
          : sorted.ascending
          ? l10n.f43TableSortedAsc(column.name)
          : l10n.f43TableSortedDesc(column.name),
      hint: l10n.f43TableHeaderHint,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DataTableGeometry.horizontalPadding,
            ),
            child: Row(
              mainAxisAlignment: numeric
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    column.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: numeric ? TextAlign.end : TextAlign.start,
                    style: style.copyWith(color: scheme.onSurface),
                  ),
                ),
                SizedBox(
                  width: DataTableGeometry.sortSpace,
                  child: Icon(
                    sorted == null
                        ? Icons.unfold_more_rounded
                        : sorted.ascending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: sorted == null
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                        : accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.column,
    required this.width,
    required this.height,
    required this.style,
    required this.stripe,
    required this.truncated,
    required this.onTap,
    super.key,
  });

  final String value;
  final TableColumn column;
  final double width;
  final double height;
  final TextStyle style;

  /// Si es una fila de las del tono alterno.
  final bool stripe;
  final bool truncated;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final numeric = column.isNumeric;
    final content = Container(
      width: width,
      height: height,
      color: stripe
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(
        horizontal: DataTableGeometry.horizontalPadding,
        vertical: DataTableGeometry.verticalPadding,
      ),
      alignment: numeric
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Text(
        value,
        maxLines: DataTableGeometry.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: numeric ? TextAlign.end : TextAlign.start,
        style: style.copyWith(color: scheme.onSurface),
      ),
    );
    final tap = onTap;
    return Semantics(
      container: true,
      label: '${column.name}: $value',
      hint: truncated ? l10n.f43TableCellHint : null,
      button: tap != null,
      excludeSemantics: true,
      child: tap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: tap, child: content),
            ),
    );
  }
}

/// Mantiene dos desplazamientos iguales: el de los encabezados con el de las
/// filas, y el de la columna fija con el de las demás. Se mueva cuál se
/// mueva, el otro lo sigue.
class _ScrollLink {
  _ScrollLink(this.a, this.b) {
    a.addListener(_fromA);
    b.addListener(_fromB);
  }

  final ScrollController a;
  final ScrollController b;
  var _busy = false;

  void _fromA() => _copy(a, b);
  void _fromB() => _copy(b, a);

  void _copy(ScrollController from, ScrollController to) {
    if (_busy || !from.hasClients || !to.hasClients) return;
    final target = from.offset.clamp(0.0, to.position.maxScrollExtent);
    if ((to.offset - target).abs() < 0.01) return;
    _busy = true;
    to.jumpTo(target);
    _busy = false;
  }

  void dispose() {
    a.removeListener(_fromA);
    b.removeListener(_fromB);
  }
}

/// «Copiar la tabla»: al portapapeles como texto separado por tabulaciones,
/// en el orden que se ve —se pega tal cual en una planilla—.
Future<void> copyDataTable(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final table = StudyTableJson.decode(creation.decodedContent);
  if (table.isEmpty) return;
  await Clipboard.setData(
    ClipboardData(
      text: tableToTsv(table, order: dataTableOrder(ref, creation, table)),
    ),
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.f43TableCopied)));
}

/// Los botones de la tabla en la barra del visor: copiarla y exportarla a
/// CSV.
List<Widget> dataTableViewerActions(
  BuildContext context,
  StudyCreation creation,
) => [
  Consumer(
    builder: (context, ref, _) {
      final l10n = AppLocalizations.of(context)!;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('data-table-copy'),
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: l10n.f43TableCopy,
            onPressed: () => unawaited(copyDataTable(context, ref, creation)),
          ),
          IconButton(
            key: const Key('data-table-csv'),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: l10n.f43TableExportCsv,
            onPressed: () => unawaited(
              runCreationAction(
                context,
                ref,
                creation,
                CreationAction.download,
              ),
            ),
          ),
        ],
      );
    },
  ),
];
