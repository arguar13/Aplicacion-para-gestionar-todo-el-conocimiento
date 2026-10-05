// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// Un servicio de embeddings de mentira, para las pruebas que no están
/// probando `flutter_gemma` en sí.
///
/// [vectorFor] decide qué vector "calcula" para cada texto —por defecto,
/// uno determinístico a partir de la longitud del texto, así dos textos
/// distintos casi nunca terminan con el mismo vector por accidente en un
/// test que no se preocupa por vectores concretos.
class FakeEmbeddingService implements EmbeddingService {
  FakeEmbeddingService({
    List<double> Function(String text)? vectorFor,
    this.error,
  }) : vectorFor = vectorFor ?? _defaultVectorFor;

  final List<double> Function(String text) vectorFor;

  /// Si está, se lanza en vez de calcular nada.
  Object? error;

  /// Cada texto que se pidió embeber, en orden —individual o en lote—.
  final requests = <String>[];

  @override
  Future<List<double>> embed(String text) async {
    requests.add(text);
    final err = error;
    if (err != null) throw err;
    return vectorFor(text);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    requests.addAll(texts);
    final err = error;
    if (err != null) throw err;
    return texts.map(vectorFor).toList();
  }

  /// Cada búsqueda de la persona que se pidió embeber (F30), en orden.
  final queryRequests = <String>[];

  @override
  Future<List<double>> embedQuery(String text) async {
    queryRequests.add(text);
    final err = error;
    if (err != null) throw err;
    return vectorFor(text);
  }

  /// Cuántas veces se pidió sacarlo de la memoria.
  int releases = 0;

  @override
  Future<void> release({Duration? unusedFor}) async => releases++;

  static List<double> _defaultVectorFor(String text) {
    final length = text.length.toDouble();
    return [length, length / 2, length / 3];
  }
}
