import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Armado a mano de paquetes `.apkg` que imitan a los que escribe Anki, para
/// probar el lector sin depender del `AnkiPackageBuilder` de Sinapsis (que solo
/// escribe un subconjunto de lo que Anki real hace).
///
/// Las definiciones de tipos de nota ([basicModel], [reversedModel],
/// [optionalReversedModel], [typedModel], [clozeModel]) son las de fábrica de
/// Anki 2.1, con sus plantillas tal cual.

/// Un tipo de nota con la forma de `col.models`.
Map<String, dynamic> model({
  required int id,
  required String name,
  required List<String> fields,
  required List<({String name, String qfmt, String afmt})> templates,
  int type = 0,
}) {
  return {
    'id': id,
    'name': name,
    'type': type,
    'mod': 0,
    'usn': -1,
    'sortf': 0,
    'did': 1,
    'flds': [
      for (final (ord, field) in fields.indexed)
        {'name': field, 'ord': ord, 'sticky': false, 'rtl': false},
    ],
    'tmpls': [
      for (final (ord, t) in templates.indexed)
        {
          'name': t.name,
          'ord': ord,
          'qfmt': t.qfmt,
          'afmt': t.afmt,
          'did': null,
        },
    ],
    'css': '.card { font-family: arial; }',
    'req': <dynamic>[],
  };
}

const _back = '{{FrontSide}}\n\n<hr id=answer>\n\n';

Map<String, dynamic> basicModel(int id) => model(
  id: id,
  name: 'Básico',
  fields: ['Front', 'Back'],
  templates: [(name: 'Tarjeta 1', qfmt: '{{Front}}', afmt: '$_back{{Back}}')],
);

Map<String, dynamic> reversedModel(int id) => model(
  id: id,
  name: 'Básico (y tarjeta invertida)',
  fields: ['Front', 'Back'],
  templates: [
    (name: 'Tarjeta 1', qfmt: '{{Front}}', afmt: '$_back{{Back}}'),
    (name: 'Tarjeta 2', qfmt: '{{Back}}', afmt: '$_back{{Front}}'),
  ],
);

Map<String, dynamic> optionalReversedModel(int id) => model(
  id: id,
  name: 'Básico (tarjeta invertida opcional)',
  fields: ['Front', 'Back', 'Add Reverse'],
  templates: [
    (name: 'Tarjeta 1', qfmt: '{{Front}}', afmt: '$_back{{Back}}'),
    (
      name: 'Tarjeta 2',
      qfmt: '{{#Add Reverse}}{{Back}}{{/Add Reverse}}',
      afmt: '$_back{{Front}}',
    ),
  ],
);

Map<String, dynamic> typedModel(int id) => model(
  id: id,
  name: 'Básico (escribir la respuesta)',
  fields: ['Front', 'Back'],
  templates: [
    (
      name: 'Tarjeta 1',
      qfmt: '{{Front}}\n\n{{type:Back}}',
      afmt: '{{Front}}\n\n<hr id=answer>\n\n{{type:Back}}',
    ),
  ],
);

Map<String, dynamic> clozeModel(int id) => model(
  id: id,
  name: 'Cloze',
  type: 1,
  fields: ['Text', 'Extra'],
  templates: [
    (
      name: 'Cloze',
      qfmt: '{{cloze:Text}}',
      afmt: '{{cloze:Text}}<br>\n{{Extra}}',
    ),
  ],
);

/// Un mazo con la forma de `col.decks`.
Map<String, dynamic> deck(int id, String name, {bool filtered = false}) => {
  'id': id,
  'name': name,
  'mod': 0,
  'usn': 0,
  'collapsed': false,
  'dyn': filtered ? 1 : 0,
  'conf': 1,
  'desc': '',
};

class FixtureNote {
  const FixtureNote({
    required this.id,
    required this.modelId,
    required this.fields,
    this.tags = '',
    String? guid,
  }) : guid = guid ?? 'g$id';

  final int id;
  final int modelId;
  final List<String> fields;

  /// Como las guarda Anki: separadas por espacios y con uno a cada lado.
  final String tags;
  final String guid;
}

class FixtureCard {
  const FixtureCard({
    required this.id,
    required this.noteId,
    this.deckId = 1,
    this.ord = 0,
    this.type = 0,
    this.queue = 0,
    this.due = 1,
    this.ivl = 0,
    this.factor = 0,
    this.reps = 0,
    this.lapses = 0,
    this.left = 0,
    this.odue = 0,
    this.odid = 0,
  });

  final int id;
  final int noteId;
  final int deckId;
  final int ord;
  final int type;
  final int queue;
  final int due;
  final int ivl;
  final int factor;
  final int reps;
  final int lapses;
  final int left;
  final int odue;
  final int odid;
}

class FixtureReview {
  const FixtureReview({
    required this.id,
    required this.cardId,
    required this.ease,
    this.ivl = 1,
    this.lastIvl = 0,
    this.time = 5000,
  });

  final int id;
  final int cardId;
  final int ease;
  final int ivl;
  final int lastIvl;
  final int time;
}

const _schema = '''
CREATE TABLE col (id integer primary key, crt integer not null,
  mod integer not null, scm integer not null, ver integer not null,
  dty integer not null, usn integer not null, ls integer not null,
  conf text not null, models text not null, decks text not null,
  dconf text not null, tags text not null);
CREATE TABLE notes (id integer primary key, guid text not null,
  mid integer not null, mod integer not null, usn integer not null,
  tags text not null, flds text not null, sfld integer not null,
  csum integer not null, flags integer not null, data text not null);
CREATE TABLE cards (id integer primary key, nid integer not null,
  did integer not null, ord integer not null, mod integer not null,
  usn integer not null, type integer not null, queue integer not null,
  due integer not null, ivl integer not null, factor integer not null,
  reps integer not null, lapses integer not null, left integer not null,
  odue integer not null, odid integer not null, flags integer not null,
  data text not null);
CREATE TABLE revlog (id integer primary key, cid integer not null,
  usn integer not null, ease integer not null, ivl integer not null,
  lastIvl integer not null, factor integer not null, time integer not null,
  type integer not null);
''';

/// Los bytes de una colección SQLite al estilo del esquema 11 de Anki.
Uint8List collectionBytes({
  required int crt,
  required List<Map<String, dynamic>> models,
  required List<Map<String, dynamic>> decks,
  required List<FixtureNote> notes,
  required List<FixtureCard> cards,
  List<FixtureReview>? revlog,
  bool withRevlogTable = true,
}) {
  final dir = Directory.systemTemp.createTempSync('sinapsis-anki-fixture-');
  try {
    final file = File(p.join(dir.path, 'collection.db'));
    final db = sqlite3.sqlite3.open(file.path);
    try {
      db.execute(_schema);
      if (!withRevlogTable) db.execute('DROP TABLE revlog');
      db.execute(
        'INSERT INTO col VALUES (1, ?, 0, 0, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
        [
          crt,
          '{}',
          jsonEncode({for (final m in models) '${m['id']}': m}),
          jsonEncode({for (final d in decks) '${d['id']}': d}),
          '{}',
          '{}',
        ],
      );
      for (final n in notes) {
        db.execute(
          'INSERT INTO notes VALUES (?, ?, ?, 0, 0, ?, ?, 0, 0, 0, ?)',
          [n.id, n.guid, n.modelId, n.tags, n.fields.join('\u001f'), ''],
        );
      }
      for (final c in cards) {
        db.execute(
          'INSERT INTO cards VALUES '
          '(?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
          [
            c.id,
            c.noteId,
            c.deckId,
            c.ord,
            c.type,
            c.queue,
            c.due,
            c.ivl,
            c.factor,
            c.reps,
            c.lapses,
            c.left,
            c.odue,
            c.odid,
            '',
          ],
        );
      }
      if (withRevlogTable) {
        for (final r in revlog ?? const <FixtureReview>[]) {
          db.execute('INSERT INTO revlog VALUES (?, ?, 0, ?, ?, ?, 0, ?, 1)', [
            r.id,
            r.cardId,
            r.ease,
            r.ivl,
            r.lastIvl,
            r.time,
          ]);
        }
      }
    } finally {
      db.close();
    }
    return file.readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Un `.apkg` con las entradas dadas: nombre → bytes.
Uint8List zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in entries.entries) {
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// Un paquete completo con la colección dentro de [collectionName].
Uint8List apkgOf(
  Uint8List collection, {
  String collectionName = 'collection.anki21',
  String media = '{}',
  Map<String, List<int>> extra = const {},
}) =>
    zipOf({collectionName: collection, 'media': utf8.encode(media), ...extra});

/// La colección de relleno que Anki escribe junto al formato nuevo: una sola
/// nota que pide actualizar.
Uint8List placeholderCollection() {
  final basic = basicModel(1);
  return collectionBytes(
    crt: 1700000000,
    models: [basic],
    decks: [deck(1, 'Default')],
    notes: const [
      FixtureNote(
        id: 1,
        modelId: 1,
        fields: [
          'Please update to the latest Anki version, then import the .colpkg/.apkg file again.',
          '',
        ],
      ),
    ],
    cards: const [FixtureCard(id: 1, noteId: 1)],
  );
}

/// La misma colección con otro `models` y `decks` en `col`: para imitar un
/// esquema que los deja vacíos, o un JSON dañado.
Uint8List rewriteColJson(
  Uint8List collection, {
  required String models,
  required String decks,
}) {
  final dir = Directory.systemTemp.createTempSync('sinapsis-anki-fixture-');
  try {
    final file = File(p.join(dir.path, 'collection.db'))
      ..writeAsBytesSync(collection);
    final db = sqlite3.sqlite3.open(file.path);
    try {
      db.execute('UPDATE col SET models = ?, decks = ?', [models, decks]);
    } finally {
      db.close();
    }
    return file.readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Una base SQLite válida que no es de Anki.
Uint8List unrelatedDatabaseBytes() {
  final dir = Directory.systemTemp.createTempSync('sinapsis-anki-fixture-');
  try {
    final file = File(p.join(dir.path, 'otra.db'));
    final db = sqlite3.sqlite3.open(file.path);
    try {
      db
        ..execute('CREATE TABLE tareas (id integer primary key, texto text)')
        ..execute("INSERT INTO tareas (texto) VALUES ('comprar pan')");
    } finally {
      db.close();
    }
    return file.readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
