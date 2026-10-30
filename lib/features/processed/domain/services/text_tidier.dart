import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

/// Quien ordena el texto extraído de una fuente al triarla (F45, decisión B):
/// la IA de turno —Gemma en el teléfono o el proveedor en la nube—.
///
/// Interfaz propia, como `StudyMarker`: quien ordena un documento no tiene
/// por qué saber de motores, ventanas ni turnos.
abstract interface class TextTidier {
  /// Cuántos caracteres conviene darle por pedido: lo que entra en la ventana
  /// del modelo elegido junto con lo que contesta, que mide lo mismo.
  int get tidyPartChars;

  /// Ordena [text], un pedazo de la extracción: lo que contesta el modelo,
  /// tal cual. Quien llama lo comprueba (`checkTidiedText`) antes de usarlo.
  ///
  /// Lanza [TidyPartTooLong] si el pedido no entra en la ventana —el texto
  /// cuenta más tokens de lo común—, y lo que lance el modelo si no está
  /// listo o falla —sin conexión, sin cuota—.
  Future<String> tidyPart(String text);
}

/// El pedazo no entra en la ventana del modelo: hay que partirlo.
class TidyPartTooLong implements Exception {
  const TidyPartTooLong();

  @override
  String toString() => 'TidyPartTooLong';
}

/// Cuántos caracteres de texto se le dan por pedido a un modelo con
/// [contextTokens] de ventana para ordenarlos: lo que contesta mide lo mismo
/// que lo que lee, así que la ventana se reparte por mitades, con lugar para
/// la instrucción. Nunca más que una página del texto de un documento
/// procesado ([kProcessedTextPageChars]): se ordena de a una.
///
/// Con Gemma (2048 tokens), unos 2.600 caracteres; con un modelo en la nube,
/// una página entera.
int tidyPartCharBudget(int contextTokens) =>
    ((contextTokens - 320) * 3 ~/ 2).clamp(600, kProcessedTextPageChars);

/// Cuántos tokens puede escribir el modelo al ordenar [chars] caracteres: lo
/// mismo que lee, contado con holgura —tres caracteres por token—, y un
/// margen para los renglones que agrega.
int tidyReplyTokens(int chars) => (chars ~/ 3 + 64).clamp(128, 4096);

/// Lo que contestó el modelo, sin lo que lo envuelve: los espacios de las
/// puntas y un bloque de código (```) alrededor de todo, que algunos modelos
/// agregan aunque se les pida que no.
String cleanTidyReply(String reply) {
  final text = reply.trim();
  final fenced = RegExp(r'^```[^\n]*\n([\s\S]*?)\n?```$').firstMatch(text);
  return (fenced?.group(1) ?? text).trim();
}

/// Los pedazos en que se ordena [page], una página de la extracción, de
/// hasta [maxChars] caracteres: donde menos rompen (`splitIntoParts`). Uno
/// detrás del otro, son la página entera.
List<TextPart> tidyPieces(String page, int maxChars) =>
    splitIntoParts(page, maxChars: maxChars);

/// [piece] con su centro cambiado por [core]: los espacios y renglones de sus
/// puntas se conservan, para que la página quede unida como estaba entre
/// pedazo y pedazo.
String withTidiedCore(String piece, String core) {
  final lead = RegExp(r'^\s*').firstMatch(piece)!.group(0)!;
  final trail = piece.trim().isEmpty
      ? ''
      : RegExp(r'\s*$').firstMatch(piece)!.group(0)!;
  return '$lead$core$trail';
}
