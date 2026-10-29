import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_repository_impl.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_sql.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';

import '../../../support/in_memory_file_store.dart';
import '../creations_harness.dart';

class _Telemetry extends Mock implements TelemetryService {}

/// «Lo creado» en la base (F43): crear, el estado que escribe la cola, las
/// listas por recorte que se actualizan solas y la papelera.
void main() {
  late CreationsHarness h;

  setUp(() async => h = await CreationsHarness.create());
  tearDown(() => h.close());

  Future<StudyCreation> create(
    StudyCreationKind kind, {
    CreationScope scope = const CreationScope.allProcessed(),
    List<String> sources = const ['doc-a'],
    bool runNow = true,
  }) async => (await h.creations.create(
    CreationRequest(
      kind: kind,
      scope: scope,
      sourceIds: sources,
      options: const {'numero': 'estandar'},
      runNow: runNow,
    ),
  )).getRight().toNullable()!;

  List<String> idsOf(List<StudyCreation> list) => [for (final c in list) c.id];

  group('crear', () {
    test('una de la IA nace en la cola, con lo que se eligió', () async {
      h.processed.vault.at(5);
      final created = await create(
        StudyCreationKind.mindMap,
        scope: const CreationScope.notebook('cuaderno'),
        sources: ['doc-a', 'doc-b'],
        runNow: false,
      );

      expect(created.status, CreationStatus.queued);
      expect(created.kind, StudyCreationKind.mindMap);
      expect(created.scope, const CreationScope.notebook('cuaderno'));
      expect(created.sourceIds, ['doc-a', 'doc-b']);
      expect(created.options, {'numero': 'estandar'});
      expect(created.languageCode, 'es');
      expect(created.runNow, isFalse);
      expect(created.title, isNull);
      expect(created.content, isNull);
      expect(created.createdAt, h.processed.vault.now);
    });

    test('una de extraer nace lista y sin contenido: es una vista viva '
        '(decisión E)', () async {
      for (final kind in [
        StudyCreationKind.fullText,
        StudyCreationKind.summary,
        StudyCreationKind.synthesis,
      ]) {
        final created = await create(kind);
        expect(created.status, CreationStatus.ready, reason: kind.name);
        expect(created.content, isNull, reason: kind.name);
      }
    });
  });

  group('lo que escribe la cola', () {
    test(
      'generándose, con su avance; lista, con su título y su contenido',
      () async {
        final created = await create(StudyCreationKind.report);
        await h.creations.markGenerating(created.id, modelName: 'Gemma');
        await h.creations.reportProgress(
          created.id,
          progress: 0.5,
          step: CreationStep.readingParts,
        );

        var now = (await h.creations.find(created.id)).getRight().toNullable()!;
        expect(now.status, CreationStatus.generating);
        expect(now.progress, 0.5);
        expect(now.step, CreationStep.readingParts);
        expect(now.attempts, 1);
        expect(now.modelName, 'Gemma');

        h.processed.vault.at(9);
        await h.creations.complete(
          created.id,
          title: '  Éxodo: Liberación y Alianza ',
          content: '{"secciones":[]}',
          contentVersion: 2,
          sourceIds: ['doc-a'],
        );
        now = (await h.creations.find(created.id)).getRight().toNullable()!;
        expect(now.status, CreationStatus.ready);
        expect(now.title, 'Éxodo: Liberación y Alianza');
        expect(now.content, '{"secciones":[]}');
        expect(now.decodedContent, {'secciones': <Object?>[]});
        expect(now.contentVersion, 2);
        expect(now.progress, isNull);
        expect(now.step, isNull);
        expect(now.attempts, 0);
        expect(now.updatedAt, h.processed.vault.now);
      },
    );

    test('fallida, con su motivo; reintentar la vuelve a la cola', () async {
      final created = await create(StudyCreationKind.quiz);
      await h.creations.markGenerating(created.id, modelName: null);
      await h.creations.fail(
        created.id,
        CreationFailure.unreadableReply,
        detail: 'No es JSON',
      );

      var now = (await h.creations.find(created.id)).getRight().toNullable()!;
      expect(now.status, CreationStatus.failed);
      expect(now.failure, CreationFailure.unreadableReply);
      expect(now.failureDetail, 'No es JSON');

      final requeued = (await h.creations.requeue(
        created.id,
        runNow: false,
        options: const {'numero': 'mas'},
        languageCode: 'en',
      )).getRight().toNullable()!;
      expect(requeued.status, CreationStatus.queued);
      expect(requeued.failure, isNull);
      expect(requeued.runNow, isFalse);
      expect(requeued.options, {'numero': 'mas'});
      expect(requeued.languageCode, 'en');
      now = requeued;
      expect(now.sourceIds, [
        'doc-a',
      ], reason: 'sin fuentes nuevas, las mismas');
    });

    test('el avance de una que no se está generando no se anota', () async {
      final created = await create(StudyCreationKind.quiz);
      await h.creations.reportProgress(
        created.id,
        progress: 0.7,
        step: CreationStep.writing,
      );
      final now = (await h.creations.find(created.id)).getRight().toNullable()!;
      expect(now.progress, isNull);
    });

    test('lo pendiente: primero lo de «ahora», y lo más viejo primero; nada '
        'de la papelera ni lo terminado', () async {
      h.processed.vault.at(1);
      final later1 = await create(StudyCreationKind.quiz, runNow: false);
      h.processed.vault.at(2);
      final now1 = await create(StudyCreationKind.report);
      h.processed.vault.at(3);
      final later2 = await create(StudyCreationKind.mindMap, runNow: false);
      h.processed.vault.at(4);
      final now2 = await create(StudyCreationKind.dataTable);
      final trashed = await create(StudyCreationKind.infographic);
      await h.creations.trash(trashed.id);
      await create(StudyCreationKind.summary); // lista enseguida

      final pending = (await h.creations.pending()).getRight().toNullable()!;
      expect(idsOf(pending), [now1.id, now2.id, later1.id, later2.id]);
    });
  });

  group('lo que quedó a medias al cerrar la app', () {
    test('vuelve a la cola, o falla si ya se empezó tres veces', () async {
      final once = await create(StudyCreationKind.report);
      final thrice = await create(StudyCreationKind.quiz);
      final inFlight = await create(StudyCreationKind.mindMap);
      await h.creations.markGenerating(once.id, modelName: null);
      for (var i = 0; i < 3; i++) {
        await h.creations.markGenerating(thrice.id, modelName: null);
      }
      await h.creations.markGenerating(inFlight.id, modelName: null);

      final requeued = await h.creations.recoverInterrupted(
        maxAttempts: 3,
        inFlight: {inFlight.id},
      );

      expect(requeued.getRight().toNullable(), 1);
      Future<StudyCreation> read(String id) async =>
          (await h.creations.find(id)).getRight().toNullable()!;
      expect((await read(once.id)).status, CreationStatus.queued);
      expect((await read(once.id)).attempts, 1, reason: 'cuenta el intento');
      expect((await read(thrice.id)).status, CreationStatus.failed);
      expect((await read(thrice.id)).failure, CreationFailure.interrupted);
      expect((await read(inFlight.id)).status, CreationStatus.generating);
    });
  });

  group('las listas por recorte', () {
    test('todo lo procesado: todas, la más nueva arriba', () async {
      h.processed.vault.at(1);
      final a = await create(StudyCreationKind.quiz);
      h.processed.vault.at(2);
      final b = await create(
        StudyCreationKind.report,
        scope: const CreationScope.notebook('n'),
      );
      h.processed.vault.at(3);
      final c = await create(
        StudyCreationKind.mindMap,
        scope: const CreationScope.document('doc-z'),
        sources: ['doc-z'],
      );

      final all = await h.creations
          .watchByScope(const CreationScope.allProcessed())
          .first;
      expect(idsOf(all), [c.id, b.id, a.id]);
    });

    test('un documento: las creadas sobre él y las que lo leyeron', () async {
      final onIt = await create(
        StudyCreationKind.mindMap,
        scope: const CreationScope.document('doc-a'),
        sources: ['doc-a'],
      );
      final readIt = await create(
        StudyCreationKind.report,
        scope: const CreationScope.notebook('n'),
        sources: ['doc-b', 'doc-a'],
      );
      await create(
        StudyCreationKind.quiz,
        scope: const CreationScope.notebook('n'),
        sources: ['doc-b'],
      );

      final list = await h.creations
          .watchByScope(const CreationScope.document('doc-a'))
          .first;
      expect(idsOf(list).toSet(), {onIt.id, readIt.id});
    });

    test('un documento entre miles: solo las suyas —sobre él o como fuente '
        'desde un cuaderno o un tema—, y el tiempo crece con la base, no más '
        '(F43, M6: «En Repasar» de cada documento)', () async {
      final at = h.processed.vault.now;
      final db = h.processed.db;

      /// [count] creaciones más en cuadernos y temas, cada una con tres
      /// fuentes que nunca son `doc-a`; empieza a numerar en [from].
      Future<void> fill(int from, int count) => db.batch((batch) {
        batch.insertAll(db.studyCreations, [
          for (var i = from; i < from + count; i++)
            StudyCreationsCompanion.insert(
              id: 'relleno-$i',
              kind: StudyCreationKind.quiz.storageKey,
              scopeKind: i.isEven ? 'notebook' : 'topic',
              scopeId: Value('recorte-${i % 37}'),
              // `doc-a1` y `doc-a10` empiezan como `doc-a`: la regla compara
              // ids enteros, no un pedazo del texto.
              sourceIdsJson: Value(
                '["doc-${i % 97}","doc-a${i % 11}","doc-b${i % 13}"]',
              ),
              languageCode: 'es',
              status: 'ready',
              createdAt: at.subtract(Duration(minutes: i)),
              updatedAt: at,
            ),
        ]);
      });

      final onIt = await create(
        StudyCreationKind.mindMap,
        scope: const CreationScope.document('doc-a'),
        sources: ['doc-a'],
      );
      final viaNotebook = await create(
        StudyCreationKind.report,
        scope: const CreationScope.notebook('recorte-3'),
        sources: ['doc-b', 'doc-a'],
      );
      final viaTopic = await create(
        StudyCreationKind.infographic,
        scope: const CreationScope.topic('roma'),
        sources: ['doc-a'],
      );
      final trashed = await create(
        StudyCreationKind.quiz,
        scope: const CreationScope.notebook('recorte-3'),
        sources: ['doc-a'],
      );
      await h.creations.trash(trashed.id);
      final expected = {onIt.id, viaNotebook.id, viaTopic.id};

      const document = CreationScope.document('doc-a');
      Future<void> onlyItsOwn() async => expect(
        idsOf(await h.creations.watchByScope(document).first).toSet(),
        expected,
      );

      await fill(0, 1000);
      await onlyItsOwn();
      await fill(1000, 3000);
      await onlyItsOwn();

      // Que crezca con la base y no más lo dice el plan de SQLite, no un
      // reloj: medir milisegundos depende de cuán cargada esté la máquina.
      // Una sola pasada por la tabla, y por cada fila nada más que sus
      // fuentes (`json_each`, una tabla virtual de tres valores). Una segunda
      // lectura de `study_creations` por fila sería crecer al cuadrado.
      final filter = creationsInScopeSql(document);
      final plan = [
        for (final row
            in await db
                .customSelect(
                  'EXPLAIN QUERY PLAN SELECT * FROM study_creations c '
                  'WHERE ${filter.sql} ORDER BY c.created_at DESC, c.id DESC',
                  variables: filter.variables,
                )
                .get())
          row.read<String>('detail'),
      ];
      final reads = [
        for (final step in plan)
          if (step.startsWith('SCAN ') || step.startsWith('SEARCH ')) step,
      ];
      expect(
        reads.where((step) => !step.contains('VIRTUAL TABLE')),
        hasLength(1),
        reason: plan.join('\n'),
      );
      expect(
        reads.singleWhere((step) => !step.contains('VIRTUAL TABLE')),
        startsWith('SCAN c'),
        reason: plan.join('\n'),
      );

      // Y a 4.000 creaciones sigue siendo de una pantalla que se abre: una
      // cota generosa, que solo salta si algo se rompe de verdad.
      final watch = Stopwatch()..start();
      await onlyItsOwn();
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test(
      'un cuaderno, un tema o un espacio: las creadas sobre ese recorte',
      () async {
        final inNotebook = await create(
          StudyCreationKind.report,
          scope: const CreationScope.notebook('n'),
          sources: ['doc-a'],
        );
        final inTopic = await create(
          StudyCreationKind.quiz,
          scope: const CreationScope.topic('roma'),
        );
        final inSpace = await create(
          StudyCreationKind.quiz,
          scope: const CreationScope.space('roma'),
        );

        Future<List<String>> of(CreationScope scope) async =>
            idsOf(await h.creations.watchByScope(scope).first);
        expect(await of(const CreationScope.notebook('n')), [inNotebook.id]);
        expect(await of(const CreationScope.topic('roma')), [inTopic.id]);
        expect(await of(const CreationScope.space('roma')), [inSpace.id]);
        expect(await of(const CreationScope.notebook('otro')), isEmpty);
      },
    );

    test(
      'se actualizan solas: aparece, cambia y se va a la papelera',
      () async {
        final queue = StreamQueue(
          h.creations.watchByScope(const CreationScope.allProcessed()),
        );
        addTearDown(queue.cancel);
        expect(await queue.next, isEmpty);

        final created = await create(StudyCreationKind.mindMap);
        expect(idsOf(await queue.next), [created.id]);

        await h.creations.rename(created.id, 'Mapa del Éxodo');
        expect((await queue.next).single.title, 'Mapa del Éxodo');

        await h.creations.trash(created.id);
        expect(await queue.next, isEmpty);
      },
    );

    test(
      'un tipo que esta versión no conoce se conserva y no se muestra',
      () async {
        final at = h.processed.vault.now;
        await h.processed.db
            .into(h.processed.db.studyCreations)
            .insert(
              StudyCreationsCompanion.insert(
                id: 'del-futuro',
                kind: 'hologram',
                scopeKind: 'all',
                languageCode: 'es',
                status: 'ready',
                createdAt: at,
                updatedAt: at,
              ),
            );

        expect(
          await h.creations
              .watchByScope(const CreationScope.allProcessed())
              .first,
          isEmpty,
        );
        expect(
          await h.processed.db.select(h.processed.db.studyCreations).get(),
          hasLength(1),
        );
      },
    );
  });

  group('la papelera', () {
    test('borrar la manda a la papelera; restaurarla la devuelve', () async {
      final created = await create(StudyCreationKind.report);
      await h.creations.complete(created.id, title: 'Informe', content: '{}');
      h.processed.vault.at(7);
      await h.creations.trash(created.id);

      final trash = await h.creations.watchTrash().first;
      expect(idsOf(trash), [created.id]);
      expect(trash.single.deletedAt, h.processed.vault.now);

      await h.creations.restore(created.id);
      expect(await h.creations.watchTrash().first, isEmpty);
      final back = (await h.creations.find(
        created.id,
      )).getRight().toNullable()!;
      expect(back.status, CreationStatus.ready);
      expect(back.isTrashed, isFalse);
    });

    test('una que se borró a medias vuelve fallida por interrumpida', () async {
      final created = await create(StudyCreationKind.report);
      await h.creations.markGenerating(created.id, modelName: null);
      await h.creations.trash(created.id);
      await h.creations.restore(created.id);

      final back = (await h.creations.find(
        created.id,
      )).getRight().toNullable()!;
      expect(back.status, CreationStatus.failed);
      expect(back.failure, CreationFailure.interrupted);
    });

    test('borrar para siempre solo borra lo que está en la papelera', () async {
      final kept = await create(StudyCreationKind.quiz);
      final trashed = await create(StudyCreationKind.report);
      await h.creations.trash(trashed.id);

      await h.creations.purge([kept.id, trashed.id]);

      expect(
        (await h.creations.find(kept.id)).getRight().toNullable(),
        isNotNull,
      );
      expect(
        (await h.creations.find(trashed.id)).getRight().toNullable(),
        isNull,
      );

      final another = await create(StudyCreationKind.mindMap);
      await h.creations.trash(another.id);
      await h.creations.emptyTrash();
      expect(await h.creations.watchTrash().first, isEmpty);
      expect(
        (await h.creations.find(kept.id)).getRight().toNullable(),
        isNotNull,
      );
    });

    test('renombrar en blanco no vale', () async {
      final created = await create(StudyCreationKind.quiz);
      expect((await h.creations.rename(created.id, '   ')).isLeft(), isTrue);
    });
  });

  group('borrar para siempre se lleva sus archivos', () {
    late InMemoryFileStore files;
    late _Telemetry telemetry;
    late StudyCreationRepositoryImpl withFiles;

    setUp(() {
      files = InMemoryFileStore();
      telemetry = _Telemetry();
      withFiles = StudyCreationRepositoryImpl(
        database: h.processed.db,
        telemetry: telemetry,
        clock: () => h.processed.vault.now,
        files: files,
      );
    });

    Future<String> withFile(String name) async {
      final created = await create(StudyCreationKind.infographic);
      await files.saveStream(
        bytes: Stream.value([1, 2, 3]),
        suggestedName: name,
        id: created.id,
        folder: 'ilustraciones',
      );
      return created.id;
    }

    test('la carpeta de cada una que se borra, y nada de las demás', () async {
      final gone = await withFile('header.png');
      final alive = await withFile('header.png');
      final onlyTrashed = await withFile('header.png');
      await withFiles.trash(gone);
      await withFiles.trash(onlyTrashed);

      // Una viva no se borra aunque se la nombre.
      await withFiles.purge([gone, alive]);

      expect(files.deletedFolders, [gone]);
      expect(files.paths.where((p) => p.contains(gone)), isEmpty);
      expect(files.paths.where((p) => p.contains(alive)), isNotEmpty);
      expect(files.paths.where((p) => p.contains(onlyTrashed)), isNotEmpty);

      await withFiles.emptyTrash();
      expect(files.deletedFolders, [gone, onlyTrashed]);
      expect(files.paths.where((p) => p.contains(onlyTrashed)), isEmpty);
      expect((await withFiles.find(alive)).getRight().toNullable(), isNotNull);
    });

    test(
      'un archivo que se resiste no deshace el borrado, y se anota',
      () async {
        final gone = await withFile('header.png');
        await withFiles.trash(gone);
        files.deleteError = const FileSystemFailure();

        expect((await withFiles.purge([gone])).isRight(), isTrue);
        expect((await withFiles.find(gone)).getRight().toNullable(), isNull);
        verify(
          () => telemetry.recordError(
            any<dynamic>(),
            any(),
            hint: any(named: 'hint'),
          ),
        ).called(1);
      },
    );
  });

  group('guardar un contenido barre las ilustraciones que ya no nombra', () {
    late InMemoryFileStore files;
    late CreationIllustrationStore store;
    late StudyCreationRepositoryImpl withFiles;

    setUp(() {
      files = InMemoryFileStore();
      store = CreationIllustrationStore(files);
      withFiles = StudyCreationRepositoryImpl(
        database: h.processed.db,
        telemetry: _Telemetry(),
        clock: () => h.processed.vault.now,
        files: files,
      );
    });

    Future<String> draw(String creationId, String slotId) => store.save(
      creationId: creationId,
      slotId: slotId,
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
    );

    /// Un contenido que nombra [paths], cada una a su profundidad.
    String naming(List<String> paths) => jsonEncode({
      'sheet': {
        'blocks': [
          for (final path in paths) {'illustration_ref': path},
        ],
      },
    });

    test(
      'al generarla, al volver a generarla y al retocarla: lo suyo que no '
      'se nombra se va; lo nombrado, lo de otras y lo ajeno quedan',
      () async {
        final c = await create(StudyCreationKind.infographic);
        final other = await create(StudyCreationKind.quiz);
        final a = await draw(c.id, 'a');
        final b = await draw(c.id, 'b');
        // De una sesión anterior, que ningún contenido nombra.
        final stale = await files.saveStream(
          bytes: Stream.value([9]),
          suggestedName: 'viejo.png',
          id: c.id,
          folder: 'ilustraciones',
        );
        final theirs = await draw(other.id, 'a');
        final original = await files.save(
          bytes: Uint8List.fromList([4]),
          suggestedName: 'libro.pdf',
          id: 'documento',
        );

        await withFiles.complete(
          c.id,
          title: 'Lámina',
          content: naming([a, b, theirs, original]),
        );
        expect(files.deleted, [stale]);

        // Rehacer «a» deja la nueva al lado; guardado el contenido, la vieja
        // se va.
        final a2 = await draw(c.id, 'a');
        await withFiles.amend(c.id, content: naming([a2, b]));
        expect(files.deleted, [stale, a]);

        // Volver a generar sin ilustraciones.
        await withFiles.complete(c.id, title: 'Lámina', content: naming([]));
        expect(files.deleted, [stale, a, a2, b]);
        expect(files.paths, unorderedEquals([theirs, original]));
      },
    );

    test('nada antes de guardar: un retoque que no se guarda, uno sin '
        'contenido o una que falla dejan todo como estaba', () async {
      final c = await create(StudyCreationKind.presentation);
      final a = await draw(c.id, 'a');
      await withFiles.complete(c.id, title: 'P', content: naming([a]));
      final b = await draw(c.id, 'b');

      await withFiles.amend(c.id, options: const {'diseño': 'aurora'});
      await withFiles.fail(c.id, CreationFailure.cancelled);
      // Fallida no se retoca: el contenido nuevo no se guarda.
      expect(
        (await withFiles.amend(c.id, content: naming([b]))).isLeft(),
        isTrue,
      );
      expect(files.deleted, isEmpty);
      expect(files.paths, unorderedEquals([a, b]));
    });

    test('lo que un ilustrador está guardando para ella mientras se guarda '
        'otro contenido no se borra', () async {
      final c = await create(StudyCreationKind.flashcards);
      final a = await draw(c.id, 'a');
      await withFiles.complete(c.id, title: 'Mazo', content: naming([a]));

      final gate = Completer<void>();
      files.saveGate = gate.future;
      final drawing = draw(c.id, 'b');
      await pumpEventQueue();
      final saving = withFiles.complete(
        c.id,
        title: 'Mazo',
        content: naming([]),
      );
      await pumpEventQueue();
      expect(files.deleted, isEmpty);

      files.saveGate = null;
      gate.complete();
      final b = await drawing;
      await saving;
      expect(files.deleted, [a]);
      expect(files.paths, [b]);
    });
  });

  group('retocar una lista sin volver a generarla (decisión G)', () {
    test('cambia sus opciones o su contenido, deja lo demás y avanza la '
        'fecha', () async {
      h.processed.vault.at(1);
      final created = await create(StudyCreationKind.infographic);
      await h.creations.complete(created.id, title: 'Lámina', content: '{}');
      h.processed.vault.at(7);

      final styled = await h.creations.amend(
        created.id,
        options: const {'style': 'clay'},
      );
      expect(styled.isRight(), isTrue);
      var now = (await h.creations.find(created.id)).getRight().toNullable()!;
      expect(now.options, {'style': 'clay'});
      expect(now.content, '{}');
      expect(now.title, 'Lámina');
      expect(now.status, CreationStatus.ready);
      expect(now.updatedAt, h.processed.vault.now);

      await h.creations.amend(created.id, content: '{"sheet":{}}');
      now = (await h.creations.find(created.id)).getRight().toNullable()!;
      expect(now.content, '{"sheet":{}}');
      expect(now.options, {'style': 'clay'});
    });

    test('una en la cola, fallida o en la papelera no se retoca', () async {
      final queued = await create(StudyCreationKind.infographic);
      expect(
        (await h.creations.amend(queued.id, content: 'x')).isLeft(),
        isTrue,
      );
      final failed = await create(StudyCreationKind.infographic);
      await h.creations.fail(failed.id, CreationFailure.error);
      expect(
        (await h.creations.amend(failed.id, content: 'x')).isLeft(),
        isTrue,
      );
      final trashed = await create(StudyCreationKind.infographic);
      await h.creations.complete(trashed.id, title: 'T', content: '{}');
      await h.creations.trash(trashed.id);
      expect(
        (await h.creations.amend(trashed.id, content: 'x')).isLeft(),
        isTrue,
      );
      expect(
        (await h.creations.find(trashed.id)).getRight().toNullable()!.content,
        '{}',
      );
      expect(
        (await h.creations.amend('no-existe', content: 'x')).isLeft(),
        isTrue,
      );
    });
  });

  test(
    'las columnas por defecto de la base, sin pasar por el repositorio',
    () async {
      // El camino de la unión de bóvedas: una fila que llega como texto.
      final at = h.processed.vault.now;
      await h.processed.db
          .into(h.processed.db.studyCreations)
          .insert(
            StudyCreationsCompanion.insert(
              id: 'cruda',
              kind: 'quiz',
              scopeKind: 'document',
              scopeId: const Value('doc-a'),
              sourceIdsJson: const Value('no es json'),
              languageCode: 'es',
              status: 'ready',
              createdAt: at,
              updatedAt: at,
            ),
          );
      final read = (await h.creations.find('cruda')).getRight().toNullable()!;
      expect(read.sourceIds, isEmpty, reason: 'un JSON roto no rompe nada');
      expect(read.scope, const CreationScope.document('doc-a'));
    },
  );
}

/// Lo que lanza el disco de mentira al borrar.
class FileSystemFailure implements Exception {
  const FileSystemFailure();
}
