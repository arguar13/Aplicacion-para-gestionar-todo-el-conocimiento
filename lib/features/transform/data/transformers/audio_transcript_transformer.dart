import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Transcribe un audio o un video guardado como archivo: una nota de voz, un
/// podcast, la grabación de una clase.
///
/// Mismo criterio que `ImageTransformer`: traer el archivo, transcribirlo, y
/// devolver el elemento enriquecido o tal cual si no salió ningún texto. Un
/// mismo transformador para los dos `SourceKind` porque la distinción entre
/// "es audio" y "es video sin plataforma reconocida" no importa acá —lo
/// único que se transcribe es la pista de audio, la tenga un `.mp3` o la
/// pista de un `.mp4`—.
class AudioTranscriptTransformer implements Transformer {
  const AudioTranscriptTransformer({
    required AudioTranscriber transcriber,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
  }) : _transcriber = transcriber,
       _files = files,
       _ids = ids,
       _clock = clock;

  final AudioTranscriber _transcriber;
  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;

  /// Trabajo largo: transcribir horas de audio no tiene un tope fijo
  /// razonable.
  @override
  Duration? get timeLimit => null;

  @override
  bool canTransform(KnowledgeItem item) {
    final kind = item.source.kind;
    if (kind != SourceKind.audio && kind != SourceKind.video) return false;
    if (item.source.originalFilePath == null) return false;

    // Ya tiene contenido: no se vuelve a transcribir. Sin esta
    // comprobación, cada pasada de la cola repetiría la misma transcripción
    // sobre el mismo archivo.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    final path = item.source.originalFilePath!;

    // Alcanza con comprobar que siga estando: lo único que hace falta
    // después es la ruta absoluta, no los bytes. Cargarlos en memoria solo
    // para descartarlos es un costo real cuando el archivo es un video de
    // varios cientos de megas.
    if (!await _files.exists(path)) throw MissingOriginalFileException(path);

    // En la web `resolve()` no tiene sentido —no hay ruta absoluta— así
    // que el transcriptor recibe la ruta relativa y la resuelve por su
    // cuenta.
    final transcriberPath = kIsWeb ? path : await _files.resolve(path);
    final text = await _transcriber.transcribe(transcriberPath);

    // Sin texto transcripto no es un fallo: un video sin diálogo, música
    // instrumental, silencio. El elemento se marca listo igual, con el
    // archivo original como único contenido.
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
