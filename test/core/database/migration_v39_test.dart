import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../generated_migrations/schema_v38.dart' as v38;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 38→39: repasar sin depender de Anki (F31, decisión
/// 69). `flashcards` gana cinco columnas —pausada, pospuesta, paso de
/// aprendizaje, grupo de hermanas y número de hueco— y `review_log` seis —de
/// qué etapa partió el repaso y lo necesario para deshacerlo—.
///
/// Aditiva: lo que está programado sigue igual. La única fila que se toca es la
/// etapa de los repasos viejos, para que los límites del día cuenten bien.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> insertCard(
    GeneratedDatabase db,
    String id, {
    int repetitions = 0,
    int intervalDays = 0,
    int? lastReviewedAt,
    double ease = 2.5,
    int dueAt = seconds,
  }) => db.customStatement(
    'INSERT INTO flashcards (id, item_id, front, back, ease_factor, '
    'interval_days, repetitions, due_at, created_at, last_reviewed_at) '
    "VALUES ('$id', 'nota', 'Pregunta $id', 'Respuesta $id', $ease, "
    '$intervalDays, $repetitions, $dueAt, $seconds, '
    '${lastReviewedAt ?? 'NULL'})',
  );

  Future<void> insertReview(
    GeneratedDatabase db,
    String id,
    String cardId, {
    required int intervalBefore,
    required int intervalAfter,
    String grade = 'good',
    int at = seconds,
  }) => db.customStatement(
    'INSERT INTO review_log (id, flashcard_id, reviewed_at, grade, quality, '
    'interval_before, interval_after, ease_before, ease_after, device_id) '
    "VALUES ('$id', '$cardId', $at, '$grade', 4, $intervalBefore, "
    "$intervalAfter, 2.5, 2.5, 'dispositivo-a')",
  );

  Future<void> insertNote(GeneratedDatabase db) async {
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('nota', 'Una nota', 'note', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('nota', "
      "'living', 'seed')",
    );
  }

  /// Una bóveda de antes de F31: una tarjeta nueva, una que se contestó una
  /// vez («De nuevo»: intervalo 1, repeticiones 0), una en repaso, y el
  /// historial de las dos que se contestaron.
  Future<void> seedVault(GeneratedDatabase db) async {
    await insertNote(db);
    await insertCard(db, 'nueva');
    await insertCard(
      db,
      'olvidada',
      intervalDays: 1,
      lastReviewedAt: seconds - 86400,
      dueAt: seconds + 86400,
    );
    await insertCard(
      db,
      'madura',
      repetitions: 4,
      intervalDays: 30,
      lastReviewedAt: seconds - 3 * 86400,
      ease: 2.2,
      dueAt: seconds + 27 * 86400,
    );
    // La historia de «madura»: su primera respuesta partió de intervalo 0.
    await insertReview(
      db,
      'r1',
      'madura',
      intervalBefore: 0,
      intervalAfter: 1,
      at: seconds - 30 * 86400,
    );
    await insertReview(
      db,
      'r2',
      'madura',
      intervalBefore: 1,
      intervalAfter: 6,
      at: seconds - 29 * 86400,
    );
    await insertReview(
      db,
      'r3',
      'olvidada',
      intervalBefore: 0,
      intervalAfter: 1,
      grade: 'again',
      at: seconds - 86400,
    );
  }

  final untouched = [
    ...VaultCounts.userDataTables,
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
    ...VaultCounts.referenceTables,
    ...VaultCounts.viewsAndTemplatesTables,
    ...VaultCounts.notebookTables,
    ...VaultCounts.habitTables,
    ...VaultCounts.quizTables,
    ...VaultCounts.aiTables,
    ...VaultCounts.aiFieldChangeTables,
    ...VaultCounts.contentTrashTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom38({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(38);
    final oldDb = v38.DatabaseAtV38(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v39', () async {
    await migrateFrom38();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(39));
  });

  test('lo programado sigue igual: ni pausada, ni pospuesta, ni en un paso, '
      'ni con hermanas', () async {
    final db = await migrateFrom38();

    final cards = {
      for (final card in await db.select(db.flashcards).get()) card.id: card,
    };
    expect(cards, hasLength(3));
    for (final card in cards.values) {
      expect(card.suspended, isFalse, reason: card.id);
      expect(card.buriedUntil, isNull, reason: card.id);
      expect(card.learningStep, isNull, reason: card.id);
      expect(card.groupId, isNull, reason: card.id);
      expect(card.clozeIndex, isNull, reason: card.id);
    }
    // El calendario, intacto.
    final mature = cards['madura']!;
    expect(mature.repetitions, 4);
    expect(mature.intervalDays, 30);
    expect(mature.easeFactor, 2.2);
    expect(
      mature.dueAt,
      DateTime.fromMillisecondsSinceEpoch((seconds + 27 * 86400) * 1000),
    );
  });

  test('el historial viejo: la primera respuesta de cada tarjeta es una '
      'nueva; las demás, repasos; y no se puede deshacer ninguna', () async {
    final db = await migrateFrom38();

    final logs = {
      for (final row in await db.select(db.reviewLogs).get()) row.id: row,
    };
    expect(logs['r1']!.phaseBefore, CardPhase.newCard);
    expect(logs['r2']!.phaseBefore, CardPhase.review);
    expect(logs['r3']!.phaseBefore, CardPhase.newCard);
    for (final row in logs.values) {
      expect(row.stepBefore, isNull);
      expect(row.stepAfter, isNull);
      // Sin esto no se puede deshacer: de antes de v39 no se guardó.
      expect(row.dueBefore, isNull);
      expect(row.lastReviewedBefore, isNull);
      expect(row.repetitionsBefore, isNull);
    }
  });

  test('las columnas nuevas aceptan lo nuevo', () async {
    final db = await migrateFrom38();

    await (db.update(db.flashcards)..where((f) => f.id.equals('nueva'))).write(
      FlashcardsCompanion(
        suspended: const Value(true),
        buriedUntil: Value(DateTime(2026, 10, 9, 4)),
        learningStep: const Value(1),
        groupId: const Value('grupo'),
        clozeIndex: const Value(2),
      ),
    );
    final card = await (db.select(
      db.flashcards,
    )..where((f) => f.id.equals('nueva'))).getSingle();

    expect(card.suspended, isTrue);
    expect(card.buriedUntil, DateTime(2026, 10, 9, 4));
    expect(card.learningStep, 1);
    expect(card.groupId, 'grupo');
    expect(card.clozeIndex, 2);
  });

  test('hay un índice por grupo, para encontrar a las hermanas', () async {
    final db = await migrateFrom38();

    final indexes = await db
        .customSelect("SELECT name FROM pragma_index_list('flashcards')")
        .get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('idx_flashcards_group'),
    );
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom38(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );

  test('desde una base más vieja, que pasa por las reconstrucciones de '
      'antes, llega igual', () async {
    final schema = await verifier.schemaAt(22);
    final oldDb = v22.DatabaseAtV22(schema.newConnection());
    await insertNote(oldDb);
    await insertCard(oldDb, 'vieja', repetitions: 2, intervalDays: 6);
    await insertReview(
      oldDb,
      'rv',
      'vieja',
      intervalBefore: 0,
      intervalAfter: 1,
    );
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);

    final card = await db.select(db.flashcards).getSingle();
    expect(card.repetitions, 2);
    expect(card.suspended, isFalse);
    expect(card.learningStep, isNull);
    final log = await db.select(db.reviewLogs).getSingle();
    expect(log.phaseBefore, CardPhase.newCard);
  });
}
