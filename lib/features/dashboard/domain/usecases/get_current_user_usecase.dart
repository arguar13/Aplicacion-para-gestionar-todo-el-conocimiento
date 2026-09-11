import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/usecase/usecase.dart';
import 'package:cristo_es_el_salvador/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:fpdart/fpdart.dart';

class GetCurrentUserUseCase implements UseCase<User, NoParams> {
  const GetCurrentUserUseCase(this._repository);

  final DashboardRepository _repository;

  @override
  Future<Either<Failure, User>> call(NoParams params) {
    return _repository.getCurrentUser();
  }
}
