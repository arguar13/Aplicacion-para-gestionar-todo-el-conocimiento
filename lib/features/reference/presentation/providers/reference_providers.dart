import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_fuzzy_match_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_identity_repository_impl.dart';
import 'package:sinapsis/features/reference/data/repositories/reference_repository_impl.dart';
import 'package:sinapsis/features/reference/data/usecases/generate_metadata_suggestion_usecase.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_fuzzy_match_repository.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_identity_repository.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_repository.dart';
import 'package:sinapsis/features/reference/domain/services/metadata_suggestion_generator.dart';
import 'package:sinapsis/features/reference/domain/usecases/attach_reference_file_usecase.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_reference_entry_usecase.dart';
import 'package:sinapsis/features/reference/domain/usecases/import_references_file_usecase.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';

/// Cascada de inyección del feature: la presentación depende de este
/// repositorio y nunca de la base.
final referenceRepositoryProvider = Provider<ReferenceRepository>(
  (ref) => ReferenceRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// La referencia de una fuente, actualizándose sola.
///
/// `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin esto seguiría recomponiéndose con la pantalla
/// cerrada.
final referenceProvider = StreamProvider.autoDispose
    .family<ReferenceData, String>(
      (ref, itemId) => ref.watch(referenceRepositoryProvider).watch(itemId),
    );

/// Genera la sugerencia de referencia al capturar (F15, D12) —enganchado en
/// `ProcessItemUseCase`— y también al abrir el formulario, sobre la misma
/// fuente ya guardada, para las que se capturaron antes de que este generador
/// existiera.
final metadataSuggestionGeneratorProvider =
    Provider<MetadataSuggestionGenerator>(
      (ref) => GenerateMetadataSuggestionUseCase(
        files: ref.watch(fileStoreProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      ),
    );

/// Quién ya tiene cada DOI/ISBN/URL de la bóveda, para importar sin duplicar
/// (F15, D9).
final referenceIdentityRepositoryProvider =
    Provider<ReferenceIdentityRepository>(
      (ref) => ReferenceIdentityRepositoryImpl(ref.watch(appDatabaseProvider)),
    );

/// La coincidencia difusa —título, año, primer autor— al importar sin
/// identificador exacto (F15, D9).
final referenceFuzzyMatchRepositoryProvider =
    Provider<ReferenceFuzzyMatchRepository>(
      (ref) =>
          ReferenceFuzzyMatchRepositoryImpl(ref.watch(appDatabaseProvider)),
    );

/// Crea o completa UNA fuente al importar (F15, D9).
final importReferenceEntryUseCaseProvider =
    Provider<ImportReferenceEntryUseCase>(
      (ref) => ImportReferenceEntryUseCase(
        library: ref.watch(libraryRepositoryProvider),
        reference: ref.watch(referenceRepositoryProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        ids: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
      ),
    );

/// Vincula el PDF que trae un `.bib`/`.ris` a la fuente que se acaba de
/// crear (F15, D14).
final attachReferenceFileUseCaseProvider = Provider<AttachReferenceFileUseCase>(
  (ref) => AttachReferenceFileUseCase(
    library: ref.watch(libraryRepositoryProvider),
    files: ref.watch(fileStoreProvider),
  ),
);

/// Importa un `.bib`/`.ris` entero, con su informe (F15, D15.3).
final importReferencesFileUseCaseProvider =
    Provider<ImportReferencesFileUseCase>(
      (ref) => ImportReferencesFileUseCase(
        identity: ref.watch(referenceIdentityRepositoryProvider),
        fuzzyMatch: ref.watch(referenceFuzzyMatchRepositoryProvider),
        importEntry: ref.watch(importReferenceEntryUseCaseProvider),
        attachFile: ref.watch(attachReferenceFileUseCaseProvider),
      ),
    );
