import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/seed_author_category_v22.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Siembra las categorías de propiedad que crea la app, no el usuario: "Tema"
/// (donde caen las etiquetas, desde F8), "Fecha del hecho" (separada de cuándo
/// se capturó la fuente) y "Autor" (F15, ver `ensureAuthorCategory`).
///
/// La llama `onCreate`: una bóveda nueva no pasa por `onUpgrade`, y sin esto
/// un usuario recién instalado no tendría ninguna. Las bóvedas que ya existían
/// las recibieron en su migración: "Tema" y "Fecha del hecho" en v9, y "Autor"
/// en v22.
///
/// No reusa `OrganizeRepository.getOrCreatePropertyDefinition`: ese
/// método es de propósito general y no debería poder "promover" una fila
/// existente a categoría de sistema como efecto colateral de una llamada
/// cualquiera del resto de la app.
Future<void> seedSystemPropertyCategories(
  AppDatabase db, {
  required IdGenerator ids,
}) async {
  await _ensureSystemCategory(
    db,
    ids: ids,
    name: kTemaCategoryName,
    type: PropertyValueType.text,
  );
  await _ensureSystemCategory(
    db,
    ids: ids,
    name: kFechaDelHechoCategoryName,
    type: PropertyValueType.date,
  );
  await ensureAuthorCategory(db, ids: ids);
}

/// Si ya existía una categoría con ese nombre —creada a mano antes de
/// esta migración, un caso límite pero posible— se la REUSA, promovida a
/// sistema: no se reporta como conflicto ni se duplica, mismo criterio
/// que `getOrCreatePropertyDefinition` ya aplica a cualquier nombre
/// repetido.
Future<void> _ensureSystemCategory(
  AppDatabase db, {
  required IdGenerator ids,
  required String name,
  required PropertyValueType type,
}) async {
  final existing = await (db.select(
    db.propertyDefinitions,
  )..where((d) => d.name.lower().equals(name.toLowerCase()))).getSingleOrNull();

  if (existing != null) {
    await (db.update(
      db.propertyDefinitions,
    )..where((d) => d.id.equals(existing.id))).write(
      PropertyDefinitionsCompanion(
        isSystem: const Value(true),
        type: Value(type),
      ),
    );
    return;
  }

  await db
      .into(db.propertyDefinitions)
      .insert(
        PropertyDefinitionsCompanion.insert(
          id: ids.next(),
          name: name,
          createdAt: DateTime.now(),
          type: Value(type),
          isSystem: const Value(true),
        ),
      );
}
