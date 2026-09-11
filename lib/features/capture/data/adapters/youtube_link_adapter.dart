import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/core/util/youtube_url.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Enlaces de YouTube: videos, shorts y los de la versión móvil.
///
/// Va antes que `WebLinkAdapter` en el registro. Los dos aceptarían la misma
/// dirección, pero reconocerla como YouTube desde el momento de guardarla
/// cambia lo que pasa después: el elemento queda marcado con su tipo real, la
/// lista puede filtrarlo como video y la etapa de transformación sabe que a
/// esto le corresponden subtítulos y no un raspado de HTML.
class YouTubeLinkAdapter implements SourceAdapter {
  const YouTubeLinkAdapter({required IdGenerator ids, required Clock clock})
    : _ids = ids,
      _clock = clock;

  final IdGenerator _ids;
  final Clock _clock;

  @override
  SourceKind get producesKind => SourceKind.youtube;

  @override
  bool canHandle(CaptureRequest request) {
    final url = request.asUrl;
    return url != null && YouTubeUrl.isVideo(url);
  }

  @override
  Future<KnowledgeItem> adapt(CaptureRequest request) async {
    final now = _clock();
    final url = request.asUrl!;
    final videoId = YouTubeUrl.videoIdOf(url);

    return KnowledgeItem(
      id: _ids.next(),
      // Sin salir a la red no se puede saber cómo se llama el video. El
      // identificador al menos distingue uno de otro en la lista, y el título
      // real lo pone la transformación cuando baje los metadatos.
      title: request.title?.trim().isNotEmpty ?? false
          ? request.title!.trim()
          : 'youtu.be/$videoId',
      subtitle: 'youtube.com',
      notes: request.note,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.youtube,
        capturedAt: now,
        url: url.toString(),
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
    );
  }
}
