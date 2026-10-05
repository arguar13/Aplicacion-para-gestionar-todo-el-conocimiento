import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/chat_source.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notes/data/repositories/derived_note_repository_impl.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_parts.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/relations/data/services/item_vector_index_impl.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Un [DerivedNoteGenerator] de prueba: devuelve exactamente el borrador
/// que se le da, sin tocar ni el modelo de lenguaje ni el anclaje del
/// commit 11 —eso ya se prueba aparte, acá lo que importa es qué hace el
/// caso de uso con un borrador YA anclado—.
class FakeDerivedNoteGenerator implements DerivedNoteGenerator {
  FakeDerivedNoteGenerator(this.draft, {this.throws = false, this.draftFor});

  DerivedNoteDraft draft;
  List<ChatSource>? sourcesSeen;

  /// Si está, arma el borrador de cada pedido según sus fuentes, en vez de
  /// devolver siempre [draft].
  final DerivedNoteDraft Function(List<ChatSource> sources)? draftFor;

  /// Las fuentes de cada pedido, en orden (F30: un cuaderno grande se lee en
  /// varios).
  final calls = <List<ChatSource>>[];

  /// Simula una falla del motor de inferencia —de terceros, sin tipo propio
  /// en Dart— en vez de un borrador.
  final bool throws;

  @override
  Future<DerivedNoteDraft> generateDerivedNote({
    required DerivedNoteType type,
    required List<ChatSource> sources,
  }) async {
    sourcesSeen = sources;
    calls.add(sources);
    if (throws) throw Exception('el modelo falló');
    return draftFor?.call(sources) ?? draft;
  }
}

/// Genera un derivado desde un cuaderno o un elemento (F16, 12b), contra
/// SQLite real: guarda la nota, la marca y ancla cada afirmación con su
/// propia relación `extractedFrom`, todo o nada.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late NotebookRepositoryImpl notebooks;
  late OrganizeRepositoryImpl organize;
  late DerivedNoteRepositoryImpl derivedNotes;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 24, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'lib'),
      clock: () => now,
    );
    notebooks = NotebookRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'nb'),
      clock: () => now,
    );
    organize = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'org'),
      clock: () => now,
    );
    derivedNotes = DerivedNoteRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      clock: () => now,
    );
    ids = FakeIdGenerator(prefix: 'derived');
  });

  tearDown(() => db.close());

  GenerateDerivedNoteUseCase useCase(DerivedNoteGenerator generator) =>
      GenerateDerivedNoteUseCase(
        library: library,
        notebooks: notebooks,
        organize: organize,
        derivedNotes: derivedNotes,
        generator: generator,
        vectors: ItemVectorIndexImpl(database: db),
        ids: ids,
        clock: () => now,
      );

  Future<String> seedSource(String id, String content) async {
    final result = await library.save(
      KnowledgeItem(
        id: id,
        title: 'Fuente $id',
        source: Source(
          id: 'src-$id',
          kind: SourceKind.webPage,
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
            kind: RenditionKind.plainText,
            content: content,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );
    return result.getRight().toNullable()!.id;
  }

  test(
    'genera un derivado desde un cuaderno manual, con sus relaciones',
    () async {
      await seedSource('a', 'primer contenido real');
      await seedSource('b', 'segundo contenido real');
      final notebook = await notebooks.create(
        name: 'Cuaderno',
        mode: NotebookMode.manual,
      );
      await notebooks.addItem(notebookId: notebook.id, itemId: 'a');
      await notebooks.addItem(notebookId: notebook.id, itemId: 'b');

      const draft = DerivedNoteDraft(
        type: DerivedNoteType.studyGuide,
        sections: [
          DerivedSection(
            heading: 'Tema uno',
            claims: [
              DerivedClaim(
                text: 'afirmación de a',
                sourceItemId: 'a',
                sourceCharStart: 0,
                sourceCharEnd: 6,
              ),
              DerivedClaim(
                text: 'afirmación de b',
                sourceItemId: 'b',
                sourceCharStart: 7,
                sourceCharEnd: 14,
              ),
            ],
          ),
        ],
      );

      final result = await useCase(FakeDerivedNoteGenerator(draft))(
        GenerateDerivedNoteParams(
          type: DerivedNoteType.studyGuide,
          title: 'Guía de estudio',
          model: 'gemma-3n',
          notebookId: notebook.id,
        ),
      );

      final saved = result.getRight().toNullable()!;
      expect(saved.title, 'Guía de estudio');
      expect(saved.source.kind, SourceKind.manualNote);

      final rendition = saved.renditions.whereType<TextRendition>().single;
      expect(decodeContentBlocks(rendition.content), [
        const ContentBlock.heading(text: 'Tema uno', level: 2),
        const ContentBlock.bulletItem(text: 'afirmación de a'),
        const ContentBlock.bulletItem(text: 'afirmación de b'),
      ]);

      final mark = await derivedNotes.watchMark(saved.id).first;
      expect(mark!.model, 'gemma-3n');
      expect(mark.generatedAt, now);
      expect(mark.edited, isFalse);

      final relations = await organize.watchRelationsForItem(saved.id).first;
      expect(relations, hasLength(2));
      expect(
        relations.every((r) => r.direction == RelationDirection.outgoing),
        isTrue,
      );
      expect(
        relations.every((r) => r.kind == RelationKind.extractedFrom),
        isTrue,
      );
      expect(relations.map((r) => r.otherItemId), containsAll(['a', 'b']));
    },
  );

  test('genera un derivado desde un único elemento', () async {
    await seedSource('a', 'contenido de un solo elemento');

    const draft = DerivedNoteDraft(
      type: DerivedNoteType.outline,
      sections: [
        DerivedSection(
          claims: [
            DerivedClaim(
              text: 'punto principal',
              sourceItemId: 'a',
              sourceCharStart: 0,
              sourceCharEnd: 10,
            ),
          ],
        ),
      ],
    );

    final result = await useCase(FakeDerivedNoteGenerator(draft))(
      GenerateDerivedNoteParams(
        type: DerivedNoteType.outline,
        title: 'Esquema',
        model: 'gemma-3n',
        itemId: 'a',
      ),
    );

    final saved = result.getRight().toNullable()!;
    final relations = await organize.watchRelationsForItem(saved.id).first;
    expect(relations, hasLength(1));
    expect(relations.single.otherItemId, 'a');
    expect(relations.single.sourceCharStart, 0);
    expect(relations.single.sourceCharEnd, 10);
  });

  test('sin fuentes que resolver, no genera nada', () async {
    final generator = FakeDerivedNoteGenerator(
      const DerivedNoteDraft(type: DerivedNoteType.outline, sections: []),
    );

    final result = await useCase(generator)(
      GenerateDerivedNoteParams(
        type: DerivedNoteType.outline,
        title: 'Esquema',
        model: 'gemma-3n',
        itemId: 'no-existe',
      ),
    );

    expect(result.isLeft(), isTrue);
    expect(generator.sourcesSeen, isNull);
    final items = (await library.list(
      const LibraryQuery(),
    )).getRight().toNullable()!;
    expect(items, isEmpty);
  });

  test(
    'una falla del motor de inferencia se traduce a Failure, no revienta',
    () async {
      await seedSource('a', 'contenido real');
      final generator = FakeDerivedNoteGenerator(
        const DerivedNoteDraft(type: DerivedNoteType.outline, sections: []),
        throws: true,
      );

      final result = await useCase(generator)(
        GenerateDerivedNoteParams(
          type: DerivedNoteType.outline,
          title: 'Esquema',
          model: 'gemma-3n',
          itemId: 'a',
        ),
      );

      expect(result.isLeft(), isTrue);
      final items = (await library.list(
        const LibraryQuery(),
      )).getRight().toNullable()!;
      // Solo la fuente sembrada: ningún derivado se creó.
      expect(items, hasLength(1));
    },
  );

  test('un cuaderno vacío no genera nada', () async {
    final notebook = await notebooks.create(
      name: 'Vacío',
      mode: NotebookMode.manual,
    );
    final generator = FakeDerivedNoteGenerator(
      const DerivedNoteDraft(type: DerivedNoteType.outline, sections: []),
    );

    final result = await useCase(generator)(
      GenerateDerivedNoteParams(
        type: DerivedNoteType.outline,
        title: 'Esquema',
        model: 'gemma-3n',
        notebookId: notebook.id,
      ),
    );

    expect(result.isLeft(), isTrue);
  });

  test('un borrador sin nada anclado no guarda ninguna nota', () async {
    await seedSource('a', 'contenido real');

    final result =
        await useCase(
          FakeDerivedNoteGenerator(
            const DerivedNoteDraft(type: DerivedNoteType.outline, sections: []),
          ),
        )(
          GenerateDerivedNoteParams(
            type: DerivedNoteType.outline,
            title: 'Esquema',
            model: 'gemma-3n',
            itemId: 'a',
          ),
        );

    expect(result.isLeft(), isTrue);
    final items = (await library.list(
      const LibraryQuery(),
    )).getRight().toNullable()!;
    // Solo la fuente sembrada: ningún derivado se creó.
    expect(items, hasLength(1));
  });

  group('por partes (F30)', () {
    /// Una nota manual: no se fragmenta, así que no se puede citar.
    Future<void> seedNote(String id, String content) async {
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
              content: encodeContentBlocks([
                ContentBlock.paragraph(text: content),
              ]),
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );
    }

    Future<String> notebookOf(List<String> itemIds) async {
      final notebook = await notebooks.create(
        name: 'Roma',
        mode: NotebookMode.manual,
      );
      await notebooks.addItems(notebookId: notebook.id, itemIds: itemIds);
      return notebook.id;
    }

    /// Una afirmación por fuente, anclada a su principio, bajo «Roma».
    DerivedNoteDraft oneClaimPerSource(List<ChatSource> sources) =>
        DerivedNoteDraft(
          type: DerivedNoteType.studyGuide,
          sections: [
            DerivedSection(
              heading: 'Roma',
              claims: [
                for (final source in sources)
                  DerivedClaim(
                    text: 'de ${source.itemId}',
                    sourceItemId: source.itemId,
                    sourceCharStart: 0,
                    sourceCharEnd: 5,
                  ),
              ],
            ),
          ],
        );

    String longText(int i) => List.filled(30, 'Texto de la fuente $i. ').join();

    test('un cuaderno grande se lee en partes que entran, y lo de cada una '
        'se junta en una sola nota', () async {
      final ids = [
        for (var i = 0; i < 14; i++) await seedSource('s$i', longText(i)),
      ];
      final notebookId = await notebookOf(ids);
      final generator = FakeDerivedNoteGenerator(
        const DerivedNoteDraft(type: DerivedNoteType.studyGuide, sections: []),
        draftFor: oneClaimPerSource,
      );
      final progress = <(int, int)>[];

      final result = await useCase(generator)(
        GenerateDerivedNoteParams(
          type: DerivedNoteType.studyGuide,
          title: 'Guía',
          model: 'gemma-3n',
          notebookId: notebookId,
          onProgress: (read, total) => progress.add((read, total)),
        ),
      );

      expect(generator.calls, hasLength(greaterThan(1)));
      for (final call in generator.calls) {
        expect(
          call.map(derivedSourceChars).fold(0, (a, b) => a + b),
          lessThanOrEqualTo(kDerivedNotePartChars),
        );
      }
      expect(
        generator.calls.expand((c) => c).map((s) => s.itemId).toSet(),
        ids.toSet(),
      );
      final parts = generator.calls.length;
      expect(progress, [for (var i = 0; i <= parts; i++) (i, parts)]);

      final saved = result.getRight().toNullable()!;
      final blocks = decodeContentBlocks(
        saved.renditions.whereType<TextRendition>().single.content,
      );
      expect(blocks.whereType<HeadingBlock>(), hasLength(1));
      expect(blocks.whereType<BulletItemBlock>(), hasLength(14));
      final relations = await organize.watchRelationsForItem(saved.id).first;
      expect(relations, hasLength(14));
    });

    test('de un cuaderno más grande que lo que entra, como mucho las partes '
        'del tope', () async {
      final ids = [
        for (var i = 0; i < 40; i++) await seedSource('s$i', longText(i)),
      ];
      final notebookId = await notebookOf(ids);
      final generator = FakeDerivedNoteGenerator(
        const DerivedNoteDraft(type: DerivedNoteType.studyGuide, sections: []),
        draftFor: oneClaimPerSource,
      );

      final result = await useCase(generator)(
        GenerateDerivedNoteParams(
          type: DerivedNoteType.studyGuide,
          title: 'Guía',
          model: 'gemma-3n',
          notebookId: notebookId,
        ),
      );

      expect(generator.calls, hasLength(kDerivedNoteMaxParts));
      final seen = generator.calls.expand((c) => c).map((s) => s.itemId);
      expect(seen.toSet(), hasLength(seen.length));
      expect(result.isRight(), isTrue);
    });

    test(
      'las notas del cuaderno no van al modelo: no se podrían citar',
      () async {
        await seedSource(
          'fuente',
          'El Senado romano tenía trescientos miembros.',
        );
        await seedNote('nota', 'Lo que pienso del Senado.');
        final notebookId = await notebookOf(['fuente', 'nota']);
        final generator = FakeDerivedNoteGenerator(
          const DerivedNoteDraft(
            type: DerivedNoteType.studyGuide,
            sections: [],
          ),
          draftFor: oneClaimPerSource,
        );

        await useCase(generator)(
          GenerateDerivedNoteParams(
            type: DerivedNoteType.studyGuide,
            title: 'Guía',
            model: 'gemma-3n',
            notebookId: notebookId,
          ),
        );

        expect(generator.calls.single.map((s) => s.itemId), ['fuente']);
      },
    );

    test('un cuaderno con solo notas no llama al modelo', () async {
      await seedNote('nota', 'Lo que pienso del Senado.');
      final notebookId = await notebookOf(['nota']);
      final generator = FakeDerivedNoteGenerator(
        const DerivedNoteDraft(type: DerivedNoteType.studyGuide, sections: []),
      );

      final result = await useCase(generator)(
        GenerateDerivedNoteParams(
          type: DerivedNoteType.studyGuide,
          title: 'Guía',
          model: 'gemma-3n',
          notebookId: notebookId,
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(generator.calls, isEmpty);
    });
  });
}
