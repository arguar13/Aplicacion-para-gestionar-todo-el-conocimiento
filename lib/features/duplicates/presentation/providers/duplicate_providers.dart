import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/duplicates/data/repositories/duplicate_provenance_repository_impl.dart';
import 'package:sinapsis/features/duplicates/domain/entities/merged_provenance.dart';
import 'package:sinapsis/features/duplicates/domain/repositories/duplicate_provenance_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final duplicateProvenanceRepositoryProvider =
    Provider<DuplicateProvenanceRepository>((ref) {
      return DuplicateProvenanceRepositoryImpl(
        database: ref.watch(appDatabaseProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });

/// Qué otras procedencias absorbió un elemento al fusionarse con
/// duplicados — vacío para la inmensa mayoría, que nunca se fusionó con
/// nada.
final mergedProvenancesForItemProvider = StreamProvider.autoDispose
    .family<List<MergedProvenance>, String>((ref, itemId) {
      return ref
          .watch(duplicateProvenanceRepositoryProvider)
          .watchMergedProvenancesForItem(itemId);
    });
