import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
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
import 'package:sinapsis/features/library/presentation/widgets/move_to_trash.dart';
import 'package:sinapsis/features/library/presentation/widgets/summarize_button.dart';
import 'package:sinapsis/features/narration/presentation/widgets/narration_player.dart';
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
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/features/transform/presentation/widgets/processing_status.dart';
import 'package:sinapsis/features/transform/presentation/widgets/youtube_audio_download_section.dart';
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
        for (final format in ExportFormat.values)
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

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = item.renditions.whereType<TextRendition>().toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Scrollbar(
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
            padding: const EdgeInsets.all(24),
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
                  _UserNote(note: item.notes!),
                  const SizedBox(height: 24),
                ],

                // El archivo original, visible directo acá arriba —antes del
                // contenido— para lo que de verdad agrega algo sobre el texto
                // ya extraído: una foto, un video, un PDF con su maquetación,
                // la página archivada. Sin botón "Ver" de por medio: si hay
                // algo que mostrar, ya se está mostrando.
                EmbeddedFileViewer(item: item),

                // Justo debajo de donde se está viendo o escuchando el
                // archivo, no perdido al final de la procedencia: es la
                // acción que sigue naturalmente a mirarlo, no algo que se
                // decide desde una lista de metadatos.
                if (_hasKeepableText(item)) ...[
                  const SizedBox(height: 4),
                  _DeleteOriginalFileButton(item: item),
                ],

                // El audio de un video de YouTube: se baja solo a pedido
                // (F21) —el video ya está listo con su transcripción— y,
                // bajado, se escucha acá. En la web no hay de dónde bajarlo.
                if (item.source.kind == SourceKind.youtube && !kIsWeb) ...[
                  YouTubeAudioDownloadSection(item: item),
                  const SizedBox(height: 16),
                ],

                if (texts.isEmpty)
                  _NoContentYet(item: item)
                else if (item.source.kind == SourceKind.document)
                  _CollapsedExtractedText(item: item, texts: texts)
                else
                  for (final rendition in texts) ...[
                    if (rendition.kind == RenditionKind.blocks)
                      _BlocksRendition(item: item, rendition: rendition)
                    else
                      _TextRenditionView(item: item, rendition: rendition),
                    const SizedBox(height: 16),
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

/// Una rendition de texto plano, Markdown o la transcripción de un video o
/// audio: se muestra con [HighlightableText] y, si tiene marcas de tiempo
/// —`[mm:ss]` al principio de cada línea, las pone `formatTranscript` en
/// `youtube_transcript_transformer.dart`—, con un botón para quitarlas y
/// dejar el texto corrido.
/// El texto que se sacó de un documento, plegado (F21, decisión A).
///
/// En un documento lo principal es el original, arriba, en su visor: el
/// texto extraído existe para la búsqueda, el chat, las tarjetas y el quiz,
/// no para leerlo acá. Plegado tampoco se construye: el de un libro de
/// cientos de páginas no se arma hasta que alguien lo abre.
class _CollapsedExtractedText extends StatelessWidget {
  const _CollapsedExtractedText({required this.item, required this.texts});

  final KnowledgeItem item;
  final List<TextRendition> texts;

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
        for (final rendition in texts) ...[
          if (rendition.kind == RenditionKind.blocks)
            _BlocksRendition(item: item, rendition: rendition)
          else
            _TextRenditionView(item: item, rendition: rendition),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _TextRenditionView extends ConsumerWidget {
  const _TextRenditionView({required this.item, required this.rendition});

  final KnowledgeItem item;
  final TextRendition rendition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Este texto viene de un DOCX, un EPUB o similar cuando ese es el
    // primario: ahí "Modo lectura" abre el mismo contenido, paginado y con
    // tipografía grande, en vez de repetirlo embebido en el detalle como sí
    // vale la pena para una foto, un video o un PDF — ver
    // `EmbeddedFileViewer`.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 4,
            children: [
              if (isTranscriptSource(item.source) &&
                  hasTimestamps(rendition.content))
                TextButton.icon(
                  icon: const Icon(Icons.timer_off_outlined, size: 18),
                  label: Text(l10n.detailRemoveTimestamps),
                  onPressed: () => _removeTimestamps(context, ref),
                ),
              TextButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(l10n.readingOpenAction),
                onPressed: () => context.push(RoutePaths.reading(item.id)),
              ),
              SummarizeButton(content: rendition.content),
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(l10n.detailCopyContent),
                onPressed: () => _copyContent(context),
              ),
            ],
          ),
        ),
        HighlightableText(
          itemId: item.id,
          renditionId: rendition.id,
          content: rendition.content,
          markdown: extractedTextIsMarkdown(item.source),
        ),
        const SizedBox(height: 8),
        NarrationPlayer(text: rendition.content),
      ],
    );
  }

  Future<void> _copyContent(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: rendition.content));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailContentCopied)));
  }

  Future<void> _removeTimestamps(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final cleaned = stripTimestamps(rendition.content);

    final updated = item.copyWith(
      renditions: [
        for (final r in item.renditions)
          if (r.id == rendition.id && r is TextRendition)
            r.copyWith(content: cleaned)
          else
            r,
      ],
    );

    final result = await ref.read(libraryRepositoryProvider).save(updated);
    if (!context.mounted) return;

    result.match(
      (failure) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
      (_) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.detailTimestampsRemoved))),
    );
  }
}

/// Una nota de bloques dentro del detalle: la muestra de solo lectura, con
/// un botón para abrir el editor y cambiarla.
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
    final l10n = AppLocalizations.of(context)!;
    final blocks = decodeContentBlocks(rendition.content);
    // Un resumen o una lectura en voz alta no distinguen encabezados de
    // párrafos: unir el texto de cada bloque con un punto y aparte es
    // suficiente para las dos cosas, sin tener que enseñarles nada sobre
    // la estructura de una nota de bloques.
    final plainText = blocks.map((b) => b.text).join('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 4,
            children: [
              SummarizeButton(content: plainText),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.blocksEditAction),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) => BlockEditorScreen(existingItem: item),
                  ),
                ),
              ),
            ],
          ),
        ),
        BlockView(
          blocks: blocks,
          onLinkTap: (title) => unawaited(_openLink(context, ref, title)),
        ),
        const SizedBox(height: 8),
        NarrationPlayer(text: plainText),
      ],
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
  const _UserNote({required this.note});

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
            child: SelectableText(note, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// El aviso de que el contenido todavía no llegó.
///
/// En los dos casos —esperando o fallido— dice explícitamente que el enlace
/// ya está guardado. Sin esa aclaración, una pantalla vacía se lee como "no
/// se guardó nada" y el usuario vuelve a capturarlo, o peor, deja de confiar
/// en la app.
class _NoContentYet extends ConsumerWidget {
  const _NoContentYet({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final failed = item.processingState == ProcessingState.failed;
    // Los dos se escuchan siempre y se usan según el estado. Escucharlos
    // solo cuando corresponde suscribía y desuscribía la consulta en medio
    // de un cuadro cada vez que el elemento cambiaba de estado —al tocar
    // "Reintentar", por ejemplo—.
    final activeProgress = ref.watch(processingProgressProvider(item.id));
    final failure = ref.watch(processingFailureProvider(item.id)).valueOrNull;
    final progress = failed ? null : activeProgress;
    // La causa real del fallo, no un "no se pudo" genérico (F21): lo que
    // falta —un modelo, la conexión— dice también qué hacer.
    final reason = failed ? failure : null;
    final needsTranscriptionModel =
        reason == ProcessingFailureReason.transcriptionModelMissing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (item.processingState) {
                ProcessingState.pending => Icons.schedule,
                ProcessingState.processing => Icons.hourglass_empty,
                ProcessingState.failed => Icons.error_outline,
                ProcessingState.ready => Icons.info_outline,
              },
              size: 20,
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                failureMessage(l10n, reason) ??
                    _emptyStateMessage(l10n, item: item, failed: failed),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        // Un libro de cientos de páginas o un video de horas: la barra dice
        // cuánto va, y el original se puede abrir y leer mientras tanto.
        if (progress != null) ...[
          const SizedBox(height: 12),
          ProcessingProgressBar(progress: progress, kind: item.source.kind),
        ],
        if (needsTranscriptionModel) ...[
          const SizedBox(height: 12),
          // Reintentar sin el modelo volvería a fallar igual: lo que resuelve
          // es descargarlo, y al terminar este elemento se retoma solo.
          FilledButton.tonalIcon(
            onPressed: () => context.push(RoutePaths.transcriptionModel),
            icon: const Icon(Icons.download, size: 18),
            label: Text(l10n.failureTranscriptionModelAction),
          ),
        ] else if (failed) ...[
          const SizedBox(height: 12),
          // Reintentar es a pedido y no automático en cada arranque: un fallo
          // puede ser permanente —un video borrado, una página que ya no
          // existe— y volver a intentarlo solo gastaría batería y datos para
          // fallar de nuevo. Quien sabe si vale la pena es el usuario.
          FilledButton.tonalIcon(
            onPressed: () => unawaited(
              ref.read(processingQueueProvider.notifier).retry(item.id),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.detailRetry),
          ),
        ],
      ],
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

/// Si tiene sentido ofrecer "borrar el archivo, quedarme con el texto".
///
/// Hace falta que el original sea video o audio —los formatos pesados,
/// donde soltar el archivo cambia algo— y que ya haya una forma de texto
/// primaria guardada aparte: sin ella, borrar el archivo se llevaría todo
/// el contenido del elemento.
bool _hasKeepableText(KnowledgeItem item) {
  const keepable = {
    SourceKind.youtube,
    SourceKind.audio,
    SourceKind.video,
    SourceKind.socialPost,
  };
  if (!keepable.contains(item.source.kind)) return false;
  // Sin archivo no hay nada que soltar: un video de YouTube cuyo audio no se
  // bajó —ya no se baja solo (F21)— tiene transcripción pero ningún archivo.
  if (item.source.originalFilePath == null) return false;

  return item.renditions.whereType<TextRendition>().any((r) => r.isPrimary);
}

/// El botón para soltar el archivo pesado y quedarse solo con el texto ya
/// extraído.
///
/// Vive justo debajo de donde ese archivo se está viendo o escuchando —ver
/// `EmbeddedFileViewer` en `_DetailBody`—, no al final de la procedencia:
/// es la acción que sigue naturalmente a mirarlo, no un dato más en una
/// lista de metadatos.
class _DeleteOriginalFileButton extends ConsumerWidget {
  const _DeleteOriginalFileButton({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => _deleteOriginalFile(context, ref, item),
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: Text(l10n.detailDeleteOriginalFile),
      ),
    );
  }
}

Future<void> _deleteOriginalFile(
  BuildContext context,
  WidgetRef ref,
  KnowledgeItem item,
) async {
  final l10n = AppLocalizations.of(context)!;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.detailDeleteOriginalFileConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.detailDelete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final relativePath = item.source.originalFilePath!;
  await ref.read(fileStoreProvider).delete(relativePath);

  final updated = item.copyWith(
    source: item.source.copyWith(originalFilePath: null),
  );
  final result = await ref.read(libraryRepositoryProvider).save(updated);
  if (!context.mounted) return;

  result.match(
    (failure) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(l10n)))),
    (_) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.detailOriginalFileDeleted))),
  );
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

/// Qué decir cuando todavía no hay contenido.
///
/// El mensaje cambia según de dónde vino el elemento, y no es un matiz: a
/// quien guardó un enlace le importa saber que el enlace está a salvo, y a
/// quien guardó un PDF le importa saber que el archivo está a salvo. Decirle
/// "el enlace sigue guardado" a alguien que nunca guardó un enlace suena a
/// mensaje equivocado, y hace dudar de si su documento sigue ahí.
String _emptyStateMessage(
  AppLocalizations l10n, {
  required KnowledgeItem item,
  required bool failed,
}) {
  final fromFile = item.source.originalFilePath != null;

  if (failed) {
    return fromFile
        ? l10n.detailExtractionFailedFile
        : l10n.detailExtractionFailed;
  }

  return fromFile ? l10n.detailNoContentYetFile : l10n.detailNoContentYet;
}

/// El nombre con el que el usuario reconoce su archivo.
///
/// En el almacén cada archivo vive en una carpeta con el identificador de su
/// fuente, así que el último tramo de la ruta ya es el nombre original: no
/// hay nada que recortar ni que adivinar.
String originalFileNameOf(String storedPath) => p.basename(storedPath);
