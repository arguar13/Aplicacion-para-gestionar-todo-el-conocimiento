/// Cada línea de una transcripción —de YouTube o de un audio/video
/// transcripto— puede empezar con su marca de tiempo entre corchetes:
/// `[2:07]` o, pasada la hora, `[1:02:07]`. Es lo que arma
/// `formatTranscript` en `youtube_transcript_transformer.dart`, y la
/// transcripción de un audio en `runSegmentedTranscription` (F22).
final _timestampLine = RegExp(
  r'^\[\d{1,2}(?::\d{2}){1,2}\]\s*',
  multiLine: true,
);

/// Si el contenido tiene al menos una línea con marca de tiempo.
///
/// Se usa para decidir si ofrecer la acción de quitarlas: no tiene sentido
/// mostrar el botón sobre un artículo o una nota que nunca tuvo una.
bool hasTimestamps(String content) => _timestampLine.hasMatch(content);

/// Saca la marca de tiempo del principio de cada línea, y nada más (F22).
///
/// Lo que el usuario pide es no ver los minutos, no que se toque lo dicho:
/// cada línea queda como estaba, en su lugar. Antes además juntaba todas las
/// líneas en un solo párrafo —y como se ofrecía en cualquier texto con una
/// línea que empezara como "[12:30]", destruía los párrafos de un PDF o un
/// Word—. Una línea que era solo su marca, sin texto, se va con ella.
String stripTimestamps(String content) => content
    .split('\n')
    .map((line) => (line, line.replaceFirst(_timestampLine, '')))
    .where((pair) => pair.$1 == pair.$2 || pair.$2.trim().isNotEmpty)
    .map((pair) => pair.$2)
    .join('\n');

/// `2:07` para lo que dura menos de una hora, `1:02:07` para lo que dura más.
///
/// No se usa siempre el formato largo porque la mayoría de los videos duran
/// minutos, y un `0:02:07` obliga a leer un cero que no aporta nada.
String formatTimestamp(Duration offset) {
  final hours = offset.inHours;
  final minutes = offset.inMinutes.remainder(60);
  final seconds = offset.inSeconds.remainder(60);

  final paddedSeconds = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$paddedSeconds';

  return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
}
