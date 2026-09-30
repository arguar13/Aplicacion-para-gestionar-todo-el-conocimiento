import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/data/repositories/text_anchor_relocator_impl.dart';

import '../../../../support/item_rows.dart';

/// Lo que apunta a posiciones del texto de un elemento —tarjetas, sus
/// opciones, notas extraídas— se lleva al texto nuevo cuando se vuelve a
/// extraer (F22), contra SQLite real.
void main() {
  late AppDatabase db;
  final now = DateTime(2026, 9, 30);

  // Como lo guardaba la app antes de F22: renglones y palabra cortada, unidos.
  const from = 'Uno. Las explicaciones van aparte. Dos.';
  const to = 'Primero:\nUno.\nLas ex-\nplicaciones van aparte.\nDos.';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await insertItemRows(
      db,
      id: 'libro',
      title: 'Libro',
      kind: SourceKind.document,
    );
    await insertItemRows(
      db,
      id: 'nota',
      title: 'Nota extraída',
      kind: SourceKind.manualNote,
    );
  });

  tearDown(() => db.close());

  (int, int) at(String excerpt) {
    final start = from.indexOf(excerpt);
    return (start, start + excerpt.length);
  }

  Future<void> card(String id, (int, int)? range) => db
      .into(db.flashcards)
      .insert(
        FlashcardsCompanion.insert(
          id: id,
          itemId: 'libro',
          front: '¿Qué?',
          back: 'Eso.',
          dueAt: now,
          createdAt: now,
          sourceCharStart: Value(range?.$1),
          sourceCharEnd: Value(range?.$2),
        ),
      );

  Future<FlashcardRow> cardRow(String id) =>
      (db.select(db.flashcards)..where((c) => c.id.equals(id))).getSingle();

  Future<List<Object?>> relocate() => TextAnchorRelocatorImpl(
    db,
  ).relocate(itemId: 'libro', renditionId: 'ninguna', from: from, to: to);

  test('una tarjeta que cita un fragmento lo sigue citando en el texto '
      'nuevo, aunque ahí esté cortado en renglones', () async {
    final (start, end) = at('Las explicaciones van aparte.');
    await card('c1', (start, end));

    await relocate();

    final row = await cardRow('c1');
    expect(
      to.substring(row.sourceCharStart!, row.sourceCharEnd),
      'Las ex-\nplicaciones van aparte.',
    );
  });

  test('si su fragmento ya no está, queda sin posición: se abre el '
      'elemento, no un lugar equivocado', () async {
    await card('c1', (0, 4));
    await db.customStatement(
      'UPDATE flashcards SET source_char_start = 5, source_char_end = 9 '
      "WHERE id = 'c1'",
    );

    await TextAnchorRelocatorImpl(db).relocate(
      itemId: 'libro',
      renditionId: 'ninguna',
      from: 'xxxxxNADAxxxx',
      to: to,
    );

    final row = await cardRow('c1');
    expect(row.sourceCharStart, isNull);
    expect(row.sourceCharEnd, isNull);
  });

  test('una nota extraída de un fragmento apunta a su lugar nuevo', () async {
    final (start, end) = at('Dos.');
    await db
        .into(db.relations)
        .insert(
          RelationsCompanion.insert(
            id: 'r1',
            fromItemId: 'nota',
            toItemId: 'libro',
            kind: RelationKind.extractedFrom,
            createdAt: now,
            sourceCharStart: Value(start),
            sourceCharEnd: Value(end),
          ),
        );

    await relocate();

    final row = await db.select(db.relations).getSingle();
    expect(to.substring(row.sourceCharStart!, row.sourceCharEnd), 'Dos.');
  });

  test('una tarjeta sin fragmento no se toca', () async {
    await card('c1', null);

    await relocate();

    expect((await cardRow('c1')).sourceCharStart, isNull);
  });
}
