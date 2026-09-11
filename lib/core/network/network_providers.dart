import 'package:cristo_es_el_salvador/core/config/env_config.dart';
import 'package:cristo_es_el_salvador/core/error/global_error_bus.dart';
import 'package:cristo_es_el_salvador/core/logging/logger_provider.dart';
import 'package:cristo_es_el_salvador/core/network/interceptors/auth_interceptor.dart';
import 'package:cristo_es_el_salvador/core/network/interceptors/error_interceptor.dart';
import 'package:cristo_es_el_salvador/core/network/interceptors/logging_interceptor.dart';
import 'package:cristo_es_el_salvador/core/network/interceptors/unauthorized_interceptor.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/session/session_providers.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
