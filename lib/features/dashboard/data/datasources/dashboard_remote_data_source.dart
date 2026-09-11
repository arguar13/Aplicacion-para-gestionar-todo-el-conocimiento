import 'package:dio/dio.dart';
import 'package:sinapsis/core/data/dtos/user_dto.dart';
import 'package:sinapsis/core/network/dio_exception_mapper.dart';

/// `GET /user`: no arma la cabecera `Authorization` a mano, la pone
/// `AuthInterceptor` (ver `core/network/network_providers.dart`). Si esta
/// llamada funciona sin tocar headers aquí, el interceptor está
/// funcionando; si el backend responde 401, `UnauthorizedInterceptor`
/// desloguea globalmente antes de que este error llegue al repositorio.
// ignore: one_member_abstracts
abstract interface class DashboardRemoteDataSource {
  Future<UserDTO> getCurrentUser();
}

class DashboardRemoteDataSourceImpl implements DashboardRemoteDataSource {
  const DashboardRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<UserDTO> getCurrentUser() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/user');
      return UserDTO.fromJson(response.data!);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
