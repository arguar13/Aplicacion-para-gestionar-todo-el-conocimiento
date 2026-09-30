import 'package:dio/dio.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/dio_exception_mapper.dart';
import 'package:sinapsis/features/transform/data/clients/html_text_decoder.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// [WebPageClient] sobre el `Dio` de la app.
///
/// Reusa el cliente compartido —con su registro de peticiones, su manejo
/// transversal de errores y su User-Agent honesto— en vez de crear uno
/// propio. Ver `core/network/network_providers.dart`.
class DioWebPageClient implements WebPageClient {
  const DioWebPageClient(this._dio, {AppLogger? logger}) : _logger = logger;

  final Dio _dio;

  /// Dónde queda registrada una página que declara una codificación que la
  /// app no sabe leer (F22): su texto puede haberse guardado con caracteres
  /// rotos, y así se sabe por qué. `null` en las pruebas a las que no les
  /// interesa.
  final AppLogger? _logger;

  /// Lanza [NetworkException] si no hubo conexión o el servidor no respondió
  /// a tiempo, y [ServerException] —con su código— si respondió con un
  /// error: así el motivo que se guarda distingue "sin conexión" de "la
  /// página ya no existe" (F21).
  @override
  Future<String> fetchHtml(Uri url) async {
    try {
      final response = await _dio.getUri<List<int>>(
        url,
        options: Options(
          // Se piden los bytes, no texto (F22): con `ResponseType.plain`
          // Dio decodifica siempre como UTF-8, sin mirar el `charset` que
          // declara el servidor, y una página en Latin-1 perdía cada tilde.
          // La codificación la decide `decodeHtmlBytes`, como un navegador.
          responseType: ResponseType.bytes,
          headers: const {'Accept': 'text/html,application/xhtml+xml'},
        ),
      );

      return decodeHtmlBytes(
        response.data ?? const [],
        contentType: response.headers.value(Headers.contentTypeHeader),
        onUnsupportedCharset: (charset) => _logger?.warning(
          'La página $url declara la codificación "$charset", que la app no '
          'sabe leer: se leyó como UTF-8 (o Windows-1252 si no lo era) y '
          'puede tener caracteres rotos.',
        ),
      );
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }
}
