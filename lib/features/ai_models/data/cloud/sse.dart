import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Un evento de una respuesta en vivo (Server-Sent Events): su nombre, si lo
/// tiene, y sus datos.
typedef SseEvent = ({String? event, String data});

/// Los eventos de [bytes], tal como llegan (F32): Gemini, OpenAI y Claude
/// mandan la respuesta así. Las líneas `data:` seguidas se juntan; una línea
/// vacía cierra el evento; los comentarios (`:`) se ignoran.
///
/// Los bytes se decodifican como UTF-8 sin partir caracteres: una letra con
/// acento puede llegar cortada entre dos pedazos de la red.
Stream<SseEvent> sseEvents(Stream<Uint8List> bytes) async* {
  String? event;
  final data = <String>[];

  SseEvent? flush() {
    if (data.isEmpty) {
      event = null;
      return null;
    }
    final out = (event: event, data: data.join('\n'));
    event = null;
    data.clear();
    return out;
  }

  final lines = bytes
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    if (line.isEmpty) {
      final out = flush();
      if (out != null) yield out;
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.add(value);
    }
  }
  final last = flush();
  if (last != null) yield last;
}
