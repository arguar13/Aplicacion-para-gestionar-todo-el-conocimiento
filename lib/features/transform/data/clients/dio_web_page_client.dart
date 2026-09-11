import 'package:dio/dio.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// [WebPageClient] sobre el `Dio` de la app.
///
/// Reusa el cliente compartido —con su registro de peticiones, su manejo
/// transversal de errores y su User-Agent honesto— en vez de crear uno
/// propio. Ver `core/network/network_providers.dart`.
class DioWebPageClient implements WebPageClient {
  const DioWebPageClient(this._dio);

  final Dio _dio;

  @override
  Future<String> fetchHtml(Uri url) async {
    final response = await _dio.getUri<String>(
      url,
      options: Options(
        // Se pide texto explícitamente: sin esto, Dio intenta interpretar la
        // respuesta como JSON y se rompe con el primer `<`.
        responseType: ResponseType.plain,
        headers: const {'Accept': 'text/html,application/xhtml+xml'},
      ),
    );

    return response.data ?? '';
  }
}
