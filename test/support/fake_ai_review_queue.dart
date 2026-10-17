import 'package:sinapsis/features/ai_organize/domain/services/ai_review_queue.dart';

/// La cola de «Revisar con otro modelo» de mentira (F33), para las pantallas
/// que solo le piden algo: lo que importa ahí es que pidan lo correcto —qué
/// elementos y si dejan afuera lo del mismo modelo—, no que la cola lo haga;
/// eso lo prueba `ai_review_queue_test.dart`.
///
/// Lo que no se usa en estas pruebas no está: llamarlo falla, en vez de
/// hacer como que anduvo.
class FakeAiReviewQueue implements AiReviewQueue {
  /// Lo que se pidió revisar, en orden.
  final requests = <({List<String> itemIds, bool skipOwnWork})>[];

  /// Los botones que se tocaron: `pause`, `resume`, `cancel`, `dismiss`.
  final actions = <String>[];

  @override
  void review(Iterable<String> itemIds, {bool skipOwnWork = true}) =>
      requests.add((itemIds: itemIds.toList(), skipOwnWork: skipOwnWork));

  @override
  void pause() => actions.add('pause');

  @override
  void resume() => actions.add('resume');

  @override
  void cancel() => actions.add('cancel');

  @override
  void dismiss() => actions.add('dismiss');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
