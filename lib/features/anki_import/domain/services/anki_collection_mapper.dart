import 'dart:convert';

import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_media_ref.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_html_text.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_template.dart';
import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';

/// Una plantilla de un tipo de nota de Anki.
class AnkiTemplateDef {
  const AnkiTemplateDef({
    required this.name,
    required this.ord,
    required this.question,
    required this.answer,
  });

  final String name;
  final int ord;

  /// `qfmt` y `afmt`.
  final String question;
  final String answer;
}

/// Un tipo de nota de Anki (`col.models`).
class AnkiModelDef {
  const AnkiModelDef({
    required this.id,
    required this.name,
    required this.isCloze,
    required this.fieldNames,
    required this.templates,
  });

  final int id;
  final String name;

  /// `type == 1` en Anki.
  final bool isCloze;

  /// Los campos, en el orden de `ord`.
  final List<String> fieldNames;
  final List<AnkiTemplateDef> templates;
}

/// Una fila de `notes`, la parte que hace falta.
class AnkiNoteRow {
  const AnkiNoteRow({
    required this.id,
    required this.guid,
    required this.modelId,
    required this.tags,
    required this.fields,
  });

  final int id;
  final String guid;
  final int modelId;

  /// `notes.tags`, separadas por espacios.
  final String tags;

  /// `notes.flds`, separados por `\x1f`.
  final String fields;
}

/// Una fila de `cards`, la parte que hace falta.
class AnkiCardRow {
  const AnkiCardRow({
    required this.id,
    required this.deckId,
    required this.ord,
    required this.type,
    required this.queue,
    required this.due,
    required this.interval,
    required this.factor,
    required this.reps,
    required this.lapses,
    this.originalDue = 0,
    this.originalDeckId = 0,
  });

  final int id;
  final int deckId;
  final int ord;
  final int type;
  final int queue;
  final int due;
  final int interval;
  final int factor;
  final int reps;
  final int lapses;

  /// `odue` y `odid`: el calendario y el mazo de antes de entrar en un mazo
  /// filtrado (0 si no está en uno).
  final int originalDue;
  final int originalDeckId;
}

/// Los tipos de nota de `col.models` (un JSON `{id: definición}`).
Map<int, AnkiModelDef> parseAnkiModels(String json) {
  final decoded = _decodeMap(json, 'los tipos de nota');
  final models = <int, AnkiModelDef>{};
  for (final entry in decoded.entries) {
    final raw = entry.value;
    if (raw is! Map<String, dynamic>) continue;
    final id = _asInt(raw['id']) ?? int.tryParse(entry.key);
    if (id == null) continue;

    final fields = _list(raw['flds']).whereType<Map<String, dynamic>>().toList()
      ..sort(
        (a, b) => (_asInt(a['ord']) ?? 0).compareTo(_asInt(b['ord']) ?? 0),
      );
    final templates =
        _list(raw['tmpls']).whereType<Map<String, dynamic>>().toList()..sort(
          (a, b) => (_asInt(a['ord']) ?? 0).compareTo(_asInt(b['ord']) ?? 0),
        );
    models[id] = AnkiModelDef(
      id: id,
      name: raw['name'] as String? ?? '',
      isCloze: _asInt(raw['type']) == 1,
      fieldNames: [for (final f in fields) f['name'] as String? ?? ''],
      templates: [
        for (final (index, t) in templates.indexed)
          AnkiTemplateDef(
            name: t['name'] as String? ?? '',
            ord: _asInt(t['ord']) ?? index,
            question: t['qfmt'] as String? ?? '',
            answer: t['afmt'] as String? ?? '',
          ),
      ],
    );
  }
  return models;
}

/// Los mazos de `col.decks` (un JSON `{id: mazo}`): id → nombre completo
/// con `::`, y el conjunto de los que son filtrados (`dyn`).
({Map<int, String> names, Set<int> filtered}) parseAnkiDecks(String json) {
  final decoded = _decodeMap(json, 'los mazos');
  final names = <int, String>{};
  final filtered = <int>{};
  for (final entry in decoded.entries) {
    final raw = entry.value;
    if (raw is! Map<String, dynamic>) continue;
    final id = _asInt(raw['id']) ?? int.tryParse(entry.key);
    if (id == null) continue;
    // Las versiones nuevas separan los niveles con U+001F en vez de `::`.
    names[id] = (raw['name'] as String? ?? '').replaceAll('\u001f', '::');
    if (_asInt(raw['dyn']) == 1) filtered.add(id);
  }
  return (names: names, filtered: filtered);
}

Map<String, dynamic> _decodeMap(String json, String what) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Cae al error de abajo.
  }
  throw AnkiImportException(
    AnkiImportFailure.corrupt,
    'No se pudo leer $what del paquete de Anki: la colección está dañada '
    'o es de una versión que no se sabe leer.',
  );
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Arma las tarjetas de Sinapsis a partir de las filas de una colección de
/// Anki, una nota por vez.
///
/// Puro: no sabe de ZIP ni de SQLite. El lector de `.apkg` le va dando las
/// notas con sus tarjetas, y al final pide [build].
class AnkiCollectionMapper {
  AnkiCollectionMapper({
    required this.collectionCreatedAt,
    required this.models,
    required this.deckNames,
    this.filteredDecks = const {},
    this.lastReviewByCard = const {},
  });

  /// El día 0 de los vencimientos de Anki (`col.crt`), a la hora local.
  final DateTime collectionCreatedAt;
  final Map<int, AnkiModelDef> models;
  final Map<int, String> deckNames;
  final Set<int> filteredDecks;

  /// Último repaso de cada tarjeta, en milisegundos desde 1970 (el `id` más
  /// alto de su `revlog`).
  final Map<int, int> lastReviewByCard;

  final _decks = <int, List<AnkiImportedCard>>{};
  final _order = <int>[];
  final _warnings = <String>[];
  final _warnedModels = <int>{};
  var _skipped = 0;
  var _filteredCards = 0;

  /// Los avisos hasta ahora.
  List<String> get warnings {
    final filtered = _filteredCards == 0
        ? null
        : '$_filteredCards tarjetas estaban en un mazo filtrado de Anki: '
              'entran en el mazo al que pertenecían, con su calendario '
              'original.';
    return [..._warnings, ?filtered];
  }

  int get skipped => _skipped;

  /// Agrega una nota con las tarjetas que Anki generó de ella.
  void addNote(AnkiNoteRow note, List<AnkiCardRow> cards) {
    final model = models[note.modelId];
    if (model == null || model.templates.isEmpty) {
      if (_warnedModels.add(note.modelId)) {
        _warnings.add(
          'Hay notas de un tipo que no está en el paquete: se dejaron '
          'afuera.',
        );
      }
      _skipped += cards.length;
      return;
    }

    final values = note.fields.split('\u001f');
    final fields = <String, String>{
      for (final (index, name) in model.fieldNames.indexed)
        name: index < values.length ? values[index] : '',
    };
    final tags = note.tags
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final sorted = [...cards]..sort((a, b) => a.ord.compareTo(b.ord));
    final built = <_Built>[];
    for (final row in sorted) {
      final result = _buildCard(note, row, model, fields, tags);
      if (result == null) {
        _skipped++;
      } else {
        built.add(result);
      }
    }

    _markReversed(built);

    for (final b in built) {
      final deckId = b.row.originalDeckId != 0
          ? b.row.originalDeckId
          : b.row.deckId;
      if (b.row.originalDeckId != 0 || filteredDecks.contains(b.row.deckId)) {
        _filteredCards++;
      }
      if (!_decks.containsKey(deckId)) _order.add(deckId);
      _decks.putIfAbsent(deckId, () => []).add(b.card);
    }
  }

  /// Los mazos con tarjetas, en el orden en que apareció la primera.
  List<AnkiImportedDeck> build() => [
    for (final id in _order)
      AnkiImportedDeck(
        id: id,
        path: deckNames[id] ?? 'Importado de Anki',
        cards: _decks[id]!,
      ),
  ];

  _Built? _buildCard(
    AnkiNoteRow note,
    AnkiCardRow row,
    AnkiModelDef model,
    Map<String, String> fields,
    List<String> tags,
  ) {
    final template = model.templates.firstWhere(
      (t) => t.ord == row.ord,
      orElse: () => model.templates.first,
    );
    final special = {
      'Tags': note.tags.trim(),
      'Deck': deckNames[row.deckId] ?? '',
      'Subdeck': (deckNames[row.deckId] ?? '').split('::').last,
      'Card': template.name,
    };
    final question = AnkiTemplate.parse(template.question);
    final answer = AnkiTemplate.parse(template.answer);
    final schedule = _scheduleOf(row);

    AnkiImportedCard make({
      required AnkiCardKind kind,
      required String front,
      required String back,
      required List<AnkiMediaRef> media,
      String? clozeSource,
      int? clozeNumber,
      List<String> distractors = const [],
    }) => AnkiImportedCard(
      ankiCardId: row.id,
      noteId: note.id,
      guid: note.guid,
      ord: row.ord,
      kind: kind,
      front: front,
      back: back,
      schedule: schedule,
      tags: tags,
      media: media,
      clozeSource: clozeSource,
      clozeNumber: clozeNumber,
      distractors: distractors,
      noteTypeName: model.name,
    );

    // --- Huecos -------------------------------------------------------------
    final clozeVariable = question.variables
        .where((v) => v.hasFilter('cloze'))
        .firstOrNull;
    if (model.isCloze || clozeVariable != null) {
      final fieldName =
          clozeVariable?.field ??
          (model.fieldNames.isEmpty ? '' : model.fieldNames.first);
      final rawText = fields[fieldName] ?? '';
      final converted = ankiHtmlToText(rawText, markdown: false);
      final parsed = parseCloze(converted.text);
      final number = row.ord + 1;
      if (!parsed.numbers.contains(number)) return null;

      // Lo que la plantilla agrega después del texto (el «extra»).
      final extraHtml = answer.render(
        fields,
        answerSide: true,
        special: special,
        clozeFilter: (_) => '',
      );
      final extra = ankiHtmlToText(extraHtml);
      final back = extra.text.isEmpty
          ? parsed.answerFor(number)
          : '${parsed.answerFor(number)}\n\n${extra.text}';
      return _Built(
        row,
        make(
          kind: AnkiCardKind.cloze,
          front: parsed.questionFor(number),
          back: back,
          media: _mergeMedia([converted.media, extra.media]),
          clozeSource: converted.text,
          clozeNumber: number,
        ),
      );
    }

    // --- Opción múltiple de Sinapsis -----------------------------------------
    if (_isMultipleChoiceModel(model)) {
      final q = ankiHtmlToText(fields['Question'] ?? '');
      final a = ankiHtmlToText(fields['Answer'] ?? '');
      final distractors = <String>[];
      final media = <List<AnkiMediaRef>>[q.media, a.media];
      for (var i = 1; i <= 3; i++) {
        final d = ankiHtmlToText(fields['Distractor$i'] ?? '');
        if (d.text.isNotEmpty) distractors.add(d.text);
        media.add(d.media);
      }
      if (q.text.isEmpty && a.text.isEmpty) return null;
      return _Built(
        row,
        make(
          kind: AnkiCardKind.multipleChoice,
          front: q.text,
          back: a.text,
          media: _mergeMedia(media),
          distractors: distractors,
        ),
      );
    }

    // --- Básica, invertida, escribir ----------------------------------------
    final front = ankiHtmlToText(question.render(fields, special: special));
    final backHtml = _answerSide(answer, fields, special);
    final back = ankiHtmlToText(backHtml);
    var backText = back.text;
    // Una plantilla que repite el frente en el dorso sin `{{FrontSide}}`.
    if (front.text.isNotEmpty &&
        backText != front.text &&
        backText.startsWith('${front.text}\n')) {
      backText = backText.substring(front.text.length).trim();
    }
    final media = _mergeMedia([front.media, back.media]);
    if (front.text.isEmpty && backText.isEmpty && media.isEmpty) return null;

    final isTyped = question.variables.any((v) => v.hasFilter('type'));
    return _Built(
      row,
      make(
        kind: isTyped ? AnkiCardKind.typed : AnkiCardKind.basic,
        front: front.text,
        back: backText,
        media: media,
      ),
    );
  }

  /// El HTML del dorso, sin el frente: lo que sigue a `<hr id=answer>` o,
  /// sin esa raya, la plantilla sin `{{FrontSide}}`.
  String _answerSide(
    AnkiTemplate answer,
    Map<String, String> fields,
    Map<String, String> special,
  ) {
    const sentinel = '\uE000FRONTSIDE\uE000';
    final html = answer.render(
      fields,
      frontSide: sentinel,
      answerSide: true,
      special: special,
    );
    final rule = _answerRule.firstMatch(html);
    if (rule != null) return html.substring(rule.end).replaceAll(sentinel, '');
    return html.replaceAll(sentinel, '');
  }

  /// Marca como invertidas las dos tarjetas de una nota cuando el frente de
  /// una es el dorso de la otra: no importa cómo se llame el tipo de nota
  /// (viene traducido), importa que se vea igual.
  void _markReversed(List<_Built> built) {
    if (built.length < 2) return;
    for (var i = 0; i < built.length; i++) {
      for (var j = i + 1; j < built.length; j++) {
        final a = built[i].card;
        final b = built[j].card;
        if (a.kind != AnkiCardKind.basic || b.kind != AnkiCardKind.basic) {
          continue;
        }
        if (a.front.isNotEmpty &&
            a.front == b.back &&
            a.back == b.front &&
            a.front != a.back) {
          built[i] = built[i].withKind(AnkiCardKind.reversed);
          built[j] = built[j].withKind(AnkiCardKind.reversed);
        }
      }
    }
  }

  bool _isMultipleChoiceModel(AnkiModelDef model) {
    final names = model.fieldNames;
    return names.length >= 2 &&
        names[0] == 'Question' &&
        names[1] == 'Answer' &&
        names.skip(2).every((n) => n.startsWith('Distractor'));
  }

  List<AnkiMediaRef> _mergeMedia(List<List<AnkiMediaRef>> groups) {
    final seen = <AnkiMediaRef>{};
    return [
      for (final group in groups)
        for (final ref in group)
          if (seen.add(ref)) ref,
    ];
  }

  AnkiCardSchedule _scheduleOf(AnkiCardRow row) {
    final state = switch (row.type) {
      0 => AnkiCardState.newCard,
      2 => AnkiCardState.review,
      3 => AnkiCardState.relearning,
      _ => AnkiCardState.learning,
    };
    final inFiltered = row.originalDeckId != 0;
    // En un mazo filtrado el calendario de verdad es `odue`.
    final due = inFiltered && row.originalDue != 0 ? row.originalDue : row.due;
    final lastMs = lastReviewByCard[row.id];

    return AnkiCardSchedule(
      state: state,
      easeFactor: row.factor <= 0 ? 2.5 : _clampEase(row.factor / 1000),
      intervalDays: row.interval < 0 ? 0 : row.interval,
      repetitions: state == AnkiCardState.newCard
          ? 0
          : (row.reps < 1 ? 1 : row.reps),
      lapses: row.lapses,
      dueAt: state == AnkiCardState.newCard ? null : _dueAt(due),
      newPosition: state == AnkiCardState.newCard ? due : null,
      lastReviewedAt: lastMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMs),
      suspended: row.queue == -1,
      postponed: row.queue == -2 || row.queue == -3,
      inFilteredDeck: inFiltered,
    );
  }

  double _clampEase(double ease) => ease < 1.3 ? 1.3 : ease;

  /// `due` de una tarjeta que no es nueva: días desde el día 0 de la
  /// colección, o —en aprendizaje— segundos desde 1970. Una cantidad de días
  /// no llega a cien millones (más de 270.000 años); unos segundos de hoy,
  /// sí.
  DateTime _dueAt(int due) {
    if (due > 100000000) {
      return DateTime.fromMillisecondsSinceEpoch(due * 1000);
    }
    final start = collectionCreatedAt;
    return DateTime(
      start.year,
      start.month,
      start.day + due,
      start.hour,
      start.minute,
      start.second,
    );
  }
}

final _answerRule = RegExp(
  r'''<hr\s+id\s*=\s*["']?answer["']?\s*/?>''',
  caseSensitive: false,
);

class _Built {
  const _Built(this.row, this.card);

  final AnkiCardRow row;
  final AnkiImportedCard card;

  _Built withKind(AnkiCardKind kind) => _Built(
    row,
    AnkiImportedCard(
      ankiCardId: card.ankiCardId,
      noteId: card.noteId,
      guid: card.guid,
      ord: card.ord,
      kind: kind,
      front: card.front,
      back: card.back,
      schedule: card.schedule,
      tags: card.tags,
      media: card.media,
      clozeSource: card.clozeSource,
      clozeNumber: card.clozeNumber,
      distractors: card.distractors,
      noteTypeName: card.noteTypeName,
    ),
  );
}
