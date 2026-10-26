import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/timeline/data/repositories/dated_event_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event.dart';
import 'package:sinapsis/features/timeline/domain/repositories/dated_event_repository.dart';

/// Los hechos fechados dentro de los documentos (F40).
final datedEventRepositoryProvider = Provider<DatedEventRepository>(
  (ref) => DatedEventRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// Los hechos fechados de un elemento, y cada cambio.
final itemDatedEventsProvider = StreamProvider.autoDispose
    .family<List<DatedEvent>, String>(
      (ref, itemId) =>
          ref.watch(datedEventRepositoryProvider).watchForItem(itemId),
    );
