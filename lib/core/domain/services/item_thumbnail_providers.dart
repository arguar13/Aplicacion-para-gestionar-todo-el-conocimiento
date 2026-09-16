import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/services/item_thumbnail.dart';
import 'package:sinapsis/core/storage/pdf_first_page_renderer.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';

final _itemThumbnailResolverProvider = Provider<ItemThumbnailResolver>(
  (ref) => ItemThumbnailResolver(
    files: ref.watch(fileStoreProvider),
    renderPdfFirstPage: renderPdfFirstPageThumbnail,
  ),
);

/// La vista previa de un elemento —para su tarjeta en el grafo o su fila en
/// la biblioteca—, cacheada por Riverpod mientras esté en pantalla.
///
/// `autoDispose` y no un caché para siempre: renderizar la primera página de
/// un PDF no es gratis, y sin memoria se repetiría en cada arrastre o zoom
/// del lienzo, o cada vez que la lista se reconstruye al filtrar — pero
/// tampoco hace falta guardarlo una vez que la tarjeta ya no está a la
/// vista—. La familia se indexa por el elemento entero, no solo por su id:
/// si el original cambia —se reemplaza el archivo, se borra la copia
/// guardada— `KnowledgeItem` deja de ser igual por valor y esto trae una
/// miniatura nueva en vez de una vieja que ya no corresponde.
final itemThumbnailProvider = FutureProvider.autoDispose
    .family<ItemThumbnail, KnowledgeItem>((ref, item) {
      return ref.watch(_itemThumbnailResolverProvider).resolve(item);
    });
