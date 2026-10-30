import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// Desde cuánto parecido dos documentos «hablan de lo mismo» para la capa
/// «Parecidos» del Mapa (F44, paso 5): el mismo umbral con el que un cuaderno
/// con IA da a un candidato por muy cercano (`kNotebookStrongSimilarity`). Más
/// abajo, el mapa se llenaría de líneas entre cosas apenas emparentadas.
const kMapSimilarMinScore = 0.6;

/// Cuántos parecidos propone cada documento, como mucho: uno central no se
/// lleva todas las líneas.
const kMapSimilarPerDocument = 2;

/// Cuántos parecidos se dibujan, como mucho: es una propuesta para mirar de a
/// una, no una segunda red.
const kMapSimilarPairs = 30;

/// De dónde salen los parecidos del Mapa (F44, paso 5): los vectores que ya
/// guarda el teléfono (F30), sin red ni claves. Solo lee.
///
/// Devuelve los pares de los documentos pedidos que hablan de lo mismo y **no
/// están vinculados** —con ningún vínculo, en ningún sentido—, del más
/// parecido al menos, con los topes de arriba. Un documento sin vectores
/// todavía no entra.
///
/// Compara todos con todos fuera del hilo de la interfaz: quien lo llama pasa
/// los documentos a la vista, que son como mucho `kMaxGraphItems`.
typedef MapSimilarSource =
    Future<List<SimilarPair>> Function(List<String> itemIds);
