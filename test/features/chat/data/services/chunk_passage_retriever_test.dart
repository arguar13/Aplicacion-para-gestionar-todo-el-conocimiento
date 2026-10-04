import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/data/services/chunk_passage_retriever.dart';
import 'package:sinapsis/features/chat/domain/services/chat_passages.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria — mismo criterio que el resto de las
/// pruebas de repositorio: lo que importa acá es que los índices de FTS5
/// encuentran el pasaje relevante, y eso no lo ejercita un doble (F30).
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late ChunkPassageRetriever retriever;

  final now = DateTime(2026, 9, 13, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    retriever = ChunkPassageRetriever(database: db);
    counter = 0;
  });

  tearDown(() => db.close());

  Future<void> seed(String title, {String content = ''}) async {
    final n = counter++;
    await libraryRepository.save(
      KnowledgeItem(
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
        renditions: content.isEmpty
            ? const []
            : [
                Rendition.text(
                  id: 'rend-$n',
                  itemId: 'item-$n',
                  kind: RenditionKind.plainText,
                  content: content,
                  isPrimary: true,
                  createdAt: now,
                ),
              ],
      ),
    );
  }

  test('encuentra el elemento cuyo título coincide con la pregunta', () async {
    await seed('Charla sobre paradigmas científicos');
    await seed('Receta de cocina');

    final sources = await retriever.retrieve('paradigmas');

    expect(sources, hasLength(1));
    expect(sources.single.itemTitle, 'Charla sobre paradigmas científicos');
    expect(sources.single.itemId, 'item-0');
  });

  test(
    'una pregunta que no coincide con nada devuelve una lista vacía',
    () async {
      await seed('Receta de cocina');

      expect(await retriever.retrieve('paradigmas científicos'), isEmpty);
    },
  );

  test('respeta el límite pedido', () async {
    for (var i = 0; i < 6; i++) {
      await seed('Artículo sobre biología número $i');
    }

    final sources = await retriever.retrieve('biología', limit: 2);

    expect(sources, hasLength(2));
  });

  test('una pregunta de solo espacios no busca nada', () async {
    await seed('Cualquier cosa');

    expect(await retriever.retrieve('   '), isEmpty);
  });

  test('el fragmento citado sale del contenido de la rendition', () async {
    await seed(
      'Un artículo',
      content: 'Acá se explica por qué las enzimas catalizan reacciones.',
    );

    final sources = await retriever.retrieve('enzimas');

    expect(sources.single.excerpt, contains('catalizan reacciones'));
  });

  test('un contenido más largo que el límite queda truncado', () async {
    await seed('Un artículo largo', content: 'palabra ' * 200);

    final sources = await retriever.retrieve('palabra');

    expect(
      sources.single.excerpt.length,
      lessThanOrEqualTo(kChatPassageChars + 2),
    );
    expect(sources.single.excerpt, endsWith('…'));
  });

  test('una pregunta larga en lenguaje natural encuentra igual lo que '
      'menciona una sola de sus palabras', () async {
    // Es el caso real que falla si la pregunta se busca como una sola
    // consulta con AND implícito entre sus palabras (ver `buildSearchQuery`):
    // ninguna nota real contiene las quince palabras exactas de la
    // pregunta, pero sí menciona "religión".
    await seed(
      'Sobre la fe',
      content: 'Un texto que habla de religión y de historia.',
    );
    await seed('Receta de cocina', content: 'Ingredientes y pasos.');

    final sources = await retriever.retrieve(
      'Contame qué dice mi bóveda sobre religión, por favor',
    );

    expect(sources, hasLength(1));
    expect(sources.single.itemTitle, 'Sobre la fe');
  });

  test('un elemento que menciona varias palabras de la pregunta queda antes '
      'que uno que solo menciona una', () async {
    await seed(
      'Habla de las dos cosas',
      content: 'Se explican la religión y la filosofía juntas.',
    );
    await seed('Solo una de las dos', content: 'Se explica la religión.');

    final sources = await retriever.retrieve('religión filosofía');

    expect(sources.first.itemTitle, 'Habla de las dos cosas');
  });

  group('el offset del fragmento citado (F16, D2)', () {
    test(
      'cae dentro de un chunk real: es la misma coordenada que `Chunks`',
      () async {
        await seed(
          'Un artículo',
          content: 'Acá se explica por qué las enzimas catalizan reacciones.',
        );

        final source = (await retriever.retrieve('enzimas')).single;

        expect(source.sourceCharStart, isNotNull);
        expect(source.sourceCharEnd, isNotNull);
        final chunk =
            await (db.select(db.chunks)
                  ..where((c) => c.itemId.equals(source.itemId))
                  ..where(
                    (c) =>
                        c.charStart.isSmallerOrEqualValue(
                          source.sourceCharStart!,
                        ) &
                        c.charEnd.isBiggerThanValue(source.sourceCharStart!),
                  ))
                .getSingle();
        expect(chunk.content, contains('enzimas'));
      },
    );

    test('una nota manual no tiene offset: nunca se fragmenta', () async {
      await libraryRepository.save(
        KnowledgeItem(
          id: 'note-0',
          title: 'Mi nota sobre paradigmas',
          source: Source(
            id: 'src-note-0',
            kind: SourceKind.manualNote,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-note-0',
              itemId: 'note-0',
              kind: RenditionKind.plainText,
              content: 'Algo sobre paradigmas, escrito a mano.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

      final source = (await retriever.retrieve('paradigmas')).single;

      expect(source.excerpt, contains('paradigmas'));
      expect(source.sourceCharStart, isNull);
      expect(source.sourceCharEnd, isNull);
    });

    test('con más de una forma de texto, el offset sale de la principal, no '
        'de las dos juntas', () async {
      await libraryRepository.save(
        KnowledgeItem(
          id: 'item-multi',
          title: 'Con dos formas',
          source: Source(
            id: 'src-multi',
            kind: SourceKind.webPage,
            capturedAt: now,
            url: 'https://ejemplo.org/multi',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-old',
              itemId: 'item-multi',
              kind: RenditionKind.plainText,
              content: 'La forma vieja habla de paradigmas también.',
              isPrimary: false,
              createdAt: now.subtract(const Duration(days: 1)),
            ),
            Rendition.text(
              id: 'rend-primary',
              itemId: 'item-multi',
              kind: RenditionKind.plainText,
              content: 'La forma principal, con paradigmas de verdad.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

      final source = (await retriever.retrieve('paradigmas')).single;

      expect(source.excerpt, 'La forma principal, con paradigmas de verdad.');
      expect(source.sourceCharStart, 0);
    });

    test('un contenido con espacio al principio reporta el offset real, no '
        'cero', () async {
      await seed('Con espacio', content: '   Empieza con paradigmas acá.');

      final source = (await retriever.retrieve('paradigmas')).single;

      expect(source.sourceCharStart, 3);
      expect(source.excerpt, startsWith('Empieza con paradigmas'));
    });
  });

  group('scopeIds (F16, D1: acotar a un cuaderno)', () {
    test('sin alcance, busca en toda la bóveda', () async {
      await seed('Charla sobre paradigmas científicos');
      await seed('Otro paradigma distinto');

      final sources = await retriever.retrieve('paradigma');

      expect(sources, hasLength(2));
    });

    test('con alcance, ignora lo que coincide pero está afuera', () async {
      await seed('Charla sobre paradigmas científicos');
      await seed('Otro paradigma distinto');

      final sources = await retriever.retrieve(
        'paradigma',
        scopeIds: {'item-0'},
      );

      expect(sources, hasLength(1));
      expect(sources.single.itemId, 'item-0');
    });

    test('un alcance vacío no encuentra nada, aunque algo coincida', () async {
      await seed('Charla sobre paradigmas científicos');

      final sources = await retriever.retrieve('paradigma', scopeIds: {});

      expect(sources, isEmpty);
    });
  });

  group('el pasaje que importa (F30)', () {
    test('de un texto largo, cita el pasaje donde está lo preguntado, no su '
        'principio', () async {
      final text =
          '${'Introducción general sobre otros asuntos. ' * 40}'
          'El Senado romano reunía a los patricios más antiguos. '
          '${'Más relleno sin relación alguna. ' * 40}';
      await seed('Un libro de historia', content: text);

      final source = (await retriever.retrieve(
        '¿Qué era el Senado romano?',
      )).single;

      expect(source.excerpt, contains('El Senado romano reunía'));
      expect(source.excerpt, startsWith('…'));
      expect(source.excerpt.length, lessThanOrEqualTo(kChatPassageChars + 2));
      // La cita apunta justo al pasaje, dentro del texto de la fuente.
      final cited = text.substring(
        source.sourceCharStart!,
        source.sourceCharEnd,
      );
      expect(cited, contains('El Senado romano reunía'));
      expect(source.excerpt, contains(cited));
    });

    test('una pregunta de solo palabras vacías no busca nada', () async {
      await seed('Algo', content: 'Que es lo que hay sobre esto.');

      expect(
        await retriever.retrieve('¿Qué es lo que hay sobre esto?'),
        isEmpty,
      );
    });

    test('lo que está en la papelera no se cita', () async {
      await seed('Borrado', content: 'Habla de paradigmas.');
      await seed('Vivo', content: 'También de paradigmas.');
      await libraryRepository.delete('item-0');

      final sources = await retriever.retrieve('paradigmas');

      expect(sources.map((s) => s.itemTitle), ['Vivo']);
    });

    test('como mucho las fuentes pedidas, una por elemento', () async {
      for (var i = 0; i < 6; i++) {
        await seed(
          'Elemento $i',
          content: 'Habla de paradigmas, el número $i.',
        );
      }

      final sources = await retriever.retrieve('paradigmas');

      expect(sources, hasLength(kChatMaxSources));
      expect(sources.map((s) => s.itemId).toSet(), hasLength(kChatMaxSources));
    });
  });
}
