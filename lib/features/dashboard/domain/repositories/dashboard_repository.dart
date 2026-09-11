import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:fpdart/fpdart.dart';

// Contrato del dominio, de un solo método hoy porque el feature solo
// necesita esto; crecerá con más operaciones del dashboard.
// ignore: one_member_abstracts
abstract interface class DashboardRepository {
  Future<Either<Failure, User>> getCurrentUser();
}
