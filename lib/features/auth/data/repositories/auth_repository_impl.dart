import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/network/token_storage.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:sinapsis/features/auth/data/datasources/sign_up_remote_data_source.dart';
import 'package:sinapsis/features/auth/domain/errors/auth_exceptions.dart';
import 'package:sinapsis/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required SignUpRemoteDataSource signUpRemoteDataSource,
    required TokenStorage tokenStorage,
    required TelemetryService telemetry,
  }) : _remoteDataSource = remoteDataSource,
       _signUpRemoteDataSource = signUpRemoteDataSource,
       _tokenStorage = tokenStorage,
       _telemetry = telemetry;

  final AuthRemoteDataSource _remoteDataSource;
  final SignUpRemoteDataSource _signUpRemoteDataSource;
  final TokenStorage _tokenStorage;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, User>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _remoteDataSource.login(
        email: email,
        password: password,
      );
      await _tokenStorage.saveAccessToken(response.token);
      return right(response.user.toEntity());
    } on InvalidCredentialsException catch (e) {
      return left(Failure.unauthorized(message: e.message));
    } on ServerException catch (e) {
      return left(Failure.server(message: e.message, statusCode: e.statusCode));
    } on NetworkException catch (e) {
      return left(Failure.network(message: e.message));
      // Catch-all deliberado (no `on Exception`): un JSON malformado del
      // backend hace que el `fromJson` generado (modo unchecked) lance un
      // `TypeError`, que es un `Error`, no un `Exception` — si solo
      // atrapáramos `Exception` esto escaparía sin control y dejaría a
      // quien llame esperando una respuesta que nunca llega. Siempre es un
      // bug (del cliente o del contrato con el backend), nunca una
      // condición esperada, así que también se reporta a telemetría.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'AuthRepositoryImpl.login');
      return left(Failure.unexpected(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _signUpRemoteDataSource.signUp(
        name: name,
        email: email,
        password: password,
      );
      await _tokenStorage.saveAccessToken(response.token);
      return right(response.user.toEntity());
    } on EmailAlreadyInUseException catch (e) {
      return left(Failure.validation(message: e.message));
    } on ServerException catch (e) {
      return left(Failure.server(message: e.message, statusCode: e.statusCode));
    } on NetworkException catch (e) {
      return left(Failure.network(message: e.message));
      // Ver el comentario equivalente en login: un JSON malformado lanza
      // `TypeError` (un `Error`, no un `Exception`).
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'AuthRepositoryImpl.signUp');
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
