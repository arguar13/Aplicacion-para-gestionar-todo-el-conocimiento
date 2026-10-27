import 'package:meta/meta.dart';

/// Habla a texto con el reconocimiento de voz del propio teléfono (F42): el
/// 🎤 del campo del chat.
///
/// Un contrato y no una llamada directa al sistema por lo mismo que
/// `FileChooser`: escuchar el micrófono de verdad es lo único de este camino
/// que no se puede probar. Detrás de esta interfaz, el campo se prueba
/// entero con un doble que «oye» lo que la prueba quiera.
///
/// En Android lo hace el `SpeechRecognizer` del sistema por un canal propio
/// (`DictationChannel`), sin dependencias nuevas; donde no hay reconocedor
/// —Windows, la web, un teléfono sin el servicio de voz— [isAvailable] es
/// `false` y el 🎤 no aparece.
abstract interface class Dictation {
  /// Si este dispositivo puede pasar habla a texto. No pide ningún permiso:
  /// se pregunta al abrir el chat, para saber si mostrar el 🎤.
  Future<bool> isAvailable();

  /// Escucha una frase y la da escrita mientras se dice.
  ///
  /// La primera vez pide el permiso del micrófono. Cada evento es un
  /// [DictationUpdate]: lo oído hasta ahí —entero, no lo nuevo— o el volumen
  /// de la voz. Termina sola cuando la persona hace una pausa, o con [stop];
  /// si no se oyó nada, termina sin texto. Si no hay permiso termina con
  /// [DictationPermissionDeniedException]; si el reconocedor falla, con
  /// [DictationFailedException].
  ///
  /// [localeTag] es el idioma en que se habla («es-AR»); `null`, el del
  /// teléfono. **Dejar de escucharla la cancela**: el reconocedor se suelta
  /// sin dar más texto.
  Stream<DictationUpdate> listen({String? localeTag});

  /// Deja de escuchar: lo dicho hasta acá se reconoce y llega como lo último
  /// de [listen], que después termina.
  Future<void> stop();
}

/// Algo que trae [Dictation.listen].
@immutable
sealed class DictationUpdate {
  const DictationUpdate();
}

/// Lo oído hasta ahora, entero. [isFinal] en lo último: lo que el
/// reconocedor da por bueno al terminar la frase.
final class DictationHeard extends DictationUpdate {
  const DictationHeard(this.text, {this.isFinal = false});

  final String text;
  final bool isFinal;
}

/// Qué tan fuerte llega la voz, de 0 (silencio) a 1: lo que hace latir el
/// 🎤 mientras escucha.
final class DictationLevel extends DictationUpdate {
  const DictationLevel(this.level);

  final double level;
}

/// La persona no dio permiso para usar el micrófono. Se distingue de un
/// error porque pide otra cosa: ir a los ajustes del sistema.
class DictationPermissionDeniedException implements Exception {
  const DictationPermissionDeniedException();

  @override
  String toString() => 'Sin permiso para usar el micrófono';
}

/// El reconocedor del sistema falló: sin red (algunos reconocen en la nube),
/// ocupado, o un error suyo. [code] es como lo nombra el sistema.
class DictationFailedException implements Exception {
  const DictationFailedException(this.code);

  final String code;

  @override
  String toString() => 'El reconocimiento de voz falló: $code';
}
