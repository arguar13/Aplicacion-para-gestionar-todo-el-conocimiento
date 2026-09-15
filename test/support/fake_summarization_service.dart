import 'package:sinapsis/features/library/domain/services/summarization_service.dart';

/// Un resumidor de mentira, para las pruebas de pantalla que no están
/// probando `flutter_gemma` en sí.
class FakeSummarizationService implements SummarizationService {
  FakeSummarizationService({this.response, this.error});

  /// Lo que "contesta" [summarize]. Mutable a propósito.
  String? response;

  /// Si está, se lanza en vez de contestar.
  Object? error;

  /// Cada contenido que se pidió resumir, en orden.
  final summarized = <String>[];

  @override
  Future<String> summarize({required String content}) async {
    summarized.add(content);
    final err = error;
    // El doble lanza lo que el test le dé, y el tipo tiene que ser
    // `Object` porque `Exception` y `Error` no comparten más supertipo.
    // ignore: only_throw_errors
    if (err != null) throw err;
    return response ?? '';
  }
}
