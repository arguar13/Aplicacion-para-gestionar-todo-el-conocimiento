import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/ai_rejection_kind.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v33.dart' as v33;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 33→34 —la IA organiza sola, y todo se puede
/// corregir (F27)—: quién hizo cada vínculo, tarjeta y propiedad, la pasada de
/// la IA que lo hizo y la memoria de lo que «no era». Aditiva: todo lo de
/// antes queda como de la persona, y ninguna fila cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v33.DatabaseAtV33 db) async {
    // El esquema v33 generado no trae clases de datos: SQL directo.
    for (final id in ['un-video', 'una-nota']) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', '$id', 'source', 'processed', $seconds, "
        "$seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      'INSERT INTO relations (id, from_item_id, to_item_id, kind, note, '
      "created_at) VALUES ('vinculo', 'una-nota', 'un-video', 'relatedTo', "
      "'Hablan de lo mismo', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO flashcards (id, item_id, front, back, due_at, created_at) '
      "VALUES ('tarjeta', 'un-video', '¿Qué?', 'Esto', $seconds, $seconds)",
    );
    await db.customStatement(
      'INSERT INTO property_definitions (id, name, created_at) '
      "VALUES ('tema', 'Tema', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO property_values (id, definition_id, value, created_at) '
      "VALUES ('roma', 'tema', 'Roma', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO item_property_values (item_id, property_value_id, origin) '
      "VALUES ('un-video', 'roma', 'suggestedAccepted')",
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom33({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(33);
    final oldDb = v33.DatabaseAtV33(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v34', () async {
    await migrateFrom33();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(34));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final before = <String, int>{};
    final db = await migrateFrom33(countsBefore: before);

    expect(await countsOf(db), before);
    expect(before['relations'], 1);
    expect(before['flashcards'], 1);
    expect(before['item_property_values'], 1);
  });

  test('lo de antes queda como de la persona, sin pasada de la IA', () async {
    final db = await migrateFrom33();

    final relation = await db.select(db.relations).getSingle();
    expect(relation.origin, ContentOrigin.user);
    expect(relation.confidence, isNull);
    expect(relation.aiRunId, isNull);
    expect(relation.note, 'Hablan de lo mismo');

    final card = await db.select(db.flashcards).getSingle();
    expect(card.origin, ContentOrigin.user);
    expect(card.aiRunId, isNull);
    expect(card.front, '¿Qué?');

    final assignment = await db.select(db.itemPropertyValues).getSingle();
    expect(assignment.origin, ItemPropertyOrigin.suggestedAccepted);
    expect(assignment.aiRunId, isNull);
  });

  test('las tablas nuevas arrancan vacías y aceptan una pasada y un '
      '«no era»', () async {
    final db = await migrateFrom33();
    expect(await db.select(db.aiRuns).get(), isEmpty);
    expect(await db.select(db.aiRejections).get(), isEmpty);

    await db.customStatement('PRAGMA foreign_keys = ON');
    await db
        .into(db.aiRuns)
        .insert(
          AiRunsCompanion.insert(
            id: 'pasada',
            itemId: 'un-video',
            startedAt: DateTime(2026, 10),
          ),
        );
    await (db.update(db.relations)..where((r) => r.id.equals('vinculo'))).write(
      const RelationsCompanion(
        origin: Value(ContentOrigin.ai),
        aiRunId: Value('pasada'),
      ),
    );
    await db
        .into(db.aiRejections)
        .insert(
          AiRejectionsCompanion.insert(
            id: 'no-era',
            kind: AiRejectionKind.flashcard,
            itemId: 'un-video',
            fingerprint: 'qué',
            createdAt: DateTime(2026, 10),
          ),
        );

    expect((await db.select(db.relations).getSingle()).aiRunId, 'pasada');
    expect(await db.select(db.aiRejections).get(), hasLength(1));
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom33();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
