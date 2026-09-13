import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final organizeRepositoryProvider = Provider<OrganizeRepository>((ref) {
  return OrganizeRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Todas las etiquetas que existen, actualizándose solas.
///
/// `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin esto, la lista de etiquetas seguiría
/// recomponiéndose para siempre aunque ninguna pantalla la esté mostrando.
final allTagsProvider = StreamProvider.autoDispose<List<Tag>>((ref) {
  return ref.watch(organizeRepositoryProvider).watchAllTags();
});

/// Con qué otros elementos está vinculado un elemento, actualizándose solo.
final itemRelationsProvider = StreamProvider.autoDispose
    .family<List<ItemRelation>, String>((ref, itemId) {
      return ref
          .watch(organizeRepositoryProvider)
          .watchRelationsForItem(itemId);
    });

/// Los resaltados de una forma de contenido, actualizándose solos.
final renditionHighlightsProvider = StreamProvider.autoDispose
    .family<List<Highlight>, String>((ref, renditionId) {
      return ref
          .watch(organizeRepositoryProvider)
          .watchHighlightsForRendition(renditionId);
    });

/// Todos los espacios que existen, actualizándose solos.
final allSpacesProvider = StreamProvider.autoDispose<List<Space>>((ref) {
  return ref.watch(organizeRepositoryProvider).watchAllSpaces();
});
