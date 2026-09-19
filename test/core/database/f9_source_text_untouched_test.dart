import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/health/data/repositories/health_repository_impl.dart';
import 'package:sinapsis/features/inbox/data/repositories/inbox_repository_impl.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notes/data/repositories/note_sources_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';

import '../../support/fake_id_generator.dart';
import '../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// La restricción inalienable del encargo, comprobada contra F9: nada de lo
/// que F9 hace —enlaces `[[ ]]`, sugerencias en lote y su deshacer, revisar
/// contradicciones, fechar un hecho, extraer una nota con su posición, la
/// madurez, la Bandeja y su deshacer, y todas las lecturas del panel de salud,
/// la línea de tiempo y las fuentes citadas— toca el texto de una fuente ni sus
/// chunks. Concatenar los chunks sigue reproduciendo `fullText` carácter a
/// carácter, y los chunks siguen siendo LOS MISMOS, con sus ids.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late OrganizeRepositoryImpl organize;
  late SuggestionRepositoryImpl suggestions;
  late InboxRepositoryImpl inbox;
  late FakeIdGenerator chunkIds;

  final now = DateTime(2026, 9, 19, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    chunkIds = FakeIdGenerator(prefix: 'chunk');
    final ids = FakeIdGenerator(prefix: 'org');
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'lib'),
      clock: () => now,
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    suggestions = SuggestionRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      organize: organize,
      merge: MergeDuplicateItemsUseCaseImpl(
        database: db,
        library: library,
        ids: FakeIdGenerator(prefix: 'merge'),
        clock: () => now,
        telemetry: MockTelemetryService(),
      ),
      ids: FakeIdGenerator(prefix: 'sug'),
      clock: () => now,
    );
    inbox = InboxRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
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

  Future<String> seedNote(String id, List<ContentBlock> blocks) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: 'Nota $id',
        source: Source(
          id: 'src-$id',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-$id',
            itemId: id,
            kind: RenditionKind.blocks,
            content: encodeContentBlocks(blocks),
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );
    return id;
  }

  String chunkKey(ChunkRow c) =>
      'chunk ${c.id}|${c.itemId}|${c.seq}|${c.charStart}|${c.charEnd}|'
      '${c.content.hashCode}';

  /// Lo que describe el texto de las fuentes, en una lista comparable: el
  /// `fullText` de cada una y cada chunk con su id, su posición y su texto.
  Future<List<String>> textSnapshot() async => [
    for (final s in await db.select(db.knowledgeSources).get())
      'fuente ${s.itemId}|${s.fullText.length}|${s.fullText.hashCode}',
    for (final c in await db.select(db.chunks).get()) chunkKey(c),
  ]..sort();

  test('todo lo que hace F9 deja el texto de las fuentes y sus chunks '
      'intactos', () async {
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

    // Enlaces [[ ]]: una nota que apunta a otra y a un título que no existe;
    // se guarda dos veces, porque cada guardado los vuelve a sincronizar.
    final other = await seedNote('otra', [
      ContentBlock.paragraph(text: 'Roma', addedAt: now),
    ]);
    final living = await seedNote('viva', [
      ContentBlock.paragraph(
        text: 'Ver [[Nota otra]] y [[Nota que falta]].',
        addedAt: now,
      ),
    ]);
    final saved = (await library.findById(living)).getRight().toNullable()!;
    await library.save(saved.copyWith(title: 'Nota viva editada'));

    // Extracción con su posición, y la cita directa de una fuente.
    final atomic = await seedNote('atomica', [
      ContentBlock.paragraph(
        text: 'La república nació en 509 a.C.',
        addedAt: now,
      ),
    ]);
    await organize.createRelation(
      fromItemId: atomic,
      toItemId: article,
      kind: RelationKind.extractedFrom,
      sourceCharStart: 8,
      sourceCharEnd: 40,
    );
    await organize.createRelation(
      fromItemId: living,
      toItemId: atomic,
      kind: RelationKind.relatedTo,
    );
    await organize.createRelation(
      fromItemId: living,
      toItemId: transcript,
      kind: RelationKind.cites,
    );

    // Contradicciones y su revisión.
    await organize.createRelation(
      fromItemId: other,
      toItemId: living,
      kind: RelationKind.contradicts,
    );
    final relation = await db
        .select(db.relations)
        .get()
        .then(
          (rows) => rows.firstWhere((r) => r.kind == RelationKind.contradicts),
        );
    await organize.setRelationReviewed(relationId: relation.id, reviewed: true);
    await organize.setRelationReviewed(
      relationId: relation.id,
      reviewed: false,
    );

    // Sugerencias de propiedad: en lote, y deshaciendo una aceptada.
    final region = (await organize.getOrCreatePropertyDefinition(
      'Región',
    )).getRight().toNullable()!;
    final proposed = [
      for (final value in ['Roma', 'Egipto'])
        (await suggestions.createPropertySuggestion(
          targetItemId: article,
          definitionId: region.id,
          definitionName: 'Región',
          value: value,
          isNewValue: true,
        )).getRight().toNullable()!.id,
    ];
    await suggestions.acceptMany(proposed);
    await suggestions.revertAccepted(proposed.first);
    await suggestions.rejectMany([proposed.first]);

    // Fechar los hechos: la "Fecha del hecho" de las dos fuentes.
    final fecha = (await organize.getOrCreatePropertyDefinition(
      kFechaDelHechoCategoryName,
    )).getRight().toNullable()!;
    for (final (item, date) in [
      (
        article,
        const HistoricalDate(
          year: 509,
          precision: DatePrecision.year,
          isBce: true,
        ),
      ),
      (
        transcript,
        const HistoricalDate(
          year: 27,
          precision: DatePrecision.year,
          isBce: true,
        ),
      ),
    ]) {
      final value = (await organize.getOrCreateHistoricalPropertyValue(
        definitionId: fecha.id,
        date: date,
      )).getRight().toNullable()!;
      await organize.assignProperty(
        itemId: item,
        definitionId: fecha.id,
        value: value.value,
      );
    }

    // La madurez y la Bandeja, con su deshacer.
    await inbox.setNoteMaturity(itemId: living, maturity: NoteMaturity.mature);
    await inbox.transitionState(itemId: article, to: ItemState.triaged);
    await inbox.transitionState(itemId: article, to: ItemState.processed);
    await inbox.transitionState(itemId: transcript, to: ItemState.discarded);
    await inbox.transitionState(itemId: transcript, to: ItemState.processed);

    // Todas las lecturas nuevas.
    await TimelineRepositoryImpl(
      database: db,
      library: library,
      telemetry: MockTelemetryService(),
    ).watchEvents(const LibraryQuery()).first;
    final health = HealthRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
    );
    await health.watchNoteComposition().first;
    await health.watchUnreviewedContradictionCount().first;
    final cited = await NoteSourcesRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
    ).watchCitedSources(living).first;
    // Y de verdad se armaron: no es un test que pasa porque no hizo nada.
    expect(
      cited.map((s) => s.sourceId),
      unorderedEquals([article, transcript]),
    );

    // Nada de eso tocó el texto: mismos chunks, mismos ids, mismo fullText...
    expect(await textSnapshot(), before);
    // ...y el invariante central sigue valiendo sobre toda la bóveda.
    final report = await verifyChunkInvariant(db);
    expect(report.holds, isTrue, reason: report.violations.join('\n'));
    expect(report.sourcesChecked, 2);
  });
}
