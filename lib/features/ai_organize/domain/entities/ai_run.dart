import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';

part 'ai_run.freezed.dart';

/// Cuánto de cada cosa (F27): vínculos, tarjetas, propiedades, el tema de la
/// biblioteca, los datos de la referencia, los temas que ubicó en el árbol,
/// las notas mapa que escribió, los hechos fechados que puso en la línea de
/// tiempo (F40) y —en una pasada de revisión (F33)— las correcciones que la
/// persona le aceptó.
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

    /// Los temas sueltos que ubicó sola en el árbol (el Atlas): cada uno,
    /// bajo el padre que eligió. Lo que todavía es de la IA es lo que sigue
    /// donde ella lo puso.
    @Default(0) int topicPlacements,

    /// Las notas mapa que creó entera (el Atlas): 0 o 1 por pasada. Lo que
    /// la pasada le puso —su tema— va con ella y no se cuenta aparte. Deja de
    /// ser de la IA si la persona la editó o la borró.
    @Default(0) int mapNotes,

    /// Los hechos fechados que puso (F40), cada uno con su cita. Lo que
    /// todavía es de la IA es lo que la persona no editó ni quitó.
    @Default(0) int dates,

    /// Lo que la persona le aceptó a una pasada de revisión (F33): cada
    /// corrección o cada cosa que se sacó, de a una. Lo que todavía es de la
    /// IA es lo que sigue como la dejó la corrección.
    @Default(0) int corrections,
  }) = _AiRunTally;

  const AiRunTally._();

  int get total =>
      relations +
      flashcards +
      properties +
      spaces +
      referenceFields +
      topicPlacements +
      mapNotes +
      dates +
      corrections;

  bool get isEmpty => total == 0;

  /// Lo que «Revisar con otro modelo» (F33) puede mirar: las tarjetas, los
  /// vínculos, las etiquetas, el tema, los datos de la referencia y las notas
  /// mapa. No lo que ubicó en el árbol, ni los hechos fechados —cada uno ya
  /// trae su cita para revisarlo en la línea—, ni lo que ya corrigió una
  /// revisión.
  /// Alcanza para ofrecerlo; qué se revisa de verdad lo dice
  /// `AiRunRepository.reviewCandidates`.
  int get reviewable =>
      relations + flashcards + properties + spaces + referenceFields + mapNotes;

  AiRunTally operator +(AiRunTally other) => AiRunTally(
    relations: relations + other.relations,
    flashcards: flashcards + other.flashcards,
    properties: properties + other.properties,
    spaces: spaces + other.spaces,
    referenceFields: referenceFields + other.referenceFields,
    topicPlacements: topicPlacements + other.topicPlacements,
    mapNotes: mapNotes + other.mapNotes,
    dates: dates + other.dates,
    corrections: corrections + other.corrections,
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

    /// Qué le pidieron: organizar el elemento, solo tarjetas, revisarlo o
    /// analizarlo para estudiar (F39).
    @Default(AiRunScope.organize) AiRunScope scope,

    /// Cuánto trabajó el modelo en la pasada (F39, paso 6), sin las esperas
    /// por la cuota o la conexión. Cero en las de antes, que no lo guardaban.
    @Default(Duration.zero) Duration workTime,

    /// Los tokens que el modelo leyó y escribió, contados por quien los
    /// cuenta de verdad. Cero en las de antes.
    @Default(0) int inputTokens,
    @Default(0) int outputTokens,

    /// Lo que creó, contado al terminar: la historia, que no cambia.
    @Default(AiRunTally()) AiRunTally created,

    /// Lo que todavía es de la IA, contado al leer: lo que «deshacer todo» se
    /// llevaría hoy. Es menos que [created] si la persona adoptó —editó— o
    /// borró algo después.
    @Default(AiRunTally()) AiRunTally remaining,
  }) = _AiRun;

  const AiRun._();

  bool get isUndone => undoneAt != null;

  int get tokens => inputTokens + outputTokens;

  /// Si la pasada tiene algo que contar de lo que costó: tiempo o tokens.
  bool get hasUsage => workTime > Duration.zero || tokens > 0;

  /// Si la pasada organizó el elemento: la última de estas es la que dice si
  /// la persona se lo sacó a la IA. Las de solo tarjetas, la revisión y el
  /// análisis para estudiar no cuentan.
  bool get organizedItem => scope == AiRunScope.organize;
}
