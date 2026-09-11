import 'package:cristo_es_el_salvador/core/network/network_providers.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_provider.dart';
import 'package:cristo_es_el_salvador/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:cristo_es_el_salvador/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cristo_es_el_salvador/features/dashboard/domain/usecases/get_current_user_usecase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cascada de DI del feature: DataSource -> Repository -> UseCase.
final dashboardRemoteDataSourceProvider = Provider<DashboardRemoteDataSource>((
  ref,
) {
  return DashboardRemoteDataSourceImpl(ref.watch(dioProvider));
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(
    remoteDataSource: ref.watch(dashboardRemoteDataSourceProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>((ref) {
  return GetCurrentUserUseCase(ref.watch(dashboardRepositoryProvider));
});
