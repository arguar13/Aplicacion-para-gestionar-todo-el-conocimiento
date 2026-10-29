import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
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
}
