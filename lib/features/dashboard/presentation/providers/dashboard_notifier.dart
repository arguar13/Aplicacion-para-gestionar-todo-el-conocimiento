import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/dashboard/domain/usecases/get_current_user_usecase.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:sinapsis/features/dashboard/presentation/providers/dashboard_state.dart';

/// Nota sobre 401: si `GET /me` expira, `UnauthorizedInterceptor`
/// (core/network) ya desloguea globalmente y el router saca al usuario del
/// dashboard antes de que nadie vea el mensaje de [DashboardState.error]
/// de esta llamada — igual lo seteamos para no dejar el estado colgado en
/// `loading` en el instante entre ambas cosas.
class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier({
    required GetCurrentUserUseCase getCurrentUser,
    required AppLogger logger,
    required TelemetryService telemetry,
  }) : _getCurrentUser = getCurrentUser,
       _logger = logger,
       _telemetry = telemetry,
       super(const DashboardState.initial());

  final GetCurrentUserUseCase _getCurrentUser;
  final AppLogger _logger;
  final TelemetryService _telemetry;

  Future<void> loadCurrentUser() async {
    state = const DashboardState.loading();

    final result = await _getCurrentUser(const NoParams());

    result.match(
      (failure) {
        _logger.error(
          'No se pudo cargar el perfil: ${failure.runtimeType}',
          failure,
        );
        state = DashboardState.error(_messageFor(failure));
      },
      // Único lugar de la app donde se conoce el `User` autenticado (ver
      // el comentario de clase): de acá sale el id que queda asociado a
      // los próximos reportes de telemetría. Nunca el nombre ni el email.
      (user) {
        _telemetry.setUserContext(user.id);
        state = DashboardState.loaded(user);
      },
    );
  }

  String _messageFor(Failure failure) {
    return switch (failure) {
      ServerFailure(:final message) => message,
      NetworkFailure(:final message) => message,
      UnauthorizedFailure(:final message) => message,
      ValidationFailure(:final message) => message,
      CacheFailure(:final message) => message,
      UnexpectedFailure(:final message) => message,
    };
  }
}

final dashboardNotifierProvider =
    StateNotifierProvider.autoDispose<DashboardNotifier, DashboardState>((ref) {
      return DashboardNotifier(
        getCurrentUser: ref.watch(getCurrentUserUseCaseProvider),
        telemetry: ref.watch(telemetryServiceProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });
