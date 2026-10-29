import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v47.dart' as v47;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 47→48: «Lo creado» de Estudiar (F43) —la tabla
/// `study_creations` y sus índices—. Solo agrega.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  Future<void> seedVault(v47.DatabaseAtV47 db) async {
    for (final (id, kind) in [('fuente', 'source'), ('proc', 'note')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Éxodo', '$kind', 'triaged', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('proc', "
      "'processed', 'seed')",
    );
    await db.customStatement(
      'INSERT INTO processed_documents (item_id, source_item_id, source_kind, '
      "created_at) VALUES ('proc', 'fuente', 'book', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO flashcards (id, item_id, front, back, ease_factor, '
      'interval_days, repetitions, due_at, created_at) VALUES '
      "('tarjeta', 'proc', '¿Quién?', 'Moisés', 2.5, 0, 0, $seconds, "
      '$seconds)',
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
    ...VaultCounts.studyTables,
    ...VaultCounts.itemSpaceTables,
    ...VaultCounts.datedEventTables,
    ...VaultCounts.processedTables,
    ...VaultCounts.processedImageTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom47({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(47);
    final oldDb = v47.DatabaseAtV47(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  StudyCreationsCompanion creation(String id, {String status = 'ready'}) {
    final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return StudyCreationsCompanion.insert(
      id: id,
      kind: 'mind_map',
      scopeKind: 'document',
      scopeId: const Value('proc'),
      languageCode: 'es',
      status: status,
      createdAt: at,
      updatedAt: at,
    );
  }

  test('la migración llega a la forma del snapshot de v48', () async {
    await migrateFrom47();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(48));
  });

  test('lo nuevo nace vacío, con sus tres índices', () async {
    final db = await migrateFrom47();

    expect(await db.select(db.studyCreations).get(), isEmpty);
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'study_creations' AND name LIKE 'idx_%' "
          'ORDER BY name',
        )
        .get();
    expect(
      [for (final row in indexes) row.read<String>('name')],
      [
        'idx_study_creations_created',
        'idx_study_creations_scope',
        'idx_study_creations_status',
      ],
    );
  });

  test('una creación guarda sus valores por defecto, y la base hace cumplir '
      'su estado y su recorte', () async {
    final db = await migrateFrom47();

    await db.into(db.studyCreations).insert(creation('lista'));
    final row = await db.select(db.studyCreations).getSingle();
    expect(row.sourceIdsJson, '[]');
    expect(row.optionsJson, '{}');
    expect(row.contentJson, isNull);
    expect(row.contentVersion, 1);
    expect(row.runNow, isFalse);
    expect(row.attempts, 0);
    expect(row.deletedAt, isNull);

    // Un estado que no existe.
    await expectLater(
      db.into(db.studyCreations).insert(creation('rara', status: 'raro')),
      throwsA(anything),
    );
    // Fallida sin motivo, o con motivo sin haber fallado.
    await expectLater(
      db.into(db.studyCreations).insert(creation('sin', status: 'failed')),
      throwsA(anything),
    );
    await expectLater(
      db
          .into(db.studyCreations)
          .insert(creation('con').copyWith(failure: const Value('error'))),
      throwsA(anything),
    );
    // «Todo» no apunta a nada, y lo demás sí.
    await expectLater(
      db
          .into(db.studyCreations)
          .insert(creation('todo').copyWith(scopeKind: const Value('all'))),
      throwsA(anything),
    );
    await expectLater(
      db
          .into(db.studyCreations)
          .insert(creation('nada').copyWith(scopeId: const Value(null))),
      throwsA(anything),
    );
    // Un avance fuera de 0..1.
    await expectLater(
      db
          .into(db.studyCreations)
          .insert(creation('mucho').copyWith(progress: const Value(1.5))),
      throwsA(anything),
    );
  });

  test('borrar el documento procesado no se lleva la creación', () async {
    final db = await migrateFrom47();
    await db
        .into(db.studyCreations)
        .insert(
          creation('mapa').copyWith(sourceIdsJson: const Value('["proc"]')),
        );

    await db.customStatement("DELETE FROM item WHERE id = 'proc'");

    final row = await db.select(db.studyCreations).getSingle();
    expect(row.id, 'mapa');
    expect(row.sourceIdsJson, '["proc"]');
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom47(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
