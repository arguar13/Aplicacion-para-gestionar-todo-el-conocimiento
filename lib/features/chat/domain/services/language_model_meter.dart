import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';

/// Dónde queda lo medido del modelo de lenguaje (F30): la última carga y la
/// última respuesta de cada tipo. Lo muestra la pantalla del modelo, en
/// Ajustes.
///
/// Se mide siempre, también en una versión de producción: los registros de
/// `flutter_gemma` (`gemmaLog`) solo existen en las de depuración, y lo que
/// importa medir es el teléfono de verdad con la app de verdad.
class LanguageModelMeter {
  final _performance = ValueNotifier(const LanguageModelPerformance());

  ValueListenable<LanguageModelPerformance> get performance => _performance;

  void recordLoad(LanguageModelLoad load) =>
      _performance.value = _performance.value.withLoad(load);

  void recordReply(LanguageModelReply reply) =>
      _performance.value = _performance.value.withReply(reply);
}

/// Cuántas palabras tiene [text]: lo que se separa por espacios.
int countWords(String text) => _word.allMatches(text).length;

final _word = RegExp(r'\S+');
