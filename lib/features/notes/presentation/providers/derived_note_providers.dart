import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notes/data/repositories/derived_note_repository_impl.dart';
import 'package:sinapsis/features/notes/domain/entities/derived_note_mark.dart';
import 'package:sinapsis/features/notes/domain/repositories/derived_note_repository.dart';
import 'package:sinapsis/features/notes/domain/usecases/generate_derived_note_usecase.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

final derivedNoteRepositoryProvider = Provider<DerivedNoteRepository>((ref) {
  return DerivedNoteRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

/// La marca de procedencia de una nota, actualizándose sola. `null` si no es
/// un derivado.
final derivedNoteMarkProvider = StreamProvider.autoDispose
    .family<DerivedNoteMark?, String>((ref, itemId) {
      return ref.watch(derivedNoteRepositoryProvider).watchMark(itemId);
    });

final generateDerivedNoteUseCaseProvider =
    Provider.autoDispose<GenerateDerivedNoteUseCase>((ref) {
      return GenerateDerivedNoteUseCase(
        library: ref.watch(libraryRepositoryProvider),
        notebooks: ref.watch(notebookRepositoryProvider),
        organize: ref.watch(organizeRepositoryProvider),
        derivedNotes: ref.watch(derivedNoteRepositoryProvider),
        generator: ref.watch(derivedNoteGeneratorProvider),
        ids: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
      );
    });
