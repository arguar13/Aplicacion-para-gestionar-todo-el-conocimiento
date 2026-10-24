import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/highlight_toolbar.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_selection_aloud.dart';
import 'package:sinapsis/features/organize/presentation/hand_highlighting.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/features/viewer/domain/services/pdf_study_pages.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_selection.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La barrita de resaltado (F38) sobre lo seleccionado en un documento real
/// —el PDF, la página web archivada—: la misma [HighlightToolbar] de «Texto
/// extraído» y del lector, con cada botón llevado a [selection].
///
/// [context] es el de la pantalla, no el de la barrita: la barrita deja de
/// existir cuando la selección se quita, y un diálogo o un aviso que se abre
/// después tiene que tener dónde. [anchors] son los bordes de la selección
/// en el lugar donde se dibuja la barrita.
///
/// Lo que se hace con lo elegido es en el texto extraído [text]: ahí se
/// guardan los resaltados, y de ahí salen la nota extraída y la tarjeta. Lo
/// que no se pudo ubicar ahí —una página escaneada, un texto que se volvió a
/// extraer— se avisa y no se hace. Copiar y Escuchar usan lo que se ve, así
/// que andan igual.
Widget documentHighlightToolbar(
  BuildContext context,
  WidgetRef ref, {
  required TextSelectionToolbarAnchors anchors,
  required DocumentSelection selection,
  required StudyText text,
  bool canCopy = true,
  double systemToolbarExtent = 0,
  List<HighlightToolbarAction> moreActions = const [],
}) {
  void highlight(HighlightColor color, HighlightStyle style) {
    ref.read(lastHighlightColorProvider.notifier).state = color;
    unawaited(
      highlightAndReport(context, selection, color: color, style: style),
    );
  }

  return HighlightToolbar(
    anchors: anchors,
    systemToolbarExtent: systemToolbarExtent,
    underlineColor: ref.read(lastHighlightColorProvider),
    onHighlight: (color) => highlight(color, HighlightStyle.fill),
    onUnderline: (color) => highlight(color, HighlightStyle.underline),
    // Un PDF puede no dejar copiar su texto.
    onCopy: !canCopy
        ? null
        : () => unawaited(() async {
            await Clipboard.setData(
              ClipboardData(text: await selection.text()),
            );
            await selection.clear();
          }()),
    onReadAloud: () => unawaited(() async {
      final selected = await selection.text();
      await selection.clear();
      await readSelectionAloud(ref, text: selected);
    }()),
    onNote: () => unawaited(() async {
      if (await _located(context, selection) == null) return;
      final excerpt = await selection.text();
      if (!context.mounted) return;
      final note = await askHighlightNote(context, excerpt: excerpt);
      if (note == null || !context.mounted) return;
      await highlightAndReport(
        context,
        selection,
        color: ref.read(lastHighlightColorProvider),
        note: note.text,
      );
    }()),
    onExtract: () => unawaited(() async {
      final range = await _located(context, selection);
      if (range == null || !context.mounted) return;
      await selection.clear();
      if (!context.mounted) return;
      await extractRangeAsNote(
        context,
        ref,
        itemId: text.itemId,
        content: text.content,
        start: range.start,
        end: range.end,
      );
    }()),
    onCreateFlashcard: () => unawaited(() async {
      final range = await _located(context, selection);
      if (range == null || !context.mounted) return;
      await selection.clear();
      if (!context.mounted) return;
      await createFlashcardFromRange(
        context,
        ref,
        itemId: text.itemId,
        content: text.content,
        start: range.start,
        end: range.end,
      );
    }()),
    moreActions: moreActions,
  );
}

/// Dónde cae lo elegido en el texto extraído, de la primera letra a la
/// última —en un PDF, la selección que cruza páginas da un tramo por página—,
/// o `null` después de decir por qué no se pudo ubicar.
Future<TextSlice?> _located(
  BuildContext context,
  DocumentSelection selection,
) async {
  final location = await selection.locate();
  if (!context.mounted) return null;
  if (location.issue case final issue?) {
    final message = highlightIssueMessage(
      AppLocalizations.of(context)!,
      HighlightOutcome.issue(issue),
    );
    if (message != null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    return null;
  }
  return (start: location.slices.first.start, end: location.slices.last.end);
}
