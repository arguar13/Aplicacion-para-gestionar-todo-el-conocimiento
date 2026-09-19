import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
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
  });

  final String keepId;

  /// La fila completa del valor descartado, para volver a crearla igual.
  final PropertyValueRow discard;

  /// Asignaciones (elemento, origin) que pasaron del descartado al que se
  /// conserva.
  final List<({String itemId, ItemPropertyOrigin origin})> movedAssignments;

  /// Asignaciones del descartado que sobraban porque el elemento ya tenía el
  /// valor que se conserva: se borraron, y deshacer las vuelve a poner.
  final List<({String itemId, ItemPropertyOrigin origin})> droppedAssignments;

  /// Alias que apuntaban al descartado y pasaron al que se conserva.
  final List<String> movedAliasIds;

  /// El alias que se creó con el label del descartado; `null` si no se pudo
  /// crear porque ese texto ya era un alias de otra cosa.
  final String? createdAliasId;

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
  final moved = <({String itemId, ItemPropertyOrigin origin})>[];
  final dropped = <({String itemId, ItemPropertyOrigin origin})>[];
  for (final assignment in assignments) {
    final alreadyHasKeep =
        await (db.select(db.itemPropertyValues)..where(
              (t) =>
                  t.itemId.equals(assignment.itemId) &
                  t.propertyValueId.equals(keep.id),
            ))
            .getSingleOrNull();
    if (alreadyHasKeep != null) {
      dropped.add((itemId: assignment.itemId, origin: assignment.origin));
      await (db.delete(db.itemPropertyValues)..where(
            (t) =>
                t.itemId.equals(assignment.itemId) &
                t.propertyValueId.equals(discard.id),
          ))
          .go();
    } else {
      moved.add((itemId: assignment.itemId, origin: assignment.origin));
    }
  }

  // 2. El resto de las asignaciones de discard pasan a keep.
  await (db.update(db.itemPropertyValues)
        ..where((t) => t.propertyValueId.equals(discard.id)))
      .write(ItemPropertyValuesCompanion(propertyValueId: Value(keep.id)));

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

  // 5. discard ya no tiene nada que solo él tuviera: se borra.
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
  );
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
  PropertyValueMergeUndo undo,
) async {
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
  await db.into(db.propertyValues).insert(undo.discard);

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
          ),
        );
  }
}
