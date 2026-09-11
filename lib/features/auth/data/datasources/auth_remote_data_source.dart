import 'package:dio/dio.dart';
import 'package:sinapsis/core/network/dio_exception_mapper.dart';
import 'package:sinapsis/features/auth/data/dtos/login_response_dto.dart';
import 'package:sinapsis/features/auth/domain/errors/auth_exceptions.dart';

// Interfaz de un solo método a propósito: define el contrato que
// AuthRepositoryImpl consume y que los tests pueden mockear.
// ignore: one_member_abstracts
abstract interface class AuthRemoteDataSource {
  Future<LoginResponseDto> login({
    required String email,
    required String password,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  const AuthRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<LoginResponseDto> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/login',
        data: {'email': email, 'password': password},
      );
      return LoginResponseDto.fromJson(response.data!);
    } on DioException catch (e) {
      // 401/403 en /login significa "credenciales inválidas", no "sesión
      // expirada" (todavía no hay sesión) — por eso no delega ese caso al
      // mapeador genérico de `core/network`.
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        throw const InvalidCredentialsException();
      }
      throw mapDioException(e);
    }
  }
}
