import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';

/// La cola de la IA de mentira (F27), para las pantallas que solo le piden
/// algo: lo que importa ahí es que pidan lo correcto, no que la cola lo haga
/// —eso lo prueban `ai_organize_queue_test.dart` y la prueba de punta a
/// punta—. Con la de verdad, pedir «organizar ahora» con los modelos listos
/// arrancaría una pasada entera debajo de la prueba.
///
/// Lo que no se usa en estas pruebas no está: llamarlo falla, en vez de
/// hacer como que anduvo.
class FakeAiOrganizeQueue implements AiOrganizeQueue {
  /// Lo que se pidió organizar a mano, en orden.
  final organizeNowCalls = <String>[];

  @override
  void organizeNow(String itemId) => organizeNowCalls.add(itemId);

  @override
  void organizeAllNow(Iterable<String> itemIds) =>
      organizeNowCalls.addAll(itemIds);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
