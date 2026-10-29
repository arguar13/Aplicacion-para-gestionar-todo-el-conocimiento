import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

/// Cuánto va una creación: de 0 a 1, y en qué paso.
typedef CreationProgressReport =
    void Function(double progress, CreationStep step);

/// Lo que se le da a un generador: la creación tal como está guardada —su
/// tipo, sus opciones, su recorte, su idioma— y la señal para cortarla.
@immutable
class CreationJob {
  const CreationJob({required this.creation, required this.cancellation});

  final StudyCreation creation;

  /// Se cancela si la persona la cancela o la manda a la papelera: pasarla a
  /// [StructuredRequest.cancellation] corta lo que el modelo esté escribiendo.
  final CancellationSignal cancellation;

  StudyCreationKind get kind => creation.kind;
  Map<String, Object?> get options => creation.options;
  String get languageCode => creation.languageCode;
}

/// Lo que devuelve un generador: lo que se guarda en la creación.
@immutable
class CreationOutput {
  const CreationOutput({
    required this.title,
    required this.content,
    this.contentVersion = 1,
    this.sourceIds,
  });

  /// El título que puso la IA. En blanco, la fila muestra el nombre del tipo.
  final String title;

  /// El contenido, en el JSON del esquema del tipo (decisión G): lo que lee su
  /// visor. Nunca diseño: cambiar plantilla o estilo no vuelve a llamar a la
  /// IA.
  final String content;

  /// La versión de ese esquema.
  final int contentVersion;

  /// Las fuentes que de verdad se usaron, si no son las del material.
  final List<String>? sourceIds;
}

/// Quien genera un tipo de creación (F43, ola 3): un mapa mental, un informe,
/// una presentación… Vive en la carpeta de su tipo
/// (`lib/features/creations/<tipo>/`) con su instrucción, su esquema y su
/// lector, y se suma a la cola con UNA línea en `creationGeneratorsProvider`.
///
/// La cola (`CreationQueue`) le arma el material para que entre en la ventana
/// del modelo —con lo que dice [budgetFor]—, le da el modelo con el turno que
/// corresponde («Generar ahora» o «Generar más tarde») y guarda lo que
/// devuelve. El generador solo arma el pedido —normalmente un solo
/// [StructuredWriter.writeStructured]—, lee la respuesta y, si su tipo lo
/// necesita, hace algo después (el mazo guarda sus tarjetas en el procesado).
///
/// Las tres de extraer no tienen generador: no le piden nada a la IA
/// (decisión E).
abstract class CreationGenerator {
  const CreationGenerator();

  /// El tipo que genera.
  StudyCreationKind get kind;

  /// El tope de la respuesta final para [job]: lo que se le reserva en la
  /// ventana al armar el material.
  int maxOutputTokens(CreationJob job);

  /// Cuánto entra en la ventana de [contextTokens] para [job]. Por defecto,
  /// con [maxOutputTokens] reservado y la instrucción de siempre; un tipo con
  /// un esquema largo reserva más instrucción.
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: maxOutputTokens(job),
      );

  /// Genera [job] con [material] y [writer]. Lanza
  /// [UnreadableStructuredReply] si la IA no devolvió lo pedido y
  /// [CreationCancelledException] si se canceló; cualquier otra cosa es una
  /// falla. [progress] va de 0 a 1.
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  );
}
