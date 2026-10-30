import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/processed/data/repositories/prefs_processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';

/// Los pedidos de ordenar con la IA, en el teléfono (F45, decisión B): lo que
/// la cola retoma al volver a abrir la app.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('guarda los pedidos en orden, cada uno con cuánto va, y vuelven '
      'iguales al abrir de nuevo', () async {
    final store = PrefsProcessedTidyStore(prefs);
    await store.save(const ProcessedTidyJob(documentId: 'a'));
    await store.save(const ProcessedTidyJob(documentId: 'b'));
    await store.save(
      const ProcessedTidyJob(
        documentId: 'a',
        nextPage: 3,
        tidied: 7,
        kept: {TidyProblem.invented: 2, TidyProblem.missing: 1},
        unanswered: 1,
      ),
    );

    final again = await PrefsProcessedTidyStore(prefs).pending();
    expect(again, const [
      ProcessedTidyJob(
        documentId: 'a',
        nextPage: 3,
        tidied: 7,
        kept: {TidyProblem.invented: 2, TidyProblem.missing: 1},
        unanswered: 1,
      ),
      ProcessedTidyJob(documentId: 'b'),
    ]);
    expect(again.first.keptCount, 4);
  });

  test('sacar el último deja las preferencias limpias', () async {
    final store = PrefsProcessedTidyStore(prefs);
    await store.save(const ProcessedTidyJob(documentId: 'a'));
    await store.remove('a');
    await store.remove('nunca-estuvo');

    expect(await store.pending(), isEmpty);
    expect(prefs.containsKey(PrefsProcessedTidyStore.key), isFalse);
  });

  test('lo guardado roto no tumba la cola: se empieza sin pedidos', () async {
    await prefs.setString(PrefsProcessedTidyStore.key, '{no es json');
    expect(await PrefsProcessedTidyStore(prefs).pending(), isEmpty);

    await prefs.setString(
      PrefsProcessedTidyStore.key,
      '[{"document": 3}, "nada", {"document": "c", "next": "dos"}]',
    );
    expect(await PrefsProcessedTidyStore(prefs).pending(), const [
      ProcessedTidyJob(documentId: 'c'),
    ]);
  });
}
