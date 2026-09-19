import 'dart:io';

import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/fake_duplicate_suggestion_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria. Un doble de la base respondería lo que se
/// le pida y no probaría ni las transacciones, ni las cascadas, ni la
/// búsqueda — que es justamente lo que hay que verificar acá.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repository;
  late InMemoryFileStore files;

  final now = DateTime(2026, 9, 11, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = InMemoryFileStore();
    repository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: files,
    );
    counter = 0;
  });

  tearDown(() => db.close());

  /// Las etiquetas que existen hoy: desde F8 son los valores de Tema.
  Future<List<PropertyValueRow>> temaValues() async {
    final tema = await temaDefinitionId(db);
    return (db.select(
      db.propertyValues,
    )..where((v) => v.definitionId.equals(tema))).get();
  }

  KnowledgeItem buildItem({
    String? id,
    String title = 'La estructura de las revoluciones científicas',
    String? subtitle,
    SourceKind sourceKind = SourceKind.webPage,
    DateTime? capturedAt,
    DateTime? publishedAt,
    ProcessingState state = ProcessingState.ready,
    List<Rendition> renditions = const [],
    List<Tag> tags = const [],
  }) {
    final n = counter++;
    final itemId = id ?? 'item-$n';
    return KnowledgeItem(
      id: itemId,
      title: title,
      subtitle: subtitle,
      source: Source(
        id: 'src-$n',
        kind: sourceKind,
        capturedAt: capturedAt ?? now,
        publishedAt: publishedAt,
        url: 'https://ejemplo.org/$n',
        authorName: 'Autora $n',
        authorUrl: 'https://ejemplo.org/autora-$n',
      ),
      processingState: state,
      createdAt: now,
      updatedAt: now,
      renditions: renditions,
      tags: tags,
    );
  }

  Rendition textRendition(
    String itemId,
    String content, {
    String? id,
    bool isPrimary = true,
  }) => Rendition.text(
    id: id ?? 'rend-${counter++}',
    itemId: itemId,
    kind: RenditionKind.plainText,
    content: content,
    isPrimary: isPrimary,
    createdAt: now,
  );

  group('guardar y recuperar', () {
    test('un elemento vuelve completo: con su fuente, sus formas y sus '
        'etiquetas', () async {
      final base = buildItem(subtitle: 'Thomas Kuhn, 1962');
      final item = base.copyWith(
        renditions: [textRendition(base.id, 'El concepto de paradigma...')],
        tags: [Tag(id: 'tag-1', name: 'epistemología', createdAt: now)],
      );

      await repository.save(item);
      final found = (await repository.findById(
        item.id,
      )).getRight().toNullable();

      expect(found, isNotNull);
      expect(found!.title, item.title);
      expect(found.subtitle, 'Thomas Kuhn, 1962');
      // Lo que más importa: la procedencia sobrevivió al viaje completo.
      expect(found.source.url, item.source.url);
      expect(found.source.authorName, 'Autora 0');
      expect(found.source.authorUrl, item.source.authorUrl);
      expect(found.renditions, hasLength(1));
      expect(found.tags.map((t) => t.name), ['epistemología']);
    });

    test('un elemento que no existe devuelve null, no un error', () async {
      final result = await repository.findById('no-existe');

      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable(), isNull);
    });

    test('guardar dos veces actualiza en vez de duplicar', () async {
      final item = buildItem(title: 'Título original');
      await repository.save(item);

      await repository.save(item.copyWith(title: 'Título corregido'));

      final all = (await repository.list(
        const LibraryQuery(),
      )).getRight().toNullable()!;
      expect(all, hasLength(1));
      expect(all.single.title, 'Título corregido');
    });

    test(
      'el guardado es atómico: si algo falla, no queda nada a medias',
      () async {
        // Una forma inválida —sin texto ni archivo— viola el CHECK del esquema
        // en mitad de la transacción, después de haber escrito la fuente y el
        // elemento.
        final base = buildItem();
        final broken = base.copyWith(
          renditions: [
            Rendition.file(
              id: 'r1',
              itemId: base.id,
              kind: RenditionKind.image,
              relativePath: '',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        );

        // Se fuerza el fallo insertando directamente una forma inválida con el
        // mismo identificador, para que el upsert choque.
        await db.customStatement(
          'INSERT INTO sources (id, kind, captured_at) VALUES (?, ?, ?)',
          [base.source.id, 'webPage', now.millisecondsSinceEpoch ~/ 1000],
        );

        final result = await repository.save(broken.copyWith(title: 'x' * 10));

        // Sea cual sea el desenlace, lo que no puede pasar es que quede un
        // elemento sin sus formas: o entró todo, o no entró nada.
        if (result.isRight()) {
          final found = (await repository.findById(
            broken.id,
          )).getRight().toNullable();
          expect(found!.renditions, hasLength(1));
        } else {
          expect(await db.select(db.items).get(), isEmpty);
        }
      },
    );
  });

  group('actualizar sin destruir', () {
    test('actualizar un elemento NO borra los subrayados de las formas que '
        'siguen estando', () async {
      // El bug que esta implementación evita a propósito: rehacer todas las
      // formas en cada guardado sería más corto de escribir y se llevaría por
      // delante, en cascada, cada subrayado y cada nota al margen del
      // usuario. Sin ruido y sin vuelta atrás.
      final base = buildItem();
      final rendition = textRendition(
        base.id,
        'una frase que alguien va a subrayar',
        id: 'rend-fijo',
      );
      await repository.save(base.copyWith(renditions: [rendition]));

      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              id: 'hl-1',
              renditionId: 'rend-fijo',
              startOffset: 2,
              endOffset: 7,
              excerpt: 'frase',
              createdAt: now,
            ),
          );

      // Se guarda otra vez, cambiando solo el título.
      await repository.save(
        base.copyWith(title: 'Otro título', renditions: [rendition]),
      );

      expect(await db.select(db.highlights).get(), hasLength(1));
    });

    test('una forma que desaparece de la entidad sí se borra', () async {
      final base = buildItem();
      final a = textRendition(base.id, 'primera', id: 'r-a');
      final b = textRendition(base.id, 'segunda', id: 'r-b', isPrimary: false);
      await repository.save(base.copyWith(renditions: [a, b]));

      await repository.save(base.copyWith(renditions: [a]));

      final found = (await repository.findById(
        base.id,
      )).getRight().toNullable();
      expect(found!.renditions.map((r) => r.renditionId), ['r-a']);
    });

    test('quitar una etiqueta de un elemento no borra la etiqueta para los '
        'demás', () async {
      final tag = Tag(id: 'tag-1', name: 'filosofía', createdAt: now);
      final a = buildItem(title: 'A');
      final b = buildItem(title: 'B');
      await repository.save(a.copyWith(tags: [tag]));
      await repository.save(b.copyWith(tags: [tag]));

      await repository.save(a.copyWith(tags: const []));

      final foundB = (await repository.findById(b.id)).getRight().toNullable();
      expect(foundB!.tags.map((t) => t.name), ['filosofía']);
      // La etiqueta es un valor de Tema: seguir existiendo para B lo
      // comprueba la línea de arriba, y sigue siendo UN solo valor.
      expect(await temaValues(), hasLength(1));
    });
  });

  group('borrar', () {
    test('borra el elemento y todo lo que cuelga de él', () async {
      final base = buildItem();
      await repository.save(
        base.copyWith(
          renditions: [textRendition(base.id, 'contenido')],
          tags: [Tag(id: 'tag-1', name: 'algo', createdAt: now)],
        ),
      );

      await repository.delete(base.id);

      expect(await db.select(db.items).get(), isEmpty);
      expect(await db.select(db.renditions).get(), isEmpty);
      expect(await db.select(db.itemPropertyValues).get(), isEmpty);
      // La etiqueta en sí sobrevive: puede estar en uso por otros elementos,
      // y aunque no lo esté, es parte del vocabulario del usuario.
      expect(await temaValues(), hasLength(1));
    });

    test('también borra el archivo original del disco', () async {
      // Las cascadas del esquema limpian la base, pero el disco no tiene
      // cascadas. Sin esto, borrar cincuenta PDFs dejaría cincuenta PDFs
      // ocupando el teléfono sin que nada los referencie.
      final base = buildItem();
      final path = await files.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'apunte.pdf',
        id: base.source.id,
      );
      await repository.save(
        base.copyWith(source: base.source.copyWith(originalFilePath: path)),
      );

      await repository.delete(base.id);

      expect(files.deleted, [path]);
      expect(files.paths, isEmpty);
    });

    test('un archivo compartido por dos elementos NO se borra', () async {
      // El mismo PDF capturado dos veces reutiliza su fila de fuente. Borrar
      // el archivo al eliminar el primero dejaría al segundo apuntando a algo
      // que ya no está.
      final primero = buildItem(id: 'item-a');
      final path = await files.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'apunte.pdf',
        id: primero.source.id,
      );
      final source = primero.source.copyWith(originalFilePath: path);

      await repository.save(primero.copyWith(source: source));
      await repository.save(buildItem(id: 'item-b').copyWith(source: source));

      await repository.delete('item-a');

      expect(files.deleted, isEmpty);
      expect(files.paths, [path]);
    });

    test('si el disco se resiste, el elemento se borra igual', () async {
      // El usuario pidió eliminar algo y en la base ya no está. Devolver un
      // error porque el archivo no se dejó borrar sería mentirle.
      final base = buildItem();
      final path = await files.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'apunte.pdf',
        id: base.source.id,
      );
      await repository.save(
        base.copyWith(source: base.source.copyWith(originalFilePath: path)),
      );
      files.deleteError = const FileSystemException('volumen desmontado');

      final result = await repository.delete(base.id);

      expect(result.isRight(), isTrue);
      expect(await db.select(db.items).get(), isEmpty);
    });

    test('un elemento sin archivo no intenta borrar nada', () async {
      final base = buildItem();
      await repository.save(base);

      await repository.delete(base.id);

      expect(files.deleted, isEmpty);
    });
  });

  group('borrar varios de una vez', () {
    test('borra los elementos pedidos y deja los demás intactos', () async {
      final a = buildItem(id: 'item-a');
      final b = buildItem(id: 'item-b');
      final c = buildItem(id: 'item-c');
      await repository.save(a);
      await repository.save(b);
      await repository.save(c);

      final result = await repository.deleteMany(['item-a', 'item-b']);

      expect(result.isRight(), isTrue);
      final remaining = await db.select(db.items).get();
      expect(remaining.map((r) => r.id), ['item-c']);
    });

    test('borra el archivo original de cada uno', () async {
      final a = buildItem(id: 'item-a');
      final pathA = await files.save(
        bytes: Uint8List.fromList([1]),
        suggestedName: 'a.pdf',
        id: a.source.id,
      );
      final b = buildItem(id: 'item-b');
      final pathB = await files.save(
        bytes: Uint8List.fromList([2]),
        suggestedName: 'b.pdf',
        id: b.source.id,
      );
      await repository.save(
        a.copyWith(source: a.source.copyWith(originalFilePath: pathA)),
      );
      await repository.save(
        b.copyWith(source: b.source.copyWith(originalFilePath: pathB)),
      );

      await repository.deleteMany(['item-a', 'item-b']);

      expect(files.deleted, unorderedEquals([pathA, pathB]));
    });

    test('un archivo compartido entre dos de los elementos borrados se borra '
        'una sola vez, no cero ni dos', () async {
      final a = buildItem(id: 'item-a');
      final path = await files.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'compartido.pdf',
        id: a.source.id,
      );
      final source = a.source.copyWith(originalFilePath: path);
      await repository.save(a.copyWith(source: source));
      await repository.save(buildItem(id: 'item-b').copyWith(source: source));

      await repository.deleteMany(['item-a', 'item-b']);

      expect(files.deleted, [path]);
    });

    test('si el disco se resiste en uno, los demás se borran igual', () async {
      final a = buildItem(id: 'item-a');
      final path = await files.save(
        bytes: Uint8List.fromList([1]),
        suggestedName: 'a.pdf',
        id: a.source.id,
      );
      await repository.save(
        a.copyWith(source: a.source.copyWith(originalFilePath: path)),
      );
      await repository.save(buildItem(id: 'item-b'));
      files.deleteError = const FileSystemException('volumen desmontado');

      final result = await repository.deleteMany(['item-a', 'item-b']);

      expect(result.isRight(), isTrue);
      expect(await db.select(db.items).get(), isEmpty);
    });
  });

  group('mover varios a un tema de una vez', () {
    Future<void> createSpace(String id, String name) => db
        .into(db.spaces)
        .insert(SpacesCompanion.insert(id: id, name: name, createdAt: now));

    test('asigna el mismo tema a todos los elementos pedidos', () async {
      await createSpace('space-1', 'Filosofía');
      final a = buildItem(id: 'item-a');
      final b = buildItem(id: 'item-b');
      final c = buildItem(id: 'item-c');
      await repository.save(a);
      await repository.save(b);
      await repository.save(c);

      final result = await repository.assignSpaceMany(
        itemIds: ['item-a', 'item-b'],
        spaceId: 'space-1',
      );

      expect(result.isRight(), isTrue);
      final foundA = (await repository.findById(
        'item-a',
      )).getRight().toNullable();
      final foundB = (await repository.findById(
        'item-b',
      )).getRight().toNullable();
      final foundC = (await repository.findById(
        'item-c',
      )).getRight().toNullable();
      expect(foundA!.spaceId, 'space-1');
      expect(foundB!.spaceId, 'space-1');
      expect(foundC!.spaceId, isNull);
    });

    test('con spaceId nulo, deja a todos sin clasificar', () async {
      await createSpace('space-1', 'Filosofía');
      final a = buildItem(id: 'item-a');
      final b = buildItem(id: 'item-b');
      await repository.save(a.copyWith(spaceId: 'space-1'));
      await repository.save(b.copyWith(spaceId: 'space-1'));

      await repository.assignSpaceMany(
        itemIds: ['item-a', 'item-b'],
        spaceId: null,
      );

      final foundA = (await repository.findById(
        'item-a',
      )).getRight().toNullable();
      final foundB = (await repository.findById(
        'item-b',
      )).getRight().toNullable();
      expect(foundA!.spaceId, isNull);
      expect(foundB!.spaceId, isNull);
    });
  });

  group('filtrar', () {
    Future<void> seed() async {
      // La categoría tiene que existir antes: `_syncProperties` solo
      // sincroniza valores y su relación con el elemento, no crea la
      // categoría — eso es trabajo de `OrganizeRepository`, ver la
      // decisión 31 en docs/arquitectura.md.
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-region',
              name: 'Región',
              createdAt: now,
            ),
          );

      final yt = buildItem(
        title: 'Charla sobre paradigmas',
        sourceKind: SourceKind.youtube,
      );
      await repository.save(
        yt.copyWith(
          renditions: [
            textRendition(yt.id, 'transcripción sobre epistemología'),
          ],
          tags: [Tag(id: 'tag-filo', name: 'filosofía', createdAt: now)],
        ),
      );

      final web = buildItem(title: 'Artículo sobre enzimas');
      await repository.save(
        web.copyWith(
          renditions: [textRendition(web.id, 'las enzimas catalizan')],
          tags: [Tag(id: 'tag-bio', name: 'biología', createdAt: now)],
        ),
      );

      final pdf = buildItem(
        title: 'Un PDF pendiente',
        sourceKind: SourceKind.document,
        state: ProcessingState.pending,
      );
      await repository.save(
        pdf.copyWith(
          tags: [
            Tag(id: 'tag-filo', name: 'filosofía', createdAt: now),
            Tag(id: 'tag-bio', name: 'biología', createdAt: now),
          ],
          properties: [
            ItemProperty(
              definitionId: 'def-region',
              definitionName: 'Región',
              valueId: 'val-roma',
              value: 'Roma',
              createdAt: now,
            ),
            ItemProperty(
              definitionId: 'def-region',
              definitionName: 'Región',
              valueId: 'val-egipto',
              value: 'Egipto',
              createdAt: now,
            ),
          ],
        ),
      );
    }

    Future<List<String>> titlesOf(LibraryQuery query) async {
      final items = (await repository.list(query)).getRight().toNullable()!;
      return items.map((i) => i.title).toList();
    }

    test('por tipo de fuente', () async {
      await seed();

      expect(
        await titlesOf(const LibraryQuery(sourceKinds: {SourceKind.youtube})),
        ['Charla sobre paradigmas'],
      );
    });

    test('dentro de un mismo filtro vale cualquiera de los valores', () async {
      await seed();

      final titles = await titlesOf(
        const LibraryQuery(
          sourceKinds: {SourceKind.youtube, SourceKind.document},
        ),
      );

      expect(titles, hasLength(2));
    });

    test(
      'por estado de procesamiento, para poder mirar solo lo que falta',
      () async {
        await seed();

        expect(
          await titlesOf(
            const LibraryQuery(processingStates: {ProcessingState.pending}),
          ),
          ['Un PDF pendiente'],
        );
      },
    );

    test('por etiqueta', () async {
      await seed();

      final titles = await titlesOf(const LibraryQuery(tagIds: {'tag-filo'}));

      expect(titles, hasLength(2));
      expect(titles, contains('Charla sobre paradigmas'));
      expect(titles, contains('Un PDF pendiente'));
    });

    test('un elemento que coincide con VARIAS de las etiquetas buscadas '
        'aparece una sola vez', () async {
      // El motivo de resolver este filtro con una subconsulta y no con un
      // join: con join, el PDF —que tiene las dos etiquetas— saldría
      // duplicado, y la lista mostraría el mismo elemento dos veces.
      await seed();

      final titles = await titlesOf(
        const LibraryQuery(tagIds: {'tag-filo', 'tag-bio'}),
      );

      expect(titles.where((t) => t == 'Un PDF pendiente'), hasLength(1));
    });

    test('por valor de propiedad', () async {
      await seed();

      final titles = await titlesOf(
        const LibraryQuery(propertyValueIds: {'val-roma'}),
      );

      expect(titles, ['Un PDF pendiente']);
    });

    test('un elemento con VARIOS de los valores buscados '
        'aparece una sola vez', () async {
      // Mismo motivo que con las etiquetas: sin subconsulta, el PDF —que
      // tiene Roma y Egipto— saldría dos veces.
      await seed();

      final titles = await titlesOf(
        const LibraryQuery(propertyValueIds: {'val-roma', 'val-egipto'}),
      );

      expect(titles.where((t) => t == 'Un PDF pendiente'), hasLength(1));
    });

    test('entre filtros distintos se tienen que cumplir todos', () async {
      await seed();

      final titles = await titlesOf(
        const LibraryQuery(
          sourceKinds: {SourceKind.document},
          tagIds: {'tag-filo'},
        ),
      );

      expect(titles, ['Un PDF pendiente']);
    });

    test('busca en el contenido, no solo en el título', () async {
      await seed();

      expect(await titlesOf(const LibraryQuery(searchText: 'catalizan')), [
        'Artículo sobre enzimas',
      ]);
    });

    test('la búsqueda se combina con los filtros', () async {
      await seed();

      expect(
        await titlesOf(
          const LibraryQuery(
            searchText: 'sobre',
            sourceKinds: {SourceKind.youtube},
          ),
        ),
        ['Charla sobre paradigmas'],
      );
    });

    test(
      'una búsqueda de solo espacios no filtra nada: no es una búsqueda',
      () async {
        // Tratarla como tal devolvería cero resultados y daría a entender que
        // la biblioteca está vacía.
        await seed();

        expect(
          await titlesOf(const LibraryQuery(searchText: '   ')),
          hasLength(3),
        );
      },
    );
  });

  group('ordenar y paginar', () {
    Future<void> seedOrdered() async {
      for (final (i, title) in ['Cero', 'Alfa', 'Beta'].indexed) {
        await repository.save(
          buildItem(
            title: title,
            capturedAt: now.add(Duration(days: i)),
          ),
        );
      }
    }

    Future<List<String>> titlesOf(LibraryQuery query) async {
      final items = (await repository.list(query)).getRight().toNullable()!;
      return items.map((i) => i.title).toList();
    }

    test('por fecha de captura, lo más nuevo primero', () async {
      await seedOrdered();

      expect(await titlesOf(const LibraryQuery()), ['Beta', 'Alfa', 'Cero']);
    });

    test('y al revés si se pide', () async {
      await seedOrdered();

      expect(await titlesOf(const LibraryQuery(descending: false)), [
        'Cero',
        'Alfa',
        'Beta',
      ]);
    });

    test('alfabético por título', () async {
      await seedOrdered();

      expect(
        await titlesOf(
          const LibraryQuery(sortBy: LibrarySort.title, descending: false),
        ),
        ['Alfa', 'Beta', 'Cero'],
      );
    });

    test('sin texto buscado, pedir orden por relevancia no rompe: cae en el '
        'orden por fecha', () async {
      await seedOrdered();

      expect(
        await titlesOf(const LibraryQuery(sortBy: LibrarySort.relevance)),
        ['Beta', 'Alfa', 'Cero'],
      );
    });

    test('con texto buscado, el orden por relevancia pone primero lo que más '
        'coincide', () async {
      final poco = buildItem(title: 'Mención aislada de enzimas');
      await repository.save(poco);
      final mucho = buildItem(title: 'Enzimas');
      await repository.save(
        mucho.copyWith(
          renditions: [
            textRendition(mucho.id, 'enzimas, enzimas y más enzimas'),
          ],
        ),
      );

      final titles = await titlesOf(
        const LibraryQuery(
          searchText: 'enzimas',
          sortBy: LibrarySort.relevance,
        ),
      );

      expect(titles.first, 'Enzimas');
      expect(titles, hasLength(2));
    });

    test('pagina', () async {
      await seedOrdered();

      expect(await titlesOf(const LibraryQuery(limit: 2)), ['Beta', 'Alfa']);
      expect(await titlesOf(const LibraryQuery(limit: 2, offset: 2)), ['Cero']);
    });

    test('contar devuelve el total, no el tamaño de la página', () async {
      await seedOrdered();

      final total = (await repository.count(
        const LibraryQuery(limit: 1),
      )).getRight().toNullable();

      expect(total, 3);
    });

    test('contar respeta los filtros', () async {
      await seedOrdered();
      await repository.save(
        buildItem(title: 'Un video', sourceKind: SourceKind.youtube),
      );

      final total = (await repository.count(
        const LibraryQuery(sourceKinds: {SourceKind.youtube}),
      )).getRight().toNullable();

      expect(total, 1);
    });
  });

  group('observar cambios', () {
    // Se usa `StreamQueue` y no `pumpEventQueue` ni `emitsInOrder` a secas.
    //
    // El stream de `watch` no termina nunca —esa es su función—, así que
    // esperar a que la cola de eventos se vacíe cuelga el test. Y la primera
    // emisión es asíncrona (hay una consulta de por medio), de modo que
    // suscribirse y escribir en la línea siguiente es una carrera: la
    // escritura puede llegar antes de que salga la emisión inicial, y
    // entonces esa primera emisión ya trae el cambio.
    //
    // Para la aplicación eso da igual —el stream converge al estado
    // correcto— pero un test tiene que ser determinista. `StreamQueue`
    // permite decir exactamente lo que se quiere: esperá la primera, recién
    // entonces escribí, después esperá la siguiente.

    test(
      'vuelve a emitir cuando algo se guarda, sin que nadie pregunte',
      () async {
        // Es lo que permite que una pantalla abierta se actualice sola cuando
        // una transcripción termina en segundo plano.
        final queue = StreamQueue(repository.watch(const LibraryQuery()));
        addTearDown(queue.cancel);

        expect(await queue.next, isEmpty);

        await repository.save(buildItem(title: 'Recién llegado'));

        expect(await queue.next, hasLength(1));
      },
    );

    test('también cuando algo se borra', () async {
      final item = buildItem();
      await repository.save(item);

      final queue = StreamQueue(repository.watch(const LibraryQuery()));
      addTearDown(queue.cancel);

      expect(await queue.next, hasLength(1));

      await repository.delete(item.id);

      expect(await queue.next, isEmpty);
    });

    test('lo que emite respeta los filtros de la consulta', () async {
      final queue = StreamQueue(
        repository.watch(const LibraryQuery(sourceKinds: {SourceKind.youtube})),
      );
      addTearDown(queue.cancel);

      expect(await queue.next, isEmpty);

      // Un elemento que no cumple el filtro igual provoca una emisión —el
      // stream reacciona a cualquier escritura— pero su contenido tiene que
      // seguir vacío.
      await repository.save(buildItem(title: 'Un artículo'));
      expect(await queue.next, isEmpty);

      await repository.save(
        buildItem(title: 'Un video', sourceKind: SourceKind.youtube),
      );
      expect(await queue.next, hasLength(1));
    });
  });

  group('espejo del modelo nuevo', () {
    test(
      'guardar una fuente crea su entrada y su fuente en el espejo',
      () async {
        final item = buildItem();

        await repository.save(item);

        final entry = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals(item.id))).getSingle();
        expect(entry.kind, ItemKind.source);
        expect(entry.state, ItemState.processed);
        expect(entry.title, item.title);

        final source = await (db.select(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals(item.id))).getSingle();
        expect(source.sourceType, item.source.kind);
        expect(source.originUrl, item.source.url);
        expect(source.authorName, item.source.authorName);
        expect(source.fullText, isEmpty);
        expect(source.contentHash, isEmpty);
      },
    );

    test('guardar una nota crea su entrada y su nota en el espejo', () async {
      final item = buildItem(sourceKind: SourceKind.manualNote);

      await repository.save(item);

      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingle();
      expect(entry.kind, ItemKind.note);

      final note = await (db.select(
        db.knowledgeNotes,
      )..where((n) => n.itemId.equals(item.id))).getSingle();
      expect(note.noteKind, NoteKind.living);
      expect(note.maturity, NoteMaturity.seed);
    });

    test('editar un elemento ya triado no lo devuelve a processed', () async {
      final item = buildItem();
      await repository.save(item);

      // Simula lo que hará `InboxRepository.transitionState`.
      await (db.update(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).write(
        const KnowledgeEntriesCompanion(state: Value(ItemState.triaged)),
      );

      await repository.save(item.copyWith(title: 'Título editado'));

      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingle();
      expect(entry.state, ItemState.triaged);
      expect(entry.title, 'Título editado');
    });

    test('el estado avanza de captured a processed cuando el pipeline '
        'termina', () async {
      final item = buildItem(state: ProcessingState.pending);
      await repository.save(item);

      final captured = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingle();
      expect(captured.state, ItemState.captured);

      await repository.save(
        item.copyWith(processingState: ProcessingState.ready),
      );

      final processed = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingle();
      expect(processed.state, ItemState.processed);
    });

    test('fullText/contentHash puestos a mano sobreviven a una edición '
        'posterior', () async {
      final item = buildItem();
      await repository.save(item);

      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).write(
        const KnowledgeSourcesCompanion(
          fullText: Value('El texto íntegro de la fuente.'),
          contentHash: Value('hash-simulado'),
        ),
      );

      await repository.save(item.copyWith(title: 'Otro título'));

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).getSingle();
      expect(source.fullText, 'El texto íntegro de la fuente.');
      expect(source.contentHash, 'hash-simulado');
    });

    test(
      'borrar un elemento borra su entrada, y en cascada su fuente',
      () async {
        final item = buildItem();
        await repository.save(item);

        await repository.delete(item.id);

        final entry = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals(item.id))).getSingleOrNull();
        final source = await (db.select(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals(item.id))).getSingleOrNull();
        expect(entry, isNull);
        expect(source, isNull);
      },
    );

    test('borrar varios de una vez borra el espejo de todos', () async {
      final a = buildItem();
      final b = buildItem();
      await repository.save(a);
      await repository.save(b);

      await repository.deleteMany([a.id, b.id]);

      final remaining = await db.select(db.knowledgeEntries).get();
      expect(remaining, isEmpty);
    });
  });

  group('propiedades', () {
    Future<String> seedDefinition(String name) async {
      final id = 'def-${counter++}';
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: id,
              name: name,
              createdAt: now,
            ),
          );
      return id;
    }

    test('el origin manual (el default) persiste y se lee igual', () async {
      final definitionId = await seedDefinition('Región');
      final item = buildItem().copyWith(
        properties: [
          ItemProperty(
            definitionId: definitionId,
            definitionName: 'Región',
            valueId: 'val-${counter++}',
            value: 'Roma',
            createdAt: now,
          ),
        ],
      );

      await repository.save(item);

      final found = (await repository.findById(
        item.id,
      )).getRight().toNullable()!;
      expect(found.properties.single.origin, ItemPropertyOrigin.manual);
    });

    test('el origin sobrevive a una edición posterior que no toca las '
        'propiedades', () async {
      final definitionId = await seedDefinition('Región');
      final item = buildItem().copyWith(
        properties: [
          ItemProperty(
            definitionId: definitionId,
            definitionName: 'Región',
            valueId: 'val-${counter++}',
            value: 'Roma',
            createdAt: now,
            origin: ItemPropertyOrigin.inherited,
          ),
        ],
      );
      await repository.save(item);

      final loaded = (await repository.findById(
        item.id,
      )).getRight().toNullable()!;
      await repository.save(loaded.copyWith(title: 'Título editado'));

      final reloaded = (await repository.findById(
        item.id,
      )).getRight().toNullable()!;
      expect(reloaded.properties.single.origin, ItemPropertyOrigin.inherited);
      expect(reloaded.title, 'Título editado');
    });
  });

  group('deduplicación (F7)', () {
    test('guardar una nota nueva dispara el generador de duplicados', () async {
      final generator = FakeDuplicateSuggestionGenerator();
      final withGenerator = LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: files,
        duplicateSuggestionGenerator: generator,
      );
      final note = buildItem(sourceKind: SourceKind.manualNote);

      await withGenerator.save(note);

      expect(generator.calls, [note.id]);
    });

    test(
      'editarla de nuevo también lo dispara, no solo la primera vez',
      () async {
        final generator = FakeDuplicateSuggestionGenerator();
        final withGenerator = LibraryRepositoryImpl(
          database: db,
          telemetry: MockTelemetryService(),
          files: files,
          duplicateSuggestionGenerator: generator,
        );
        final note = buildItem(sourceKind: SourceKind.manualNote);
        await withGenerator.save(note);

        await withGenerator.save(note.copyWith(title: 'Título editado'));

        expect(generator.calls, [note.id, note.id]);
      },
    );

    test('guardar una fuente no dispara nada: esa es responsabilidad de '
        'ProcessItemUseCase, no de este hook', () async {
      final generator = FakeDuplicateSuggestionGenerator();
      final withGenerator = LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: files,
        duplicateSuggestionGenerator: generator,
      );
      final source = buildItem();

      await withGenerator.save(source);

      expect(generator.calls, isEmpty);
    });

    test(
      'sin ningún generador configurado, guardar una nota no revienta',
      () async {
        final note = buildItem(sourceKind: SourceKind.manualNote);

        final result = await repository.save(note);

        expect(result.isRight(), isTrue);
      },
    );
  });

  group('enlaces en línea (F9)', () {
    /// Una forma de bloques: un párrafo por cada texto.
    Rendition blocksRendition(
      String itemId,
      List<String> paragraphs, {
      String? id,
    }) => Rendition.text(
      id: id ?? 'blocks-$itemId',
      itemId: itemId,
      kind: RenditionKind.blocks,
      content: encodeContentBlocks([
        for (final text in paragraphs) ContentBlock.paragraph(text: text),
      ]),
      isPrimary: true,
      createdAt: now,
    );

    KnowledgeItem blocksNote(
      String title,
      List<String> paragraphs, {
      String? id,
    }) {
      final base = buildItem(
        id: id,
        title: title,
        sourceKind: SourceKind.manualNote,
      );
      return base.copyWith(renditions: [blocksRendition(base.id, paragraphs)]);
    }

    Future<Set<(String, String?)>> linksOf(String itemId) async => {
      for (final link in await (db.select(
        db.inlineLinks,
      )..where((l) => l.fromItemId.equals(itemId))).get())
        (link.normalizedTitle, link.toItemId),
    };

    Future<Set<(String, String)>> relatedTo() async => {
      for (final relation in await db.select(db.relations).get())
        (relation.fromItemId, relation.toItemId),
    };

    test('guardar una nota que enlaza a un elemento existente la vincula en '
        'el mismo guardado', () async {
      await repository.save(buildItem(id: 'roma', title: 'Roma'));

      await repository.save(blocksNote('Viaje', ['Fui a [[Roma]].'], id: 'n1'));

      expect(await linksOf('n1'), {('roma', 'roma')});
      expect(await relatedTo(), {('n1', 'roma')});
    });

    test('un enlace a algo que no existe queda roto, y crear ese elemento '
        'después lo resuelve', () async {
      await repository.save(blocksNote('Viaje', ['[[Cartago]]'], id: 'n1'));
      expect(await linksOf('n1'), {('cartago', null)});
      expect(await relatedTo(), isEmpty);

      await repository.save(buildItem(id: 'cartago', title: 'Cartago'));

      expect(await linksOf('n1'), {('cartago', 'cartago')});
      expect(await relatedTo(), {('n1', 'cartago')});
    });

    test('renombrar un elemento resuelve los enlaces que esperaban ese '
        'nombre', () async {
      await repository.save(blocksNote('Viaje', ['[[Atenas]]'], id: 'n1'));
      final algo = buildItem(id: 'x', title: 'Algo');
      await repository.save(algo);
      expect(await linksOf('n1'), {('atenas', null)});

      await repository.save(algo.copyWith(title: 'Atenas'));

      expect(await linksOf('n1'), {('atenas', 'x')});
    });

    test('editar la nota y quitar el enlace lo borra del registro', () async {
      await repository.save(buildItem(id: 'roma', title: 'Roma'));
      final note = blocksNote('Viaje', ['[[Roma]]'], id: 'n1');
      await repository.save(note);

      await repository.save(
        note.copyWith(
          renditions: [
            blocksRendition('n1', ['Sin enlaces.']),
          ],
        ),
      );

      expect(await linksOf('n1'), isEmpty);
    });

    test('los enlaces de todas las formas de bloques del elemento cuentan, '
        'no solo los de la primera', () async {
      final base = blocksNote('Viaje', ['[[Roma]]'], id: 'n1');

      await repository.save(
        base.copyWith(
          renditions: [
            blocksRendition('n1', ['[[Roma]]'], id: 'blocks-a'),
            blocksRendition('n1', ['[[Cartago]]'], id: 'blocks-b'),
          ],
        ),
      );

      expect(await linksOf('n1'), {('roma', null), ('cartago', null)});
    });

    test('un texto con [[ ]] que no es una nota de bloques no registra '
        'enlaces', () async {
      final item = buildItem(id: 'n1', title: 'Un artículo');
      await repository.save(
        item.copyWith(
          renditions: [textRendition(item.id, 'Habla de [[Roma]] a secas.')],
        ),
      );

      expect(await db.select(db.inlineLinks).get(), isEmpty);
    });

    test('bloques ilegibles no impiden guardar: se informa y los enlaces '
        'registrados quedan como estaban', () async {
      final telemetry = MockTelemetryService();
      final repo = LibraryRepositoryImpl(
        database: db,
        telemetry: telemetry,
        files: files,
      );
      await repo.save(buildItem(id: 'roma', title: 'Roma'));
      final note = blocksNote('Viaje', ['[[Roma]]'], id: 'n1');
      await repo.save(note);

      final result = await repo.save(
        note.copyWith(
          title: 'Viaje editado',
          renditions: [
            Rendition.text(
              id: 'blocks-n1',
              itemId: 'n1',
              kind: RenditionKind.blocks,
              content: 'esto no es json',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

      expect(result.isRight(), isTrue);
      final saved = (await repo.findById('n1')).getRight().toNullable()!;
      expect(saved.title, 'Viaje editado');
      expect(await linksOf('n1'), {('roma', 'roma')});
      verify(
        () => telemetry.recordError(
          any<dynamic>(),
          any(),
          hint: 'LibraryRepositoryImpl.save',
        ),
      ).called(1);
    });

    test('borrar el destino deja el enlace roto; borrar la nota se lleva '
        'sus enlaces', () async {
      await repository.save(buildItem(id: 'roma', title: 'Roma'));
      await repository.save(blocksNote('Viaje', ['[[Roma]]'], id: 'n1'));

      await repository.delete('roma');
      expect(await linksOf('n1'), {('roma', null)});

      await repository.delete('n1');
      expect(await db.select(db.inlineLinks).get(), isEmpty);
    });
  });
}
