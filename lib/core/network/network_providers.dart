import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/error/global_error_bus.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/network/interceptors/auth_interceptor.dart';
import 'package:sinapsis/core/network/interceptors/error_interceptor.dart';
import 'package:sinapsis/core/network/interceptors/logging_interceptor.dart';
import 'package:sinapsis/core/network/interceptors/unauthorized_interceptor.dart';
import 'package:sinapsis/core/network/token_storage.dart';
import 'package:sinapsis/core/session/session_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';

/// Cliente HTTP base de la app. Cada `data source` de un feature debe
/// depender de este provider en vez de instanciar su propio `Dio`.
final dioProvider = Provider<Dio>((ref) {
  final logger = ref.watch(appLoggerProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: EnvConfig.current.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.addAll([
    AuthInterceptor(tokenStorage: tokenStorage),
    NetworkLoggingInterceptor(logger: logger),
    UnauthorizedInterceptor(
      onUnauthorized: () =>
          ref.read(sessionControllerProvider.notifier).logout(),
      logger: logger,
    ),
    GlobalErrorInterceptor(
      logger: logger,
      telemetry: ref.watch(telemetryServiceProvider),
      onDomainError: (exception) =>
          ref.read(globalErrorNotifierProvider.notifier).report(exception),
    ),
  ]);

  return dio;
});
