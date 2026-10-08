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

  /// Lo que se pidió hacer solo en tarjetas (F30), en orden.
  final flashcardRequests = <List<String>>[];

  @override
  void makeFlashcards(Iterable<String> itemIds, {bool anotherBatch = false}) =>
      flashcardRequests.add(itemIds.toList());

  /// Cuántas veces se la despertó: la llegada de un modelo la despierta.
  int wakes = 0;

  @override
  Future<void> wake() async => wakes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
