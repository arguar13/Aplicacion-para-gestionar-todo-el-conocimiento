import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// Abre la fuente de [card] en el fragmento del que salió (F11).
///
/// Es la lectura para destilar con el mismo salto que usan las notas
/// extraídas: baja hasta el rango y lo marca un momento. No hace nada si la
/// tarjeta no dice de dónde salió.
void openFlashcardSource(BuildContext context, Flashcard card) {
  if (!card.hasSourceRange) return;
  context.push(
    RoutePaths.reading(
      card.itemId,
      start: card.sourceCharStart,
      end: card.sourceCharEnd,
    ),
  );
}
