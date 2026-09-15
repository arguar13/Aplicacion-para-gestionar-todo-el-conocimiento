import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/capture/data/adapters/provisional_titles.dart';
import 'package:sinapsis/features/capture/domain/adapters/source_adapter.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';

/// Enlaces de TikTok e Instagram: videos, reels y publicaciones.
///
/// Va antes que `WebLinkAdapter` en el registro, por la misma razón que
/// `YouTubeLinkAdapter`: reconocer la plataforma desde el momento de
/// guardar cambia lo que pasa después — la etapa de transformación sabe que
/// acá corresponde intentar raspar el video y el texto, no archivar la
/// página como un artículo.
///
/// Solo reconoce las direcciones donde eso vale la pena: un video, un reel,
/// una publicación puntual. El perfil de un usuario o la página de inicio
/// de la plataforma no traen nada que extraer y quedan para el enlace
/// genérico.
class SocialPostLinkAdapter implements SourceAdapter {
  const SocialPostLinkAdapter({required IdGenerator ids, required Clock clock})
    : _ids = ids,
      _clock = clock;

  final IdGenerator _ids;
  final Clock _clock;

  @override
  SourceKind get producesKind => SourceKind.socialPost;

  @override
  bool canHandle(CaptureRequest request) {
    final url = request.asUrl;
    return url != null && _isPost(url);
  }

  bool _isPost(Uri url) {
    final host = url.host.toLowerCase();
    final segments = url.pathSegments;

    if (host.contains('tiktok.com')) {
      // /@usuario/video/1234... es la forma de escritorio; el enlace corto
      // vm.tiktok.com/XXXX no trae segmentos propios, así que cualquier
      // dirección de ese subdominio se acepta tal cual.
      return host.startsWith('vm.') || segments.contains('video');
    }

    if (host.contains('instagram.com')) {
      // /reel/<id>, /p/<id> (publicación normal, puede traer video) y
      // /tv/<id> (IGTV). El perfil —solo /<usuario>— queda afuera a
      // propósito: no hay una sola publicación que raspar.
      return segments.isNotEmpty &&
          const {'reel', 'p', 'tv'}.contains(segments.first);
    }

    return false;
  }

  @override
  Future<KnowledgeItem> adapt(CaptureRequest request) async {
    final now = _clock();
    final url = request.asUrl!;

    return KnowledgeItem(
      id: _ids.next(),
      title: request.title?.trim().isNotEmpty ?? false
          ? request.title!.trim()
          : titleFromUrl(url),
      subtitle: url.host,
      notes: request.note,
      source: Source(
        id: _ids.next(),
        kind: SourceKind.socialPost,
        capturedAt: now,
        url: url.toString(),
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
    );
  }
}
