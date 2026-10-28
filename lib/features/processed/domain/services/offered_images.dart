import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';

/// Si el archivo [path] de una fuente de [kind] es una imagen que se ofrece
/// para Procesado (F41, decisión L): una imagen guardada siempre; en otra
/// fuente, si su nombre dice que es una foto —la de una publicación—. Los SVG
/// no: no hay con qué dibujarlos en la grilla ni en la galería.
///
/// La misma regla que lista `SourceImagesReader`, dicha sobre un elemento ya
/// leído: la Bandeja la usa para saber, sin pedir nada, si hay qué triar.
bool isOfferedOwnImage(String path, SourceKind kind) {
  if (isSvgPath(path)) return false;
  return kind == SourceKind.image ||
      mediaKindOf(fileName: p.basename(path)) == RenditionKind.image;
}

/// Si una forma con archivo [path] y tipo [mimeType] es un SVG.
bool isSvgPath(String path, {String? mimeType}) =>
    p.extension(path).toLowerCase() == '.svg' ||
    (mimeType?.toLowerCase().startsWith('image/svg') ?? false);

/// Si [item] trae alguna imagen que llevar a Procesado: su archivo, si es una
/// imagen, o una foto de su «Contenido».
bool offersImages(KnowledgeItem item) {
  final own = item.source.originalFilePath;
  if (own != null && isOfferedOwnImage(own, item.source.kind)) return true;
  return item.renditions.any(
    (rendition) => switch (rendition) {
      FileRendition(kind: RenditionKind.image, :final relativePath) =>
        !isSvgPath(relativePath),
      _ => false,
    },
  );
}
