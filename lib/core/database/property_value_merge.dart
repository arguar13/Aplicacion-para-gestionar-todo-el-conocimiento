import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/vocabulary_tree_rows.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Lo que hace falta para deshacer UNA fusión de dos valores: qué era el
/// valor descartado, qué asignaciones pasaron al que se conserva, cuáles
/// se descartaron por duplicadas, y qué alias se movieron o se crearon.
///
/// Vive en memoria mientras dura la sesión: no se persiste (ver
/// [undoPropertyValueMerge]).
class PropertyValueMergeUndo {
  const PropertyValueMergeUndo({
    required this.keepId,
    required this.discard,
    required this.movedAssignments,
    required this.droppedAssignments,
    required this.movedAliasIds,
    required this.createdAliasId,
    this.placements = const [],
    this.movedContributors = const [],
    this.droppedContributors = const [],
  });

  final String keepId;

  /// La fila completa del valor descartado, para volver a crearla igual.
  final PropertyValueRow discard;

  /// Asignaciones (elemento, origin y la pasada de la IA, si la puso ella)
  /// que pasaron del descartado al que se conserva.
  final List<({String itemId, ItemPropertyOrigin origin, String? aiRunId})>
  movedAssignments;

  /// Asignaciones del descartado que sobraban porque el elemento ya tenía el
  /// valor que se conserva: se borraron, y deshacer las vuelve a poner.
  final List<({String itemId, ItemPropertyOrigin origin, String? aiRunId})>
  droppedAssignments;

  /// Alias que apuntaban al descartado y pasaron al que se conserva.
  final List<String> movedAliasIds;

  /// El alias que se creó con el label del descartado; `null` si no se pudo
  /// crear porque ese texto ya era un alias de otra cosa.
  final String? createdAliasId;

  /// Dónde estaba, ANTES de la fusión, cada valor de la jerarquía que la
  /// fusión movió: los hijos del descartado, que pasan al que se conserva, y
  /// el propio que se conserva si estaba dentro de la rama del descartado y
  /// sube a su lugar (F13). Vacío si la fusión no movió ninguno.
  final List<ValuePlacement> placements;

  /// Las obras de la persona descartada que pasaron a la que se conserva (F15),
  /// tal como estaban: la fila de `source_contributor` con su rol y su lugar.
  final List<SourceContributorRow> movedContributors;

  /// Las que sobraban porque la obra ya tenía a la persona que se conserva con
  /// el mismo rol: se borraron, y deshacer las vuelve a poner.
  final List<SourceContributorRow> droppedContributors;

  /// Cuántos elementos tocó la fusión: los que tenían el valor descartado.
  int get affectedItems => movedAssignments.length + droppedAssignments.length;
}

/// El motor de la fusión de dos valores de una misma categoría: todo lo que
/// tenía [discard] pasa a [keep], y [discard] desaparece.
///
/// Vive a nivel de base y no dentro de `OrganizeRepositoryImpl` porque lo
/// usan caminos que no se pueden mezclar por capas: la fusión que el usuario
/// pide desde la pantalla de Vocabulario y la reconciliación de etiquetas
/// que corre dentro de una migración —`core/database` no puede depender de
/// `features`—. Una sola implementación, no dos copias que terminen
/// desviándose.
///
/// No abre transacción ni valida nada: quien llama la corre dentro de la
/// suya, con los dos valores ya leídos y comprobado que son distintos y de
/// la misma categoría. Son cinco pasos que solo tienen sentido juntos —a
/// medias dejarían asignaciones apuntando a un valor que ya no existe—.
///
/// Devuelve lo necesario para deshacerla con [undoPropertyValueMerge].
Future<PropertyValueMergeUndo> mergePropertyValueRows(
  AppDatabase db, {
  required PropertyValueRow keep,
  required PropertyValueRow discard,
  required IdGenerator ids,
  required Clock clock,
}) async {
  assert(keep.id != discard.id, 'Un valor no se fusiona consigo mismo.');
  assert(
    keep.definitionId == discard.definitionId,
    'Solo se fusionan valores de la misma categoría.',
  );

  // 1. Si un item ya tenía asignadas ambas, la fila de discard sobra:
  // borrarla antes de reapuntar el resto, para no chocar con la clave
  // primaria compuesta de ItemPropertyValues en el paso 2.
  final assignments = await (db.select(
    db.itemPropertyValues,
  )..where((t) => t.propertyValueId.equals(discard.id))).get();
  final moved =
      <({String itemId, ItemPropertyOrigin origin, String? aiRunId})>[];
  final dropped =
      <({String itemId, ItemPropertyOrigin origin, String? aiRunId})>[];
  for (final assignment in assignments) {
    final alreadyHasKeep =
        await (db.select(db.itemPropertyValues)..where(
              (t) =>
                  t.itemId.equals(assignment.itemId) &
                  t.propertyValueId.equals(keep.id),
            ))
            .getSingleOrNull();
    if (alreadyHasKeep != null) {
      dropped.add((
        itemId: assignment.itemId,
        origin: assignment.origin,
        aiRunId: assignment.aiRunId,
      ));
      await (db.delete(db.itemPropertyValues)..where(
            (t) =>
                t.itemId.equals(assignment.itemId) &
                t.propertyValueId.equals(discard.id),
          ))
          .go();
    } else {
      moved.add((
        itemId: assignment.itemId,
        origin: assignment.origin,
        aiRunId: assignment.aiRunId,
      ));
    }
  }

  // 2. El resto de las asignaciones de discard pasan a keep.
  await (db.update(db.itemPropertyValues)
        ..where((t) => t.propertyValueId.equals(discard.id)))
      .write(ItemPropertyValuesCompanion(propertyValueId: Value(keep.id)));

  // 2b. Las obras de la persona (F15): si el valor es de una categoría de
  // persona, las obras que la nombran como autora, traductora… pasan a nombrar
  // a la que se conserva. Sin esto la fusión las BORRARÍA: `source_contributor`
  // cae en cascada con el valor.
  final contributors = await _repointContributors(
    db,
    keep: keep,
    discard: discard,
    clock: clock,
  );

  // 3. Los alias que ya apuntaban a discard pasan a keep —ANTES de borrar
  // discard: su FK es ON DELETE CASCADE, y borrarlo primero se los llevaría
  // con él—.
  final aliasIds =
      (await (db.select(
            db.propertyAliases,
          )..where((a) => a.propertyValueId.equals(discard.id))).get())
          .map((a) => a.id)
          .toList();
  await (db.update(db.propertyAliases)
        ..where((a) => a.propertyValueId.equals(discard.id)))
      .write(PropertyAliasesCompanion(propertyValueId: Value(keep.id)));

  // 4. El label de discard queda como alias nuevo de keep, salvo que ese
  // texto ya sea un alias de otra cosa en la misma categoría —de otro
  // valor, o de keep mismo—: se tolera sin fallar la fusión entera por un
  // solo alias que no se pudo sumar.
  final aliasClash =
      await (db.select(db.propertyAliases)..where(
            (a) =>
                a.definitionId.equals(keep.definitionId) &
                a.alias.lower().equals(discard.value.toLowerCase()),
          ))
          .getSingleOrNull();
  String? createdAliasId;
  if (aliasClash == null) {
    createdAliasId = ids.next();
    await db
        .into(db.propertyAliases)
        .insert(
          PropertyAliasesCompanion.insert(
            id: createdAliasId,
            propertyValueId: keep.id,
            definitionId: keep.definitionId,
            alias: discard.value,
            createdAt: clock(),
          ),
        );
  }

  // 5. La rama de discard no se pierde con él (F13): sus hijos pasan a keep.
  final placements = await _adoptBranch(db, keep: keep, discard: discard);

  // 6. discard ya no tiene nada que solo él tuviera: se borra.
  await (db.delete(
    db.propertyValues,
  )..where((v) => v.id.equals(discard.id))).go();

  return PropertyValueMergeUndo(
    keepId: keep.id,
    discard: discard,
    movedAssignments: moved,
    droppedAssignments: dropped,
    movedAliasIds: aliasIds,
    createdAliasId: createdAliasId,
    placements: placements,
    movedContributors: contributors.moved,
    droppedContributors: contributors.dropped,
  );
}

/// Pasa las obras de [discard] a [keep] (F15): lo hace `KnowledgeEntryWriter`,
/// que es quien escribe esas tablas y anota que la referencia de cada obra
/// cambió.
///
/// Solo si el valor es de una categoría de PERSONA: es lo único que puede tener
/// obras, y lo que deja esta función fuera de las migraciones de esquemas
/// anteriores a v22, donde la tabla todavía no existe.
Future<({List<SourceContributorRow> moved, List<SourceContributorRow> dropped})>
_repointContributors(
  AppDatabase db, {
  required PropertyValueRow keep,
  required PropertyValueRow discard,
  required Clock clock,
}) async {
  final definition = await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.id.equals(discard.definitionId))).getSingleOrNull();
  if (definition?.type != PropertyValueType.person) {
    return (
      moved: const <SourceContributorRow>[],
      dropped: const <SourceContributorRow>[],
    );
  }
  return KnowledgeEntryWriter(
    db,
    clock: clock,
  ).repointContributors(keepId: keep.id, discardId: discard.id);
}

/// Lo que le pasa a la rama de [discard] cuando se lo fusiona en [keep]: sus
/// hijos pasan a colgar de [keep], con toda su descendencia.
///
/// Si [keep] estaba DENTRO de la rama de [discard] —«Roma antigua» que absorbe
/// a «Roma», su propio padre—, tomaría a sus hijos y él mismo quedaría bajo su
/// propio hijo: un ciclo. Entonces [keep] sube primero al lugar de [discard],
/// y recién después recibe a los hijos que quedan.
///
/// Devuelve dónde estaba, antes, cada valor que cambió de lugar o de nivel:
/// lo que hace falta para deshacerlo.
Future<List<ValuePlacement>> _adoptBranch(
  AppDatabase db, {
  required PropertyValueRow keep,
  required PropertyValueRow discard,
}) async {
  final discardBranch = await subtreeRows(db, [discard.id]);
  final keepBranch = await subtreeRows(db, [keep.id]);
  final before = {
    for (final row in placementsOf([...discardBranch, ...keepBranch]))
      if (row.id != discard.id) row.id: row,
  };

  if (discardBranch.any((row) => row.id == keep.id)) {
    await (db.update(db.propertyValues)..where((v) => v.id.equals(keep.id)))
        .write(PropertyValuesCompanion(parentId: Value(discard.parentId)));
  }
  await (db.update(db.propertyValues)..where(
        (v) => v.parentId.equals(discard.id) & v.id.equals(keep.id).not(),
      ))
      .write(PropertyValuesCompanion(parentId: Value(keep.id)));
  await recomputeDepths(db, [keep.id]);

  final after = await subtreeRows(db, [keep.id]);
  return [
    for (final row in after)
      if (before[row.id] case final was?
          when was.parentId != row.parentId || was.depth != row.depth)
        was,
  ];
}

/// Por qué [undoPropertyValueMerge] se negó a deshacer.
class MergeUndoConflict implements Exception {
  const MergeUndoConflict(this.message);

  final String message;

  @override
  String toString() => 'MergeUndoConflict: $message';
}

/// Deshace una fusión hecha con [mergePropertyValueRows]: vuelve a crear el
/// valor descartado, le devuelve sus asignaciones y sus alias, y quita el
/// alias que la fusión había creado.
///
/// Se NIEGA —lanza [MergeUndoConflict]— si el vocabulario cambió desde
/// entonces de una forma que haría adivinar: el valor que se conservó ya no
/// existe, el id del descartado se volvió a usar, o una asignación que la
/// fusión había movido ya no está donde la dejó. Deshacer a medias, o
/// inventando qué quiso el usuario en el medio, es peor que no deshacer.
///
/// No abre transacción: quien llama la corre dentro de la suya, para que una
/// negativa a mitad de camino no deje nada tocado.
Future<void> undoPropertyValueMerge(
  AppDatabase db,
  PropertyValueMergeUndo undo, {
  Clock clock = DateTime.now,
}) async {
  final keep = await (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(undo.keepId))).getSingleOrNull();
  if (keep == null) {
    throw const MergeUndoConflict(
      'El valor en el que se fusionó ya no existe.',
    );
  }
  final discardTaken = await (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(undo.discard.id))).getSingleOrNull();
  if (discardTaken != null) {
    throw const MergeUndoConflict('El valor fusionado ya fue recreado.');
  }
  for (final moved in undo.movedAssignments) {
    final stillThere =
        await (db.select(db.itemPropertyValues)..where(
              (t) =>
                  t.itemId.equals(moved.itemId) &
                  t.propertyValueId.equals(keep.id),
            ))
            .getSingleOrNull();
    if (stillThere == null) {
      throw const MergeUndoConflict(
        'Un elemento ya no tiene el valor en el que se fusionó.',
      );
    }
  }

  // El descartado vuelve a existir tal cual era.
  final discardParent = undo.discard.parentId;
  if (discardParent != null &&
      await (db.select(
            db.propertyValues,
          )..where((v) => v.id.equals(discardParent))).getSingleOrNull() ==
          null) {
    throw const MergeUndoConflict(
      'El valor bajo el que estaba el fusionado ya no existe.',
    );
  }
  await db.into(db.propertyValues).insert(undo.discard);
  await restoreValuePlacements(db, undo.placements);

  // Sin el alias que la fusión le puso al que se conservó.
  final createdAliasId = undo.createdAliasId;
  if (createdAliasId != null) {
    await (db.delete(
      db.propertyAliases,
    )..where((a) => a.id.equals(createdAliasId))).go();
  }

  // Los alias que ya eran suyos, de vuelta.
  if (undo.movedAliasIds.isNotEmpty) {
    await (db.update(
      db.propertyAliases,
    )..where((a) => a.id.isIn(undo.movedAliasIds))).write(
      PropertyAliasesCompanion(propertyValueId: Value(undo.discard.id)),
    );
  }

  // Las asignaciones que se habían movido, de vuelta...
  for (final moved in undo.movedAssignments) {
    await (db.update(db.itemPropertyValues)..where(
          (t) =>
              t.itemId.equals(moved.itemId) & t.propertyValueId.equals(keep.id),
        ))
        .write(
          ItemPropertyValuesCompanion(
            propertyValueId: Value(undo.discard.id),
            origin: Value(moved.origin),
          ),
        );
  }
  // ...y las que sobraban por duplicadas, otra vez con su origin.
  for (final dropped in undo.droppedAssignments) {
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: dropped.itemId,
            propertyValueId: undo.discard.id,
            origin: Value(dropped.origin),
            // La pasada de la IA que la había puesto (F27): sin ella, deshacer
            // la fusión dejaría una asignación de la IA que ya no se deshace.
            aiRunId: Value(dropped.aiRunId),
          ),
        );
  }

  // Las obras: las que se habían movido vuelven a nombrar a la persona de
  // antes, y las que sobraban, a estar. Lo hace quien las escribe, y si alguien
  // las cambió desde entonces se niega sin dejar nada a medias.
  try {
    await KnowledgeEntryWriter(db, clock: clock).restoreContributors(
      keepId: keep.id,
      discardId: undo.discard.id,
      moved: undo.movedContributors,
      dropped: undo.droppedContributors,
    );
  } on ContributorRestoreConflict catch (conflict) {
    throw MergeUndoConflict(conflict.message);
  }
}

/// Devuelve cada valor de [placements] a su padre y su nivel de antes: lo que
/// necesitan para deshacer tanto una fusión como un movimiento de rama.
///
/// Primero los suelta a todos —una raíz nunca cierra un ciclo— y después los
/// vuelve a colgar de arriba hacia abajo, con el mismo orden que tenían: el
/// estado de la fusión y el de antes pueden poner a dos valores uno bajo el
/// otro en sentidos contrarios, y cambiar un padre por vez, sin soltar primero,
/// pasaría por un ciclo que la base rechaza.
Future<void> restoreValuePlacements(
  AppDatabase db,
  List<ValuePlacement> placements,
) async {
  if (placements.isEmpty) return;
  final ids = placements.map((p) => p.id).toList();
  final present = {
    for (final row in await (db.select(
      db.propertyValues,
    )..where((v) => v.id.isIn(ids))).get())
      row.id,
  };
  if (present.length != ids.length) {
    throw const MergeUndoConflict(
      'Un valor de la rama fusionada ya no existe.',
    );
  }
  for (final placement in placements) {
    final parentId = placement.parentId;
    if (parentId == null || present.contains(parentId)) continue;
    final parent = await (db.select(
      db.propertyValues,
    )..where((v) => v.id.equals(parentId))).getSingleOrNull();
    if (parent == null) {
      throw const MergeUndoConflict(
        'El valor bajo el que estaba una rama ya no existe.',
      );
    }
  }

  await (db.update(db.propertyValues)..where((v) => v.id.isIn(ids))).write(
    const PropertyValuesCompanion(parentId: Value(null)),
  );
  final topDown = [...placements]..sort((a, b) => a.depth.compareTo(b.depth));
  for (final placement in topDown) {
    await (db.update(
      db.propertyValues,
    )..where((v) => v.id.equals(placement.id))).write(
      PropertyValuesCompanion(
        parentId: Value(placement.parentId),
        depth: Value(placement.depth),
      ),
    );
  }
}
