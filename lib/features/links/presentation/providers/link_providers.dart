import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/links/data/repositories/link_repository_impl.dart';
import 'package:sinapsis/features/links/domain/entities/broken_link.dart';
import 'package:sinapsis/features/links/domain/repositories/link_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final linkRepositoryProvider = Provider<LinkRepository>((ref) {
  return LinkRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    library: ref.watch(libraryRepositoryProvider),
    inbox: ref.watch(inboxRepositoryProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Los `[[Título]]` sin nota de toda la bóveda, agrupados por título y
/// actualizándose solos.
///
/// `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin esto seguiría recomponiéndose aunque ninguna
/// pantalla lo esté mostrando.
final brokenLinksProvider = StreamProvider.autoDispose<List<BrokenLink>>((ref) {
  return ref.watch(linkRepositoryProvider).watchBrokenLinks();
});
