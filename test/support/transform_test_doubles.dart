// Los dobles lanzan lo que el test les dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese. Es
// deliberado: la app tiene que sobrevivir a las dos cosas —una librería ajena
// puede tirar un `Error` de parseo— y eso solo se puede probar si el doble
// puede simular ambas.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/clients/youtube_client.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Cliente de YouTube que responde lo que se le diga, sin salir a la red.
///
/// Un test que pidiera videos de verdad fallaría sin conexión, cambiaría de
/// resultado cuando cambie el video y tardaría segundos en cada corrida.
class FakeYouTubeClient implements YouTubeClient {
  FakeYouTubeClient({this.data, this.error});

  /// Lo que devuelve. Si es `null` y no hay [error], responde un video mínimo.
  final YouTubeVideoData? data;

  /// Si está, se lanza en vez de responder.
  final Object? error;

  /// Los identificadores que se le pidieron, en orden.
  final requested = <String>[];

  @override
  Future<YouTubeVideoData> fetchVideo(
    String videoId, {
    List<String> preferredLanguages = const ['es', 'en'],
  }) async {
    requested.add(videoId);
    if (error != null) throw error!;

    return data ?? const YouTubeVideoData(title: 'Un video');
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
  });

  final bool accepts;
  final Object? error;

  /// Qué devolver. Por defecto agrega una forma de texto, que es lo que hace
  /// un transformador real.
  final KnowledgeItem Function(KnowledgeItem)? enrich;

  /// Se llama al empezar. Sirve para observar el estado justo antes de
  /// transformar — por ejemplo, comprobar que ya se publicó "en curso".
  final Future<void> Function(KnowledgeItem)? onTransform;

  final transformed = <String>[];

  @override
  bool canTransform(KnowledgeItem item) => accepts;

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    transformed.add(item.id);
    await onTransform?.call(item);
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
