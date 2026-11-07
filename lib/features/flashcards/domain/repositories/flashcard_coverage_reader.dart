import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';

/// Qué elementos pueden tener tarjetas y cuáles ya tienen (F30): lo que
/// cuenta la hoja de «Crear tarjetas con IA» antes de pedirlas.
@immutable
class FlashcardCoverage {
  const FlashcardCoverage({required this.eligible, required this.withCards});

  /// Los que pueden tener tarjetas —vivos, listos y con texto—, del más
  /// nuevo al más viejo.
  final List<String> eligible;

  /// De esos, los que ya tienen al menos una.
  final Set<String> withCards;

  /// Los que todavía no tienen ninguna, en el mismo orden.
  List<String> get withoutCards => [
    for (final id in eligible)
      if (!withCards.contains(id)) id,
  ];

  @override
  bool operator ==(Object other) =>
      other is FlashcardCoverage &&
      listEquals(other.eligible, eligible) &&
      setEquals(other.withCards, withCards);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(eligible), Object.hashAllUnordered(withCards));
}

/// Cuenta, para las tarjetas que hace la IA a pedido (F30), qué elementos
/// entran y cuáles ya tienen tarjetas.
///
/// **Pueden tener tarjetas** los elementos vivos —no en la papelera—, listos
/// —una nota, o una fuente ya procesada: lo que la IA que organiza sola
/// también toma— y con algún texto guardado: una foto sin texto leído o un
/// audio sin transcribir no tienen de dónde sacar preguntas.
abstract interface class FlashcardCoverageReader {
  /// Entre [itemIds] —o en toda la biblioteca, si es `null`—, los que
  /// pueden tener tarjetas y cuáles ya tienen.
  Future<Either<Failure, FlashcardCoverage>> coverageOf(
    Iterable<String>? itemIds,
  );

  /// Cuántos de [itemIds] pueden tener tarjetas y no tienen ninguna: lo que
  /// [coverageOf] daría en `withoutCards`, contado en UNA consulta aunque sean
  /// diez mil (F46, paso 5h). Lo que dice Repasar vacío de su recorte.
  ///
  /// Antes se contaba toda la biblioteca —también las notas y las fuentes—,
  /// y Repasar decía «58 elementos todavía no tienen tarjetas» con un recorte
  /// de 14 documentos.
  Future<Either<Failure, int>> withoutCardsCountOf(List<String> itemIds);

  /// Si hay alguna tarjeta, de un elemento vivo, le toque o no:
  /// actualizándose solo. Con alguna, Repasar vacío ofrece practicar igual.
  Stream<bool> watchHasCards();
}
