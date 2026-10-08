import 'dart:io';

import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/bulk_writer_holder.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_property.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/domain/entities/timed_word.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_repository_impl.dart';

import '../../../../support/fake_duplicate_suggestion_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

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

    test('una transcripción vuelve con el momento de cada palabra, y sin '
        'ellos si no se midieron (F23)', () async {
      final base = buildItem();
      const timings = [TimedWord('Hola', 0), TimedWord('mundo.', 420)];
      await repository.save(
        base.copyWith(
          renditions: [
            (textRendition(base.id, '[0:00] Hola mundo.') as TextRendition)
                .copyWith(wordTimings: timings),
            textRendition(base.id, 'Sin tiempos', id: 'otra', isPrimary: false),
          ],
        ),
      );

      final found = (await repository.findById(
        base.id,
      )).getRight().toNullable()!;
      final texts = found.renditions.cast<TextRendition>();
      expect(texts.firstWhere((r) => r.id != 'otra').wordTimings, timings);
      expect(texts.firstWhere((r) => r.id == 'otra').wordTimings, isEmpty);
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

    test('el guardado es atómico: si algo falla al final, no queda nada a '
        'medias', () async {
      final base = buildItem();
      final failing = base.copyWith(
        renditions: [
          Rendition.text(
            id: 'r1',
            itemId: base.id,
            kind: RenditionKind.plainText,
            content: 'texto',
            isPrimary: true,
            createdAt: now,
          ),
        ],
        // El último paso del guardado: una propiedad de una categoría que no
        // existe viola la clave foránea DESPUÉS de haber escrito el elemento,
        // su fuente y su forma.
        properties: [
          ItemProperty(
            definitionId: 'categoria-que-no-existe',
            definitionName: 'X',
            valueId: 'valor-1',
            value: 'un valor',
            createdAt: now,
          ),
        ],
      );

      final result = await repository.save(failing);

      expect(result.isLeft(), isTrue);
      // La transacción tiene que haber deshecho todo lo anterior.
      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
      expect(await db.select(db.knowledgeSources).get(), isEmpty);
      expect(await db.select(db.renditions).get(), isEmpty);
    });
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

  group('borrar: la papelera (F11)', () {
    Future<KnowledgeEntryRow> entryOf(String id) => (db.select(
      db.knowledgeEntries,
    )..where((e) => e.id.equals(id))).getSingle();

    test(
      'manda el elemento a la papelera y no borra nada de lo que tiene',
      () async {
        final base = buildItem();
        await repository.save(
          base.copyWith(
            renditions: [textRendition(base.id, 'contenido')],
            tags: [Tag(id: 'tag-1', name: 'algo', createdAt: now)],
          ),
        );

        final result = await repository.delete(base.id);

        expect(result.isRight(), isTrue);
        expect((await entryOf(base.id)).deletedAt, isNotNull);
        // Lo que colgaba de él sigue ahí: se restaura entero.
        expect(await db.select(db.renditions).get(), hasLength(1));
        expect(await db.select(db.itemPropertyValues).get(), hasLength(1));
        expect(await db.select(db.knowledgeSources).get(), hasLength(1));
        expect(await temaValues(), hasLength(1));
      },
    );

    test('el archivo original no se toca: sigue ahí hasta que se borre para '
        'siempre', () async {
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

      expect(files.deleted, isEmpty);
      expect(files.paths, [path]);
    });

    test('borrar algo que no existe no es un error', () async {
      expect((await repository.delete('no-existe')).isRight(), isTrue);
    });

    test('borrarlo otra vez no cambia cuándo se borró', () async {
      final base = buildItem();
      await repository.save(base);
      await repository.delete(base.id);
      final first = (await entryOf(base.id)).deletedAt;

      await repository.delete(base.id);

      expect((await entryOf(base.id)).deletedAt, first);
      expect((await entryOf(base.id)).rev, 2);
    });
  });

  group('borrar varios de una vez', () {
    test('manda a la papelera los pedidos y deja los demás intactos', () async {
      final a = buildItem(id: 'item-a');
      final b = buildItem(id: 'item-b');
      final c = buildItem(id: 'item-c');
      await repository.save(a);
      await repository.save(b);
      await repository.save(c);

      final result = await repository.deleteMany(['item-a', 'item-b']);

      expect(result.isRight(), isTrue);
      final rows = await db.select(db.knowledgeEntries).get();
      expect(rows, hasLength(3));
      expect(
        {
          for (final r in rows)
            if (r.deletedAt != null) r.id,
        },
        {'item-a', 'item-b'},
      );
    });

    test('con una lista vacía no hace nada', () async {
      final a = buildItem(id: 'item-a');
      await repository.save(a);

      final result = await repository.deleteMany(const []);

      expect(result.isRight(), isTrue);
      expect(
        (await db.select(db.knowledgeEntries).getSingle()).deletedAt,
        isNull,
      );
    });
  });

  group('restaurar (F11)', () {
    test('el elemento vuelve a la biblioteca tal cual estaba', () async {
      final base = buildItem(title: 'Roma');
      await repository.save(
        base.copyWith(renditions: [textRendition(base.id, 'contenido')]),
      );
      await repository.delete(base.id);

      final result = await repository.restore(base.id);

      expect(result.isRight(), isTrue);
      final found = (await repository.findById(
        base.id,
      )).getRight().toNullable();
      expect(found?.title, 'Roma');
      expect(found?.renditions, hasLength(1));
    });

    test(
      'varios a la vez, y lo que no estaba en la papelera se ignora',
      () async {
        final a = buildItem(id: 'item-a');
        final b = buildItem(id: 'item-b');
        final c = buildItem(id: 'item-c');
        for (final item in [a, b, c]) {
          await repository.save(item);
        }
        await repository.deleteMany(['item-a', 'item-b']);

        final result = await repository.restoreMany([
          'item-a',
          'item-b',
          'item-c',
          'no-existe',
        ]);

        expect(result.isRight(), isTrue);
        final rows = await db.select(db.knowledgeEntries).get();
        expect(rows.every((r) => r.deletedAt == null), isTrue);
      },
    );

    test(
      'un [[título]] que esperaba al elemento se resuelve al volver',
      () async {
        await repository.save(buildItem(id: 'roma', title: 'Roma'));
        await repository.save(blocksNote('Viaje', ['[[Roma]]'], id: 'n1'));
        await repository.delete('roma');
        // Con el destino en la papelera, otra nota que lo nombra queda rota.
        await repository.save(blocksNote('Diario', ['[[Roma]]'], id: 'n2'));
        expect(await linksOf('n2'), {('roma', null)});

        await repository.restore('roma');

        expect(await linksOf('n2'), {('roma', 'roma')});
      },
    );
  });

  group('borrar para siempre (F11)', () {
    Future<int> entries() async =>
        (await db.select(db.knowledgeEntries).get()).length;

    test('borra el elemento que ya estaba en la papelera y todo lo que cuelga '
        'de él', () async {
      final base = buildItem();
      await repository.save(
        base.copyWith(
          renditions: [textRendition(base.id, 'contenido')],
          tags: [Tag(id: 'tag-1', name: 'algo', createdAt: now)],
        ),
      );
      await repository.delete(base.id);

      final result = await repository.purge([base.id]);

      expect(result.isRight(), isTrue);
      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
      expect(await db.select(db.renditions).get(), isEmpty);
      expect(await db.select(db.itemPropertyValues).get(), isEmpty);
      // La etiqueta en sí sobrevive: puede estar en uso por otros elementos,
      // y aunque no lo esté, es parte del vocabulario del usuario.
      expect(await temaValues(), hasLength(1));
    });

    test('lo que sigue vivo no se borra: no hay atajo', () async {
      final base = buildItem();
      await repository.save(base);

      final result = await repository.purge([base.id]);

      expect(result.isRight(), isTrue);
      expect(await entries(), 1);
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

      await repository.purge([base.id]);

      expect(files.deleted, [path]);
      expect(files.paths, isEmpty);
    });

    test('el archivo de algo que sigue vivo no se borra: aunque otro elemento '
        'que lo compartía sí', () async {
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

      await repository.purge(['item-a']);

      expect(files.deleted, isEmpty);
      expect(files.paths, [path]);
    });

    test('ni el de algo que sigue en la papelera: todavía se puede '
        'restaurar', () async {
      final primero = buildItem(id: 'item-a');
      final path = await files.save(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedName: 'apunte.pdf',
        id: primero.source.id,
      );
      final source = primero.source.copyWith(originalFilePath: path);
      await repository.save(primero.copyWith(source: source));
      await repository.save(buildItem(id: 'item-b').copyWith(source: source));
      await repository.deleteMany(['item-a', 'item-b']);

      await repository.purge(['item-a']);

      expect(files.deleted, isEmpty);
    });

    test('un archivo compartido entre dos de los borrados para siempre se '
        'borra una sola vez, no cero ni dos', () async {
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

      await repository.purge(['item-a', 'item-b']);

      expect(files.deleted, [path]);
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
      await repository.delete(base.id);
      files.deleteError = const FileSystemException('volumen desmontado');

      final result = await repository.purge([base.id]);

      expect(result.isRight(), isTrue);
      expect(await entries(), 0);
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
      await repository.deleteMany(['item-a', 'item-b']);
      files.deleteError = const FileSystemException('volumen desmontado');

      final result = await repository.purge(['item-a', 'item-b']);

      expect(result.isRight(), isTrue);
      expect(await entries(), 0);
    });

    test('un elemento sin archivo no intenta borrar nada', () async {
      final base = buildItem();
      await repository.save(base);
      await repository.delete(base.id);

      await repository.purge([base.id]);

      expect(files.deleted, isEmpty);
    });

    test(
      'vaciar la papelera borra todo lo que hay en ella y nada más',
      () async {
        final a = buildItem(id: 'item-a');
        final b = buildItem(id: 'item-b');
        final c = buildItem(id: 'item-c');
        final path = await files.save(
          bytes: Uint8List.fromList([1]),
          suggestedName: 'a.pdf',
          id: a.source.id,
        );
        await repository.save(
          a.copyWith(source: a.source.copyWith(originalFilePath: path)),
        );
        await repository.save(b);
        await repository.save(c);
        await repository.deleteMany(['item-a', 'item-b']);

        final result = await repository.emptyTrash();

        expect(result.isRight(), isTrue);
        expect((await db.select(db.knowledgeEntries).get()).map((r) => r.id), [
          'item-c',
        ]);
        expect(files.deleted, [path]);
      },
    );

    test('vaciar una papelera vacía no es un error', () async {
      expect((await repository.emptyTrash()).isRight(), isTrue);
    });
  });

  group('lo que hay en la papelera (F11)', () {
    test('se lista del más reciente al más viejo, con su tipo', () async {
      var at = DateTime(2026, 9, 20, 9);
      final clocked = LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: files,
        clock: () => at = at.add(const Duration(minutes: 1)),
      );
      final a = buildItem(id: 'item-a', title: 'Primero');
      final b = buildItem(id: 'item-b', title: 'Segundo');
      final nota = blocksNote('Una nota', ['texto'], id: 'nota');
      for (final item in [a, b, nota]) {
        await clocked.save(item);
      }
      await clocked.delete('item-a');
      await clocked.delete('nota');
      await clocked.delete('item-b');

      final trash = await clocked.watchTrash().first;

      expect(trash.map((t) => t.title), ['Segundo', 'Una nota', 'Primero']);
      expect(trash.map((t) => t.sourceKind), [
        SourceKind.webPage,
        SourceKind.manualNote,
        SourceKind.webPage,
      ]);
      expect(trash.first.deletedAt.isAfter(trash.last.deletedAt), isTrue);
    });

    test(
      'lo vivo no está, y una papelera vacía emite una lista vacía',
      () async {
        await repository.save(buildItem());

        expect(await repository.watchTrash().first, isEmpty);
      },
    );

    test(
      'emite de nuevo cuando algo entra, sale o se borra para siempre',
      () async {
        final a = buildItem(id: 'item-a');
        await repository.save(a);
        final queue = StreamQueue(repository.watchTrash());
        addTearDown(queue.cancel);
        expect(await queue.next, isEmpty);

        await repository.delete('item-a');
        var latest = await queue.next;
        while (latest.isEmpty) {
          latest = await queue.next.timeout(const Duration(seconds: 5));
        }
        expect(latest.single.id, 'item-a');

        await repository.restore('item-a');
        latest = await queue.next;
        while (latest.isNotEmpty) {
          latest = await queue.next.timeout(const Duration(seconds: 5));
        }

        await repository.delete('item-a');
        latest = await queue.next;
        while (latest.isEmpty) {
          latest = await queue.next.timeout(const Duration(seconds: 5));
        }
        await repository.purge(['item-a']);
        latest = await queue.next;
        while (latest.isNotEmpty) {
          latest = await queue.next.timeout(const Duration(seconds: 5));
        }
      },
    );
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

    group('limitar a ciertos elementos', () {
      Future<Map<String, String>> idsByTitle() async {
        final items = (await repository.list(
          const LibraryQuery(),
        )).getRight().toNullable()!;
        return {for (final item in items) item.title: item.id};
      }

      test('deja pasar solo a los elementos pedidos', () async {
        await seed();
        final ids = await idsByTitle();

        final titles = await titlesOf(
          LibraryQuery(
            ids: {ids['Charla sobre paradigmas']!, ids['Un PDF pendiente']!},
            sortBy: LibrarySort.title,
            descending: false,
          ),
        );

        expect(titles, ['Charla sobre paradigmas', 'Un PDF pendiente']);
      });

      test('un conjunto vacío no deja pasar nada, y no es lo mismo que no '
          'pedir ninguno', () async {
        await seed();

        expect(await titlesOf(const LibraryQuery(ids: {})), isEmpty);
        expect(await titlesOf(const LibraryQuery()), hasLength(3));
        expect(
          (await repository.count(
            const LibraryQuery(ids: {}),
          )).getRight().toNullable(),
          0,
        );
      });

      test('un id que no existe no aparece ni rompe', () async {
        await seed();
        final ids = await idsByTitle();

        final titles = await titlesOf(
          LibraryQuery(ids: {ids['Artículo sobre enzimas']!, 'no-existe'}),
        );

        expect(titles, ['Artículo sobre enzimas']);
      });

      test('se combina con los demás filtros', () async {
        await seed();
        final ids = await idsByTitle();

        final titles = await titlesOf(
          LibraryQuery(
            ids: {ids['Charla sobre paradigmas']!, ids['Un PDF pendiente']!},
            sourceKinds: const {SourceKind.document},
          ),
        );

        expect(titles, ['Un PDF pendiente']);
      });
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

  group('filtrar por lo decidido en la Bandeja (F28)', () {
    /// Una fuente lista —llega a la Bandeja— que después se pasa a [state],
    /// por el mismo escritor que usa la Bandeja.
    Future<void> seedSource(String title, [ItemState? state]) async {
      final item = buildItem(title: title);
      await repository.save(item);
      if (state != null) {
        await KnowledgeEntryWriter(db).setState(item.id, state);
      }
    }

    Future<List<String>> titlesOf(Set<InboxStatus> statuses) async {
      final items = (await repository.list(
        LibraryQuery(
          inboxStatuses: statuses,
          sortBy: LibrarySort.title,
          descending: false,
        ),
      )).getRight().toNullable()!;
      return items.map((i) => i.title).toList();
    }

    Future<void> seed() async {
      await seedSource('Por revisar');
      await seedSource('Triada', ItemState.triaged);
      await seedSource('Destilada', ItemState.distilled);
      await seedSource('Descartada', ItemState.discarded);
      // Una nota también queda `processed`, pero nunca esperó en la
      // Bandeja.
      await repository.save(
        buildItem(title: 'Una nota', sourceKind: SourceKind.manualNote),
      );
    }

    test('por revisar es lo que espera en la Bandeja, sin las notas', () async {
      await seed();

      expect(await titlesOf({InboxStatus.pending}), ['Por revisar']);
    });

    test('triado incluye lo destilado', () async {
      await seed();

      expect(await titlesOf({InboxStatus.triaged}), ['Destilada', 'Triada']);
    });

    test('descartado sigue en la Biblioteca, y se encuentra', () async {
      await seed();

      expect(await titlesOf({InboxStatus.discarded}), ['Descartada']);
    });

    test(
      'dentro del filtro vale cualquiera, y cuenta igual que lista',
      () async {
        await seed();
        const query = LibraryQuery(
          inboxStatuses: {InboxStatus.triaged, InboxStatus.discarded},
        );

        expect(await titlesOf(query.inboxStatuses), [
          'Descartada',
          'Destilada',
          'Triada',
        ]);
        expect((await repository.count(query)).getRight().toNullable(), 3);
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

    /// Siete elementos que mencionan "enzimas" una cantidad distinta de
    /// veces, para que la relevancia los ordene sin empates.
    Future<void> seedEnzymes() async {
      for (var i = 1; i <= 7; i++) {
        final item = buildItem(title: 'Nota $i');
        await repository.save(
          item.copyWith(
            renditions: [
              textRendition(item.id, List.filled(i, 'enzimas').join(' y ')),
            ],
          ),
        );
      }
    }

    test('con texto buscado, las páginas juntas dan la lista entera en el '
        'orden de relevancia', () async {
      await seedEnzymes();
      const search = LibraryQuery(
        searchText: 'enzimas',
        sortBy: LibrarySort.relevance,
      );

      final whole = await titlesOf(search);
      final pages = [
        for (var offset = 0; offset < 7; offset += 3)
          ...await titlesOf(search.copyWith(limit: 3, offset: offset)),
      ];

      expect(whole, hasLength(7));
      expect(pages, whole);
    });

    test('con texto buscado, contar da todas las coincidencias y no el '
        'tamaño de la página', () async {
      await seedEnzymes();
      await repository.save(buildItem(title: 'Otro tema'));

      final total = (await repository.count(
        const LibraryQuery(searchText: 'enzimas', limit: 2),
      )).getRight().toNullable();

      expect(total, 7);
    });

    test('con texto buscado, los identificadores de todo lo que coincide '
        'salen sin paginar', () async {
      await seedEnzymes();

      final ids = (await repository.matchingIds(
        const LibraryQuery(searchText: 'enzimas'),
      )).getRight().toNullable();

      expect(ids, hasLength(7));
    });

    test('con texto buscado se puede ordenar por otra cosa que la '
        'relevancia', () async {
      await seedEnzymes();

      expect(
        await titlesOf(
          const LibraryQuery(
            searchText: 'enzimas',
            sortBy: LibrarySort.title,
            descending: false,
            limit: 3,
          ),
        ),
        ['Nota 1', 'Nota 2', 'Nota 3'],
      );
    });

    test('un texto sin ninguna palabra que buscar no encuentra nada, ni '
        'cuenta nada, ni rompe', () async {
      await seedEnzymes();
      const query = LibraryQuery(searchText: '"');

      expect(await titlesOf(query), isEmpty);
      expect((await repository.count(query)).getRight().toNullable(), 0);
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

    test('los identificadores son los mismos que los de la lista, en el '
        'mismo orden', () async {
      await seedOrdered();
      const query = LibraryQuery(sortBy: LibrarySort.title, descending: false);

      final ids = (await repository.matchingIds(query)).getRight().toNullable();
      final listed = (await repository.list(
        query,
      )).getRight().toNullable()!.map((item) => item.id).toList();

      expect(ids, hasLength(3));
      expect(ids, listed);
    });

    test('los identificadores respetan los filtros y la página', () async {
      await seedOrdered();
      final video = buildItem(
        title: 'Un video',
        sourceKind: SourceKind.youtube,
      );
      await repository.save(video);

      final filtered = (await repository.matchingIds(
        const LibraryQuery(sourceKinds: {SourceKind.youtube}),
      )).getRight().toNullable();
      final page = (await repository.matchingIds(
        const LibraryQuery(limit: 2),
      )).getRight().toNullable();

      expect(filtered, [video.id]);
      expect(page, hasLength(2));
    });
  });

  // Una lista se vuelve a armar con cada escritura —procesar, organizar con la
  // IA—: traerle a cada elemento sus libros enteros eran cientos de MB para
  // mostrar títulos. Lo que necesita el texto lo pide completo.
  group('listas sin texto, elementos completos', () {
    late String bookId;

    setUp(() async {
      final book = buildItem(title: 'Un libro largo', id: 'libro');
      bookId = book.id;
      await repository.save(
        book.copyWith(
          renditions: [
            textRendition(book.id, 'Capítulo uno. ' * 50, id: 'texto-libro'),
            Rendition.file(
              id: 'pagina-libro',
              itemId: book.id,
              kind: RenditionKind.html,
              relativePath: 'originales/libro/pagina.html',
              isPrimary: false,
              createdAt: now,
            ),
          ],
        ),
      );
    });

    test('mirar una lista no trae el texto, pero sí los archivos', () async {
      final items = await repository.watch(const LibraryQuery()).first;

      final book = items.single;
      expect(book.renditions.whereType<TextRendition>(), isEmpty);
      expect(book.renditions.map((r) => r.id), ['pagina-libro']);
      expect(book.title, 'Un libro largo');
    });

    test('buscar por título tampoco trae el texto', () async {
      final hits = await repository
          .watchSearch(const LibraryQuery(searchText: 'libro'))
          .first;

      expect(hits.single.item.id, bookId);
      expect(hits.single.item.renditions.whereType<TextRendition>(), isEmpty);
    });

    test('«list» trae el texto, salvo que se pida sin él', () async {
      final full = (await repository.list(
        const LibraryQuery(),
      )).getRight().toNullable()!;
      final light = (await repository.list(
        const LibraryQuery(),
        withText: false,
      )).getRight().toNullable()!;

      expect(
        full.single.renditions.whereType<TextRendition>().single.content,
        startsWith('Capítulo uno.'),
      );
      expect(light.single.renditions.whereType<TextRendition>(), isEmpty);
    });

    test('«findAllById» trae los elementos completos, en el orden pedido, y '
        'sin los que no existen', () async {
      await repository.save(buildItem(title: 'Otro', id: 'otro'));

      final items = (await repository.findAllById([
        'otro',
        'no-existe',
        bookId,
      ])).getRight().toNullable()!;

      expect(items.map((i) => i.id), ['otro', bookId]);
      expect(
        items.last.renditions.whereType<TextRendition>().single.content,
        startsWith('Capítulo uno.'),
      );
    });

    test('«findById» y «watchById» siguen trayendo el texto', () async {
      expect(
        (await repository.findById(
          bookId,
        )).getRight().toNullable()!.renditions.whereType<TextRendition>(),
        isNotEmpty,
      );
      expect(
        (await repository.watchById(bookId).first)!.renditions
            .whereType<TextRendition>(),
        isNotEmpty,
      );
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

    test('el contentHash puesto por el chunking sobrevive a una edición '
        'posterior', () async {
      final item = buildItem();
      await repository.save(item);

      await (db.update(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).write(
        const KnowledgeSourcesCompanion(contentHash: Value('hash-simulado')),
      );

      await repository.save(item.copyWith(title: 'Otro título'));

      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).getSingle();
      expect(source.contentHash, 'hash-simulado');
    });

    test(
      'borrar un elemento borra su entrada, y en cascada su fuente',
      () async {
        final item = buildItem();
        await repository.save(item);

        await repository.delete(item.id);
        await repository.purge([item.id]);

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
      await repository.purge([a.id, b.id]);

      final remaining = await db.select(db.knowledgeEntries).get();
      expect(remaining, isEmpty);
    });
  });

  group('la lectura sale del modelo nuevo (F10)', () {
    Future<KnowledgeItem> found(String id) async =>
        (await repository.findById(id)).getRight().toNullable()!;

    test('el título, el subtítulo, las notas y el espacio vienen de item, no '
        'de la tabla vieja', () async {
      final saved = buildItem(title: 'Título de antes');
      await repository.save(saved);
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(id: 'sp', name: 'Un tema', createdAt: now),
          );

      // Se cambia SOLO la fila nueva: si la lectura saliera de la vieja, no se
      // vería.
      await (db.update(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(saved.id))).write(
        const KnowledgeEntriesCompanion(
          title: Value('Título de ahora'),
          subtitle: Value('Un subtítulo'),
          notes: Value('Una nota mía'),
          spaceId: Value('sp'),
        ),
      );

      final read = await found(saved.id);
      expect(read.title, 'Título de ahora');
      expect(read.subtitle, 'Un subtítulo');
      expect(read.notes, 'Una nota mía');
      expect(read.spaceId, 'sp');
    });

    test(
      'la procedencia viene de source, y su id es el del elemento',
      () async {
        final saved = buildItem();
        await repository.save(saved);
        await (db.update(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals(saved.id))).write(
          const KnowledgeSourcesCompanion(
            originUrl: Value('https://otro.org/x'),
            authorName: Value('Otra persona'),
          ),
        );

        final read = await found(saved.id);

        expect(read.source.url, 'https://otro.org/x');
        expect(read.source.authorName, 'Otra persona');
        expect(read.source.kind, saved.source.kind);
        expect(read.source.id, saved.id);
      },
    );

    test('el estado del pipeline sale del de la fuente, y una nota está '
        'siempre lista', () async {
      final source = buildItem();
      final note = buildItem(sourceKind: SourceKind.manualNote);
      await repository.save(source);
      await repository.save(note);

      Future<ProcessingState> stateOf(String id) async =>
          (await found(id)).processingState;

      for (final (status, expected) in [
        (SourceProcessingStatus.pending, ProcessingState.pending),
        (SourceProcessingStatus.running, ProcessingState.processing),
        (SourceProcessingStatus.done, ProcessingState.ready),
        (SourceProcessingStatus.failed, ProcessingState.failed),
      ]) {
        await (db.update(db.knowledgeSources)
              ..where((s) => s.itemId.equals(source.id)))
            .write(KnowledgeSourcesCompanion(processingStatus: Value(status)));
        expect(await stateOf(source.id), expected, reason: status.name);
      }
      expect(await stateOf(note.id), ProcessingState.ready);
    });

    test('una nota no tiene fila de fuente: su procedencia es una nota '
        'manual, capturada cuando se creó', () async {
      final note = buildItem(sourceKind: SourceKind.manualNote);
      await repository.save(note);

      final read = await found(note.id);

      expect(read.source.kind, SourceKind.manualNote);
      expect(read.source.capturedAt, note.createdAt);
      expect(read.source.url, isNull);
      expect(
        await (db.select(
          db.knowledgeSources,
        )..where((s) => s.itemId.equals(note.id))).get(),
        isEmpty,
      );
    });

    test('filtrar por estado usa el estado de la fuente, y una nota cuenta '
        'como lista', () async {
      final failed = buildItem(title: 'Fallida', state: ProcessingState.failed);
      final pending = buildItem(
        title: 'Pendiente',
        state: ProcessingState.pending,
      );
      final note = buildItem(
        title: 'Una nota',
        sourceKind: SourceKind.manualNote,
      );
      for (final item in [failed, pending, note]) {
        await repository.save(item);
      }

      Future<List<String>> titles(Set<ProcessingState> states) async {
        final items = (await repository.list(
          LibraryQuery(processingStates: states),
        )).getRight().toNullable()!;
        return items.map((i) => i.title).toList()..sort();
      }

      expect(await titles({ProcessingState.failed}), ['Fallida']);
      expect(await titles({ProcessingState.pending}), ['Pendiente']);
      expect(await titles({ProcessingState.ready}), ['Una nota']);
      expect(await titles({ProcessingState.failed, ProcessingState.ready}), [
        'Fallida',
        'Una nota',
      ]);
    });

    test('por fecha de captura ordena por la de la fuente y, para una nota, '
        'por la de creación', () async {
      final old = buildItem(title: 'Vieja', capturedAt: DateTime(2026));
      final recent = buildItem(
        title: 'Reciente',
        capturedAt: DateTime(2026, 8),
      );
      final note = buildItem(title: 'Nota', sourceKind: SourceKind.manualNote);
      // La nota se creó entre las dos.
      await repository.save(old);
      await repository.save(recent);
      await repository.save(note.copyWith(createdAt: DateTime(2026, 4)));

      final items = (await repository.list(
        const LibraryQuery(descending: false),
      )).getRight().toNullable()!;

      expect(items.map((i) => i.title), ['Vieja', 'Nota', 'Reciente']);
    });

    test(
      'mover un elemento de tema actualiza también el modelo nuevo',
      () async {
        final item = buildItem();
        await repository.save(item);
        await db
            .into(db.spaces)
            .insert(
              SpacesCompanion.insert(id: 'sp', name: 'Un tema', createdAt: now),
            );

        await repository.assignSpace(itemId: item.id, spaceId: 'sp');

        final entry = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals(item.id))).getSingle();
        expect(entry.spaceId, 'sp');
        expect((await found(item.id)).spaceId, 'sp');
      },
    );

    test('mover varios de tema actualiza también el modelo nuevo', () async {
      final a = buildItem();
      final b = buildItem();
      await repository.save(a);
      await repository.save(b);
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(id: 'sp', name: 'Un tema', createdAt: now),
          );

      await repository.assignSpaceMany(itemIds: [a.id, b.id], spaceId: 'sp');

      final entries = await db.select(db.knowledgeEntries).get();
      expect(entries.map((e) => e.spaceId), ['sp', 'sp']);
    });

    test('guardar espeja las notas libres del elemento', () async {
      final item = buildItem().copyWith(notes: 'algo que quiero recordar');

      await repository.save(item);

      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals(item.id))).getSingle();
      expect(entry.notes, 'algo que quiero recordar');
    });
  });

  group('una sola escritura (F10)', () {
    test('guardar escribe el elemento una vez: item, y su source o su note; el '
        'modelo viejo ya no existe', () async {
      await repository.save(buildItem());
      await repository.save(buildItem(sourceKind: SourceKind.manualNote));

      expect(await db.select(db.knowledgeEntries).get(), hasLength(2));
      expect(await db.select(db.knowledgeSources).get(), hasLength(1));
      expect(await db.select(db.knowledgeNotes).get(), hasLength(1));
      final legacy = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
            "('items', 'sources', 'tags', 'item_tags')",
          )
          .get();
      expect(legacy, isEmpty);
    });

    test('borrar se lleva de item todo lo que cuelga de él', () async {
      final saved = buildItem().copyWith(
        renditions: [
          Rendition.text(
            id: 'rend-una',
            itemId: 'item-una',
            kind: RenditionKind.plainText,
            content: 'texto',
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );
      await repository.save(saved.copyWith(id: 'item-una'));
      await db
          .into(db.spaces)
          .insert(
            SpacesCompanion.insert(id: 'sp', name: 'Un tema', createdAt: now),
          );
      await repository.assignSpace(itemId: 'item-una', spaceId: 'sp');

      await repository.delete('item-una');
      await repository.purge(['item-una']);

      expect(await db.select(db.knowledgeEntries).get(), isEmpty);
      expect(await db.select(db.knowledgeSources).get(), isEmpty);
      expect(await db.select(db.renditions).get(), isEmpty);
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

    test('borrar el destino para siempre deja el enlace roto; borrar la nota '
        'se lleva sus enlaces', () async {
      await repository.save(buildItem(id: 'roma', title: 'Roma'));
      await repository.save(blocksNote('Viaje', ['[[Roma]]'], id: 'n1'));

      await repository.delete('roma');
      await repository.purge(['roma']);
      expect(await linksOf('n1'), {('roma', null)});

      await repository.delete('n1');
      await repository.purge(['n1']);
      expect(await db.select(db.inlineLinks).get(), isEmpty);
    });
  });

  group('la papelera (F11): lo borrado no es de la biblioteca', () {
    Future<List<String>> listedIds([
      LibraryQuery query = const LibraryQuery(),
    ]) async => [
      for (final item in (await repository.list(
        query,
      )).getRight().toNullable()!)
        item.id,
    ];

    test('la lista, la cuenta y los ids no lo incluyen; vuelve al '
        'restaurarlo', () async {
      final a = buildItem();
      final b = buildItem();
      await repository.save(a);
      await repository.save(b);

      await trashItemRows(db, a.id);

      expect(await listedIds(), [b.id]);
      expect(
        (await repository.count(const LibraryQuery())).getRight().toNullable(),
        1,
      );
      expect(
        (await repository.matchingIds(
          const LibraryQuery(),
        )).getRight().toNullable(),
        [b.id],
      );

      await restoreItemRows(db, a.id);

      expect(await listedIds(), unorderedEquals([a.id, b.id]));
    });

    test('pedirlo por su id tampoco lo trae', () async {
      final a = buildItem();
      await repository.save(a);
      await trashItemRows(db, a.id);

      expect((await repository.findById(a.id)).getRight().toNullable(), isNull);
      expect(await listedIds(LibraryQuery(ids: {a.id})), isEmpty);
    });

    test('con cualquier filtro sigue afuera', () async {
      final a = buildItem(title: 'Roma');
      await repository.save(a);
      await trashItemRows(db, a.id);

      expect(
        await listedIds(const LibraryQuery(sourceKinds: {SourceKind.webPage})),
        isEmpty,
      );
      expect(await listedIds(const LibraryQuery(searchText: 'Roma')), isEmpty);
      expect(
        await listedIds(
          const LibraryQuery(sortBy: LibrarySort.title, limit: 10),
        ),
        isEmpty,
      );
    });

    test('la lista observada lo saca en cuanto va a la papelera, y lo '
        'devuelve al restaurarlo', () async {
      final a = buildItem();
      final b = buildItem();
      await repository.save(a);
      await repository.save(b);
      final queue = StreamQueue(repository.watch(const LibraryQuery()));
      addTearDown(queue.cancel);
      expect(
        (await queue.next).map((i) => i.id),
        unorderedEquals([a.id, b.id]),
      );

      await trashItemRows(db, a.id);
      expect((await queue.next).map((i) => i.id), [b.id]);

      await restoreItemRows(db, a.id);
      expect(
        (await queue.next).map((i) => i.id),
        unorderedEquals([a.id, b.id]),
      );
    });

    test(
      'el elemento observado por su id pasa a null en la papelera',
      () async {
        final a = buildItem();
        await repository.save(a);
        final queue = StreamQueue(repository.watchById(a.id));
        addTearDown(queue.cancel);
        expect((await queue.next)?.id, a.id);

        await trashItemRows(db, a.id);
        expect(await queue.next, isNull);

        await restoreItemRows(db, a.id);
        expect((await queue.next)?.id, a.id);
      },
    );

    test('guardarlo mientras está en la papelera no lo saca de ella', () async {
      final a = buildItem(title: 'Antes');
      await repository.save(a);
      await trashItemRows(db, a.id);

      // El procesamiento en segundo plano puede terminar después de que el
      // usuario lo borró.
      await repository.save(a.copyWith(title: 'Después'));

      expect((await repository.findById(a.id)).getRight().toNullable(), isNull);
      await restoreItemRows(db, a.id);
      expect(
        (await repository.findById(a.id)).getRight().toNullable()?.title,
        'Después',
      );
    });
  });

  group('runInTransaction (F15, comando 16)', () {
    test('lo de adentro queda guardado, todo junto', () async {
      final a = buildItem(title: 'Uno');
      final b = buildItem(title: 'Dos');

      final result = await repository.runInTransaction(() async {
        await repository.save(a);
        await repository.save(b);
        return 'listo';
      });

      expect(result, 'listo');
      expect(
        (await repository.findById(a.id)).getRight().toNullable()?.title,
        'Uno',
      );
      expect(
        (await repository.findById(b.id)).getRight().toNullable()?.title,
        'Dos',
      );
    });

    test('un fallo de adentro deshace TODO, no solo lo que faltaba', () async {
      final a = buildItem(title: 'Se pierde con el resto');

      await expectLater(
        repository.runInTransaction(() async {
          await repository.save(a);
          throw StateError('algo salió mal a mitad de camino');
        }),
        throwsStateError,
      );

      expect((await repository.findById(a.id)).getRight().toNullable(), isNull);
    });
  });

  group('runBulk (F19, 19.4)', () {
    Future<List<String>> searchItems(String userInput) async {
      final query = buildSearchQuery(userInput);
      if (query.isEmpty) return [];
      final rows = await db
          .customSelect(
            'SELECT item_id FROM item_search WHERE item_search MATCH ? '
            'ORDER BY rank',
            variables: [Variable.withString(query)],
          )
          .get();
      return rows.map((r) => r.data['item_id']! as String).toList();
    }

    test('lo de adentro queda guardado, todo junto', () async {
      final a = buildItem(title: 'Uno');
      final b = buildItem(title: 'Dos');

      final result = await repository.runBulk(() async {
        await repository.save(a);
        await repository.save(b);
        return 'listo';
      });

      expect(result, 'listo');
      expect(
        (await repository.findById(a.id)).getRight().toNullable()?.title,
        'Uno',
      );
      expect(
        (await repository.findById(b.id)).getRight().toNullable()?.title,
        'Dos',
      );
    });

    test('un fallo de adentro deshace TODO, no solo lo que faltaba', () async {
      final a = buildItem(title: 'Se pierde con el resto');

      await expectLater(
        repository.runBulk(() async {
          await repository.save(a);
          throw StateError('algo salió mal a mitad de camino');
        }),
        throwsStateError,
      );

      expect((await repository.findById(a.id)).getRight().toNullable(), isNull);
    });

    test(
      'suspende el índice de texto durante el lote y lo repuebla al cerrar',
      () async {
        final a = buildItem(title: 'Revoluciones científicas');

        await repository.runBulk(() async {
          await repository.save(a);
          // Adentro del lote: el trigger real está suspendido.
          expect(await searchItems('revoluciones'), isEmpty);
        });

        expect(await searchItems('revoluciones'), [a.id]);
      },
    );

    test('comparte el lote con un ReferenceRepositoryImpl que use el mismo '
        'puente: sus campos también se difieren y se vuelcan juntos', () async {
      final holder = BulkWriterHolder();
      final shared = LibraryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        files: files,
        bulkWriter: holder,
      );
      final reference = ReferenceRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        clock: () => now,
        bulkWriter: holder,
      );

      final item = buildItem(
        title: 'Con referencia',
        sourceKind: SourceKind.reference,
      );

      Future<List<FieldVersionRow>> referenceVersions() =>
          (db.select(db.fieldVersions)..where(
                (f) =>
                    f.itemId.equals(item.id) &
                    f.fieldName.equals(EntryField.reference),
              ))
              .get();

      await shared.runBulk(() async {
        await shared.save(item);
        await reference.saveReference(
          item.id,
          const ReferenceData(publisher: 'Editorial Uno'),
        );
        // Adentro del lote: el escritor de referencia todavía no volcó su
        // `field_version` —comparte el mismo lote que abrió `shared`—.
        expect(await referenceVersions(), isEmpty);
      });

      expect(await referenceVersions(), hasLength(1));
    });
  });
}
