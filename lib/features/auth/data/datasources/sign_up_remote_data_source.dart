import 'package:cristo_es_el_salvador/core/network/dio_exception_mapper.dart';
import 'package:cristo_es_el_salvador/features/auth/data/dtos/login_response_dto.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/errors/auth_exceptions.dart';
import 'package:dio/dio.dart';

// Interfaz de un solo método a propósito, igual que AuthRemoteDataSource:
// define el contrato que AuthRepositoryImpl consume y los tests mockean.
// ignore: one_member_abstracts
abstract interface class SignUpRemoteDataSource {
  Future<LoginResponseDto> signUp({
    required String name,
    required String email,
    required String password,
  });
}

class SignUpRemoteDataSourceImpl implements SignUpRemoteDataSource {
  const SignUpRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<LoginResponseDto> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/signup',
        data: {'name': name, 'email': email, 'password': password},
      );
      return LoginResponseDto.fromJson(response.data!);
    } on DioException catch (e) {
      // 400 en /signup significa "ese correo ya existe" — un rechazo de
      // negocio propio de este endpoint, no genérico de red.
      if (e.response?.statusCode == 400) {
        throw const EmailAlreadyInUseException();
      }
      throw mapDioException(e);
    }
  }
}
