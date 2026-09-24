import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';

/// Cascada de inyección de los cuadernos (F16).
final notebookRepositoryProvider = Provider<NotebookRepository>((ref) {
  return NotebookRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Los cuadernos, actualizándose solos.
final notebooksProvider = StreamProvider.autoDispose<List<Notebook>>((ref) {
  return ref.watch(notebookRepositoryProvider).watchAll();
});

/// Uno solo, para la pantalla de detalle.
final notebookByIdProvider = StreamProvider.autoDispose
    .family<Notebook?, String>((ref, id) {
      return ref.watch(notebookRepositoryProvider).watchById(id);
    });

/// Los ids de un cuaderno manual —ver `NotebookRepository.watchItemIds`—.
final notebookItemIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, notebookId) {
      return ref.watch(notebookRepositoryProvider).watchItemIds(notebookId);
    });
