import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';

import '../../support/fake_id_generator.dart';
import '../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La restricción inalienable del encargo, comprobada contra F8: nada de lo
/// que F8 hace —etiquetas como valores de Tema, fusionar valores, renombrar,
/// alias, borrar lo que no se usa, y deshacer todo eso— toca el texto de una
/// fuente ni sus chunks. (La reconciliación de etiquetas viejas de la migración
/// v14 se retiró con los pasos anteriores a v15, y con ella su parte de esta
/// prueba.) Concatenar los chunks sigue reproduciendo el texto
/// carácter a carácter, y los chunks siguen siendo LOS MISMOS, con sus ids.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late OrganizeRepositoryImpl organize;
  late VocabularyRepositoryImpl vocabulary;
  late FakeIdGenerator chunkIds;

  final now = DateTime(2026, 9, 19, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    chunkIds = FakeIdGenerator(prefix: 'chunk');
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'org'),
      clock: () => now,
    );
    vocabulary = VocabularyRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'voc'),
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<String> seedSource(String id, String text, SourceKind kind) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Fuente $id',
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: now,
          url: 'https://ejemplo.org/$id',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-$id',
            itemId: id,
            kind: RenditionKind.markdown,
            content: text,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );
    await chunkAndPersistSource(db, itemId: id, ids: chunkIds);
    return id;
  }

  String chunkKey(ChunkRow c) =>
      'chunk ${c.id}|${c.itemId}|${c.seq}|${c.charStart}|${c.charEnd}|'
      '${c.content.hashCode}';

  /// Lo que describe el texto de las fuentes, en una lista comparable: el
  /// texto de cada una —el de su forma principal— y cada chunk con su id, su
  /// posición y su texto.
  Future<List<String>> textSnapshot() async => [
    for (final s in await db.select(db.knowledgeSources).get())
      for (final r in await (db.select(
        db.renditions,
      )..where((r) => r.itemId.equals(s.itemId))).get())
        if (r.content case final text?)
          'texto ${s.itemId}|${r.id}|${text.length}|${text.hashCode}',
    for (final c in await db.select(db.chunks).get()) chunkKey(c),
  ]..sort();

  test('etiquetar, mantener el vocabulario y deshacerlo todo no toca el '
      'texto de ninguna fuente', () async {
    final article = await seedSource(
      'articulo',
      '# Roma\n\nLa república nació en 509 a.C. y el imperio en 27 a.C. '
          'Cierre sin salto final',
      SourceKind.webPage,
    );
    final transcript = await seedSource(
      'transcripcion',
      '[00:00] Hola a todos.\n[00:20] Hoy hablamos de Roma y de Egipto.\n'
          '[00:40] Fin.',
      SourceKind.youtube,
    );
    final before = await textSnapshot();
    expect((await verifyChunkInvariant(db)).sourcesChecked, 2);

    // Las etiquetas, por el camino de la app: valores de Tema puestos en los
    // elementos.
    final roma = (await organize.getOrCreateTag(
      'Roma',
    )).getRight().toNullable()!;
    final egipto = (await organize.getOrCreateTag(
      'Egipto',
    )).getRight().toNullable()!;
    for (final (id, tag) in [(article, roma), (transcript, egipto)]) {
      final item = (await library.findById(id)).getRight().toNullable()!;
      await library.save(item.copyWith(tags: [...item.tags, tag]));
    }

    // Una etiqueta más, puesta al guardar el elemento.
    final tag = (await organize.getOrCreateTag(
      'Historia',
    )).getRight().toNullable()!;
    final saved = (await library.findById(article)).getRight().toNullable()!;
    await library.save(saved.copyWith(tags: [...saved.tags, tag]));

    // Mantenimiento del vocabulario, cada cosa con su deshacer.
    final tema = await temaDefinitionId(db);
    final values = await (db.select(
      db.propertyValues,
    )..where((v) => v.definitionId.equals(tema))).get();
    final ids = {for (final v in values) v.value: v.id};
    expect(ids.keys, containsAll(['Roma', 'Egipto', 'Historia']));

    final renamed = (await vocabulary.renameValue(
      id: ids['Egipto']!,
      label: 'Egipto antiguo',
    )).getRight().toNullable()!;
    await vocabulary.undo(renamed);

    final aliased = (await vocabulary.addAlias(
      valueId: ids['Roma']!,
      alias: 'Urbe',
    )).getRight().toNullable()!;
    await vocabulary.undo(aliased);

    final merged = (await vocabulary.mergeValues(
      keepId: ids['Roma']!,
      discardIds: [ids['Historia']!],
    )).getRight().toNullable()!;
    await vocabulary.undo(merged);

    // Un valor sin ningún elemento, para poder borrarlo.
    final sobrante = (await organize.getOrCreateTag(
      'Sobrante',
    )).getRight().toNullable()!;
    final unused = (await vocabulary.deleteUnusedValues([
      sobrante.id,
    ])).getRight().toNullable()!;
    await vocabulary.undo(unused);

    // Nada de eso tocó el texto: mismos chunks, mismos ids, mismo texto...
    expect(await textSnapshot(), before);
    // ...y el invariante central sigue valiendo sobre toda la bóveda.
    final report = await verifyChunkInvariant(db);
    expect(report.holds, isTrue, reason: report.violations.join('\n'));
    expect(report.sourcesChecked, 2);
  });
}
