import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// El trabajo del «Contenido» de un elemento (F30): bajar lo que ofrece su
/// página y sacarle el texto a cada archivo.
///
/// Es un [Transformer] más para la cola —corre en el carril largo, con el
/// vigilante, la cancelación y el servicio de trabajo largo de siempre—, con
/// una diferencia: no lo elige el registro por la clase del elemento, sino
/// la cola cuando [hasWork] dice que queda algo. Así corre después del
/// transformador del elemento —el artículo se guarda sin esperar a las
/// fotos— y también solo, para «Bajar el resto».
abstract interface class AttachmentWork implements Transformer {
  /// Si a [itemId] le queda algo por bajar o algún archivo sin texto.
  Future<bool> hasWork(String itemId);
}
