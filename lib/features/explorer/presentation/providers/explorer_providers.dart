import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/explorer/data/repositories/explorer_repository_impl.dart';
import 'package:sinapsis/features/explorer/domain/entities/folder.dart';
import 'package:sinapsis/features/explorer/domain/repositories/explorer_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final explorerRepositoryProvider = Provider<ExplorerRepository>((ref) {
  return ExplorerRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Todas las carpetas que existen, actualizándose solas.
///
/// `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin esto, seguiría recomponiéndose para siempre
/// aunque ninguna pantalla la esté mostrando.
final allFoldersProvider = StreamProvider.autoDispose<List<Folder>>((ref) {
  return ref.watch(explorerRepositoryProvider).watchAllFolders();
});

/// Los `id` de los elementos guardados directamente en una carpeta (`null`
/// para "sin carpeta"), actualizándose solos.
final folderItemIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String?>((ref, folderId) {
      return ref
          .watch(explorerRepositoryProvider)
          .watchItemIdsInFolder(folderId);
    });

/// En qué carpetas está un elemento, actualizándose solo. Para el selector
/// de mover/copiar.
final itemFolderIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, itemId) {
      return ref
          .watch(explorerRepositoryProvider)
          .watchFolderIdsForItem(itemId);
    });
