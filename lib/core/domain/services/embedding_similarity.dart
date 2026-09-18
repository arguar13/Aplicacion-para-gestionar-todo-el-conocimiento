import 'dart:math' as math;
import 'dart:typed_data';

/// Serializa un vector de embedding para guardarlo en `Embeddings.vector`
/// (blob) — `Float32List`, no `Float64List`: el modelo ya entrega
/// precisión simple, y guardar el doble de bytes por dimensión no suma
/// nada de precisión real.
Uint8List encodeEmbeddingVector(List<double> vector) {
  return Float32List.fromList(vector).buffer.asUint8List();
}

/// El inverso de [encodeEmbeddingVector].
///
/// `Float32List.sublistView`, no `Float32List.view(bytes.buffer)`: `.view`
/// exige que el offset del buffer esté alineado a 4 bytes, algo que no
/// está garantizado para un `Uint8List` que vuelve de sqlite3 vía Drift.
/// `sublistView` copia si hace falta y es la forma correcta para este
/// caso, documentada por el propio SDK de Dart.
List<double> decodeEmbeddingVector(Uint8List bytes) {
  return Float32List.sublistView(bytes);
}

/// Similitud coseno entre dos vectores de la misma dimensión: 1.0
/// idénticos en dirección, 0.0 ortogonales, -1.0 opuestos.
///
/// Función pura, sin dependencia de Drift ni de `flutter_gemma` —mismo
/// nivel de pureza que `ChunkingService`—, para que el motor de
/// relaciones (F5) pueda preseleccionar candidatos por similitud sin
/// necesitar ni la base ni el modelo cargados para probarlo.
///
/// Devuelve `0.0` si algún vector es todo ceros —dividir por una norma
/// cero no tiene un resultado con sentido, y `0.0` ("nada en común") es
/// más seguro que propagar un `NaN` a quien ordena candidatos por
/// puntaje.
double cosineSimilarity(List<double> a, List<double> b) {
  assert(
    a.length == b.length,
    'los vectores tienen que ser de la misma dimensión',
  );

  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  if (normA == 0 || normB == 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}

/// El centroide —promedio elemento a elemento— de una lista de vectores
/// de la misma dimensión: la similitud de un ítem contra otro se calcula
/// entre sus dos centroides, no par a par entre todos sus chunks (ver la
/// decisión sobre F5, D6) — más barato y suficiente porque el resultado
/// es solo una preselección; el LLM es quien de verdad juzga el vínculo
/// después.
List<double> centroid(List<List<double>> vectors) {
  assert(vectors.isNotEmpty, 'no hay centroide de una lista vacía');

  final dimension = vectors.first.length;
  final sum = List<double>.filled(dimension, 0);
  for (final vector in vectors) {
    for (var i = 0; i < dimension; i++) {
      sum[i] += vector[i];
    }
  }
  return [for (final value in sum) value / vectors.length];
}
