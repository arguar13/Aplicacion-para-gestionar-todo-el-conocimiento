import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide Order;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_atlas_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/atlas_topics.dart';

void main() {
  late AiOrganizeHarness vault;
  late AtlasTopics topics;
  late AiAtlasRepositoryImpl atlas;
  late String historia;
  late String roma;

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
    historia = await topics.add('Historia antigua');
    await topics.add('Grecia', parentId: historia);
    roma = await topics.add('Roma');
  });

  tearDown(() => vault.close());

  /// El valor de [result], o la prueba falla con el motivo.
  T right<T>(Either<Failure, T> result) =>
      result.getOrElse((failure) => fail('$failure'));

  const blocks = [
    ContentBlock.paragraph(text: 'Índice.'),
    ContentBlock.bulletItem(text: '[[Las legiones]]'),
  ];

  group('el árbol de temas', () {
    test('se lee entero, con sus caminos y lo que está suelto', () async {
      final tree = right(await atlas.topicTree());

      expect(tree.isLoose(roma), isTrue);
      expect(tree.isLoose(historia), isFalse);
      expect(tree.isInTree(historia), isTrue);
      expect(tree.pathOf('t-Grecia'), 'Historia antigua › Grecia');
    });

    test(
      'ubicar solo deja el tema bajo el padre y el registro con su pasada',
      () async {
        await vault.source('a', title: 'Las legiones', content: 'Roma.');
        final run = await vault.startRun('a');

        final placed = await atlas.applyTopicPlacement(
          itemId: 'a',
          runId: run,
          valueId: roma,
          parentId: historia,
        );

        expect(placed.getRight().toNullable(), isTrue);
        expect(await topics.parentOf(roma), historia);
        expect(right(await atlas.hasPlacementRecord(roma)), isTrue);
        final record =
            right(await vault.suggestions.suggestionsFor('a')).single
                as TopicParentSuggestion;
        expect(
          (record.status, record.aiRunId),
          (SuggestionStatus.accepted, run),
        );
      },
    );

    test('un tema que dejó de estar suelto mientras el modelo pensaba no se '
        'toca', () async {
      await vault.source('a', title: 'Las legiones', content: 'Roma.');
      final run = await vault.startRun('a');
      // La persona le colgó un subtema.
      await topics.add('Roma imperial', parentId: roma);

      final placed = await atlas.applyTopicPlacement(
        itemId: 'a',
        runId: run,
        valueId: roma,
        parentId: historia,
      );

      expect(placed.getRight().toNullable(), isFalse);
      expect(await topics.parentOf(roma), isNull);
      expect(right(await atlas.hasPlacementRecord(roma)), isFalse);
    });
  });

  group('lo que junta un tema', () {
    test('los elementos vivos de la rama, con sus valores, sin las notas mapa '
        'ni la papelera', () async {
      await vault.source('a', title: 'A', content: 'x');
      await vault.source('b', title: 'B', content: 'x');
      await vault.note('c', title: 'C', content: 'x');
      await vault.source('borrado', title: 'Borrado', content: 'x');
      await vault.note('mapa', title: 'Mapa', content: 'x');
      await KnowledgeEntryWriter(vault.db).setNoteKind('mapa', NoteKind.map);
      const grecia = 't-Grecia';
      await topics.tag('a', historia);
      await topics.tag('a', grecia);
      await topics.tag('b', grecia);
      await topics.tag('c', historia);
      await topics.tag('borrado', historia);
      await topics.tag('mapa', historia);
      await vault.library.delete('borrado');

      final material = right(await atlas.topicMaterial({historia, grecia}));

      final byId = {for (final m in material) m.itemId: m};
      expect(byId.keys, unorderedEquals(['a', 'b', 'c']));
      expect(byId['a']!.valueIds, {historia, grecia});
      expect(byId['c']!.noteKind, NoteKind.living);
      expect(byId['b']!.isNote, isFalse);
    });

    test('el comienzo de cada uno: los bloques se leen como texto', () async {
      await vault.source('a', title: 'A', content: 'palabra ' * 100);
      await vault.note('n', title: 'N', content: 'x');
      await (vault.db.update(
        vault.db.renditions,
      )..where((r) => r.itemId.equals('n'))).write(
        RenditionsCompanion(
          kind: const Value(RenditionKind.blocks),
          content: Value(
            encodeContentBlocks(const [
              ContentBlock.heading(text: 'Título'),
              ContentBlock.paragraph(text: 'Texto de la nota.'),
            ]),
          ),
        ),
      );

      final excerpts = right(await atlas.excerptsOf(['a', 'n'], chars: 30));

      expect(excerpts['a'], 'palabra palabra palabra…');
      expect(excerpts['n'], 'Título Texto de la nota.');
    });
  });

  group('las notas mapa de la IA', () {
    test(
      'nace como nota mapa de la IA, con el tema puesto en su propia pasada, '
      'y la cola no la organiza',
      () async {
        final noteId = right(
          await atlas.createMapNote(
            valueId: historia,
            title: 'Mapa de Historia antigua',
            blocks: blocks,
            model: 'gemma',
          ),
        )!;

        final row = await (vault.db.select(
          vault.db.knowledgeNotes,
        )..where((n) => n.itemId.equals(noteId))).getSingle();
        expect((row.noteKind, row.generatedByModel), (NoteKind.map, 'gemma'));
        final note = await vault.reload(noteId);
        final tag = note.tags.single;
        expect(tag.id, historia);
        final assignment = await (vault.db.select(
          vault.db.itemPropertyValues,
        )..where((a) => a.itemId.equals(noteId))).getSingle();
        expect(assignment.origin, ItemPropertyOrigin.ai);
        final run = right(await vault.runs.listRuns(itemId: noteId)).single;
        expect(run.finishedAt, isNotNull);
        expect(run.created.properties, 1);

        final maps = right(await atlas.mapNotesOf(historia));
        expect(maps.single.keptByAi, isTrue);
        // Un índice no se vincula ni se vuelve tarjetas: tiene su pasada.
        expect(
          await AiOrganizeBacklogImpl(vault.db).nextFresh(
            since: DateTime(2000),
            notesQuietBefore: vault.now.add(const Duration(days: 1)),
          ),
          isNull,
        );
      },
    );

    test('no nace si el tema ya tiene una nota mapa', () async {
      await vault.note('mia', title: 'Mi mapa', content: 'x');
      await KnowledgeEntryWriter(vault.db).setNoteKind('mia', NoteKind.map);
      await topics.tag('mia', historia);

      final created = await atlas.createMapNote(
        valueId: historia,
        title: 'Mapa de Historia antigua',
        blocks: blocks,
        model: 'gemma',
      );

      expect(created.getRight().toNullable(), isNull);
      expect(right(await atlas.mapNotesOf(historia)), hasLength(1));
    });

    test('se actualiza solo si sigue siendo la que escribió la IA', () async {
      final noteId = right(
        await atlas.createMapNote(
          valueId: historia,
          title: 'Mapa de Historia antigua',
          blocks: blocks,
          model: 'gemma',
        ),
      )!;
      final before = right(
        await atlas.mapNotesOf(historia),
      ).single.blocksContent;
      const fresh = [ContentBlock.paragraph(text: 'Índice nuevo.')];

      // Con otro contenido del que se leyó: alguien la cambió en el medio.
      expect(
        right(
          await atlas.updateMapNote(
            noteId: noteId,
            expectedContent: '[]',
            blocks: fresh,
          ),
        ),
        isFalse,
      );
      expect(
        right(
          await atlas.updateMapNote(
            noteId: noteId,
            expectedContent: before,
            blocks: fresh,
          ),
        ),
        isTrue,
      );
      final updated = right(await atlas.mapNotesOf(historia)).single;
      expect(updated.blocksContent, encodeContentBlocks(fresh));

      // Editada por la persona: ya es suya.
      await KnowledgeEntryWriter(vault.db).markDerivedEdited(noteId);
      expect(
        right(
          await atlas.updateMapNote(
            noteId: noteId,
            expectedContent: updated.blocksContent,
            blocks: blocks,
          ),
        ),
        isFalse,
      );
    });

    test('lo que la persona le sacó no vuelve: a la papelera, la pasada '
        'deshecha o «no era» en el tema', () async {
      Future<bool> declined() async => right(
        await atlas.mapNoteDeclined(
          historia,
          title: 'Mapa de Historia antigua',
        ),
      );
      expect(await declined(), isFalse);

      // A la papelera.
      final first = right(
        await atlas.createMapNote(
          valueId: historia,
          title: 'Mapa de Historia antigua',
          blocks: blocks,
          model: 'gemma',
        ),
      )!;
      await vault.library.delete(first);
      expect(await declined(), isTrue);
      await vault.library.purge([first]);
      expect(await declined(), isFalse);

      // La pasada deshecha: la nota queda, sin el tema.
      final second = right(
        await atlas.createMapNote(
          valueId: historia,
          title: 'Mapa de Historia antigua',
          blocks: blocks,
          model: 'gemma',
        ),
      )!;
      final run = right(await vault.runs.listRuns(itemId: second)).single;
      await vault.runs.undoRun(run.id);
      expect(right(await atlas.mapNotesOf(historia)), isEmpty);
      expect(await declined(), isTrue);
      await vault.library.purge([second]);

      // «No era» el tema en la nota mapa de la IA.
      final third = right(
        await atlas.createMapNote(
          valueId: historia,
          title: 'Otro título',
          blocks: blocks,
          model: 'gemma',
        ),
      )!;
      await vault.organize.rejectAiProperty(
        itemId: third,
        propertyValueId: historia,
      );
      expect(await declined(), isTrue);
    });
  });

  group('cuánto creció una nota', () {
    test(
      'sus vínculos vivos, en los dos sentidos, sin contar índices',
      () async {
        await vault.note('n', title: 'Roma', content: 'x');
        await vault.source('a', title: 'A', content: 'x');
        await vault.source('b', title: 'B', content: 'x');
        await vault.source('borrado', title: 'Borrado', content: 'x');
        await vault.note('mapa', title: 'Mapa', content: 'x');
        await KnowledgeEntryWriter(vault.db).setNoteKind('mapa', NoteKind.map);
        for (final (from, to) in [
          ('n', 'a'),
          ('b', 'n'),
          ('a', 'n'),
          ('n', 'borrado'),
          ('mapa', 'n'),
        ]) {
          await vault.organize.createRelation(
            fromItemId: from,
            toItemId: to,
            kind: from == 'a' ? RelationKind.cites : RelationKind.relatedTo,
          );
        }
        await vault.library.delete('borrado');

        final growth = right(await atlas.noteGrowth('n'))!;

        expect(growth.connections, 2);
        expect(growth.noteKind, NoteKind.living);
        expect(growth.maturity, NoteMaturity.seed);
        expect(right(await atlas.noteGrowth('a')), isNull);
      },
    );

    test('proponer la madurez la deja pendiente y no la cambia', () async {
      await vault.note('n', title: 'Roma', content: 'x');

      await atlas.proposeMaturity(
        itemId: 'n',
        from: NoteMaturity.seed,
        to: NoteMaturity.developing,
      );

      final pending =
          (await vault.suggestions.watchPendingSuggestions('n').first).single
              as MaturitySuggestion;
      expect(pending.to, NoteMaturity.developing);
      expect(await topics.maturityOf('n'), NoteMaturity.seed);
    });
  });
}
