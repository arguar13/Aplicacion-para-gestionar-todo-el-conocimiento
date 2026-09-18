import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/util/id_generator.dart';

const _migrationName = 'f2_vocabulary';

/// Migra cada `Tag` existente a un `PropertyValue` bajo la categoría de
/// sistema "Tema" —ya sembrada por `seedSystemPropertyCategories`—, y
/// cada fila de `ItemTags` a la `ItemPropertyValues` correspondiente.
///
/// `Tags`/`ItemTags` no se tocan ni se borran: siguen siendo la fuente
/// de verdad de `TagEditor` hasta que una sub-fase posterior migre
/// también la UI. Solo se llama desde `onUpgrade` —una bóveda nueva no
/// tiene etiquetas que migrar—.
///
/// El `PropertyValue` que resulta tiene un id NUEVO, no el mismo `id`
/// del `Tag`: las dos tablas quedan deliberadamente desacopladas en esta
/// sub-fase (sin escritura dual, ver la decisión de F1 sobre el mismo
/// trade-off sobre `item`/`source`/`note`), y reusar el id crearía una
/// coincidencia accidental entre dos tablas sin ninguna FK que la
/// respalde.
Future<void> migrateTagsToPropertyValues(
  AppDatabase db, {
  required IdGenerator ids,
  required AppLogger logger,
}) async {
  final tema = await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.lower().equals('tema'))).getSingle();

  final tags = await db.select(db.tags).get();

  for (final tag in tags) {
    try {
      final trimmed = tag.name.trim();
      if (trimmed.isEmpty) {
        await _reportIssue(
          db,
          ids: ids,
          itemId: tag.id,
          message: 'Etiqueta con nombre vacío, no migrada.',
        );
        continue;
      }

      final existingValue =
          await (db.select(db.propertyValues)..where(
                (v) =>
                    v.definitionId.equals(tema.id) &
                    v.value.lower().equals(trimmed.toLowerCase()),
              ))
              .getSingleOrNull();

      final valueId = existingValue?.id ?? ids.next();
      if (existingValue == null) {
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: valueId,
                definitionId: tema.id,
                value: trimmed,
                createdAt: tag.createdAt,
              ),
            );
      }

      final itemTags = await (db.select(
        db.itemTags,
      )..where((it) => it.tagId.equals(tag.id))).get();
      for (final itemTag in itemTags) {
        await db
            .into(db.itemPropertyValues)
            .insertOnConflictUpdate(
              ItemPropertyValuesCompanion.insert(
                itemId: itemTag.itemId,
                propertyValueId: valueId,
              ),
            );
      }
      // Ver `_unexpected` en los repositorios: un `TypeError` es `Error`,
      // no `Exception`, y dejarlo escapar aquí abortaría la migración
      // entera por una sola etiqueta con datos inesperados.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      logger.error(
        'migrateTagsToPropertyValues: no se pudo migrar la etiqueta '
        '${tag.id}',
        e,
        stackTrace,
      );
      await _reportIssue(db, ids: ids, itemId: tag.id, message: e.toString());
    }
  }
}

Future<void> _reportIssue(
  AppDatabase db, {
  required IdGenerator ids,
  required String itemId,
  required String message,
}) {
  return db
      .into(db.migrationIssues)
      .insert(
        MigrationIssuesCompanion.insert(
          id: ids.next(),
          migration: _migrationName,
          itemId: itemId,
          stage: 'migrate_tags',
          message: message,
          createdAt: DateTime.now(),
        ),
      );
}
