import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/highlight_card.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlight_note_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/entities/extract_note_target.dart';
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_seed.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/timeline_navigation.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/dated_event_form.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// Resaltar a mano sobre el texto extraído (F38): lo que comparten
// «Texto extraído» y el lector de Word, EPUB y texto. Cada uno sabe traducir
// su selección a un tramo del contenido de la forma de texto —cada uno
// con sus posiciones—; lo que viene después de eso es igual en los dos y vive
// acá, en vez de dos veces.
//
// Trabajan con tramos `[start, end)` del **contenido crudo** [content] de
// la forma de texto [renditionId]: las mismas posiciones que guardan los
// resaltados, las notas extraídas y las tarjetas.

/// El último color que se eligió para resaltar: el que usa «Subrayar» (F38).
/// Al abrir la app, el primero.
final lastHighlightColorProvider = StateProvider<HighlightColor>(
  (ref) => HighlightColor.values.first,
);

/// Resalta `[start, end)` de [content] con [color] y [style], y recuerda
/// [color] como el último elegido. Si algo falla, lo dice.
Future<void> saveHandHighlight(
  BuildContext context,
  WidgetRef ref, {
  required String renditionId,
  required String content,
  required int start,
  required int end,
  required HighlightColor color,
  HighlightStyle style = HighlightStyle.fill,
  String? note,
}) async {
  if (end <= start || end > content.length) return;
  ref.read(lastHighlightColorProvider.notifier).state = color;
  final result = await ref
      .read(organizeRepositoryProvider)
      .createHighlight(
        renditionId: renditionId,
        startOffset: start,
        endOffset: end,
        excerpt: content.substring(start, end),
        note: note,
        color: color,
        style: style,
      );
  if (!context.mounted) return;
  final failure = result.getLeft().toNullable();
  if (failure != null) {
    _say(context, failure.localizedMessage(AppLocalizations.of(context)!));
  }
}

/// «Nota»: pide la nota y resalta `[start, end)` con el último color
/// elegido. Cancelar el diálogo no resalta nada; una nota en blanco sí
/// resalta —resaltar sin explicar por qué es perfectamente legítimo—, sin
/// nota.
Future<void> saveHandHighlightWithNote(
  BuildContext context,
  WidgetRef ref, {
  required String renditionId,
  required String content,
  required int start,
  required int end,
}) async {
  if (end <= start || end > content.length) return;
  final note = await askHighlightNote(
    context,
    excerpt: content.substring(start, end),
  );
  if (note == null || !context.mounted) return;
  await saveHandHighlight(
    context,
    ref,
    renditionId: renditionId,
    content: content,
    start: start,
    end: end,
    color: ref.read(lastHighlightColorProvider),
    note: note.text,
  );
}

/// Pide la nota de un resaltado nuevo de [excerpt]: `null` si se canceló;
/// si no, la nota, que en blanco es ninguna.
Future<({String? text})?> askHighlightNote(
  BuildContext context, {
  required String excerpt,
}) async {
  final note = await showDialog<String>(
    context: context,
    builder: (context) =>
        HighlightNoteDialog(initialNote: null, excerpt: excerpt),
  );
  return note == null ? null : (text: note.isEmpty ? null : note);
}

/// «Extraer como nota»: `[start, end)` de [content] —el texto de la forma
/// [renditionId] de [itemId]— como nota. Adónde va lo decide qué es [itemId],
/// no la pantalla (F41, decisiones C y J); así cada visor que ofrece «Extraer
/// como nota» lo hace bien sin saber de Procesado:
///
/// - **Mientras se tría** («Cortar del original»), a las notas de la hoja
///   «¿Qué va a Procesado?», que se guardan con ella.
/// - **De una fuente**, a las notas de su documento procesado, que nace con
///   esa nota si no existía, sin triar la fuente (`ExtractNoteToProcessed`).
///   El aviso dice «Nota guardada en Procesado», con «Ver» y «Deshacer».
/// - **De una fuente en la papelera**, nada: lo dice y ofrece restaurarla.
/// - **De un documento procesado**, a sus propias notas.
/// - **De una nota propia**, una nota atómica suelta, vinculada a ella como
///   su fuente: ver [_extractAsLooseNote].
Future<void> extractRangeAsNote(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String renditionId,
  required String content,
  required int start,
  required int end,
}) async {
  if (start < 0 || end <= start || end > content.length) return;
  final excerpt = content.substring(start, end);
  if (processedCutterFor(ref, itemId) case final cutter?) {
    final added = cutter.extractNote(
      ProcessedAnchor(renditionId: renditionId, start: start, end: end),
      excerpt: excerpt,
    );
    final l10n = AppLocalizations.of(context)!;
    _say(
      context,
      added ? l10n.processedCutNoteAdded : l10n.processedCutRepeated,
    );
    return;
  }

  final routed = await ref.read(extractNoteToProcessedProvider)(
    itemId: itemId,
    renditionId: renditionId,
    start: start,
    end: end,
    excerpt: excerpt,
  );
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  if (routed.getLeft().toNullable() case final failure?) {
    _say(context, failure.localizedMessage(l10n));
    return;
  }
  switch (routed.getRight().toNullable()!) {
    case ExtractLooseNote():
      await _extractAsLooseNote(
        context,
        ref,
        itemId: itemId,
        excerpt: excerpt,
        start: start,
        end: end,
      );
    case ExtractRefusedInTrash(:final sourceItemId):
      _offerRestore(context, ref, sourceItemId);
    case final ExtractedToProcessed saved when saved.unchanged:
      _say(context, l10n.processedCutRepeated);
    case final ExtractedToProcessed saved:
      _announceProcessedNote(context, ref, saved);
  }
}

/// «Nota guardada en Procesado», con «Ver» —abre el documento procesado— y
/// «Deshacer» —saca esa nota sola, y el documento si nació para ella—.
///
/// Lo que usan los botones se resuelve ahora: el aviso puede tocarse después
/// de cerrada la pantalla que extrajo. «Ver» usa el router de esa pantalla, y
/// sin uno —un visor suelto, fuera de la app— no se ofrece.
void _announceProcessedNote(
  BuildContext context,
  WidgetRef ref,
  ExtractedToProcessed saved,
) {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.maybeOf(context);
  final extract = ref.read(extractNoteToProcessedProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      AppSnackBar(
        content: Row(
          children: [
            Expanded(child: Text(l10n.processedNoteSaved)),
            if (router != null)
              TextButton(
                key: const Key('processed-note-view'),
                style: TextButton.styleFrom(
                  foregroundColor:
                      theme.snackBarTheme.actionTextColor ??
                      theme.colorScheme.inversePrimary,
                ),
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  unawaited(
                    router.push(RoutePaths.processedDocument(saved.documentId)),
                  );
                },
                child: Text(l10n.detailExtractedNoteView),
              ),
          ],
        ),
        action: SnackBarAction(
          label: l10n.inboxUndo,
          onPressed: () => unawaited(() async {
            final undone = await extract.undo(saved.undo);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    undone.match(
                      (failure) => failure.localizedMessage(l10n),
                      (_) => l10n.processedNoteUndone,
                    ),
                  ),
                ),
              );
          }()),
        ),
      ),
    );
}

/// Una fuente en la papelera no acepta notas (decisión J): lo dice y ofrece
/// restaurarla.
void _offerRestore(BuildContext context, WidgetRef ref, String sourceItemId) {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final library = ref.read(libraryRepositoryProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      AppSnackBar(
        content: Text(l10n.processedNoteSourceInTrash),
        action: SnackBarAction(
          label: l10n.trashRestore,
          onPressed: () => unawaited(() async {
            final restored = await library.restore(sourceItemId);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    restored.match(
                      (failure) => failure.localizedMessage(l10n),
                      (_) => l10n.processedNoteSourceRestored,
                    ),
                  ),
                ),
              );
          }()),
        ),
      ),
    );
}

/// Una nota atómica nueva con [excerpt] —`[start, end)` del texto de
/// [itemId]—, vinculada a [itemId] como su fuente: lo que se extrae de una
/// nota propia, que no tiene documento procesado.
///
/// Pasa por [captureItemUseCaseProvider] —el mismo camino de entrada que
/// cualquier captura manual— en vez de armar el `KnowledgeItem` a mano: así
/// la nota nueva recibe el mismo tratamiento (id, timestamps, guardado
/// atómico) que cualquier otra, sin duplicar esa lógica acá.
Future<void> _extractAsLooseNote(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String excerpt,
  required int start,
  required int end,
}) async {
  final result = await ref.read(captureItemUseCaseProvider)(
    CaptureRequest.text(rawInput: excerpt),
  );
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;

  final failure = result.getLeft().toNullable();
  if (failure != null) {
    _say(context, failure.localizedMessage(l10n));
    return;
  }
  final newItem = result.getRight().toNullable()!;

  await ref
      .read(organizeRepositoryProvider)
      .createRelation(
        fromItemId: newItem.id,
        toItemId: itemId,
        kind: RelationKind.extractedFrom,
        // De dónde salió: con esto la nota lleva de vuelta al lugar exacto.
        sourceCharStart: start,
        sourceCharEnd: end,
      );
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      AppSnackBar(
        content: Text(l10n.detailExtractedNoteCreated(newItem.title)),
        action: SnackBarAction(
          label: l10n.detailExtractedNoteView,
          onPressed: () {
            if (context.mounted) {
              context.push(RoutePaths.itemDetail(newItem.id));
            }
          },
        ),
      ),
    );
}

/// «A Procesado» (F41): manda `[start, end)` de [content] —el texto de la
/// forma [renditionId]— a los fragmentos del documento procesado de
/// [itemId], en la hoja «¿Qué va a Procesado?». Solo hace algo mientras se
/// corta de esa fuente (ver `processedCutSourceProvider`); un pasaje que ya
/// estaba cortado no entra dos veces, y lo avisa.
void cutRangeToProcessed(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String renditionId,
  required String content,
  required int start,
  required int end,
}) {
  if (start < 0 || end <= start || end > content.length) return;
  final cutter = processedCutterFor(ref, itemId);
  if (cutter == null) return;
  final excerpt = content.substring(start, end);
  if (excerpt.trim().isEmpty) return;
  final added = cutter.cut(
    ProcessedAnchor(renditionId: renditionId, start: start, end: end),
    excerpt: excerpt,
  );
  if (!added) {
    _say(context, AppLocalizations.of(context)!.processedCutRepeated);
  }
}

/// Si se está cortando de [itemId] para Procesado: entonces la barrita
/// ofrece «A Procesado».
bool cuttingForProcessed(WidgetRef ref, String itemId) =>
    processedCutterFor(ref, itemId) != null;

/// Crea una tarjeta de repaso con `[start, end)` de [content] como respuesta
/// (F11): la pregunta la escribe la persona, y la tarjeta guarda el rango del
/// que salió, para poder volver a él desde el repaso.
Future<void> createFlashcardFromRange(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String content,
  required int start,
  required int end,
}) async {
  if (end <= start) return;
  final answer = await showFlashcardEditDialog(
    context,
    initialBack: content.substring(start, end),
  );
  if (answer == null || !context.mounted) return;
  final (front, back) = answer;

  final result = await ref
      .read(flashcardRepositoryProvider)
      .create(
        itemId: itemId,
        front: front,
        back: back,
        sourceCharStart: start,
        sourceCharEnd: end,
      );
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;

  _say(
    context,
    result.match(
      (failure) => failure.localizedMessage(l10n),
      (_) => l10n.flashcardsCreatedFromSelection,
    ),
  );
}

/// Convierte `[start, end)` de [content] en un hecho de la línea de tiempo
/// (F40): abre el formulario con la cita ya puesta —la forma de texto, las
/// posiciones y el fragmento, como las de un resaltado o una tarjeta— y, si lo
/// seleccionado trae una fecha («en 1859», «siglo XV»), con la fecha cargada
/// (y su fin, si es un rango): solo falta confirmar el título. Si no trae
/// fecha, el formulario abre vacío en ella.
///
/// Al guardar avisa, con un «Ver» que abre la línea de tiempo en ese documento.
///
/// La línea de tiempo se arma con lo procesado (F41, paso 6): lo que se
/// selecciona en una fuente va a su documento procesado, con la cita en la
/// fuente —donde está el texto—. Si la fuente todavía no se procesó, lo dice y
/// lleva a la Bandeja: el hecho no se vería en la línea.
Future<void> addRangeToTimeline(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String renditionId,
  required String content,
  required int start,
  required int end,
}) async {
  if (start < 0 || end <= start || end > content.length) return;
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.maybeOf(context);
  final documentId = await _timelineDocumentOf(ref, itemId);
  if (!context.mounted) return;
  if (documentId == null) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        AppSnackBar(
          content: Text(l10n.timelineFactSourceNotProcessed),
          action: router == null
              ? null
              : SnackBarAction(
                  label: l10n.organizedGoToInbox,
                  onPressed: () => router.go(RoutePaths.inbox),
                ),
        ),
      );
    return;
  }
  final seed = DatedEventSeed.fromQuote(
    itemId: documentId,
    renditionId: renditionId,
    content: content,
    start: start,
    end: end,
  );
  final saved = await showDatedEventForm(context, seed: seed);
  if (!saved || !context.mounted) return;
  final title = await _documentTitle(ref, documentId);
  if (!context.mounted) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      AppSnackBar(
        content: Text(l10n.timelineFactAdded),
        action: SnackBarAction(
          label: l10n.timelineFactAddedSee,
          onPressed: () {
            if (!context.mounted) return;
            showInTimeline(
              context,
              ref,
              TimelineScope.document(itemId: documentId, label: title),
            );
          },
        ),
      ),
    );
}

/// De qué elemento es un hecho que se agrega desde el texto de [itemId] (F41,
/// paso 6): de una fuente, su documento procesado —`null` si todavía no lo
/// tiene—; de una nota o un procesado, él mismo.
Future<String?> _timelineDocumentOf(WidgetRef ref, String itemId) async {
  final item = await ref.read(libraryItemProvider(itemId).future);
  if (item == null) return null;
  if (item.source.kind.role != EntityRole.source) return item.id;
  // El id del procesado sale de la fuente (`processedDocumentIdFor`): se
  // pregunta por él, sin traer el documento.
  final documentId = processedDocumentIdFor(itemId);
  final status =
      (await ref.read(processedRepositoryProvider).statusOf(documentId))
          .getRight()
          .toNullable();
  return status == ProcessedDocumentStatus.active ? documentId : null;
}

/// El título de [itemId], para rotular el chip de la línea de tiempo.
Future<String> _documentTitle(WidgetRef ref, String itemId) async {
  final item = await ref.read(libraryItemProvider(itemId).future);
  return item?.title ?? '';
}

/// Abre la ficha de [highlight] (F38): cambiarle el color o el estilo,
/// escribirle la nota o quitarlo.
Future<void> openHighlightCard(
  BuildContext context,
  WidgetRef ref,
  Highlight highlight,
) {
  // Antes de abrir: la ficha puede cerrarse después de que quien la abrió ya
  // no esté.
  final repository = ref.read(organizeRepositoryProvider);
  return showHighlightCard(
    context,
    highlight: highlight,
    onLook: (color, style) async {
      await repository.updateHighlightLook(
        id: highlight.id,
        color: color,
        style: style,
      );
    },
    onNote: (note) async {
      await repository.updateHighlightNote(id: highlight.id, note: note);
    },
    onDelete: () async {
      await repository.deleteHighlight(highlight.id);
    },
  );
}

/// El resaltado que toca la posición [offset] del contenido —donde la
/// persona tocó—, o `null`. Si hay uno que la rodea por los dos lados, ese;
/// si no, el que empieza o termina justo ahí: un toque en la mitad de la
/// última letra cae en su borde.
Highlight? highlightAt(Iterable<Highlight> highlights, int offset) {
  Highlight? edge;
  for (final highlight in highlights) {
    if (highlight.startOffset < offset && offset < highlight.endOffset) {
      return highlight;
    }
    if (highlight.startOffset == offset || highlight.endOffset == offset) {
      edge ??= highlight;
    }
  }
  return edge;
}

/// Los subrayados de [highlights] que tocan `[from, to)` del contenido, como
/// los pinta `RenderedMarkdown.buildSpans`: recortados a ese tramo y contados
/// desde [from] —lo que cae en una página del lector—, cada uno con su color
/// (el de siempre si no eligió ninguno) y su estilo.
List<HandMark> handMarks(
  BuildContext context,
  Iterable<Highlight> highlights, {
  required int to,
  int from = 0,
}) => [
  for (final highlight in highlights)
    if (highlight.endOffset > from && highlight.startOffset < to)
      HandMark(
        (highlight.startOffset < from ? from : highlight.startOffset) - from,
        (highlight.endOffset > to ? to : highlight.endOffset) - from,
        // Una línea de un tono de resaltador clarísimo no se vería.
        color: switch (highlight.style) {
          HighlightStyle.fill => HighlightPalette.resolve(
            context,
            highlight.color,
          ),
          HighlightStyle.underline => HighlightPalette.line(
            context,
            highlight.color,
          ),
        },
        style: highlight.style,
      ),
];

/// La barrita de resaltado de un texto seleccionable (F38): la de
/// [HighlightToolbar] puesta junto a la selección de [editable], con Copiar,
/// Compartir, Seleccionar todo y Buscar en la Web de siempre, y lo propio de
/// cada texto en los callbacks (también «A la línea de tiempo», F40, y,
/// mientras se corta del original, «A Procesado», F41).
///
/// Cada botón cierra la barrita antes de actuar, como las opciones de
/// Flutter. Sin nada seleccionado, el menú común de la app.
///
/// Con [readOnly] —la copia del original de un documento procesado, ver
/// `isReadOnlyStudyKey`— la barrita queda con lo que ahí se puede hacer:
/// copiar, escuchar y «Extraer como nota». Sin colores, sin nota, sin tarjeta
/// y sin línea de tiempo: no hay forma de texto donde caigan.
Widget buildHighlightMenu(
  BuildContext context,
  WidgetRef ref,
  EditableTextState editable, {
  required void Function(HighlightColor color, HighlightStyle style)
  onHighlight,
  bool readOnly = false,
  VoidCallback? onReadAloud,
  VoidCallback? onNote,
  VoidCallback? onExtract,
  VoidCallback? onCreateFlashcard,
  VoidCallback? onAddToTimeline,
  VoidCallback? onToProcessed,
}) {
  final value = editable.textEditingValue;
  final selected = value.selection.isValid
      ? value.selection.textInside(value.text).trim()
      : '';
  if (selected.isEmpty) {
    return buildSelectionMenu(context, editable);
  }

  ContextMenuButtonItem? fromFlutter(ContextMenuButtonType type) {
    for (final item in editable.contextMenuButtonItems) {
      if (item.type == type) return item;
    }
    return null;
  }

  VoidCallback closing(VoidCallback action) => () {
    ContextMenuController.removeAny();
    action();
  };
  VoidCallback? closingOrNull(VoidCallback? action) =>
      action == null ? null : closing(action);

  final copy = fromFlutter(ContextMenuButtonType.copy)?.onPressed;
  return HighlightToolbar(
    anchors: editable.contextMenuAnchors,
    underlineColor: ref.read(lastHighlightColorProvider),
    onHighlight: readOnly
        ? null
        : (color) {
            ContextMenuController.removeAny();
            onHighlight(color, HighlightStyle.fill);
          },
    onUnderline: readOnly
        ? null
        : (color) {
            ContextMenuController.removeAny();
            onHighlight(color, HighlightStyle.underline);
          },
    onCopy: copy == null ? null : closing(copy),
    onReadAloud: closingOrNull(onReadAloud),
    onNote: readOnly ? null : closingOrNull(onNote),
    onExtract: closingOrNull(onExtract),
    onCreateFlashcard: readOnly ? null : closingOrNull(onCreateFlashcard),
    onAddToTimeline: readOnly ? null : closingOrNull(onAddToTimeline),
    onToProcessed: closingOrNull(onToProcessed),
    moreActions: [
      for (final type in const [
        ContextMenuButtonType.share,
        ContextMenuButtonType.selectAll,
      ])
        if (fromFlutter(type) case final item?)
          HighlightToolbarAction(
            label: AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
            onPressed: item.onPressed ?? () {},
          ),
      HighlightToolbarAction(
        label: AdaptiveTextSelectionToolbar.getButtonLabel(
          context,
          const ContextMenuButtonItem(
            type: ContextMenuButtonType.searchWeb,
            onPressed: null,
          ),
        ),
        onPressed: closing(() => unawaited(searchWeb(selected))),
      ),
    ],
  );
}

void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));
