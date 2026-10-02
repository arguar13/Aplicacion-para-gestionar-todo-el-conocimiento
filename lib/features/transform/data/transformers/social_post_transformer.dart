import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/entities/timed_text.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_checkpoints.dart';
import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';
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
///
/// El audio del video bajado se transcribe, como el de un video del
/// teléfono (F24): lo que se dice en un reel suele ser el contenido de
/// verdad, y la descripción, un par de líneas y etiquetas.
class SocialPostTransformer implements Transformer {
  const SocialPostTransformer({
    required SocialPostClient client,
    required ResourceFetcher fetcher,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
    required AppLogger logger,
    AudioTranscriber? transcriber,
    ProcessingCheckpoints? checkpoints,
  }) : _client = client,
       _fetcher = fetcher,
       _files = files,
       _ids = ids,
       _clock = clock,
       _logger = logger,
       _transcriber = transcriber,
       _checkpoints = checkpoints;

  final SocialPostClient _client;
  final ResourceFetcher _fetcher;
  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;
  final AppLogger _logger;

  /// Con qué transcribir el audio del video bajado (F24). Sin él —en una
  /// prueba que no lo necesita—, queda solo la descripción, como antes.
  final AudioTranscriber? _transcriber;

  /// Dónde se guardan los tramos ya transcritos, para retomar si se
  /// interrumpe (F21). `null`: se transcribe de un tirón.
  final ProcessingCheckpoints? _checkpoints;

  /// El tramo corto: la publicación y su video o su foto. Transcribir el
  /// audio del video es trabajo largo, pero no corre bajo este tope: antes
  /// pasa al carril largo —ver [_transcribeVideo]—, donde lo vigila que
  /// siga avanzando, igual que el audio de un video de YouTube sin
  /// subtítulos.
  @override
  Duration? get timeLimit => kShortTransformTimeLimit;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.socialPost) return false;
    if (item.source.url == null) return false;

    // Ya tiene contenido: no se vuelve a bajar. Sin esta comprobación, cada
    // pasada de la cola raspa la misma publicación otra vez.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
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

    final spoken = videoPath == null
        ? null
        : await _transcribeVideo(videoPath, item, context);
    final hasSpoken = spoken != null && spoken.text.trim().isNotEmpty;

    return item.copyWith(
      subtitle: post.authorName ?? item.subtitle,
      source: item.source.copyWith(
        authorName: post.authorName ?? item.source.authorName,
        originalFilePath:
            videoPath ?? imagePath ?? item.source.originalFilePath,
        // En qué idioma quedó el texto, como en YouTube (F22).
        language: hasSpoken
            ? item.source.language ?? defaultTranscriptionLanguage
            : item.source.language,
      ),
      // Lo dicho, cuando lo hay, es el texto principal, y la descripción
      // queda al lado, también buscable. Mismo criterio que YouTube, donde
      // la descripción es solo lo que queda cuando no hay lo dicho: lo
      // principal es lo que leen el chat y las tarjetas, y lo que sigue al
      // audio en amarillo (F23); lo que vale ahí es lo que se dice en el
      // video, no un par de líneas y etiquetas.
      renditions: [
        if (hasSpoken)
          Rendition.text(
            id: _ids.next(),
            itemId: item.id,
            kind: RenditionKind.plainText,
            content: spoken.text,
            isPrimary: true,
            createdAt: now,
            // Cuándo se dice cada palabra, si el motor lo midió (F23).
            wordTimings: spoken.words,
          ),
        if (hasCaption)
          Rendition.text(
            id: _ids.next(),
            itemId: item.id,
            kind: RenditionKind.plainText,
            content: caption,
            isPrimary: !hasSpoken,
            createdAt: now,
          ),
      ],
    );
  }

  /// El audio del video guardado en [videoPath], transcrito; `null` si no
  /// hay con qué transcribir (F24).
  ///
  /// Como cualquier audio: en el carril largo, por tramos y retomable. Sin
  /// texto —música sola, silencio— no es un fallo: vuelve vacío, y el
  /// elemento queda listo con la descripción y el video.
  ///
  /// Un fallo se relanza, igual que el del audio de YouTube: el elemento
  /// queda fallido para reintentar, con los tramos ya transcritos guardados.
  /// El video bajado se deja —el reintento lo vuelve a bajar al mismo
  /// lugar—, salvo que se haya abandonado porque el elemento se borró: ahí
  /// ya no es de nadie.
  Future<Transcript?> _transcribeVideo(
    String videoPath,
    KnowledgeItem item,
    TransformContext context,
  ) async {
    final transcriber = _transcriber;
    if (transcriber == null) return null;
    await context.enterLongLane();

    try {
      // En la web no hay ruta absoluta: el transcriptor recibe la relativa y
      // la resuelve por su cuenta — ver `AudioTranscriptTransformer`.
      final path = kIsWeb ? videoPath : await _files.resolve(videoPath);
      final checkpoints = _checkpoints;
      return await transcriber.transcribe(
        path,
        language: item.source.language ?? defaultTranscriptionLanguage,
        session: TranscriptionSession(
          context: context,
          workKey: item.id,
          loadSegments: checkpoints == null
              ? null
              : () => checkpoints.load(
                  item.id,
                  ProcessingCheckpointKind.transcriptWindow,
                ),
          saveSegment: checkpoints == null
              ? null
              : (segment, text) => checkpoints.save(
                  item.id,
                  ProcessingCheckpointKind.transcriptWindow,
                  position: segment,
                  content: text,
                ),
        ),
      );
    } on Object {
      if (context.isCancelled) await _files.delete(videoPath);
      rethrow;
    }
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
