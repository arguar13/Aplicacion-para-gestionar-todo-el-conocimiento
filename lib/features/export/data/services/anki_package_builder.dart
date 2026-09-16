import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// [AnkiDeckBuilder] sobre el esquema clásico de Anki ("schema 11"), el
/// mismo que arma `genanki` —la librería de referencia para generar
/// `.apkg` fuera de Anki—: es el que entienden todas las versiones de Anki
/// al importar un paquete, a diferencia del esquema nuevo con
/// `collection.anki21b` comprimido en zstd, pensado para sincronizar con
/// AnkiWeb y no para un archivo suelto.
///
/// El estado de repaso (SM-2, ver [Flashcard]) de cada tarjeta se traduce a
/// los campos de Anki: una tarjeta sin repasos todavía (`repetitions == 0`)
/// queda como tarjeta "nueva"; el resto, como tarjeta "de repaso", con su
/// intervalo y factor de facilidad ya cargados — así seguir repasando en
/// Anki continúa donde quedó, en vez de reiniciar el progreso.
class AnkiPackageBuilder implements AnkiDeckBuilder {
  const AnkiPackageBuilder();

  static const _deckName = 'Sinapsis';
  static const _modelName = 'Sinapsis básico';
  static const _defaultDeckId = 1;
  static const _defaultConfId = 1;

  @override
  Future<Uint8List> build(List<Flashcard> cards) async {
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

  void _writeCollection(sqlite3.Database db, List<Flashcard> cards) {
    db.execute(_schemaSql);

    final now = DateTime.now();
    final createdAt = DateTime(now.year, now.month, now.day);
    final crt = createdAt.millisecondsSinceEpoch ~/ 1000;
    final modMs = now.millisecondsSinceEpoch;

    // IDs únicos y crecientes para todo lo que hace falta: el mazo, el
    // modelo de nota, y cada nota/tarjeta. No importa el orden entre roles
    // distintos, solo que no se repitan entre sí.
    var nextId = modMs;
    int newId() => nextId++;

    final deckId = newId();
    final modelId = newId();

    db.execute(
      'INSERT INTO col '
      '(id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, '
      'tags) '
      'VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
      [
        crt,
        modMs,
        modMs,
        jsonEncode(_conf(deckId: deckId, modelId: modelId)),
        jsonEncode(_models(modelId: modelId, deckId: deckId)),
        jsonEncode(_decks(deckId: deckId)),
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
      'VALUES (?, ?, ?, 0, ?, 0, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, ?)',
    );

    try {
      for (final card in cards) {
        final noteId = newId();
        final cardId = newId();
        final reviewedOrCreatedAt = card.lastReviewedAt ?? card.createdAt;
        final noteModSeconds =
            reviewedOrCreatedAt.millisecondsSinceEpoch ~/ 1000;
        final front = card.front.trim();
        final back = card.back.trim();

        insertNote.execute([
          noteId,
          card.id,
          modelId,
          noteModSeconds,
          '',
          '$front\u001f$back',
          front,
          _fieldChecksum(front),
          '',
        ]);

        final scheduling = _scheduling(card, collectionCreatedAt: createdAt);
        insertCard.execute([
          cardId,
          noteId,
          deckId,
          noteModSeconds,
          scheduling.type,
          scheduling.queue,
          scheduling.due,
          scheduling.ivl,
          scheduling.factor,
          card.repetitions,
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
    if (card.repetitions <= 0) {
      // Tarjeta nueva: sin repasos todavía, Anki la mete en la cola de
      // tarjetas nuevas y el "due" ahí es una posición relativa, no una
      // fecha.
      return const _CardScheduling(
        type: 0,
        queue: 0,
        due: 0,
        ivl: 0,
        factor: 0,
      );
    }

    final dueInDays = card.dueAt.difference(collectionCreatedAt).inDays;
    return _CardScheduling(
      type: 2,
      queue: 2,
      // Ya estaba vencida al momento de exportar: que aparezca para repasar
      // hoy mismo en vez de con un "due" negativo, que Anki no espera ver
      // en una tarjeta de repaso.
      due: dueInDays < 1 ? 1 : dueInDays,
      ivl: card.intervalDays < 1 ? 1 : card.intervalDays,
      factor: (card.easeFactor * 1000).round(),
    );
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

  Map<String, dynamic> _models({required int modelId, required int deckId}) {
    return {
      '$modelId': {
        'id': modelId,
        'name': _modelName,
        'type': 0,
        'mod': 0,
        'usn': 0,
        'sortf': 0,
        'did': deckId,
        'tmpls': [
          {
            'name': 'Tarjeta 1',
            'ord': 0,
            'qfmt': '{{Front}}',
            'afmt': '{{FrontSide}}\n\n<hr id="answer">\n\n{{Back}}',
            'did': null,
            'bqfmt': '',
            'bafmt': '',
          },
        ],
        'flds': [
          {
            'name': 'Front',
            'ord': 0,
            'sticky': false,
            'rtl': false,
            'font': 'Arial',
            'size': 20,
          },
          {
            'name': 'Back',
            'ord': 1,
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
      },
    };
  }

  Map<String, dynamic> _decks({required int deckId}) {
    return {
      '$_defaultDeckId': _deck(
        id: _defaultDeckId,
        name: 'Default',
        collapsed: true,
      ),
      '$deckId': _deck(id: deckId, name: _deckName, collapsed: false),
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
  });

  final int type;
  final int queue;
  final int due;
  final int ivl;
  final int factor;
}
