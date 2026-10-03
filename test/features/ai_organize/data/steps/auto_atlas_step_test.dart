import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_atlas_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_atlas_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_atlas.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_atlas_rules.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_intro.dart';
import 'package:sinapsis/features/ai_organize/domain/services/topic_parent_chooser.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/atlas_topics.dart';

/// Un modelo de mentira que elige el padre que se le diga, con la certeza que
/// se le diga, y anota qué le preguntaron.
class _FakeChooser {
  /// El nombre del padre que elige; `null` = «ninguno».
  String? pick;
  AiCertainty? certainty = AiCertainty.high;
  final asked = <({String topic, List<String> candidates})>[];

  Future<TopicParentChoice?> call({
    required String topic,
    required String itemTitle,
    required List<String> candidates,
  }) async {
    asked.add((topic: topic, candidates: candidates));
    final index = pick == null
        ? -1
        : candidates.indexWhere((c) => c == pick || c.endsWith('› $pick'));
    return index < 0
        ? null
        : TopicParentChoice(index: index, certainty: certainty);
  }
}

/// Un modelo de mentira que escribe una introducción —con un enlace inventado,
/// para comprobar que no llega a la nota— y anota lo que vio.
class _FakeWriter {
  final seen = <List<MapIntroEntry>>[];

  Future<String> call({
    required String topic,
    required List<MapIntroEntry> entries,
  }) async {
    seen.add(entries);
    return '**Todo** lo reunido sobre $topic. Ver [[Inventado]].';
  }
}

void main() {
  late AiOrganizeHarness vault;
  late AtlasTopics topics;
  late AiAtlasRepositoryImpl atlas;
  late _FakeChooser chooser;
  late _FakeWriter writer;
  late AutoAtlasStep step;
  late String historia;

  /// Desde cuándo organiza la IA: los temas de antes son «viejos».
  final epoch = DateTime(2026, 10);

  setUp(() async {
    vault = AiOrganizeHarness();
    topics = AtlasTopics(vault.db);
    atlas = AiAtlasRepositoryImpl(
      database: vault.db,
      library: vault.library,
      organize: vault.organize,
      runs: vault.runs,
      telemetry: vault.telemetry,
      ids: vault.ids,
      clock: vault.clock,
    );
    chooser = _FakeChooser();
    writer = _FakeWriter();
    step = AutoAtlasStep(
      atlas: atlas,
      library: vault.library,
      suggestions: vault.suggestions,
      chooseParent: chooser.call,
      writeIntro: writer.call,
      epoch: () async => epoch,
      modelName: () => 'gemma-prueba',
      clock: vault.clock,
    );
    // El árbol que armó la persona.
    historia = await topics.add('Historia antigua', createdAt: DateTime(2026));
    await topics.add('Grecia', parentId: historia, createdAt: DateTime(2026));
  });

  tearDown(() => vault.close());

  /// Organiza [itemId] en una pasada nueva, como lo hace la cola.
  Future<AiStepReport> organize(String itemId) async => step.organize(
    await vault.reload(itemId),
    runId: await vault.startRun(itemId),
  );

  /// Una fuente con el tema [valueId].
  Future<void> sourceIn(String id, String valueId, {String? title}) async {
    await vault.source(id, title: title ?? 'Fuente $id', content: 'Texto $id.');
    await topics.tag(id, valueId);
  }

  Future<List<Suggestion>> suggestionsOf(String itemId) async =>
      (await vault.suggestions.suggestionsFor(
        itemId,
      )).getOrElse((f) => fail('$f'));

  Future<List<TopicMapNote>> mapNotesOf(String valueId) async =>
      (await atlas.mapNotesOf(valueId)).getOrElse((f) => fail('$f'));

  group('el árbol de temas', () {
    test('lo seguro de un tema nuevo se aplica, registrado con su pasada: '
        'deshacerla lo devuelve a la raíz', () async {
      final roma = await topics.add('Roma');
      await sourceIn('a', roma);
      chooser.pick = 'Historia antigua';
      final run = await vault.startRun('a');

      final report = await step.organize(await vault.reload('a'), runId: run);

      expect(report.applied, 1);
      expect(await topics.parentOf(roma), historia);
      expect(chooser.asked.single.topic, 'Roma');
      expect(chooser.asked.single.candidates, [
        'Historia antigua',
        'Historia antigua › Grecia',
      ]);
      final record = (await suggestionsOf('a')).single as TopicParentSuggestion;
      expect((record.status, record.aiRunId), (SuggestionStatus.accepted, run));

      await vault.runs.undoRun(run);
      expect(await topics.parentOf(roma), isNull);
    });

    test('lo que ubicó cuenta en su pasada: al cerrarla, al listarla y al '
        'deshacerla', () async {
      final roma = await topics.add('Roma');
      final cartago = await topics.add('Cartago');
      await sourceIn('a', roma);
      await topics.tag('a', cartago);
      chooser.pick = 'Historia antigua';
      final run = await vault.startRun('a');
      await step.organize(await vault.reload('a'), runId: run);

      final finished = (await vault.runs.finishRun(
        run,
      )).getOrElse((f) => fail('$f'));
      expect(finished.topicPlacements, 2);

      // La persona movió uno: ese ya es suyo, y deshacer no lo toca.
      await (vault.db.update(vault.db.propertyValues)
            ..where((v) => v.id.equals(cartago)))
          .write(const PropertyValuesCompanion(parentId: Value('t-Grecia')));
      final listed = (await vault.runs.listRuns(
        itemId: 'a',
      )).getOrElse((f) => fail('$f')).single;
      expect(listed.created.topicPlacements, 2);
      expect(listed.remaining.topicPlacements, 1);

      final undone = (await vault.runs.undoRun(
        run,
      )).getOrElse((f) => fail('$f'));
      expect(undone.topicPlacements, 1);
      expect(await topics.parentOf(roma), isNull);
      expect(await topics.parentOf(cartago), 't-Grecia');
      final after = (await vault.runs.listRuns(
        itemId: 'a',
      )).getOrElse((f) => fail('$f')).single;
      expect(after.created.topicPlacements, 2);
      expect(after.remaining.topicPlacements, 0);
    });

    test('lo dudoso va a «Para revisar» y no toca el árbol; aceptarlo lo '
        'ubica', () async {
      final roma = await topics.add('Roma');
      await sourceIn('a', roma);
      chooser
        ..pick = 'Historia antigua'
        ..certainty = AiCertainty.medium;

      final report = await organize('a');

      expect((report.applied, report.forReview), (0, 1));
      expect(await topics.parentOf(roma), isNull);
      final pending =
          (await vault.suggestions.watchPendingSuggestions('a').first).single
              as TopicParentSuggestion;
      expect(
        (pending.valueName, pending.parentName),
        ('Roma', 'Historia antigua'),
      );

      await vault.suggestions.accept(pending.id);
      expect(await topics.parentOf(roma), historia);
    });

    test('un tema viejo en la raíz pudo dejarlo ahí la persona: aunque el '
        'modelo esté seguro, solo se propone', () async {
      final roma = await topics.add('Roma', createdAt: DateTime(2026, 9));
      await sourceIn('a', roma);
      chooser.pick = 'Historia antigua';

      final report = await organize('a');

      expect((report.applied, report.forReview), (0, 1));
      expect(await topics.parentOf(roma), isNull);
    });

    test('nunca toca lo que la persona ubicó: ni un tema con padre, ni una '
        'rama que armó, ni uno del que ya se decidió algo', () async {
      const grecia = 't-Grecia';
      final arte = await topics.add('Arte');
      await topics.add('Escultura', parentId: arte);
      final roma = await topics.add('Roma');
      await sourceIn('a', grecia);
      await topics.tag('a', arte);
      await topics.tag('a', roma);
      // Lo que la IA propuso antes sobre «Roma» y la persona descartó.
      chooser
        ..pick = 'Historia antigua'
        ..certainty = AiCertainty.medium;
      await organize('a');
      // De los tres, solo se le preguntó por el suelto.
      expect(chooser.asked.single.topic, 'Roma');
      final proposal = (await suggestionsOf('a')).single;
      await vault.suggestions.reject(proposal.id);
      chooser.asked.clear();

      await sourceIn('b', roma);
      final report = await organize('b');

      expect(report, AiStepReport.nothing);
      expect(chooser.asked, isEmpty);
      expect(await topics.parentOf(roma), isNull);
      expect(await topics.parentOf(arte), isNull);
      expect(await topics.parentOf(grecia), historia);
    });

    test('nunca crea temas: si no va bajo ninguno, no pasa nada, y no se le '
        'vuelve a preguntar por lo mismo', () async {
      final roma = await topics.add('Roma');
      await sourceIn('a', roma);
      await sourceIn('b', roma);
      chooser.pick = null;
      final before = await vault.db.select(vault.db.propertyValues).get();

      expect(await organize('a'), AiStepReport.nothing);
      expect(await organize('b'), AiStepReport.nothing);

      expect(
        await vault.db.select(vault.db.propertyValues).get(),
        hasLength(before.length),
      );
      expect(chooser.asked, hasLength(1));
      expect(await suggestionsOf('a'), isEmpty);
    });

    test('si la persona nunca armó un árbol, la IA no empieza uno', () async {
      await (vault.db.update(vault.db.propertyValues)
            ..where((v) => v.id.equals('t-Grecia')))
          .write(const PropertyValuesCompanion(parentId: Value(null)));
      final roma = await topics.add('Roma');
      await sourceIn('a', roma);
      chooser.pick = 'Historia antigua';

      expect(await organize('a'), AiStepReport.nothing);
      expect(chooser.asked, isEmpty);
    });
  });

  group('las notas mapa', () {
    test(
      'con menos de cinco elementos no hay nota mapa; con cinco, nace',
      () async {
        for (var i = 1; i < kAiMapNoteMinItems; i++) {
          await sourceIn('f$i', historia);
        }
        await organize('f1');
        expect(await mapNotesOf(historia), isEmpty);
        expect(writer.seen, isEmpty);

        await sourceIn('f5', historia);
        final report = await organize('f5');

        expect(report.applied, 1);
        final map = (await mapNotesOf(historia)).single;
        expect(map.title, 'Mapa de Historia antigua');
        expect(map.keptByAi, isTrue);
        final row = await (vault.db.select(
          vault.db.knowledgeNotes,
        )..where((n) => n.itemId.equals(map.itemId))).getSingle();
        expect(
          (row.noteKind, row.generatedByModel),
          (NoteKind.map, 'gemma-prueba'),
        );
      },
    );

    test('su contenido: la introducción del modelo, limpia, y un enlace a cada '
        'elemento que existe de verdad', () async {
      for (var i = 1; i <= 5; i++) {
        await sourceIn('f$i', historia);
      }
      await vault.note('n', title: 'Mi nota', content: 'Lo que pienso.');
      await topics.tag('n', historia);

      await organize('n');

      final map = (await mapNotesOf(historia)).single;
      final blocks = decodeContentBlocks(map.blocksContent!);
      expect(
        blocks.first,
        const ContentBlock.paragraph(
          text: 'Todo lo reunido sobre Historia antigua. Ver Inventado.',
        ),
      );
      expect(blocks.whereType<HeadingBlock>().map((b) => b.text), [
        'Notas',
        'Fuentes',
      ]);
      expect(linkedTitlesOf(map.blocksContent), {
        'mi nota',
        for (var i = 1; i <= 5; i++) 'fuente f$i',
      });
      // Cada enlace resuelve a un elemento: ninguno roto, ninguno inventado.
      final links = await (vault.db.select(
        vault.db.inlineLinks,
      )..where((l) => l.fromItemId.equals(map.itemId))).get();
      expect(links, hasLength(6));
      expect(links.every((l) => l.toItemId != null), isTrue);
      // El modelo vio lo que hay, con su fragmento.
      expect(
        writer.seen.single.first,
        const MapIntroEntry(title: 'Mi nota', excerpt: 'Lo que pienso.'),
      );
    });

    test(
      'el tema y sus ancestros: lo de «Grecia» suma a «Historia antigua»',
      () async {
        for (var i = 1; i <= 5; i++) {
          await sourceIn('g$i', 't-Grecia');
        }

        await organize('g5');

        expect(await mapNotesOf('t-Grecia'), hasLength(1));
        final general = (await mapNotesOf(historia)).single;
        expect(
          decodeContentBlocks(
            general.blocksContent!,
          ).whereType<HeadingBlock>().map((b) => b.text),
          ['Grecia'],
        );
      },
    );

    test('la de la IA sin editar se actualiza cuando entra material nuevo, y '
        'solo entonces', () async {
      for (var i = 1; i <= 5; i++) {
        await sourceIn('f$i', historia);
      }
      await organize('f5');
      // Sin nada nuevo, ni se le pregunta al modelo.
      await organize('f4');
      expect(writer.seen, hasLength(1));

      await sourceIn('f6', historia);
      final report = await organize('f6');

      expect(report.applied, 1);
      expect(writer.seen, hasLength(2));
      expect(
        linkedTitlesOf((await mapNotesOf(historia)).single.blocksContent),
        contains('fuente f6'),
      );
    });

    test('la que la persona editó ya es suya: no se toca', () async {
      for (var i = 1; i <= 5; i++) {
        await sourceIn('f$i', historia);
      }
      await organize('f5');
      final map = (await mapNotesOf(historia)).single;
      await KnowledgeEntryWriter(vault.db).markDerivedEdited(map.itemId);

      await sourceIn('f6', historia);
      final report = await organize('f6');

      expect(report, AiStepReport.nothing);
      final after = (await mapNotesOf(historia)).single;
      expect(after.blocksContent, map.blocksContent);
    });

    test('una de la persona no se toca, y el tema no recibe otra', () async {
      await vault.note('mio', title: 'Mi índice', content: 'x');
      await KnowledgeEntryWriter(vault.db).setNoteKind('mio', NoteKind.map);
      await topics.tag('mio', historia);
      for (var i = 1; i <= 5; i++) {
        await sourceIn('f$i', historia);
      }

      expect(await organize('f5'), AiStepReport.nothing);
      expect((await mapNotesOf(historia)).single.itemId, 'mio');
    });

    test('se borra como cualquier nota, y no vuelve', () async {
      for (var i = 1; i <= 5; i++) {
        await sourceIn('f$i', historia);
      }
      await organize('f5');
      await vault.library.delete((await mapNotesOf(historia)).single.itemId);

      await sourceIn('f6', historia);
      final report = await organize('f6');

      expect(report, AiStepReport.nothing);
      expect(await mapNotesOf(historia), isEmpty);
    });

    test('deshacer su pasada la manda a la papelera, y recuperarla no hace '
        'que la IA cree otra ni la vuelva a tocar', () async {
      for (var i = 1; i <= 5; i++) {
        await sourceIn('f$i', historia);
      }
      await organize('f5');
      final map = (await mapNotesOf(historia)).single;
      final run = (await vault.runs.listRuns(
        itemId: map.itemId,
      )).getOrElse((f) => fail('$f')).single;
      await vault.runs.undoRun(run.id);

      await sourceIn('f6', historia);
      expect(await organize('f6'), AiStepReport.nothing);
      expect(await mapNotesOf(historia), isEmpty);

      (await vault.library.restore(map.itemId)).getOrElse((f) => fail('$f'));
      await sourceIn('f7', historia);
      expect(await organize('f7'), AiStepReport.nothing);
      expect(await mapNotesOf(historia), isEmpty);
      expect(writer.seen, hasLength(1));
      // Vuelve como estaba: sin el tema, con el índice que tenía.
      final restored = await vault.reload(map.itemId);
      expect(restored.tags, isEmpty);
      final blocks =
          await (vault.db.select(vault.db.renditions)..where(
                (r) =>
                    r.itemId.equals(map.itemId) &
                    r.kind.equalsValue(RenditionKind.blocks),
              ))
              .getSingle();
      expect(blocks.content, map.blocksContent);
    });
  });

  group('la madurez', () {
    /// Una nota viva de [chars] caracteres, nacida hace [age], vinculada con
    /// [links] fuentes.
    Future<void> livingNote({
      int chars = kDevelopingMinChars,
      Duration age = kDevelopingMinAge,
      int links = kDevelopingMinConnections,
    }) async {
      await vault.note(
        'n',
        title: 'Roma',
        content: 'a' * chars,
        createdAt: vault.now.subtract(age),
      );
      for (var i = 0; i < links; i++) {
        await vault.source('s$i', title: 'S$i', content: 'x');
        await vault.organize.createRelation(
          fromItemId: 'n',
          toItemId: 's$i',
          kind: RelationKind.relatedTo,
        );
      }
    }

    test('una nota viva que creció deja la sugerencia de subirla, y nunca la '
        'cambia sola', () async {
      await livingNote();

      final report = await organize('n');

      expect(report.forReview, 1);
      final pending =
          (await vault.suggestions.watchPendingSuggestions('n').first).single
              as MaturitySuggestion;
      expect(
        (pending.from, pending.to),
        (NoteMaturity.seed, NoteMaturity.developing),
      );
      expect(await topics.maturityOf('n'), NoteMaturity.seed);
    });

    test('una que no creció lo suficiente, no', () async {
      await livingNote(chars: kDevelopingMinChars - 1);

      expect(await organize('n'), AiStepReport.nothing);
      expect(await suggestionsOf('n'), isEmpty);
    });

    test('ni una que no es viva', () async {
      await livingNote();
      await KnowledgeEntryWriter(vault.db).setNoteKind('n', NoteKind.atomic);

      expect(await organize('n'), AiStepReport.nothing);
    });

    test('no repite la pendiente ni la que la persona descartó', () async {
      await livingNote();
      await organize('n');
      expect(await organize('n'), AiStepReport.nothing);

      final pending = (await suggestionsOf('n')).single;
      await vault.suggestions.reject(pending.id);

      expect(await organize('n'), AiStepReport.nothing);
      expect(await suggestionsOf('n'), hasLength(1));
      expect(await topics.maturityOf('n'), NoteMaturity.seed);
    });
  });
}
