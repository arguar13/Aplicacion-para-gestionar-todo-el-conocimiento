import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

part 'cited_source.freezed.dart';

/// Un fragmento de una fuente que una nota viva usa a través de una nota
/// atómica: la atómica salió de ahí y la nota viva la enlaza.
@freezed
sealed class CitedFragment with _$CitedFragment {
  const factory CitedFragment({
    /// La nota atómica que se extrajo de la fuente.
    required String noteId,
    required String noteTitle,

    /// De dónde a dónde del texto de la fuente salió, si se guardó. Las
    /// extracciones de antes de que se guardara la posición no lo tienen.
    int? start,
    int? end,

    /// Si el texto de la fuente en esa posición tiene marca de tiempo —una
    /// transcripción— o página, en milisegundos y en número de página. Es lo
    /// que dice "en el minuto 12" o "en la página 4"; no todas las fuentes lo
    /// tienen.
    int? startMs,
    int? pageNumber,
  }) = _CitedFragment;
}

/// Una fuente que una nota viva cita, y cómo.
///
/// Una fuente cuenta de dos maneras, que se pueden dar a la vez: la nota la
/// cita ella misma ([isDirect]) o enlaza notas atómicas que salieron de ella
/// ([fragments]). En los dos casos es una fuente citada: lo primero no dice
/// dónde, lo segundo sí.
@freezed
sealed class CitedSource with _$CitedSource {
  const factory CitedSource({
    required String sourceId,
    required String title,
    required SourceKind sourceKind,
    required bool isDirect,
    required List<CitedFragment> fragments,
  }) = _CitedSource;
}
