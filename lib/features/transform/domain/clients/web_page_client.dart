import 'package:freezed_annotation/freezed_annotation.dart';

part 'web_page_client.freezed.dart';

/// El artículo que quedó después de sacarle a la página todo lo que no era
/// el artículo.
@freezed
sealed class ExtractedArticle with _$ExtractedArticle {
  const factory ExtractedArticle({
    /// El HTML del contenido, ya limpio de navegación, publicidad,
    /// comentarios y barras laterales.
    required String contentHtml,

    /// El mismo contenido sin etiquetas. Se usa para saber si hubo algo que
    /// extraer: una página sin una letra no tiene artículo. Una con cuatro
    /// palabras sí, y se guarda (F22).
    required String textContent,
    String? title,
    String? byline,
    String? siteName,
  }) = _ExtractedArticle;
}

/// Trae el HTML de una página.
///
/// Se abstrae para poder probar el transformador sin red. Un test que
/// descargara de verdad fallaría sin conexión, cambiaría de resultado cuando
/// cambie la página, y tardaría segundos en cada corrida.
// ignore: one_member_abstracts
abstract interface class WebPageClient {
  Future<String> fetchHtml(Uri url);
}

/// Separa el artículo del resto de la página.
///
/// Es el trabajo que hacen el modo lectura de un navegador y PrintFriendly.
/// Detrás de una interfaz propia y no usado directamente porque es la pieza
/// con más probabilidad de tener que cambiarse: hoy la cubre un port del
/// algoritmo Readability de Mozilla, y si aparece algo mejor —o si este falla
/// con cierta clase de sitios— se reemplaza esta implementación sin tocar el
/// transformador ni nada aguas arriba.
// ignore: one_member_abstracts
abstract interface class ArticleExtractor {
  /// El artículo, o `null` si la página no tenía ningún texto.
  ///
  /// Un texto corto no es motivo para `null` (F22): descartarlo era perder
  /// contenido real —un aviso, una nota breve— sin guardar ni la página.
  /// `null` queda para lo que de verdad no tiene nada que leer: una página
  /// vacía, o una que solo arma su contenido con JavaScript.
  ExtractedArticle? extract(String html, {required Uri baseUri});
}

/// La página se trajo pero no había artículo que extraer.
final class NoArticleFoundException implements Exception {
  const NoArticleFoundException(this.url);

  final Uri url;

  @override
  String toString() => 'NoArticleFoundException: $url';
}
