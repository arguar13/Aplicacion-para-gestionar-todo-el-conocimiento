import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/fake_embedding_service.dart';
import '../../../../support/item_rows.dart';

/// Los vectores de las notas (F27): calculados por tramo, guardados como los
/// de las fuentes, y con ellos una nota es candidata a un vínculo igual que
/// una fuente.
void main() {
  late AiOrganizeHarness vault;
  late FakeEmbeddingService embeddings;
  late ChunkEmbeddingIndexerImpl indexer;
  late RelationCandidateSelectorImpl selector;

  setUp(() {
    vault = AiOrganizeHarness();
    embeddings = FakeEmbeddingService(
      vectorFor: (text) => text.contains('Senado') ? [1, 0] : [0, 1],
    );
    indexer = ChunkEmbeddingIndexerImpl(
      database: vault.db,
      embeddings: embeddings,
      clock: vault.clock,
    );
    selector = RelationCandidateSelectorImpl(database: vault.db);
  });

  tearDown(() => vault.close());

  const ending = 'El final de la nota. El final de la nota. El final.';
  const otherEnding = 'Otro final distinto. Otro final distinto. Otro.';

  /// Un texto de [pieces] tramos: cada párrafo llena casi uno, y el último
  /// ya no entra con el anterior.
  String longText(int pieces, {String last = ending}) => [
    for (var i = 0; i < pieces - 1; i++)
      'Párrafo $i sobre el Senado. ${'Una idea. ' * 195}',
    last,
  ].join('\n\n');

  Future<List<int>> storedSeqs(String itemId) async => [
    for (final row in await (vault.db.select(
      vault.db.noteEmbeddings,
    )..where((e) => e.itemId.equals(itemId))).get())
      row.seq,
  ]..sort();

  group('indexNote', () {
    test('guarda un vector por tramo, y la segunda vez no calcula '
        'nada', () async {
      await vault.note('n', title: 'Nota', content: longText(3));

      expect(await indexer.indexNote('n'), 3);
      expect(await storedSeqs('n'), [0, 1, 2]);
      final row = await (vault.db.select(
        vault.db.noteEmbeddings,
      )..where((e) => e.seq.equals(0))).getSingle();
      expect(decodeEmbeddingVector(row.vector), [1, 0]);

      embeddings.requests.clear();
      expect(await indexer.indexNote('n'), 0);
      expect(embeddings.requests, isEmpty);
    });

    test('si cambia el final, solo recalcula ese tramo; si se achica, '
        'se van los que sobran', () async {
      await vault.note('n', title: 'Nota', content: longText(3));
      await indexer.indexNote('n');
      embeddings.requests.clear();

      await vault.note(
        'n',
        title: 'Nota',
        content: longText(3, last: otherEnding),
      );
      expect(await indexer.indexNote('n'), 1);
      expect(embeddings.requests.single, otherEnding);

      await vault.note('n', title: 'Nota', content: 'Corta, del Senado.');
      expect(await indexer.indexNote('n'), 1);
      expect(await storedSeqs('n'), [0]);
    });

    test('si se corta a mitad, lo guardado queda y sigue desde lo que '
        'falta', () async {
      const pieces = ChunkEmbeddingIndexerImpl.batchSize + 2;
      await vault.note('n', title: 'Nota', content: longText(pieces));
      final failing = ChunkEmbeddingIndexerImpl(
        database: vault.db,
        embeddings: FakeEmbeddingService(error: StateError('se cortó')),
        clock: vault.clock,
      );
      await expectLater(failing.indexNote('n'), throwsA(isA<StateError>()));
      expect(await storedSeqs('n'), isEmpty);

      final halfway = ChunkEmbeddingIndexerImpl(
        database: vault.db,
        embeddings: _FailsOnSecondBatch(),
        clock: vault.clock,
      );
      await expectLater(halfway.indexNote('n'), throwsA(isA<StateError>()));
      expect(
        await storedSeqs('n'),
        hasLength(ChunkEmbeddingIndexerImpl.batchSize),
      );

      expect(await indexer.indexNote('n'), 2);
      expect(await storedSeqs('n'), hasLength(pieces));
    });

    test('una fuente, una nota vacía o una en la papelera: nada', () async {
      await vault.source('f', title: 'Fuente', content: 'El Senado.');
      await vault.note('vacia', title: 'Vacía', content: '   ');
      await vault.note('borrada', title: 'Borrada', content: 'El Senado.');
      await trashItemRows(vault.db, 'borrada');

      expect(await indexer.indexNote('f'), 0);
      expect(await indexer.indexNote('vacia'), 0);
      expect(await indexer.indexNote('borrada'), 0);
      expect(embeddings.requests, isEmpty);
    });

    test('los tramos son del largo de un fragmento', () async {
      await vault.note('n', title: 'Nota', content: longText(4));
      await indexer.indexNote('n');

      expect(
        embeddings.requests.every(
          (text) => text.length <= kNoteEmbeddingPieceChars,
        ),
        isTrue,
      );
    });
  });

  group('una nota como candidata', () {
    Future<void> indexedSource(String id, String content) async {
      await vault.source(id, title: 'Fuente $id', content: content);
      await indexer.indexItem(id);
    }

    test('una nota con vectores es candidata igual que una fuente, con el '
        'comienzo de su texto', () async {
      await indexedSource('semilla', 'El Senado romano.');
      await vault.note(
        'n',
        title: 'Mi nota',
        content: 'Lo que pienso del Senado.',
      );
      await indexer.indexNote('n');

      final candidates = await selector.selectCandidates(seedItemId: 'semilla');

      expect(candidates.map((c) => c.itemId), ['n']);
      expect(candidates.single.title, 'Mi nota');
      expect(candidates.single.excerpt, 'Lo que pienso del Senado.');
    });

    test('una nota también es semilla, por sus vectores guardados', () async {
      await indexedSource('a', 'Las leyes del Senado.');
      await vault.note('n', title: 'Nota', content: 'Sobre el Senado.');
      await indexer.indexNote('n');

      final candidates = await selector.selectCandidates(seedItemId: 'n');

      expect(candidates.map((c) => c.itemId), ['a']);
    });

    test('solo fuentes, cuando hace falta un fragmento que citar', () async {
      await indexedSource('semilla', 'El Senado romano.');
      await indexedSource('a', 'Las leyes del Senado.');
      await vault.note('n', title: 'Nota', content: 'Sobre el Senado.');
      await indexer.indexNote('n');

      final sources = await selector.selectSourceCandidates(
        seedItemId: 'semilla',
      );

      expect(sources.map((c) => c.itemId), ['a']);
    });

    test('una nota en la papelera no es candidata', () async {
      await indexedSource('semilla', 'El Senado romano.');
      await vault.note('n', title: 'Nota', content: 'Sobre el Senado.');
      await indexer.indexNote('n');
      await trashItemRows(vault.db, 'n');

      expect(await selector.selectCandidates(seedItemId: 'semilla'), isEmpty);
    });
  });
}

/// La segunda tanda falla, como una app que se cierra a mitad de camino.
class _FailsOnSecondBatch extends FakeEmbeddingService {
  _FailsOnSecondBatch() : super(vectorFor: (_) => [1, 0]);

  var _batches = 0;

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (++_batches == 2) throw StateError('se cortó');
    return super.embedBatch(texts);
  }
}
