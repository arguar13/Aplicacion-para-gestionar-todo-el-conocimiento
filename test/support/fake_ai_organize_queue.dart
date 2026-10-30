import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';

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

  /// Los documentos procesados que se triaron y se pasaron a organizar (F41,
  /// paso 6), en orden.
  final processedForOrganizing = <String>[];

  @override
  void enqueueProcessedForOrganizing(String documentId) =>
      processedForOrganizing.add(documentId);

  /// Lo que se pidió hacer solo en tarjetas (F30), en orden, y con qué: si
  /// era otra tanda y el estilo de la hoja (F43, M18).
  final flashcardRequests = <List<String>>[];
  final flashcardOptions = <({bool anotherBatch, FlashcardStyle style})>[];

  @override
  void makeFlashcards(
    Iterable<String> itemIds, {
    bool anotherBatch = false,
    FlashcardStyle style = FlashcardStyle.plain,
  }) {
    flashcardRequests.add(itemIds.toList());
    flashcardOptions.add((anotherBatch: anotherBatch, style: style));
  }

  /// Lo que se pidió buscar solo en fechas (F40), en orden.
  final dateRequests = <List<String>>[];

  @override
  void findDates(Iterable<String> itemIds) =>
      dateRequests.add(itemIds.toList());

  /// Cuántas veces se cancelaron y se cerraron los pedidos de fechas.
  int datesCancelled = 0;
  int datesDismissed = 0;

  @override
  void cancelDates() => datesCancelled++;

  @override
  void dismissDates() => datesDismissed++;

  /// Cuántas veces se la despertó: la llegada de un modelo la despierta.
  int wakes = 0;

  @override
  Future<void> wake() async => wakes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
