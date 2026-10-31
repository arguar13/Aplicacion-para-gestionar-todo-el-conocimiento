import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La grilla de las once tarjetas de crear (F43, punto 2 del plan), con el
/// estilo del Studio de NotebookLM: fondo apenas más claro que la pantalla,
/// bordes muy redondeados, el ícono de color propio de cada una, su nombre y
/// el lápiz de personalizar.
///
/// - **Las tres de extraer** van juntas en la primera fila, más compactas.
/// - **Las otras ocho**, de a dos en un teléfono —**Tabla de datos** con el
///   **Podcast** de F47 al lado—, de a tres o cuatro en una pantalla ancha.
/// - **Con letra grande** cada tarjeta pide más ancho: si no entran, van menos
///   por fila, nunca cortadas.
class CreationKindGrid extends ConsumerWidget {
  const CreationKindGrid({required this.onOpen, super.key});

  /// Se tocó una tarjeta: abre su hoja (decisión C).
  final ValueChanged<StudyCreationKind> onOpen;

  static const _gap = 10.0;

  /// El ancho mínimo de una tarjeta de extraer y de una de las otras, con la
  /// letra de siempre; crece con la letra.
  static const _minCompact = 96.0;
  static const _minRegular = 150.0;

  /// Cuántas van por fila en [width], de a lo sumo [max], si cada una pide
  /// [min] de ancho.
  static int columnsFor(double width, double min, int max) =>
      math.max(1, math.min(max, ((width + _gap) / (min + _gap)).floor()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(creationKindRegistryProvider);
    final scaler = MediaQuery.textScalerOf(context);
    final extract = [
      for (final spec in registry.all)
        if (spec.kind.isLiveView) spec,
    ];
    final rest = [
      for (final spec in registry.all)
        if (!spec.kind.isLiveView) spec,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 900
            ? 4
            : width >= 600
            ? 3
            : 2;
        final extractColumns = columnsFor(
          width,
          scaler.scale(_minCompact),
          extract.length,
        );
        final columns = columnsFor(width, scaler.scale(_minRegular), wide);
        return Column(
          key: const Key('creation-kind-grid'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._rows(extract, extractColumns, compact: true),
            ..._rows(rest, columns, compact: false),
          ],
        );
      },
    );
  }

  List<Widget> _rows(
    List<CreationKindSpec> specs,
    int columns, {
    required bool compact,
  }) {
    final rows = <Widget>[];
    for (var start = 0; start < specs.length; start += columns) {
      final chunk = specs.sublist(
        start,
        math.min(start + columns, specs.length),
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          // Las de una fila, todas de la misma altura: la del nombre más
          // largo.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: i < chunk.length
                        ? CreationKindTile(
                            spec: chunk[i],
                            compact: compact,
                            onTap: () => onOpen(chunk[i].kind),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return rows;
  }
}

/// Una tarjeta de crear: el ícono con su color, el nombre y el lápiz.
class CreationKindTile extends StatelessWidget {
  const CreationKindTile({
    required this.spec,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final CreationKindSpec spec;
  final VoidCallback onTap;

  /// Las de extraer: el ícono arriba, «Extraer» chico y el nombre.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = spec.accent.of(context);
    final label = spec.label(l10n);
    final pencil = Icon(
      Icons.edit_outlined,
      size: 18,
      color: scheme.onSurfaceVariant,
    );
    final name = Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );

    return Semantics(
      button: true,
      label: _fullName(l10n),
      hint: l10n.f43StudioTileCustomize,
      // Lo de adentro se lee como uno solo: el toque va acá, para que el
      // lector de pantalla también la abra.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('creation-kind-${spec.kind.storageKey}'),
          onTap: onTap,
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(14, 14, 10, 14)
                : const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(spec.iconData, color: accent, size: 24),
                          const Spacer(),
                          pencil,
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.f43StudioTileExtract,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      name,
                    ],
                  )
                : Row(
                    children: [
                      Icon(spec.iconData, color: accent, size: 26),
                      const SizedBox(width: 12),
                      Expanded(child: name),
                      const SizedBox(width: 4),
                      pencil,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// El nombre entero, para el lector de pantalla: «Extraer texto completo».
  String _fullName(AppLocalizations l10n) => switch (spec.kind) {
    StudyCreationKind.fullText => l10n.f43StudioExtractFullText,
    StudyCreationKind.summary => l10n.f43StudioExtractSummary,
    StudyCreationKind.synthesis => l10n.f43StudioExtractSynthesis,
    _ => spec.label(l10n),
  };
}
