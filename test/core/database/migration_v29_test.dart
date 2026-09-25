import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 28→29 —quizzes generados (F20)—: `flashcards`
/// gana `kind`, y `flashcard_options` nace vacía.
///
/// Una tarjeta de antes de v29 no tiene forma: tiene que llegar con
/// `kind = freeRecall`, el mismo valor que ya era —una pregunta y una
/// respuesta libres— antes de que existiera la columna. Se siembra la base
/// de v22 (mismo motivo que `migration_v28_test.dart`) y se migra de un
/// tirón hasta la versión actual.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v22.DatabaseAtV22 db) async {
    await db
        .into(db.item)
        .insert(
          v22.ItemCompanion.insert(
            id: 'fuente',
            title: 'Una fuente de antes',
            kind: 'source',
            state: 'processed',
            createdAt: seconds,
            updatedAt: seconds,
            deviceId: 'dispositivo-a',
          ),
        );
    await db
        .into(db.source)
        .insert(
          v22.SourceCompanion.insert(
            itemId: 'fuente',
            sourceType: 'webPage',
            capturedAt: seconds,
            contentHash: 'hash',
            processingStatus: 'done',
          ),
        );
    await db
        .into(db.flashcards)
        .insert(
          v22.FlashcardsCompanion.insert(
            id: 'tarjeta',
            itemId: 'fuente',
            front: '¿Qué es esto?',
            back: 'Una tarjeta de antes de F20.',
            dueAt: seconds,
            createdAt: seconds,
          ),
        );
  }

  /// Las tablas que la migración no debe cambiar de tamaño: todo lo que ya
  /// existía en v22.
  final untouched = [
    ...VaultCounts.userDataTables,
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
    ...VaultCounts.referenceTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom22() async {
    final schema = await verifier.schemaAt(22);
    final oldDb = v22.DatabaseAtV22(schema.newConnection());
    await seedVault(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v29', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(29));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final schema = await verifier.schemaAt(22);
    final oldDb = v22.DatabaseAtV22(schema.newConnection());
    await seedVault(oldDb);
    final before = await countsOf(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    final after = await countsOf(db);

    expect(after, before);
    // Y no es una comparación de ceros.
    expect(before['flashcards'], 1);
  });

  test('una tarjeta de antes de v29 llega con kind freeRecall, la forma que '
      'ya tenía', () async {
    final db = await migrateFrom22();

    final card = await db.select(db.flashcards).getSingle();
    expect(card.kind, FlashcardKind.freeRecall);
  });

  test('flashcard_options nace vacía', () async {
    final db = await migrateFrom22();

    expect(await db.select(db.flashcardOptions).get(), isEmpty);
  });

  test('se puede guardar una opción después de migrar', () async {
    final db = await migrateFrom22();

    await db
        .into(db.flashcardOptions)
        .insert(
          FlashcardOptionsCompanion.insert(
            id: 'opcion-1',
            flashcardId: 'tarjeta',
            content: 'Una opción cualquiera',
            isCorrect: true,
            position: 0,
          ),
        );

    final option = await db.select(db.flashcardOptions).getSingle();
    expect(option.flashcardId, 'tarjeta');
    expect(option.isCorrect, isTrue);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
