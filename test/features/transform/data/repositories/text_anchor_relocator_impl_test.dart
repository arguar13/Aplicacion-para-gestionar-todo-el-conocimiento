import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
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

  group('lo resaltado para estudiar (F36)', () {
    setUp(() async {
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'texto',
              itemId: 'libro',
              kind: RenditionKind.plainText,
              content: const Value(from),
              isPrimary: true,
              createdAt: now,
            ),
          );
    });

    Future<void> mark(String id, String excerpt) {
      final (start, end) = at(excerpt);
      return db
          .into(db.studyMarks)
          .insert(
            StudyMarksCompanion.insert(
              id: id,
              renditionId: 'texto',
              kind: StudyMarkKind.summary,
              origin: ContentOrigin.ai,
              startOffset: start,
              endOffset: end,
              excerpt: excerpt,
              createdAt: now,
            ),
          );
    }

    Future<void> analyzed(int until, {bool complete = false}) => db
        .into(db.studyAnalyses)
        .insert(
          StudyAnalysesCompanion.insert(
            renditionId: 'texto',
            analyzedUntil: until,
            completedAt: Value(complete ? now : null),
            updatedAt: now,
          ),
        );

    Future<void> relocateTo(String text) => TextAnchorRelocatorImpl(
      db,
    ).relocate(itemId: 'libro', renditionId: 'texto', from: from, to: text);

    test('una oración marcada sigue marcada en su lugar nuevo', () async {
      await mark('m1', 'Las explicaciones van aparte.');

      await relocateTo(to);

      final row = await db.select(db.studyMarks).getSingle();
      expect(
        to.substring(row.startOffset, row.endOffset),
        'Las ex-\nplicaciones van aparte.',
      );
    });

    test('la que ya no está en el texto nuevo se va', () async {
      await mark('m1', 'Las explicaciones van aparte.');
      await mark('m2', 'Dos.');

      await relocateTo('Uno. Otra cosa. Dos.');

      final rows = await db.select(db.studyMarks).get();
      expect(rows.map((r) => r.id), ['m2']);
    });

    test(
      'hasta dónde se analizó va al final de lo mismo en el texto nuevo',
      () async {
        final (_, end) = at('Las explicaciones van aparte.');
        await analyzed(end);

        await relocateTo(to);

        final row = await db.select(db.studyAnalyses).getSingle();
        expect(to.substring(0, row.analyzedUntil).endsWith('aparte.'), isTrue);
        expect(row.completedAt, isNull);
      },
    );

    test(
      'terminado sigue terminado si el texto nuevo no agrega nada al final',
      () async {
        await analyzed(from.length, complete: true);

        await relocateTo(to);

        final row = await db.select(db.studyAnalyses).getSingle();
        expect(row.analyzedUntil, to.length);
        expect(row.completedAt, isNotNull);
      },
    );

    test('si se agregó texto al final, falta analizarlo', () async {
      await analyzed(from.length, complete: true);

      await relocateTo('$to\nUn capítulo nuevo.');

      final row = await db.select(db.studyAnalyses).getSingle();
      expect(row.analyzedUntil, to.length);
      expect(row.completedAt, isNull);
    });

    test('si no se encuentra hasta dónde llegaba, vuelve a empezar', () async {
      await analyzed(from.length, complete: true);

      await relocateTo('Un texto que no tiene nada que ver.');

      final row = await db.select(db.studyAnalyses).getSingle();
      expect(row.analyzedUntil, 0);
      expect(row.completedAt, isNull);
    });
  });

  group('los hechos fechados (F40)', () {
    setUp(() async {
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'texto',
              itemId: 'libro',
              kind: RenditionKind.plainText,
              content: const Value(from),
              isPrimary: true,
              createdAt: now,
            ),
          );
    });

    Future<void> fact(String id, {String? excerpt, String? rendition}) {
      final range = excerpt == null ? null : at(excerpt);
      return db
          .into(db.datedEvents)
          .insert(
            DatedEventsCompanion.insert(
              id: id,
              itemId: 'libro',
              renditionId: Value(
                rendition ?? (excerpt == null ? null : 'texto'),
              ),
              title: 'Un hecho',
              dateFromYear: 1859,
              dateFromMonth: 1,
              dateFromDay: 1,
              datePrecision: DatePrecision.year,
              startOffset: Value(range?.$1),
              endOffset: Value(range?.$2),
              excerpt: Value(excerpt),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    Future<void> relocateTo(String text) => TextAnchorRelocatorImpl(
      db,
    ).relocate(itemId: 'libro', renditionId: 'texto', from: from, to: text);

    Future<DatedEventRow> row(String id) =>
        (db.select(db.datedEvents)..where((e) => e.id.equals(id))).getSingle();

    test('la cita de un hecho sigue en su lugar nuevo', () async {
      await fact('h1', excerpt: 'Las explicaciones van aparte.');

      await relocateTo(to);

      final moved = await row('h1');
      expect(
        to.substring(moved.startOffset!, moved.endOffset),
        'Las ex-\nplicaciones van aparte.',
      );
      expect(moved.renditionId, 'texto');
    });

    test('si la cita ya no está, el hecho se queda sin posición pero con su '
        'fecha, su fragmento y su texto', () async {
      await fact('h1', excerpt: 'Las explicaciones van aparte.');

      await relocateTo('Uno. Otra cosa. Dos.');

      final kept = await row('h1');
      expect(kept.startOffset, isNull);
      expect(kept.endOffset, isNull);
      expect(kept.excerpt, 'Las explicaciones van aparte.');
      expect(kept.dateFromYear, 1859);
      expect(kept.renditionId, 'texto');
    });

    test('un hecho sin cita, o de otro texto, no se toca', () async {
      await fact('suelto');
      // Del texto, pero sin posición (ya se había perdido): tampoco se toca.
      await fact('sin-posicion', rendition: 'texto');
      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'otro',
              itemId: 'libro',
              kind: RenditionKind.plainText,
              content: const Value(from),
              isPrimary: false,
              createdAt: now,
            ),
          );
      await fact('ajeno', excerpt: 'Dos.', rendition: 'otro');
      final loose = await row('suelto');
      final unplaced = await row('sin-posicion');
      final other = await row('ajeno');

      await relocateTo('Un texto que no tiene nada que ver.');

      expect(await row('suelto'), loose);
      expect(await row('sin-posicion'), unplaced);
      expect(await row('ajeno'), other);
    });
  });
}
