import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/features/creations/data/repositories/creation_scope_resolver_impl.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';

import '../../../support/processed_rows.dart';
import '../creations_harness.dart';

/// Cuenta las lecturas que llegan a SQLite.
class _ReadCounter extends QueryInterceptor {
  int reads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    reads++;
    return super.runSelect(executor, statement, args);
  }
}

/// El catálogo del selector de Repasar (F43, M11): todo lo que ofrece, con la
/// línea de cada uno, en lote. Sus cifras son las de la píldora —las dos no
/// pueden discrepar— y las lecturas no crecen con los documentos.
void main() {
  group('las líneas', () {
    late CreationsHarness h;
    late String exodo;
    late String genesis;
    late String levitico;

    setUp(() async {
      h = await CreationsHarness.create();
      exodo = await h.processedDoc(
        'exodo',
        title: 'Éxodo',
        summary: [(0, 22)],
        synthesis: [(23, 39)],
      );
      genesis = await h.processedDoc('genesis', title: 'Génesis');
      levitico = await h.processedDoc('levitico', title: 'Levítico');
      final vault = h.processed.vault;
      // Las tarjetas: las del documento, las de su fuente y una de la
      // Biblioteca que «Todo» cuenta igual.
      await vault.addFlashcard('propia', exodo);
      await vault.addFlashcard('de-la-fuente', 'exodo');
      await vault.addFlashcard('de-genesis', genesis);
      await vault.addFlashcard('suelta-1', 'levitico');
      // Un tema con su rama y un espacio.
      final tema = await vault.temaId();
      await vault.addPropertyValue('biblia', tema, 'Biblia');
      await vault.addPropertyValue('ley', tema, 'La Ley');
      await h.nest('ley', 'biblia');
      await vault.assignValue(exodo, 'biblia');
      await vault.assignValue(levitico, 'ley');
      await vault.addSpace('torah', 'Torá');
      await h.putInSpace(genesis, 'torah');
      // Las creaciones: sobre un documento, sobre todo leyendo dos, sobre un
      // cuaderno y sobre un tema.
      await h.creations.create(
        CreationRequest(
          kind: StudyCreationKind.quiz,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
        ),
      );
      await h.creations.create(
        CreationRequest(
          kind: StudyCreationKind.mindMap,
          scope: const CreationScope.allProcessed(),
          sourceIds: [exodo, genesis],
        ),
      );
      await h.creations.create(
        CreationRequest(
          kind: StudyCreationKind.report,
          scope: const CreationScope.topic('biblia'),
          sourceIds: [exodo, levitico],
        ),
      );
    });
    tearDown(() => h.close());

    Future<CreationScopeCatalog> catalog([
      Set<CreationScope> topics = const {},
    ]) => h.scopes.watchCatalog(topics).first;

    test('cada una dice lo mismo que la píldora de su recorte', () async {
      final manual = await h.notebooks.create(
        name: 'Para el examen',
        mode: NotebookMode.manual,
      );
      await h.notebooks.addItems(
        notebookId: manual.id,
        itemIds: [exodo, levitico],
      );
      final byQuery = await h.notebooks.create(
        name: 'Lo del Sinaí',
        mode: NotebookMode.query,
        query: const LibraryQuery(searchText: 'Sinaí'),
      );
      await h.creations.create(
        CreationRequest(
          kind: StudyCreationKind.summary,
          scope: CreationScope.notebook(manual.id),
          sourceIds: [exodo],
        ),
      );
      final topics = {
        const CreationScope.topic('biblia'),
        const CreationScope.topic('ley'),
        const CreationScope.space('torah'),
      };
      final lines = await catalog(topics);

      final scopes = [
        const CreationScope.allProcessed(),
        CreationScope.document(exodo),
        CreationScope.document(genesis),
        CreationScope.document(levitico),
        CreationScope.notebook(manual.id),
        CreationScope.notebook(byQuery.id),
        ...topics,
      ];
      for (final scope in scopes) {
        final summary = await h.scopes.watchSummary(scope).first;
        final line = lines.lineOf(scope);
        expect(line, isNotNull, reason: scope.storageKey);
        expect(
          (line!.documents, line.cards, line.creations),
          (summary.documents, summary.cards, summary.creations),
          reason: scope.storageKey,
        );
        if (!scope.isAll) expect(line.name, summary.name);
      }
      // Y lo que se ve en cada una, por si las dos se equivocaran juntas.
      final e = lines.lineOf(CreationScope.document(exodo))!;
      expect(
        (e.cards, e.creations, e.hasSummary, e.hasSynthesis),
        (2, 4, true, true),
        reason:
            'la suya y la de su fuente; el cuestionario sobre él y el mapa, '
            'el informe y el resumen del cuaderno, que lo leyeron',
      );
      final g = lines.lineOf(CreationScope.document(genesis))!;
      expect((g.cards, g.creations, g.hasSummary), (1, 1, false));
      expect(lines.all.documents, 3);
      expect(lines.all.cards, 4, reason: '«Todo» es todo');
      expect(lines.all.creations, 4);
      final biblia = lines.lineOf(const CreationScope.topic('biblia'))!;
      expect(
        (biblia.documents, biblia.creations),
        (2, 1),
        reason: 'con su rama',
      );
      expect(lines.lineOf(CreationScope.notebook(manual.id))!.creations, 1);
      expect(lines.lineOf(CreationScope.notebook(byQuery.id))!.documents, 3);
    });

    test('el resumen y la síntesis, cada uno por su lado', () async {
      final numeros = await h.processedDoc(
        'numeros',
        title: 'Números',
        summary: [(0, 22)],
      );
      final deuteronomio = await h.processedDoc(
        'deuteronomio',
        title: 'Deuteronomio',
        synthesis: [(0, 22)],
      );
      final lines = await catalog();

      final n = lines.lineOf(CreationScope.document(numeros))!;
      final d = lines.lineOf(CreationScope.document(deuteronomio))!;
      expect((n.hasSummary, n.hasSynthesis), (true, false));
      expect((d.hasSummary, d.hasSynthesis), (false, true));
    });

    test('lo que ya no existe no está, y lo que se borra se va', () async {
      final notebook = await h.notebooks.create(
        name: 'Borrable',
        mode: NotebookMode.manual,
      );
      final lines = h.scopes.watchCatalog({
        const CreationScope.topic('biblia'),
        const CreationScope.topic('no-existe'),
        const CreationScope.space('tampoco'),
      });
      final first = await lines.first;
      expect(first.lineOf(const CreationScope.topic('biblia')), isNotNull);
      expect(first.lineOf(const CreationScope.topic('no-existe')), isNull);
      expect(first.lineOf(const CreationScope.space('tampoco')), isNull);
      expect(first.lineOf(CreationScope.notebook(notebook.id)), isNotNull);

      await h.processed.db.customUpdate(
        'UPDATE item SET deleted_at = 1 WHERE id = ?',
        variables: [Variable.withString(genesis)],
      );
      await h.notebooks.delete(notebook.id);
      final after = await catalog({const CreationScope.topic('biblia')});

      expect(after.lineOf(CreationScope.document(genesis)), isNull);
      expect(after.lineOf(CreationScope.notebook(notebook.id)), isNull);
      expect(after.documents, hasLength(2));
      expect(after.all.documents, 2);
    });
  });

  group('en lote', () {
    late _ReadCounter counter;
    late CreationsHarness h;

    setUp(() async {
      counter = _ReadCounter();
      h = await CreationsHarness.create(
        executor: NativeDatabase.memory().interceptWith(counter),
      );
    });
    tearDown(() => h.close());

    /// Pone [count] documentos más, con una tarjeta y un cuaderno cada diez.
    Future<void> grow(int count, {int from = 0}) async {
      for (var i = from; i < from + count; i++) {
        await insertProcessedRows(h.processed.db, id: 'doc-$i', title: 'D $i');
        await h.processed.vault.addFlashcard('card-$i', 'doc-$i');
        if (i % 10 == 0) {
          final notebook = await h.notebooks.create(
            name: 'Cuaderno $i',
            mode: NotebookMode.manual,
          );
          await h.notebooks.addItems(
            notebookId: notebook.id,
            itemIds: ['doc-$i'],
          );
        }
      }
    }

    Future<int> readsOfCatalog() async {
      final before = counter.reads;
      final catalog = await h.scopes.watchCatalog(const {}).first;
      expect(catalog.documents, isNotEmpty);
      return counter.reads - before;
    }

    test('las mismas lecturas con 40 documentos que con 2.000', () async {
      await grow(40);
      final few = await readsOfCatalog();
      await grow(1960, from: 40);
      final many = await readsOfCatalog();

      expect(many, few, reason: 'ni una lectura por documento ni por cuaderno');
      expect(few, lessThanOrEqualTo(8));
      final catalog = await h.scopes.watchCatalog(const {}).first;
      expect(catalog.documents, hasLength(2000));
      expect(catalog.notebooks, hasLength(200));
    });

    test('cuántos documentos tiene cada consulta: doscientas por lectura, '
        'iguales a las de una en una', () async {
      await grow(30);
      final repository = h.processed.repository;
      final queries = {
        for (var i = 0; i < 250; i++)
          'q$i': ProcessedQuery(ids: {'doc-${i % 30}', 'doc-${(i + 1) % 30}'}),
        'todo': const ProcessedQuery(),
        'nada': const ProcessedQuery(ids: {}),
      };
      final before = counter.reads;
      final many = (await repository.matchingIdsOfMany(
        queries,
      )).getRight().toNullable()!;

      expect(counter.reads - before, 2, reason: '252 consultas: dos lecturas');
      expect(many.keys.toSet(), queries.keys.toSet());
      for (final MapEntry(:key, :value) in queries.entries) {
        final one = (await repository.matchingIds(
          value,
        )).getRight().toNullable()!;
        expect(many[key], one.toSet(), reason: key);
      }
      expect(many['nada'], isEmpty);
      expect(many['todo'], hasLength(30));
    });
  });

  test('el plan de SQLite: cada documento por clave, y las creaciones '
      'contadas una sola vez para todos', () async {
    final h = await CreationsHarness.create();
    addTearDown(h.close);
    final plan = [
      for (final row
          in await h.processed.db
              .customSelect('EXPLAIN QUERY PLAN $creationScopeDocumentsSql')
              .get())
        (
          id: row.read<int>('id'),
          parent: row.read<int>('parent'),
          detail: row.read<String>('detail'),
        ),
    ];
    final byId = {for (final step in plan) step.id: step};
    bool underCorrelated(({int id, int parent, String detail}) step) {
      var at = byId[step.parent];
      while (at != null) {
        if (at.detail.contains('CORRELATED')) return true;
        at = byId[at.parent];
      }
      return false;
    }

    final text = plan.map((s) => s.detail).join('\n');
    // Las tarjetas y las partes, siempre por su índice: nunca recorridas.
    expect(
      plan.where((s) => RegExp(r'^SCAN (f|p|source)\b').hasMatch(s.detail)),
      isEmpty,
      reason: text,
    );
    // Las creaciones se recorren, pero no una vez por documento.
    final creations = plan.where((s) => s.detail.startsWith('SCAN c'));
    expect(creations, isNotEmpty, reason: text);
    expect(creations.where(underCorrelated), isEmpty, reason: text);
  });
}
