import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/mirror_unmirrored_items.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Las columnas que cuelgan de un elemento, por tabla y nombre SQL. Son las
/// claves foráneas que v18 pasa de `items` a `item`.
const _referencesToItem = <(String table, String column)>[
  ('renditions', 'item_id'),
  ('relations', 'from_item_id'),
  ('relations', 'to_item_id'),
  ('flashcards', 'item_id'),
  ('inline_link', 'from_item_id'),
  ('inline_link', 'to_item_id'),
  ('item_property_values', 'item_id'),
];

/// Qué encuentra el paso v18 antes de re-apuntar las claves, calculado SIN
/// escribir nada: el dry-run.
///
/// Desde F10 todas las lecturas salen del modelo nuevo: un elemento de `items`
/// sin su fila en `item` sería invisible en toda la app. Hasta acá nada lo
/// comprobaba —el espejo lo escribía `save()` en la misma transacción y se
/// daba por bueno—; v18 lo exige antes de seguir, porque además pasa a
/// apuntar las formas, los vínculos y el resto a `item`, y una fila que apunte
/// a un elemento que no está ahí es un huérfano.
class ItemReferenceRepointPlan {
  const ItemReferenceRepointPlan({
    required this.items,
    required this.entries,
    required this.unmirrored,
    required this.ghosts,
    required this.orphans,
  });

  /// Filas de `items` (el modelo viejo).
  final int items;

  /// Filas de `item` (el modelo nuevo).
  final int entries;

  /// Ids de `items` que no tienen su fila en `item`.
  final List<String> unmirrored;

  /// Ids de `item` que no tienen fila en `items`: no hay de dónde salió, y
  /// nada del modelo viejo los reclama. Se informan y no se tocan.
  final List<String> ghosts;

  /// Por cada `tabla.columna`, cuántas filas apuntan a un elemento que no
  /// está en `item`.
  final Map<String, int> orphans;

  /// Nada por corregir: el espejo está completo y ninguna fila apunta a un
  /// elemento que falte.
  bool get canProceed =>
      unmirrored.isEmpty && orphans.values.every((rows) => rows == 0);

  String summary() {
    final orphaned = [
      for (final e in orphans.entries)
        if (e.value > 0) '${e.key}=${e.value}',
    ];
    return 'Referencias a item: $items elementos en items y $entries en item; '
        '${unmirrored.length} sin su fila en item, ${ghosts.length} filas de '
        'item sin su fila en items; huérfanos: '
        '${orphaned.isEmpty ? 'ninguno' : orphaned.join(', ')}.';
  }
}

/// Calcula el estado de las referencias, sin escribir NADA.
Future<ItemReferenceRepointPlan> planItemReferenceRepoint(
  AppDatabase db,
) async {
  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  Future<List<String>> ids(String sql) async => [
    for (final row in await db.customSelect(sql).get()) row.read<String>('id'),
  ];

  final orphans = <String, int>{};
  for (final (table, column) in _referencesToItem) {
    orphans['$table.$column'] = await count(
      'SELECT COUNT(*) AS n FROM $table '
      'WHERE $column IS NOT NULL AND $column NOT IN (SELECT id FROM item)',
    );
  }

  return ItemReferenceRepointPlan(
    items: await count('SELECT COUNT(*) AS n FROM items'),
    entries: await count('SELECT COUNT(*) AS n FROM item'),
    unmirrored: await ids(
      'SELECT id FROM items WHERE id NOT IN (SELECT id FROM item) ORDER BY id',
    ),
    ghosts: await ids(
      'SELECT id FROM item WHERE id NOT IN (SELECT id FROM items) ORDER BY id',
    ),
    orphans: orphans,
  );
}

/// El paso de v18 que apunta las claves foráneas a `item`.
///
/// Reconstruye `renditions`, `relations`, `flashcards`, `inline_link` y
/// `item_property_values` con su definición de hoy —sus claves apuntan a
/// `item`— y deja `items` de lado: SQLite no permite cambiar una clave foránea
/// en su lugar, hay que rehacer la tabla.
///
/// Antes de tocar nada calcula el plan y lo informa; si falta el espejo de
/// algún elemento lo completa con el mismo catch-up de siempre
/// (`mirrorUnmirroredItems`) y vuelve a mirar. Si después de eso queda algún
/// elemento sin su fila, o alguna fila apuntando a un elemento que no está,
/// lanza: la migración entera revierte y la copia previa de la base sigue
/// intacta. Nunca sigue "a ver qué pasa". Al terminar exige que
/// `PRAGMA foreign_key_check` no encuentre ninguna violación.
///
/// Las filas que hay antes y después las compara quien llama
/// (`captureVaultCounts`): este paso no cambia cuántas hay.
Future<ItemReferenceRepointPlan> repointItemReferences(
  AppDatabase db,
  Migrator migrator, {
  required IdGenerator ids,
  required AppLogger logger,
}) async {
  var plan = await planItemReferenceRepoint(db);
  logger.info(plan.summary());

  if (plan.unmirrored.isNotEmpty) {
    await mirrorUnmirroredItems(db);
    plan = await planItemReferenceRepoint(db);
    logger.info('Con el espejo completado: ${plan.summary()}');
  }
  if (!plan.canProceed) {
    throw StateError(
      'La migración a v18 no puede apuntar las claves a item: '
      '${plan.summary()} No se modificó nada.',
    );
  }

  if (plan.ghosts.isNotEmpty) {
    logger.warning(
      '${plan.ghosts.length} filas de item no tienen fila en items; se dejan '
      'como están y quedan en MigrationIssues.',
    );
    for (final id in plan.ghosts) {
      await db
          .into(db.migrationIssues)
          .insert(
            MigrationIssuesCompanion.insert(
              id: ids.next(),
              migration: 'f10_v18',
              itemId: id,
              stage: 'item_without_legacy_row',
              message:
                  'Una fila de item sin su fila en items: el modelo viejo no '
                  'la reclama y no se toca.',
              createdAt: DateTime.now(),
            ),
          );
    }
  }

  await migrator.alterTable(TableMigration(db.renditions));
  await migrator.alterTable(TableMigration(db.relations));
  // `alterTable` reconstruye la tabla con su definición de HOY: `flashcards`
  // ganó tres columnas en v20 y una más en v27, que una base de v16 o v17
  // todavía no tiene ninguna. Sin `newColumns` intentaría copiarlas desde una
  // tabla que no las trae. Cada paso las agrega solo si faltan.
  await migrator.alterTable(
    TableMigration(
      db.flashcards,
      newColumns: [
        db.flashcards.sourceChunkId,
        db.flashcards.sourceCharStart,
        db.flashcards.sourceCharEnd,
        db.flashcards.lastExportedAt,
      ],
    ),
  );
  await migrator.alterTable(TableMigration(db.inlineLinks));
  await migrator.alterTable(TableMigration(db.itemPropertyValues));

  final violations = await db.customSelect('PRAGMA foreign_key_check').get();
  if (violations.isNotEmpty) {
    final byTable = <String, int>{};
    for (final row in violations) {
      final table = row.read<String>('table');
      byTable[table] = (byTable[table] ?? 0) + 1;
    }
    throw StateError(
      'La migración a v18 dejó ${violations.length} filas que apuntan a un '
      'elemento que no existe (por tabla: $byTable).',
    );
  }
  return plan;
}
