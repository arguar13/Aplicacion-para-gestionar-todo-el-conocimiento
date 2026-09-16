import 'package:sinapsis/core/domain/services/item_thumbnail_providers.dart';

/// La vista previa de un elemento para su tarjeta en el grafo.
///
/// Alias del provider compartido con la biblioteca (ver
/// `item_thumbnail_providers.dart`): las dos pantallas necesitan la misma
/// portada resuelta de la misma forma, así que comparten también la
/// instancia cacheada por Riverpod en vez de resolverla dos veces.
final graphNodeThumbnailProvider = itemThumbnailProvider;
