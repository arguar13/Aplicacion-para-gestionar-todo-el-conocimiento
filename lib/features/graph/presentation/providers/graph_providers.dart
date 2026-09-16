import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/graph/data/services/pdfrx_first_page_renderer.dart';
import 'package:sinapsis/features/graph/domain/services/graph_node_thumbnail.dart';

final _graphNodeThumbnailResolverProvider =
    Provider<GraphNodeThumbnailResolver>(
      (ref) => GraphNodeThumbnailResolver(
        files: ref.watch(fileStoreProvider),
        renderPdfFirstPage: renderPdfFirstPageThumbnail,
      ),
    );

/// La vista previa de un elemento para su tarjeta en el grafo, cacheada por
/// Riverpod mientras esté en pantalla.
///
/// `autoDispose` y no un caché para siempre: renderizar la primera página de
/// un PDF no es gratis, y sin memoria se repetiría en cada arrastre o zoom
/// del lienzo —pero tampoco hace falta guardarlo una vez que la tarjeta ya
/// no está a la vista—. La familia se indexa por el elemento entero, no solo
/// por su id: si el original cambia —se reemplaza el archivo, se borra la
/// copia guardada— `KnowledgeItem` deja de ser igual por valor y esto trae
/// una miniatura nueva en vez de una vieja que ya no corresponde.
final graphNodeThumbnailProvider = FutureProvider.autoDispose
    .family<GraphNodeThumbnail, KnowledgeItem>((ref, item) {
      return ref.watch(_graphNodeThumbnailResolverProvider).resolve(item);
    });
