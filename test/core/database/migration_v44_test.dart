import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v43.dart' as v43;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 43→44: los hechos fechados dentro de un documento
/// (F40). Una tabla nueva y vacía (`dated_events`) y dos columnas que en todo
/// lo de antes dicen «ninguno»: `ai_runs.dates_created` y
/// `content_trash.dated_events`. «Fecha del hecho» no se toca.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v43.DatabaseAtV43 db) async {
    // El esquema v43 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('libro', 'Un libro', 'source', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'libro', 'plainText', 'Texto.', 1, "
      '$seconds)',
    );
    await db.customStatement(
      'INSERT INTO ai_runs (id, item_id, model, started_at, finished_at, '
      'relations_created, scope) VALUES '
      "('pasada', 'libro', 'gemma4E4b', $seconds, ${seconds + 60}, 2, "
      "'organize')",
    );
    await db.customStatement(
      'INSERT INTO content_trash (id, item_id, kind, rendition_id, '
      'rendition_kind, content, is_primary, rendition_created_at, '
      "trashed_at) VALUES ('papelera', 'libro', 'text', 'viejo', "
      "'plainText', 'Otro texto.', 0, $seconds, $seconds)",
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom43({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(43);
    final oldDb = v43.DatabaseAtV43(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  DatedEventsCompanion event(String id, {DateTime? at}) {
    final now = at ?? DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return DatedEventsCompanion.insert(
      id: id,
      itemId: 'libro',
      title: 'Publica El origen de las especies',
      dateFromYear: 1859,
      dateFromMonth: 1,
      dateFromDay: 1,
      datePrecision: DatePrecision.year,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('la migración llega a la forma del snapshot de v44', () async {
    await migrateFrom43();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(44));
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(44));
  });

  test('nace vacía: ningún hecho fechado, y lo de antes sigue', () async {
    final db = await migrateFrom43();

    expect(await db.select(db.datedEvents).get(), isEmpty);
    final run = await db.select(db.aiRuns).getSingle();
    expect(run.datesCreated, 0);
    expect(run.model, 'gemma4E4b');
    expect(run.relationsCreated, 2);
    final trashed = await db.select(db.trashedContents).getSingle();
    expect(trashed.datedEvents, isNull);
    expect(trashed.content, 'Otro texto.');
  });

  test('un hecho nuevo se guarda con su fecha, su fin y su cita', () async {
    final db = await migrateFrom43();
    final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.datedEvents)
        .insert(
          event('guerra').copyWith(
            title: const Value('La Gran Guerra'),
            dateFromYear: const Value(1914),
            dateEndYear: const Value(1918),
            dateEndMonth: const Value(1),
            dateEndDay: const Value(1),
            dateEndPrecision: const Value(DatePrecision.year),
            renditionId: const Value('texto'),
            startOffset: const Value(0),
            endOffset: const Value(5),
            excerpt: const Value('Texto'),
            origin: const Value(ContentOrigin.ai),
            aiRunId: const Value('pasada'),
            updatedAt: Value(at),
          ),
        );

    final row = await db.select(db.datedEvents).getSingle();
    expect(row.dateFromYear, 1914);
    expect(row.dateEndYear, 1918);
    expect(row.dateIsCirca, isFalse);
    expect(row.origin, ContentOrigin.ai);
    expect(row.aiRunId, 'pasada');
  });

  test('la base hace cumplir las invariantes del hecho', () async {
    final db = await migrateFrom43();

    Future<void> insertWith(
      DatedEventsCompanion Function(DatedEventsCompanion) f,
    ) => db.into(db.datedEvents).insert(f(event('x')));

    // El fin viene entero o no viene.
    await expectLater(
      insertWith((e) => e.copyWith(dateEndYear: const Value(1918))),
      throwsA(anything),
    );
    // La posición de la cita viene entera, es un tramo y es de un texto.
    await expectLater(
      insertWith((e) => e.copyWith(startOffset: const Value(3))),
      throwsA(anything),
    );
    await expectLater(
      insertWith(
        (e) => e.copyWith(
          startOffset: const Value(5),
          endOffset: const Value(5),
          renditionId: const Value('texto'),
        ),
      ),
      throwsA(anything),
    );
    await expectLater(
      insertWith(
        (e) =>
            e.copyWith(startOffset: const Value(1), endOffset: const Value(5)),
      ),
      throwsA(anything),
    );
    // Un mes que no existe, un título vacío y un hecho de la persona con
    // pasada de la IA.
    await expectLater(
      insertWith((e) => e.copyWith(dateFromMonth: const Value(13))),
      throwsA(anything),
    );
    await expectLater(
      insertWith((e) => e.copyWith(title: const Value('  '))),
      throwsA(anything),
    );
    await expectLater(
      insertWith((e) => e.copyWith(aiRunId: const Value('pasada'))),
      throwsA(anything),
    );
    expect(await db.select(db.datedEvents).get(), isEmpty);
  });

  test('se va con su elemento, y con su texto si lo cita', () async {
    final db = await migrateFrom43();
    await db
        .into(db.datedEvents)
        .insert(
          event('citado').copyWith(
            renditionId: const Value('texto'),
            startOffset: const Value(0),
            endOffset: const Value(5),
            excerpt: const Value('Texto'),
          ),
        );
    await db.into(db.datedEvents).insert(event('suelto'));

    await (db.delete(db.renditions)..where((r) => r.id.equals('texto'))).go();
    expect(
      [for (final e in await db.select(db.datedEvents).get()) e.id],
      ['suelto'],
    );

    await (db.delete(
      db.knowledgeEntries,
    )..where((e) => e.id.equals('libro'))).go();
    expect(await db.select(db.datedEvents).get(), isEmpty);
  });

  test('si se borra su pasada, el hecho queda sin ella', () async {
    final db = await migrateFrom43();
    await db
        .into(db.datedEvents)
        .insert(
          event('ia').copyWith(
            origin: const Value(ContentOrigin.ai),
            aiRunId: const Value('pasada'),
          ),
        );

    await db.customStatement('DELETE FROM ai_runs');

    final row = await db.select(db.datedEvents).getSingle();
    expect(row.origin, ContentOrigin.ai);
    expect(row.aiRunId, isNull);
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom43(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
