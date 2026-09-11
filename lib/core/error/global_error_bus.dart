import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Envuelve la excepción en un identificador único para que dos fallos
/// consecutivos e idénticos (p. ej. dos timeouts seguidos con el mismo
/// mensaje) sigan disparando el listener las dos veces — un
/// `StateNotifier<Exception?>` a secas deduplicaría por `==` y la segunda
/// nunca se mostraría.
class GlobalErrorEvent {
  GlobalErrorEvent(this.exception) : id = _nextId++;

  static int _nextId = 0;

  final Exception exception;
  final int id;
}

/// Bus transversal de errores de red/dominio: cualquier capa `data` que no
/// tenga —o no quiera depender de— una pantalla propia para mostrar el
/// fallo, reporta acá (ver `GlobalErrorInterceptor`) y `GlobalErrorListener`
/// (en `app/`) lo traduce a un mensaje amigable sin importar en qué
/// pantalla esté montado.
class GlobalErrorNotifier extends StateNotifier<GlobalErrorEvent?> {
  GlobalErrorNotifier() : super(null);

  void report(Exception exception) => state = GlobalErrorEvent(exception);
}

final globalErrorNotifierProvider =
    StateNotifierProvider<GlobalErrorNotifier, GlobalErrorEvent?>(
      (ref) => GlobalErrorNotifier(),
    );
