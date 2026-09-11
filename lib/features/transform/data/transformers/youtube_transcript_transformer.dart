import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/core/util/youtube_url.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Trae la transcripción de un video de YouTube, junto con su título y su
/// autor reales.
///
/// Es el reemplazo de DownSub, y sale mejor que integrarlo: los subtítulos se
/// piden sin clave de API y sin cuotas diarias, no hay que abrir una pestaña
/// ni pegar una dirección en otro sitio, y lo que baja queda guardado con el
/// enlace al video en vez de en un archivo suelto en Descargas.
class YouTubeTranscriptTransformer implements Transformer {
  const YouTubeTranscriptTransformer({
    required YouTubeClient client,
    required IdGenerator ids,
    required Clock clock,
  }) : _client = client,
       _ids = ids,
       _clock = clock;

  final YouTubeClient _client;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.youtube) return false;

    final url = item.source.url;
    if (url == null) return false;
    if (YouTubeUrl.videoIdOf(Uri.parse(url)) == null) return false;

    // Ya tiene contenido: no se vuelve a bajar. Sin esta comprobación, cada
    // pasada de la cola pediría de nuevo lo mismo y duplicaría la
    // transcripción.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    final videoId = YouTubeUrl.videoIdOf(Uri.parse(item.source.url!))!;
    final data = await _client.fetchVideo(videoId);
    final now = _clock();

    return item.copyWith(
      // El título provisional era el identificador del video; ahora se sabe
      // cómo se llama de verdad.
      title: data.title,
      subtitle: data.authorName ?? item.subtitle,
      source: item.source.copyWith(
        authorName: data.authorName ?? item.source.authorName,
        authorUrl: data.authorChannelUrl ?? item.source.authorUrl,
        publishedAt: data.publishedAt ?? item.source.publishedAt,
      ),
      renditions: _renditionsFor(item.id, data, now),
    );
  }

  /// Qué se guarda como contenido.
  ///
  /// La transcripción si la hay. Si el video no tiene subtítulos de ninguna
  /// clase —pasa, y es común en videos caseros— se guarda la descripción,
  /// que es contenido real, buscable, y mejor que dejar el elemento vacío. El
  /// audio se podrá transcribir más adelante; mientras tanto, esto ya sirve.
  List<Rendition> _renditionsFor(
    String itemId,
    YouTubeVideoData data,
    DateTime now,
  ) {
    if (data.transcript.isNotEmpty) {
      return [
        Rendition.text(
          id: _ids.next(),
          itemId: itemId,
          kind: RenditionKind.markdown,
          content: formatTranscript(data.transcript),
          isPrimary: true,
          createdAt: now,
        ),
      ];
    }

    final description = data.description?.trim() ?? '';
    if (description.isEmpty) return const [];

    return [
      Rendition.text(
        id: _ids.next(),
        itemId: itemId,
        kind: RenditionKind.plainText,
        content: description,
        isPrimary: true,
        createdAt: now,
      ),
    ];
  }
}

/// Arma el texto de la transcripción con sus marcas de tiempo.
///
/// El momento de cada línea es lo que separa una transcripción de un bloque
/// de texto: encontrar una frase en la búsqueda y saber en qué minuto del
/// video estaba es la diferencia entre volver al punto exacto y tener que
/// mirar una hora de video otra vez.
///
/// Se expone para poder probarlo por su cuenta: el formato es lo que el
/// usuario termina leyendo.
String formatTranscript(List<TranscriptLine> lines) {
  return lines
      .map((line) => '[${formatTimestamp(line.offset)}] ${line.text}')
      .join('\n');
}

/// `2:07` para lo que dura menos de una hora, `1:02:07` para lo que dura más.
///
/// No se usa siempre el formato largo porque la mayoría de los videos duran
/// minutos, y un `0:02:07` obliga a leer un cero que no aporta nada.
String formatTimestamp(Duration offset) {
  final hours = offset.inHours;
  final minutes = offset.inMinutes.remainder(60);
  final seconds = offset.inSeconds.remainder(60);

  final paddedSeconds = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$paddedSeconds';

  return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
}
