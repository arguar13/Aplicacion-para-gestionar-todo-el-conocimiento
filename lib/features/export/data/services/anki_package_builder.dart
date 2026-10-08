import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// [AnkiDeckBuilder] sobre el esquema clásico de Anki ("schema 11"), el
/// mismo que arma `genanki` —la librería de referencia para generar
/// `.apkg` fuera de Anki—: es el que entienden todas las versiones de Anki
/// al importar un paquete, a diferencia del esquema nuevo con
/// `collection.anki21b` comprimido en zstd, pensado para sincronizar con
/// AnkiWeb y no para un archivo suelto.
///
/// El estado de repaso (SM-2 con pasos de aprendizaje, ver [Flashcard]) de
/// cada tarjeta se traduce a los campos de Anki según su etapa
/// (`Flashcard.phase`, F31):
///
/// - nueva → `type 0`, cola de nuevas;
/// - aprendiendo → `type 1`, cola de aprendizaje, con la fecha en que vuelve
///   (`due` en segundos) y los pasos que le faltan (`left`);
/// - en repaso → `type 2`, cola de repaso, con su intervalo y factor de
///   facilidad ya cargados;
/// - reaprendiendo (se olvidó) → `type 3`, cola de aprendizaje, con su
///   intervalo y la fecha en que vuelve;
/// - pausada (`Flashcard.suspended`) → cola `-1`, cualquiera sea la etapa: en
///   Anki sale como "suspendida" y conserva el resto de su calendario.
///
/// Así seguir repasando en Anki continúa donde quedó, en vez de reiniciar el
/// progreso. (Una pospuesta hasta mañana sale como cualquier otra: es un "hoy
/// no" que Anki ni siquiera guarda entre días.)
///
/// CUATRO modelos de nota en el mismo paquete (F20, commit 9; F31): el básico
/// (`Front`/`Back`) para `freeRecall`/`trueFalse`; uno propio para
/// `multipleChoice` —`Question`/`Answer`/`Distractor1..3`, la pregunta con
/// distractores reales, nunca degradada al modelo de dos campos—; el `Cloze`
/// de Anki para los huecos (`cloze`), con UNA nota por texto y una carta por
/// hueco —las hermanas de un `group_id` comparten nota, y `cloze_index - 1` es
/// el `ord` de la carta—; y uno de "escribí la respuesta" (`typedAnswer`), el
/// básico con `{{type:Back}}`. El formato clásico de Anki ya admite varios
/// modelos en una misma colección (`col.models` es un mapa `{modelId:
/// definición}`, cada nota declara el suyo en `notes.mid`); no hace falta
/// tocar el esquema SQL para esto.
class AnkiPackageBuilder implements AnkiDeckBuilder {
  const AnkiPackageBuilder();

  static const _modelName = 'Sinapsis básico';
  static const _multipleChoiceModelName = 'Sinapsis opción múltiple';
  static const _clozeModelName = 'Sinapsis huecos';
  static const _typedAnswerModelName = 'Sinapsis escribí la respuesta';
  static const _defaultDeckId = 1;
  static const _defaultConfId = 1;

  @override
  Future<Uint8List> build(List<AnkiCardExport> cards) async {
    // Archivo de trabajo descartable, igual que en
    // `LocalVaultBackupService`: `Directory.systemTemp` y no
    // `path_provider`, para que esta clase se pueda probar con
    // `flutter test` puro, sin inicializar ningún binding.
    final dbFile = File(
      p.join(
        Directory.systemTemp.path,
        'sinapsis-anki-${DateTime.now().microsecondsSinceEpoch}.anki2',
      ),
    );
    if (dbFile.existsSync()) await dbFile.delete();

    final db = sqlite3.sqlite3.open(dbFile.path);
    try {
      _writeCollection(db, cards);
    } finally {
      db.close();
    }

    final dbBytes = await dbFile.readAsBytes();
    await dbFile.delete();

    final archive = Archive()
      ..addFile(ArchiveFile.bytes('collection.anki2', dbBytes))
      // El manifiesto de medios: sin fotos ni audio en las tarjetas, un
      // mapa vacío es un manifiesto válido — Anki lo exige igual para
      // reconocer el `.zip` como un paquete suyo.
      ..addFile(ArchiveFile.bytes('media', utf8.encode('{}')));

    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  void _writeCollection(sqlite3.Database db, List<AnkiCardExport> cards) {
    db.execute(_schemaSql);

    final now = DateTime.now();
    final createdAt = DateTime(now.year, now.month, now.day);
    final crt = createdAt.millisecondsSinceEpoch ~/ 1000;
    final modMs = now.millisecondsSinceEpoch;

    // IDs únicos y crecientes para todo lo que hace falta: un mazo por cada
    // subdeck distinto (D1/D2), el modelo de nota, y cada nota/tarjeta. No
    // importa el orden entre roles distintos, solo que no se repitan entre
    // sí.
    var nextId = modMs;
    int newId() => nextId++;

    // Un id por PATH distinto, en el orden en que aparece la primera
    // tarjeta de cada uno: da igual cuál, Anki no distingue el orden de
    // creación de sus mazos.
    final deckIdByPath = <String, int>{
      for (final path in {for (final export in cards) export.deckPath})
        path: newId(),
    };
    final modelId = newId();
    final multipleChoiceModelId = newId();
    final clozeModelId = newId();
    final typedAnswerModelId = newId();

    db.execute(
      'INSERT INTO col '
      '(id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, '
      'tags) '
      'VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
      [
        crt,
        modMs,
        modMs,
        // El `deckId` de acá es solo el que Anki propone por defecto para
        // una tarjeta nueva creada a mano con este modelo, dentro de Anki
        // mismo —nunca se usa al importar—: dónde queda CADA tarjeta ya
        // importada lo decide su propia fila en `cards.did`, más abajo.
        jsonEncode(
          _conf(
            deckId: deckIdByPath.values.firstOrNull ?? _defaultDeckId,
            modelId: modelId,
          ),
        ),
        jsonEncode(<String, dynamic>{
          ..._basicModel(
            modelId: modelId,
            deckId: deckIdByPath.values.firstOrNull ?? _defaultDeckId,
          ),
          ..._multipleChoiceModel(
            modelId: multipleChoiceModelId,
            deckId: deckIdByPath.values.firstOrNull ?? _defaultDeckId,
          ),
          ..._clozeModel(
            modelId: clozeModelId,
            deckId: deckIdByPath.values.firstOrNull ?? _defaultDeckId,
          ),
          ..._typedAnswerModel(
            modelId: typedAnswerModelId,
            deckId: deckIdByPath.values.firstOrNull ?? _defaultDeckId,
          ),
        }),
        jsonEncode(_decks(deckIdByPath)),
        jsonEncode(_dconf()),
        '{}',
      ],
    );

    final insertNote = db.prepare(
      'INSERT INTO notes '
      '(id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) '
      'VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, 0, ?)',
    );
    final insertCard = db.prepare(
      'INSERT INTO cards '
      '(id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, '
      'lapses, left, odue, odid, flags, data) '
      'VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 0, ?, 0, 0, 0, ?)',
    );

    // Las hermanas de huecos comparten UNA nota de Anki: la primera la crea.
    final clozeNoteByGroup = <String, int>{};

    try {
      for (final export in cards) {
        final card = export.card;
        final cardId = newId();
        final reviewedOrCreatedAt = card.lastReviewedAt ?? card.createdAt;
        final noteModSeconds =
            reviewedOrCreatedAt.millisecondsSinceEpoch ~/ 1000;
        final front = card.front.trim();
        final isCloze = card.kind == FlashcardKind.cloze;
        final groupId = card.groupId;
        // La carta de un hueco es la `ord` = hueco - 1 de su nota.
        final ord = isCloze ? (card.clozeIndex ?? 1) - 1 : 0;

        final existingClozeNote = isCloze && groupId != null
            ? clozeNoteByGroup[groupId]
            : null;
        final noteId = existingClozeNote ?? newId();

        if (existingClozeNote == null) {
          // Frente y reverso (en los huecos: el texto entero con sus
          // `{{cN::…}}`, que es la sintaxis de Anki, y el complemento en
          // "Back Extra").
          final twoFields =
              '$front\u001f'
              '${_backWithProvenance(export.answer.trim(), export.provenance)}';
          final (noteModelId, flds) = switch (card.kind) {
            FlashcardKind.multipleChoice => (
              multipleChoiceModelId,
              _multipleChoiceFields(export),
            ),
            FlashcardKind.cloze => (clozeModelId, twoFields),
            FlashcardKind.typedAnswer => (typedAnswerModelId, twoFields),
            FlashcardKind.freeRecall ||
            FlashcardKind.trueFalse => (modelId, twoFields),
          };

          insertNote.execute([
            noteId,
            // El guid es el de la primera tarjeta del grupo: estable entre
            // exportaciones.
            card.id,
            noteModelId,
            noteModSeconds,
            '',
            flds,
            front,
            _fieldChecksum(front),
            '',
          ]);
          if (isCloze && groupId != null) clozeNoteByGroup[groupId] = noteId;
        }

        final scheduling = _scheduling(card, collectionCreatedAt: createdAt);
        insertCard.execute([
          cardId,
          noteId,
          deckIdByPath[export.deckPath],
          ord,
          noteModSeconds,
          scheduling.type,
          scheduling.queue,
          scheduling.due,
          scheduling.ivl,
          scheduling.factor,
          card.repetitions,
          scheduling.left,
          '',
        ]);
      }
    } finally {
      insertNote.close();
      insertCard.close();
    }
  }

  _CardScheduling _scheduling(
    Flashcard card, {
    required DateTime collectionCreatedAt,
  }) {
    final base = _schedulingOf(card, collectionCreatedAt: collectionCreatedAt);
    // Pausada: la cola de Anki es -1 sea cual sea la etapa; el resto de su
    // calendario (tipo, intervalo, factor, fecha) se conserva para cuando se
    // la reactive allá.
    return card.suspended ? base.suspended() : base;
  }

  _CardScheduling _schedulingOf(
    Flashcard card, {
    required DateTime collectionCreatedAt,
  }) {
    switch (card.phase) {
      case CardPhase.newCard:
        // Tarjeta nueva: sin repasos todavía, Anki la mete en la cola de
        // tarjetas nuevas y el "due" ahí es una posición relativa, no una
        // fecha.
        return const _CardScheduling(
          type: 0,
          queue: 0,
          due: 0,
          ivl: 0,
          factor: 0,
          left: 0,
        );
      case CardPhase.learning:
      case CardPhase.relearning:
        // En la cola de aprendizaje el "due" es el momento en que vuelve, en
        // segundos desde 1970, y "left" cuántos pasos le faltan.
        final learning = card.phase == CardPhase.learning;
        final stepsLeft = learning ? 2 - (card.learningStep ?? 0) : 1;
        return _CardScheduling(
          type: learning ? 1 : 3,
          queue: 1,
          due: card.dueAt.millisecondsSinceEpoch ~/ 1000,
          ivl: learning ? 0 : (card.intervalDays < 1 ? 1 : card.intervalDays),
          factor: (card.easeFactor * 1000).round(),
          left: stepsLeft < 1 ? 1 : stepsLeft,
        );
      case CardPhase.review:
        final dueInDays = card.dueAt.difference(collectionCreatedAt).inDays;
        return _CardScheduling(
          type: 2,
          queue: 2,
          // Ya estaba vencida al momento de exportar: que aparezca para
          // repasar hoy mismo en vez de con un "due" negativo, que Anki no
          // espera ver en una tarjeta de repaso.
          due: dueInDays < 1 ? 1 : dueInDays,
          ivl: card.intervalDays < 1 ? 1 : card.intervalDays,
          factor: (card.easeFactor * 1000).round(),
          left: 0,
        );
    }
  }

  /// El reverso con la procedencia debajo, separada por una línea en
  /// blanco —el campo de Anki es HTML, `<br>` y no `\n` es lo que se ve
  /// como salto de línea—. Sin cita resuelta, el reverso queda igual que
  /// siempre.
  String _backWithProvenance(String back, String? provenance) {
    if (provenance == null || provenance.isEmpty) return back;
    return '$back<br><br>$provenance';
  }

  /// El mismo algoritmo que usa `genanki` para el índice de duplicados de
  /// Anki: los primeros 8 dígitos hexadecimales del SHA-1 del campo de
  /// ordenamiento, como entero. No es criptografía — es solo la clave que
  /// Anki usa para reconocer notas repetidas al importar.
  int _fieldChecksum(String sortField) {
    final digest = sha1.convert(utf8.encode(sortField));
    final hex = digest.toString().substring(0, 8);
    return int.parse(hex, radix: 16);
  }

  Map<String, dynamic> _basicModel({
    required int modelId,
    required int deckId,
  }) {
    return {
      '$modelId': _modelDefinition(
        modelId: modelId,
        deckId: deckId,
        name: _modelName,
        fieldNames: const ['Front', 'Back'],
        qfmt: '{{Front}}',
        afmt: '{{FrontSide}}\n\n<hr id="answer">\n\n{{Back}}',
      ),
    };
  }

  /// La pregunta con su respuesta correcta, y —si las trae— sus
  /// distractores reales debajo, en el reverso, para que quien repasa en
  /// Anki también vea qué otras opciones consideró Sinapsis. `Distractor2`/
  /// `Distractor3` quedan vacíos, y por eso afuera de la plantilla
  /// (`{{#Campo}}`, la condición de Anki para "el campo no está vacío"),
  /// cuando la pregunta trajo menos de tres.
  Map<String, dynamic> _multipleChoiceModel({
    required int modelId,
    required int deckId,
  }) {
    return {
      '$modelId': _modelDefinition(
        modelId: modelId,
        deckId: deckId,
        name: _multipleChoiceModelName,
        fieldNames: const [
          'Question',
          'Answer',
          'Distractor1',
          'Distractor2',
          'Distractor3',
        ],
        qfmt: '{{Question}}',
        afmt:
            '{{FrontSide}}\n\n<hr id="answer">\n\n'
            '<b>{{Answer}}</b>\n\n '
            // Sin espacio entre `<br>` y `{{Distractor1}}` a propósito: es
            // justo donde el salto de línea de la plantilla tiene que
            // quedar pegado al campo, no un espacio olvidado.
            // ignore: missing_whitespace_between_adjacent_strings
            '{{#Distractor1}}Otras opciones consideradas:<br>'
            '{{Distractor1}}{{/Distractor1}} '
            '{{#Distractor2}}<br>{{Distractor2}}{{/Distractor2}} '
            '{{#Distractor3}}<br>{{Distractor3}}{{/Distractor3}}',
      ),
    };
  }

  /// Huecos para completar (F31): el modelo `Cloze` de Anki (`type: 1`), con
  /// los campos `Text` —el texto entero con sus `{{cN::…}}`— y `Back Extra`.
  /// Anki arma una carta por cada hueco.
  Map<String, dynamic> _clozeModel({
    required int modelId,
    required int deckId,
  }) {
    return {
      '$modelId': {
        ..._modelDefinition(
          modelId: modelId,
          deckId: deckId,
          name: _clozeModelName,
          fieldNames: const ['Text', 'Back Extra'],
          qfmt: '{{cloze:Text}}',
          afmt: '{{cloze:Text}}<br>\n{{Back Extra}}',
        ),
        'type': 1,
        'css':
            '.card {\n'
            ' font-family: arial;\n'
            ' font-size: 20px;\n'
            ' text-align: center;\n'
            ' color: black;\n'
            ' background-color: white;\n'
            '}\n'
            '.cloze {\n'
            ' font-weight: bold;\n'
            ' color: blue;\n'
            '}\n',
      },
    };
  }

  /// "Escribí la respuesta" (F31): el básico con `{{type:Back}}`, que en Anki
  /// pide escribir la respuesta y la compara con la correcta.
  Map<String, dynamic> _typedAnswerModel({
    required int modelId,
    required int deckId,
  }) {
    return {
      '$modelId': _modelDefinition(
        modelId: modelId,
        deckId: deckId,
        name: _typedAnswerModelName,
        fieldNames: const ['Front', 'Back'],
        qfmt: '{{Front}}\n\n{{type:Back}}',
        afmt: '{{Front}}\n\n<hr id="answer">\n\n{{type:Back}}',
      ),
    };
  }

  /// La definición común a cualquier modelo de nota de este paquete: una
  /// sola plantilla ("Tarjeta 1"), un campo por [fieldNames] en ese orden
  /// —el primero es el de ordenamiento (`sortf`)—, mismo CSS y preámbulo de
  /// LaTeX para los dos modelos.
  Map<String, dynamic> _modelDefinition({
    required int modelId,
    required int deckId,
    required String name,
    required List<String> fieldNames,
    required String qfmt,
    required String afmt,
  }) {
    return {
      'id': modelId,
      'name': name,
      'type': 0,
      'mod': 0,
      'usn': 0,
      'sortf': 0,
      'did': deckId,
      'tmpls': [
        {
          'name': 'Tarjeta 1',
          'ord': 0,
          'qfmt': qfmt,
          'afmt': afmt,
          'did': null,
          'bqfmt': '',
          'bafmt': '',
        },
      ],
      'flds': [
        for (final (ord, fieldName) in fieldNames.indexed)
          {
            'name': fieldName,
            'ord': ord,
            'sticky': false,
            'rtl': false,
            'font': 'Arial',
            'size': 20,
          },
      ],
      'css':
          '.card {\n'
          ' font-family: arial;\n'
          ' font-size: 20px;\n'
          ' text-align: center;\n'
          ' color: black;\n'
          ' background-color: white;\n'
          '}\n',
      'latexPre':
          r'\documentclass[12pt]{article}'
          '\n'
          r'\special{papersize=3in,5in}'
          '\n'
          r'\usepackage[utf8]{inputenc}'
          '\n'
          r'\usepackage{amssymb,amsmath}'
          '\n'
          r'\pagestyle{empty}'
          '\n'
          r'\setlength{\parindent}{0in}'
          '\n'
          r'\begin{document}'
          '\n',
      'latexPost': r'\end{document}',
      'req': [
        [
          0,
          'any',
          [0],
        ],
      ],
    };
  }

  /// Los campos de una nota `multipleChoice`, en el orden del modelo:
  /// pregunta, respuesta correcta, hasta tres distractores —los que
  /// falten, campo vacío—.
  String _multipleChoiceFields(AnkiCardExport export) {
    final distractors = export.distractors;
    return [
      export.card.front.trim(),
      export.answer.trim(),
      for (var i = 0; i < 3; i++)
        if (i < distractors.length) distractors[i].trim() else '',
    ].join('\u001f');
  }

  /// Un mazo por cada `deckPath` distinto entre las tarjetas, más el
  /// `Default` que Anki exige siempre. El nombre completo —con sus `::`— es
  /// lo único que hace falta: Anki arma el árbol de subdecks a partir de él
  /// solo, sin una fila propia por cada nivel intermedio.
  Map<String, dynamic> _decks(Map<String, int> deckIdByPath) {
    return {
      '$_defaultDeckId': _deck(
        id: _defaultDeckId,
        name: 'Default',
        collapsed: true,
      ),
      for (final MapEntry(key: path, value: id) in deckIdByPath.entries)
        '$id': _deck(id: id, name: path, collapsed: false),
    };
  }

  Map<String, dynamic> _deck({
    required int id,
    required String name,
    required bool collapsed,
  }) {
    return {
      'id': id,
      'mod': 0,
      'name': name,
      'usn': 0,
      'lrnToday': [0, 0],
      'revToday': [0, 0],
      'newToday': [0, 0],
      'timeToday': [0, 0],
      'collapsed': collapsed,
      'dyn': 0,
      'conf': _defaultConfId,
      'extendNew': 10,
      'extendRev': 50,
      'desc': '',
    };
  }

  Map<String, dynamic> _dconf() {
    return {
      '$_defaultConfId': {
        'id': _defaultConfId,
        'mod': 0,
        'name': 'Default',
        'usn': 0,
        'maxTaken': 60,
        'autoplay': true,
        'timer': 0,
        'replayq': true,
        'new': {
          'bury': false,
          'delays': [1, 10],
          'initialFactor': 2500,
          'ints': [1, 4, 7],
          'order': 1,
          'perDay': 20,
        },
        'rev': {
          'bury': false,
          'ease4': 1.3,
          'ivlFct': 1,
          'maxIvl': 36500,
          'perDay': 200,
        },
        'lapse': {
          'delays': [10],
          'leechAction': 1,
          'leechFails': 8,
          'minInt': 1,
          'mult': 0,
        },
        'dyn': false,
      },
    };
  }

  Map<String, dynamic> _conf({required int deckId, required int modelId}) {
    return {
      'curDeck': deckId,
      'curModel': '$modelId',
      'nextPos': 1,
      'estTimes': true,
      'dueCounts': true,
      'activeDecks': [deckId],
      'sortType': 'noteFld',
      'sortBackwards': false,
      'addToCur': true,
      'newSpread': 0,
      'collapseTime': 1200,
      'timeLim': 0,
      'newBury': true,
    };
  }

  static const _schemaSql = '''
CREATE TABLE col (
  id integer primary key,
  crt integer not null,
  mod integer not null,
  scm integer not null,
  ver integer not null,
  dty integer not null,
  usn integer not null,
  ls integer not null,
  conf text not null,
  models text not null,
  decks text not null,
  dconf text not null,
  tags text not null
);
CREATE TABLE notes (
  id integer primary key,
  guid text not null,
  mid integer not null,
  mod integer not null,
  usn integer not null,
  tags text not null,
  flds text not null,
  sfld text not null,
  csum integer not null,
  flags integer not null,
  data text not null
);
CREATE TABLE cards (
  id integer primary key,
  nid integer not null,
  did integer not null,
  ord integer not null,
  mod integer not null,
  usn integer not null,
  type integer not null,
  queue integer not null,
  due integer not null,
  ivl integer not null,
  factor integer not null,
  reps integer not null,
  lapses integer not null,
  left integer not null,
  odue integer not null,
  odid integer not null,
  flags integer not null,
  data text not null
);
CREATE TABLE revlog (
  id integer primary key,
  cid integer not null,
  usn integer not null,
  ease integer not null,
  ivl integer not null,
  lastIvl integer not null,
  factor integer not null,
  time integer not null,
  type integer not null
);
CREATE TABLE graves (
  usn integer not null,
  oid integer not null,
  type integer not null
);
CREATE INDEX ix_notes_usn ON notes (usn);
CREATE INDEX ix_cards_usn ON cards (usn);
CREATE INDEX ix_revlog_usn ON revlog (usn);
CREATE INDEX ix_cards_nid ON cards (nid);
CREATE INDEX ix_cards_sched ON cards (did, queue, due);
CREATE INDEX ix_revlog_cid ON revlog (cid);
CREATE INDEX ix_notes_csum ON notes (csum);
''';
}

class _CardScheduling {
  const _CardScheduling({
    required this.type,
    required this.queue,
    required this.due,
    required this.ivl,
    required this.factor,
    required this.left,
  });

  final int type;
  final int queue;
  final int due;
  final int ivl;
  final int factor;

  /// Los pasos de aprendizaje que le faltan (0 fuera de la cola de
  /// aprendizaje).
  final int left;

  /// La misma tarjeta, suspendida en Anki (cola -1).
  _CardScheduling suspended() => _CardScheduling(
    type: type,
    queue: -1,
    due: due,
    ivl: ivl,
    factor: factor,
    left: left,
  );
}
