/// Huecos para completar (F31): un texto con `{{c1::respuesta}}` o
/// `{{c1::respuesta::pista}}`, el mismo formato de Anki, del que salen una
/// tarjeta por cada número de hueco.
///
/// Nada acá toca la base, la pantalla ni el modelo de lenguaje: es puro,
/// texto adentro y texto afuera. Las pantallas piden las tarjetas con
/// [parseCloze] y dibujan los [ClozeSegment]; quien guarda sabe qué números
/// hay y cuál le toca a cada tarjeta.
///
/// **Gramática.** Un hueco empieza en `{{c` + dígitos + `::` y termina en el
/// primer `}}` que no cierra una llave abierta *dentro* de él: así
/// `{{c1::f(x) = {a}}}` tiene como respuesta `f(x) = {a}` y no `f(x) = {a`.
/// El primer `::` de adentro separa la respuesta de la pista. Un hueco
/// anidado (`{{c1::el {{c2::Imperio}} romano}}`) no genera su propia tarjeta:
/// queda dentro de la respuesta del de afuera, ya revelado. Anki los admite;
/// acá no hacen falta y se prefiere no crear una tarjeta a partir de algo que
/// nadie escribió así a propósito.
///
/// **Texto que no es un hueco.** Una llave suelta, un `{{c1::` que nunca se
/// cierra o un `{{c0::` (Anki numera desde 1) quedan como texto común y
/// [validateCloze] lo avisa; nada se descarta en silencio. Los índices son de
/// unidades de código UTF-16, pero los delimitadores son ASCII, de modo que
/// ningún acento ni emoji se parte nunca.
library;

import 'package:meta/meta.dart';

/// Cuánto puede valer el número de un hueco. Más dígitos que esto es casi
/// seguro un error de tipeo (`c20260101`) y haría desbordar un `int` en la
/// web, donde valen 53 bits.
const int kClozeMaxNumber = 9999;

/// Un hueco leído del texto.
class ClozeDeletion {
  const ClozeDeletion({
    required this.number,
    required this.answer,
    required this.hint,
    required this.start,
    required this.end,
  });

  /// El número del hueco (`c1` es 1). Los que comparten número se piden
  /// juntos, en una sola tarjeta.
  final int number;

  /// Lo que va escondido, sin ninguna marca de hueco adentro.
  final String answer;

  /// La pista (`{{c1::resp::pista}}`), o `null` si no tiene o está en blanco.
  final String? hint;

  /// Dónde empieza (`{{`) y dónde termina (después de `}}`) en el texto
  /// original: `source.substring(start, end)` devuelve el hueco entero.
  final int start;
  final int end;
}

/// Qué es un trozo de una tarjeta de huecos, para que la pantalla lo dibuje.
enum ClozeSegmentKind {
  /// Texto común.
  plain,

  /// El hueco que se pregunta: en la cara de adelante, `[...]` o `[pista]`.
  hidden,

  /// El hueco ya contestado, en la cara de atrás: se resalta.
  revealed,
}

@immutable
class ClozeSegment {
  const ClozeSegment(this.text, this.kind);

  final String text;
  final ClozeSegmentKind kind;

  @override
  bool operator ==(Object other) =>
      other is ClozeSegment && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => 'ClozeSegment($kind, "$text")';
}

/// La tarjeta de un número de hueco.
class ClozeCard {
  const ClozeCard({
    required this.number,
    required this.question,
    required this.answer,
    required this.questionSegments,
    required this.answerSegments,
  });

  final int number;

  /// El frente como texto: el hueco como `[...]` (o `[pista]`) y los demás
  /// huecos ya revelados, sin marca.
  final String question;

  /// El dorso como texto: el texto completo con este hueco revelado y
  /// marcado en negrita (`**respuesta**`).
  final String answer;

  final List<ClozeSegment> questionSegments;
  final List<ClozeSegment> answerSegments;
}

/// El texto de huecos ya leído.
class ClozeText {
  const ClozeText._(this.source, this.deletions, this.problems);

  /// El texto tal como se escribió.
  final String source;

  /// Los huecos, en el orden en que aparecen.
  final List<ClozeDeletion> deletions;

  /// Lo que está mal escrito (vacío si todo está bien).
  final List<ClozeProblem> problems;

  /// Los números de hueco que hay, sin repetir y de menor a mayor.
  List<int> get numbers =>
      ({for (final d in deletions) d.number}.toList()..sort());

  /// Si hay al menos un hueco y nada mal escrito.
  bool get isValid => problems.isEmpty && deletions.isNotEmpty;

  /// El texto sin ninguna marca: todos los huecos revelados.
  String get plainText => _render(null).map((s) => s.text).join();

  /// El frente de la tarjeta del hueco [number].
  List<ClozeSegment> questionSegmentsFor(int number) =>
      _render(number, asking: true);

  /// El dorso de la tarjeta del hueco [number].
  List<ClozeSegment> answerSegmentsFor(int number) => _render(number);

  String questionFor(int number) =>
      _join(questionSegmentsFor(number), markRevealed: false);

  String answerFor(int number) =>
      _join(answerSegmentsFor(number), markRevealed: true);

  /// Una tarjeta por cada número de hueco.
  List<ClozeCard> get cards => [
    for (final n in numbers)
      ClozeCard(
        number: n,
        question: questionFor(n),
        answer: answerFor(n),
        questionSegments: questionSegmentsFor(n),
        answerSegments: answerSegmentsFor(n),
      ),
  ];

  String _join(List<ClozeSegment> segments, {required bool markRevealed}) {
    final out = StringBuffer();
    for (final s in segments) {
      if (markRevealed && s.kind == ClozeSegmentKind.revealed) {
        out
          ..write('**')
          ..write(s.text)
          ..write('**');
      } else {
        out.write(s.text);
      }
    }
    return out.toString();
  }

  /// Arma los trozos. [target] es el número que se pregunta (`null`: ninguno,
  /// se muestra el texto completo). [asking] es la cara de adelante; si no,
  /// la de atrás.
  List<ClozeSegment> _render(int? target, {bool asking = false}) {
    final segments = <ClozeSegment>[];
    final plain = StringBuffer();
    void flush() {
      if (plain.isEmpty) return;
      segments.add(ClozeSegment(plain.toString(), ClozeSegmentKind.plain));
      plain.clear();
    }

    var cursor = 0;
    for (final d in deletions) {
      plain.write(source.substring(cursor, d.start));
      cursor = d.end;
      if (d.number != target) {
        plain.write(d.answer);
        continue;
      }
      flush();
      segments.add(
        asking
            ? ClozeSegment(
                d.hint == null ? '[...]' : '[${d.hint}]',
                ClozeSegmentKind.hidden,
              )
            : ClozeSegment(d.answer, ClozeSegmentKind.revealed),
      );
    }
    plain.write(source.substring(cursor));
    flush();
    return segments;
  }
}

/// Lo que puede estar mal en un texto de huecos.
enum ClozeProblem {
  /// No tiene ningún hueco: no hay tarjeta que sacar.
  noDeletions,

  /// Un `{{c1::` que nunca se cierra con `}}`.
  unclosed,

  /// Un `{{c1::}}`: nada que esconder.
  emptyAnswer,

  /// Un número fuera de `1..`[kClozeMaxNumber] (`c0`, o uno enorme).
  invalidNumber,
}

/// Lee los huecos de [text]. No lanza nunca: lo que no se pudo leer queda
/// como texto común y se informa en [ClozeText.problems].
ClozeText parseCloze(String text) {
  final deletions = <ClozeDeletion>[];
  final problems = <ClozeProblem>{};

  var i = 0;
  while (i < text.length) {
    final open = text.indexOf('{{c', i);
    if (open < 0) break;

    final header = _readHeader(text, open + 3);
    if (header == null) {
      // `{{cuando` o `{{c1:` sin su segundo `:`: llaves que no abren nada.
      i = open + 2;
      continue;
    }

    final body = _readBody(text, header.bodyStart);
    if (body == null) {
      problems.add(ClozeProblem.unclosed);
      i = header.bodyStart;
      continue;
    }

    final number = header.number;
    final end = body.end;
    if (number == null || number < 1 || number > kClozeMaxNumber) {
      problems.add(ClozeProblem.invalidNumber);
      i = end;
      continue;
    }

    // Sin recortar: `El{{c1:: Imperio}}` revela con su espacio, y el texto
    // completo no pierde lo que la persona escribió. Solo la comprobación
    // de vacío ignora los blancos.
    final answer = _revealNested(body.answer);
    if (answer.trim().isEmpty) {
      problems.add(ClozeProblem.emptyAnswer);
      i = end;
      continue;
    }
    final rawHint = body.hint == null ? null : _revealNested(body.hint!).trim();
    deletions.add(
      ClozeDeletion(
        number: number,
        answer: answer,
        hint: rawHint == null || rawHint.isEmpty ? null : rawHint,
        start: open,
        end: end,
      ),
    );
    i = end;
  }

  if (deletions.isEmpty && problems.isEmpty) {
    problems.add(ClozeProblem.noDeletions);
  }
  return ClozeText._(text, deletions, problems.toList());
}

/// Atajo: lo que está mal en [text], vacío si sirve para sacar tarjetas.
/// Un texto sin huecos es un error ([ClozeProblem.noDeletions]) aunque no
/// tenga nada mal escrito, y uno con huecos buenos y uno roto también.
List<ClozeProblem> validateCloze(String text) {
  final parsed = parseCloze(text);
  return [
    ...parsed.problems,
    if (parsed.deletions.isEmpty &&
        !parsed.problems.contains(ClozeProblem.noDeletions))
      ClozeProblem.noDeletions,
  ];
}

/// El mensaje, en español y listo para mostrar, de lo que está mal.
String clozeProblemMessage(ClozeProblem problem) => switch (problem) {
  ClozeProblem.noDeletions =>
    'El texto no tiene ningún hueco. Marcá lo que querés esconder con '
        '{{c1::respuesta}}.',
  ClozeProblem.unclosed =>
    'Hay un hueco que no se cierra: falta el }} del final.',
  ClozeProblem.emptyAnswer => 'Hay un hueco vacío: no esconde nada.',
  ClozeProblem.invalidNumber =>
    'El número de un hueco no vale: tiene que ir de 1 a $kClozeMaxNumber '
        '(por ejemplo c1).',
};

/// Marca en [text] el rango [start]..[end] como el hueco número [number], con
/// su [hint] si hay. Para el botón «hacer hueco» del editor. Un [start]
/// inválido o un rango vacío devuelven [text] igual.
String wrapAsCloze(
  String text,
  int start,
  int end, {
  required int number,
  String? hint,
}) {
  if (start < 0 || end > text.length || start >= end || number < 1) {
    return text;
  }
  final selected = text.substring(start, end);
  if (selected.trim().isEmpty) return text;
  final suffix = hint == null || hint.trim().isEmpty ? '' : '::${hint.trim()}';
  return '${text.substring(0, start)}{{c$number::$selected$suffix}}'
      '${text.substring(end)}';
}

/// El número siguiente al más alto que usa [text] (1 si no tiene huecos).
int nextClozeNumber(String text) {
  final numbers = parseCloze(text).numbers;
  return numbers.isEmpty ? 1 : numbers.last + 1;
}

// --- Lectura ----------------------------------------------------------------

class _Header {
  const _Header(this.number, this.bodyStart);
  final int? number;
  final int bodyStart;
}

/// Lee `dígitos::` después de `{{c`. `null` si no es un encabezado de hueco.
_Header? _readHeader(String text, int from) {
  var i = from;
  while (i < text.length && _isDigit(text.codeUnitAt(i))) {
    i++;
  }
  if (i == from) return null;
  if (!text.startsWith('::', i)) return null;
  // Más de 6 dígitos ya no entra en [kClozeMaxNumber]: no se parsea (el
  // `int.parse` de 40 dígitos desbordaría).
  final digits = text.substring(from, i);
  final number = digits.length > 6 ? null : int.parse(digits);
  return _Header(number, i + 2);
}

class _Body {
  const _Body(this.answer, this.hint, this.end);
  final String answer;
  final String? hint;
  final int end;
}

/// Lee el cuerpo de un hueco desde [from] hasta su `}}`. Las llaves simples
/// de adentro se emparejan solas; los `{{...}}` anidados también (cuentan
/// como dos llaves abiertas). `null` si no se cierra.
_Body? _readBody(String text, int from) {
  var depth = 0;
  int? hintAt;
  for (var i = from; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x7B) {
      depth++;
    } else if (unit == 0x7D) {
      if (depth > 0) {
        depth--;
      } else if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x7D) {
        final inner = text.substring(from, i);
        final splitAt = hintAt == null ? null : hintAt - from;
        return splitAt == null
            ? _Body(inner, null, i + 2)
            : _Body(
                inner.substring(0, splitAt),
                inner.substring(splitAt + 2),
                i + 2,
              );
      }
    } else if (unit == 0x3A &&
        depth == 0 &&
        hintAt == null &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == 0x3A) {
      hintAt = i;
      i++;
    }
  }
  return null;
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

final _nestedHole = RegExp(r'\{\{c\d+::');

/// Un hueco anidado queda revelado: sale `{{c2::Imperio}}` → `Imperio` (y la
/// pista del anidado se descarta).
String _revealNested(String text) {
  if (!text.contains(_nestedHole)) return text;
  final inner = parseCloze(text);
  return inner.deletions.isEmpty ? text : inner.plainText;
}

// --- La IA ------------------------------------------------------------------

/// Lo que se le dice al modelo para que arme textos con huecos, en el estilo
/// de `_flashcardSystemInstruction`: un formato único y simple, porque un
/// modelo chico se desvía de lo que es complicado.
const String clozeSystemInstruction =
    'Respondé siempre en español. Tu única tarea es armar frases de estudio '
    'con huecos para completar a partir del contenido que se te da, '
    'basándote ÚNICAMENTE en ese contenido. Copiá una frase del contenido y '
    'escondé con {{c1::...}} la palabra o expresión clave que habría que '
    'recordar; si la frase tiene otra idea clave, escondela con {{c2::...}}. '
    'Opcionalmente podés dar una pista corta con {{c1::respuesta::pista}}. '
    'Usá EXACTAMENTE este formato, una frase por vez, sin numerar, sin usar '
    'Markdown ni comillas:\nH: <la frase con sus huecos>\nC: <la frase del '
    'contenido de la que sale, copiada TEXTUALMENTE, sin cambiar ni una '
    'palabra>\nNo escondas más de dos o tres huecos por frase, ni frases '
    'enteras.';

/// El mensaje del usuario para pedir hasta [count] frases con huecos a
/// partir de [content].
String buildClozeRequest({required String content, int count = 5}) =>
    'Generá hasta $count frases con huecos a partir de este contenido:\n\n'
    '$content';

/// Una frase con huecos propuesta por el modelo, todavía sin guardar.
class ClozeDraft {
  const ClozeDraft({required this.text, this.quote});

  /// La frase con sus `{{c1::...}}`: ya se comprobó que sirve
  /// ([validateCloze] vacío).
  final String text;

  /// La frase del contenido de la que dice salir, igual que
  /// `FlashcardDraft.quote`: una afirmación del modelo, no un dato.
  final String? quote;
}

final _clozeLine = RegExp(
  r'^(?:[-*•]\s*|\d+[.)]\s*)?(?:H|Hueco|Frase)\s*:\s*(.+)$',
  caseSensitive: false,
);
final _clozeQuoteLine = RegExp(
  r'^(?:[-*•]\s*)?(?:C|Cita)\s*:\s*(.+)$',
  caseSensitive: false,
);

/// Interpreta la respuesta cruda del modelo como una lista de frases con
/// huecos. Tolerante a propósito, igual que `parseFlashcardDrafts`: una línea
/// que no es de ninguno de los dos tipos se ignora; una frase **sin huecos o
/// con un hueco roto** se descarta (con una frase mal escrita no hay tarjeta
/// que valga), pero no echa a las demás. Si el modelo devolvió una frase con
/// huecos pero sin la etiqueta `H:` (una línea suelta que ya trae
/// `{{c1::...}}`), también se toma.
List<ClozeDraft> parseClozeDrafts(String rawResponse) {
  final drafts = <ClozeDraft>[];
  var lastClosed = false;

  for (final rawLine in rawResponse.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final quote = _clozeQuoteLine.firstMatch(line);
    if (quote != null && !line.contains('{{c')) {
      final text = quote.group(1)!.trim();
      if (lastClosed &&
          drafts.isNotEmpty &&
          drafts.last.quote == null &&
          text.isNotEmpty) {
        final last = drafts.removeLast();
        drafts.add(ClozeDraft(text: last.text, quote: text));
      }
      continue;
    }

    final labelled = _clozeLine.firstMatch(line);
    final candidate =
        (labelled?.group(1) ?? (line.contains('{{c') ? line : null))?.trim();
    if (candidate == null) {
      lastClosed = false;
      continue;
    }
    if (validateCloze(candidate).isEmpty) {
      drafts.add(ClozeDraft(text: candidate));
      lastClosed = true;
    } else {
      lastClosed = false;
    }
  }
  return drafts;
}
