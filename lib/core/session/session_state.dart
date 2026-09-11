import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_state.freezed.dart';

/// Estado de sesión app-wide. Solo modela "¿hay sesión o no?" para el
/// route guard — el perfil del usuario (`User`) lo pide cada feature que
/// lo necesite (ver `dashboard`), no vive aquí.
///
/// [SessionUnknown] es el estado inicial mientras se lee el almacenamiento
/// seguro al arrancar la app; el router lo usa para quedarse en el splash.
@freezed
sealed class SessionState with _$SessionState {
  const factory SessionState.unknown() = SessionUnknown;
  const factory SessionState.authenticated() = SessionAuthenticated;
  const factory SessionState.unauthenticated() = SessionUnauthenticated;
}
