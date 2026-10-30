import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_coverage_reader_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_coverage_reader.dart';
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

/// Si hay alguna tarjeta, le toque o no (F30): para «Practicar igual».
final hasFlashcardsProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(flashcardCoverageReaderProvider).watchHasCards(),
);

/// Los documentos de un cuaderno que pueden tener tarjetas, y cuáles ya tienen
/// (F30), para «Llenar con IA»; o el fallo, para decirlo. Lo que tiene hoy
/// (`NotebookRepository.memberIds`, sus documentos procesados): uno por
/// consulta trae lo que el cuaderno tiene ahora.
final notebookFlashcardCoverageProvider = FutureProvider.autoDispose
    .family<Either<Failure, FlashcardCoverage>, String>((
      ref,
      notebookId,
    ) async {
      final reader = ref.watch(flashcardCoverageReaderProvider);
      final ids = await ref
          .watch(notebookRepositoryProvider)
          .memberIds(notebookId);
      return ids.match((failure) async => left(failure), reader.coverageOf);
    });
