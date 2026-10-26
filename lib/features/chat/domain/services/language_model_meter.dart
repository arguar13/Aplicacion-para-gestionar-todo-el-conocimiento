import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';

/// Dónde queda lo medido del modelo de lenguaje (F30): la última carga y la
/// última respuesta de cada tipo. Lo muestra la pantalla del modelo, en
/// Ajustes.
///
/// Se mide siempre, también en una versión de producción: los registros de
/// `flutter_gemma` (`gemmaLog`) solo existen en las de depuración, y lo que
/// importa medir es el teléfono de verdad con la app de verdad.
///
/// Cada respuesta se avisa también a quien la quiera contar ([addTap], F39):
/// lo que gastó una tarea de la IA sale de acá, de lo que de verdad contaron
/// el proveedor o el tokenizador de Gemma.
class LanguageModelMeter {
  final _performance = ValueNotifier(const LanguageModelPerformance());
  final _taps = <void Function(LanguageModelReply reply)>[];

  ValueListenable<LanguageModelPerformance> get performance => _performance;

  void recordLoad(LanguageModelLoad load) =>
      _performance.value = _performance.value.withLoad(load);

  /// Anota [reply] y se la da a cada oyente **en el acto y en la zona de quien
  /// la pidió**, no por un `Stream`: un oyente de un `Stream` corre en la zona
  /// donde se suscribió, y de ahí no se sabe de qué tarea es la respuesta.
  void recordReply(LanguageModelReply reply) {
    _performance.value = _performance.value.withReply(reply);
    for (final tap in List.of(_taps)) {
      tap(reply);
    }
  }

  /// Avisa a [tap] cada respuesta que se anote, hasta que se llame a lo que
  /// devuelve.
  void Function() addTap(void Function(LanguageModelReply reply) tap) {
    _taps.add(tap);
    return () => _taps.remove(tap);
  }
}

/// Cuántas palabras tiene [text]: lo que se separa por espacios.
int countWords(String text) => _word.allMatches(text).length;

final _word = RegExp(r'\S+');
