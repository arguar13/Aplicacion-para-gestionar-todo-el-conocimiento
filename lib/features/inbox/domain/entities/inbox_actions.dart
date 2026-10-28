import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// Qué se puede hacer con lo que está arriba del mazo, según su texto (F41):
/// un solo lugar para los botones, los gestos y las teclas.
///
/// «Descartar» siempre: no necesita leer nada. Triar —abrir la hoja «¿Qué va
/// a Procesado?»—, vincular a una nota viva y revisar lo que sugirió la IA
/// necesitan el texto —el propio o el de un archivo de su «Contenido»—.
/// Extraer una nota y «Pasar todo sin modificar», además, el del elemento: la
/// nota se corta de él (`extractableRendition`), y lo que se pasa entero a
/// «Procesado» es él, no un archivo de su «Contenido».
@immutable
class InboxActions {
  const InboxActions({
    required this.triage,
    required this.extract,
    required this.link,
    required this.review,
    required this.passUnchanged,
  });

  factory InboxActions.of(KnowledgeItem item, PendingText text) {
    final ready = text.isReady;
    final ownText =
        ready &&
        (extractableRendition(item)?.content.trim().isNotEmpty ?? false);
    return InboxActions(
      triage: ready,
      extract: ownText,
      link: ready,
      review: ready,
      passUnchanged: ownText,
    );
  }

  /// Sin nada a la vista: ninguna tecla hace nada.
  static const none = InboxActions(
    triage: false,
    extract: false,
    link: false,
    review: false,
    passUnchanged: false,
  );

  /// Abrir la hoja «¿Qué va a Procesado?».
  final bool triage;

  /// Abrir la hoja directo en el original, para sacarle notas.
  final bool extract;
  final bool link;
  final bool review;

  /// «Pasar todo sin modificar»: el texto original entero a «Procesado», sin
  /// abrir la hoja.
  final bool passUnchanged;
}
