import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_gallery.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_keywords_view.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_part_tile.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_text_pages.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una sección de un documento procesado, plegable (F41): su nombre, cuánto
/// tiene y, desplegada, sus acciones y sus partes.
///
/// Es la misma para todas: lo que cambia por sección —cómo se ve el cuerpo,
/// qué se lee al escucharla, si se copia— se decide en un `switch` exhaustivo
/// sobre `ProcessedSection`. Sumar una sección es sumar sus casos, no otra
/// pantalla.
///
/// Plegada no pide nada a la base —`ExpansionTile` no arma lo plegado—: un
/// documento con un libro entero en «Texto» no lo lee mientras esa sección
/// está cerrada.
/// Respeta «sin animaciones»: se abre y se cierra de una.
class ProcessedSectionPanel extends StatelessWidget {
  const ProcessedSectionPanel({
    required this.document,
    required this.section,
    required this.readable,
    super.key,
  });

  final ProcessedDocument document;
  final ProcessedSection section;

  /// Lo que lee el lector en voz alta, o `null` mientras se arma.
  final ReadableDocument? readable;

  @override
  Widget build(BuildContext context) {
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

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
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
        leading: Icon(section.icon, color: colors.primary),
        title: Text(section.label(l10n), style: theme.textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        children: [
          _SectionActions(
            document: document,
            section: section,
            readable: readable,
          ),
          switch (section) {
            ProcessedSection.text => ProcessedTextPages(
              documentId: document.id,
              pageCount: count,
              sourceItemId: sourceItemId,
            ),
            ProcessedSection.keywords => ProcessedKeywordsView(
              documentId: document.id,
              count: count,
              sourceItemId: sourceItemId,
            ),
            ProcessedSection.summary ||
            ProcessedSection.synthesis ||
            ProcessedSection.notes ||
            ProcessedSection.fragments => _PartsList(
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

/// Qué se lee al tocar «Escuchar» en [section], o `null` si no tiene una
/// lectura propia —el texto, las palabras clave, las notas y los fragmentos se
/// escuchan con el botón flotante, que lee todo; las imágenes no se leen—. Las
/// palabras clave no van con `ReadScope.keywords`: esa capa lee las palabras
/// sueltas, y acá cada parte es la oración entera que las lleva.
///
/// El texto no lleva el suyo (F45, paso 4): leía lo mismo que el lector
/// flotante de abajo —el documento entero, desde la página que se mira—, y
/// eran dos botones para una sola función.
ReadScope? _listenScopeOf(ProcessedSection section) => switch (section) {
  ProcessedSection.summary => ReadScope.summary,
  ProcessedSection.synthesis => ReadScope.synthesis,
  ProcessedSection.text ||
  ProcessedSection.keywords ||
  ProcessedSection.notes ||
  ProcessedSection.fragments ||
  ProcessedSection.images => null,
};

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

/// Las acciones de una sección, arriba de sus partes: «Escuchar» y «Copiar»,
/// las que tengan sentido para ella.
///
/// Es también el lugar de las acciones que le suma el paso 1b (decisión I):
/// «Resumir», «Sintetizar» y «Palabras clave» sobre el texto del propio
/// procesado viven en la tarjeta de estudiar (`ProcessedStudySlot`), y cada
/// sección puede ofrecer acá su atajo.
class _SectionActions extends StatelessWidget {
  const _SectionActions({
    required this.document,
    required this.section,
    required this.readable,
  });

  final ProcessedDocument document;
  final ProcessedSection section;
  final ReadableDocument? readable;

  @override
  Widget build(BuildContext context) {
    final scope = _listenScopeOf(section);
    final copies = _copiesWhole(section);
    if (scope == null && !copies) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      children: [
        if (scope != null) _ListenButton(readable: readable, scope: scope),
        if (copies) _CopyButton(documentId: document.id, section: section),
      ],
    );
  }
}

/// «Escuchar» una sección con el lector flotante, resaltando en su lugar lo
/// que suena. El texto empieza en la página que se está mirando.
class _ListenButton extends ConsumerWidget {
  const _ListenButton({required this.readable, required this.scope});

  final ReadableDocument? readable;
  final ReadScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final document = readable;
    final run = document == null
        ? ReadAloudRun.none
        : ref.watch(
            readAloudRunProvider((documentId: document.id, scope: scope)),
          );
    final playing = run == ReadAloudRun.playing;

    return TextButton.icon(
      key: Key('processed-listen-${scope.name}'),
      icon: document == null
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              playing ? Icons.pause_outlined : Icons.volume_up_outlined,
              size: 18,
            ),
      label: Text(playing ? l10n.mediaPlayerPause : l10n.studyListen),
      onPressed: document == null || !document.offers(scope)
          ? null
          : () {
              final controller = ref.read(readAloudControllerProvider.notifier);
              unawaited(switch (run) {
                ReadAloudRun.playing => controller.pause(),
                ReadAloudRun.paused => controller.play(),
                ReadAloudRun.none => controller.open(document, scope: scope),
              });
            },
    );
  }
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
      onPressed: () async {
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
      },
    );
  }
}

/// Las partes de una sección que no es el texto, de a tandas: el resumen de
/// un libro puede tener cientos de oraciones, y se arman las que se ven más
/// «Mostrar más».
class _PartsList extends ConsumerStatefulWidget {
  const _PartsList({
    required this.documentId,
    required this.section,
    required this.count,
    required this.sourceItemId,
  });

  final String documentId;
  final ProcessedSection section;
  final int count;
  final String? sourceItemId;

  /// Cuántas partes se muestran por tanda.
  static const pageSize = 50;

  @override
  ConsumerState<_PartsList> createState() => _PartsListState();
}

class _PartsListState extends ConsumerState<_PartsList> {
  var _limit = _PartsList.pageSize;
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
              onPressed: () => setState(() => _limit += _PartsList.pageSize),
              child: Text(l10n.libraryLoadMore),
            ),
          ),
      ],
    );
  }
}
