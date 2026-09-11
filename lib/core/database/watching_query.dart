import 'dart:async';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';

/// Convierte una lectura puntual en un stream que se actualiza solo cuando
/// cambia alguna de [tables].
///
/// Existe por un bug real que costó encontrar: pedirle a drift la lectura
/// *dentro* de su propio flujo de notificación revienta con "Cannot add
/// event while adding stream", porque reentra en su controlador. La primera
/// solución que se probó —un `asyncMap` sobre el stream de cambios— compiló
/// y pasó las pruebas, pero tenía un bug peor y silencioso: como las
/// notificaciones de drift son un stream *broadcast*, un cambio que llegara
/// mientras la lectura anterior seguía en curso se perdía sin más. Alguien
/// podía guardar algo y no verlo aparecer hasta el próximo cambio, si es que
/// llegaba alguno.
///
/// Esta versión encola: si llega un cambio mientras se está leyendo, no se
/// dispara una segunda lectura en paralelo —eso multiplicaría consultas sin
/// necesidad— sino que se anota y, al terminar la que está en curso, se
/// vuelve a leer una vez más. Ninguna escritura se pierde y nunca hay dos
/// lecturas de la misma consulta corriendo a la vez.
Stream<T> watchQuery<T>({
  required GeneratedDatabase db,
  required Iterable<TableInfo<dynamic, dynamic>> tables,
  required Future<T> Function() read,
  required TelemetryService telemetry,
  required String hint,
}) {
  late final StreamController<T> controller;
  StreamSubscription<void>? changes;
  var isReading = false;
  var changedWhileReading = false;

  Future<void> refresh() async {
    if (isReading) {
      changedWhileReading = true;
      return;
    }

    isReading = true;
    try {
      do {
        changedWhileReading = false;
        final value = await read();
        if (!controller.isClosed) controller.add(value);
      } while (changedWhileReading);
      // Catch-all deliberado: un fallo al recomponer viaja por el stream en
      // vez de quedar en una excepción sin dueño, así que quien observa
      // puede mostrar el error en vez de quedarse esperando una emisión que
      // nunca va a llegar. Un `TypeError` es tan válido de reportar acá como
      // cualquier `Exception`.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      telemetry.recordError(e, stackTrace, hint: hint);
      if (!controller.isClosed) controller.addError(e, stackTrace);
    } finally {
      isReading = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      changes = db
          .tableUpdates(TableUpdateQuery.onAllTables(tables))
          .listen((_) => unawaited(refresh()));

      // El primer valor sale sin esperar a que cambie nada: quien se
      // suscribe quiere ver lo que hay ahora.
      unawaited(refresh());
    },
    onCancel: () async {
      await changes?.cancel();
    },
  );

  return controller.stream;
}
