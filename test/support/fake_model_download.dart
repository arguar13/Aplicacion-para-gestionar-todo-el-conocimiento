import 'dart:async';

/// La descarga de [controller] como la de un gestor de modelos de verdad:
/// si termina sin error, el modelo queda listo ([markReady]) —su `isReady`
/// lo dice desde ahí—; si falla, no.
///
/// Lo usan los gestores falsos: la pantalla ya no se cree «listo» porque la
/// descarga terminó, le vuelve a preguntar al gestor.
Stream<double> readyWhenDone(
  StreamController<double> controller,
  void Function() markReady,
) {
  var failed = false;
  return controller.stream.transform(
    StreamTransformer.fromHandlers(
      handleError: (error, stackTrace, sink) {
        failed = true;
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        if (!failed) markReady();
        sink.close();
      },
    ),
  );
}
