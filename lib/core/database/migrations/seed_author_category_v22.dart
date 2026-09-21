import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Qué migración escribe los avisos de `migration_issues`.
const authorCategoryMigration = 'f15_v22';

/// Asegura la categoría de sistema «Autor», donde viven las personas que
/// hicieron una obra (F15). La llaman `onCreate`, para una bóveda nueva, y la
/// migración a v22, para una que ya existía.
///
/// Si ya hay una categoría con ese nombre —alguien la creó a mano antes de que
/// la app la necesitara, y «Autor» es un nombre muy natural— no se la
/// duplica ni se la aparta cuando se puede evitar. Lo que hace depende de lo
/// que ya era:
///
/// - **de tipo persona**: ya está; solo se asegura que sea de sistema;
/// - **de texto**: se la REUSA, promovida a persona y a sistema, con todos sus
///   valores y lo que tienen asignado. Sus autores pasan a ser autores de
///   verdad, sin volver a cargarlos. Las personas no tienen jerarquía, así que
///   si alguien había puesto valores bajo otros, quedan en la raíz —el árbol es
///   lo único que se pierde— y cada uno queda anotado en `migration_issues`,
///   para que no se pierda en silencio. Sus nombres no se estructuran: no se
///   adivina dónde termina el apellido (ver `PropertyValues.nameFamily`);
/// - **de número o de fecha**: no puede ser la de las personas —sus valores
///   guardan otra cosa—, así que se aparta con otro nombre («Autor
///   (anterior)»), sin tocar nada de lo que tiene, y se crea la de sistema. Es
///   un caso que casi no existe, pero la alternativa es mezclar fechas con
///   autores.
///
/// No reusa `OrganizeRepository.getOrCreatePropertyDefinition` por el mismo
/// motivo que `seedSystemPropertyCategories`: ese método es de propósito
/// general y no debería poder promover una categoría a sistema como efecto
/// colateral de una llamada cualquiera.
Future<void> ensureAuthorCategory(
  AppDatabase db, {
  required IdGenerator ids,
}) async {
  final existing =
      await (db.select(db.propertyDefinitions)..where(
            (d) => d.name.lower().equals(kAutorCategoryName.toLowerCase()),
          ))
          .getSingleOrNull();

  if (existing == null) {
    await _insertAuthorCategory(db, ids: ids);
    return;
  }

  switch (existing.type) {
    case PropertyValueType.person:
      if (!existing.isSystem) {
        await _markAsAuthorCategory(db, existing.id);
      }
    case PropertyValueType.text:
      await _flattenHierarchy(db, ids: ids, category: existing);
      await _markAsAuthorCategory(db, existing.id);
    case PropertyValueType.number:
    case PropertyValueType.date:
      await _stepAside(db, ids: ids, category: existing);
      await _insertAuthorCategory(db, ids: ids);
  }
}

Future<void> _insertAuthorCategory(
  AppDatabase db, {
  required IdGenerator ids,
}) => db
    .into(db.propertyDefinitions)
    .insert(
      PropertyDefinitionsCompanion.insert(
        id: ids.next(),
        name: kAutorCategoryName,
        createdAt: DateTime.now(),
        type: const Value(PropertyValueType.person),
        isSystem: const Value(true),
      ),
    );

Future<void> _markAsAuthorCategory(AppDatabase db, String id) =>
    (db.update(db.propertyDefinitions)..where((d) => d.id.equals(id))).write(
      const PropertyDefinitionsCompanion(
        type: Value(PropertyValueType.person),
        isSystem: Value(true),
      ),
    );

/// Las personas no tienen jerarquía —los triggers de `vocabulary_hierarchy`
/// solo la admiten en las categorías de texto—: cada valor que estaba bajo otro
/// pasa a la raíz, y queda anotado cuál era su padre.
Future<void> _flattenHierarchy(
  AppDatabase db, {
  required IdGenerator ids,
  required PropertyDefinitionRow category,
}) async {
  final values = await (db.select(
    db.propertyValues,
  )..where((v) => v.definitionId.equals(category.id))).get();
  final labelOf = {for (final v in values) v.id: v.value};

  var flattened = 0;
  for (final child in values) {
    final parentId = child.parentId;
    if (parentId == null) continue;
    flattened++;
    await _recordIssue(
      db,
      ids: ids,
      itemId: child.id,
      stage: 'flatten_hierarchy',
      message:
          'El valor «${child.value}» estaba bajo «${labelOf[parentId]}» en '
          '«${category.name}». Esa categoría pasó a ser la de las personas de '
          'una obra, que no tiene jerarquía: el valor quedó en la raíz.',
    );
  }
  if (flattened == 0) return;

  await (db.update(
    db.propertyValues,
  )..where((v) => v.definitionId.equals(category.id))).write(
    const PropertyValuesCompanion(
      parentId: Value<String?>(null),
      depth: Value(0),
    ),
  );
}

/// Le busca a la categoría de número o de fecha un nombre libre —«Autor
/// (anterior)», «Autor (anterior 2)»…— y se lo pone. Nada de lo que contiene
/// se toca.
Future<void> _stepAside(
  AppDatabase db, {
  required IdGenerator ids,
  required PropertyDefinitionRow category,
}) async {
  final taken = {
    for (final d in await db.select(db.propertyDefinitions).get())
      d.name.toLowerCase(),
  };
  var name = '${category.name} (anterior)';
  for (var n = 2; taken.contains(name.toLowerCase()); n++) {
    name = '${category.name} (anterior $n)';
  }
  await (db.update(db.propertyDefinitions)
        ..where((d) => d.id.equals(category.id)))
      .write(PropertyDefinitionsCompanion(name: Value(name)));
  await _recordIssue(
    db,
    ids: ids,
    itemId: category.id,
    stage: 'category_renamed',
    message:
        'La categoría «${category.name}» era de tipo ${category.type.name}: no '
        'puede ser la de las personas de una obra. Se llama ahora «$name», con '
        'todos sus valores, y la app creó la suya.',
  );
}

Future<void> _recordIssue(
  AppDatabase db, {
  required IdGenerator ids,
  required String itemId,
  required String stage,
  required String message,
}) => db
    .into(db.migrationIssues)
    .insert(
      MigrationIssuesCompanion.insert(
        id: ids.next(),
        migration: authorCategoryMigration,
        itemId: itemId,
        stage: stage,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
