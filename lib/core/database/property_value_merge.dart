import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// El motor de la fusión de dos valores de una misma categoría: todo lo que
/// tenía [discard] pasa a [keep], y [discard] desaparece.
///
/// Vive a nivel de base y no dentro de `OrganizeRepositoryImpl` porque lo
/// usan dos caminos que no se pueden mezclar por capas: la fusión que el
/// usuario pide desde la pantalla de Vocabulario y la reconciliación de
/// etiquetas que corre dentro de una migración —`core/database` no puede
/// depender de `features`—. Una sola implementación, no dos copias que
/// terminen desviándose.
///
/// No abre transacción ni valida nada: quien llama la corre dentro de la
/// suya, con los dos valores ya leídos y comprobado que son distintos y de
/// la misma categoría. Son cinco pasos que solo tienen sentido juntos —a
/// medias dejarían asignaciones apuntando a un valor que ya no existe—.
Future<void> mergePropertyValueRows(
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
  for (final assignment in assignments) {
    final alreadyHasKeep =
        await (db.select(db.itemPropertyValues)..where(
              (t) =>
                  t.itemId.equals(assignment.itemId) &
                  t.propertyValueId.equals(keep.id),
            ))
            .getSingleOrNull();
    if (alreadyHasKeep != null) {
      await (db.delete(db.itemPropertyValues)..where(
            (t) =>
                t.itemId.equals(assignment.itemId) &
                t.propertyValueId.equals(discard.id),
          ))
          .go();
    }
  }

  // 2. El resto de las asignaciones de discard pasan a keep.
  await (db.update(db.itemPropertyValues)
        ..where((t) => t.propertyValueId.equals(discard.id)))
      .write(ItemPropertyValuesCompanion(propertyValueId: Value(keep.id)));

  // 3. Los alias que ya apuntaban a discard pasan a keep —ANTES de borrar
  // discard: su FK es ON DELETE CASCADE, y borrarlo primero se los llevaría
  // con él—.
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
  if (aliasClash == null) {
    await db
        .into(db.propertyAliases)
        .insert(
          PropertyAliasesCompanion.insert(
            id: ids.next(),
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
}
