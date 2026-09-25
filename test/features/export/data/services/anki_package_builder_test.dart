import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/export/data/services/anki_package_builder.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
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
  }) => AnkiCardExport(card: card, deckPath: deckPath, provenance: provenance);

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
