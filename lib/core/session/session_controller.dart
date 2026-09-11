import 'package:cristo_es_el_salvador/core/logging/app_logger.dart';
import 'package:cristo_es_el_salvador/core/network/token_storage.dart';
import 'package:cristo_es_el_salvador/core/session/session_state.dart';
import 'package:cristo_es_el_salvador/core/telemetry/telemetry_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Única fuente de verdad de "¿el usuario tiene sesión?" para toda la app.
/// El router lo observa (vía `refreshListenable`) para expulsar/dejar
/// entrar; `AuthNotifier` lo marca autenticado tras un login exitoso; el
/// interceptor de red lo desloguea cuando el backend responde 401.
class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required TokenStorage tokenStorage,
    required AppLogger logger,
    required TelemetryService telemetry,
  }) : _tokenStorage = tokenStorage,
       _logger = logger,
       _telemetry = telemetry,
       super(const SessionState.unknown());

  final TokenStorage _tokenStorage;
  final AppLogger _logger;
  final TelemetryService _telemetry;

  /// Se llama una sola vez al arrancar la app (desde el splash). No valida
  /// el token contra el backend: solo mira si hay uno guardado. Si está
  /// vencido, la primera petición autenticada devolverá 401 y
  /// [logout] se encargará de sacarlo — evita un round-trip extra solo
  /// para decidir la ruta inicial.
  Future<void> checkInitialSession() async {
    if (state is! SessionUnknown) return;
    try {
      final token = await _tokenStorage.readAccessToken();
      state = (token != null && token.isNotEmpty)
          ? const SessionState.authenticated()
          : const SessionState.unauthenticated();
    } on Exception catch (e, stackTrace) {
      _logger.error('No se pudo leer la sesión guardada.', e, stackTrace);
      state = const SessionState.unauthenticated();
    }
  }

  void markAuthenticated() {
    state = const SessionState.authenticated();
  }

  /// Borra el token y cambia el estado; no navega. El router reacciona
  /// solo porque escucha este provider (ver `app/router/app_router.dart`).
  /// También borra el id de usuario asociado a los reportes de telemetría
  /// — que un reporte posterior (de una sesión distinta, en el mismo
  /// proceso) no quede atribuido a quien ya cerró sesión.
  Future<void> logout() async {
    await _tokenStorage.clearTokens();
    _telemetry.setUserContext(null);
    state = const SessionState.unauthenticated();
  }
}
