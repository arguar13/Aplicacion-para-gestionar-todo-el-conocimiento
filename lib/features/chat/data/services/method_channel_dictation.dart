import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sinapsis/features/chat/domain/services/dictation.dart';

/// [Dictation] en Android, con el `SpeechRecognizer` del sistema, por los
/// canales `app.sinapsis/dictation` (preguntar, pedir el permiso, cortar) y
/// `app.sinapsis/dictation/events` (lo que se va oyendo). Ver
/// `DictationChannel` del lado de Kotlin.
///
/// Sin paquetes: el reconocedor del sistema ya está en el teléfono, y un canal
/// propio deja preguntar si hay uno **sin pedir el permiso del micrófono**
/// —lo que ningún paquete de habla a texto ofrece: todos lo piden al
/// inicializarse, o sea al abrir el chat—. El permiso se pide la primera vez
/// que se toca el 🎤, con contexto.
class MethodChannelDictation implements Dictation {
  const MethodChannelDictation({
    MethodChannel methods = const MethodChannel('app.sinapsis/dictation'),
    EventChannel events = const EventChannel('app.sinapsis/dictation/events'),
  }) : _methods = methods,
       _events = events;

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
      // Sin el canal —una versión de la app sin él, una prueba— no hay
      // reconocedor: el 🎤 no se muestra, que es lo que corresponde.
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<DictationUpdate> listen({String? localeTag}) async* {
    final granted =
        await _methods.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) throw const DictationPermissionDeniedException();
    yield* _events
        .receiveBroadcastStream({'locale': ?localeTag})
        .transform(
          StreamTransformer<Object?, DictationUpdate>.fromHandlers(
            handleData: (event, sink) {
              final update = dictationUpdateFrom(event);
              if (update != null) sink.add(update);
            },
            handleError: (error, stackTrace, sink) => sink.addError(
              error is PlatformException
                  ? (error.code == 'permission'
                        ? const DictationPermissionDeniedException()
                        : DictationFailedException(error.code))
                  : error,
              stackTrace,
            ),
          ),
        );
  }

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

/// Lo que manda `DictationChannel` por cada evento, en Dart: `{type: heard,
/// text, final}` o `{type: level, value}`. `null` si no se entiende —un
/// evento de una versión más nueva—, que se ignora.
DictationUpdate? dictationUpdateFrom(Object? event) {
  if (event is! Map) return null;
  switch (event['type']) {
    case 'heard':
      final text = event['text'];
      if (text is! String) return null;
      return DictationHeard(text, isFinal: event['final'] == true);
    case 'level':
      final value = event['value'];
      if (value is! num) return null;
      return DictationLevel(value.toDouble().clamp(0, 1));
  }
  return null;
}
