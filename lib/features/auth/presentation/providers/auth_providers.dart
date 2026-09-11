import 'package:cristo_es_el_salvador/core/network/network_providers.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_provider.dart';
import 'package:cristo_es_el_salvador/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/auth/data/datasources/sign_up_remote_data_source.dart';
import 'package:cristo_es_el_salvador/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/repositories/auth_repository.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/usecases/login_usecase.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cascada de DI del feature: DataSource -> Repository -> UseCase.
/// `presentation` solo debe depender de [loginUseCaseProvider] o
/// [signUpUseCaseProvider], nunca de `authRepositoryProvider`.
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSourceImpl(ref.watch(dioProvider));
});

final signUpRemoteDataSourceProvider = Provider<SignUpRemoteDataSource>((ref) {
  return SignUpRemoteDataSourceImpl(ref.watch(dioProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    remoteDataSource: ref.watch(authRemoteDataSourceProvider),
    signUpRemoteDataSource: ref.watch(signUpRemoteDataSourceProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(authRepositoryProvider));
});

final signUpUseCaseProvider = Provider<SignUpUseCase>((ref) {
  return SignUpUseCase(ref.watch(authRepositoryProvider));
});
