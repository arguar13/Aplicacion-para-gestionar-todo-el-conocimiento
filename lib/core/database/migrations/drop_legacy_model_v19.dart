import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/logging/app_logger.dart';

/// Qué encuentra el paso v19 antes de soltar el modelo viejo, calculado SIN
/// escribir nada: el dry-run.
///
/// v19 suelta `items`, `sources`, `tags`, `item_tags` y la columna
/// `source.full_text`. Todo eso es texto o datos que YA viven en otro lado:
/// los elementos y sus fuentes, en `item`/`source`; las etiquetas, como valores
/// de Tema desde F8; y el texto íntegro de una fuente, en su forma de texto
/// principal —`full_text` era una copia—. Lo único que este paso no puede dar
/// por copiado es el texto: por eso mira, antes de quitar la columna, que
/// ninguna fuente lo tenga SOLO ahí.
class LegacyModelDropPlan {
  const LegacyModelDropPlan({
    required this.items,
    required this.sources,
    required this.tags,
    required this.itemTags,
    required this.withFullText,
    required this.onlyInFullText,
    required this.staleFullText,
  });

  /// Filas que se sueltan de cada tabla vieja.
  final int items;
  final int sources;
  final int tags;
  final int itemTags;

  /// Fuentes con algo en `source.full_text`.
  final int withFullText;

  /// Ids de fuentes cuyo `full_text` tiene texto y que NO tienen ninguna forma
  /// de texto: soltar la columna lo perdería. Debe estar vacío.
  final List<String> onlyInFullText;

  /// Fuentes cuyo `full_text` no coincide con el texto de su forma principal:
  /// una copia vieja de un texto que después se rehízo. Se informan; la forma
  /// principal es la que vale.
  final int staleFullText;

  bool get canProceed => onlyInFullText.isEmpty;

  String summary() =>
      'Modelo viejo por soltar: $items items, $sources sources, $tags tags y '
      '$itemTags item_tags. source.full_text: $withFullText con contenido, '
      '${onlyInFullText.length} con texto que no está en ninguna forma, '
      '$staleFullText distintos del texto de su forma principal.';
}

/// Calcula el estado, sin escribir NADA.
Future<LegacyModelDropPlan> planLegacyModelDrop(AppDatabase db) async {
  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  // La forma de texto de la que sale el texto íntegro: la principal o, si
  // ninguna lo es, la primera que se guardó (`sourceTextRendition`).
  const primaryText = '''
(SELECT r.content FROM renditions r
  WHERE r.item_id = s.item_id AND r.content IS NOT NULL
  ORDER BY r.is_primary DESC, r.created_at, r.id LIMIT 1)''';

  final onlyInFullText = [
    for (final row in await db.customSelect('''
SELECT s.item_id AS id FROM source s
 WHERE s.full_text <> ''
   AND NOT EXISTS (SELECT 1 FROM renditions r
                    WHERE r.item_id = s.item_id AND r.content IS NOT NULL)
 ORDER BY s.item_id''').get())
      row.read<String>('id'),
  ];

  return LegacyModelDropPlan(
    items: await count('SELECT COUNT(*) AS n FROM items'),
    sources: await count('SELECT COUNT(*) AS n FROM sources'),
    tags: await count('SELECT COUNT(*) AS n FROM tags'),
    itemTags: await count('SELECT COUNT(*) AS n FROM item_tags'),
    withFullText: await count(
      "SELECT COUNT(*) AS n FROM source WHERE full_text <> ''",
    ),
    onlyInFullText: onlyInFullText,
    staleFullText: await count('''
SELECT COUNT(*) AS n FROM source s
 WHERE s.full_text <> ''
   AND s.full_text <> COALESCE($primaryText, '')'''),
  );
}

/// El paso de v19: suelta el modelo viejo.
///
/// Calcula el plan y lo informa; si alguna fuente tiene texto solo en
/// `source.full_text` lanza —la migración entera revierte— antes que perderlo:
/// el texto de una fuente nunca se pierde ni se reescribe. Después reconstruye
/// `source` sin la columna `full_text` y borra `item_tags`, `tags`, `items` y
/// `sources`, en el orden de sus claves foráneas. Al terminar exige que
/// `PRAGMA foreign_key_check` no encuentre ninguna violación.
///
/// Las filas de todo lo que el usuario creó, y el tamaño del modelo nuevo, los
/// compara quien llama (`captureVaultCounts`): este paso no cambia cuántas hay.
Future<LegacyModelDropPlan> dropLegacyModel(
  AppDatabase db,
  Migrator migrator, {
  required AppLogger logger,
}) async {
  final plan = await planLegacyModelDrop(db);
  logger.info(plan.summary());
  if (!plan.canProceed) {
    throw StateError(
      'La migración a v19 no puede quitar source.full_text: '
      '${plan.onlyInFullText.length} fuentes tienen texto solo ahí y perderlo '
      'está descartado. No se modificó nada.',
    );
  }

  // `alterTable` reconstruye la tabla con su definición de HOY: `source`
  // ganó `language` en v32, que una base de v18 todavía no tiene. Sin
  // `newColumns` intentaría copiarla desde una tabla que no la trae; el
  // paso de v32 la agrega solo si falta.
  await migrator.alterTable(
    TableMigration(
      db.knowledgeSources,
      newColumns: [db.knowledgeSources.language],
    ),
  );
  for (final table in const ['item_tags', 'tags', 'items', 'sources']) {
    await migrator.deleteTable(table);
  }

  final violations = await db.customSelect('PRAGMA foreign_key_check').get();
  if (violations.isNotEmpty) {
    throw StateError(
      'La migración a v19 dejó ${violations.length} filas que apuntan a algo '
      'que no existe.',
    );
  }
  return plan;
}
