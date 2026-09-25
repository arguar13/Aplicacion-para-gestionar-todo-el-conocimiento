import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';

/// Abre la fuente de [card] en el fragmento del que salió (F11).
///
/// Es la lectura para destilar con el mismo salto que usan las notas
/// extraídas: baja hasta el rango y lo marca un momento. No hace nada si la
/// tarjeta no dice de dónde salió.
void openFlashcardSource(BuildContext context, Flashcard card) {
  if (!card.hasSourceRange) return;
  _openSourceRange(
    context,
    itemId: card.itemId,
    start: card.sourceCharStart!,
    end: card.sourceCharEnd!,
  );
}

/// Abre la fuente de [option] en el fragmento del que salió (F20).
///
/// A diferencia de [openFlashcardSource], el elemento no es fijo —una
/// opción de opción múltiple, por diseño, suele venir de OTRO elemento que
/// el de la tarjeta (`DistractorSourcer`)—: usa [FlashcardOption.sourceItemId],
/// no el `itemId` de la tarjeta a la que pertenece. No hace nada si la
/// opción no dice de dónde salió.
void openFlashcardOptionSource(BuildContext context, FlashcardOption option) {
  final itemId = option.sourceItemId;
  if (!option.hasSourceRange || itemId == null) return;
  _openSourceRange(
    context,
    itemId: itemId,
    start: option.sourceCharStart!,
    end: option.sourceCharEnd!,
  );
}

void _openSourceRange(
  BuildContext context, {
  required String itemId,
  required int start,
  required int end,
}) {
  context.push(RoutePaths.reading(itemId, start: start, end: end));
}
