import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';

final fileViewerResolverProvider = Provider<FileViewerResolver>((ref) {
  return FileViewerResolver(files: ref.watch(fileStoreProvider));
});

/// Qué visor le corresponde al archivo original de un elemento, cacheado
/// por Riverpod mientras esté en pantalla.
///
/// `autoDispose` y no un caché para siempre: reconocer el formato de un
/// documento implica leer el comienzo del archivo, y no hace falta
/// guardarlo una vez que el detalle ya no está a la vista. La familia se
/// indexa por el elemento entero, no solo por su id, por el mismo motivo
/// que `itemThumbnailProvider`: si el original cambia, `KnowledgeItem` deja
/// de ser igual por valor y esto vuelve a resolver en vez de quedarse con
/// un resultado viejo.
final resolvedFileViewerProvider = FutureProvider.autoDispose
    .family<ResolvedViewer, KnowledgeItem>((ref, item) {
      return ref.watch(fileViewerResolverProvider).resolve(item);
    });
