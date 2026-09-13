import 'package:async/async.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
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
}
