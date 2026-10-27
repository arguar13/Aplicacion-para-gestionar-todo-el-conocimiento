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
/// la unión
/// de bóvedas lo junta —con sus partes— en vez de traer un segundo procesado
/// que la restricción única de `processed_documents` no dejaría entrar.
String processedDocumentIdFor(String sourceItemId) =>
    const Uuid().v5(_namespace, 'sinapsis/procesado/$sourceItemId');
