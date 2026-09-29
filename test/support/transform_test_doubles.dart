// Los dobles lanzan lo que el test les dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese. Es
// deliberado: la app tiene que sobrevivir a las dos cosas —una librería ajena
// puede tirar un `Error` de parseo— y eso solo se puede probar si el doble
// puede simular ambas.
// ignore_for_file: only_throw_errors

import 'dart:async';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/transform/domain/archive/page_archiver.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';
import 'package:sinapsis/features/transform/domain/clients/social_post_client.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Cliente de YouTube que responde lo que se le diga, sin salir a la red.
///
/// Un test que pidiera videos de verdad fallaría sin conexión, cambiaría de
/// resultado cuando cambie el video y tardaría segundos en cada corrida.
class FakeYouTubeClient implements YouTubeClient {
  FakeYouTubeClient({
    this.data,
    this.error,
    this.audio,
    this.audioError,
    this.audioPausedAfterFirstChunk,
  });

  /// Lo que devuelve. Si es `null` y no hay [error], responde un video mínimo.
  final YouTubeVideoData? data;

  /// Si está, se lanza en vez de responder.
  final Object? error;

  /// Los bytes del audio que entrega [openAudio], en partes de 2 bytes.
  /// `null` sin [audioError] responde un audio mínimo.
  final Uint8List? audio;

  /// Si está, [openAudio] lo lanza en vez de responder.
  final Object? audioError;

  /// Si está, entrega la primera parte y no sigue hasta que se complete: para
  /// hacer algo "mientras baja" sin depender del azar. Uno que nunca se
  /// completa es una descarga colgada.
  final Future<void>? audioPausedAfterFirstChunk;

  /// Los identificadores que se le pidieron, en orden.
  final requested = <String>[];

  /// Los identificadores para los que se pidió el audio, en orden.
  final audioRequested = <String>[];

  @override
  Future<YouTubeVideoData> fetchVideo(
    String videoId, {
    List<String> preferredLanguages = const ['es', 'en'],
  }) async {
    requested.add(videoId);
    if (error != null) throw error!;

    return data ?? const YouTubeVideoData(title: 'Un video');
  }

  @override
  Future<YouTubeAudioStream> openAudio(String videoId) async {
    audioRequested.add(videoId);
    if (audioError != null) throw audioError!;

    final bytes = audio ?? Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final chunks = [
      for (var i = 0; i < bytes.length; i += 2)
        bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2),
    ];

    Stream<List<int>> stream() async* {
      final pause = audioPausedAfterFirstChunk;
      if (pause == null) {
        yield* Stream.fromIterable(chunks);
        return;
      }
      yield chunks.first;
      await pause;
      yield* Stream.fromIterable(chunks.skip(1));
    }

    return YouTubeAudioStream(
      bytes: stream(),
      totalBytes: bytes.length,
      fileExtension: 'm4a',
    );
  }
}

/// Devuelve el HTML que se le dé, sin descargar nada.
class FakeWebPageClient implements WebPageClient {
  FakeWebPageClient({this.html = '', this.error});

  final String html;
  final Object? error;

  final requested = <Uri>[];

  @override
  Future<String> fetchHtml(Uri url) async {
    requested.add(url);
    if (error != null) throw error!;
    return html;
  }
}

/// Extractor que devuelve lo que se le diga.
///
/// Para probar el transformador aparte del algoritmo de extracción: son dos
/// cosas distintas y conviene que fallen por separado. El extractor de verdad
/// tiene sus propios tests con HTML realista.
class FakeArticleExtractor implements ArticleExtractor {
  FakeArticleExtractor({this.article});

  /// `null` simula una página sin artículo reconocible: una portada, un
  /// listado, un panel de control.
  final ExtractedArticle? article;

  @override
  ExtractedArticle? extract(String html, {required Uri baseUri}) => article;
}

/// Transformador que hace lo que se le diga.
///
/// Para probar el caso de uso y la cola aparte de los transformadores reales:
/// lo que se verifica ahí es la orquestación —qué se guarda, en qué orden y
/// qué pasa cuando algo falla— y usar un transformador de verdad mezclaría
/// los dos asuntos.
class FakeTransformer implements Transformer {
  FakeTransformer({
    this.accepts = true,
    this.error,
    this.enrich,
    this.onTransform,
    this.timeLimit,
  });

  final bool accepts;
  final Object? error;

  @override
  final Duration? timeLimit;

  /// Qué devolver. Por defecto agrega una forma de texto, que es lo que hace
  /// un transformador real.
  final KnowledgeItem Function(KnowledgeItem)? enrich;

  /// Se llama al empezar. Sirve para observar el estado justo antes de
  /// transformar — por ejemplo, comprobar que ya se publicó "en curso".
  ///
  /// Recibe el contexto de la cola: con él una prueba puede pasar al carril
  /// largo o informar avance, como haría un transformador de verdad.
  final Future<void> Function(KnowledgeItem item, TransformContext context)?
  onTransform;

  final transformed = <String>[];

  @override
  bool canTransform(KnowledgeItem item) => accepts;

  @override
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
    transformed.add(item.id);
    await onTransform?.call(item, context);
    if (error != null) throw error!;

    if (enrich != null) return enrich!(item);

    return item.copyWith(
      title: 'Título traído de la red',
      renditions: [
        Rendition.text(
          id: '${item.id}-rend',
          itemId: item.id,
          kind: RenditionKind.markdown,
          content: 'El contenido que se trajo.',
          isPrimary: true,
          createdAt: item.createdAt,
        ),
      ],
    );
  }
}

/// Trae lo que se le diga para cada URL, sin salir a la red.
///
/// Ausente del mapa o con valor `null` simula un recurso que no se pudo
/// traer — un 404, un CDN caído, lo que sea: son la misma cosa desde el
/// punto de vista de quien archiva.
class FakeResourceFetcher implements ResourceFetcher {
  FakeResourceFetcher({this.byUrl = const {}});

  final Map<String, Uint8List?> byUrl;

  /// Las URLs que se pidieron, en orden.
  final requested = <Uri>[];

  @override
  Future<Uint8List?> fetchBytes(Uri url) async {
    requested.add(url);
    return byUrl[url.toString()];
  }
}

/// Devuelve lo que se le diga para una publicación social, sin raspar nada.
class FakeSocialPostClient implements SocialPostClient {
  FakeSocialPostClient({this.data, this.error});

  /// Lo que devuelve. Si es `null` y no hay [error], responde vacío.
  final SocialPostData? data;

  /// Si está, se lanza en vez de responder.
  final Object? error;

  final requested = <Uri>[];

  @override
  Future<SocialPostData> fetchPost(Uri url) async {
    requested.add(url);
    if (error != null) throw error!;

    return data ?? const SocialPostData();
  }
}

/// Archivador que hace lo que se le diga, sin tocar HTML de verdad.
///
/// Para probar el transformador aparte de cómo se incrustan los recursos:
/// esto es orquestación —qué se guarda y qué pasa cuando el archivado
/// falla— y usar el archivador real mezclaría los dos asuntos.
class FakePageArchiver implements PageArchiver {
  FakePageArchiver({this.result, this.error});

  /// Lo que devuelve. `null` simula que no se pudo producir nada
  /// aprovechable, sin que eso sea un error.
  final Uint8List? result;

  /// Si está, se lanza en vez de responder.
  final Object? error;

  final requested = <String>[];

  @override
  Future<Uint8List?> archive(String html, {required Uri baseUri}) async {
    requested.add(html);
    if (error != null) throw error!;

    return result;
  }
}
