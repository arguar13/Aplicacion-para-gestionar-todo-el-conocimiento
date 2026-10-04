import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_coverage_reader_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';

/// Qué elementos pueden tener tarjetas y cuáles ya tienen (F30).
final flashcardCoverageReaderProvider = Provider<FlashcardCoverageReader>(
  (ref) => FlashcardCoverageReaderImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// Cuántos elementos podrían tener tarjetas y no tienen ninguna (F30), para
/// el Repasar vacío.
final itemsWithoutCardsCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(flashcardCoverageReaderProvider).watchWithoutCardsCount(),
);

/// Si el modelo de lenguaje está bajado: sin él no hay tarjetas con IA.
final languageModelReadyProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(chatModelManagerProvider).isReady(),
);

/// De qué elementos se piden las tarjetas con IA (F30): toda la biblioteca,
/// un tema, una etiqueta o un cuaderno.
enum AiFlashcardsScopeKind { library, space, tag, notebook }

/// El alcance elegido: el tipo y, salvo en toda la biblioteca, cuál.
@immutable
class AiFlashcardsScope {
  const AiFlashcardsScope(this.kind, String this.id)
    : assert(
        kind != AiFlashcardsScopeKind.library,
        'Toda la biblioteca no elige ninguno.',
      );

  const AiFlashcardsScope.library()
    : kind = AiFlashcardsScopeKind.library,
      id = null;

  final AiFlashcardsScopeKind kind;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is AiFlashcardsScope && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Los elementos de un alcance que pueden tener tarjetas, y cuáles ya tienen; o
/// el fallo, para decirlo. Un tema o una etiqueta, con los mismos filtros
/// que la Biblioteca (`LibraryRepository.matchingIds`); un cuaderno, con lo
/// que es hoy (`NotebookRepository.resolveQuery`): uno por consulta trae lo
/// que la consulta encuentra ahora.
final aiFlashcardsCoverageProvider = FutureProvider.autoDispose
    .family<Either<Failure, FlashcardCoverage>, AiFlashcardsScope>((
      ref,
      scope,
    ) async {
      final reader = ref.watch(flashcardCoverageReaderProvider);
      final library = ref.watch(libraryRepositoryProvider);
      final query = switch (scope.kind) {
        AiFlashcardsScopeKind.library => null,
        AiFlashcardsScopeKind.space => LibraryQuery(spaceId: scope.id),
        AiFlashcardsScopeKind.tag => LibraryQuery(tagIds: {scope.id!}),
        AiFlashcardsScopeKind.notebook =>
          await ref.watch(notebookRepositoryProvider).resolveQuery(scope.id!),
      };
      if (query == null) return reader.coverageOf(null);
      final ids = await library.matchingIds(query);
      return ids.match((failure) async => left(failure), reader.coverageOf);
    });
