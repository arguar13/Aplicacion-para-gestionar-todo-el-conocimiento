import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/content_trash/data/repositories/content_trash_repository_impl.dart';
import 'package:sinapsis/features/content_trash/domain/entities/trashed_content.dart';
import 'package:sinapsis/features/content_trash/domain/repositories/content_trash_repository.dart';

/// La papelera del contenido (F30, decisión 68).
final contentTrashRepositoryProvider = Provider<ContentTrashRepository>(
  (ref) => ContentTrashRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    files: ref.watch(fileStoreProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Lo que un elemento tiene en la papelera del contenido, en vivo: lo que el
/// detalle ofrece recuperar.
final trashedContentProvider = StreamProvider.autoDispose
    .family<List<TrashedContent>, String>(
      (ref, itemId) =>
          ref.watch(contentTrashRepositoryProvider).watchOf(itemId),
    );

/// El barrido de la papelera del contenido (F30, decisión 68): borra de
/// verdad lo que venció. Se corre al abrir la app, cuando la Biblioteca
/// retoma la cola —recién ahí, con la bóveda abierta, hay base que barrer—;
/// es barato si no hay nada vencido (una consulta por un índice).
///
/// [read] es el `read` de quien llama: el de una pantalla (`WidgetRef`) o el
/// de una prueba (`ProviderContainer`). Un fallo no corta nada: el
/// repositorio ya lo registró, y el barrido de la próxima apertura lo vuelve
/// a intentar.
Future<int> sweepContentTrash(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  final result = await read(contentTrashRepositoryProvider).purgeExpired();
  return result.getOrElse((_) => 0);
}
