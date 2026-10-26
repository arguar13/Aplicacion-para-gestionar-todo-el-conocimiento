import 'dart:convert';

import 'package:sinapsis/core/util/text_anchor_locator.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_draft.dart';
import 'package:sinapsis/features/timeline/domain/entities/historical_date_order.dart';
import 'package:sinapsis/features/timeline/domain/services/dated_passage_selector.dart';
import 'package:sinapsis/features/timeline/domain/services/normalized_date_parser.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_expressions.dart';

/// Cuántos caracteres puede tener el título de un hecho: más que esto es una
/// oración, no un nombre para una marca en la línea de tiempo.
const kMaxDatedEventTitleChars = 80;

/// Lo más corta que puede ser una cita: una palabra suelta, un «1859», no
/// dicen de dónde sale el hecho.
const kMinDatedEventQuoteChars = 6;

/// Cuántos tokens puede escribir el modelo para un pedido de [passages]
/// pasajes (F40): una línea `HECHO` por hecho —su fecha, su título y su cita—,
/// a unos 72 tokens la línea con lo que sobra, y un pasaje puede traer más de
/// un hecho.
int datedEventsReplyTokens(int passages) =>
    (passages * 72 + 48).clamp(128, 4096);

/// El pedido de [part]: sus pasajes, numerados desde 1, cada uno en un
/// renglón —el modelo contesta línea por línea, y un salto adentro de un
/// pasaje lo confunde—.
String buildDatedEventsPrompt(DatedTextPart part) {
  final buffer = StringBuffer('Fragmentos del documento:\n');
  for (final (index, passage) in part.passages.indexed) {
    final line = passage.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    buffer.writeln('[${index + 1}] $line');
  }
  return buffer.toString().trimRight();
}

/// Lee lo que contestó el modelo a `buildDatedEventsPrompt(part)` (F40): los
/// hechos que se pueden guardar, en el orden en que los dio.
///
/// Cada línea es `HECHO: <fecha> | <fin> | <título> | <cita>`. **Nada se
/// inventa**: una línea pasa solo si
///
/// - su fecha se lee con el analizador estricto (`parseNormalizedDate`) y el
///   fin, si lo hay, es posterior al inicio;
/// - su cita está en alguno de los pasajes de [part] —tolerando los espacios,
///   las comillas que la envuelven y los puntos suspensivos de los bordes—, y
///   con ella se sabe dónde del texto entero está;
/// - la fecha es una que el texto dice: si la cita trae expresiones de tiempo
///   (`findTemporalExpressions`), alguna es esa fecha, y su fin está en ellas
///   si se da; si no trae ninguna, se busca en el pasaje que la contiene;
/// - tiene título, que se acorta si es largo.
///
/// Lo que no pasa se descarta, línea por línea: una rota no rompe las demás.
/// Dos líneas con la misma fecha y la misma cita son un solo hecho.
List<DatedEventDraft> parseDatedEventsReply(String reply, DatedTextPart part) {
  final drafts = <DatedEventDraft>[];
  for (final line in const LineSplitter().convert(reply)) {
    final draft = _parseLine(line, part);
    if (draft == null) continue;
    if (drafts.any((d) => _sameFact(d, draft))) continue;
    drafts.add(draft);
  }
  return drafts;
}

bool _sameFact(DatedEventDraft a, DatedEventDraft b) =>
    a.start == b.start &&
    a.end == b.end &&
    a.date.sameReading(b.date) &&
    ((a.endDate == null && b.endDate == null) ||
        (a.endDate != null &&
            b.endDate != null &&
            a.endDate!.sameReading(b.endDate!)));

/// `HECHO:` al empezar la línea, con la viñeta, el número o la negrita que
/// un modelo suele ponerle.
final _factLine = RegExp(
  r'^\s*(?:[-*•]\s*|\d+[.)]\s*)?(?:\*\*|__)?HECHO\s*(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*(.*)$',
  caseSensitive: false,
);

DatedEventDraft? _parseLine(String line, DatedTextPart part) {
  final body = _factLine.firstMatch(line)?.group(1);
  if (body == null) return null;
  final fields = _fieldsOf(body);
  if (fields == null) return null;

  final span = _datesOf(fields.date, fields.end);
  if (span == null) return null;

  final title = _cleanTitle(fields.title);
  if (title == null) return null;

  final quote = _cleanQuote(fields.quote);
  if (quote == null) return null;
  final located = _locate(part, quote);
  if (located == null) return null;

  if (!_isSaidIn(located, span)) return null;

  return DatedEventDraft(
    date: span.start,
    endDate: span.end,
    title: title,
    start: located.start,
    end: located.end,
    excerpt: located.passage.text.substring(
      located.start - located.passage.start,
      located.end - located.passage.start,
    ),
  );
}

/// Los cuatro campos de [body], separados por `|`: la cita es el resto, por
/// si ella misma lleva una barra.
({String date, String end, String title, String quote})? _fieldsOf(
  String body,
) {
  final first = body.indexOf('|');
  if (first < 0) return null;
  final second = body.indexOf('|', first + 1);
  if (second < 0) return null;
  final third = body.indexOf('|', second + 1);
  if (third < 0) return null;
  return (
    date: body.substring(0, first).trim(),
    end: body.substring(first + 1, second).trim(),
    title: body.substring(second + 1, third).trim(),
    quote: body.substring(third + 1).trim(),
  );
}

/// El fin que dice «no hay».
final _noEnd = RegExp(
  r'^(?:|-+|–|—|ninguno|ninguna|no|none|n/a|null)$',
  caseSensitive: false,
);

/// La fecha y su fin, leídos: el rango puede venir entero en el campo de la
/// fecha (`1914..1918`) o con el fin en el suyo, pero no de las dos maneras.
DateSpan? _datesOf(String dateField, String endField) {
  final span = parseNormalizedDate(dateField);
  if (span == null) return null;
  if (_noEnd.hasMatch(endField)) return span;
  if (span.end != null) return null;
  final end = parseNormalizedDate(endField);
  if (end == null || end.end != null) return null;
  if (end.start.compareStart(span.start) <= 0) return null;
  return (start: span.start, end: end.start);
}

/// El título sin comillas ni negritas alrededor, en una línea y de hasta
/// [kMaxDatedEventTitleChars] caracteres; `null` si no queda nada.
///
/// Un título largo se corta en la última palabra que entra y termina en
/// «…»: cortarlo a mitad de palabra, o sin avisar, lo haría decir otra cosa.
String? _cleanTitle(String raw) {
  final title = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_titleEdges, '')
      .replaceAll(_trailingPunctuation, '')
      .trim();
  if (title.isEmpty) return null;
  if (title.length <= kMaxDatedEventTitleChars) return title;

  const limit = kMaxDatedEventTitleChars - 1;
  final space = title.lastIndexOf(' ', limit);
  final cut = space > limit ~/ 2 ? space : limit;
  final shortened = title
      .substring(0, cut)
      .replaceAll(_danglingPunctuation, '');
  return '$shortened…';
}

final _trailingPunctuation = RegExp(r'[.;:,]+$');

/// Lo que queda colgando al cortar: una coma, un guion, un paréntesis abierto.
final _danglingPunctuation = RegExp(r'[\s.;:,\-–—(]+$');

/// Lo que envuelve a un título sin ser parte de él.
final _titleEdges = RegExp(r'^[\s"“”«»*_`]+|[\s"“”«»*_`]+$');

/// La cita sin las comillas que la envuelven ni los puntos suspensivos de los
/// bordes —lo que un modelo agrega al recortar una frase—; `null` si queda
/// demasiado poco para ubicarla.
String? _cleanQuote(String raw) {
  var quote = raw.trim();
  const pairs = {'"': '"', '“': '”', '«': '»', "'": "'"};
  final closing = quote.isEmpty ? null : pairs[quote[0]];
  if (closing != null && quote.length >= 2 && quote.endsWith(closing)) {
    quote = quote.substring(1, quote.length - 1);
  }
  quote = quote
      .replaceAll(RegExp(r'^[\s…]+|[\s…]+$'), '')
      .replaceAll(RegExp(r'^(?:\.\.\.)\s*|\s*(?:\.\.\.)$'), '')
      .trim();
  return quote.length < kMinDatedEventQuoteChars ? null : quote;
}

typedef _Located = ({int start, int end, DatedPassage passage});

/// Dónde está [quote] en los pasajes de [part], en el texto entero.
_Located? _locate(DatedTextPart part, String quote) {
  for (final passage in part.passages) {
    final range =
        locateExcerpt(passage.text, quote) ??
        _locateIgnoringMarkup(passage.text, quote);
    if (range != null) {
      return (
        start: passage.start + range.start,
        end: passage.start + range.end,
        passage: passage,
      );
    }
  }
  return null;
}

/// Lo mismo que `locateExcerpt` en un texto de Markdown, donde el modelo copia
/// «1859» y el texto dice `**1859**`: se busca sin las marcas de énfasis y el
/// lugar se lleva de vuelta al texto con ellas.
({int start, int end})? _locateIgnoringMarkup(String text, String quote) {
  final kept = StringBuffer();
  final origin = <int>[];
  var i = 0;
  while (i < text.length) {
    final char = text[i];
    final pair = i + 1 < text.length ? text.substring(i, i + 2) : '';
    if (pair == '**' || pair == '__') {
      i += 2;
    } else if (char == '`' || char == '*' || char == '_') {
      i++;
    } else {
      kept.write(char);
      origin.add(i);
      i++;
    }
  }
  if (origin.length == text.length) return null;
  final range = locateExcerpt(kept.toString(), quote);
  if (range == null || range.end <= range.start) return null;
  return (start: origin[range.start], end: origin[range.end - 1] + 1);
}

/// Si el texto dice la fecha de [span]: la cita trae una expresión de tiempo
/// que es esa fecha —y, si hay un fin, que es ese fin o que otra expresión de
/// la cita lo es—; y si no trae ninguna, el pasaje que la contiene la trae.
bool _isSaidIn(_Located located, DateSpan span) {
  final inQuote = [
    for (final e in located.passage.expressions)
      if (e.start >= located.start && e.end <= located.end) e,
  ];
  final expressions = inQuote.isNotEmpty
      ? inQuote
      : located.passage.expressions;
  return expressions.any((e) => _says(e, expressions, span));
}

bool _says(TemporalExpression e, List<TemporalExpression> all, DateSpan span) {
  if (!e.date.sameReading(span.start)) return false;
  final end = span.end;
  if (end == null) return true;
  if (e.endDate?.sameReading(end) ?? false) return true;
  return all.any((other) => other != e && other.date.sameReading(end));
}
