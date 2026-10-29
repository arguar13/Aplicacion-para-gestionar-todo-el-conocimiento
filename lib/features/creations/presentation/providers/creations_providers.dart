import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/creations/data/repositories/creation_scope_resolver_impl.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_repository_impl.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_resolver.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

/// «Lo creado» de Estudiar (F43): las creaciones guardadas.
final studyCreationRepositoryProvider = Provider<StudyCreationRepository>(
  (ref) => StudyCreationRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Qué tiene cada recorte de Procesado: sus documentos, sus fuentes y sus
/// cifras. Es también quien le dice a «Para hoy» qué tarjetas cuenta un
/// recorte de Procesado (`StudyScope.processed`).
final creationScopeResolverProvider = Provider<CreationScopeResolver>(
  (ref) => CreationScopeResolverImpl(
    database: ref.watch(appDatabaseProvider),
    processed: ref.watch(processedRepositoryProvider),
    notebooks: ref.watch(notebookRepositoryProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// Lo creado de un recorte, con lo más nuevo arriba, al día.
final studyCreationsProvider = StreamProvider.autoDispose
    .family<List<StudyCreation>, CreationScope>(
      (ref, scope) =>
          ref.watch(studyCreationRepositoryProvider).watchByScope(scope),
    );

/// Una creación —viva o en la papelera—, al día: lo que mira su visor.
final studyCreationProvider = StreamProvider.autoDispose
    .family<StudyCreation?, String>(
      (ref, id) => ref.watch(studyCreationRepositoryProvider).watch(id),
    );

/// Las creaciones de la papelera, al día.
final trashedCreationsProvider =
    StreamProvider.autoDispose<List<StudyCreation>>(
      (ref) => ref.watch(studyCreationRepositoryProvider).watchTrash(),
    );

/// El nombre y las cifras de un recorte para la píldora del selector, al día.
final creationScopeSummaryProvider = StreamProvider.autoDispose
    .family<CreationScopeSummary, CreationScope>(
      (ref, scope) =>
          ref.watch(creationScopeResolverProvider).watchSummary(scope),
    );
