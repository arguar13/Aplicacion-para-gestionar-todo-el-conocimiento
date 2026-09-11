import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
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

  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
    'www.youtu.be',
  };

  final IdGenerator _ids;
  final Clock _clock;

  @override
  SourceKind get producesKind => SourceKind.youtube;

  @override
  bool canHandle(CaptureRequest request) {
    final url = request.asUrl;
    if (url == null) return false;
    // Se compara el host completo y no un `contains('youtube')`: un dominio
    // como `youtube.ejemplo.com` no es YouTube, y tratarlo como tal haría que
    // la transformación le pidiera subtítulos a un sitio cualquiera.
    return _hosts.contains(url.host.toLowerCase()) && videoIdOf(url) != null;
  }

  @override
  Future<KnowledgeItem> adapt(CaptureRequest request) async {
    final now = _clock();
    final url = request.asUrl!;
    final videoId = videoIdOf(url);

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

  /// El identificador del video, o `null` si la dirección no apunta a uno.
  ///
  /// Cubre las tres formas en que YouTube reparte enlaces: el clásico
  /// `?v=`, el corto `youtu.be/ID` y el de los shorts `/shorts/ID`. Una
  /// dirección de YouTube que no sea ninguna de esas —la portada, un canal,
  /// una lista— no tiene video que capturar, y es el motivo de que
  /// [canHandle] lo exija.
  static String? videoIdOf(Uri url) {
    final host = url.host.toLowerCase();

    if (host == 'youtu.be' || host == 'www.youtu.be') {
      final segments = url.pathSegments.where((s) => s.isNotEmpty);
      return segments.isEmpty ? null : segments.first;
    }

    final fromQuery = url.queryParameters['v'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex != -1 && shortsIndex + 1 < segments.length) {
      return segments[shortsIndex + 1];
    }

    return null;
  }
}
