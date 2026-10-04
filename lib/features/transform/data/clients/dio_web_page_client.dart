import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/network/dio_exception_mapper.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';
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
  /// Lo más que se lee de una página. Ninguna página de verdad se le
  /// acerca —una de Wikipedia larga pesa 1 o 2 MB—; algo más grande que esto
  /// no es una página, y leerlo entero en memoria es lo que no tiene que
  /// pasar.
  static const maxPageBytes = 32 * 1024 * 1024;

  @override
  Future<String> fetchHtml(Uri url) async {
    try {
      final response = await _dio.getUri<ResponseBody>(
        url,
        options: Options(
          // Se piden los bytes, no texto (F22): con `ResponseType.plain`
          // Dio decodifica siempre como UTF-8, sin mirar el `charset` que
          // declara el servidor, y una página en Latin-1 perdía cada tilde.
          // La codificación la decide `decodeHtmlBytes`, como un navegador.
          //
          // Y como un stream (F30): antes de leer el cuerpo se mira qué es.
          // Un enlace directo a un video de 300 MB se leía entero en memoria
          // para después tratarlo como una página.
          responseType: ResponseType.stream,
          headers: const {'Accept': 'text/html,application/xhtml+xml'},
        ),
      );
      final body = response.data!;
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final finalUrl = response.realUri;
      final offeredName = fileNameFromContentDisposition(
        response.headers.value('content-disposition'),
      );
      final name =
          offeredName ??
          finalUrl.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
          '';
      if (isFileResponse(contentType: contentType, fileName: name)) {
        await body.stream.listen(null).cancel();
        throw NotAPageException(
          url: finalUrl,
          contentType: contentType?.split(';').first.trim().toLowerCase(),
          fileName: offeredName,
        );
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        bytes.add(chunk);
        if (bytes.length > maxPageBytes) {
          throw ServerException(
            message: 'La página pesa más de $maxPageBytes bytes.',
            statusCode: response.statusCode,
          );
        }
      }

      return decodeHtmlBytes(
        bytes.takeBytes(),
        contentType: contentType,
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
