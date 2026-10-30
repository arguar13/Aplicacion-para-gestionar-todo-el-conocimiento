import 'package:async/async.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';

import '../creations_harness.dart';

/// El recorte de Procesado (F43, decisión D): qué documentos tiene cada uno
/// —todo, un documento, un cuaderno, un tema con sus ramas, un espacio—, sus
/// fuentes, sus cifras para el selector y qué tarjetas cuenta «Para hoy».
void main() {
  late CreationsHarness h;
  late String exodo;
  late String genesis;
  late String levitico;

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc('exodo', title: 'Éxodo', summary: [(0, 22)]);
    genesis = await h.processedDoc('genesis', title: 'Génesis');
    levitico = await h.processedDoc('levitico', title: 'Levítico');
    // Una fuente de la Biblioteca que nadie procesó: nunca entra.
    await h.processed.vault.saveSource('suelta', title: 'Suelta');
  });
  tearDown(() => h.close());

  Future<List<String>> idsOf(CreationScope scope) async =>
      (await h.scopes.documentIds(scope)).getRight().toNullable()!;

  group('los documentos de un recorte', () {
    test('todo lo procesado: los tres, nunca la Biblioteca', () async {
      expect((await idsOf(const CreationScope.allProcessed())).toSet(), {
        exodo,
        genesis,
        levitico,
      });
    });

    test('un documento: él, y nada si se borró o no es un procesado', () async {
      expect(await idsOf(CreationScope.document(exodo)), [exodo]);
      expect(await idsOf(const CreationScope.document('suelta')), isEmpty);

      await h.processed.vault.library.deleteMany([exodo]);
      expect(await idsOf(CreationScope.document(exodo)), isEmpty);
    });

    test('un cuaderno: lo que tiene hoy; uno que no existe falla', () async {
      await h.processed.vault.addNotebook('cuaderno', name: 'Pentateuco');
      await h.notebooks.addItems(
        notebookId: 'cuaderno',
        itemIds: [exodo, levitico, 'suelta'],
      );

      expect((await idsOf(const CreationScope.notebook('cuaderno'))).toSet(), {
        exodo,
        levitico,
      });
      expect(
        (await h.scopes.documentIds(
          const CreationScope.notebook('no'),
        )).isLeft(),
        isTrue,
      );
    });

    test('un tema trae lo de sus ramas, como el Atlas', () async {
      final vault = h.processed.vault;
      final tema = await vault.temaId();
      await vault.addPropertyValue('biblia', tema, 'Biblia');
      await vault.addPropertyValue('ley', tema, 'La Ley');
      await h.nest('ley', 'biblia');
      await vault.assignValue(exodo, 'biblia');
      await vault.assignValue(levitico, 'ley');
      // La fuente suelta también tiene el valor: no es de Procesado.
      await vault.assignValue('suelta', 'biblia');

      expect((await idsOf(const CreationScope.topic('biblia'))).toSet(), {
        exodo,
        levitico,
      });
      expect(await idsOf(const CreationScope.topic('ley')), [levitico]);
    });

    test('un espacio: lo procesado que está en él', () async {
      await h.processed.vault.addSpace('torah', 'Torá');
      await h.putInSpace(genesis, 'torah');
      await h.putInSpace('suelta', 'torah');

      expect(await idsOf(const CreationScope.space('torah')), [genesis]);
    });
  });

  group('sus fuentes', () {
    test('cada una con su título, si sigue viva, su resumen, sus tarjetas y '
        'sus creaciones; la que ya no está, como fuente borrada', () async {
      await h.processed.vault.addFlashcard('propia', exodo);
      await h.processed.vault.addFlashcard('de-la-fuente', 'exodo');
      await h.creations.create(
        CreationRequest(
          kind: StudyCreationKind.mindMap,
          scope: const CreationScope.allProcessed(),
          sourceIds: [exodo, genesis],
        ),
      );

      final sources = (await h.scopes.sourcesOf([
        exodo,
        genesis,
        'ya-no-existe',
      ])).getRight().toNullable()!;

      expect(
        [for (final s in sources) s.documentId],
        [exodo, genesis, 'ya-no-existe'],
      );
      final (e, g, gone) = (sources[0], sources[1], sources[2]);
      expect(e.title, 'Éxodo');
      expect(e.isLive, isTrue);
      expect(e.sourceItemId, 'exodo');
      expect(e.hasSummary, isTrue);
      expect(e.hasSynthesis, isFalse);
      expect(e.cards, 2, reason: 'la suya y la de «De la fuente»');
      expect(e.creations, 1);
      expect(g.hasSummary, isFalse);
      expect(g.cards, 0);
      expect(gone.isLive, isFalse);
      expect(gone.title, isEmpty);
    });
  });

  group('la píldora del selector', () {
    test('nombre y cifras de un documento, al día', () async {
      await h.processed.vault.addFlashcard('propia', exodo);
      await h.processed.vault.addFlashcard('de-la-fuente', 'exodo');
      final summaries = StreamQueue(
        h.scopes.watchSummary(CreationScope.document(exodo)),
      );
      addTearDown(summaries.cancel);
      final first = await summaries.next;

      expect(first.name, 'Éxodo');
      expect(first.documents, 1);
      expect(first.cards, 2);
      expect(first.creations, 0);
      expect(first.exists, isTrue);

      await h.creations.create(
        CreationRequest(
          kind: StudyCreationKind.quiz,
          scope: CreationScope.document(exodo),
          sourceIds: [exodo],
        ),
      );
      expect((await summaries.next).creations, 1);
    });

    test(
      'todo lo procesado no tiene nombre y cuenta todas las tarjetas',
      () async {
        await h.processed.vault.addFlashcard('suelta-1', 'suelta');
        final summary = await h.scopes
            .watchSummary(const CreationScope.allProcessed())
            .first;

        expect(summary.name, isNull);
        expect(summary.exists, isTrue);
        expect(summary.documents, 3);
        expect(summary.cards, 1, reason: '«Todo» es todo: nada se pierde');
      },
    );

    test('un cuaderno que ya no existe lo dice', () async {
      final summary = await h.scopes
          .watchSummary(const CreationScope.notebook('borrado'))
          .first;

      expect(summary.exists, isFalse);
      expect(summary.documents, 0);
    });
  });

  group('«Para hoy» con un recorte de Procesado', () {
    const limits = StudyLimits();

    Future<int> dueIn(StudyScope scope) async => (await h.study.counts(
      scope,
      limits: limits,
    )).getRight().toNullable()!.total;

    test('un documento cuenta sus tarjetas y las de su fuente, y ninguna '
        'más', () async {
      final vault = h.processed.vault;
      await vault.addFlashcard('propia', exodo);
      await vault.addFlashcard('fuente-1', 'exodo');
      await vault.addFlashcard('fuente-2', 'exodo');
      await vault.addFlashcard('otra', genesis);
      await vault.addFlashcard('suelta-1', 'suelta');

      expect(await dueIn(CreationScope.document(exodo).studyScope), 3);
      expect(await dueIn(const CreationScope.allProcessed().studyScope), 5);
    });

    test('un cuaderno, lo mismo con cada uno de sus documentos', () async {
      final vault = h.processed.vault;
      await vault.addNotebook('cuaderno');
      await h.notebooks.addItems(notebookId: 'cuaderno', itemIds: [exodo]);
      await vault.addFlashcard('propia', exodo);
      await vault.addFlashcard('fuente-1', 'exodo');
      await vault.addFlashcard('otra', genesis);

      expect(
        await dueIn(const CreationScope.notebook('cuaderno').studyScope),
        2,
      );
    });

    test('un tema, con sus ramas', () async {
      final vault = h.processed.vault;
      final tema = await vault.temaId();
      await vault.addPropertyValue('biblia', tema, 'Biblia');
      await vault.addPropertyValue('ley', tema, 'La Ley');
      await h.nest('ley', 'biblia');
      await vault.assignValue(levitico, 'ley');
      await vault.addFlashcard('lev', levitico);
      await vault.addFlashcard('lev-fuente', 'levitico');
      await vault.addFlashcard('otra', genesis);

      expect(await dueIn(const CreationScope.topic('biblia').studyScope), 2);
    });

    test('una clave que no se entiende no cuenta nada', () async {
      final result = await h.study.counts(
        const StudyScope.processed('raro'),
        limits: limits,
      );
      expect(result.isLeft(), isTrue);
    });
  });

  group('lo que el recorte ya tenía (M10)', () {
    /// Marca [kind] en [documentId], como lo deja «Marcar» en el original.
    Future<void> mark(String documentId, ProcessedSection kind) async {
      final db = h.processed.db;
      final at = DateTime(2026, 10, 29);
      await db
          .into(db.processedParts)
          .insert(
            ProcessedPartsCompanion.insert(
              id: '$documentId-${kind.name}-marca',
              documentId: documentId,
              section: kind,
              position: 0,
              content: 'Moisés guía al pueblo.',
              origin: ProcessedPartOrigin.copied,
              sourceStart: const Value(0),
              sourceEnd: const Value(22),
              createdAt: at,
              updatedAt: at,
            ),
          );
    }

    test('cuántos documentos tienen el resumen y la síntesis marcados, y '
        'cada cambio', () async {
      final summaries = StreamQueue(
        h.scopes.watchSummary(const CreationScope.allProcessed()),
      );
      addTearDown(summaries.cancel);
      final first = await summaries.next;
      expect(first.documents, 3);
      expect(first.summaryDocuments, 1, reason: 'solo el Éxodo');
      expect(first.synthesisDocuments, 0);

      await mark(genesis, ProcessedSection.synthesis);
      final marked = await summaries.next;
      expect(marked.summaryDocuments, 1);
      expect(marked.synthesisDocuments, 1);
    });

    test('un documento y un cuaderno cuentan solo los suyos', () async {
      await h.processed.vault.addNotebook('cuaderno');
      await h.notebooks.addItems(
        notebookId: 'cuaderno',
        itemIds: [genesis, levitico],
      );
      await mark(levitico, ProcessedSection.summary);

      final exodus = await h.scopes
          .watchSummary(CreationScope.document(exodo))
          .first;
      expect(exodus.summaryDocuments, 1);
      final notebook = await h.scopes
          .watchSummary(const CreationScope.notebook('cuaderno'))
          .first;
      expect(notebook.documents, 2);
      expect(notebook.summaryDocuments, 1, reason: 'el Levítico, no el Éxodo');
      expect(notebook.synthesisDocuments, 0);
      final none = await h.scopes
          .watchSummary(CreationScope.document(genesis))
          .first;
      expect(none.summaryDocuments, 0);
    });
  });

  group('de dónde sale una creación (M12)', () {
    Future<CreationOrigin> originOf(
      CreationScope scope,
      List<String> sources,
    ) => h.scopes.watchOrigin(scope, sources).first;

    test('un documento por su título; con varios, el primero y cuántos '
        'más', () async {
      expect(
        await originOf(CreationScope.document(exodo), [exodo]),
        const CreationOrigin(name: 'Éxodo'),
      );
      expect(
        await originOf(const CreationScope.allProcessed(), [
          genesis,
          exodo,
          levitico,
        ]),
        const CreationOrigin(name: 'Génesis', more: 2),
      );
    });

    test('las fuentes borradas: nombra la primera viva, y si no queda '
        'ninguna lo dice', () async {
      expect(
        await originOf(const CreationScope.allProcessed(), ['no-está', exodo]),
        const CreationOrigin(name: 'Éxodo', more: 1),
      );
      expect(
        await originOf(const CreationScope.document('no-está'), ['no-está']),
        const CreationOrigin(deleted: true),
      );
      expect(
        await originOf(const CreationScope.allProcessed(), ['a', 'b']),
        const CreationOrigin(more: 1, deleted: true),
      );
    });

    test('un cuaderno y un tema, por su nombre aunque haya leído '
        'documentos; uno que ya no existe lo dice', () async {
      final vault = h.processed.vault;
      await vault.addNotebook('cuaderno', name: 'Pentateuco');
      await vault.addPropertyValue('biblia', await vault.temaId(), 'Biblia');

      expect(
        await originOf(const CreationScope.notebook('cuaderno'), [
          exodo,
          genesis,
        ]),
        const CreationOrigin(name: 'Pentateuco'),
      );
      expect(
        await originOf(const CreationScope.topic('biblia'), [exodo]),
        const CreationOrigin(name: 'Biblia'),
      );
      expect(
        await originOf(const CreationScope.notebook('borrado'), [exodo]),
        const CreationOrigin(deleted: true),
      );
    });

    test('todo lo procesado sin fuentes no tiene nombre: lo nombra la '
        'interfaz', () async {
      expect(
        await originOf(const CreationScope.allProcessed(), const []),
        const CreationOrigin(),
      );
    });

    test('al día: si el documento se renombra o se borra', () async {
      final origins = StreamQueue(
        h.scopes.watchOrigin(CreationScope.document(exodo), [exodo]),
      );
      addTearDown(origins.cancel);
      expect((await origins.next).name, 'Éxodo');

      final db = h.processed.db;
      await db.customUpdate(
        'UPDATE item SET title = ? WHERE id = ?',
        variables: [
          Variable.withString('Éxodo, 2.ª'),
          Variable.withString(exodo),
        ],
        updates: {db.knowledgeEntries},
      );
      expect((await origins.next).name, 'Éxodo, 2.ª');

      await h.processed.vault.library.deleteMany([exodo]);
      expect(await origins.next, const CreationOrigin(deleted: true));
    });
  });
}
