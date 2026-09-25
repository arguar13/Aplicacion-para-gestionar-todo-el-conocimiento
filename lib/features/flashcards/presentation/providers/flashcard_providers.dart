import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/data/services/distractor_sourcer_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/distractor_sourcer.dart';
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
