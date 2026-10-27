import 'package:uuid/uuid.dart';

/// El espacio de nombres de los ids de los documentos procesados: fijo, para
/// que el mismo id salga en cualquier dispositivo y en cualquier versión.
const _namespace = '3b0f8a52-2c71-4e0d-9a61-5d7f41c0e2b9';

/// El id del documento procesado de la fuente [sourceItemId] (F41, decisión
/// A): un UUID versión 5 —por nombre— de la fuente.
///
/// Que el id salga de la fuente, y no de un generador al azar, es lo que hace
/// cumplir «uno por fuente» también ENTRE dispositivos: dos bóvedas que
/// procesan la misma fuente cada una por su cuenta llegan al mismo elemento, y
/// la unión de bóvedas lo junta —con sus partes— en vez de traer un segundo
/// procesado que la restricción única de `processed_documents` no dejaría
/// entrar.
String processedDocumentIdFor(String sourceItemId) =>
    const Uuid().v5(_namespace, 'sinapsis/procesado/$sourceItemId');

/// El id de la forma que guarda la copia del original del procesado
/// [documentId] (decisión H): sale del documento por lo mismo que el suyo —dos
/// dispositivos que copian el original del mismo procesado llegan a la misma
/// forma, y la unión no trae una segunda—.
String processedOriginalRenditionIdFor(String documentId) =>
    const Uuid().v5(_namespace, 'sinapsis/procesado/original/$documentId');

/// Lo que antecede a la clave de estudio de un procesado: ver
/// [processedStudyKeyFor].
const kProcessedStudyKeyPrefix = 'procesado:';

/// La clave con que se estudia el texto propio del procesado [documentId]
/// (decisión I): hace las veces del `renditionId` de un `StudyText` para la
/// máquina de estudiar (`StudyRepository`), que con ella guarda y lee en el
/// procesado y no en `study_marks`.
String processedStudyKeyFor(String documentId) =>
    '$kProcessedStudyKeyPrefix$documentId';

/// El documento de la clave de estudio [key], o `null` si no es de un
/// procesado.
String? processedDocumentOfStudyKey(String key) =>
    key.startsWith(kProcessedStudyKeyPrefix)
    ? key.substring(kProcessedStudyKeyPrefix.length)
    : null;
