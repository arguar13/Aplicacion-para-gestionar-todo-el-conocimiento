import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/highlight_card.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/design/selection_menu.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_edit_dialog.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/highlight_note_dialog.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
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

/// Crea una nota atómica nueva con `[start, end)` de [content], vinculada al
/// elemento [itemId] como su fuente.
///
/// Pasa por [captureItemUseCaseProvider] —el mismo camino de entrada que
/// cualquier captura manual— en vez de armar el `KnowledgeItem` a mano: así
/// la nota nueva recibe el mismo tratamiento (id, timestamps, guardado
/// atómico) que cualquier otra, sin duplicar esa lógica acá.
Future<void> extractRangeAsNote(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String content,
  required int start,
  required int end,
}) async {
  final excerpt = content.substring(start, end);

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
      SnackBar(
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
/// cada texto en los callbacks.
///
/// Cada botón cierra la barrita antes de actuar, como las opciones de
/// Flutter. Sin nada seleccionado, el menú común de la app.
Widget buildHighlightMenu(
  BuildContext context,
  WidgetRef ref,
  EditableTextState editable, {
  required void Function(HighlightColor color, HighlightStyle style)
  onHighlight,
  VoidCallback? onReadAloud,
  VoidCallback? onNote,
  VoidCallback? onExtract,
  VoidCallback? onCreateFlashcard,
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
    onHighlight: (color) {
      ContextMenuController.removeAny();
      onHighlight(color, HighlightStyle.fill);
    },
    onUnderline: (color) {
      ContextMenuController.removeAny();
      onHighlight(color, HighlightStyle.underline);
    },
    onCopy: copy == null ? null : closing(copy),
    onReadAloud: closingOrNull(onReadAloud),
    onNote: closingOrNull(onNote),
    onExtract: closingOrNull(onExtract),
    onCreateFlashcard: closingOrNull(onCreateFlashcard),
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
