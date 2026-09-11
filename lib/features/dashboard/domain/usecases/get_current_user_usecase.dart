import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/user.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/dashboard/domain/repositories/dashboard_repository.dart';

class GetCurrentUserUseCase implements UseCase<User, NoParams> {
  const GetCurrentUserUseCase(this._repository);

  final DashboardRepository _repository;

  @override
  Future<Either<Failure, User>> call(NoParams params) {
    return _repository.getCurrentUser();
  }
}
