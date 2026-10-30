import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';

/// Un pedido de ordenar con la IA el texto de un documento procesado (F45,
/// decisión B), con cuánto va: lo que se retoma si la app se cierra a mitad.
@immutable
class ProcessedTidyJob {
  const ProcessedTidyJob({
    required this.documentId,
    this.nextPage = 0,
    this.tidied = 0,
    this.kept = const {},
    this.unanswered = 0,
  });

  final String documentId;

  /// La primera página que falta mirar: las de antes ya se ordenaron, o se
  /// dejaron como se extrajeron.
  final int nextPage;

  /// Cuántos pedazos quedaron ordenados (o ya lo estaban).
  final int tidied;

  /// Cuántos pedazos se dejaron como se extrajeron, por qué.
  final Map<TidyProblem, int> kept;

  /// Cuántos pedazos se dejaron como se extrajeron porque la IA no contestó
  /// algo que se pudiera usar —un error de ese pedido, no de la conexión—.
  final int unanswered;

  /// Cuántos pedazos se dejaron como se extrajeron, en total.
  int get keptCount => kept.values.fold(unanswered, (sum, n) => sum + n);

  /// El pedido con una página más mirada: [tidiedNow] pedazos ordenados, y
  /// los demás dejados por [keptNow] o sin respuesta ([unansweredNow]).
  ProcessedTidyJob advanced({
    required int tidiedNow,
    Map<TidyProblem, int> keptNow = const {},
    int unansweredNow = 0,
  }) => ProcessedTidyJob(
    documentId: documentId,
    nextPage: nextPage + 1,
    tidied: tidied + tidiedNow,
    kept: {
      for (final problem in TidyProblem.values)
        if ((kept[problem] ?? 0) + (keptNow[problem] ?? 0) case final n
            when n > 0)
          problem: n,
    },
    unanswered: unanswered + unansweredNow,
  );

  @override
  bool operator ==(Object other) =>
      other is ProcessedTidyJob &&
      other.documentId == documentId &&
      other.nextPage == nextPage &&
      other.tidied == tidied &&
      other.unanswered == unanswered &&
      mapEquals(other.kept, kept);

  @override
  int get hashCode => Object.hash(
    documentId,
    nextPage,
    tidied,
    unanswered,
    Object.hashAllUnordered(
      kept.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Dónde se guardan los pedidos de ordenar que esperan o van a medias (F45,
/// decisión B): sobreviven a que la app se cierre, como la cola de
/// procesamiento (F21) y la de «Lo creado» (F43).
abstract interface class ProcessedTidyStore {
  /// Los pedidos que esperan, en el orden en que se hicieron.
  Future<List<ProcessedTidyJob>> pending();

  /// Guarda [job]: al final si es nuevo, en su lugar si ya estaba.
  Future<void> save(ProcessedTidyJob job);

  /// Saca el pedido de [documentId], si está.
  Future<void> remove(String documentId);
}
