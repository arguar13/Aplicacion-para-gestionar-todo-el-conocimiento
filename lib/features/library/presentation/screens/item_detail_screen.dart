import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_activity_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_organized_line.dart';
import 'package:sinapsis/features/blocks/presentation/widgets/block_view.dart';
import 'package:sinapsis/features/citations/presentation/export_bibliography_action.dart';
import 'package:sinapsis/features/citations/presentation/widgets/citation_section.dart';
import 'package:sinapsis/features/duplicates/domain/entities/merged_provenance.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/export/domain/entities/export_format.dart';
import 'package:sinapsis/features/export/domain/usecases/export_item_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/export/presentation/widgets/export_format_presentation.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/generate_quiz_button.dart';
import 'package:sinapsis/features/graph/presentation/widgets/local_graph_panel.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/floating_mini_player.dart';
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/library/presentation/widgets/playback_synced_text.dart';
import 'package:sinapsis/features/library/presentation/widgets/source_panel.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/notes/presentation/widgets/cited_sources_section.dart';
import 'package:sinapsis/features/notes/presentation/widgets/derived_note_badge.dart';
import 'package:sinapsis/features/notes/presentation/widgets/generate_derived_note_button.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlightable_text.dart';
import 'package:sinapsis/features/organize/presentation/widgets/map_note_links_section.dart';
import 'package:sinapsis/features/organize/presentation/widgets/property_editor.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relations_section.dart';
import 'package:sinapsis/features/organize/presentation/widgets/space_picker.dart';
import 'package:sinapsis/features/organize/presentation/widgets/tag_editor.dart';
import 'package:sinapsis/features/reference/presentation/widgets/reference_section.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/embedded_file_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un elemento por dentro: su contenido y, sobre todo, de dónde salió.
///
/// La procedencia tiene su propia sección con el mismo peso visual que el
/// contenido, y no es decoración: un texto sin origen sirve para leer, no
/// para trabajar. Poder volver al video, al artículo o al perfil de quien lo
/// escribió es la mitad del valor de haberlo guardado.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final item = ref.watch(libraryItemProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.valueOrNull?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (item.valueOrNull != null) ...[
            _ExportButton(item: item.valueOrNull!),
            // Solo una nota cita algo —F15, D13—: una fuente no tiene
            // bibliografía propia que exportar.
            if (item.valueOrNull!.source.kind == SourceKind.manualNote)
              _BibliographyButton(item: item.valueOrNull!),
            // Cualquier elemento puede ser el origen de un derivado (F16,
            // D5) —una fuente entera o una nota, no solo desde un cuaderno—.
            GenerateDerivedNoteButton(
              sourceTitle: item.valueOrNull!.title,
              itemId: item.valueOrNull!.id,
            ),
            GenerateQuizButton(item: item.valueOrNull!),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.detailDelete,
              onPressed: () => _moveToTrash(context, ref),
            ),
          ],
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _DetailError(error: error),
        data: (value) => value == null
            // El elemento dejó de existir — borrado acá o desde otro lado.
            // Se muestra un vacío breve mientras el `pop` de abajo saca de la
            // pantalla, en vez de seguir mostrando algo que ya no está.
            ? const SizedBox.shrink()
            : _DetailBody(item: value),
      ),
    );
  }

  /// Manda el elemento a la papelera —con su «Deshacer»— y vuelve. No pregunta
  /// antes: no destruye nada, se restaura tal cual.
  Future<void> _moveToTrash(BuildContext context, WidgetRef ref) async {
    final moved = await moveToTrashWithUndo(context, ref, [itemId]);
    if (!moved || !context.mounted) return;

    // Mismo cuidado que en la captura: a un detalle se puede llegar por
    // enlace directo, y entonces no hay pila que desapilar.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.library);
    }
  }
}

/// El botón de exportar, con el formato como único paso: no hace falta
/// preguntar dónde guardarlo aparte, porque el selector de guardado del
/// sistema ya resuelve eso en el mismo gesto.
class _ExportButton extends ConsumerWidget {
  const _ExportButton({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return PopupMenuButton<ExportFormat>(
      icon: const Icon(Icons.ios_share),
      tooltip: l10n.detailExportTooltip,
      onSelected: (format) => _export(context, ref, format),
      itemBuilder: (context) => [
        // Solo PDF y Word, a pedido del usuario: Markdown, texto plano y
        // BibTeX le alargaban el menú sin usarlos. El mismo par que el menú
        // de cada fila —ver `offeredItemExportFormats`—.
        for (final format in offeredItemExportFormats)
          PopupMenuItem(value: format, child: Text(format.label(l10n))),
      ],
    );
  }

  /// No distingue "canceló el diálogo de guardado" de "lo guardó": ver
  /// [ExportItemUseCase]. Solo avisa cuando algo salió mal de verdad.
  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ExportFormat format,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await ref.read(exportItemUseCaseProvider)(
      ExportItemParams(item: item, format: format),
    );
    if (!context.mounted) return;

    result.match((failure) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n))));
    }, (_) {});
  }
}

/// La bibliografía de lo que cita esta nota, sola (F15, D13): distinto de
/// exportar la nota —que ya la lleva al pie, sin este botón— porque a veces
/// lo único que hace falta es la lista de fuentes, sin el resto del texto.
class _BibliographyButton extends ConsumerWidget {
  const _BibliographyButton({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      icon: const Icon(Icons.format_quote_outlined),
      tooltip: l10n.bibliographyExportAction,
      onPressed: () => _export(context, ref),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final sources = await ref
        .read(bibliographyRepositoryProvider)
        .sourcesCitedBy(item.id);
    if (!context.mounted) return;

    await exportBibliography(
      context,
      ref,
      sources: sources,
      suggestedName: item.title,
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({required this.item});

  final KnowledgeItem item;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  final _scroll = ScrollController();

  /// Dónde está el reproductor del archivo: el mini reproductor aparece
  /// cuando sale de la pantalla (F23).
  final _playerKey = GlobalKey();

  /// Para que "Volver al audio" lleve a la palabra que suena (F23).
  final _follow = PlaybackFollowLink();

  /// Lo que se ofrece para leer en voz alta (F25): se arma de nuevo solo
  /// cuando el elemento cambia, no con cada cuadro.
  late ReadableDocument _readable = _readableOf(widget.item);

  /// Lo mismo con el texto plegado de un documento, recién cuando alguien
  /// lo despliega: ver [_CollapsedExtractedText].
  ReadableDocument? _unfolded;

  ReadableDocument _readableUnfolded() =>
      _unfolded ??= _readableOf(widget.item, unfolded: true);

  @override
  void didUpdateWidget(_DetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _readable = _readableOf(widget.item);
      _unfolded = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final texts = item.renditions.whereType<TextRendition>().toList();

    return Stack(
      children: [
        ReadableRegion(
          document: _readable,
          child: _scrollingContent(context, item, theme, texts),
        ),
        // Con un audio o un video: el mini reproductor, para pausar o seguir
        // el audio sin volver a subir hasta el reproductor (F23).
        Positioned.fill(
          child: FloatingMiniPlayer(
            item: item,
            scrollController: _scroll,
            playerKey: _playerKey,
            link: _follow,
          ),
        ),
      ],
    );
  }

  Widget _scrollingContent(
    BuildContext context,
    KnowledgeItem item,
    ThemeData theme,
    List<TextRendition> texts,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          // `SingleChildScrollView` con una `Column`, no un `ListView`: un
          // `ListView` arma un `SliverList`, que construye —y mide— sus
          // hijos de a poco a medida que entran en pantalla, y mientras
          // alguno no se construyó todavía estima cuánto mide el resto
          // promediando lo que ya vio. Con una sola forma de contenido mucho
          // más alta que el resto —un libro entero en un solo bloque de
          // texto, frente al título o las etiquetas— esa estimación queda
          // muy corta durante casi toda la lectura y se corrige de golpe
          // cerca del final: la barra de desplazamiento avanza poquísimo al
          // principio y salta de repente al llegar. `SingleChildScrollView`
          // mide a su hijo entero de una sola vez, así que la barra queda
          // siempre exacta — y el costo real es el mismo, porque esta
          // pantalla nunca tiene miles de hijos, solo unos pocos, uno de
          // ellos largo.
          child: SingleChildScrollView(
            controller: _scroll,
            // Lugar abajo para el mini reproductor: que no tape el final del
            // texto.
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.headlineSmall),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (item.source.kind == SourceKind.manualNote) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _NoteMaturityChip(itemId: item.id),
                      _MapNoteToggle(itemId: item.id),
                      DerivedNoteBadge(itemId: item.id),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SpacePicker(item: item),
                const SizedBox(height: 24),
                TagEditor(item: item),
                const SizedBox(height: 24),
                PropertyEditor(item: item),
                const SizedBox(height: 24),

                if (item.notes?.isNotEmpty ?? false) ...[
                  _UserNote(itemId: item.id, note: item.notes!),
                  const SizedBox(height: 24),
                ],

                // El archivo original, visible directo acá arriba —antes del
                // contenido— para lo que de verdad agrega algo sobre el texto
                // ya extraído: una foto, un video, un PDF con su maquetación,
                // la página archivada. Sin botón "Ver" de por medio: si hay
                // algo que mostrar, ya se está mostrando.
                //
                // Debajo, el panel de la fuente (F26): el audio, lo que está
                // pasando y las acciones, en una sola tarjeta. Los dos juntos
                // son "el reproductor" para el mini reproductor (F23): el
                // audio se maneja desde la vista previa —un audio— o desde el
                // panel —un video, YouTube—, y mientras se vea un tercio del
                // conjunto no hace falta el mini reproductor.
                KeyedSubtree(
                  key: _playerKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmbeddedFileViewer(item: item, gapBelow: 12),
                      _SourcePanelWithAi(item: item),
                    ],
                  ),
                ),

                // El texto, salvo mientras se vuelve a extraer: ahí el panel
                // cuenta cómo va, y el viejo deja de verse.
                if (texts.isNotEmpty && !item.isBeingProcessed) ...[
                  const SizedBox(height: 16),
                  if (item.source.kind == SourceKind.document)
                    _CollapsedExtractedText(
                      item: item,
                      texts: texts,
                      readable: _readableUnfolded,
                    )
                  else
                    for (final rendition in texts) ...[
                      if (rendition.kind == RenditionKind.blocks)
                        _BlocksRendition(item: item, rendition: rendition)
                      else
                        _TextRenditionView(
                          item: item,
                          rendition: rendition,
                          link: _follow,
                        ),
                      const SizedBox(height: 16),
                    ],
                ],

                const SizedBox(height: 16),
                FlashcardSection(item: item),
                const SizedBox(height: 24),
                LocalGraphPanel(item: item),
                const SizedBox(height: 24),
                // De dónde sale lo que dice la nota: no dibuja nada si no cita
                // ninguna fuente, y lleva su propio espacio de abajo.
                if (item.source.kind == SourceKind.manualNote)
                  CitedSourcesSection(noteId: item.id),
                Consumer(
                  builder: (context, ref, child) {
                    final kind = ref
                        .watch(noteKindProvider(item.id))
                        .valueOrNull;
                    return kind == NoteKind.map
                        ? MapNoteLinksSection(item: item)
                        : RelationsSection(item: item);
                  },
                ),
                const SizedBox(height: 24),
                // Los datos con que se cita: una nota no se cita, se escribe.
                if (item.source.kind != SourceKind.manualNote) ...[
                  ReferenceSection(item: item),
                  const SizedBox(height: 24),
                ],
                CitationSection(item: item),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _Provenance(item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se lee en voz alta del detalle de [item] (F25), en el orden en que
/// se ve: la nota del usuario, y después cada forma de texto —una nota de
/// bloques, bloque por bloque—.
///
/// Solo lo que se ve: sin el texto que se está volviendo a extraer —en su
/// lugar, el panel de la fuente cuenta cómo va—, y sin el de un documento
/// mientras está plegado
/// —con [unfolded], con él—. El original de un Word o un EPUB, en su lector
/// embebido, lo ofrece ese lector, que va por delante.
ReadableDocument _readableOf(KnowledgeItem item, {bool unfolded = false}) {
  final markdown = extractedTextIsMarkdown(item.source);
  final transcript = isTranscriptSource(item.source);
  final textsShown =
      !item.isBeingProcessed &&
      (unfolded || item.source.kind != SourceKind.document);

  return documentFrom('item:${item.id}', item.title, [
    if (item.notes case final notes? when notes.isNotEmpty)
      (
        sourceKey: _userNoteKey(item.id),
        text: notes,
        markdown: false,
        transcript: false,
      ),
    if (textsShown)
      for (final rendition in item.renditions.whereType<TextRendition>())
        if (rendition.kind == RenditionKind.blocks)
          for (final (index, block) in decodeContentBlocks(
            rendition.content,
          ).indexed)
            (
              sourceKey: BlockView.readAloudKey(rendition.id, index),
              text: block.text,
              markdown: true,
              transcript: false,
            )
        else
          (
            sourceKey: rendition.id,
            text: rendition.content,
            markdown: markdown,
            transcript: transcript,
          ),
  ]);
}

/// Con qué nombre conoce el lector flotante a la nota del usuario (F25).
String _userNoteKey(String itemId) => 'note:$itemId';

/// El panel de la fuente con la línea de lo que la IA organizó sola (F27),
/// cuando hizo algo que siga en pie, dejó algo para revisar o se deshizo lo
/// que hizo —ver `AiItemSummary.isVisible`—.
///
/// Se decide acá y no dentro de la línea: el panel separa cada franja con
/// una raya, y una franja que se dibuja vacía dejaría la raya sola al pie.
class _SourcePanelWithAi extends ConsumerWidget {
  const _SourcePanelWithAi({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiItemSummaryProvider(item.id));
    return SourcePanel(
      item: item,
      extraSections: [
        if (ai.isVisible)
          AiOrganizedLine(itemId: item.id, itemTitle: item.title, summary: ai),
      ],
    );
  }
}

/// La madurez de una nota viva —`seed`/`developing`/`mature`—, leída del
/// espejo `item`/`source`/`note` que F3 mantiene sincronizado. `null`
/// mientras esa fila todavía no exista —no debería pasar salvo justo
/// después de F1/antes del catch-up de F3— no dibuja nada: mejor un
/// hueco silencioso que una insignia rota.
class _NoteMaturityChip extends ConsumerWidget {
  const _NoteMaturityChip({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maturity = ref.watch(noteMaturityProvider(itemId)).valueOrNull;
    if (maturity == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = maturity.color(theme.colorScheme);

    // La madurez la decide quien escribe: tocar la insignia abre las tres
    // etapas y se puede elegir cualquiera, también volver atrás.
    return PopupMenuButton<NoteMaturity>(
      tooltip: l10n.noteMaturityChangeTooltip,
      initialValue: maturity,
      onSelected: (selected) => ref
          .read(inboxRepositoryProvider)
          .setNoteMaturity(itemId: itemId, maturity: selected),
      itemBuilder: (context) => [
        for (final option in NoteMaturity.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: option.color(theme.colorScheme),
                ),
                const SizedBox(width: 12),
                Text(option.label(l10n)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              maturity.label(l10n),
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

/// Marcar o desmarcar una nota como "mapa" (ver la decisión sobre F6):
/// `null` mientras la fila del espejo todavía no exista, mismo criterio
/// que [_NoteMaturityChip] — nada que tocar todavía. Desmarcarla la deja
/// en `NoteKind.living` siempre, sin restaurar el tipo anterior.
class _MapNoteToggle extends ConsumerWidget {
  const _MapNoteToggle({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(noteKindProvider(itemId)).valueOrNull;
    if (kind == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final isMap = kind == NoteKind.map;

    return Tooltip(
      message: isMap
          ? l10n.detailUnmarkAsMapNoteTooltip
          : l10n.detailMarkAsMapNoteTooltip,
      child: FilterChip(
        avatar: Icon(NoteKind.map.icon, size: 18),
        label: Text(NoteKind.map.label(l10n)),
        selected: isMap,
        onSelected: (selected) => ref
            .read(inboxRepositoryProvider)
            .setNoteKind(
              itemId: itemId,
              kind: selected ? NoteKind.map : NoteKind.living,
            ),
      ),
    );
  }
}

/// El texto que se sacó de un documento, plegado (F21, decisión A).
///
/// En un documento lo principal es el original, arriba, en su visor: el
/// texto extraído existe para la búsqueda, el chat, las tarjetas y el quiz,
/// no para leerlo acá. Plegado tampoco se construye: el de un libro de
/// cientos de páginas no se arma hasta que alguien lo abre. Sus acciones
/// —leer, resumir, copiar— quedan a la vista igual, en el panel de la
/// fuente (F26).
///
/// Desplegado, se lee en voz alta (F25) —es lo que se puede leer de un PDF—:
/// ofrece el detalle entero con este texto, por encima de lo que ofrece el
/// resto de la pantalla, y lo retira al plegarse.
class _CollapsedExtractedText extends StatelessWidget {
  const _CollapsedExtractedText({
    required this.item,
    required this.texts,
    required this.readable,
  });

  final KnowledgeItem item;
  final List<TextRendition> texts;

  /// Lo que se lee desplegado; se arma recién al desplegar.
  final ReadableDocument Function() readable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      leading: const Icon(Icons.notes_outlined),
      title: Text(l10n.detailExtractedTextTitle),
      subtitle: Text(
        l10n.detailExtractedTextSubtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        // Un `Builder`: plegado, `ExpansionTile` no monta lo de adentro, y
        // así tampoco se parte el texto en líneas.
        Builder(
          builder: (context) => ReadableRegion(
            document: readable(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final rendition in texts) ...[
                  if (rendition.kind == RenditionKind.blocks)
                    _BlocksRendition(item: item, rendition: rendition)
                  else
                    _TextRenditionView(item: item, rendition: rendition),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Una forma de texto plano, Markdown o la transcripción de un video o un
/// audio, para leer, subrayar y seguir al audio. Lo que se hace con ella
/// —leer para destilar, resumir, copiar, quitar las marcas de tiempo— está
/// en el panel de la fuente (F26), una sola vez por elemento y no repetido
/// encima de cada texto.
class _TextRenditionView extends StatelessWidget {
  const _TextRenditionView({
    required this.item,
    required this.rendition,
    this.link,
  });

  final KnowledgeItem item;
  final TextRendition rendition;

  /// Con el mini reproductor: "Volver al audio" muestra lo que suena en
  /// este texto (F23).
  final PlaybackFollowLink? link;

  @override
  Widget build(BuildContext context) {
    // La transcripción de un audio o un video sigue al audio mientras
    // suena: la palabra que se dice, en amarillo (F23).
    if (isTranscriptSource(item.source) && rendition.isPrimary) {
      return PlaybackSyncedText(
        item: item,
        rendition: rendition,
        markdown: extractedTextIsMarkdown(item.source),
        link: link,
      );
    }
    return HighlightableText(
      itemId: item.id,
      renditionId: rendition.id,
      content: rendition.content,
      markdown: extractedTextIsMarkdown(item.source),
    );
  }
}

/// Una nota de bloques dentro del detalle: la muestra de solo lectura. Para
/// cambiarla, "Editar" en el panel de la fuente (F26).
///
/// Aparte del resto de las formas de texto —que se muestran directo con
/// `HighlightableText`— porque el contenido guardado es JSON, no texto para
/// leer tal cual; hay que decodificarlo antes.
class _BlocksRendition extends ConsumerWidget {
  const _BlocksRendition({required this.item, required this.rendition});

  final KnowledgeItem item;
  final TextRendition rendition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BlockView(
      blocks: decodeContentBlocks(rendition.content),
      renditionId: rendition.id,
      onLinkTap: (title) => unawaited(_openLink(context, ref, title)),
    );
  }

  /// Busca un elemento por título exacto —sin distinguir mayúsculas— y
  /// navega a su detalle. Un `[[Título]]` que ya no coincide con nada
  /// —porque el elemento se borró, o porque le cambiaron el nombre después
  /// de escrito el enlace— avisa en vez de fallar en silencio: el vínculo
  /// de verdad (`Relations`, el que alimenta el Grafo) ya quedó creado al
  /// escribirlo, así que solo el texto quedó desactualizado.
  ///
  /// `list()`, no `libraryItemsProvider`: ese es un `StreamProvider`
  /// pensado para que un widget lo mire con `ref.watch` desde su propio
  /// `build`, no para leerlo una sola vez desde un manejador de toque como
  /// este — hacerlo así deja una suscripción activa que `autoDispose`
  /// nunca llega a soltar, y la próxima operación contra la base que
  /// dependa de esa misma conexión se queda esperando para siempre.
  Future<void> _openLink(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final normalized = title.trim().toLowerCase();
    final allItems =
        (await ref.read(libraryRepositoryProvider).list(const LibraryQuery()))
            .getRight()
            .toNullable() ??
        const <KnowledgeItem>[];
    final target = allItems
        .where((i) => i.title.trim().toLowerCase() == normalized)
        .firstOrNull;
    if (!context.mounted) return;

    if (target == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.detailLinkNotFound(title))));
      return;
    }

    unawaited(context.push(RoutePaths.itemDetail(target.id)));
  }
}

/// Lo que escribió el usuario sobre esto, separado del contenido.
///
/// Va destacado y arriba: es lo único de la pantalla que no vino de afuera, y
/// suele ser la razón por la que se guardó.
class _UserNote extends StatelessWidget {
  const _UserNote({required this.itemId, required this.note});

  final String itemId;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ReadAloudText(
              note,
              sourceKey: _userNoteKey(itemId),
              style: theme.textTheme.bodyMedium,
              selectable: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Provenance extends ConsumerWidget {
  const _Provenance({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final source = item.source;

    // La fecha se formatea con el idioma activo: "11 sept 2026" en español y
    // "Sep 11, 2026" en inglés, en vez de un formato fijo que se lee raro en
    // uno de los dos.
    final locale = Localizations.localeOf(context).toString();
    final captured = DateFormat.yMMMd(locale).format(source.capturedAt);
    final merged = ref
        .watch(mergedProvenancesForItemProvider(item.id))
        .valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.detailProvenance,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _ProvenanceRow(icon: source.kind.icon, text: source.kind.label(l10n)),
        if (source.authorName != null)
          _ProvenanceRow(
            icon: Icons.person_outline,
            text: l10n.detailAuthor(source.authorName!),
          ),
        _ProvenanceRow(
          icon: Icons.event_outlined,
          text: l10n.detailCapturedOn(captured),
        ),
        // Para un PDF o un libro no hay ningún enlace al que volver: el
        // archivo **es** la fuente. Sin esta fila, el detalle no diría en
        // ninguna parte que la copia original está a salvo, y el usuario
        // tendría que confiar en que sí.
        // Ni "Ver" ni "Abrir archivo" hacen falta acá: el archivo ya se ve
        // directo arriba, en `EmbeddedFileViewer`, con su propio ícono de
        // pantalla completa para quien quiera más lugar.
        if (source.originalFilePath != null)
          _ProvenanceRow(
            icon: Icons.folder_outlined,
            text: l10n.detailOriginalFile(
              originalFileNameOf(source.originalFilePath!),
            ),
          ),
        if (source.url != null) ...[
          const SizedBox(height: 12),
          _OriginalLink(url: source.url!),
        ],
        // Un elemento que absorbió duplicados al fusionarse (F7) no pierde
        // de dónde salía el descartado: esta lista chica es lo único que
        // queda de esa procedencia una vez que su propia fila desaparece.
        if (merged != null && merged.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.detailMergedProvenanceTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final provenance in merged)
            _MergedProvenanceRow(provenance: provenance, locale: locale),
        ],
      ],
    );
  }
}

class _MergedProvenanceRow extends StatelessWidget {
  const _MergedProvenanceRow({required this.provenance, required this.locale});

  final MergedProvenance provenance;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final captured = DateFormat.yMMMd(locale).format(provenance.capturedAt);

    return _ProvenanceRow(
      icon: Icons.call_merge,
      text: l10n.detailMergedProvenanceRow(
        provenance.sourceKind.label(l10n),
        captured,
      ),
    );
  }
}

class _ProvenanceRow extends StatelessWidget {
  const _ProvenanceRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El enlace al original, seleccionable y copiable.
///
/// Se copia en vez de abrirse: abrirlo exigiría un complemento nativo que hoy
/// no se puede probar en este proyecto, y ofrecer un botón que a veces no
/// hace nada es peor que ofrecer uno que siempre funciona. Copiar y pegar
/// resuelve el caso completo mientras tanto.
class _OriginalLink extends StatelessWidget {
  const _OriginalLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            url,
            contextMenuBuilder: buildSelectionMenu,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(l10n.detailLinkCopied)));
          },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.detailCopyLink),
        ),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final message = error is Failure
        ? (error as Failure).localizedMessage(l10n)
        : l10n.globalErrorUnexpected;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// El nombre con el que el usuario reconoce su archivo.
///
/// En el almacén cada archivo vive en una carpeta con el identificador de su
/// fuente, así que el último tramo de la ruta ya es el nombre original: no
/// hay nada que recortar ni que adivinar.
String originalFileNameOf(String storedPath) => p.basename(storedPath);
