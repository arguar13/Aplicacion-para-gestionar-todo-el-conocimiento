import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 24→25 —el chat se acota a un cuaderno (F16)—:
/// una columna nueva y nula en `Conversations`.
///
/// Es aditiva: una columna, ninguna fila tocada. Se siembra la base de v22
/// (con `schemaAt(22)` y las clases generadas de esa versión —v23 en
/// adelante ya no traen Companion utilizable para sembrar a mano, mismo
/// motivo que `migration_v23_test.dart`—) y se migra de un tirón hasta la
/// versión actual, pasando por v23 y v24. Lo que se comprueba es que no
/// cambia ninguna fila de lo que ya existía en v22 y que las conversaciones
/// de antes de la migración quedan sin cuaderno —`null` es "toda la
/// bóveda", lo mismo que significaba antes de que la columna existiera—.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v22.DatabaseAtV22 db) async {
    await db
        .into(db.item)
        .insert(
          v22.ItemCompanion.insert(
            id: 'art',
            title: 'Un artículo',
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
            itemId: 'art',
            sourceType: 'webPage',
            capturedAt: seconds,
            contentHash: '',
            processingStatus: 'done',
          ),
        );
    await db
        .into(db.conversations)
        .insert(
          v22.ConversationsCompanion.insert(
            id: 'conv-1',
            mode: 'vault',
            createdAt: seconds,
            updatedAt: seconds,
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

  test('la migración llega a la forma del snapshot de v25', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(25));
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
    expect(before['item'], 1);
    expect(before['conversations'], 1);
  });

  test(
    'una conversación de antes de la migración queda sin cuaderno',
    () async {
      final db = await migrateFrom22();

      final conversation = await (db.select(
        db.conversations,
      )..where((c) => c.id.equals('conv-1'))).getSingle();

      expect(conversation.notebookId, isNull);
    },
  );

  test('una conversación nueva puede acotarse a un cuaderno', () async {
    final db = await migrateFrom22();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.notebooks)
        .insert(
          NotebooksCompanion.insert(
            id: 'nb-1',
            name: 'Tesis',
            mode: NotebookMode.manual,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'conv-2',
            mode: ChatConversationMode.vault,
            createdAt: now,
            updatedAt: now,
            notebookId: const Value('nb-1'),
          ),
        );

    final conversation = await (db.select(
      db.conversations,
    )..where((c) => c.id.equals('conv-2'))).getSingle();
    expect(conversation.notebookId, 'nb-1');
  });

  test(
    'borrar el cuaderno deja la conversación sin acotar, no la borra',
    () async {
      final db = await migrateFrom22();
      final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

      await db
          .into(db.notebooks)
          .insert(
            NotebooksCompanion.insert(
              id: 'nb-1',
              name: 'Tesis',
              mode: NotebookMode.manual,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: 'conv-2',
              mode: ChatConversationMode.vault,
              createdAt: now,
              updatedAt: now,
              notebookId: const Value('nb-1'),
            ),
          );

      await (db.delete(db.notebooks)..where((n) => n.id.equals('nb-1'))).go();

      final conversation = await (db.select(
        db.conversations,
      )..where((c) => c.id.equals('conv-2'))).getSingle();
      expect(conversation.notebookId, isNull);
    },
  );

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
