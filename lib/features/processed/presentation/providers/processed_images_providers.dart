import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_image.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

/// Un tramo de las imágenes que ofrece una fuente (decisión L).
typedef SourceImagesPageKey = ({String sourceItemId, int offset, int limit});

/// Las imágenes de un tramo de una fuente, para la grilla de la hoja: se piden
/// de a tandas, a medida que se muestran. Una que falla se ve vacía —la grilla
/// sigue con las demás—.
final sourceImagesPageProvider = FutureProvider.autoDispose
    .family<List<SourceImage>, SourceImagesPageKey>((ref, key) async {
      final page = await ref
          .watch(processedRepositoryProvider)
          .sourceImages(key.sourceItemId, offset: key.offset, limit: key.limit);
      return page.getOrElse((_) => const []);
    });

/// Qué imágenes de un documento procesado pedir: todas, o un tramo.
typedef ProcessedImagesKey = ({String documentId, int offset, int? limit});

/// Las imágenes de un documento procesado —o un tramo—, en orden, y cada
/// cambio: la galería y la pantalla completa.
final processedImagesProvider = StreamProvider.autoDispose
    .family<List<ProcessedImage>, ProcessedImagesKey>(
      (ref, key) => ref
          .watch(processedRepositoryProvider)
          .watchImages(key.documentId, offset: key.offset, limit: key.limit),
    );
