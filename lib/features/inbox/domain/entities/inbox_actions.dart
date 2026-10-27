import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_text.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// Qué se puede hacer con lo que está arriba del mazo, según su texto (F41):
/// un solo lugar para los botones, los gestos y las teclas.
///
/// «Descartar» siempre: no necesita leer nada. Triar, vincular a una nota viva
/// y revisar lo que sugirió la IA necesitan el texto —el propio o el de un
/// archivo de su «Contenido»—; extraer una nota, además, el del elemento, que
/// es sobre el que trabaja la lectura para destilar (`extractableRendition`).
@immutable
class InboxActions {
  const InboxActions({
    required this.triage,
    required this.extract,
    required this.link,
    required this.review,
  });

  factory InboxActions.of(KnowledgeItem item, PendingText text) {
    final ready = text.isReady;
    return InboxActions(
      triage: ready,
      extract:
          ready &&
          (extractableRendition(item)?.content.trim().isNotEmpty ?? false),
      link: ready,
      review: ready,
    );
  }

  /// Sin nada a la vista: ninguna tecla hace nada.
  static const none = InboxActions(
    triage: false,
    extract: false,
    link: false,
    review: false,
  );

  final bool triage;
  final bool extract;
  final bool link;
  final bool review;
}
