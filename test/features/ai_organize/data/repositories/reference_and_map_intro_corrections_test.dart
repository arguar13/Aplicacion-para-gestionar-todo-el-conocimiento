import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Either, Left, Unit, right, unit;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/correction_suggestions.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/reviewable_ai_thing.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_atlas_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/atlas_topics.dart';

/// Las correcciones de «Revisar con otro modelo» (F33, 4c) sobre los datos de
/// la referencia y la introducción de las notas mapa: con los repositorios de
/// verdad, porque las dos cosas las escriben el registro de la pasada y el
/// Atlas.
void main() {
  late AiOrganizeHarness vault;

  setUp(() => vault = AiOrganizeHarness());
  tearDown(() => vault.close());

  T ok<T>(Either<Failure, T> result) =>
      result.getOrElse((failure) => fail('$failure'));

  Future<String> reviewRun(String itemId) async => ok(
    await vault.runs.startRun(
      itemId,
      model: 'gemini-3.8-flash',
      scope: AiRunScope.review,
    ),
  );

  /// Lo que recuerda la pasada [run] de haber completado [field].
  Future<String> changeOf(String run, AiChangedField field) async =>
      (await (vault.db.select(vault.db.aiFieldChanges)..where(
                (c) => c.aiRunId.equals(run) & c.field.equalsValue(field),
              ))
              .getSingle())
          .id;

  Future<SuggestionStatus> statusOf(String id) async => (await (vault.db.select(
    vault.db.suggestions,
  )..where((s) => s.id.equals(id))).getSingle()).status;

  group('los datos de la referencia', () {
    setUp(() async {
      await vault.source('a', title: 'Rayuela', content: 'Una novela.');
    });

    /// La pasada que completó la editorial —y el tipo de obra y el ISBN— de
    /// «a», y lo que recuerda de la editorial.
    Future<({String run, String change})> aiReference() async {
      final run = await vault.startRun('a');
      ok(
        await vault.runs.completeReference(
          runId: run,
          itemId: 'a',
          extracted: const ExtractedMetadata(
            reference: ReferenceData(
              type: ReferenceType.book,
              publisher: 'Planeta',
              isbn: '9788437604947',
            ),
          ),
        ),
      );
      await vault.runs.finishRun(run);
      return (run: run, change: await changeOf(run, AiChangedField.publisher));
    }

    Future<ReferenceData> referenceOfA() => ReferenceReader(vault.db).read('a');

    Future<void> personWrites(String? publisher) async {
      final current = await referenceOfA();
      await KnowledgeEntryWriter(vault.db).setReference(
        'a',
        ReferenceData(
          type: current.type,
          publisher: publisher,
          isbn: current.isbn,
        ),
      );
    }

    Future<CorrectionSuggestion> propose(
      String change,
      String run, {
      Map<String, String>? after = const {
        ReferenceCorrectionField.field: 'publisher',
        ReferenceCorrectionField.type: 'book',
        ReferenceCorrectionField.value: 'Sudamericana',
      },
      String field = 'publisher',
      String value = 'Planeta',
    }) async =>
        ok(
              await vault.suggestions.createCorrectionSuggestion(
                targetItemId: 'a',
                subject: CorrectionSubject.reference,
                subjectId: change,
                before: {
                  ReferenceCorrectionField.field: field,
                  ReferenceCorrectionField.type: 'book',
                  ReferenceCorrectionField.value: value,
                },
                after: after,
                reason: 'La primera edición es de Sudamericana.',
                aiRunId: run,
                model: 'gemini-3.8-flash',
              ),
            )
            as CorrectionSuggestion;

    Map<String, String> publisher(String value) => {
      ReferenceCorrectionField.field: 'publisher',
      ReferenceCorrectionField.type: 'book',
      ReferenceCorrectionField.value: value,
    };

    test('aceptar lo corrige tal como queda guardado y sigue siendo de la IA: '
        'deshacer la pasada que lo completó lo vacía', () async {
      final made = await aiReference();
      final correction = await propose(
        made.change,
        await reviewRun('a'),
        after: publisher('  Sudamericana  '),
      );

      expect(
        await vault.suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );
      expect((await referenceOfA()).publisher, 'Sudamericana');
      final read = correctionSuggestionOf(
        await (vault.db.select(
          vault.db.suggestions,
        )..where((s) => s.id.equals(correction.id))).getSingle(),
      );
      expect(read.after![ReferenceCorrectionField.value], 'Sudamericana');

      await vault.runs.undoRun(made.run);
      final after = await referenceOfA();
      expect(after.publisher, isNull);
      expect(after.isbn, isNull);
    });

    test(
      'no pone un valor que no sirve ni el mismo, y no deja nada a medias',
      () async {
        final made = await aiReference();
        final run = await reviewRun('a');
        final isbn = await changeOf(made.run, AiChangedField.isbn);
        final invalid = await propose(
          isbn,
          run,
          field: 'isbn',
          value: '9788437604947',
          after: const {
            ReferenceCorrectionField.field: 'isbn',
            ReferenceCorrectionField.type: 'book',
            ReferenceCorrectionField.value: 'no es un isbn',
          },
        );
        expect(
          await vault.suggestions.accept(invalid.id),
          isA<Left<Failure, Unit>>(),
        );
        expect((await referenceOfA()).isbn, '9788437604947');

        for (final value in ['Planeta', ' ', '']) {
          final same = await propose(made.change, run, after: publisher(value));
          expect(
            await vault.suggestions.accept(same.id),
            isA<Left<Failure, Unit>>(),
            reason: value,
          );
        }
        expect((await referenceOfA()).publisher, 'Planeta');
      },
    );

    test(
      'no toca el que la persona cambió, ni el de una pasada deshecha',
      () async {
        final made = await aiReference();
        final run = await reviewRun('a');
        final adopted = await propose(made.change, run);
        await personWrites('Alfaguara');
        expect(
          await vault.suggestions.accept(adopted.id),
          isA<Left<Failure, Unit>>(),
        );
        expect((await referenceOfA()).publisher, 'Alfaguara');

        // Lo que vio el modelo es lo de hoy, pero lo puso la persona.
        final same = await propose(made.change, run, value: 'Alfaguara');
        expect(await stillApplicableCorrections(vault.db, [same]), isEmpty);

        await personWrites('Planeta');
        final stale = await propose(made.change, run);
        await vault.runs.undoRun(made.run);
        await personWrites('Planeta');
        expect(
          await vault.suggestions.accept(stale.id),
          isA<Left<Failure, Unit>>(),
        );
      },
    );

    test('el tipo de obra, las personas y la fecha no se corrigen', () async {
      final made = await aiReference();
      final type = await changeOf(made.run, AiChangedField.referenceType);
      final correction = await propose(
        type,
        await reviewRun('a'),
        field: 'referenceType',
        value: 'book',
        after: const {
          ReferenceCorrectionField.field: 'referenceType',
          ReferenceCorrectionField.type: 'book',
          ReferenceCorrectionField.value: 'article',
        },
      );

      expect(await stillApplicableCorrections(vault.db, [correction]), isEmpty);
      expect(
        await vault.suggestions.accept(correction.id),
        isA<Left<Failure, Unit>>(),
      );
      expect((await referenceOfA()).type, ReferenceType.book);
    });

    test('vaciarlo lo deja vacío; deshacer la revisión lo vuelve a poner, y '
        'sigue siendo de la IA', () async {
      final made = await aiReference();
      final run = await reviewRun('a');
      await vault.suggestions.accept(
        (await propose(made.change, run, after: null)).id,
      );
      expect((await referenceOfA()).publisher, isNull);
      expect((await referenceOfA()).isbn, '9788437604947');

      expect(
        ok(await vault.runs.undoRun(run)),
        const AiRunTally(corrections: 1),
      );
      expect((await referenceOfA()).publisher, 'Planeta');

      await vault.runs.undoRun(made.run);
      expect((await referenceOfA()).publisher, isNull);
    });

    test('deshacer la revisión que lo corrigió devuelve el de antes, y la '
        'pasada que lo completó lo sigue reconociendo', () async {
      final made = await aiReference();
      final run = await reviewRun('a');
      final correction = await propose(made.change, run);
      await vault.suggestions.accept(correction.id);

      expect(
        ok(await vault.runs.undoRun(run)),
        const AiRunTally(corrections: 1),
      );
      expect((await referenceOfA()).publisher, 'Planeta');
      expect(await statusOf(correction.id), SuggestionStatus.rejected);

      await vault.runs.undoRun(made.run);
      expect((await referenceOfA()).publisher, isNull);
    });

    test('deshacer no pisa lo que la persona escribió después de vaciarlo, '
        'ni devuelve el de una pasada deshecha', () async {
      final made = await aiReference();
      final run = await reviewRun('a');
      await vault.suggestions.accept(
        (await propose(made.change, run, after: null)).id,
      );
      await personWrites('Alfaguara');

      expect(ok(await vault.runs.undoRun(run)), const AiRunTally());
      expect((await referenceOfA()).publisher, 'Alfaguara');
    });

    test(
      'el vaciado no vuelve si la pasada que lo completó se deshizo',
      () async {
        final made = await aiReference();
        final run = await reviewRun('a');
        await vault.suggestions.accept(
          (await propose(made.change, run, after: null)).id,
        );
        await vault.runs.undoRun(made.run);

        expect(ok(await vault.runs.undoRun(run)), const AiRunTally());
        expect((await referenceOfA()).publisher, isNull);
      },
    );

    test(
      '«Revisión» lo ofrece hasta que la persona edita la referencia',
      () async {
        final made = await aiReference();
        await propose(made.change, await reviewRun('a'));
        final queue = StreamQueue(vault.suggestions.watchPendingCorrections());
        addTearDown(queue.cancel);

        expect((await queue.next).single.corrections, hasLength(1));
        await personWrites('Alfaguara');
        expect(await queue.next, isEmpty);
      },
    );

    test('lo que sigue en pie cuenta el dato corregido hasta que la persona '
        'lo cambia', () async {
      final made = await aiReference();
      final run = await reviewRun('a');
      await vault.suggestions.accept((await propose(made.change, run)).id);

      expect(await aiCorrectionCounts(vault.db, [run]), {
        run: (created: 1, remaining: 1),
      });
      await personWrites('Alfaguara');
      expect(await aiCorrectionCounts(vault.db, [run]), {
        run: (created: 1, remaining: 0),
      });
    });
  });

  group('la introducción de una nota mapa', () {
    late AiAtlasRepositoryImpl atlas;
    late String historia;

    const intro = 'Lo que la IA dice del tema.';
    const withIntro = [
      ContentBlock.paragraph(text: intro),
      ContentBlock.heading(text: 'Roma', level: 2),
      ContentBlock.bulletItem(text: '[[Las legiones]]'),
    ];

    setUp(() async {
      atlas = AiAtlasRepositoryImpl(
        database: vault.db,
        library: vault.library,
        organize: vault.organize,
        runs: vault.runs,
        telemetry: vault.telemetry,
        ids: vault.ids,
        clock: vault.clock,
      );
      historia = await AtlasTopics(vault.db).add('Historia antigua');
    });

    Future<String> aiMapNote({List<ContentBlock> blocks = withIntro}) async =>
        ok(
          await atlas.createMapNote(
            valueId: historia,
            title: 'Mapa de Historia antigua',
            blocks: blocks,
            model: 'gemma',
          ),
        )!;

    Future<List<ContentBlock>> blocksOf(String noteId) async =>
        tryDecodeContentBlocks(
          (await (vault.db.select(vault.db.renditions)..where(
                    (r) =>
                        r.itemId.equals(noteId) &
                        r.kind.equalsValue(RenditionKind.blocks),
                  ))
                  .getSingle())
              .content!,
        )!;

    Future<bool> keptByAi() async =>
        ok(await atlas.mapNotesOf(historia)).single.keptByAi;

    Future<CorrectionSuggestion> propose(
      String noteId,
      String run, {
      Map<String, String>? after = const {
        MapIntroCorrectionField.text: 'Una introducción mejor.',
      },
      String before = intro,
    }) async =>
        ok(
              await vault.suggestions.createCorrectionSuggestion(
                targetItemId: noteId,
                subject: CorrectionSubject.mapIntro,
                subjectId: noteId,
                before: {MapIntroCorrectionField.text: before},
                after: after,
                reason: 'Dice algo que los elementos no dicen.',
                aiRunId: run,
                model: 'gemini-3.8-flash',
              ),
            )
            as CorrectionSuggestion;

    test('aceptar cambia solo la introducción, en un párrafo, y la nota sigue '
        'siendo de la IA', () async {
      final note = await aiMapNote();
      final correction = await propose(
        note,
        await reviewRun(note),
        after: const {
          MapIntroCorrectionField.text: '  Una introducción\n\nmejor.  ',
        },
      );

      expect(
        await vault.suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );
      expect(await blocksOf(note), [
        const ContentBlock.paragraph(text: 'Una introducción mejor.'),
        ...withIntro.skip(1),
      ]);
      expect(await keptByAi(), isTrue);
    });

    test('no la saca, no la deja vacía, no le pone enlaces ni la cambia por '
        'lo mismo', () async {
      final note = await aiMapNote();
      final run = await reviewRun(note);
      for (final after in <Map<String, String>?>[
        null,
        const {MapIntroCorrectionField.text: '  '},
        const {MapIntroCorrectionField.text: 'Ver [[Las legiones]].'},
        const {MapIntroCorrectionField.text: intro},
      ]) {
        final correction = await propose(note, run, after: after);
        expect(
          await vault.suggestions.accept(correction.id),
          isA<Left<Failure, Unit>>(),
          reason: '$after',
        );
      }
      expect(await blocksOf(note), withIntro);
    });

    test('no toca una nota mapa que la persona editó, ni una sin '
        'introducción', () async {
      final edited = await aiMapNote();
      final run = await reviewRun(edited);
      final onEdited = await propose(edited, run);
      await KnowledgeEntryWriter(vault.db).markDerivedEdited(edited);
      expect(
        await vault.suggestions.accept(onEdited.id),
        isA<Left<Failure, Unit>>(),
      );
      await vault.library.delete(edited);
      await vault.library.purge([edited]);

      final bare = await aiMapNote(blocks: withIntro.skip(1).toList());
      final onBare = await propose(bare, await reviewRun(bare));
      expect(await stillApplicableCorrections(vault.db, [onBare]), isEmpty);
      expect(
        await vault.suggestions.accept(onBare.id),
        isA<Left<Failure, Unit>>(),
      );
    });

    test('ni una en la papelera', () async {
      final note = await aiMapNote();
      final correction = await propose(note, await reviewRun(note));
      await vault.library.delete(note);

      expect(await stillApplicableCorrections(vault.db, [correction]), isEmpty);
    });

    test('ni una que la IA soltó: deshicieron su pasada y la recuperaron de '
        'la papelera', () async {
      final note = await aiMapNote();
      final run = await reviewRun(note);
      final correction = await propose(note, run);
      final created = ok(
        await vault.runs.listRuns(itemId: note),
      ).firstWhere((r) => r.id != run);
      await vault.runs.undoRun(created.id);
      await vault.library.restore(note);

      expect(await stillApplicableCorrections(vault.db, [correction]), isEmpty);
    });

    test('ni una nota mapa de la persona, ni una cuyo único párrafo no '
        'presenta un índice', () async {
      await vault.note('mia', title: 'Mi mapa', content: 'x');
      final writer = KnowledgeEntryWriter(vault.db);
      await writer.setNoteKind('mia', NoteKind.map);
      await vault.db
          .into(vault.db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'bloques-mia',
              itemId: 'mia',
              kind: RenditionKind.blocks,
              isPrimary: true,
              createdAt: vault.now,
              content: Value(encodeContentBlocks(withIntro)),
            ),
          );
      final mine = await propose('mia', await reviewRun('mia'));
      expect(await stillApplicableCorrections(vault.db, [mine]), isEmpty);

      final lone = await aiMapNote(
        blocks: const [ContentBlock.paragraph(text: intro)],
      );
      final onLone = await propose(lone, await reviewRun(lone));
      expect(await stillApplicableCorrections(vault.db, [onLone]), isEmpty);
    });

    test('deshacer la revisión devuelve la de antes, y la IA sigue '
        'manteniendo la nota', () async {
      final note = await aiMapNote();
      // La revisión empieza después: es la última pasada sobre la nota.
      vault.now = vault.now.add(const Duration(minutes: 1));
      final run = await reviewRun(note);
      final correction = await propose(note, run);
      await vault.suggestions.accept(correction.id);

      expect(
        ok(await vault.runs.undoRun(run)),
        const AiRunTally(corrections: 1),
      );

      expect(await blocksOf(note), withIntro);
      expect(await statusOf(correction.id), SuggestionStatus.rejected);
      // Deshacer una revisión no es soltar la nota: el Atlas la sigue
      // actualizando, y una revisión nueva la puede corregir.
      expect(await keptByAi(), isTrue);
      final current = ok(await atlas.mapNotesOf(historia)).single;
      const updated = [
        ContentBlock.paragraph(text: 'Otra introducción.'),
        ContentBlock.heading(text: 'Roma', level: 2),
      ];
      expect(
        ok(
          await atlas.updateMapNote(
            noteId: note,
            expectedContent: current.blocksContent,
            blocks: updated,
          ),
        ),
        isTrue,
      );
      final again = await propose(
        note,
        await reviewRun(note),
        before: 'Otra introducción.',
      );
      expect(await stillApplicableCorrections(vault.db, [again]), hasLength(1));
    });

    test('se da a revisar la introducción, que no se saca; una nota sin '
        'introducción no tiene nada que revisar', () async {
      final note = await aiMapNote();
      final thing = (await reviewableAiThings(vault.db, note)).single;
      expect(thing.subject, CorrectionSubject.mapIntro);
      expect(thing.before, {MapIntroCorrectionField.text: intro});
      expect((thing.canFix, thing.canRemove), (true, false));
      expect(thing.model, 'gemma');
      await vault.library.delete(note);
      await vault.library.purge([note]);

      final bare = await aiMapNote(blocks: withIntro.skip(1).toList());
      expect(await reviewableAiThings(vault.db, bare), isEmpty);
    });

    test('deshacer no pisa la introducción que cambió después', () async {
      final note = await aiMapNote();
      final run = await reviewRun(note);
      await vault.suggestions.accept((await propose(note, run)).id);
      final current = ok(await atlas.mapNotesOf(historia)).single;
      const rewritten = [
        ContentBlock.paragraph(text: 'La IA la volvió a escribir.'),
        ContentBlock.heading(text: 'Roma', level: 2),
      ];
      ok(
        await atlas.updateMapNote(
          noteId: note,
          expectedContent: current.blocksContent,
          blocks: rewritten,
        ),
      );

      expect(ok(await vault.runs.undoRun(run)), const AiRunTally());
      expect(await blocksOf(note), rewritten);
    });

    test('deshacer la pasada que la creó la manda a la papelera aunque esté '
        'corregida', () async {
      final note = await aiMapNote();
      final run = await reviewRun(note);
      await vault.suggestions.accept((await propose(note, run)).id);
      final created = ok(
        await vault.runs.listRuns(itemId: note),
      ).firstWhere((r) => r.id != run);

      await vault.runs.undoRun(created.id);

      expect(ok(await atlas.mapNotesOf(historia)), isEmpty);
      expect(ok(await vault.runs.undoRun(run)), const AiRunTally());
    });

    test('«Revisión» la ofrece hasta que la persona edita la nota, y lo que '
        'sigue en pie la cuenta hasta entonces', () async {
      final note = await aiMapNote();
      final run = await reviewRun(note);
      await propose(note, run);
      final queue = StreamQueue(vault.suggestions.watchPendingCorrections());
      addTearDown(queue.cancel);

      expect((await queue.next).single.corrections, hasLength(1));
      await KnowledgeEntryWriter(vault.db).markDerivedEdited(note);
      expect(await queue.next, isEmpty);
    });

    test('lo que sigue en pie cuenta la introducción corregida hasta que la '
        'persona edita la nota', () async {
      final note = await aiMapNote();
      final run = await reviewRun(note);
      await vault.suggestions.accept((await propose(note, run)).id);

      expect(await aiCorrectionCounts(vault.db, [run]), {
        run: (created: 1, remaining: 1),
      });
      await KnowledgeEntryWriter(vault.db).markDerivedEdited(note);
      expect(await aiCorrectionCounts(vault.db, [run]), {
        run: (created: 1, remaining: 0),
      });
    });
  });

  group('lo que se le da a revisar (F33, 4d)', () {
    late String tema;

    setUp(() async {
      await vault.source('a', title: 'Rayuela', content: 'Una novela.');
      await vault.source('b', title: 'Cortázar', content: 'Un escritor.');
      tema = await temaDefinitionId(vault.db);
      for (final (id, name) in [('lit', 'Literatura'), ('arte', 'Arte')]) {
        await vault.db
            .into(vault.db.spaces)
            .insert(
              SpacesCompanion.insert(id: id, name: name, createdAt: vault.now),
            );
      }
      // «Novela» ya está en el vocabulario: la usa otro elemento.
      ok(
        await vault.organize.assignProperty(
          itemId: 'b',
          definitionId: tema,
          value: 'Novela',
        ),
      );
    });

    /// Una pasada de Gemma sobre «a» que hace de todo.
    Future<String> organizeA() async {
      final run = ok(await vault.runs.startRun('a', model: 'Gemma 4 E4B'));
      ok(
        await vault.organize.createRelation(
          fromItemId: 'a',
          toItemId: 'b',
          kind: RelationKind.relatedTo,
          note: 'El autor.',
          ai: AiProvenance(runId: run),
        ),
      );
      ok(
        await vault.organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Cuento',
          origin: ItemPropertyOrigin.ai,
          aiRunId: run,
        ),
      );
      ok(await vault.runs.applySpace(runId: run, itemId: 'a', spaceId: 'arte'));
      ok(
        await vault.runs.completeReference(
          runId: run,
          itemId: 'a',
          extracted: const ExtractedMetadata(
            reference: ReferenceData(publisher: 'Sudamericana'),
          ),
        ),
      );
      await vault.runs.finishRun(run);
      return run;
    }

    test('el vínculo, la etiqueta, el tema y la editorial, cada uno con su '
        'antes, su pasada y lo que vale al corregirlo', () async {
      final run = await organizeA();

      final things = await reviewableAiThings(vault.db, 'a');

      expect(
        [for (final t in things) t.subject],
        [
          CorrectionSubject.relation,
          CorrectionSubject.property,
          CorrectionSubject.space,
          CorrectionSubject.reference,
        ],
      );
      expect({for (final t in things) t.aiRunId}, {run});
      expect({for (final t in things) t.model}, {'Gemma 4 E4B'});

      final [relation, tag, space, reference] = things;
      expect(relation.before, {
        RelationCorrectionField.kind: 'relatedTo',
        RelationCorrectionField.note: 'El autor.',
      });
      expect(relation.label, 'Cortázar');
      expect(relation.relatedItemId, 'b');
      expect(
        [for (final o in relation.options) o.id],
        [
          for (final kind in RelationKind.values)
            if (!kind.isStructural) kind.name,
        ],
      );

      expect(tag.before, {
        PropertyCorrectionField.category: kTemaCategoryName,
        PropertyCorrectionField.value: 'Cuento',
      });
      expect([
        for (final o in tag.options) o.label,
      ], containsAll(['Cuento', 'Novela']));
      expect(tag.canFix, isTrue);

      expect(space.before, {
        SpaceCorrectionField.id: 'arte',
        SpaceCorrectionField.name: 'Arte',
      });
      expect(space.options, const [
        ReviewOption(id: 'arte', label: 'Arte'),
        ReviewOption(id: 'lit', label: 'Literatura'),
      ]);

      expect(reference.before, {
        ReferenceCorrectionField.field: 'publisher',
        ReferenceCorrectionField.type: '',
        ReferenceCorrectionField.value: 'Sudamericana',
      });
      expect(reference.options, isEmpty);
      expect(reference.canRemove, isTrue);
    });

    test('deja afuera lo que ya es de la persona y lo que hizo una pasada de '
        'otro elemento', () async {
      await organizeA();
      final relation = await vault.db.select(vault.db.relations).getSingle();
      ok(
        await vault.organize.updateRelation(
          relation.id,
          kind: RelationKind.relatedTo,
          note: 'Mía.',
        ),
      );
      ok(
        await vault.organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Cuento',
        ),
      );
      await KnowledgeEntryWriter(vault.db).setSpaces(['a'], {'lit'});
      await KnowledgeEntryWriter(
        vault.db,
      ).setReference('a', const ReferenceData(publisher: 'Alfaguara'));
      // Lo que hizo una pasada sobre «b» no es de «a», aunque vincule a «a».
      final onB = ok(await vault.runs.startRun('b', model: 'Gemma 4 E4B'));
      ok(
        await vault.organize.createRelation(
          fromItemId: 'b',
          toItemId: 'a',
          kind: RelationKind.cites,
          ai: AiProvenance(runId: onB),
        ),
      );

      expect(await reviewableAiThings(vault.db, 'a'), isEmpty);
      expect(
        [for (final t in await reviewableAiThings(vault.db, 'b')) t.label],
        ['Rayuela'],
      );
    });

    test(
      'una etiqueta que no es de texto se puede sacar pero no corregir',
      () async {
        await vault.db
            .into(vault.db.propertyDefinitions)
            .insert(
              PropertyDefinitionsCompanion.insert(
                id: 'paginas',
                name: 'Páginas',
                createdAt: vault.now,
                type: const Value(PropertyValueType.number),
              ),
            );
        final run = ok(await vault.runs.startRun('a', model: 'Gemma 4 E4B'));
        ok(
          await vault.organize.assignProperty(
            itemId: 'a',
            definitionId: 'paginas',
            value: '320',
            origin: ItemPropertyOrigin.ai,
            aiRunId: run,
          ),
        );

        final thing = (await reviewableAiThings(vault.db, 'a')).single;
        expect((thing.canFix, thing.canRemove), (false, true));
        expect(thing.options, isEmpty);
      },
    );
  });
}
