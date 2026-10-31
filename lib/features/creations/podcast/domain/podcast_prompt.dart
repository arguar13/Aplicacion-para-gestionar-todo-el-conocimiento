/// Lo que se le pide a la IA para el guion de un podcast (F47, punto 5 del
/// plan). Breve —con Gemma, la tarea y el esquema entran en la reserva del
/// pedido— y en español, como las demás tareas de «Lo creado»: el idioma del
/// guion lo pone la instrucción de siempre (`structuredInstruction`).
library;

import 'package:sinapsis/features/creations/podcast/domain/podcast_check.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// Lo menos y lo más que puede tener una vuelta, en por ciento de lo que se
/// le pide: lo que acepta la comprobación, y lo que se le dice a la IA. En
/// enteros, para que el rango no dependa del redondeo de un decimal.
const kPodcastMinPercent = 70;
const kPodcastMaxPercent = 140;

/// El rango de palabras que se acepta para [target]: `(lo, hi)`.
(int, int) podcastWordRange(int target) => (
  target * kPodcastMinPercent ~/ 100,
  (target * kPodcastMaxPercent + 99) ~/ 100,
);

/// La forma del JSON del guion, con un ejemplo de cada clase de tramo. En la
/// conversación, con las dos voces; en los demás formatos, todo de la A.
String podcastSchemaPrompt(PodcastFormat format) {
  final second = format.speakerCount == 2 ? 'B' : 'A';
  return '{\n'
      '  "title": "título del episodio",\n'
      '  "segments": [\n'
      '    {"speaker": "A", "kind": "link", "text": "una frase corta que '
      'abre, pregunta o une, sin datos"},\n'
      '    {"speaker": "$second", "kind": "data", "text": "lo que se dice, '
      'con lo del material, para escuchar", "quotes": [{"source": "título '
      'del documento", "quote": "palabras copiadas tal cual del '
      'material"}]},\n'
      '    {"speaker": "A", "kind": "data", "text": "…", "quotes": [{"source": '
      '"…", "quote": "…"}], "pause": "long"}\n'
      '  ]\n'
      '}';
}

/// Cómo se cuenta cada formato.
String podcastFormatGuide(PodcastFormat format) => switch (format) {
  PodcastFormat.brief =>
    'breve, de una sola voz (la A), directo a lo esencial, sin rodeos ni '
        'relleno',
  PodcastFormat.lesson =>
    'una clase de una sola voz (la A), para aprender: explica de a una idea, '
        'con los ejemplos que trae el material, le hace preguntas a quien '
        'escucha —con una pausa larga después de cada una para pensar— y '
        'después las responde',
  PodcastFormat.story =>
    'contado como un relato, de una sola voz (la A), con un hilo en orden y '
        'que despierte interés, sin inventar nada: lo que no está en el '
        'material no se cuenta, ni siquiera para ambientar',
  PodcastFormat.conversation =>
    'una conversación entre dos voces, la A y la B: la A conduce, presenta y '
        'pregunta; la B explica con lo del material; se repreguntan y se '
        'turnan seguido, con tramos cortos, y las dos hablan en cada parte del '
        'guion',
};

/// Las reglas de los tramos y las citas: lo que después se comprueba
/// (`PodcastChecker`).
const _rules =
    'Escribí por tramos: cada tramo es lo que dice una voz de corrido, de una '
    'a tres oraciones cortas y naturales, para escuchar —nada de viñetas, '
    'títulos, Markdown ni emojis—. Cada tramo que dice algo del material va '
    'con "kind": "data" y lleva en "quotes" al menos una cita: entre 5 y 25 '
    'palabras seguidas copiadas TAL CUAL del material, con el título de su '
    'documento en "source". No digas nada que no esté en el material: ni '
    'datos, ni fechas, ni cifras, ni nombres, ni la duración del episodio. '
    'Los tramos que solo abren, preguntan o unen van con "kind": "link", '
    'cortos (menos de $kPodcastMaxLinkWords palabras) y sin datos ni cifras. '
    'Pedí "pause": "long" solo donde haga falta pensar o asentar algo';

/// La tarea de una vuelta del guion: [round] de [rounds] (desde 0), de unas
/// [words] palabras. [previous] es cómo terminó la vuelta anterior, para
/// seguir sin repetir. Con varias vueltas sobre el mismo material
/// ([sharedMaterial]), cada una trata su parte, en orden.
String podcastTask({
  required PodcastFormat format,
  required int words,
  int round = 0,
  int rounds = 1,
  String? previous,
  bool sharedMaterial = false,
}) {
  final (lo, hi) = podcastWordRange(words);
  final single = rounds == 1;
  final what = single
      ? 'el guion de un episodio de podcast'
      : 'la parte ${round + 1} de $rounds del guion de un episodio de podcast';
  final buffer = StringBuffer('escribir $what, ${podcastFormatGuide(format)}. ')
    ..write(
      '${single ? 'El guion' : 'Esta parte'} tiene que tener unas $words '
      'palabras dichas (entre $lo y $hi), sin contar las citas. ',
    )
    ..write('$_rules. ');
  if (rounds > 1) {
    buffer.write(switch (round) {
      0 =>
        'Abrí el episodio con una presentación corta del tema y no lo '
            'cierres: sigue en la parte siguiente. ',
      _ when round == rounds - 1 =>
        'Seguí donde quedó la parte anterior, sin saludar ni presentar de '
            'nuevo, y cerrá el episodio con un final breve que recoja lo '
            'esencial. ',
      _ =>
        'Seguí donde quedó la parte anterior, sin saludar ni presentar de '
            'nuevo, y no lo cierres: sigue en la parte siguiente. ',
    });
    if (sharedMaterial) {
      buffer.write(
        'Tratá, en orden, lo que le toca a esta parte: el tramo '
        '${round + 1} de $rounds del material. ',
      );
    }
    final last = previous?.trim();
    if (last != null && last.isNotEmpty) {
      buffer.write(
        'Así terminó la parte anterior, para no repetirla: «$last». ',
      );
    }
  } else {
    buffer.write(
      'Abrí con una presentación corta y cerrá con un final breve. ',
    );
  }
  return buffer.toString().trim();
}

/// Lo que se le pide a UNA parte del material, por partes: los tramos que
/// esa parte aporta, para que el paso de unir arme la vuelta.
String podcastPartTask({required PodcastFormat format, required int words}) =>
    'armar el borrador de los tramos que aporta esta parte del material al '
    'guion de un podcast ${podcastFormatGuide(format)}: unas $words palabras '
    'dichas. $_rules. Sin saludos ni cierres: eso se arma al unir';

/// Lo que se hace con los borradores de las partes: unirlos en una vuelta del
/// guion, con las citas tal cual estaban.
String podcastMergeTask({
  required PodcastFormat format,
  required int words,
  int round = 0,
  int rounds = 1,
  String? previous,
}) {
  final task = podcastTask(
    format: format,
    words: words,
    round: round,
    rounds: rounds,
    previous: previous,
  );
  return 'unir en uno solo los borradores de tramos que se te dan —cada uno '
      'se armó con una parte del material, en orden—, sin repetir nada y '
      'conservando cada cita exactamente como estaba: no inventes citas ni '
      'las cambies. $task';
}
