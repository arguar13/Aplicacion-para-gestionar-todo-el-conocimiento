import 'package:sinapsis/core/domain/entities/processed_section.dart';

/// El texto entero de un documento procesado, tal como lo leen la IA que
/// organiza y los vectores de los vínculos (F41, paso 6): lo que la persona
/// eligió al triar, y nada de la fuente que no haya elegido.
///
/// Un único lugar dice cómo se arma, para que quien guarda los vectores, quien
/// muestra el comienzo de un candidato y quien busca sus fechas lean el MISMO
/// texto, con las mismas posiciones:
///
/// - las secciones en el orden en que se leen ([ProcessedSection]) y cada parte
///   en su lugar;
/// - las páginas de «Texto» van pegadas, sin nada entre ellas: juntas
///   reproducen el texto copiado carácter por carácter (`processedTextPages`),
///   y una fecha que cae entre dos páginas sigue siendo una sola cita;
/// - todo lo demás —cada oración del resumen o de la síntesis, cada nota, cada
///   fragmento, y el paso de una sección a otra— va separado por un renglón en
///   blanco, para que dos partes que no estaban juntas en el original no se
///   lean como una oración.
const kProcessedPartSeparator = '\n\n';

/// Una parte, con lo justo para armar el texto: su sección y su texto. Las de
/// [joinProcessedParts] vienen ya en orden de lectura.
typedef ProcessedReadingPart = ({ProcessedSection section, String content});

/// El texto entero de [parts] —en orden de lectura— y dónde empieza cada una en
/// él (ver [kProcessedPartSeparator]). [ProcessedJoin.glued] dice, de cada
/// parte, si va pegada a la anterior: sin separador de por medio.
ProcessedJoin joinProcessedParts(List<ProcessedReadingPart> parts) {
  final text = StringBuffer();
  final starts = <int>[];
  final glued = <bool>[];
  ProcessedSection? previous;
  for (final part in parts) {
    final pasted =
        previous == ProcessedSection.text && part.section == previous;
    if (previous != null && !pasted) text.write(kProcessedPartSeparator);
    starts.add(text.length);
    glued.add(pasted);
    text.write(part.content);
    previous = part.section;
  }
  return ProcessedJoin(
    text: text.toString(),
    starts: List.unmodifiable(starts),
    glued: List.unmodifiable(glued),
  );
}

/// Lo que arma [joinProcessedParts].
class ProcessedJoin {
  const ProcessedJoin({
    required this.text,
    required this.starts,
    required this.glued,
  });

  final String text;

  /// Dónde empieza cada parte en [text], en el orden de las partes.
  final List<int> starts;

  /// Si cada parte va pegada a la anterior —dos páginas seguidas de «Texto»—.
  final List<bool> glued;
}
