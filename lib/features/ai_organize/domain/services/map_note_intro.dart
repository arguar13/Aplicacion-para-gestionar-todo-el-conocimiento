import 'package:flutter/foundation.dart';

/// Lo que el modelo ve de un elemento para escribir la introducción de una
/// nota mapa (F27, el Atlas): su título y un fragmento.
@immutable
class MapIntroEntry {
  const MapIntroEntry({required this.title, this.excerpt = ''});

  final String title;

  /// El comienzo de su texto, o vacío si no tiene.
  final String excerpt;

  @override
  bool operator ==(Object other) =>
      other is MapIntroEntry &&
      other.title == title &&
      other.excerpt == excerpt;

  @override
  int get hashCode => Object.hash(title, excerpt);
}

/// Escribe la introducción de la nota mapa del tema [topic] a partir de
/// [entries] (F27), con el modelo de lenguaje del chat
/// —`GemmaChatModel.writeMapIntroduction`—. Devuelve la respuesta tal cual;
/// la limpia [cleanMapIntro]. Vacía si el modelo no dijo nada.
///
/// Una función y no una interfaz, como `SpaceChooser`.
typedef MapIntroWriter =
    Future<String> Function({
      required String topic,
      required List<MapIntroEntry> entries,
    });

/// Cuánto texto ve el modelo, como mucho, para escribir la introducción: el
/// pedido entero —el tema y los elementos— en unos 3.000 caracteres, cerca de
/// 900 tokens. Con las instrucciones (~150) y la respuesta (~200) entra
/// holgado en la ventana de 2048 tokens del modelo del teléfono. Un tema con
/// cientos de elementos no se manda entero: se mandan los primeros que
/// entran, que quien llama ordena por importancia.
const kMapIntroPromptChars = 3000;

/// Cuánto de cada elemento: el comienzo alcanza para decir de qué trata.
const kMapIntroExcerptChars = 220;

/// Cuánto puede ocupar la introducción en la nota: dos o tres oraciones. Lo
/// que el modelo escriba de más se corta en la última oración entera.
const kMapIntroMaxChars = 600;

/// Lo que se le manda al modelo: el tema y, uno por línea, el título y el
/// fragmento de cada elemento, hasta [maxChars]. Función pura: lo que se
/// prueba es que nunca pase del tope, sea cual sea el tema.
String buildMapIntroPrompt({
  required String topic,
  required List<MapIntroEntry> entries,
  int maxChars = kMapIntroPromptChars,
}) {
  final buffer = StringBuffer('Tema: ${_cut(topic, 120)}\n\nElementos:\n');
  for (final entry in entries) {
    final excerpt = _cut(_oneLine(entry.excerpt), kMapIntroExcerptChars);
    final line =
        '- ${_cut(_oneLine(entry.title), 160)}'
        '${excerpt.isEmpty ? '' : ': $excerpt'}\n';
    if (buffer.length + line.length > maxChars) break;
    buffer.write(line);
  }
  return buffer.toString().trimRight();
}

final _markup = RegExp(r'[\[\]*#`]');
final _spaces = RegExp(r'\s+');
final _sentenceEnd = RegExp(r'[.!?…]["»”)]?(?=\s|$)');

/// La introducción tal como va en la nota: un solo párrafo, sin la marca que
/// el modelo haya puesto —ningún `[[ ]]`: los enlaces de una nota mapa los
/// arma la app con lo que hay en la bóveda, nunca el modelo— y sin pasar de
/// [maxChars], cortada en la última oración entera. Vacía si no queda nada.
String cleanMapIntro(String raw, {int maxChars = kMapIntroMaxChars}) {
  final text = raw.replaceAll(_markup, '').replaceAll(_spaces, ' ').trim();
  if (text.length <= maxChars) return text;
  final head = text.substring(0, maxChars);
  final ends = _sentenceEnd.allMatches(head).toList();
  if (ends.isNotEmpty) return head.substring(0, ends.last.end).trim();
  final space = head.lastIndexOf(' ');
  return '${head.substring(0, space > 0 ? space : maxChars).trim()}…';
}

String _oneLine(String text) => text.replaceAll(_spaces, ' ').trim();

/// [text] hasta [max] caracteres, cortado en una palabra entera.
String _cut(String text, int max) {
  if (text.length <= max) return text;
  final head = text.substring(0, max);
  final space = head.lastIndexOf(' ');
  return '${head.substring(0, space > max ~/ 2 ? space : max).trim()}…';
}
