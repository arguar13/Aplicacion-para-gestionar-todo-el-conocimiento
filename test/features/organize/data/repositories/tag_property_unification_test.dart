import 'package:async/async.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// F8: una etiqueta ES un valor de la categoría Tema. Estos tests son la
/// razón de ser de la unificación: el bug que arregla era que una etiqueta
/// creada en la interfaz no existía como propiedad, y filtrar por la
/// propiedad devolvía resultados incompletos sin avisar.
///
/// Contra SQLite real, en memoria, por los mismos caminos que usa la app:
/// `getOrCreateTag` + `save` para la interfaz de etiquetas, `assignProperty`
/// para la de propiedades.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late OrganizeRepositoryImpl organize;

  final now = DateTime(2026, 9, 19, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'gen'),
      clock: () => now,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem() async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: 'Elemento $n',
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
    return (await library.save(item)).getRight().toNullable()!;
  }

  Future<KnowledgeItem> reload(String id) async =>
      (await library.findById(id)).getRight().toNullable()!;

  Future<String> temaId() => temaDefinitionId(db);

  /// Como lo hace `TagEditor`: `getOrCreateTag` y guardar el elemento con la
  /// lista de etiquetas cambiada.
  Future<Tag> addTagFromUi(KnowledgeItem item, String name) async {
    final tag = (await organize.getOrCreateTag(name)).getRight().toNullable()!;
    final current = await reload(item.id);
    await library.save(current.copyWith(tags: [...current.tags, tag]));
    return tag;
  }

  Future<List<String>> idsMatching(LibraryQuery query) async =>
      (await library.list(
        query,
      )).getRight().toNullable()!.map((i) => i.id).toList();

  group('etiqueta creada en la interfaz de etiquetas', () {
    test('aparece al filtrar por la propiedad Tema', () async {
      final item = await seedItem();
      await seedItem(); // otro elemento, sin la etiqueta

      final tag = await addTagFromUi(item, 'Filosofía');

      // Por el filtro de propiedades, con el id del valor: solo el que la
      // tiene, no el otro.
      expect(await idsMatching(LibraryQuery(propertyValueIds: {tag.id})), [
        item.id,
      ]);
    });

    test(
      'es un valor de la categoría Tema, con el mismo id que la etiqueta',
      () async {
        final item = await seedItem();

        final tag = await addTagFromUi(item, 'Filosofía');

        final values = await organize.watchPropertyValues(await temaId()).first;
        expect(values.map((v) => (v.id, v.value)), [(tag.id, 'Filosofía')]);
      },
    );

    test('se resuelve como propiedad de Tema, por su texto', () async {
      final item = await seedItem();
      final tag = await addTagFromUi(item, 'Filosofía');

      final resolved = await organize.resolvePropertyValue(
        definitionId: await temaId(),
        text: 'filosofia',
      );

      expect(resolved.getRight().toNullable()?.id, tag.id);
    });

    test(
      'el filtro por etiqueta y el filtro por propiedad dan lo mismo',
      () async {
        final item = await seedItem();
        await seedItem();
        final tag = await addTagFromUi(item, 'Filosofía');

        expect(
          await idsMatching(LibraryQuery(tagIds: {tag.id})),
          await idsMatching(LibraryQuery(propertyValueIds: {tag.id})),
        );
      },
    );

    test('no aparece además como propiedad: cada cosa una sola vez', () async {
      final item = await seedItem();

      await addTagFromUi(item, 'Filosofía');

      final reloaded = await reload(item.id);
      expect(reloaded.tags.map((t) => t.name), ['Filosofía']);
      expect(reloaded.properties, isEmpty);
    });
  });

  group('valor de Tema asignado en la interfaz de propiedades', () {
    test(
      'aparece como etiqueta del elemento y en la lista de etiquetas',
      () async {
        final item = await seedItem();

        await organize.assignProperty(
          itemId: item.id,
          definitionId: await temaId(),
          value: 'Historia',
        );

        final reloaded = await reload(item.id);
        expect(reloaded.tags.map((t) => t.name), ['Historia']);
        expect(reloaded.properties, isEmpty);
        expect((await organize.watchAllTags().first).map((t) => t.name), [
          'Historia',
        ]);
      },
    );

    test('aparece al filtrar por etiqueta', () async {
      final item = await seedItem();
      await organize.assignProperty(
        itemId: item.id,
        definitionId: await temaId(),
        value: 'Historia',
      );
      final tag = (await reload(item.id)).tags.single;

      expect(await idsMatching(LibraryQuery(tagIds: {tag.id})), [item.id]);
    });

    test(
      'escribir el alias de una etiqueta la resuelve en vez de duplicarla',
      () async {
        final item = await seedItem();
        final tag = await addTagFromUi(item, 'Bizancio');
        await db
            .into(db.propertyAliases)
            .insert(
              PropertyAliasesCompanion.insert(
                id: 'alias-1',
                propertyValueId: tag.id,
                definitionId: await temaId(),
                alias: 'Constantinopla',
                createdAt: now,
              ),
            );

        final resolved = (await organize.getOrCreateTag(
          'constantinópla',
        )).getRight().toNullable()!;

        expect(resolved.id, tag.id);
        expect(await organize.watchAllTags().first, hasLength(1));
      },
    );
  });

  group('guardar un elemento', () {
    test('no degrada el origin de una etiqueta que llegó como sugerencia '
        'aceptada', () async {
      final item = await seedItem();
      await organize.assignProperty(
        itemId: item.id,
        definitionId: await temaId(),
        value: 'Historia',
        origin: ItemPropertyOrigin.suggestedAccepted,
      );

      // Un guardado cualquiera del mismo elemento, con las etiquetas tal
      // como se leyeron.
      final loaded = await reload(item.id);
      await library.save(loaded.copyWith(title: 'Otro título'));

      final assignment = await db.select(db.itemPropertyValues).getSingle();
      expect(assignment.origin, ItemPropertyOrigin.suggestedAccepted);
    });

    test('quitar una etiqueta de la lista quita solo esa asignación', () async {
      final item = await seedItem();
      final a = await addTagFromUi(item, 'Arte');
      await addTagFromUi(item, 'Historia');

      final current = await reload(item.id);
      await library.save(
        current.copyWith(
          tags: current.tags.where((t) => t.id != a.id).toList(),
        ),
      );

      expect((await reload(item.id)).tags.map((t) => t.name), ['Historia']);
      // El valor sigue existiendo para los demás elementos.
      expect((await organize.watchAllTags().first).map((t) => t.name), [
        'Arte',
        'Historia',
      ]);
    });

    test('no toca las propiedades que no son Tema', () async {
      final item = await seedItem();
      final region = (await organize.getOrCreatePropertyDefinition(
        'Región',
      )).getRight().toNullable()!;
      await organize.assignProperty(
        itemId: item.id,
        definitionId: region.id,
        value: 'Roma',
      );

      await addTagFromUi(item, 'Historia');

      final reloaded = await reload(item.id);
      expect(reloaded.properties.map((p) => p.value), ['Roma']);
      expect(reloaded.tags.map((t) => t.name), ['Historia']);
    });

    test(
      'sigue sincronizando por completo las propiedades que no son Tema',
      () async {
        final item = await seedItem();
        final region = (await organize.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        final roma = ItemProperty(
          definitionId: region.id,
          definitionName: 'Región',
          valueId: 'v-roma',
          value: 'Roma',
          createdAt: now,
        );
        await library.save(item.copyWith(properties: [roma]));
        expect((await reload(item.id)).properties.map((p) => p.value), [
          'Roma',
        ]);

        await library.save((await reload(item.id)).copyWith(properties: []));

        expect((await reload(item.id)).properties, isEmpty);
      },
    );

    test('una etiqueta armada en memoria crea su valor en Tema, con su mismo '
        'id', () async {
      final item = await seedItem();
      final tag = Tag(id: 'tag-en-memoria', name: 'Ética', createdAt: now);

      await library.save(item.copyWith(tags: [tag]));

      final value = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals('tag-en-memoria'))).getSingle();
      expect(value.definitionId, await temaId());
      expect(value.value, 'Ética');
      expect((await reload(item.id)).tags.single.id, 'tag-en-memoria');
    });

    test('una propiedad de Tema que llega en item.properties no se pierde: '
        'se trata como etiqueta', () async {
      final item = await seedItem();
      final property = ItemProperty(
        definitionId: await temaId(),
        definitionName: 'Tema',
        valueId: 'v-tema',
        value: 'Lógica',
        createdAt: now,
        origin: ItemPropertyOrigin.inherited,
      );

      await library.save(item.copyWith(properties: [property]));

      final reloaded = await reload(item.id);
      expect(reloaded.tags.map((t) => t.name), ['Lógica']);
      expect(reloaded.properties, isEmpty);
      final assignment = await db.select(db.itemPropertyValues).getSingle();
      expect(assignment.origin, ItemPropertyOrigin.inherited);
    });
  });

  group('renombrar y borrar', () {
    test('renombrar una etiqueta cambia el valor de Tema y se ve en los '
        'elementos', () async {
      final item = await seedItem();
      final tag = await addTagFromUi(item, 'Filosofia');

      await organize.renameTag(id: tag.id, name: 'Filosofía');

      expect((await reload(item.id)).tags.single.name, 'Filosofía');
      final values = await organize.watchPropertyValues(await temaId()).first;
      expect(values.single.value, 'Filosofía');
    });

    test('renombrar por esta API un valor que no es de Tema falla', () async {
      final item = await seedItem();
      final region = (await organize.getOrCreatePropertyDefinition(
        'Región',
      )).getRight().toNullable()!;
      await organize.assignProperty(
        itemId: item.id,
        definitionId: region.id,
        value: 'Roma',
      );
      final roma = (await reload(item.id)).properties.single;

      final result = await organize.renameTag(id: roma.valueId, name: 'Otra');

      expect(result.isLeft(), isTrue);
    });

    test('borrar una etiqueta la saca de los elementos y de Tema', () async {
      final item = await seedItem();
      final tag = await addTagFromUi(item, 'Efímera');

      await organize.deleteTag(tag.id);

      expect((await reload(item.id)).tags, isEmpty);
      expect(await organize.watchPropertyValues(await temaId()).first, isEmpty);
    });

    test(
      'borrar por esta API un valor que no es de Tema no lo borra',
      () async {
        final item = await seedItem();
        final region = (await organize.getOrCreatePropertyDefinition(
          'Región',
        )).getRight().toNullable()!;
        await organize.assignProperty(
          itemId: item.id,
          definitionId: region.id,
          value: 'Roma',
        );
        final roma = (await reload(item.id)).properties.single;

        await organize.deleteTag(roma.valueId);

        expect((await reload(item.id)).properties.map((p) => p.value), [
          'Roma',
        ]);
      },
    );
  });

  test('la lista de etiquetas se actualiza sola cuando se asigna un valor de '
      'Tema', () async {
    final item = await seedItem();
    final queue = StreamQueue(organize.watchAllTags());
    addTearDown(queue.cancel);
    expect(await queue.next, isEmpty);

    await organize.assignProperty(
      itemId: item.id,
      definitionId: await temaId(),
      value: 'Historia',
    );

    expect((await queue.next).map((t) => t.name), ['Historia']);
  });
}
