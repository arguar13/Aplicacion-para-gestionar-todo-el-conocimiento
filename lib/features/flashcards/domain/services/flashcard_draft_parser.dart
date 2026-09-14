import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';

final _questionLine = RegExp(r'^P:\s*(.+)$', caseSensitive: false);
final _answerLine = RegExp(r'^R:\s*(.+)$', caseSensitive: false);

/// Interpreta la respuesta cruda del modelo de lenguaje como una lista de
/// tarjetas.
///
/// Función pura a propósito, aparte de quien habla con el modelo: lo único
/// que puede fallar acá es el formato de un texto, y eso se prueba sin
/// necesitar ningún modelo de lenguaje de verdad corriendo.
///
/// El formato esperado es una línea `P: ...` seguida de una `R: ...`, y
/// nada más —ni Markdown, ni numeración, ni comillas—: cuanto más simple el
/// formato pedido, menos formas tiene el modelo de desviarse de él. Un
/// modelo de 1B de parámetros no es tan confiable siguiendo instrucciones
/// como uno mucho más grande, así que el parser es tolerante a título de
/// diseño: una línea que no matchea ninguno de los dos patrones se ignora
/// en silencio, en vez de descartar la tarjeta entera o hacer fallar todo
/// el lote por una sola línea rara.
List<FlashcardDraft> parseFlashcardDrafts(String rawResponse) {
  final drafts = <FlashcardDraft>[];
  String? pendingFront;

  for (final rawLine in rawResponse.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final question = _questionLine.firstMatch(line);
    if (question != null) {
      pendingFront = question.group(1)!.trim();
      continue;
    }

    final answer = _answerLine.firstMatch(line);
    final front = pendingFront;
    if (answer != null && front != null && front.isNotEmpty) {
      final back = answer.group(1)!.trim();
      if (back.isNotEmpty) drafts.add(FlashcardDraft(front: front, back: back));
      pendingFront = null;
    }
  }

  return drafts;
}
