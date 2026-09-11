import 'dart:ui';

import 'package:cristo_es_el_salvador/core/error/failures.dart';
import 'package:cristo_es_el_salvador/core/i18n/locale_notifier.dart';
import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/logging/logger_provider.dart';
import 'package:cristo_es_el_salvador/core/session/session_controller.dart';
import 'package:cristo_es_el_salvador/core/session/session_providers.dart';
import 'package:cristo_es_el_salvador/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:cristo_es_el_salvador/features/auth/presentation/providers/auth_providers.dart';
import 'package:cristo_es_el_salvador/features/auth/presentation/providers/auth_state.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reutiliza [AuthState] (no un `SignUpState` propio): la forma es
/// idéntica a la del login —initial/loading/success/error— y ambas
/// representan lo mismo, "una acción de autenticación en curso".
///
/// La validación de que las contraseñas coincidan vive acá, no solo en la
/// UI: si no coinciden, el estado pasa a `error` directo, sin `loading`
/// de por medio, porque no hay nada asíncrono que esperar todavía.
///
/// Un `StateNotifier` no tiene `BuildContext`, así que no puede llamar
/// `AppLocalizations.of(context)`. En vez de eso recibe el `Locale`
/// efectivo ya resuelto (ver `effectiveLocaleProvider`) y usa
/// `lookupAppLocalizations`, la función que el propio código generado
/// expone justo para este caso (localizar fuera del árbol de widgets).
class SignUpNotifier extends StateNotifier<AuthState> {
  SignUpNotifier({
    required SignUpUseCase signUpUseCase,
    required AppLogger logger,
    required SessionController sessionController,
    required Locale locale,
  }) : _signUpUseCase = signUpUseCase,
       _logger = logger,
       _sessionController = sessionController,
       _l10n = lookupAppLocalizations(locale),
       super(const AuthState.initial());

  final SignUpUseCase _signUpUseCase;
  final AppLogger _logger;
  final SessionController _sessionController;
  final AppLocalizations _l10n;

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (password != confirmPassword) {
      state = AuthState.error(_l10n.passwordsDoNotMatchError);
      return;
    }

    state = const AuthState.loading();

    final result = await _signUpUseCase(
      SignUpParams(name: name, email: email, password: password),
    );

    result.match(
      (failure) {
        switch (failure) {
          case ValidationFailure():
            _logger.warning('Registro rechazado: ${failure.message}');
          case UnauthorizedFailure() ||
              ServerFailure() ||
              NetworkFailure() ||
              UnexpectedFailure():
            _logger.error('Registro falló: ${failure.runtimeType}', failure);
          case CacheFailure():
            _logger.error(
              'Registro falló guardando el token localmente.',
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

final signUpNotifierProvider =
    StateNotifierProvider.autoDispose<SignUpNotifier, AuthState>((ref) {
      return SignUpNotifier(
        signUpUseCase: ref.watch(signUpUseCaseProvider),
        logger: ref.watch(appLoggerProvider),
        sessionController: ref.watch(sessionControllerProvider.notifier),
        locale: ref.watch(effectiveLocaleProvider),
      );
    });
