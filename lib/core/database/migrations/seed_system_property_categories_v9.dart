import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Siembra las dos categorías de propiedad que crea la app, no el
/// usuario: "Tema" (donde caen las etiquetas migradas, ver
/// `migrate_tags_to_property_values_v9.dart`) y "Fecha del hecho"
/// (separada de cuándo se capturó la fuente).
///
/// Se llama tanto desde `onCreate` como desde `onUpgrade` —ver
/// `app_database.dart`—: una bóveda nueva pasa por `onCreate` y nunca ve
/// `onUpgrade`, así que sin esto un usuario recién instalado no tendría
/// ninguna de las dos categorías.
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
    name: 'Tema',
    type: PropertyValueType.text,
  );
  await _ensureSystemCategory(
    db,
    ids: ids,
    name: 'Fecha del hecho',
    type: PropertyValueType.date,
  );
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
