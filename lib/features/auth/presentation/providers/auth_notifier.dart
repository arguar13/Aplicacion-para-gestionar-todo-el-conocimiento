import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/session/session_controller.dart';
import 'package:sinapsis/core/session/session_providers.dart';
import 'package:sinapsis/features/auth/domain/usecases/login_usecase.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_providers.dart';
import 'package:sinapsis/features/auth/presentation/providers/auth_state.dart';

/// Único punto donde vive la lógica de login: valida nada (eso lo hace la
/// UI antes de llamar), orquesta el `LoginUseCase` y traduce el resultado
/// a [AuthState]. La UI solo escucha este estado, nunca llama a Dio ni al
/// repositorio directamente.
///
/// [AuthState] es solo para la UI de esta pantalla (loading/error del
/// formulario); la sesión de la app la marca [SessionController] — por
/// eso un login exitoso actualiza los dos.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required LoginUseCase loginUseCase,
    required AppLogger logger,
    required SessionController sessionController,
  }) : _loginUseCase = loginUseCase,
       _logger = logger,
       _sessionController = sessionController,
       super(const AuthState.initial());

  final LoginUseCase _loginUseCase;
  final AppLogger _logger;
  final SessionController _sessionController;

  Future<void> login({required String email, required String password}) async {
    state = const AuthState.loading();

    final result = await _loginUseCase(
      LoginParams(email: email, password: password),
    );

    result.match(
      (failure) {
        switch (failure) {
          case UnauthorizedFailure():
            _logger.warning('Login rechazado: credenciales inválidas.');
          case ServerFailure() ||
              NetworkFailure() ||
              ValidationFailure() ||
              UnexpectedFailure():
            _logger.error('Login falló: ${failure.runtimeType}', failure);
          case CacheFailure():
            _logger.error(
              'Login falló guardando el token localmente.',
              failure,
            );
        }
        state = AuthState.error(_messageFor(failure));
      },
      (user) {
        state = AuthState.success(user);
        _sessionController.markAuthenticated();
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

final authNotifierProvider =
    StateNotifierProvider.autoDispose<AuthNotifier, AuthState>((ref) {
      return AuthNotifier(
        loginUseCase: ref.watch(loginUseCaseProvider),
        logger: ref.watch(appLoggerProvider),
        sessionController: ref.watch(sessionControllerProvider.notifier),
      );
    });
