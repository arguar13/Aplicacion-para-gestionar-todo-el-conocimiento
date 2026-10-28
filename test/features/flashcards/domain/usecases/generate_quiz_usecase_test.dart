import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/services/distractor_sourcer.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_question_generator.dart';
import 'package:sinapsis/features/flashcards/domain/usecases/generate_quiz_usecase.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Un [QuizQuestionGenerator] de prueba: devuelve exactamente los borradores
/// que se le den, sin tocar el modelo de lenguaje —eso se prueba en
/// `gemma_chat_model`, acá lo que importa es qué hace el caso de uso con
/// borradores YA generados—.
class FakeQuizQuestionGenerator implements QuizQuestionGenerator {
  FakeQuizQuestionGenerator(this.drafts, {this.throws = false});

  List<FlashcardDraft> drafts;
  final bool throws;

  @override
  Future<List<FlashcardDraft>> generateQuizQuestions({
    required String content,
    int count = 5,
  }) async {
    if (throws) throw Exception('el modelo falló');
    return drafts;
  }
}

/// Un [DistractorSourcer] de prueba: devuelve una lista fija de candidatos
/// por elemento semilla, sin tocar la bóveda —eso ya se prueba aparte en
/// `distractor_sourcer_impl_test.dart`—.
class FakeDistractorSourcer implements DistractorSourcer {
  FakeDistractorSourcer(this.byItem);

  final Map<String, List<DistractorCandidate>> byItem;

  @override
  Future<List<DistractorCandidate>> sourceDistractors({
    required String seedItemId,
    required String excludeContent,
    int count = 3,
  }) async => byItem[seedItemId] ?? const [];
}

DistractorCandidate _candidate(String itemId, String content) =>
    DistractorCandidate(
      itemId: itemId,
      content: content,
      sourceChunkId: 'chunk-$itemId',
      sourceCharStart: 0,
      sourceCharEnd: content.length,
    );

/// Genera preguntas de quiz y las guarda (F20, 20.5, decisión D): contra
/// SQLite real para `LibraryRepository`/`FlashcardRepository`, con dobles
/// para las dos piezas de IA/bóveda que ya se prueban aparte.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late FlashcardRepositoryImpl flashcards;
  late ProcessedRepositoryImpl processed;

  const text = 'La Tierra es redonda. Orbita alrededor del Sol.';
  final now = DateTime(2026, 9, 25, 14);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'lib'),
      clock: () => now,
    );
    flashcards = FlashcardRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: FakeIdGenerator(prefix: 'fc'),
      clock: () => now,
    );
    processed = ProcessedRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
      ids: FakeIdGenerator(prefix: 'parte'),
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem() async {
    final item = KnowledgeItem(
      id: 'seed',
      title: 'La Tierra',
      source: Source(
        id: 'src-seed',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/tierra',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: 'rend-seed',
          itemId: 'seed',
          kind: RenditionKind.markdown,
          content: text,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    final saved = await library.save(item);
    return saved.getRight().toNullable()!;
  }

  GenerateQuizUseCase useCaseWith({
    required List<FlashcardDraft> drafts,
    Map<String, List<DistractorCandidate>> distractorsByItem = const {},
  }) => GenerateQuizUseCase(
    library: library,
    flashcards: flashcards,
    generator: FakeQuizQuestionGenerator(drafts),
    distractorSourcer: FakeDistractorSourcer(distractorsByItem),
    processed: processed,
  );

  group('generate', () {
    test(
      'una pregunta cuya cita ancla, con distractores reales, se ofrece',
      () async {
        final item = await seedItem();
        final useCase = useCaseWith(
          drafts: const [
            FlashcardDraft(
              front: '¿Qué órbita la Tierra?',
              back: 'el Sol',
              quote: 'Orbita alrededor del Sol.',
            ),
          ],
          distractorsByItem: {
            'seed': [_candidate('other', 'la Luna')],
          },
        );

        final result = await useCase.generate(item: item);

        final questions = result.getRight().toNullable()!;
        expect(questions, hasLength(1));
        expect(questions.single.question, '¿Qué órbita la Tierra?');
        expect(questions.single.correctAnswer, 'el Sol');
        expect(questions.single.correctSourceItemId, 'seed');
        expect(questions.single.distractors, hasLength(1));
      },
    );

    test('una cita que no aparece en el texto real descarta la pregunta —mejor '
        'ninguna que una sin chunk real', () async {
      final item = await seedItem();
      final useCase = useCaseWith(
        drafts: const [
          FlashcardDraft(
            front: '¿Algo?',
            back: 'algo',
            quote: 'esto no está en el texto de la fuente',
          ),
        ],
        distractorsByItem: {
          'seed': [_candidate('other', 'un distractor')],
        },
      );

      final result = await useCase.generate(item: item);

      expect(result.getRight().toNullable(), isEmpty);
    });

    test('sin ningún distractor real, la pregunta se descarta entera —nunca '
        'se completa con nada inventado', () async {
      final item = await seedItem();
      final useCase = useCaseWith(
        drafts: const [
          FlashcardDraft(
            front: '¿Qué órbita la Tierra?',
            back: 'el Sol',
            quote: 'Orbita alrededor del Sol.',
          ),
        ],
      );

      final result = await useCase.generate(item: item);

      expect(result.getRight().toNullable(), isEmpty);
    });

    test('un elemento sin texto no genera nada y avisa', () async {
      final saved = await library.save(
        KnowledgeItem(
          id: 'vacio',
          title: 'Vacío',
          source: Source(
            id: 'src-vacio',
            kind: SourceKind.manualNote,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final item = saved.getRight().toNullable()!;
      final useCase = useCaseWith(drafts: const []);

      final result = await useCase.generate(item: item);

      expect(result.isLeft(), isTrue);
    });

    test('si el modelo falla, se informa el fallo en vez de romper', () async {
      final item = await seedItem();
      final useCase = GenerateQuizUseCase(
        library: library,
        flashcards: flashcards,
        generator: FakeQuizQuestionGenerator(const [], throws: true),
        distractorSourcer: FakeDistractorSourcer(const {}),
        processed: processed,
      );

      final result = await useCase.generate(item: item);

      expect(result.isLeft(), isTrue);
    });
  });

  group('de un documento procesado (F41, decisión K)', () {
    /// El procesado de la fuente `seed`, con lo que se pida —su texto entero
    /// copiado tal cual y una nota escrita, si no—, como elemento.
    Future<KnowledgeItem> processedOf([
      Map<ProcessedSection, SectionEdit>? edits,
    ]) async {
      await seedItem();
      final result = await ProcessSourceUseCase(processed)(
        'seed',
        edits ??
            {
              ProcessedSection.text: SectionEdit.add(
                const SectionInput.fromSource(),
              ),
              ProcessedSection.notes: SectionEdit.add(
                const SectionInput.drafts([
                  ProcessedDraft.written('Mi nota: Marte es rojo.'),
                ]),
              ),
            },
      );
      expect(result.isRight(), isTrue, reason: '$result');
      final item = await library.findById(processedDocumentIdFor('seed'));
      return item.getRight().toNullable()!;
    }

    test(
      'sale del texto de sus tarjetas, y la respuesta se ancla en la '
      'fuente, con los distractores de otros elementos que no sean ella',
      () async {
        final item = await processedOf();
        final generator = FakeQuizQuestionGenerator(const [
          FlashcardDraft(
            front: '¿Qué órbita la Tierra?',
            back: 'el Sol',
            quote: 'Orbita alrededor del Sol.',
          ),
        ]);
        final useCase = GenerateQuizUseCase(
          library: library,
          flashcards: flashcards,
          generator: generator,
          distractorSourcer: FakeDistractorSourcer({
            'seed': [_candidate('other', 'la Luna')],
          }),
          processed: processed,
        );

        final result = await useCase.generate(item: item);

        final question = result.getRight().toNullable()!.single;
        expect(question.correctSourceItemId, 'seed');
        expect(
          text.substring(
            question.correctSourceCharStart,
            question.correctSourceCharEnd,
          ),
          'Orbita alrededor del Sol.',
        );
        expect(question.distractors.single.itemId, 'other');
      },
    );

    test('una respuesta que sale de lo escrito a mano no se puede anclar en '
        'la fuente: la pregunta se descarta', () async {
      final item = await processedOf();
      final useCase = useCaseWith(
        drafts: const [
          FlashcardDraft(
            front: '¿De qué color es Marte?',
            back: 'rojo',
            quote: 'Marte es rojo.',
          ),
        ],
        distractorsByItem: {
          'seed': [_candidate('other', 'azul')],
        },
      );

      final result = await useCase.generate(item: item);

      expect(result.getRight().toNullable(), isEmpty);
    });
  });

  group('save', () {
    test('guarda cada pregunta confirmada como una tarjeta de opción múltiple, '
        'con la correcta y sus distractores anclados', () async {
      final item = await seedItem();
      final other = await library.save(
        KnowledgeItem(
          id: 'other',
          title: 'La Luna',
          source: Source(
            id: 'src-other',
            kind: SourceKind.webPage,
            capturedAt: now,
            url: 'https://ejemplo.org/luna',
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-other',
              itemId: 'other',
              kind: RenditionKind.markdown,
              content: 'La Luna orbita la Tierra.',
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );
      expect(other.isRight(), isTrue);

      final useCase = useCaseWith(drafts: const []);

      final saved = await useCase.save(
        itemId: item.id,
        confirmed: [
          QuizQuestionResult(
            question: '¿Qué órbita la Tierra?',
            correctAnswer: 'el Sol',
            correctSourceItemId: item.id,
            correctSourceCharStart: 0,
            correctSourceCharEnd: 4,
            distractors: [_candidate('other', 'la Luna')],
          ),
        ],
      );

      final cards = saved.getRight().toNullable()!;
      expect(cards, hasLength(1));

      final options = (await flashcards.optionsFor(
        cards.single.id,
      )).getRight().toNullable()!;
      expect(options.map((o) => o.content), ['el Sol', 'la Luna']);
      expect(options[0].isCorrect, isTrue);
      expect(options[0].sourceItemId, item.id);
      expect(options[1].isCorrect, isFalse);
      expect(options[1].sourceChunkId, isNotNull);
    });

    test('la respuesta correcta se ancla en su propio elemento —la fuente de '
        'un procesado—, no en el de la tarjeta', () async {
      final item = await seedItem();
      final owner = await library.save(
        KnowledgeItem(
          id: 'procesado',
          title: 'La Tierra',
          source: Source(
            id: 'procesado',
            kind: SourceKind.manualNote,
            capturedAt: now,
          ),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final useCase = useCaseWith(drafts: const []);

      final saved = await useCase.save(
        itemId: owner.getRight().toNullable()!.id,
        confirmed: [
          QuizQuestionResult(
            question: '¿Qué órbita la Tierra?',
            correctAnswer: 'el Sol',
            correctSourceItemId: item.id,
            correctSourceCharStart: 22,
            correctSourceCharEnd: 47,
            distractors: [_candidate('seed', 'la Luna')],
          ),
        ],
      );

      final card = saved.getRight().toNullable()!.single;
      expect(card.itemId, 'procesado');
      final options = (await flashcards.optionsFor(
        card.id,
      )).getRight().toNullable()!;
      expect(options.first.sourceItemId, 'seed');
      expect(options.first.sourceCharStart, 22);
    });

    test('una lista vacía no guarda nada ni falla', () async {
      final item = await seedItem();
      final useCase = useCaseWith(drafts: const []);

      final result = await useCase.save(itemId: item.id, confirmed: const []);

      expect(result.getRight().toNullable(), isEmpty);
      expect(await db.select(db.flashcards).get(), isEmpty);
    });

    test('todo o nada: si una pregunta de varias falla al guardar, ninguna '
        'queda a medias', () async {
      final item = await seedItem();
      final useCase = useCaseWith(drafts: const []);

      // La segunda pregunta trae una sola opción —menos de dos, la
      // guarda rechaza sin escribir nada—: sirve para comprobar que la
      // primera, ya válida, tampoco queda guardada.
      final result = await useCase.save(
        itemId: item.id,
        confirmed: [
          QuizQuestionResult(
            question: 'Primera, válida',
            correctAnswer: 'el Sol',
            correctSourceItemId: item.id,
            correctSourceCharStart: 0,
            correctSourceCharEnd: 4,
            distractors: [_candidate('other', 'la Luna')],
          ),
          const QuizQuestionResult(
            question: 'Segunda, sin distractores',
            correctAnswer: 'algo',
            correctSourceItemId: 'seed',
            correctSourceCharStart: 0,
            correctSourceCharEnd: 4,
            distractors: [],
          ),
        ],
      );

      expect(result.isLeft(), isTrue);
      expect(await db.select(db.flashcards).get(), isEmpty);
    });
  });
}
