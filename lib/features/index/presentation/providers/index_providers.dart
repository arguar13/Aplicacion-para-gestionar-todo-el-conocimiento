import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/index/data/repositories/index_repository_impl.dart';
import 'package:sinapsis/features/index/domain/repositories/index_repository.dart';

/// Lo que la pantalla del Índice (F46) lee y escribe.
final indexRepositoryProvider = Provider<IndexRepository>(
  (ref) => IndexRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);
