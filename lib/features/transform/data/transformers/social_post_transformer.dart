import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Trae el texto y, si se puede, el video o la foto de una publicación de
/// TikTok o Instagram —un reel, un short compartido fuera de YouTube, un
/// carrusel con descripción.
///
/// A diferencia del transformador de páginas web, acá no hay un algoritmo de
/// lectura confiable como Readability: lo que trae [SocialPostClient] ya es
/// el resultado final, raspado del HTML de la plataforma. Por esa misma
/// razón el resultado es menos confiable — cualquiera de las partes, texto,
/// video o foto, puede faltar sin que eso sea un error de la app.
///
/// Que falte el video o la foto nunca le cuesta el texto, ni al revés: se
/// guarda lo que se haya conseguido, con el mismo criterio best-effort que
/// ya usan `WebArticleTransformer` para archivar la página y
/// `YouTubeTranscriptTransformer` para el audio. Solo si no se consiguió
/// nada de nada se marca el elemento como fallido, para que el usuario
/// pueda reintentarlo cuando la plataforma vuelva a dejarse raspar.
///
/// Entre video y foto, el video gana cuando hay las dos: es el contenido
/// más completo, y `SocialPostData.imageUrl` solo trae la carátula cuando
/// el video ya está — ver ese comentario sobre por qué nunca hay más de
/// una foto para elegir en una publicación con varias.
class SocialPostTransformer implements Transformer {
  const SocialPostTransformer({
    required SocialPostClient client,
    required ResourceFetcher fetcher,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
    required AppLogger logger,
  }) : _client = client,
       _fetcher = fetcher,
       _files = files,
       _ids = ids,
       _clock = clock,
       _logger = logger;

  final SocialPostClient _client;
  final ResourceFetcher _fetcher;
  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;
  final AppLogger _logger;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.socialPost) return false;
    if (item.source.url == null) return false;

    // Ya tiene contenido: no se vuelve a bajar. Sin esta comprobación, cada
    // pasada de la cola raspa la misma publicación otra vez.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    final url = Uri.parse(item.source.url!);
    final post = await _client.fetchPost(url);

    final caption = post.caption?.trim();
    final hasCaption = caption != null && caption.isNotEmpty;

    if (!hasCaption && post.videoUrl == null && post.imageUrl == null) {
      // Ni texto, ni un video, ni una foto que intentar bajar: la
      // plataforma no dejó sacar nada, sea porque la publicación es
      // privada, se borró, o porque ese día decidió servirle a este
      // cliente una página distinta de la que ve una persona. Se lanza
      // para que el elemento quede como fallido, con su enlace intacto, y
      // se pueda reintentar más tarde.
      throw SocialPostUnavailableException(url);
    }

    final now = _clock();
    final videoPath = await _downloadFileSafely(
      post.videoUrl,
      sourceId: item.source.id,
      title: item.title,
      extension: 'mp4',
    );
    // Solo se baja la foto si no hay video: entre las dos, el video es el
    // contenido más completo — ver el comentario de `SocialPostData.imageUrl`
    // sobre por qué nunca hay más de una foto para elegir.
    final imagePath = videoPath == null
        ? await _downloadFileSafely(
            post.imageUrl,
            sourceId: item.source.id,
            title: item.title,
            extension: 'jpg',
          )
        : null;

    return item.copyWith(
      subtitle: post.authorName ?? item.subtitle,
      source: item.source.copyWith(
        authorName: post.authorName ?? item.source.authorName,
        originalFilePath:
            videoPath ?? imagePath ?? item.source.originalFilePath,
      ),
      renditions: hasCaption
          ? [
              Rendition.text(
                id: _ids.next(),
                itemId: item.id,
                kind: RenditionKind.plainText,
                content: caption,
                isPrimary: true,
                createdAt: now,
              ),
            ]
          : const [],
    );
  }

  /// Baja el video o la foto y lo guarda, o `null` si no se pudo.
  ///
  /// Atrapa cualquier fallo a propósito, igual que
  /// `YouTubeTranscriptTransformer._downloadAudioSafely`: el archivo es un
  /// extra sobre el texto, y no puede costarle al usuario la descripción
  /// que sí se consiguió.
  Future<String?> _downloadFileSafely(
    Uri? url, {
    required String sourceId,
    required String title,
    required String extension,
  }) async {
    if (url == null) return null;

    try {
      final bytes = await _fetcher.fetchBytes(url);
      if (bytes == null) return null;

      return await _files.save(
        bytes: bytes,
        suggestedName: '$title.$extension',
        id: sourceId,
      );
      // El archivo es un extra: cualquier fallo, del tipo que sea, se
      // registra y se sigue sin él, en vez de perder el texto.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      _logger.warning('No se pudo bajar $url: $e');
      return null;
    }
  }
}
