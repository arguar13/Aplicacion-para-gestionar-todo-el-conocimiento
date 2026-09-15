/// Cada línea de una transcripción —de YouTube o de un audio/video
/// transcripto— puede empezar con su marca de tiempo entre corchetes:
/// `[2:07]` o, pasada la hora, `[1:02:07]`. Es lo que arma
/// `formatTranscript` en `youtube_transcript_transformer.dart`.
final _timestampLine = RegExp(r'^\[\d{1,2}(?::\d{2}){1,2}\]\s*', multiLine: true);

/// Si el contenido tiene al menos una línea con marca de tiempo.
///
/// Se usa para decidir si ofrecer la acción de quitarlas: no tiene sentido
/// mostrar el botón sobre un artículo o una nota que nunca tuvo una.
bool hasTimestamps(String content) => _timestampLine.hasMatch(content);

/// Saca las marcas de tiempo y junta las líneas en párrafos de lectura
/// corrida, en vez de dejarlas separadas una por una.
///
/// Es una transformación con pérdida a propósito: el pedido es leer la
/// transcripción como un texto normal, no navegarla por minuto. Quien
/// necesite volver a un momento exacto del video todavía tiene el enlace al
/// original, en la procedencia del elemento.
String stripTimestamps(String content) {
  final withoutStamps = content.replaceAll(_timestampLine, '');
  final lines = withoutStamps
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return lines.join(' ');
}
