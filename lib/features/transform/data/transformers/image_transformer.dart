import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Saca el texto de una imagen guardada como archivo: una captura de
/// pantalla, la foto de una página, un cartel.
///
/// El mismo criterio que `DocumentTransformer`: traer el archivo, reconocer
/// si hay algo que hacer, y devolver el elemento enriquecido o tal cual si
/// no había texto que reconocer. Lo que cambia es que acá no hace falta
/// elegir entre varios lectores —hay un solo motor de reconocimiento— y que
/// una imagen sin ninguna letra adentro es el caso normal, no una excepción.
class ImageTransformer implements Transformer {
  const ImageTransformer({
    required ImageTextExtractor extractor,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
  }) : _extractor = extractor,
       _files = files,
       _ids = ids,
       _clock = clock;

  final ImageTextExtractor _extractor;
  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.image) return false;
    if (item.source.originalFilePath == null) return false;

    // Ya tiene contenido: no se vuelve a reconocer. Sin esta comprobación,
    // cada pasada de la cola repetiría el mismo reconocimiento sobre la
    // misma imagen.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    final path = item.source.originalFilePath!;

    final bytes = await _files.read(path);
    if (bytes == null) throw MissingOriginalFileException(path);

    // En la web `resolve()` no tiene sentido —no hay ruta absoluta— así que
    // el extractor recibe la ruta relativa y la resuelve por su cuenta.
    final extractorPath = kIsWeb ? path : await _files.resolve(path);
    final text = await _extractor.extractText(extractorPath);

    // Sin texto reconocido no es un fallo: la mayoría de las fotos no
    // tienen ninguna letra adentro, y eso está bien. El elemento se marca
    // listo igual, con la imagen como único contenido.
    if (text.trim().isEmpty) return item;

    return item.copyWith(
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: item.id,
          kind: RenditionKind.plainText,
          content: text,
          isPrimary: true,
          createdAt: _clock(),
        ),
      ],
    );
  }
}
