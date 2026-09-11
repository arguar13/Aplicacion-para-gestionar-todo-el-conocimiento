import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinapsis/features/transform/domain/clients/resource_fetcher.dart';

/// [ResourceFetcher] sobre un `Dio` propio, sin el interceptor de error
/// global — ver `core/network/network_providers.dart#resourceFetchDioProvider`.
class DioResourceFetcher implements ResourceFetcher {
  const DioResourceFetcher(this._dio);

  final Dio _dio;

  @override
  Future<Uint8List?> fetchBytes(Uri url) async {
    try {
      final response = await _dio.getUri<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
      // Cualquier fallo de red o de estado HTTP —404, CORS, tiempo de
      // espera— es normal al pedir un recurso de una página ajena, y este
      // cliente existe justamente para no lanzar por eso: ver la interfaz.
    } on DioException {
      return null;
    }
  }
}
