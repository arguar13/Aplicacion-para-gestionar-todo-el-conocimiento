import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';

// Contrato del dominio, de un solo método hoy porque el feature solo
// necesita esto; crecerá con más operaciones del dashboard.
// ignore: one_member_abstracts
abstract interface class DashboardRepository {
  Future<Either<Failure, User>> getCurrentUser();
}
