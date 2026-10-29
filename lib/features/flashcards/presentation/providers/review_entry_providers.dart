import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';

/// Qué se estudia, elegido en la entrada a Repasar (F31, ola 2). Dura lo que
/// la app abierta: volver de una sesión deja el mismo recorte.
final reviewEntryScopeProvider = StateProvider<StudyScope>(
  (ref) => const StudyScope.all(),
);

/// El nombre de lo que apunta un recorte: el tema, la etiqueta, el cuaderno, el
/// elemento o el recorte de Procesado. `null` mientras se lee, o si ya no
/// existe (se borró).
final studyScopeNameProvider = Provider.autoDispose
    .family<AsyncValue<String?>, StudyScope>((ref, scope) {
      final id = scope.id;
      switch (scope.kind) {
        case StudyScopeKind.all:
          return const AsyncValue.data(null);
        case StudyScopeKind.space:
          return ref
              .watch(allSpacesProvider)
              .whenData(
                (spaces) => spaces.where((s) => s.id == id).firstOrNull?.name,
              );
        case StudyScopeKind.value:
          return ref
              .watch(vocabularyValueStatsProvider)
              .whenData(
                (values) => values.where((v) => v.id == id).firstOrNull?.label,
              );
        case StudyScopeKind.notebook:
          return ref
              .watch(notebooksProvider)
              .whenData(
                (all) => all.where((n) => n.id == id).firstOrNull?.name,
              );
        case StudyScopeKind.item:
          return ref
              .watch(libraryItemProvider(id!))
              .whenData((item) => item?.title);
        case StudyScopeKind.processed:
          // El del selector de Procesado (F43): el documento, el cuaderno o el
          // tema. Uno que no se entiende no tiene nombre.
          final processed = CreationScope.parse(id!);
          if (processed == null) return const AsyncValue.data(null);
          return ref
              .watch(creationScopeSummaryProvider(processed))
              .whenData((summary) => summary.name);
      }
    });
