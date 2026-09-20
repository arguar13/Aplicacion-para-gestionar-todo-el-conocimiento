import 'dart:math';

import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/neighborhood.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria. Un doble de la base respondería lo que se
/// le pida y no ejercitaría las restricciones del esquema —la unicidad de una
/// etiqueta, el `CHECK` contra vincular algo consigo mismo— que es justo lo
/// que hay que verificar acá.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late OrganizeRepositoryImpl repository;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 11, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    repository = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  /// Guarda un elemento por el mismo camino que la app: si el test insertara
  /// filas a mano, la fuente y el elemento podrían quedar en combinaciones
  /// que la app nunca produce.
  Future<KnowledgeItem> seedItem({String title = 'Un elemento'}) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );

    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  Future<String> seedRendition(
    String itemId, {
    String content = 'texto',
  }) async {
    final renditionId = 'rend-${counter++}';
    final item = (await libraryRepository.findById(
      itemId,
    )).getRight().toNullable()!;

    await libraryRepository.save(
      item.copyWith(
        renditions: [
          Rendition.text(
            id: renditionId,
            itemId: itemId,
            kind: RenditionKind.plainText,
            content: content,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );

    return renditionId;
  }

  group('etiquetas', () {
    Future<Tag> seedTag(String name) async {
      final item = await seedItem();
      final tag = Tag(id: 'tag-${counter++}', name: name, createdAt: now);

      await libraryRepository.save(item.copyWith(tags: [tag]));
      return tag;
    }

    group('listar todas', () {
      test('las devuelve en orden alfabético', () async {
        await seedTag('Zoología');
        await seedTag('Arte');
        await seedTag('Filosofía');

        final queue = StreamQueue(repository.watchAllTags());
        addTearDown(queue.cancel);

        final tags = await queue.next;
        expect(tags.map((t) => t.name), ['Arte', 'Filosofía', 'Zoología']);
      });

      test('se actualiza sola cuando se agrega una etiqueta nueva', () async {
        final queue = StreamQueue(repository.watchAllTags());
        addTearDown(queue.cancel);

        expect(await queue.next, isEmpty);

        await seedTag('Historia');

        expect((await queue.next).map((t) => t.name), ['Historia']);
      });
    });

    group('obtener o crear', () {
      test('si no existe, la crea', () async {
        final result = await repository.getOrCreateTag('Nueva');

        expect(result.getRight().toNullable()?.name, 'Nueva');
        expect((await repository.watchAllTags().first).map((t) => t.name), [
          'Nueva',
        ]);
      });

      test('si ya existe, devuelve la misma sin crear una segunda', () async {
        final original = await seedTag('Filosofía');

        final result = await repository.getOrCreateTag('Filosofía');

        expect(result.getRight().toNullable()?.id, original.id);
        expect(await repository.watchAllTags().first, hasLength(1));
      });

      test('encuentra la existente sin distinguir mayúsculas', () async {
        // Quien escribe "filosofía" en un elemento que ya tiene la etiqueta
        // "Filosofía" tiene que terminar en la misma etiqueta, no en dos que
        // compiten por agrupar lo mismo.
        final original = await seedTag('Filosofía');

        final result = await repository.getOrCreateTag('filosofía');

        expect(result.getRight().toNullable()?.id, original.id);
        expect(await repository.watchAllTags().first, hasLength(1));
      });

      test('un nombre en blanco se rechaza', () async {
        final result = await repository.getOrCreateTag('   ');

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('recorta los espacios de los bordes', () async {
        final result = await repository.getOrCreateTag('  Historia  ');

        expect(result.getRight().toNullable()?.name, 'Historia');
      });
    });

    group('renombrar', () {
      test('el nuevo nombre queda guardado', () async {
        final tag = await seedTag('Filosofia');

        final result = await repository.renameTag(
          id: tag.id,
          name: 'Filosofía',
        );

        expect(result.getRight().toNullable()?.name, 'Filosofía');
      });

      test('un nombre en blanco se rechaza', () async {
        final tag = await seedTag('Arte');

        final result = await repository.renameTag(id: tag.id, name: '   ');

        // No solo que falle: que falle con un mensaje pensado para
        // mostrarse, y no con lo que sea que diga una restricción de la
        // base si el nombre en blanco llegara a intentarse guardar.
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('no se puede renombrar para chocar con otra etiqueta', () async {
        await seedTag('Arte');
        final segunda = await seedTag('Historia');

        final result = await repository.renameTag(id: segunda.id, name: 'arte');

        // Sin distinguir mayúsculas, igual que la restricción de la base:
        // "Arte" y "arte" tienen que seguir siendo la misma etiqueta.
        //
        // Se comprueba el TIPO del fallo y no solo que sea `Left`: sin la
        // comprobación previa en el repositorio, esta misma aserción
        // seguiría pasando igual —la base también rechaza el choque— pero
        // con la excepción cruda de una restricción SQL en vez del mensaje
        // que se pensó para mostrarse. `isLeft()` no distingue las dos
        // cosas; el tipo del fallo, sí.
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('renombrarla a su propio nombre no choca consigo misma', () async {
        final tag = await seedTag('Arte');

        final result = await repository.renameTag(id: tag.id, name: 'Arte');

        expect(result.isRight(), isTrue);
      });

      test('una que ya no existe devuelve un fallo, no revienta', () async {
        final result = await repository.renameTag(
          id: 'no-existe',
          name: 'Lo que sea',
        );

        expect(result.isLeft(), isTrue);
      });

      test(
        'renombrarla al nombre de otra en un solo paso no dice "no existe"',
        () async {
          // Sin la comprobación previa, esto fallaría igual —por la
          // restricción de unicidad, no porque la etiqueta faltara— pero con
          // el mensaje equivocado.
          await seedTag('Arte');
          final segunda = await seedTag('Historia');

          final result = await repository.renameTag(
            id: segunda.id,
            name: 'Arte',
          );

          expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        },
      );
    });

    group('borrar', () {
      test('el elemento que la tenía simplemente deja de tenerla', () async {
        final tag = await seedTag('Efímera');
        final item = await seedItem();
        await libraryRepository.save(item.copyWith(tags: [tag]));

        await repository.deleteTag(tag.id);

        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.tags, isEmpty);
      });

      test('borrar una que no existe no falla', () async {
        final result = await repository.deleteTag('no-existe');

        expect(result.isRight(), isTrue);
      });
    });
  });

  group('espacios', () {
    group('listar todos', () {
      test('ordenados alfabéticamente, actualizándose solo', () async {
        final stream = repository.watchAllSpaces();
        final queue = StreamQueue(stream);

        expect(await queue.next, isEmpty);

        await repository.createSpace('Trabajo');
        expect((await queue.next).map((s) => s.name), ['Trabajo']);

        await repository.createSpace('Casa');
        expect((await queue.next).map((s) => s.name), ['Casa', 'Trabajo']);

        await queue.cancel();
      });
    });

    group('crear', () {
      test('un nombre nuevo se crea', () async {
        final result = await repository.createSpace('Proyectos');

        final space = result.getRight().toNullable()!;
        expect(space.name, 'Proyectos');
      });

      test('un nombre repetido, sin distinguir mayúsculas, falla', () async {
        await repository.createSpace('Proyectos');

        final result = await repository.createSpace('proyectos');

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('un nombre vacío falla', () async {
        final result = await repository.createSpace('   ');

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });
    });

    group('renombrar', () {
      test('cambia el nombre', () async {
        final created = (await repository.createSpace(
          'Viejo',
        )).getRight().toNullable()!;

        final result = await repository.renameSpace(
          id: created.id,
          name: 'Nuevo',
        );

        expect(result.getRight().toNullable()!.name, 'Nuevo');
      });

      test('a un nombre que ya usa otro espacio falla', () async {
        await repository.createSpace('Uno');
        final dos = (await repository.createSpace(
          'Dos',
        )).getRight().toNullable()!;

        final result = await repository.renameSpace(id: dos.id, name: 'uno');

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('a su propio nombre no falla por choque consigo mismo', () async {
        final space = (await repository.createSpace(
          'Mismo',
        )).getRight().toNullable()!;

        final result = await repository.renameSpace(
          id: space.id,
          name: 'Mismo',
        );

        expect(result.isRight(), isTrue);
      });
    });

    group('borrar', () {
      test(
        'el elemento que pertenecía queda sin clasificar, no se borra',
        () async {
          final space = (await repository.createSpace(
            'Efímero',
          )).getRight().toNullable()!;
          final item = await seedItem();
          await libraryRepository.assignSpace(
            itemId: item.id,
            spaceId: space.id,
          );

          await repository.deleteSpace(space.id);

          final reloaded = (await libraryRepository.findById(
            item.id,
          )).getRight().toNullable()!;
          expect(reloaded.spaceId, isNull);
        },
      );

      test('borrar uno que no existe no falla', () async {
        final result = await repository.deleteSpace('no-existe');

        expect(result.isRight(), isTrue);
      });
    });
  });

  group('relaciones', () {
    test('vincula dos elementos y se puede ver desde los dos lados', () async {
      final a = await seedItem(title: 'El artículo original');
      final b = await seedItem(title: 'La respuesta');

      final created = await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.contradicts,
        note: 'polemizan sobre el mismo punto',
      );
      expect(created.isRight(), isTrue);

      final fromA = await repository.watchRelationsForItem(a.id).first;
      expect(fromA, hasLength(1));
      expect(fromA.single.direction, RelationDirection.outgoing);
      expect(fromA.single.otherItemId, b.id);
      expect(fromA.single.otherItemTitle, 'La respuesta');
      expect(fromA.single.kind, RelationKind.contradicts);
      expect(fromA.single.note, 'polemizan sobre el mismo punto');

      final fromB = await repository.watchRelationsForItem(b.id).first;
      expect(fromB, hasLength(1));
      expect(fromB.single.direction, RelationDirection.incoming);
      expect(fromB.single.otherItemId, a.id);
      expect(fromB.single.otherItemTitle, 'El artículo original');
    });

    group('de dónde salió una extracción', () {
      Future<(KnowledgeItem, KnowledgeItem)> pair() async => (
        await seedItem(title: 'La nota'),
        await seedItem(title: 'La fuente'),
      );

      test('una extracción guarda el rango de la fuente y lo devuelve por los '
          'dos lados', () async {
        final (note, source) = await pair();

        final created = await repository.createRelation(
          fromItemId: note.id,
          toItemId: source.id,
          kind: RelationKind.extractedFrom,
          sourceCharStart: 120,
          sourceCharEnd: 180,
        );

        expect(created.isRight(), isTrue);
        for (final id in [note.id, source.id]) {
          final relation =
              (await repository.watchRelationsForItem(id).first).single;
          expect(relation.sourceCharStart, 120, reason: id);
          expect(relation.sourceCharEnd, 180, reason: id);
        }
      });

      test(
        'una extracción sin rango sigue siendo válida y queda sin rango',
        () async {
          final (note, source) = await pair();

          await repository.createRelation(
            fromItemId: note.id,
            toItemId: source.id,
            kind: RelationKind.extractedFrom,
          );

          final relation =
              (await repository.watchRelationsForItem(note.id).first).single;
          expect(relation.sourceCharStart, isNull);
          expect(relation.sourceCharEnd, isNull);
        },
      );

      test('el rango queda en la fila de la relación', () async {
        final (note, source) = await pair();

        await repository.createRelation(
          fromItemId: note.id,
          toItemId: source.id,
          kind: RelationKind.extractedFrom,
          sourceCharStart: 5,
          sourceCharEnd: 9,
        );

        final row = await db.select(db.relations).getSingle();
        expect(row.sourceCharStart, 5);
        expect(row.sourceCharEnd, 9);
      });

      test('el inicio sin el fin, o al revés, se rechaza', () async {
        final (note, source) = await pair();

        final onlyStart = await repository.createRelation(
          fromItemId: note.id,
          toItemId: source.id,
          kind: RelationKind.extractedFrom,
          sourceCharStart: 5,
        );
        final onlyEnd = await repository.createRelation(
          fromItemId: note.id,
          toItemId: source.id,
          kind: RelationKind.extractedFrom,
          sourceCharEnd: 9,
        );

        expect(onlyStart.getLeft().toNullable(), isA<ValidationFailure>());
        expect(onlyEnd.getLeft().toNullable(), isA<ValidationFailure>());
        expect(await db.select(db.relations).get(), isEmpty);
      });

      test('un rango vacío, invertido o negativo se rechaza', () async {
        final (note, source) = await pair();

        for (final (start, end) in [(5, 5), (9, 5), (-1, 4)]) {
          final result = await repository.createRelation(
            fromItemId: note.id,
            toItemId: source.id,
            kind: RelationKind.extractedFrom,
            sourceCharStart: start,
            sourceCharEnd: end,
          );

          expect(
            result.getLeft().toNullable(),
            isA<ValidationFailure>(),
            reason: '($start, $end)',
          );
        }
        expect(await db.select(db.relations).get(), isEmpty);
      });

      test('el rango solo va en una extracción', () async {
        final (a, b) = await pair();

        final result = await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.cites,
          sourceCharStart: 1,
          sourceCharEnd: 2,
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('los vínculos que no son extracciones no tienen rango', () async {
        final (a, b) = await pair();

        await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.relatedTo,
        );

        final relation =
            (await repository.watchRelationsForItem(a.id).first).single;
        expect(relation.sourceCharStart, isNull);
        expect(relation.sourceCharEnd, isNull);
      });
    });

    test('un elemento no puede vincularse consigo mismo', () async {
      final a = await seedItem();

      final result = await repository.createRelation(
        fromItemId: a.id,
        toItemId: a.id,
        kind: RelationKind.relatedTo,
      );

      // El esquema también tiene un CHECK contra esto — se comprueba el
      // tipo del fallo para asegurarse de que lo que contesta es el mensaje
      // pensado para mostrarse, y no la excepción cruda de esa restricción.
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('el mismo vínculo dos veces se rechaza', () async {
      final a = await seedItem();
      final b = await seedItem();

      await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.relatedTo,
      );
      final second = await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.relatedTo,
      );

      // Igual que con el autovínculo: el esquema también tiene una
      // restricción `UNIQUE` para este caso, así que sin la comprobación
      // previa esto fallaría igual pero con el mensaje equivocado.
      expect(second.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('el mismo par con otro tipo de vínculo SÍ se permite', () async {
      // "A cita a B" y "A contradice a B" no son el mismo hecho.
      final a = await seedItem();
      final b = await seedItem();

      await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.cites,
      );
      final second = await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.contradicts,
      );

      expect(second.isRight(), isTrue);
      expect(await repository.watchRelationsForItem(a.id).first, hasLength(2));
    });

    test('borrar un vínculo lo saca de los dos lados', () async {
      final a = await seedItem();
      final b = await seedItem();
      await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.relatedTo,
      );
      final relationId = (await repository.watchRelationsForItem(a.id).first)
          .single
          .relationId;

      await repository.deleteRelation(relationId);

      expect(await repository.watchRelationsForItem(a.id).first, isEmpty);
      expect(await repository.watchRelationsForItem(b.id).first, isEmpty);
    });

    test('borrar un elemento borra también sus vínculos', () async {
      // Las cascadas del esquema, no algo que este repositorio tenga que
      // hacer a mano.
      final a = await seedItem();
      final b = await seedItem();
      await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.relatedTo,
      );

      await libraryRepository.delete(a.id);

      expect(await repository.watchRelationsForItem(b.id).first, isEmpty);
    });

    test('se actualiza sola cuando se crea un vínculo nuevo', () async {
      final a = await seedItem();
      final b = await seedItem();

      final queue = StreamQueue(repository.watchRelationsForItem(a.id));
      addTearDown(queue.cancel);

      expect(await queue.next, isEmpty);

      await repository.createRelation(
        fromItemId: a.id,
        toItemId: b.id,
        kind: RelationKind.relatedTo,
      );

      expect(await queue.next, hasLength(1));
    });

    group('el otro elemento sale del modelo nuevo (F10)', () {
      test('su título y su tipo de fuente vienen de item y de source, no de '
          'las tablas viejas', () async {
        final a = await seedItem();
        final b = await seedItem(title: 'Título de antes');
        await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.relatedTo,
        );

        // Se cambia SOLO el modelo nuevo: si la lectura saliera del viejo, no
        // se vería.
        await (db.update(db.knowledgeEntries)..where((e) => e.id.equals(b.id)))
            .write(const KnowledgeEntriesCompanion(title: Value('De ahora')));
        await (db.update(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals(b.id))).write(
          const KnowledgeSourcesCompanion(
            sourceType: Value(SourceKind.document),
          ),
        );

        final relation =
            (await repository.watchRelationsForItem(a.id).first).single;
        expect(relation.otherItemTitle, 'De ahora');
        expect(relation.otherItemSourceKind, SourceKind.document);
      });

      test('una nota no tiene fila de fuente y sigue apareciendo vinculada, '
          'como nota', () async {
        final source = await seedItem();
        final note = (await libraryRepository.save(
          KnowledgeItem(
            id: 'una-nota',
            title: 'Mi nota',
            source: Source(
              id: 'src-una-nota',
              kind: SourceKind.manualNote,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        )).getRight().toNullable()!;
        expect(
          await (db.select(
            db.knowledgeSources,
          )..where((s) => s.itemId.equals(note.id))).get(),
          isEmpty,
        );
        await repository.createRelation(
          fromItemId: source.id,
          toItemId: note.id,
          kind: RelationKind.relatedTo,
        );
        await repository.createRelation(
          fromItemId: note.id,
          toItemId: source.id,
          kind: RelationKind.extractedFrom,
        );

        final fromSource =
            (await repository.watchRelationsForItem(source.id).first)
                .firstWhere((r) => r.otherItemId == note.id);
        expect(fromSource.otherItemTitle, 'Mi nota');
        expect(fromSource.otherItemSourceKind, SourceKind.manualNote);

        // Y al revés: la nota es la que mira, y lo que aparece es la fuente.
        final fromNote = (await repository.watchRelationsForItem(note.id).first)
            .firstWhere((r) => r.otherItemId == source.id);
        expect(fromNote.otherItemSourceKind, SourceKind.webPage);
      });

      test(
        'se actualiza sola cuando cambia el título del otro elemento',
        () async {
          final a = await seedItem();
          final b = await seedItem(title: 'Título de antes');
          await repository.createRelation(
            fromItemId: a.id,
            toItemId: b.id,
            kind: RelationKind.relatedTo,
          );
          final queue = StreamQueue(repository.watchRelationsForItem(a.id));
          addTearDown(queue.cancel);
          expect((await queue.next).single.otherItemTitle, 'Título de antes');

          await (db.update(db.knowledgeEntries)
                ..where((e) => e.id.equals(b.id)))
              .write(const KnowledgeEntriesCompanion(title: Value('De ahora')));

          expect((await queue.next).single.otherItemTitle, 'De ahora');
        },
      );
    });

    group('todos los vínculos', () {
      test('trae los de toda la bóveda, no de un elemento', () async {
        final a = await seedItem();
        final b = await seedItem();
        final c = await seedItem();

        await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.relatedTo,
        );
        await repository.createRelation(
          fromItemId: b.id,
          toItemId: c.id,
          kind: RelationKind.continues,
        );

        final edges = await repository.watchAllRelations().first;

        expect(edges, hasLength(2));
        expect(
          edges.map((e) => (e.fromItemId, e.toItemId)),
          containsAll([(a.id, b.id), (b.id, c.id)]),
        );
      });

      test('sin ningún vínculo, una lista vacía', () async {
        await seedItem();

        expect(await repository.watchAllRelations().first, isEmpty);
      });

      test('se actualiza sola cuando se crea o se borra un vínculo', () async {
        final a = await seedItem();
        final b = await seedItem();

        final queue = StreamQueue(repository.watchAllRelations());
        addTearDown(queue.cancel);

        expect(await queue.next, isEmpty);

        await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.relatedTo,
        );
        final created = await queue.next;
        expect(created, hasLength(1));

        await repository.deleteRelation(created.single.id);

        expect(await queue.next, isEmpty);
      });
    });

    group('el vecindario de un elemento', () {
      Future<void> link(
        String from,
        String to, {
        OrganizeRepositoryImpl? through,
      }) async {
        final result = await (through ?? repository).createRelation(
          fromItemId: from,
          toItemId: to,
          kind: RelationKind.relatedTo,
        );
        expect(result.isRight(), isTrue);
      }

      Set<(String, String)> pairsOf(Neighborhood hood) => {
        for (final e in hood.edges) (e.fromItemId, e.toItemId),
      };

      test('sin ningún vínculo no hay vecindario', () async {
        final a = await seedItem();

        final hood = await repository
            .watchNeighborhood(seedItemId: a.id, maxNodes: 30)
            .first;

        expect(hood.nodeIds, isEmpty);
        expect(hood.edges, isEmpty);
        expect(hood.omitted, 0);
      });

      test('a un salto trae los vecinos directos, en los dos sentidos, y los '
          'vínculos entre ellos: nada de más lejos', () async {
        final a = await seedItem();
        final b = await seedItem();
        final c = await seedItem();
        final d = await seedItem();
        final e = await seedItem();
        await link(a.id, b.id);
        await link(c.id, a.id);
        await link(b.id, c.id);
        await link(b.id, d.id);
        await link(d.id, e.id);

        final hood = await repository
            .watchNeighborhood(seedItemId: a.id, maxNodes: 30)
            .first;

        expect(hood.nodeIds, {a.id, b.id, c.id});
        expect(pairsOf(hood), {(a.id, b.id), (c.id, a.id), (b.id, c.id)});
        expect(hood.omitted, 0);
      });

      test('a más saltos llega más lejos, y sin techo hasta el borde de la '
          'red', () async {
        final a = await seedItem();
        final b = await seedItem();
        final c = await seedItem();
        final d = await seedItem();
        final apart = await seedItem();
        final apart2 = await seedItem();
        await link(a.id, b.id);
        await link(b.id, c.id);
        await link(c.id, d.id);
        await link(apart.id, apart2.id);

        Future<Set<String>> reach(int? degree) async {
          final hood = await repository
              .watchNeighborhood(seedItemId: a.id, maxNodes: 30, degree: degree)
              .first;
          return hood.nodeIds;
        }

        expect(await reach(2), {a.id, b.id, c.id});
        expect(await reach(null), {a.id, b.id, c.id, d.id});
      });

      test('con más vecinos que el tope, entran los vinculados más '
          'recientemente y se dice cuántos faltan', () async {
        var clock = now;
        final repo = OrganizeRepositoryImpl(
          database: db,
          telemetry: MockTelemetryService(),
          ids: ids,
          clock: () => clock,
        );
        final hub = await seedItem(title: 'El nodo central');
        final neighbors = <KnowledgeItem>[];
        for (var i = 0; i < 6; i++) {
          neighbors.add(await seedItem(title: 'Vecino $i'));
          clock = now.add(Duration(days: i));
          await link(hub.id, neighbors[i].id, through: repo);
        }

        final hood = await repo
            .watchNeighborhood(seedItemId: hub.id, maxNodes: 4)
            .first;

        // El central más los tres vinculados más tarde.
        expect(hood.nodeIds, {
          hub.id,
          neighbors[5].id,
          neighbors[4].id,
          neighbors[3].id,
        });
        expect(hood.omitted, 3);
        expect(hood.isTruncated, isTrue);
      });

      test('con un tope que no deja lugar para ningún vecino, el elemento de '
          'partida sigue estando y todos los vecinos se cuentan como '
          'omitidos', () async {
        final a = await seedItem();
        final b = await seedItem();
        await link(a.id, b.id);

        final hood = await repository
            .watchNeighborhood(seedItemId: a.id, maxNodes: 1)
            .first;

        expect(hood.nodeIds, {a.id});
        expect(hood.omitted, 1);
      });

      test('coincide con recorrer el grafo entero en memoria, a cualquier '
          'grado', () async {
        // La regla de qué es "el vecindario" vive en `localGraphFrom`; esto
        // asegura que traerlo de la base no la cambia.
        final random = Random(7);
        final items = [for (var i = 0; i < 25; i++) await seedItem()];
        for (var i = 0; i < 45; i++) {
          final from = items[random.nextInt(items.length)];
          final to = items[random.nextInt(items.length)];
          if (from.id == to.id) continue;
          // Un vínculo repetido lo rechaza el esquema: no importa.
          await repository.createRelation(
            fromItemId: from.id,
            toItemId: to.id,
            kind: RelationKind.relatedTo,
          );
        }
        final all = (await libraryRepository.list(
          const LibraryQuery(),
        )).getRight().toNullable()!;
        final edges = await repository.watchAllRelations().first;

        for (final seed in [items[0], items[7], items[19]]) {
          for (final degree in <int?>[0, 1, 2, 3, null]) {
            final expected = localGraphFrom(
              seedItemId: seed.id,
              items: all,
              edges: edges,
              degree: degree,
            );
            final hood = await repository
                .watchNeighborhood(
                  seedItemId: seed.id,
                  maxNodes: 1000,
                  degree: degree,
                )
                .first;

            expect(
              hood.nodeIds,
              expected.nodeIds.toSet(),
              reason: 'nodos, semilla ${seed.id}, grado $degree',
            );
            expect(
              hood.edges.map((e) => e.id).toSet(),
              expected.edges.map((e) => e.id).toSet(),
              reason: 'vínculos, semilla ${seed.id}, grado $degree',
            );
          }
        }
      });

      test('se actualiza solo cuando aparece un vínculo nuevo', () async {
        final a = await seedItem();
        final b = await seedItem();

        final queue = StreamQueue(
          repository.watchNeighborhood(seedItemId: a.id, maxNodes: 30),
        );
        addTearDown(queue.cancel);

        expect((await queue.next).nodeIds, isEmpty);

        await link(a.id, b.id);

        expect((await queue.next).nodeIds, {a.id, b.id});
      });
    });

    group('marcar un vínculo como revisado (F9)', () {
      Future<String> seedContradiction() async {
        final a = await seedItem();
        final b = await seedItem();
        await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.contradicts,
        );
        return (await repository.watchAllRelations().first).single.id;
      }

      test('un vínculo nuevo nace sin revisar', () async {
        await seedContradiction();

        final edge = (await repository.watchAllRelations().first).single;

        expect(edge.reviewedAt, isNull);
      });

      test(
        'marcarlo guarda la fecha de ahora y no cambia el vínculo',
        () async {
          final id = await seedContradiction();
          final before = (await repository.watchAllRelations().first).single;

          final result = await repository.setRelationReviewed(
            relationId: id,
            reviewed: true,
          );

          expect(result.isRight(), isTrue);
          final after = (await repository.watchAllRelations().first).single;
          expect(after.reviewedAt, now);
          // Sigue siendo el mismo vínculo.
          expect(
            (after.id, after.fromItemId, after.toItemId, after.kind),
            (before.id, before.fromItemId, before.toItemId, before.kind),
          );
        },
      );

      test('se le puede quitar la marca', () async {
        final id = await seedContradiction();
        await repository.setRelationReviewed(relationId: id, reviewed: true);

        final result = await repository.setRelationReviewed(
          relationId: id,
          reviewed: false,
        );

        expect(result.isRight(), isTrue);
        expect(
          (await repository.watchAllRelations().first).single.reviewedAt,
          isNull,
        );
      });

      test('marcar dos veces es lo mismo que una', () async {
        final id = await seedContradiction();

        await repository.setRelationReviewed(relationId: id, reviewed: true);
        final again = await repository.setRelationReviewed(
          relationId: id,
          reviewed: true,
        );

        expect(again.isRight(), isTrue);
        expect(
          (await repository.watchAllRelations().first).single.reviewedAt,
          now,
        );
      });

      test('solo toca el vínculo pedido', () async {
        final a = await seedItem();
        final b = await seedItem();
        final c = await seedItem();
        await repository.createRelation(
          fromItemId: a.id,
          toItemId: b.id,
          kind: RelationKind.contradicts,
        );
        await repository.createRelation(
          fromItemId: a.id,
          toItemId: c.id,
          kind: RelationKind.contradicts,
        );
        final edges = await repository.watchAllRelations().first;

        await repository.setRelationReviewed(
          relationId: edges.first.id,
          reviewed: true,
        );

        final after = {
          for (final e in await repository.watchAllRelations().first)
            e.id: e.reviewedAt,
        };
        expect(after[edges.first.id], now);
        expect(after[edges.last.id], isNull);
      });

      test('un vínculo que no existe devuelve un fallo', () async {
        final result = await repository.setRelationReviewed(
          relationId: 'no-existe',
          reviewed: true,
        );

        expect(result.getLeft().toNullable(), isA<UnexpectedFailure>());
      });

      test('la lista se actualiza sola al marcar', () async {
        final id = await seedContradiction();
        final queue = StreamQueue(repository.watchAllRelations());
        addTearDown(queue.cancel);
        expect((await queue.next).single.reviewedAt, isNull);

        await repository.setRelationReviewed(relationId: id, reviewed: true);

        expect((await queue.next).single.reviewedAt, now);
      });
    });

    group('extractedFrom marca la nota de origen', () {
      Future<KnowledgeItem> seedNote({String title = 'Una nota'}) async {
        final n = counter++;
        final item = KnowledgeItem(
          id: 'item-$n',
          title: title,
          source: Source(
            id: 'src-$n',
            kind: SourceKind.manualNote,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        );
        final result = await libraryRepository.save(item);
        return result.getRight().toNullable()!;
      }

      test('un vínculo extractedFrom deja la nota como atomic', () async {
        final nota = await seedNote();
        final fuente = await seedItem();

        await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.extractedFrom,
        );

        final note = await (db.select(
          db.knowledgeNotes,
        )..where((n) => n.itemId.equals(nota.id))).getSingle();
        expect(note.noteKind, NoteKind.atomic);
      });

      test('el cambio de subtipo queda registrado: la revisión y la versión '
          'del campo', () async {
        final nota = await seedNote();
        final fuente = await seedItem();
        Future<KnowledgeEntryRow> entry() => (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals(nota.id))).getSingle();
        final before = (await entry()).rev;

        await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.extractedFrom,
        );

        expect((await entry()).rev, before + 1);
        final version =
            await (db.select(db.fieldVersions)..where(
                  (f) =>
                      f.itemId.equals(nota.id) &
                      f.fieldName.equals(EntryField.noteKind),
                ))
                .getSingle();
        expect(version.updatedAt, now);
      });

      test('otro tipo de vínculo no toca noteKind', () async {
        final nota = await seedNote();
        final fuente = await seedItem();

        await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.relatedTo,
        );

        final note = await (db.select(
          db.knowledgeNotes,
        )..where((n) => n.itemId.equals(nota.id))).getSingle();
        expect(note.noteKind, NoteKind.living);
      });

      test('la nota hereda las propiedades de la fuente, con origin '
          'inherited', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final tema = (await repository.getOrCreatePropertyDefinition(
          'Tema',
        )).getRight().toNullable()!;
        final fuente = await seedItem();
        await repository.assignProperty(
          itemId: fuente.id,
          definitionId: region.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: fuente.id,
          definitionId: tema.id,
          value: 'Historia',
        );
        final nota = await seedNote();

        await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.extractedFrom,
        );

        final reloaded = (await libraryRepository.findById(
          nota.id,
        )).getRight().toNullable()!;
        // Los valores de Tema se muestran como etiquetas, no como
        // propiedades: la nota heredó los dos, cada uno donde corresponde.
        expect(reloaded.properties.map((p) => p.value), {'Roma'});
        expect(reloaded.tags.map((t) => t.name), ['Historia']);
        // El origin de las dos asignaciones —`Tag` no lo expone— se lee de
        // la tabla.
        final assignments = await (db.select(
          db.itemPropertyValues,
        )..where((a) => a.itemId.equals(nota.id))).get();
        expect(assignments, hasLength(2));
        expect(
          assignments.every((a) => a.origin == ItemPropertyOrigin.inherited),
          isTrue,
        );
      });

      test('una fuente sin propiedades no rompe nada', () async {
        final fuente = await seedItem();
        final nota = await seedNote();

        final result = await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.extractedFrom,
        );

        expect(result.isRight(), isTrue);
        final reloaded = (await libraryRepository.findById(
          nota.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, isEmpty);
      });

      test('una propiedad ya puesta a mano en la nota no se downgradea '
          'ni se duplica', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final fuente = await seedItem();
        await repository.assignProperty(
          itemId: fuente.id,
          definitionId: region.id,
          value: 'Roma',
        );
        final nota = await seedNote();
        await repository.assignProperty(
          itemId: nota.id,
          definitionId: region.id,
          value: 'Roma',
        );

        await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.extractedFrom,
        );

        final reloaded = (await libraryRepository.findById(
          nota.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, hasLength(1));
        expect(reloaded.properties.single.origin, ItemPropertyOrigin.manual);
      });

      test('otro tipo de vínculo no copia ninguna propiedad', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final fuente = await seedItem();
        await repository.assignProperty(
          itemId: fuente.id,
          definitionId: region.id,
          value: 'Roma',
        );
        final nota = await seedNote();

        await repository.createRelation(
          fromItemId: nota.id,
          toItemId: fuente.id,
          kind: RelationKind.relatedTo,
        );

        final reloaded = (await libraryRepository.findById(
          nota.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, isEmpty);
      });
    });
  });

  group('resaltados', () {
    test('se guarda con su texto y su nota', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id, content: 'texto largo');

      final result = await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 5,
        excerpt: 'texto',
        note: 'por qué importa',
      );

      expect(result.isRight(), isTrue);
      final highlight = result.getRight().toNullable()!;
      expect(highlight.excerpt, 'texto');
      expect(highlight.note, 'por qué importa');
    });

    test('una nota en blanco cuenta como ausente', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id);

      final result = await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 4,
        excerpt: 'text',
        note: '   ',
      );

      expect(result.getRight().toNullable()?.note, isNull);
    });

    test('una selección invertida o vacía se rechaza', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id);

      final invertido = await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 5,
        endOffset: 2,
        excerpt: 'x',
      );
      final vacio = await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 3,
        endOffset: 3,
        excerpt: '',
      );

      // El esquema también tiene un CHECK para esto, así que se comprueba el
      // tipo del fallo y no solo que sea `Left`.
      expect(invertido.getLeft().toNullable(), isA<ValidationFailure>());
      expect(vacio.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('se listan en el orden en que aparecen en el texto', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(
        item.id,
        content: 'uno dos tres cuatro',
      );

      // Se crean fuera de orden a propósito.
      await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 8,
        endOffset: 12,
        excerpt: 'tres',
      );
      await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 3,
        excerpt: 'uno',
      );

      final highlights = await repository
          .watchHighlightsForRendition(renditionId)
          .first;

      expect(highlights.map((h) => h.excerpt), ['uno', 'tres']);
    });

    test('cambiar la nota no cambia lo demás', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id);
      final created = (await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 4,
        excerpt: 'text',
      )).getRight().toNullable()!;

      final updated = await repository.updateHighlightNote(
        id: created.id,
        note: 'ahora sí tiene nota',
      );

      final highlight = updated.getRight().toNullable()!;
      expect(highlight.note, 'ahora sí tiene nota');
      expect(highlight.excerpt, 'text');
      expect(highlight.startOffset, 0);
    });

    test('poner la nota en null la borra', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id);
      final created = (await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 4,
        excerpt: 'text',
        note: 'algo',
      )).getRight().toNullable()!;

      final updated = await repository.updateHighlightNote(
        id: created.id,
        note: null,
      );

      expect(updated.getRight().toNullable()?.note, isNull);
    });

    test('borrar uno no toca los demás de la misma rendition', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id, content: 'uno dos');
      final first = (await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 3,
        excerpt: 'uno',
      )).getRight().toNullable()!;
      await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 4,
        endOffset: 7,
        excerpt: 'dos',
      );

      await repository.deleteHighlight(first.id);

      final remaining = await repository
          .watchHighlightsForRendition(renditionId)
          .first;
      expect(remaining.map((h) => h.excerpt), ['dos']);
    });

    test('borrar la rendition borra también sus resaltados', () async {
      final item = await seedItem();
      final renditionId = await seedRendition(item.id);
      await repository.createHighlight(
        renditionId: renditionId,
        startOffset: 0,
        endOffset: 4,
        excerpt: 'text',
      );

      // Reemplazar las renditions del elemento por una lista vacía las borra
      // — es el mismo camino que sigue una transcripción que se rehace.
      final reloaded = (await libraryRepository.findById(
        item.id,
      )).getRight().toNullable()!;
      await libraryRepository.save(reloaded.copyWith(renditions: []));

      final remaining = await repository
          .watchHighlightsForRendition(renditionId)
          .first;
      expect(remaining, isEmpty);
    });
  });

  group('propiedades', () {
    group('categorías', () {
      test(
        'listar todas, ordenadas alfabéticamente, actualizándose solo',
        () async {
          // "Fecha del hecho" y "Tema" son categorías de sistema,
          // sembradas desde el arranque —ver
          // `seedSystemPropertyCategories`—: dos inserts separados
          // durante `onCreate`, cada uno con su propia notificación. Se
          // deja que esos emits terminen antes de empezar a contar
          // cambios, para que no se cuelen como si fueran la reacción a
          // algo que hizo el test.
          await repository.watchAllPropertyDefinitions().first;

          final stream = repository.watchAllPropertyDefinitions();
          final queue = StreamQueue(stream);

          expect((await queue.next).map((d) => d.name), [
            'Fecha del hecho',
            'Tema',
          ]);

          await repository.getOrCreatePropertyDefinition('Región');
          expect((await queue.next).map((d) => d.name), [
            'Fecha del hecho',
            'Región',
            'Tema',
          ]);

          await repository.getOrCreatePropertyDefinition('Época');
          expect((await queue.next).map((d) => d.name), [
            'Fecha del hecho',
            'Región',
            'Tema',
            'Época',
          ]);

          await queue.cancel();
        },
      );

      test('un nombre nuevo se crea', () async {
        final result = await repository.getOrCreatePropertyDefinition('Región');

        expect(result.getRight().toNullable()!.name, 'Región');
      });

      test('un nombre repetido, sin distinguir mayúsculas, devuelve la '
          'misma categoría en vez de crear otra', () async {
        final first = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;

        final second = await repository.getOrCreatePropertyDefinition('región');

        expect(second.getRight().toNullable()!.id, first.id);
      });

      test('un nombre vacío falla', () async {
        final result = await repository.getOrCreatePropertyDefinition('   ');

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('crearla con un type indicado lo guarda', () async {
        final result = await repository.getOrCreatePropertyDefinition(
          'Población',
          type: PropertyValueType.number,
        );

        expect(result.getRight().toNullable()!.type, PropertyValueType.number);
      });

      test('un nombre repetido no le pisa el type a la categoría '
          'existente', () async {
        final first = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        expect(first.type, PropertyValueType.text);

        final second = await repository.getOrCreatePropertyDefinition(
          'región',
          type: PropertyValueType.number,
        );

        expect(second.getRight().toNullable()!.type, PropertyValueType.text);
      });

      test('borrar una categoría se lleva sus valores y las asignaciones '
          'que tenía puestas', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );

        await repository.deletePropertyDefinition(definition.id);

        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, isEmpty);
      });

      test('borrar una que no existe no falla', () async {
        final result = await repository.deletePropertyDefinition('no-existe');

        expect(result.isRight(), isTrue);
      });

      test('una categoría de sistema no se puede borrar', () async {
        final tema = await (db.select(
          db.propertyDefinitions,
        )..where((d) => d.name.equals('Tema'))).getSingle();

        final result = await repository.deletePropertyDefinition(tema.id);

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        final stillThere = await (db.select(
          db.propertyDefinitions,
        )..where((d) => d.id.equals(tema.id))).getSingleOrNull();
        expect(stillThere, isNotNull);
      });
    });

    group('asignar valores', () {
      test('un valor nuevo se crea y queda en el elemento', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        final result = await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );

        expect(result.isRight(), isTrue);
        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, hasLength(1));
        expect(reloaded.properties.single.value, 'Roma');
        expect(reloaded.properties.single.definitionName, 'Región');
      });

      test('el mismo valor, sin distinguir mayúsculas, se reutiliza en vez '
          'de crear uno nuevo', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final itemA = await seedItem();
        final itemB = await seedItem();

        await repository.assignProperty(
          itemId: itemA.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: itemB.id,
          definitionId: definition.id,
          value: 'roma',
        );

        final valueIdA = (await libraryRepository.findById(
          itemA.id,
        )).getRight().toNullable()!.properties.single.valueId;
        final valueIdB = (await libraryRepository.findById(
          itemB.id,
        )).getRight().toNullable()!.properties.single.valueId;
        expect(valueIdA, valueIdB);
      });

      test('un elemento puede tener varios valores bajo la misma '
          'categoría a la vez', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Egipto',
        );

        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties.map((p) => p.value), {'Roma', 'Egipto'});
      });

      test('asignar el mismo valor dos veces no falla ni lo duplica', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        final second = await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );

        expect(second.isRight(), isTrue);
        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, hasLength(1));
      });

      test('un valor vacío falla', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        final result = await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: '   ',
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('sin pasar origin, queda manual', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );

        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties.single.origin, ItemPropertyOrigin.manual);
      });

      test('con un origin indicado, se persiste tal cual', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
          origin: ItemPropertyOrigin.inherited,
        );

        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties.single.origin, ItemPropertyOrigin.inherited);
      });

      test('asignarlo dos veces con distinto origin deja el último', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();

        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
          origin: ItemPropertyOrigin.suggestedAccepted,
        );

        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(
          reloaded.properties.single.origin,
          ItemPropertyOrigin.suggestedAccepted,
        );
      });
    });

    group('resolución por label y alias, sin distinguir acentos', () {
      Future<String> seedDefinitionId(String name) async =>
          (await repository.getOrCreatePropertyDefinition(
            name,
          )).getRight().toNullable()!.id;

      Future<String> assignedValueId(String itemId) async =>
          (await libraryRepository.findById(
            itemId,
          )).getRight().toNullable()!.properties.single.valueId;

      Future<void> assign(String itemId, String definitionId, String value) =>
          repository.assignProperty(
            itemId: itemId,
            definitionId: definitionId,
            value: value,
          );

      Future<void> insertValue(
        String definitionId,
        String id,
        String label,
        DateTime createdAt,
      ) => db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: id,
              definitionId: definitionId,
              value: label,
              createdAt: createdAt,
            ),
          );

      Future<void> insertAlias(
        String definitionId,
        String valueId,
        String alias,
      ) => db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-${counter++}',
              propertyValueId: valueId,
              definitionId: definitionId,
              alias: alias,
              createdAt: now,
            ),
          );

      Future<int> valueCount(String definitionId) async => (await (db.select(
        db.propertyValues,
      )..where((v) => v.definitionId.equals(definitionId))).get()).length;

      group('asignar', () {
        test('otro acento reutiliza el valor en vez de duplicarlo', () async {
          final definitionId = await seedDefinitionId('Región');
          final a = await seedItem();
          final b = await seedItem();

          await assign(a.id, definitionId, 'Canción');
          await assign(b.id, definitionId, 'cancion');

          expect(await assignedValueId(b.id), await assignedValueId(a.id));
          expect(await valueCount(definitionId), 1);
        });

        test('una mayúscula con acento tampoco duplica: el lower() de SQLite '
            'solo baja ASCII', () async {
          final definitionId = await seedDefinitionId('Región');
          final a = await seedItem();
          final b = await seedItem();

          await assign(a.id, definitionId, 'Álgebra');
          await assign(b.id, definitionId, 'álgebra');

          expect(await assignedValueId(b.id), await assignedValueId(a.id));
          expect(await valueCount(definitionId), 1);
        });

        test('el texto de un alias resuelve al valor, no crea un duplicado '
            '(antes, asignar ignoraba los alias)', () async {
          final definitionId = await seedDefinitionId('Región');
          final a = await seedItem();
          final b = await seedItem();
          await assign(a.id, definitionId, 'Bizancio');
          final bizancioId = await assignedValueId(a.id);
          await insertAlias(definitionId, bizancioId, 'Constantinopla');

          final result = await repository.assignProperty(
            itemId: b.id,
            definitionId: definitionId,
            value: 'constantinópla',
          );

          expect(result.isRight(), isTrue);
          expect(await assignedValueId(b.id), bizancioId);
          expect(await valueCount(definitionId), 1);
        });

        test(
          'la eñe no se pliega: "Año" y "Ano" son valores distintos',
          () async {
            final definitionId = await seedDefinitionId('Región');
            final a = await seedItem();
            final b = await seedItem();

            await assign(a.id, definitionId, 'Año');
            await assign(b.id, definitionId, 'Ano');

            expect(
              await assignedValueId(b.id),
              isNot(await assignedValueId(a.id)),
            );
            expect(await valueCount(definitionId), 2);
          },
        );

        test('un valor realmente nuevo se crea con el texto tal cual se '
            'escribió', () async {
          final definitionId = await seedDefinitionId('Región');
          final item = await seedItem();

          await assign(item.id, definitionId, '  Canción  ');

          final reloaded = (await libraryRepository.findById(
            item.id,
          )).getRight().toNullable()!;
          expect(reloaded.properties.single.value, 'Canción');
        });

        test('con dos valores que solo difieren en el acento (de antes de '
            'F8), gana el que se escribió igual, después el que solo difiere '
            'en mayúsculas, y si no el más antiguo', () async {
          final definitionId = await seedDefinitionId('Región');
          // El índice UNIQUE es ASCII-only, así que estos dos conviven.
          await insertValue(definitionId, 'v-roma', 'Roma', DateTime(2026));
          await insertValue(
            definitionId,
            'v-roma-acento',
            'Róma',
            DateTime(2027),
          );
          final items = [
            await seedItem(),
            await seedItem(),
            await seedItem(),
            await seedItem(),
          ];

          await assign(items[0].id, definitionId, 'Róma');
          await assign(items[1].id, definitionId, 'RÓMA');
          await assign(items[2].id, definitionId, 'roma');
          await assign(items[3].id, definitionId, 'Ròma');

          expect(await assignedValueId(items[0].id), 'v-roma-acento');
          expect(await assignedValueId(items[1].id), 'v-roma-acento');
          expect(await assignedValueId(items[2].id), 'v-roma');
          // Ninguno de los dos coincide ni en mayúsculas: el más antiguo.
          expect(await assignedValueId(items[3].id), 'v-roma');
          expect(await valueCount(definitionId), 2);
        });
      });

      group('resolver', () {
        test('encuentra un valor sin distinguir acentos', () async {
          final definitionId = await seedDefinitionId('Región');
          final item = await seedItem();
          await assign(item.id, definitionId, 'Canción');

          final result = await repository.resolvePropertyValue(
            definitionId: definitionId,
            text: 'CANCION',
          );

          expect(result.getRight().toNullable()?.value, 'Canción');
        });

        test('encuentra un valor por un alias, sin distinguir acentos ni '
            'mayúsculas', () async {
          final definitionId = await seedDefinitionId('Región');
          final item = await seedItem();
          await assign(item.id, definitionId, 'Bizancio');
          final bizancioId = await assignedValueId(item.id);
          await insertAlias(definitionId, bizancioId, 'Ciudad de los Césares');

          final result = await repository.resolvePropertyValue(
            definitionId: definitionId,
            text: 'ciudad de los cesares',
          );

          expect(result.getRight().toNullable()?.id, bizancioId);
        });

        test(
          'un label gana sobre un alias con el mismo texto normalizado',
          () async {
            final definitionId = await seedDefinitionId('Región');
            final a = await seedItem();
            final b = await seedItem();
            await assign(a.id, definitionId, 'Roma');
            await assign(b.id, definitionId, 'Latium');
            final latiumId = await assignedValueId(b.id);
            await insertAlias(definitionId, latiumId, 'Róma');

            final result = await repository.resolvePropertyValue(
              definitionId: definitionId,
              text: 'róma',
            );

            expect(result.getRight().toNullable()?.value, 'Roma');
          },
        );

        test('la eñe no se pliega al resolver', () async {
          final definitionId = await seedDefinitionId('Región');
          final item = await seedItem();
          await assign(item.id, definitionId, 'Año');

          final result = await repository.resolvePropertyValue(
            definitionId: definitionId,
            text: 'Ano',
          );

          expect(result.getRight().toNullable(), isNull);
        });

        test('un texto solo de espacios no resuelve a nada', () async {
          final definitionId = await seedDefinitionId('Región');

          final result = await repository.resolvePropertyValue(
            definitionId: definitionId,
            text: '   ',
          );

          expect(result.getRight().toNullable(), isNull);
        });
      });

      group('renombrar', () {
        test('no se puede renombrar para chocar con otro valor que solo '
            'difiere en el acento', () async {
          final definitionId = await seedDefinitionId('Región');
          final a = await seedItem();
          final b = await seedItem();
          await assign(a.id, definitionId, 'Roma');
          await assign(b.id, definitionId, 'Egipto');

          final result = await repository.renamePropertyValue(
            id: await assignedValueId(b.id),
            label: 'Róma',
          );

          expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        });

        test('no se puede renombrar para chocar con un alias que solo '
            'difiere en el acento', () async {
          final definitionId = await seedDefinitionId('Región');
          final a = await seedItem();
          final b = await seedItem();
          await assign(a.id, definitionId, 'Bizancio');
          await assign(b.id, definitionId, 'Otra región');
          await insertAlias(
            definitionId,
            await assignedValueId(a.id),
            'Constantinopla',
          );

          final result = await repository.renamePropertyValue(
            id: await assignedValueId(b.id),
            label: 'Constantinópla',
          );

          expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        });

        test(
          'cambiar solo el acento o las mayúsculas del propio label sí se '
          'permite: es corregir la grafía, no chocar consigo mismo',
          () async {
            final definitionId = await seedDefinitionId('Región');
            final item = await seedItem();
            await assign(item.id, definitionId, 'Roma');
            final valueId = await assignedValueId(item.id);

            final result = await repository.renamePropertyValue(
              id: valueId,
              label: 'Róma',
            );

            expect(result.getRight().toNullable()?.value, 'Róma');
            expect(await assignedValueId(item.id), valueId);
          },
        );
      });
    });

    group('quitar valores', () {
      test('saca el valor del elemento sin borrarlo para los demás', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final itemA = await seedItem();
        final itemB = await seedItem();
        await repository.assignProperty(
          itemId: itemA.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: itemB.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        final valueId = (await libraryRepository.findById(
          itemA.id,
        )).getRight().toNullable()!.properties.single.valueId;

        await repository.removeItemProperty(
          itemId: itemA.id,
          propertyValueId: valueId,
        );

        final reloadedA = (await libraryRepository.findById(
          itemA.id,
        )).getRight().toNullable()!;
        final reloadedB = (await libraryRepository.findById(
          itemB.id,
        )).getRight().toNullable()!;
        expect(reloadedA.properties, isEmpty);
        expect(reloadedB.properties, hasLength(1));
      });
    });

    group('renombrar valores', () {
      test('el nuevo label queda guardado', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Bizancio',
        );
        final valueId = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!.properties.single.valueId;

        final result = await repository.renamePropertyValue(
          id: valueId,
          label: 'Constantinopla',
        );

        expect(result.getRight().toNullable()?.value, 'Constantinopla');
      });

      test('un label en blanco se rechaza', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        final valueId = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!.properties.single.valueId;

        final result = await repository.renamePropertyValue(
          id: valueId,
          label: '   ',
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('no se puede renombrar para chocar con otro valor de la misma '
          'categoría', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Atenas',
        );
        final atenasId = (await libraryRepository.findById(item.id))
            .getRight()
            .toNullable()!
            .properties
            .firstWhere((p) => p.value == 'Atenas')
            .valueId;

        final result = await repository.renamePropertyValue(
          id: atenasId,
          label: 'roma',
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('el mismo label en otra categoría SÍ se permite', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final ciudadNatal = (await repository.getOrCreatePropertyDefinition(
          'Ciudad natal',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: region.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: ciudadNatal.id,
          value: 'Otra ciudad',
        );
        final otraCiudadId = (await libraryRepository.findById(item.id))
            .getRight()
            .toNullable()!
            .properties
            .firstWhere((p) => p.value == 'Otra ciudad')
            .valueId;

        final result = await repository.renamePropertyValue(
          id: otraCiudadId,
          label: 'Roma',
        );

        expect(result.getRight().toNullable()?.value, 'Roma');
      });

      test('renombrarlo a su propio label no choca consigo mismo', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        final valueId = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!.properties.single.valueId;

        final result = await repository.renamePropertyValue(
          id: valueId,
          label: 'roma',
        );

        expect(result.getRight().toNullable()?.value, 'roma');
      });

      test('no se puede renombrar para chocar con un alias de la misma '
          'categoría', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Bizancio',
        );
        final valueId = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!.properties.single.valueId;
        await db
            .into(db.propertyAliases)
            .insert(
              PropertyAliasesCompanion.insert(
                id: 'alias-1',
                propertyValueId: valueId,
                definitionId: definition.id,
                alias: 'Constantinopla',
                createdAt: now,
              ),
            );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Otra región',
        );
        final otraId = (await libraryRepository.findById(item.id))
            .getRight()
            .toNullable()!
            .properties
            .firstWhere((p) => p.value == 'Otra región')
            .valueId;

        final result = await repository.renamePropertyValue(
          id: otraId,
          label: 'constantinopla',
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('uno que ya no existe devuelve un fallo, no revienta', () async {
        final result = await repository.renamePropertyValue(
          id: 'no-existe',
          label: 'Lo que sea',
        );

        expect(result.isLeft(), isTrue);
      });
    });

    group('resolver valores', () {
      test(
        'encuentra un valor por su label, sin distinguir mayúsculas',
        () async {
          final definition = (await repository.getOrCreatePropertyDefinition(
            'Región',
          )).getRight().toNullable()!;
          final item = await seedItem();
          await repository.assignProperty(
            itemId: item.id,
            definitionId: definition.id,
            value: 'Roma',
          );

          final result = await repository.resolvePropertyValue(
            definitionId: definition.id,
            text: 'roma',
          );

          expect(result.getRight().toNullable()?.value, 'Roma');
        },
      );

      test('encuentra un valor por un alias suyo, sin distinguir '
          'mayúsculas', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Bizancio',
        );
        final valueId = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!.properties.single.valueId;
        await db
            .into(db.propertyAliases)
            .insert(
              PropertyAliasesCompanion.insert(
                id: 'alias-1',
                propertyValueId: valueId,
                definitionId: definition.id,
                alias: 'Constantinopla',
                createdAt: now,
              ),
            );

        final result = await repository.resolvePropertyValue(
          definitionId: definition.id,
          text: 'constantinopla',
        );

        expect(result.getRight().toNullable()?.id, valueId);
        expect(result.getRight().toNullable()?.value, 'Bizancio');
      });

      test('sin ningún match, un null sin ser un fallo', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;

        final result = await repository.resolvePropertyValue(
          definitionId: definition.id,
          text: 'No existe',
        );

        expect(result.isRight(), isTrue);
        expect(result.getRight().toNullable(), isNull);
      });

      test('el mismo texto en otra categoría no matchea', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final ciudadNatal = (await repository.getOrCreatePropertyDefinition(
          'Ciudad natal',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: region.id,
          value: 'Roma',
        );

        final result = await repository.resolvePropertyValue(
          definitionId: ciudadNatal.id,
          text: 'Roma',
        );

        expect(result.getRight().toNullable(), isNull);
      });
    });

    group('fusionar valores', () {
      Future<String> valueIdByLabel(String definitionId, String label) async {
        final row =
            await (db.select(db.propertyValues)..where(
                  (v) =>
                      v.definitionId.equals(definitionId) &
                      v.value.equals(label),
                ))
                .getSingle();
        return row.id;
      }

      test('lo que tenía el descartado pasa al que se conserva, y su '
          'label queda como alias', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma antigua',
        );
        final romaAntiguaId = await valueIdByLabel(
          definition.id,
          'Roma antigua',
        );
        // "Roma" se crea aparte —sin asignarla a ningún elemento— para
        // que sea claramente el valor que se conserva.
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: 'val-roma',
                definitionId: definition.id,
                value: 'Roma',
                createdAt: now,
              ),
            );

        final result = await repository.mergePropertyValues(
          keepId: 'val-roma',
          discardId: romaAntiguaId,
        );

        expect(result.isRight(), isTrue);
        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties.single.valueId, 'val-roma');
        expect(reloaded.properties.single.value, 'Roma');

        final resolved = await repository.resolvePropertyValue(
          definitionId: definition.id,
          text: 'Roma antigua',
        );
        expect(resolved.getRight().toNullable()?.id, 'val-roma');

        final discardStillThere = await (db.select(
          db.propertyValues,
        )..where((v) => v.id.equals(romaAntiguaId))).getSingleOrNull();
        expect(discardStillThere, isNull);
      });

      test('un elemento que ya tenía asignados los dos termina con uno '
          'solo, sin romper por la clave compuesta', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma antigua',
        );
        final keepId = await valueIdByLabel(definition.id, 'Roma');
        final discardId = await valueIdByLabel(definition.id, 'Roma antigua');

        final result = await repository.mergePropertyValues(
          keepId: keepId,
          discardId: discardId,
        );

        expect(result.isRight(), isTrue);
        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties, hasLength(1));
        expect(reloaded.properties.single.valueId, keepId);
      });

      test('un alias que ya tenía el descartado pasa a apuntar al que se '
          'conserva', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Bizancio',
        );
        final discardId = await valueIdByLabel(definition.id, 'Bizancio');
        await db
            .into(db.propertyAliases)
            .insert(
              PropertyAliasesCompanion.insert(
                id: 'alias-vieja',
                propertyValueId: discardId,
                definitionId: definition.id,
                alias: 'Vieja Roma',
                createdAt: now,
              ),
            );
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: 'val-roma',
                definitionId: definition.id,
                value: 'Roma',
                createdAt: now,
              ),
            );

        final result = await repository.mergePropertyValues(
          keepId: 'val-roma',
          discardId: discardId,
        );

        expect(result.isRight(), isTrue);
        final resolved = await repository.resolvePropertyValue(
          definitionId: definition.id,
          text: 'Vieja Roma',
        );
        expect(resolved.getRight().toNullable()?.id, 'val-roma');
      });

      test('no se pueden fusionar valores de categorías distintas', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final ciudadNatal = (await repository.getOrCreatePropertyDefinition(
          'Ciudad natal',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: region.id,
          value: 'Roma',
        );
        await repository.assignProperty(
          itemId: item.id,
          definitionId: ciudadNatal.id,
          value: 'Otra ciudad',
        );
        final regionValueId = await valueIdByLabel(region.id, 'Roma');
        final ciudadValueId = await valueIdByLabel(
          ciudadNatal.id,
          'Otra ciudad',
        );

        final result = await repository.mergePropertyValues(
          keepId: regionValueId,
          discardId: ciudadValueId,
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('un valor no se puede fusionar consigo mismo', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        final valueId = await valueIdByLabel(definition.id, 'Roma');

        final result = await repository.mergePropertyValues(
          keepId: valueId,
          discardId: valueId,
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('un id que ya no existe devuelve un fallo, no revienta', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Roma',
        );
        final valueId = await valueIdByLabel(definition.id, 'Roma');

        final result = await repository.mergePropertyValues(
          keepId: valueId,
          discardId: 'no-existe',
        );

        expect(result.isLeft(), isTrue);
      });

      test('si el label del descartado ya es alias de un tercero, la '
          'fusión igual se completa sin ese alias nuevo', () async {
        final definition = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final item = await seedItem();
        await repository.assignProperty(
          itemId: item.id,
          definitionId: definition.id,
          value: 'Bizancio',
        );
        final discardId = await valueIdByLabel(definition.id, 'Bizancio');
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: 'val-tercero',
                definitionId: definition.id,
                value: 'Un tercero',
                createdAt: now,
              ),
            );
        // "Bizancio" ya es alias de un valor sin relación con la
        // fusión: el paso 4 no puede sumarlo de nuevo para el ganador
        // sin chocar con el UNIQUE de la categoría.
        await db
            .into(db.propertyAliases)
            .insert(
              PropertyAliasesCompanion.insert(
                id: 'alias-tercero',
                propertyValueId: 'val-tercero',
                definitionId: definition.id,
                alias: 'Bizancio',
                createdAt: now,
              ),
            );
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: 'val-roma',
                definitionId: definition.id,
                value: 'Roma',
                createdAt: now,
              ),
            );

        final result = await repository.mergePropertyValues(
          keepId: 'val-roma',
          discardId: discardId,
        );

        expect(result.isRight(), isTrue);
        final reloaded = (await libraryRepository.findById(
          item.id,
        )).getRight().toNullable()!;
        expect(reloaded.properties.single.valueId, 'val-roma');
        // El alias "Bizancio" se lo queda el tercero, como antes.
        final resolved = await repository.resolvePropertyValue(
          definitionId: definition.id,
          text: 'Bizancio',
        );
        expect(resolved.getRight().toNullable()?.id, 'val-tercero');
      });
    });

    group('valores históricos', () {
      test('crea un valor con su rango, y la segunda llamada con la '
          'misma fecha reusa el mismo', () async {
        final fecha = (await repository.getOrCreatePropertyDefinition(
          'Fecha del hecho fundacional',
          type: PropertyValueType.date,
        )).getRight().toNullable()!;
        const date = HistoricalDate(
          year: 44,
          precision: DatePrecision.year,
          isBce: true,
        );

        final first = await repository.getOrCreateHistoricalPropertyValue(
          definitionId: fecha.id,
          date: date,
        );
        final second = await repository.getOrCreateHistoricalPropertyValue(
          definitionId: fecha.id,
          date: date,
        );

        expect(first.getRight().toNullable()?.value, '44 a.C.');
        expect(
          second.getRight().toNullable()?.id,
          first.getRight().toNullable()?.id,
        );
        expect(
          await (db.select(
            db.propertyValues,
          )..where((v) => v.definitionId.equals(fecha.id))).get(),
          hasLength(1),
        );
      });

      test('una categoría que no es de tipo fecha se rechaza', () async {
        final region = (await repository.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;

        final result = await repository.getOrCreateHistoricalPropertyValue(
          definitionId: region.id,
          date: const HistoricalDate(year: 44, precision: DatePrecision.year),
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test('una categoría que no existe se rechaza', () async {
        final result = await repository.getOrCreateHistoricalPropertyValue(
          definitionId: 'no-existe',
          date: const HistoricalDate(year: 44, precision: DatePrecision.year),
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      });

      test(
        'la fecha original se reconstruye igual al leerla de vuelta',
        () async {
          final fecha = (await repository.getOrCreatePropertyDefinition(
            'Fecha del hecho fundacional',
            type: PropertyValueType.date,
          )).getRight().toNullable()!;
          const date = HistoricalDate(
            year: 44,
            precision: DatePrecision.month,
            month: 3,
            isBce: true,
            isCirca: true,
          );

          await repository.getOrCreateHistoricalPropertyValue(
            definitionId: fecha.id,
            date: date,
          );

          final values = await repository.watchPropertyValues(fecha.id).first;

          expect(values.single.historicalDate, date);
        },
      );
    });
  });
}
