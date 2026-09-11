import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:cristo_es_el_salvador/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:fpdart/fpdart.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl({
    required DashboardRemoteDataSource remoteDataSource,
    required TelemetryService telemetry,
  }) : _remoteDataSource = remoteDataSource,
       _telemetry = telemetry;

  final DashboardRemoteDataSource _remoteDataSource;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, User>> getCurrentUser() async {
    try {
      final userDto = await _remoteDataSource.getCurrentUser();
      return right(userDto.toEntity());
    } on UnauthorizedException catch (e) {
      return left(Failure.unauthorized(message: e.message));
    } on ServerException catch (e) {
      return left(Failure.server(message: e.message, statusCode: e.statusCode));
    } on NetworkException catch (e) {
      return left(Failure.network(message: e.message));
      // Ver el comentario equivalente en AuthRepositoryImpl.login: un JSON
      // malformado lanza `TypeError` (un `Error`, no un `Exception`) — por
      // eso además se reporta a telemetría: a diferencia de las ramas de
      // arriba, esta sí es siempre un bug (del cliente o del contrato con
      // el backend), nunca una condición esperada del usuario.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'DashboardRepositoryImpl.getCurrentUser',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
