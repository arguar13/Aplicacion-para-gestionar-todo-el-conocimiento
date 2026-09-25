import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_option.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/data/services/distractor_sourcer_impl.dart';
import 'package:sinapsis/features/flashcards/data/services/quiz_session_summary_service_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/distractor_sourcer.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_session_summary_service.dart';
import 'package:sinapsis/features/flashcards/domain/usecases/generate_quiz_usecase.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/presentation/providers/map_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';

final flashcardRepositoryProvider = Provider<FlashcardRepository>((ref) {
  return FlashcardRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

final distractorSourcerProvider = Provider<DistractorSourcer>((ref) {
  return DistractorSourcerImpl(
    database: ref.watch(appDatabaseProvider),
    topics: ref.watch(ankiTopicResolverProvider),
    map: ref.watch(knowledgeMapRepositoryProvider),
    organize: ref.watch(organizeRepositoryProvider),
    relations: ref.watch(relationCandidateSelectorProvider),
  );
});

final generateQuizUseCaseProvider = Provider<GenerateQuizUseCase>((ref) {
  return GenerateQuizUseCase(
    library: ref.watch(libraryRepositoryProvider),
    flashcards: ref.watch(flashcardRepositoryProvider),
    generator: ref.watch(quizQuestionGeneratorProvider),
    distractorSourcer: ref.watch(distractorSourcerProvider),
  );
});

final quizSessionSummaryServiceProvider = Provider<QuizSessionSummaryService>((
  ref,
) {
  return QuizSessionSummaryServiceImpl(
    database: ref.watch(appDatabaseProvider),
    topics: ref.watch(ankiTopicResolverProvider),
  );
});

/// Las tarjetas de un elemento, actualizándose solas.
final itemFlashcardsProvider = StreamProvider.autoDispose
    .family<List<Flashcard>, String>((ref, itemId) {
      return ref.watch(flashcardRepositoryProvider).watchForItem(itemId);
    });

/// Las tarjetas que ya toca repasar, en toda la bóveda.
final dueFlashcardsProvider = StreamProvider.autoDispose<List<Flashcard>>((
  ref,
) {
  return ref.watch(flashcardRepositoryProvider).watchDue();
});

/// Cuántas hay para repasar, para la insignia del ícono en la biblioteca.
final dueFlashcardCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(flashcardRepositoryProvider).watchDueCount();
});

/// Las opciones de una tarjeta de opción múltiple, en el orden guardado.
/// Vacía para lo que no es de opción múltiple, o si la lectura falló —una
/// falla acá no debería trabar la presentación de la tarjeta, solo dejarla
/// sin opciones que mostrar—.
final flashcardOptionsProvider = FutureProvider.autoDispose
    .family<List<FlashcardOption>, String>((ref, flashcardId) async {
      final result = await ref
          .watch(flashcardRepositoryProvider)
          .optionsFor(flashcardId);
      return result.getOrElse((_) => const []);
    });
