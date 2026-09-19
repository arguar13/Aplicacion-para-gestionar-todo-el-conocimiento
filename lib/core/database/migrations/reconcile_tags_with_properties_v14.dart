import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/property_value_merge.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

const _migrationName = 'f8_tag_reconciliation';

/// Una etiqueta vieja (`Tags`) con lo que tenía puesto.
class TagReconciliationTag {
  const TagReconciliationTag({
    required this.tagId,
    required this.label,
    required this.createdAt,
    required this.itemIds,
  });

  final String tagId;
  final String label;
  final DateTime createdAt;

  /// Solo elementos que existen todavía: ver `danglingAssignments`.
  final Set<String> itemIds;
}

/// Un valor de Tema que se fusiona en el canónico de su grupo.
class TagReconciliationMerge {
  const TagReconciliationMerge({
    required this.valueId,
    required this.label,
    required this.assignments,
  });

  final String valueId;
  final String label;
  final int assignments;
}

/// Lo que se escribe, o se lee y se ignora, bajo UN mismo texto
/// normalizado: los valores de Tema y las etiquetas que "se llaman igual"
/// sin distinguir mayúsculas ni acentos.
class TagReconciliationGroup {
  const TagReconciliationGroup({
    required this.normalizedLabel,
    required this.canonicalLabel,
    required this.canonicalValueId,
    required this.seedTag,
    required this.merges,
    required this.tags,
    required this.aliasesToAdd,
    required this.assignmentsToAdd,
  });

  final String normalizedLabel;
  final String canonicalLabel;

  /// El valor de Tema que se conserva. `null` si el grupo no tiene ninguno
  /// todavía —solo etiquetas—: entonces se crea uno desde [seedTag].
  final String? canonicalValueId;
  final TagReconciliationTag? seedTag;

  /// Valores de Tema que se fusionan dentro del canónico.
  final List<TagReconciliationMerge> merges;

  /// Las etiquetas viejas del grupo, todas: de ellas salen las asignaciones.
  final List<TagReconciliationTag> tags;

  /// Textos que pasan a ser alias del canónico, incluidos los labels de los
  /// valores que se fusionan: la fusión ya los agrega por su cuenta, y al
  /// aplicar el plan `insertOrIgnore` no los duplica.
  final List<String> aliasesToAdd;

  /// Cuántas asignaciones (elemento, valor) le faltan al canónico y salen de
  /// las etiquetas.
  final int assignmentsToAdd;

  bool get createsValue => canonicalValueId == null;

  /// Sin nada que escribir: solo se listó para el recuento.
  bool get isNoop =>
      !createsValue &&
      merges.isEmpty &&
      assignmentsToAdd == 0 &&
      aliasesToAdd.isEmpty;
}

/// Qué hará la reconciliación, calculado SIN escribir nada: el dry-run.
///
/// Solo trae los grupos con algo que hacer. Vale para el estado de la base
/// con el que se calculó: aplicarlo sobre otro es un error de quien llama.
class TagReconciliationPlan {
  const TagReconciliationPlan({
    required this.temaDefinitionId,
    required this.tagsExamined,
    required this.assignmentsExamined,
    required this.groups,
    required this.temaValuesWithoutTag,
    required this.unmappableTags,
    required this.danglingAssignments,
  });

  final String temaDefinitionId;
  final int tagsExamined;

  /// Filas de `ItemTags` que se revisaron.
  final int assignmentsExamined;

  /// Solo los grupos con algo que escribir.
  final List<TagReconciliationGroup> groups;

  /// Valores de Tema que ninguna etiqueta reclama —los creó el editor de
  /// propiedades, o son lo que quedó de una etiqueta que se renombró o se
  /// borró después de la migración a valores de F2—. No se tocan: no hay
  /// forma de saber cuál de las dos cosas fue.
  final int temaValuesWithoutTag;

  /// Etiquetas sin nombre: no hay a qué valor mapearlas.
  final List<TagReconciliationTag> unmappableTags;

  /// Filas de `ItemTags` de un elemento que ya no existe. No se copian.
  final int danglingAssignments;

  bool get hasChanges => groups.isNotEmpty;

  /// Etiquetas que no tenían ningún valor equivalente en Tema.
  int get orphanTags => groups
      .where((g) => g.createsValue)
      .fold(0, (sum, g) => sum + g.tags.length);

  int get assignmentsToAdd =>
      groups.fold(0, (sum, g) => sum + g.assignmentsToAdd);

  int get valueMerges => groups.fold(0, (sum, g) => sum + g.merges.length);

  int get aliasesToAdd =>
      groups.fold(0, (sum, g) => sum + g.aliasesToAdd.length);

  String summary() {
    final aside = [
      if (unmappableTags.isNotEmpty)
        '${unmappableTags.length} etiquetas sin nombre (sin migrar)',
      if (danglingAssignments > 0)
        '$danglingAssignments asignaciones de elementos borrados (sin migrar)',
    ];
    return 'Reconciliación de etiquetas con Tema: $tagsExamined etiquetas y '
        '$assignmentsExamined asignaciones revisadas; '
        '$orphanTags etiquetas sin valor equivalente (se crea), '
        '$assignmentsToAdd asignaciones que faltaban (se agregan), '
        '$valueMerges valores repetidos por acento o mayúsculas (se '
        'fusionan), $aliasesToAdd alias nuevos; '
        '$temaValuesWithoutTag valores de Tema sin etiqueta (no se tocan)'
        '${aside.map((note) => '; $note').join()}.';
  }
}

/// Calcula qué haría [applyTagReconciliation], sin escribir NADA.
///
/// Unifica por texto normalizado —sin distinguir mayúsculas ni acentos, ver
/// `normalizeVocabularyLabel`—, y SOLO dentro de "Tema": es la categoría a
/// la que F2 copió las etiquetas, y a la que ahora se vuelve la única
/// fuente de verdad de las etiquetas.
///
/// Por cada texto normalizado:
///  * si ya hay valores de Tema, se conserva el más usado (a igual uso, el
///    más antiguo) y los demás se fusionan en él, con su label como alias;
///  * si no hay ninguno —etiquetas creadas después de F2, que nunca llegaron
///    a Tema—, se crea uno desde la etiqueta más usada, con su mismo id;
///  * las asignaciones de las etiquetas pasan al canónico, y el texto de
///    cada etiqueta que difiere del canónico queda como alias.
///
/// Nunca inventa ni pierde una asignación: lo que cambia es CON QUÉ VALOR
/// se guarda cada una, no a qué elemento ni bajo qué texto normalizado.
Future<TagReconciliationPlan> planTagReconciliation(AppDatabase db) async {
  // `getSingle` y no `getSingleOrNull`: `seedSystemPropertyCategories` la
  // siembra antes en cualquier camino que llegue acá. Si falta, la base
  // está rota y seguir en silencio dejaría las etiquetas sin adónde ir.
  final tema = await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.lower().equals('tema'))).getSingle();

  final tags = await db.select(db.tags).get();
  final itemTags = await db.select(db.itemTags).get();

  // Con las claves foráneas apagadas —lo están durante `onUpgrade`— nada
  // garantiza que un `ItemTags` apunte a un elemento que existe.
  final existingItemIds =
      (await (db.selectOnly(db.items)..addColumns([db.items.id]))
              .map((row) => row.read(db.items.id)!)
              .get())
          .toSet();

  final values = await (db.select(
    db.propertyValues,
  )..where((v) => v.definitionId.equals(tema.id))).get();
  final valueAssignments =
      await (db.select(db.itemPropertyValues).join([
        innerJoin(
          db.propertyValues,
          db.propertyValues.id.equalsExp(db.itemPropertyValues.propertyValueId),
        ),
      ])..where(db.propertyValues.definitionId.equals(tema.id))).map((row) {
        final assignment = row.readTable(db.itemPropertyValues);
        return (assignment.propertyValueId, assignment.itemId);
      }).get();
  final existingAliases =
      (await (db.select(
            db.propertyAliases,
          )..where((a) => a.definitionId.equals(tema.id))).get())
          .map((a) => a.alias.toLowerCase())
          .toSet();

  final itemsByValue = <String, Set<String>>{};
  for (final (valueId, itemId) in valueAssignments) {
    itemsByValue.putIfAbsent(valueId, () => {}).add(itemId);
  }

  var danglingAssignments = 0;
  final itemsByTag = <String, Set<String>>{};
  for (final row in itemTags) {
    if (existingItemIds.contains(row.itemId)) {
      itemsByTag.putIfAbsent(row.tagId, () => {}).add(row.itemId);
    } else {
      danglingAssignments++;
    }
  }

  // Agrupar por texto normalizado.
  final valuesByKey = <String, List<PropertyValueRow>>{};
  for (final value in values) {
    final key = normalizeVocabularyLabel(value.value);
    if (key.isNotEmpty) valuesByKey.putIfAbsent(key, () => []).add(value);
  }
  final tagsByKey = <String, List<TagReconciliationTag>>{};
  final unmappable = <TagReconciliationTag>[];
  for (final tag in tags) {
    final reconTag = TagReconciliationTag(
      tagId: tag.id,
      label: tag.name.trim(),
      createdAt: tag.createdAt,
      itemIds: itemsByTag[tag.id] ?? const {},
    );
    final key = normalizeVocabularyLabel(tag.name);
    if (key.isEmpty) {
      unmappable.add(reconTag);
    } else {
      tagsByKey.putIfAbsent(key, () => []).add(reconTag);
    }
  }

  final groups = <TagReconciliationGroup>[];
  var temaValuesWithoutTag = 0;
  final keys = {...valuesByKey.keys, ...tagsByKey.keys}.toList()..sort();
  for (final key in keys) {
    final groupValues = valuesByKey[key] ?? const <PropertyValueRow>[];
    final groupTags = tagsByKey[key] ?? const <TagReconciliationTag>[];
    if (groupTags.isEmpty) temaValuesWithoutTag += groupValues.length;

    final canonical = groupValues.isEmpty
        ? null
        : _pickFirst<PropertyValueRow>(
            groupValues,
            usage: (v) => itemsByValue[v.id]?.length ?? 0,
            createdAt: (v) => v.createdAt,
            id: (v) => v.id,
          );
    final seedTag = canonical != null
        ? null
        : _pickFirst<TagReconciliationTag>(
            groupTags,
            usage: (t) => t.itemIds.length,
            createdAt: (t) => t.createdAt,
            id: (t) => t.tagId,
          );
    final canonicalLabel = canonical?.value ?? seedTag!.label;

    final toMerge = [
      for (final v in groupValues)
        if (v.id != canonical?.id) v,
    ];
    final canonicalItems = canonical == null
        ? const <String>{}
        : itemsByValue[canonical.id] ?? const <String>{};
    final movedItems = {for (final v in toMerge) ...?itemsByValue[v.id]};
    final tagItems = {for (final t in groupTags) ...t.itemIds};
    final assignmentsToAdd = tagItems
        .difference(canonicalItems)
        .difference(movedItems)
        .length;

    // Los textos que difieren del canónico solo en mayúsculas ya son "el
    // mismo": no hace falta un alias. Los que difieren en un acento o en un
    // carácter no ASCII sí quedan.
    final aliasCandidates = <String>{
      for (final v in toMerge) v.value,
      for (final t in groupTags) t.label,
    }..removeWhere((a) => a.toLowerCase() == canonicalLabel.toLowerCase());
    final aliasesToAdd = (aliasCandidates.toList()..sort())
        .where((a) => !existingAliases.contains(a.toLowerCase()))
        .toList();

    final group = TagReconciliationGroup(
      normalizedLabel: key,
      canonicalLabel: canonicalLabel,
      canonicalValueId: canonical?.id,
      seedTag: seedTag,
      merges: [
        for (final v in toMerge)
          TagReconciliationMerge(
            valueId: v.id,
            label: v.value,
            assignments: itemsByValue[v.id]?.length ?? 0,
          ),
      ],
      tags: groupTags,
      aliasesToAdd: aliasesToAdd,
      assignmentsToAdd: assignmentsToAdd,
    );
    if (!group.isNoop) groups.add(group);
  }

  return TagReconciliationPlan(
    temaDefinitionId: tema.id,
    tagsExamined: tags.length,
    assignmentsExamined: itemTags.length,
    groups: groups,
    temaValuesWithoutTag: temaValuesWithoutTag,
    unmappableTags: unmappable,
    danglingAssignments: danglingAssignments,
  );
}

/// Aplica [plan]: crea los valores que faltan, fusiona los repetidos, pasa
/// las asignaciones de las etiquetas al valor canónico y suma los alias.
///
/// No abre transacción: quien llama la corre dentro de la suya —en la
/// migración ya la hay—. Las asignaciones se agregan con `insertOrIgnore`,
/// nunca `insertOnConflictUpdate`: si el elemento ya tenía el valor, su
/// `origin` (`suggestedAccepted`, `inherited`) se queda como estaba en vez
/// de degradarse a `manual`. Es el mismo error que la migración de F2 sí
/// tenía.
///
/// `Tags` y `ItemTags` no se tocan: quedan como están hasta que F10 las
/// retire.
Future<void> applyTagReconciliation(
  AppDatabase db,
  TagReconciliationPlan plan, {
  required IdGenerator ids,
  Clock clock = DateTime.now,
}) async {
  for (final group in plan.groups) {
    final canonicalId =
        group.canonicalValueId ??
        await _createValueFromTag(
          db,
          definitionId: plan.temaDefinitionId,
          tag: group.seedTag!,
          ids: ids,
        );

    for (final merge in group.merges) {
      final keep = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals(canonicalId))).getSingle();
      final discard = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals(merge.valueId))).getSingle();
      await mergePropertyValueRows(
        db,
        keep: keep,
        discard: discard,
        ids: ids,
        clock: clock,
      );
    }

    for (final tag in group.tags) {
      for (final itemId in tag.itemIds) {
        await db
            .into(db.itemPropertyValues)
            .insert(
              ItemPropertyValuesCompanion.insert(
                itemId: itemId,
                propertyValueId: canonicalId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }

    for (final alias in group.aliasesToAdd) {
      // `insertOrIgnore`: el UNIQUE de la categoría decide si ya existía,
      // con el mismo criterio de mayúsculas que usa siempre — sin
      // reimplementarlo acá.
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: ids.next(),
              propertyValueId: canonicalId,
              definitionId: plan.temaDefinitionId,
              alias: alias,
              createdAt: clock(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
}

/// El paso completo de la migración v14: calcula el plan, deja el informe
/// —en `MigrationIssues` y en el logger— y recién entonces lo aplica.
///
/// Idempotente: una segunda corrida calcula un plan sin cambios y no
/// escribe nada, ni siquiera informe.
///
/// Sin `try`/`catch`: si algo falla, la migración entera falla y revierte —
/// corre dentro de la transacción de `onUpgrade`—, y hay una copia previa de
/// la base. Seguir con un grupo saltado dejaría una etiqueta sin valor, y
/// una etiqueta que desaparece de la interfaz es exactamente la pérdida que
/// este paso existe para evitar.
Future<TagReconciliationPlan> reconcileTagsWithProperties(
  AppDatabase db, {
  required IdGenerator ids,
  required AppLogger logger,
  Clock clock = DateTime.now,
}) async {
  final plan = await planTagReconciliation(db);
  if (!plan.hasChanges &&
      plan.unmappableTags.isEmpty &&
      plan.danglingAssignments == 0) {
    return plan;
  }

  logger.info(plan.summary());
  await _recordReport(db, plan, ids: ids, now: clock());
  if (plan.hasChanges) {
    await applyTagReconciliation(db, plan, ids: ids, clock: clock);
  }
  return plan;
}

Future<String> _createValueFromTag(
  AppDatabase db, {
  required String definitionId,
  required TagReconciliationTag tag,
  required IdGenerator ids,
}) async {
  // Se reusa el id de la etiqueta —`Tag.id` y `PropertyValue.id` pasan a ser
  // lo mismo—, salvo que ya lo use un valor: un choque de ids es casi
  // imposible con UUID, pero si pasara, la migración no debería morir por
  // eso.
  final taken =
      await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals(tag.tagId))).getSingleOrNull() !=
      null;
  final valueId = taken ? ids.next() : tag.tagId;

  await db
      .into(db.propertyValues)
      .insert(
        PropertyValuesCompanion.insert(
          id: valueId,
          definitionId: definitionId,
          value: tag.label,
          createdAt: tag.createdAt,
        ),
      );
  return valueId;
}

/// El informe previo: una fila de `MigrationIssues` por cada cosa que la
/// reconciliación va a crear, fusionar o no pudo mapear. Nadie las lee hoy;
/// son la bitácora para quien tenga que entender qué pasó con una etiqueta.
Future<void> _recordReport(
  AppDatabase db,
  TagReconciliationPlan plan, {
  required IdGenerator ids,
  required DateTime now,
}) async {
  Future<void> report(String itemId, String stage, String message) => db
      .into(db.migrationIssues)
      .insert(
        MigrationIssuesCompanion.insert(
          id: ids.next(),
          migration: _migrationName,
          itemId: itemId,
          stage: stage,
          message: message,
          createdAt: now,
        ),
      );

  for (final group in plan.groups) {
    if (group.createsValue) {
      for (final tag in group.tags) {
        await report(
          tag.tagId,
          'orphan_tag',
          'La etiqueta "${tag.label}" no tenía un valor equivalente bajo '
              'Tema (${tag.itemIds.length} elementos); se crea.',
        );
      }
    }
    for (final merge in group.merges) {
      await report(
        merge.valueId,
        'merge_values',
        'El valor de Tema "${merge.label}" (${merge.assignments} elementos) '
            'se fusiona en "${group.canonicalLabel}": difieren solo en '
            'acentos o mayúsculas.',
      );
    }
  }
  for (final tag in plan.unmappableTags) {
    await report(
      tag.tagId,
      'unmapped_tag',
      'Etiqueta sin nombre (${tag.itemIds.length} elementos): no hay a qué '
          'valor mapearla; queda sin migrar.',
    );
  }
  if (plan.danglingAssignments > 0) {
    await report(
      plan.temaDefinitionId,
      'dangling_assignments',
      '${plan.danglingAssignments} asignaciones de etiqueta apuntaban a '
          'elementos que ya no existen; no se migran.',
    );
  }
}

/// El primero de [items] según: más uso, después más antiguo, después id —un
/// orden total, para que el resultado no dependa del orden en que la base
/// devuelva las filas—.
T _pickFirst<T>(
  Iterable<T> items, {
  required int Function(T) usage,
  required DateTime Function(T) createdAt,
  required String Function(T) id,
}) {
  int compare(T a, T b) {
    final byUsage = usage(b).compareTo(usage(a));
    if (byUsage != 0) return byUsage;
    final byAge = createdAt(a).compareTo(createdAt(b));
    if (byAge != 0) return byAge;
    return id(a).compareTo(id(b));
  }

  return items.reduce((best, next) => compare(next, best) < 0 ? next : best);
}
