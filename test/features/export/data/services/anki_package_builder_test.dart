import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/export/data/services/anki_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// No hay forma de probar un import de verdad contra la aplicación Anki en
/// este entorno; lo que sí se puede probar —y lo que se prueba acá— es que
/// el `.apkg` generado es un `.zip` válido con una base SQLite adentro que
/// respeta el esquema legado de Anki (tablas, columnas y JSON de
/// configuración), que el estado SM-2 de cada tarjeta se traduce a los
/// campos de repaso que Anki espera, y que cada `deckPath` distinto (F17,
/// D1/D2) es su propio mazo.
void main() {
  const builder = AnkiPackageBuilder();

  Flashcard card({
    required String id,
    required String front,
    required String back,
    int repetitions = 0,
    double easeFactor = 2.5,
    int intervalDays = 0,
    DateTime? dueAt,
    DateTime? createdAt,
    DateTime? lastReviewedAt,
  }) {
    final now = DateTime.now();
    return Flashcard(
      id: id,
      itemId: 'item-1',
      front: front,
      back: back,
      dueAt: dueAt ?? now,
      createdAt: createdAt ?? now,
      repetitions: repetitions,
      easeFactor: easeFactor,
      intervalDays: intervalDays,
      lastReviewedAt: lastReviewedAt,
    );
  }

  AnkiCardExport export(
    Flashcard card, {
    String deckPath = 'Sinapsis::Sin tema',
    String? provenance,
    List<String> distractors = const [],
  }) => AnkiCardExport(
    card: card,
    deckPath: deckPath,
    answer: card.back,
    provenance: provenance,
    distractors: distractors,
  );

  test(
    'arma un .zip con la base de Anki y el manifiesto de medios adentro',
    () async {
      final bytes = await builder.build([
        export(card(id: 'c1', front: '¿Capital de Francia?', back: 'París')),
      ]);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(
        archive.files.map((f) => f.name),
        containsAll(['collection.anki2', 'media']),
      );

      final mediaEntry = archive.files.firstWhere((f) => f.name == 'media');
      expect(utf8.decode(mediaEntry.content as List<int>), '{}');
    },
  );

  test('cada tarjeta se convierte en una nota y una carta de Anki', () async {
    final bytes = await builder.build([
      export(card(id: 'c1', front: 'Pregunta 1', back: 'Respuesta 1')),
      export(
        card(
          id: 'c2',
          front: 'Pregunta 2',
          back: 'Respuesta 2',
          repetitions: 3,
          easeFactor: 2.3,
          intervalDays: 6,
          dueAt: DateTime.now().add(const Duration(days: 4)),
          lastReviewedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ),
    ]);

    final db = await _openCollection(bytes);
    try {
      final notes = db.select('SELECT * FROM notes ORDER BY rowid');
      final cards = db.select('SELECT * FROM cards ORDER BY rowid');

      expect(notes, hasLength(2));
      expect(cards, hasLength(2));
      // El separador de campos de Anki (U+001F) entre Front y Back: sin él,
      // Anki lee las dos mitades como un solo campo.
      expect(notes.first['flds'], 'Pregunta 1\u001fRespuesta 1');
      expect(notes.first['sfld'], 'Pregunta 1');

      // La primera nunca se repasó: queda como tarjeta nueva.
      expect(cards.first['type'], 0);
      expect(cards.first['queue'], 0);

      // La segunda ya tiene historial de SM-2: queda como tarjeta de
      // repaso, con su intervalo, factor y repeticiones ya cargados.
      expect(cards.last['type'], 2);
      expect(cards.last['queue'], 2);
      expect(cards.last['factor'], 2300);
      expect(cards.last['ivl'], 6);
      expect(cards.last['reps'], 3);
    } finally {
      db.close();
    }
  });

  test('la fila de la colección trae JSON válido en sus columnas de '
      'configuración, con el subdeck de la tarjeta entre los mazos', () async {
    final bytes = await builder.build([
      export(
        card(id: 'c1', front: 'Pregunta', back: 'Respuesta'),
        deckPath: 'Sinapsis::Historia::Roma',
      ),
    ]);

    final db = await _openCollection(bytes);
    try {
      final col = db.select('SELECT * FROM col').single;

      expect(col['ver'], 11);
      final models =
          jsonDecode(col['models'] as String) as Map<String, dynamic>;
      final decks = jsonDecode(col['decks'] as String) as Map<String, dynamic>;
      final dconf = jsonDecode(col['dconf'] as String) as Map<String, dynamic>;
      final conf = jsonDecode(col['conf'] as String) as Map<String, dynamic>;

      expect(models, isNotEmpty);
      expect(
        decks.values.any(
          (d) => (d as Map)['name'] == 'Sinapsis::Historia::Roma',
        ),
        isTrue,
      );
      expect(dconf, isNotEmpty);
      expect(conf['curDeck'], isNotNull);
    } finally {
      db.close();
    }
  });

  group('procedencia en el reverso (F17, commit 3)', () {
    test('con procedencia, va debajo de la respuesta, separada', () async {
      final bytes = await builder.build([
        export(
          card(id: 'c1', front: 'Pregunta', back: 'Respuesta'),
          provenance: '(Autor, 2020, p. 4)',
        ),
      ]);

      final db = await _openCollection(bytes);
      try {
        final note = db.select('SELECT * FROM notes').single;
        expect(
          note['flds'],
          'Pregunta\u001fRespuesta<br><br>(Autor, 2020, p. 4)',
        );
        // El campo de ordenamiento sigue siendo solo la pregunta: la
        // procedencia no es parte de lo que Anki usa para ordenar ni para
        // el checksum de duplicados.
        expect(note['sfld'], 'Pregunta');
      } finally {
        db.close();
      }
    });

    test('sin procedencia, el reverso queda igual que siempre', () async {
      final bytes = await builder.build([
        export(card(id: 'c1', front: 'Pregunta', back: 'Respuesta')),
      ]);

      final db = await _openCollection(bytes);
      try {
        final note = db.select('SELECT * FROM notes').single;
        expect(note['flds'], 'Pregunta\u001fRespuesta');
      } finally {
        db.close();
      }
    });
  });

  group('subdecks (F17, D1/D2)', () {
    test('cada deckPath distinto es su propio mazo', () async {
      final bytes = await builder.build([
        export(
          card(id: 'c1', front: 'p1', back: 'r1'),
          deckPath: 'Sinapsis::Historia::Roma',
        ),
        export(
          card(id: 'c2', front: 'p2', back: 'r2'),
          deckPath: 'Sinapsis::Historia::Roma',
        ),
        export(
          card(id: 'c3', front: 'p3', back: 'r3'),
          deckPath: 'Sinapsis::Biología',
        ),
        export(card(id: 'c4', front: 'p4', back: 'r4')),
      ]);

      final db = await _openCollection(bytes);
      try {
        final col = db.select('SELECT * FROM col').single;
        final decks =
            jsonDecode(col['decks'] as String) as Map<String, dynamic>;
        final names = decks.values.map((d) => (d as Map)['name']).toSet();

        expect(
          names,
          containsAll([
            'Sinapsis::Historia::Roma',
            'Sinapsis::Biología',
            'Sinapsis::Sin tema',
          ]),
        );
        // Default + tres subdecks distintos: dos tarjetas comparten uno, no
        // cuenta doble.
        expect(decks, hasLength(4));

        final cards = db.select('SELECT * FROM cards');
        final roma = decks.entries
            .firstWhere(
              (e) => (e.value as Map)['name'] == 'Sinapsis::Historia::Roma',
            )
            .key;
        final romaDid = int.parse(roma);
        final romaCards = cards.where((c) => c['did'] == romaDid);
        expect(romaCards, hasLength(2));
      } finally {
        db.close();
      }
    });
  });

  test(
    'un mazo vacío igual arma un paquete válido, sin notas ni cartas',
    () async {
      final bytes = await builder.build(const []);

      final db = await _openCollection(bytes);
      try {
        expect(db.select('SELECT * FROM notes'), isEmpty);
        expect(db.select('SELECT * FROM cards'), isEmpty);
        // Sin tarjetas, sin ningún subdeck: solo el Default que Anki exige.
        final col = db.select('SELECT * FROM col').single;
        final decks =
            jsonDecode(col['decks'] as String) as Map<String, dynamic>;
        expect(decks, hasLength(1));
        expect((decks.values.single as Map)['name'], 'Default');
      } finally {
        db.close();
      }
    },
  );

  group('una tarjeta de opción múltiple (F20, commit 9)', () {
    Flashcard multipleChoiceCard({String id = 'mc1'}) => Flashcard(
      id: id,
      itemId: 'item-1',
      front: '¿Cuál es correcta?',
      back: '',
      kind: FlashcardKind.multipleChoice,
      dueAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

    test(
      'usa un modelo de nota propio, con la pregunta, la respuesta y los '
      'distractores reales en campos separados —nunca en Front/Back—',
      () async {
        final bytes = await builder.build([
          AnkiCardExport(
            card: multipleChoiceCard(),
            deckPath: 'Sinapsis::Sin tema',
            answer: 'La correcta',
            distractors: const ['Distractor uno', 'Distractor dos'],
          ),
        ]);

        final db = await _openCollection(bytes);
        try {
          final col = db.select('SELECT * FROM col').single;
          final models =
              jsonDecode(col['models'] as String) as Map<String, dynamic>;
          // Los modelos de la colección: el básico, este, el de huecos y el
          // de "escribí la respuesta" (F31).
          expect(models, hasLength(4));
          expect(
            models.values.map((m) => (m as Map)['name']),
            containsAll([
              'Sinapsis básico',
              'Sinapsis opción múltiple',
              'Sinapsis huecos',
              'Sinapsis escribí la respuesta',
            ]),
          );

          final note = db.select('SELECT * FROM notes').single;
          expect(
            note['flds'],
            // El separador de campos de Anki (U+001F) entre cada uno, sin
            // espacio: no es prosa, es el mismo carácter que ya usa el
            // básico Front/Back.
            // ignore: missing_whitespace_between_adjacent_strings
            '¿Cuál es correcta?\u001fLa correcta\u001fDistractor uno\u001f'
            'Distractor dos\u001f',
          );
        } finally {
          db.close();
        }
      },
    );

    test('conviven en el mismo mazo con tarjetas de otra forma, cada una con '
        'su propio modelo', () async {
      final bytes = await builder.build([
        export(card(id: 'c1', front: 'Pregunta libre', back: 'Respuesta')),
        AnkiCardExport(
          card: multipleChoiceCard(),
          deckPath: 'Sinapsis::Sin tema',
          answer: 'La correcta',
          distractors: const ['Distractor uno'],
        ),
      ]);

      final db = await _openCollection(bytes);
      try {
        final notes = db.select('SELECT * FROM notes ORDER BY rowid');
        expect(notes, hasLength(2));
        expect(notes.first['mid'], isNot(notes.last['mid']));
      } finally {
        db.close();
      }
    });
  });

  // Repasar sin depender de Anki (F31): lo que Sinapsis sabe de una tarjeta
  // —en qué etapa está, si está pausada, a qué grupo pertenece— sale al
  // `.apkg` con su equivalente de Anki, así seguir allá continúa donde quedó.
  group('el calendario nuevo en Anki (F31)', () {
    final reviewed = DateTime.now().subtract(const Duration(hours: 1));

    Future<Row> exportedCard(Flashcard card) async {
      final db = await _openCollection(await builder.build([export(card)]));
      try {
        return db.select('SELECT * FROM cards').single;
      } finally {
        db.close();
      }
    }

    test('una que se está aprendiendo va a la cola de aprendizaje, con la '
        'hora en que vuelve y los pasos que le faltan', () async {
      final backAt = DateTime.now().add(const Duration(minutes: 10));

      final exported = await exportedCard(
        card(
          id: 'c1',
          front: 'P',
          back: 'R',
          dueAt: backAt,
          lastReviewedAt: reviewed,
        ).copyWith(learningStep: 1),
      );

      expect(exported['type'], 1);
      expect(exported['queue'], 1);
      expect(exported['due'], backAt.millisecondsSinceEpoch ~/ 1000);
      expect(exported['left'], 1);
      expect(exported['ivl'], 0);
    });

    test('una que se olvidó y se reaprende es de tipo 3, con su intervalo y '
        'su facilidad', () async {
      final backAt = DateTime.now().add(const Duration(minutes: 10));

      final exported = await exportedCard(
        card(
          id: 'c1',
          front: 'P',
          back: 'R',
          intervalDays: 1,
          easeFactor: 1.7,
          dueAt: backAt,
          lastReviewedAt: reviewed,
        ).copyWith(learningStep: 0),
      );

      expect(exported['type'], 3);
      expect(exported['queue'], 1);
      expect(exported['ivl'], 1);
      expect(exported['factor'], 1700);
      expect(exported['due'], backAt.millisecondsSinceEpoch ~/ 1000);
    });

    test('una a la que le dijeron «De nuevo» antes de F31 (intervalo 1, cero '
        'repeticiones) sigue de repaso: no se reinicia como nueva', () async {
      final exported = await exportedCard(
        card(
          id: 'c1',
          front: 'P',
          back: 'R',
          intervalDays: 1,
          dueAt: DateTime.now().add(const Duration(days: 1)),
          lastReviewedAt: reviewed,
        ),
      );

      expect(exported['type'], 2);
      expect(exported['queue'], 2);
      expect(exported['ivl'], 1);
    });

    test('una pausada sale como suspendida, conservando el resto de su '
        'calendario', () async {
      for (final (label, base) in [
        ('nueva', card(id: 'n', front: 'P', back: 'R')),
        (
          'de repaso',
          card(
            id: 'r',
            front: 'P',
            back: 'R',
            repetitions: 3,
            intervalDays: 6,
            easeFactor: 2.2,
            dueAt: DateTime.now().add(const Duration(days: 4)),
            lastReviewedAt: reviewed,
          ),
        ),
        (
          'aprendiendo',
          card(
            id: 'a',
            front: 'P',
            back: 'R',
            dueAt: DateTime.now().add(const Duration(minutes: 5)),
            lastReviewedAt: reviewed,
          ).copyWith(learningStep: 0),
        ),
      ]) {
        final normal = await exportedCard(base);
        final suspended = await exportedCard(base.copyWith(suspended: true));

        expect(normal['queue'], isNot(-1), reason: label);
        expect(suspended['queue'], -1, reason: label);
        // Lo demás es igual: al reactivarla en Anki vuelve como estaba.
        expect(suspended['type'], normal['type'], reason: label);
        expect(suspended['ivl'], normal['ivl'], reason: label);
        expect(suspended['factor'], normal['factor'], reason: label);
        expect(suspended['due'], normal['due'], reason: label);
      }
    });

    test('una pospuesta hasta mañana sale como cualquier otra', () async {
      final base = card(id: 'c1', front: 'P', back: 'R');

      final buried = await exportedCard(
        base.copyWith(
          buriedUntil: DateTime.now().add(const Duration(hours: 6)),
        ),
      );

      expect(buried['queue'], 0);
    });
  });

  group('las formas nuevas en Anki (F31)', () {
    const clozeText = 'El {{c1::Imperio romano}} cayó en {{c2::476}}';

    Flashcard clozeCard(String id, int index, {String? groupId = 'g'}) =>
        Flashcard(
          id: id,
          itemId: 'item-1',
          front: clozeText,
          back: 'Fecha clásica',
          kind: FlashcardKind.cloze,
          clozeIndex: index,
          groupId: groupId,
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

    test('los huecos de un texto son UNA nota de tipo Cloze con una carta por '
        'hueco', () async {
      final bytes = await builder.build([
        export(clozeCard('h1', 1)),
        export(clozeCard('h2', 2)),
      ]);

      final db = await _openCollection(bytes);
      try {
        final notes = db.select('SELECT * FROM notes');
        final cards = db.select('SELECT * FROM cards ORDER BY ord');

        expect(notes, hasLength(1));
        expect(notes.single['flds'], '$clozeTextFecha clásica');
        expect(cards, hasLength(2));
        expect(cards.map((c) => c['ord']), [0, 1]);
        expect(cards.map((c) => c['nid']).toSet(), {notes.single['id']});

        final models =
            jsonDecode(
                  db.select('SELECT * FROM col').single['models'] as String,
                )
                as Map<String, dynamic>;
        final model = models['${notes.single['mid']}'] as Map;
        expect(model['name'], 'Sinapsis huecos');
        // `type: 1` es el modelo Cloze de Anki.
        expect(model['type'], 1);
        expect(
          ((model['tmpls'] as List).single as Map)['qfmt'],
          '{{cloze:Text}}',
        );
      } finally {
        db.close();
      }
    });

    test('dos textos con huecos son dos notas', () async {
      final bytes = await builder.build([
        export(clozeCard('a1', 1, groupId: 'g1')),
        export(clozeCard('a2', 2, groupId: 'g1')),
        export(clozeCard('b1', 1, groupId: 'g2')),
      ]);

      final db = await _openCollection(bytes);
      try {
        expect(db.select('SELECT * FROM notes'), hasLength(2));
        expect(db.select('SELECT * FROM cards'), hasLength(3));
      } finally {
        db.close();
      }
    });

    test('un hueco suelto, sin grupo, es su propia nota', () async {
      final bytes = await builder.build([
        export(clozeCard('h1', 2, groupId: null)),
      ]);

      final db = await _openCollection(bytes);
      try {
        expect(db.select('SELECT * FROM notes'), hasLength(1));
        expect(db.select('SELECT * FROM cards').single['ord'], 1);
      } finally {
        db.close();
      }
    });

    test(
      '«escribí la respuesta» usa su propio modelo, con {{type:Back}}',
      () async {
        final typed = Flashcard(
          id: 't1',
          itemId: 'item-1',
          front: '¿Año de la caída?',
          back: '476',
          kind: FlashcardKind.typedAnswer,
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        );
        final bytes = await builder.build([export(typed)]);

        final db = await _openCollection(bytes);
        try {
          final note = db.select('SELECT * FROM notes').single;
          expect(note['flds'], '¿Año de la caída?476');
          final models =
              jsonDecode(
                    db.select('SELECT * FROM col').single['models'] as String,
                  )
                  as Map<String, dynamic>;
          final model = models['${note['mid']}'] as Map;
          expect(model['name'], 'Sinapsis escribí la respuesta');
          expect(
            ((model['tmpls'] as List).single as Map)['qfmt'] as String,
            contains('{{type:Back}}'),
          );
        } finally {
          db.close();
        }
      },
    );

    test(
      'las dos direcciones de una pregunta salen como dos notas básicas',
      () async {
        Flashcard direction(String id, String front, String back) => Flashcard(
          id: id,
          itemId: 'item-1',
          front: front,
          back: back,
          groupId: 'g',
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        );
        final bytes = await builder.build([
          export(direction('ida', '¿Capital de Italia?', 'Roma')),
          export(direction('vuelta', 'Roma', '¿Capital de Italia?')),
        ]);

        final db = await _openCollection(bytes);
        try {
          final notes = db.select('SELECT * FROM notes ORDER BY rowid');
          expect(notes, hasLength(2));
          expect(notes.first['flds'], '¿Capital de Italia?Roma');
          expect(notes.last['flds'], 'Roma¿Capital de Italia?');
        } finally {
          db.close();
        }
      },
    );
  });
}

Future<sqlite3.Database> _openCollection(Uint8List apkgBytes) async {
  final archive = ZipDecoder().decodeBytes(apkgBytes);
  final entry = archive.files.firstWhere((f) => f.name == 'collection.anki2');

  final tempFile = File(
    p.join(
      Directory.systemTemp.path,
      'sinapsis-anki-test-${DateTime.now().microsecondsSinceEpoch}.anki2',
    ),
  );
  await tempFile.writeAsBytes(entry.content as List<int>);
  addTearDown(() async {
    if (tempFile.existsSync()) await tempFile.delete();
  });

  return sqlite3.sqlite3.open(tempFile.path);
}
