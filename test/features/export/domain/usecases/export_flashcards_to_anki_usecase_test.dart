// El doble lanza lo que el test le dé, igual que `FakeFileSaver`.
// ignore_for_file: only_throw_errors

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/services/vocabulary_tree.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/citations/data/services/fragment_locator_resolver.dart';
import 'package:sinapsis/features/citations/domain/entities/bibliography.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/repositories/bibliography_repository.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_topic_resolver.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

import '../../../../support/fake_file_saver.dart';

class _MockFlashcardRepository extends Mock implements FlashcardRepository {}

/// Sin ninguna fuente citable por defecto: la bibliografía ya se prueba
/// aparte (`bibliography_repository_impl_test.dart`).
class _FakeBibliographyRepository implements BibliographyRepository {
  Iterable<String>? requestedItemIds;
  List<BibliographySource> sources = const [];

  @override
  Future<List<BibliographySource>> sourcesOf(Iterable<String> itemIds) async {
    requestedItemIds = itemIds;
    return sources;
  }

  @override
  Future<List<BibliographySource>> sourcesMatching(LibraryQuery query) =>
      throw UnimplementedError();

  @override
  Future<List<BibliographySource>> sourcesOfSpace(String spaceId) =>
      throw UnimplementedError();

  @override
  Future<List<BibliographySource>> sourcesOfBranch(String valueId) =>
      throw UnimplementedError();

  @override
  Future<List<BibliographySource>> sourcesCitedBy(String noteId) =>
      throw UnimplementedError();
}

/// Sin ningún locator por defecto: `FragmentLocatorResolver` ya se prueba a
/// fondo, con SQLite real, en `fragment_locator_resolver_test.dart`.
class _FakeFragmentLocatorResolver implements FragmentLocatorResolver {
  List<({String key, String itemId, int charOffset})>? requestedLocations;
  Map<String, CitationLocator> locators = const {};

  @override
  Future<Map<String, CitationLocator>> locateMany(
    List<({String key, String itemId, int charOffset})> requests,
  ) async {
    requestedLocations = requests;
    return locators;
  }

  @override
  Future<CitationLocator?> locate({
    required String itemId,
    required String renditionId,
    required int charOffset,
  }) => throw UnimplementedError();
}

/// Devuelve bytes fijos en vez de armar un `.apkg` de verdad: lo que prueba
/// este archivo es que el caso de uso encadena bien el repositorio, la
/// resolución de temas, el armador y el guardado, no el formato del
/// paquete —eso ya lo cubre `anki_package_builder_test.dart`— ni el árbol
/// de Temas —eso lo cubre `anki_deck_path_test.dart`—.
class _FakeAnkiDeckBuilder implements AnkiDeckBuilder {
  /// Se activa a mitad de una prueba, después de armar el resto del
  /// escenario — igual que `FakeFileSaver.error`.
  Object? error;
  List<AnkiCardExport>? receivedCards;

  @override
  Future<Uint8List> build(List<AnkiCardExport> cards) async {
    if (error != null) throw error!;
    receivedCards = cards;
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// Sin ningún tema para nadie, por defecto: el árbol de Temas ya se prueba
/// aparte.
class _FakeAnkiTopicResolver implements AnkiTopicResolver {
  Set<String>? requestedItemIds;

  @override
  Future<AnkiTopicResolution> resolve(Set<String> itemIds) async {
    requestedItemIds = itemIds;
    return AnkiTopicResolution(
      tree: VocabularyTree(const []),
      labelOf: const {},
      firstTopicByItem: {for (final id in itemIds) id: null},
    );
  }
}

void main() {
  late _MockFlashcardRepository repository;
  late _FakeAnkiTopicResolver topics;
  late _FakeBibliographyRepository bibliography;
  late _FakeFragmentLocatorResolver locator;
  late _FakeAnkiDeckBuilder builder;
  late FakeFileSaver saver;

  setUpAll(() {
    registerFallbackValue(
      Flashcard(
        id: 'fallback',
        itemId: 'fallback',
        front: 'f',
        back: 'b',
        dueAt: DateTime(2024),
        createdAt: DateTime(2024),
      ),
    );
  });

  setUp(() {
    repository = _MockFlashcardRepository();
    topics = _FakeAnkiTopicResolver();
    bibliography = _FakeBibliographyRepository();
    locator = _FakeFragmentLocatorResolver();
    builder = _FakeAnkiDeckBuilder();
    saver = FakeFileSaver();
    when(
      () => repository.markExported(any()),
    ).thenAnswer((_) async => right(unit));
  });

  ExportFlashcardsToAnkiUseCase useCase() => ExportFlashcardsToAnkiUseCase(
    flashcards: repository,
    topics: topics,
    bibliography: bibliography,
    locator: locator,
    citationStyle: kReferenceStyles.defaultStyle,
    citationLanguage: CitationLanguage.es,
    builder: builder,
    saver: saver,
  );

  Flashcard sampleCard() => Flashcard(
    id: 'c1',
    itemId: 'item-1',
    front: 'Pregunta',
    back: 'Respuesta',
    dueAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  test('arma el mazo con todas las tarjetas y lo guarda', () async {
    final cards = [sampleCard()];
    when(() => repository.getAll()).thenAnswer((_) async => right(cards));

    final result = await useCase()(
      const ExportFlashcardsToAnkiParams(exportAll: true),
    );

    expect(result.isRight(), isTrue);
    expect(builder.receivedCards?.map((e) => e.card).toList(), cards);
    // Sin tema asignado: va al subdeck fijo de F17, D1.
    expect(builder.receivedCards!.single.deckPath, 'Sinapsis::Sin tema');
    expect(topics.requestedItemIds, {'item-1'});
    expect(bibliography.requestedItemIds, {'item-1'});
    // Sin ninguna fuente citable (la fake no trae ninguna): sin procedencia.
    expect(builder.receivedCards!.single.provenance, isNull);
    expect(saver.savedFileName, 'sinapsis.apkg');
    expect(saver.savedBytes, isNotNull);
  });

  group('procedencia en el reverso (F17, commit 3)', () {
    test(
      'con una fuente citable, resuelve la cita antes del builder',
      () async {
        final cards = [sampleCard()];
        when(() => repository.getAll()).thenAnswer((_) async => right(cards));
        bibliography.sources = const [
          BibliographySource(
            itemId: 'item-1',
            source: CitationSource(title: 'La fuente'),
          ),
        ];

        final result = await useCase()(
          const ExportFlashcardsToAnkiParams(exportAll: true),
        );

        expect(result.isRight(), isTrue);
        expect(builder.receivedCards!.single.provenance, isNotNull);
        expect(builder.receivedCards!.single.provenance, isNotEmpty);
      },
    );

    test(
      'con un rango real, pide su locator por lotes, no por tarjeta',
      () async {
        final withRange = Flashcard(
          id: 'c1',
          itemId: 'item-1',
          front: 'Pregunta',
          back: 'Respuesta',
          dueAt: DateTime(2024),
          createdAt: DateTime(2024),
          sourceCharStart: 40,
          sourceCharEnd: 60,
        );
        when(
          () => repository.getAll(),
        ).thenAnswer((_) async => right([withRange, sampleCard()]));
        bibliography.sources = const [
          BibliographySource(
            itemId: 'item-1',
            source: CitationSource(title: 'La fuente'),
          ),
        ];
        locator.locators = {'c1': const CitationLocator.page('4')};

        final result = await useCase()(
          const ExportFlashcardsToAnkiParams(exportAll: true),
        );

        expect(result.isRight(), isTrue);
        // Solo la tarjeta con rango pide locator: la otra tarjeta comparte
        // itemId pero no tiene de dónde sacar un offset.
        expect(locator.requestedLocations, hasLength(1));
        expect(locator.requestedLocations!.single.key, 'c1');
        expect(locator.requestedLocations!.single.charOffset, 40);
      },
    );

    test('sin ninguna fuente citable, el reverso queda sin cambios', () async {
      final cards = [sampleCard()];
      when(() => repository.getAll()).thenAnswer((_) async => right(cards));

      final result = await useCase()(
        const ExportFlashcardsToAnkiParams(exportAll: true),
      );

      expect(result.isRight(), isTrue);
      expect(builder.receivedCards!.single.provenance, isNull);
    });
  });

  test('si el repositorio falla, no llega a armar nada', () async {
    when(
      () => repository.getAll(),
    ).thenAnswer((_) async => left(const Failure.unexpected(message: 'x')));

    final result = await useCase()(
      const ExportFlashcardsToAnkiParams(exportAll: true),
    );

    expect(result.isLeft(), isTrue);
    expect(builder.receivedCards, isNull);
    expect(saver.savedFileName, isNull);
  });

  test('si armar el paquete falla, es un fallo de exportación', () async {
    when(() => repository.getAll()).thenAnswer((_) async => right([]));
    builder.error = StateError('no se pudo armar el .apkg');

    final result = await useCase()(
      const ExportFlashcardsToAnkiParams(exportAll: true),
    );

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ExportFailedFailure>());
  });

  group('incremental (F17, D4)', () {
    test('por defecto, pide solo lo que nunca se exportó', () async {
      final cards = [sampleCard()];
      when(
        () => repository.getPendingExport(),
      ).thenAnswer((_) async => right(cards));

      final result = await useCase()(const ExportFlashcardsToAnkiParams());

      expect(result.isRight(), isTrue);
      expect(builder.receivedCards?.map((e) => e.card).toList(), cards);
      verifyNever(() => repository.getAll());
    });

    test('con exportAll, pide todas, sin filtrar por lo nuevo', () async {
      final cards = [sampleCard()];
      when(() => repository.getAll()).thenAnswer((_) async => right(cards));

      final result = await useCase()(
        const ExportFlashcardsToAnkiParams(exportAll: true),
      );

      expect(result.isRight(), isTrue);
      expect(builder.receivedCards?.map((e) => e.card).toList(), cards);
      verifyNever(() => repository.getPendingExport());
    });

    test(
      'al guardar con éxito, marca exportadas justo las tarjetas que iban',
      () async {
        final cards = [sampleCard()];
        when(
          () => repository.getPendingExport(),
        ).thenAnswer((_) async => right(cards));

        final result = await useCase()(const ExportFlashcardsToAnkiParams());

        expect(result.isRight(), isTrue);
        verify(() => repository.markExported({'c1'})).called(1);
      },
    );

    test(
      'un mazo vacío no tiene nada que marcar, pero igual arma el archivo',
      () async {
        when(
          () => repository.getPendingExport(),
        ).thenAnswer((_) async => right(const []));

        final result = await useCase()(const ExportFlashcardsToAnkiParams());

        expect(result.isRight(), isTrue);
        expect(saver.savedFileName, 'sinapsis.apkg');
        verify(() => repository.markExported(const {})).called(1);
      },
    );

    test(
      'si falla marcarlas, es un fallo, aunque el archivo ya se guardó',
      () async {
        final cards = [sampleCard()];
        when(
          () => repository.getPendingExport(),
        ).thenAnswer((_) async => right(cards));
        when(
          () => repository.markExported(any()),
        ).thenAnswer((_) async => left(const Failure.unexpected(message: 'x')));

        final result = await useCase()(const ExportFlashcardsToAnkiParams());

        expect(result.isLeft(), isTrue);
        // El archivo ya se guardó antes de intentar marcar: un fallo acá no
        // lo deshace, solo se avisa.
        expect(saver.savedFileName, 'sinapsis.apkg');
      },
    );
  });
}
