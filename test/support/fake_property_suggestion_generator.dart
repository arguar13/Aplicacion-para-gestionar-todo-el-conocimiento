// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'dart:async';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_generator.dart';

/// Un generador de sugerencias de propiedades de mentira, para probar
/// `ProcessItemUseCase` sin depender de `flutter_gemma` ni de la base.
class FakePropertySuggestionGenerator implements PropertySuggestionGenerator {
  FakePropertySuggestionGenerator({this.error});

  /// Cada `item.id` que se pidió generar, en orden.
  final calls = <String>[];

  /// Si está, `generate()` lo lanza en vez de completar normalmente.
  Object? error;

  /// Si está puesto, `generate()` espera este `Future` en vez de
  /// completar enseguida — para probar que `ProcessItemUseCase` de verdad
  /// no espera el resultado (fire-and-forget), no solo que no falla.
  Completer<void>? hang;

  @override
  Future<void> generate(KnowledgeItem item) async {
    calls.add(item.id);
    final hanging = hang;
    if (hanging != null) await hanging.future;
    final err = error;
    if (err != null) throw err;
  }
}
