import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/export/data/services/anki_package_builder.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// No hay forma de probar un import de verdad contra la aplicación Anki en
/// este entorno; lo que sí se puede probar —y lo que se prueba acá— es que
/// el `.apkg` generado es un `.zip` válido con una base SQLite adentro que
/// respeta el esquema legado de Anki (tablas, columnas y JSON de
/// configuración), y que el estado SM-2 de cada tarjeta se traduce a los
/// campos de repaso que Anki espera.
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

  test(
    'arma un .zip con la base de Anki y el manifiesto de medios adentro',
    () async {
      final bytes = await builder.build([
        card(id: 'c1', front: '¿Capital de Francia?', back: 'París'),
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
      card(id: 'c1', front: 'Pregunta 1', back: 'Respuesta 1'),
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
    ]);

    final db = await _openCollection(bytes);
    try {
      final notes = db.select('SELECT * FROM notes ORDER BY rowid');
      final cards = db.select('SELECT * FROM cards ORDER BY rowid');

      expect(notes, hasLength(2));
      expect(cards, hasLength(2));
      expect(notes.first['flds'], 'Pregunta 1Respuesta 1');
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
      'configuración, con el mazo "Sinapsis" entre los mazos', () async {
    final bytes = await builder.build([
      card(id: 'c1', front: 'Pregunta', back: 'Respuesta'),
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
      expect(decks.values.any((d) => (d as Map)['name'] == 'Sinapsis'), isTrue);
      expect(dconf, isNotEmpty);
      expect(conf['curDeck'], isNotNull);
    } finally {
      db.close();
    }
  });

  test(
    'un mazo vacío igual arma un paquete válido, sin notas ni cartas',
    () async {
      final bytes = await builder.build(const []);

      final db = await _openCollection(bytes);
      try {
        expect(db.select('SELECT * FROM notes'), isEmpty);
        expect(db.select('SELECT * FROM cards'), isEmpty);
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
