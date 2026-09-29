// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/transform/domain/services/audio_transcriber.dart';

/// Devuelve el texto que el test le ponga, sin ningún motor de verdad
/// detrás.
class FakeAudioTranscriber implements AudioTranscriber {
  FakeAudioTranscriber({this.text = ''});

  /// Lo que "transcribe" en cualquier archivo. Cadena vacía por defecto,
  /// igual que un video sin diálogo. Mutable a propósito: una prueba puede
  /// cambiarlo a mitad de camino.
  String text;

  /// Si está, se lanza en vez de devolver.
  Object? error;

  /// Las rutas que se le pidió transcribir, para comprobar en las pruebas
  /// que se le pide la absoluta y no la relativa que guarda la base.
  final requested = <String>[];

  /// La sesión de cada pedido, en orden.
  final sessions = <TranscriptionSession>[];

  @override
  Future<String> transcribe(
    String absolutePath, {
    TranscriptionSession session = TranscriptionSession.detached,
  }) async {
    requested.add(absolutePath);
    sessions.add(session);
    if (error != null) throw error!;

    return text;
  }
}
