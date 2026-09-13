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
import 'package:sinapsis/features/chat/data/services/library_vault_retriever.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria — mismo criterio que el resto de las
/// pruebas de repositorio: lo que importa acá es que la búsqueda de FTS5
/// que ya tiene la biblioteca encuentra lo relevante, y eso no lo ejercita
/// un doble.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late LibraryVaultRetriever retriever;

  final now = DateTime(2026, 9, 13, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    retriever = LibraryVaultRetriever(library: libraryRepository);
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

    expect(sources.single.excerpt.length, lessThan(('palabra ' * 200).length));
    expect(sources.single.excerpt, endsWith('…'));
  });
}
