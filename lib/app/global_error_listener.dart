import 'package:cristo_es_el_salvador/core/error/exceptions.dart';
import 'package:cristo_es_el_salvador/core/error/global_error_bus.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mecanismo visual global de feedback de errores: escucha
/// [globalErrorNotifierProvider] (alimentado por `GlobalErrorInterceptor`,
/// ver `core/network`) y muestra un SnackBar con un mensaje amigable sin
/// importar qué pantalla esté montada — así una petición que falla en
/// segundo plano nunca deja a la app en silencio ni a una pantalla colgada
/// en un estado de carga sin explicación.
///
/// Se usa desde el `builder` de `MaterialApp.router` en `app.dart`, un
/// nivel por encima del `Navigator`: `MaterialApp` ya coloca un
/// `ScaffoldMessenger` ahí mismo, así que este widget puede usar
/// `ScaffoldMessenger.of(context)` sin necesitar su propio `Scaffold`.
class GlobalErrorListener extends ConsumerWidget {
  const GlobalErrorListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<GlobalErrorEvent?>(globalErrorNotifierProvider, (
      previous,
      next,
    ) {
      if (next == null) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_messageFor(next.exception, l10n))),
        );
    });

    return child;
  }

  String _messageFor(Exception exception, AppLocalizations l10n) {
    return switch (exception) {
      NetworkException() => l10n.globalErrorNetwork,
      UnauthorizedException() => l10n.globalErrorUnauthorized,
      ServerException() => l10n.globalErrorServer,
      CacheException() => l10n.globalErrorServer,
      _ => l10n.globalErrorUnexpected,
    };
  }
}
