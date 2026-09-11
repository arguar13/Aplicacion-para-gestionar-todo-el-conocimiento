import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que ve el usuario cuando la URL no corresponde a ninguna ruta: el
/// `errorBuilder` del `GoRouter`.
///
/// No es una pantalla de desarrollo. En Web la barra de direcciones es
/// parte de la interfaz —se tipea, se comparte, se guarda en favoritos y
/// queda desactualizada cuando una ruta cambia—, así que este es un estado
/// de usuario real y necesita lo que necesita cualquier otro: texto
/// traducido, estilo del tema y una salida. Antes mostraba un
/// `PlaceholderScreen` con el string 'Ruta no encontrada: ...' escrito a
/// mano en español, que ni se traducía ni ofrecía a dónde ir.
class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({required this.uri, super.key});

  /// La dirección que no se pudo resolver. Se muestra tal cual: es el
  /// único dato que le permite a alguien entender qué salió mal (un enlace
  /// viejo, una letra de más) o reportarlo con precisión.
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.explore_off_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.routeNotFoundTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.routeNotFoundMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _FailedAddress(uri: uri),
                  const SizedBox(height: 24),
                  FilledButton(
                    // Al splash y no al dashboard: es el único destino que
                    // no presupone si hay sesión o no. El route guard lo
                    // resuelve solo (ver `app_router.dart`), mandando a
                    // /dashboard o a /login según corresponda, así esta
                    // pantalla no necesita saber nada de la sesión.
                    onPressed: () => context.go(RoutePaths.splash),
                    child: Text(l10n.routeNotFoundAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La dirección fallida, tratada como el dato técnico que es: fuente
/// monoespaciada y un fondo tenue que la separa del texto explicativo sin
/// competir con él.
class _FailedAddress extends StatelessWidget {
  const _FailedAddress({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        uri.toString(),
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
