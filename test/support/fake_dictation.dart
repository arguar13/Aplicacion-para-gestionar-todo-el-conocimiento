import 'dart:async';

import 'package:sinapsis/features/chat/domain/services/dictation.dart';

/// Un reconocimiento de voz de mentira (F42): la prueba dice si hay y «habla»
/// por [say], [finish] y [fail], como lo haría el teléfono.
class FakeDictation implements Dictation {
  FakeDictation({this.available = false});

  /// Lo que contesta [isAvailable].
  bool available;

  /// Cada idioma con que se pidió escuchar, en orden.
  final listenedIn = <String?>[];

  /// Cuántas veces se pidió [stop].
  int stops = 0;

  StreamController<DictationUpdate>? _current;

  /// Si está escuchando ahora.
  bool get listening => _current != null && !_current!.isClosed;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<DictationUpdate> listen({String? localeTag}) {
    listenedIn.add(localeTag);
    final controller = StreamController<DictationUpdate>();
    controller.onCancel = () async {
      if (identical(_current, controller)) _current = null;
    };
    _current = controller;
    return controller.stream;
  }

  /// Lo oído hasta ahora, entero.
  void say(String text, {bool isFinal = false}) =>
      _current!.add(DictationHeard(text, isFinal: isFinal));

  /// El volumen de la voz.
  void level(double value) => _current!.add(DictationLevel(value));

  /// Termina la frase con [text] —o sin nada— como lo último.
  Future<void> finish([String? text]) async {
    final current = _current!;
    if (text != null) current.add(DictationHeard(text, isFinal: true));
    _current = null;
    await current.close();
  }

  /// Termina con [error].
  Future<void> fail(Object error) async {
    final current = _current!;
    _current = null;
    current.addError(error);
    await current.close();
  }

  @override
  Future<void> stop() async {
    stops++;
    if (_current != null) await finish();
  }
}
