import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_run.freezed.dart';

/// Cuánto de cada cosa (F27): vínculos, tarjetas, propiedades, el tema de la
/// biblioteca y los datos de la referencia.
@freezed
sealed class AiRunTally with _$AiRunTally {
  const factory AiRunTally({
    @Default(0) int relations,
    @Default(0) int flashcards,
    @Default(0) int properties,

    /// El tema de la biblioteca —el espacio— que puso: 0 o 1 por pasada.
    @Default(0) int spaces,

    /// Los datos de la referencia que completó: autor, editorial, año…, de a
    /// uno.
    @Default(0) int referenceFields,
  }) = _AiRunTally;

  const AiRunTally._();

  int get total =>
      relations + flashcards + properties + spaces + referenceFields;

  bool get isEmpty => total == 0;

  AiRunTally operator +(AiRunTally other) => AiRunTally(
    relations: relations + other.relations,
    flashcards: flashcards + other.flashcards,
    properties: properties + other.properties,
    spaces: spaces + other.spaces,
    referenceFields: referenceFields + other.referenceFields,
  );
}

/// Una pasada de la IA sobre un elemento (F27), como la muestra «Lo que hizo
/// la IA».
@freezed
sealed class AiRun with _$AiRun {
  const factory AiRun({
    required String id,
    required String itemId,

    /// El título del elemento, para mostrarla sin otra consulta.
    required String itemTitle,
    required DateTime startedAt,

    /// `null` mientras sigue, o si se cortó a mitad.
    DateTime? finishedAt,

    /// Cuándo la persona la deshizo entera. `null` = sigue en pie.
    DateTime? undoneAt,

    /// Qué modelo trabajó, si se sabe.
    String? model,

    /// Lo que creó, contado al terminar: la historia, que no cambia.
    @Default(AiRunTally()) AiRunTally created,

    /// Lo que todavía es de la IA, contado al leer: lo que «deshacer todo» se
    /// llevaría hoy. Es menos que [created] si la persona adoptó —editó— o
    /// borró algo después.
    @Default(AiRunTally()) AiRunTally remaining,
  }) = _AiRun;

  const AiRun._();

  bool get isUndone => undoneAt != null;
}
