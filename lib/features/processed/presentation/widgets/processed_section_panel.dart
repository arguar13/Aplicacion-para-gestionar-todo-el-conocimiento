import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_reader_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_gallery.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_keywords_view.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_part_tile.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una sección de un documento procesado (F41): su nombre, cuánto tiene y lo
/// que tiene.
///
/// **El texto, el resumen y la síntesis se leen en el marco de lectura**
/// (F45, mejora 12; F47, paso 1): la sección es un renglón que lo abre —el
/// mismo lector que el de «Lo creado», con el texto limpio, la letra de
/// «Apariencia» y un solo «Escuchar»—, y editar se hace desde su ⋮. Las demás
/// —las palabras clave, las notas, los fragmentos, las imágenes— se despliegan
/// acá, con sus partes; también el resumen y la síntesis de un documento sin
/// texto propio, que el lector no tiene sobre qué mostrar.
///
/// Lo que cambia por sección se decide en un `switch` exhaustivo sobre
/// `ProcessedSection`: sumar una sección es sumar sus casos, no otra
/// pantalla.
///
/// Plegada no pide nada a la base —`ExpansionTile` no arma lo plegado—, y el
/// texto entero no se trae a esta pantalla: lo trae el lector, de a bloques.
/// Respeta «sin animaciones»: se abre y se cierra de una.
class ProcessedSectionPanel extends ConsumerWidget {
  const ProcessedSectionPanel({
    required this.document,
    required this.section,
    super.key,
  });

  final ProcessedDocument document;
  final ProcessedSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = document.summary.partCounts[section] ?? 0;
    final edited = document.stats[section]?.edited ?? 0;
    final source = document.source;
    final sourceItemId = source == null || source.inTrash
        ? null
        : source.itemId;
    final subtitle = [
      section.countLabel(l10n, count),
      if (edited > 0) l10n.processedEditedCount(edited),
    ].join(' · ');
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
    );
    final leading = Icon(section.icon, color: colors.primary);
    final title = Text(section.label(l10n), style: theme.textTheme.titleMedium);
    final detail = Text(
      subtitle,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );

    // El resumen y la síntesis se leen sobre el texto propio del documento
    // —sus páginas de «Texto» o la copia de su original—, donde están
    // marcados. Un documento que solo trajo sus oraciones, sin texto, las
    // muestra acá, como siempre.
    final own = ref.watch(extractOwnTextProvider(document.id));
    final readable =
        section == ProcessedSection.text || own.isLoading || own.value != null;
    if (extractKindOfSection(section) case final kind? when readable) {
      return Material(
        color: colors.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: Key('processed-read-${section.name}'),
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          leading: leading,
          title: title,
          subtitle: detail,
          trailing: Icon(
            Icons.chrome_reader_mode_outlined,
            color: colors.onSurfaceVariant,
            semanticLabel: l10n.f47P1SectionRead,
          ),
          onTap: count == 0
              ? null
              : () => unawaited(
                  context.push(RoutePaths.extractReading(kind, [document.id])),
                ),
        ),
      );
    }

    return Material(
      color: colors.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: section.startsExpanded(
          alone: document.summary.sections.length == 1,
        ),
        expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: leading,
        title: title,
        subtitle: detail,
        children: [
          if (_copiesWhole(section))
            Align(
              alignment: Alignment.centerRight,
              child: _CopyButton(documentId: document.id, section: section),
            ),
          switch (section) {
            ProcessedSection.keywords => ProcessedKeywordsView(
              documentId: document.id,
              count: count,
              sourceItemId: sourceItemId,
            ),
            ProcessedSection.notes ||
            ProcessedSection.fragments ||
            // El texto, el resumen y la síntesis se leen en el marco (arriba):
            // acá no llegan.
            ProcessedSection.text ||
            ProcessedSection.summary ||
            ProcessedSection.synthesis => ProcessedPartsList(
              documentId: document.id,
              section: section,
              count: count,
              sourceItemId: sourceItemId,
            ),
            ProcessedSection.images => ProcessedImageGallery(
              documentId: document.id,
              count: count,
            ),
          },
        ],
      ),
    );
  }
}

/// Si «Copiar» copia la sección entera: el texto de un libro no —se copia
/// de a una página, seleccionándola—; lo elegido sí. Las imágenes no son
/// texto que copiar.
bool _copiesWhole(ProcessedSection section) => switch (section) {
  ProcessedSection.text || ProcessedSection.images => false,
  ProcessedSection.summary ||
  ProcessedSection.synthesis ||
  ProcessedSection.keywords ||
  ProcessedSection.notes ||
  ProcessedSection.fragments => true,
};

/// Copia [section] entera de [documentId], una parte por párrafo, y lo dice.
Future<void> copyProcessedSection(
  BuildContext context,
  WidgetRef ref,
  String documentId,
  ProcessedSection section,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final parts = await ref
      .read(processedRepositoryProvider)
      .partsOf(documentId, sections: {section});
  final list = parts.getRight().toNullable();
  if (list == null || list.isEmpty) return;
  await Clipboard.setData(
    ClipboardData(text: [for (final p in list) p.content].join('\n\n')),
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.studyCopied)));
}

/// «Copiar» la sección entera, una parte por párrafo.
class _CopyButton extends ConsumerWidget {
  const _CopyButton({required this.documentId, required this.section});

  final String documentId;
  final ProcessedSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return TextButton.icon(
      key: Key('processed-copy-${section.name}'),
      icon: const Icon(Icons.copy_outlined, size: 18),
      label: Text(l10n.studyCopy),
      onPressed: () =>
          unawaited(copyProcessedSection(context, ref, documentId, section)),
    );
  }
}

/// Las partes de una sección que no es el texto, de a tandas: el resumen de
/// un libro puede tener cientos de oraciones, y se arman las que se ven más
/// «Mostrar más». La sección desplegada del documento y la edición de las
/// oraciones del resumen o la síntesis desde el lector (F47, paso 1).
class ProcessedPartsList extends ConsumerStatefulWidget {
  const ProcessedPartsList({
    required this.documentId,
    required this.section,
    required this.count,
    required this.sourceItemId,
    super.key,
  });

  final String documentId;
  final ProcessedSection section;
  final int count;
  final String? sourceItemId;

  /// Cuántas partes se muestran por tanda.
  static const pageSize = 50;

  @override
  ConsumerState<ProcessedPartsList> createState() => _PartsListState();
}

class _PartsListState extends ConsumerState<ProcessedPartsList> {
  var _limit = ProcessedPartsList.pageSize;
  List<ProcessedPart>? _shown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parts = ref.watch(
      processedPartsProvider((
        documentId: widget.documentId,
        section: widget.section,
        offset: 0,
        limit: _limit,
      )),
    );
    // Mientras llega la tanda más larga se siguen viendo las de antes, sin
    // pasar por la ruedita.
    if (parts.valueOrNull case final loaded?) _shown = loaded;
    final list = _shown;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final remaining = widget.count - list.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, part) in list.indexed) ...[
          if (index > 0) const Divider(height: 1),
          ProcessedPartTile(
            key: ValueKey(part.id),
            part: part,
            sourceItemId: widget.sourceItemId,
          ),
        ],
        if (remaining > 0 && list.length >= _limit)
          Align(
            child: TextButton(
              onPressed: () =>
                  setState(() => _limit += ProcessedPartsList.pageSize),
              child: Text(l10n.libraryLoadMore),
            ),
          ),
      ],
    );
  }
}
