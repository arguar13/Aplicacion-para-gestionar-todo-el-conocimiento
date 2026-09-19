import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';

/// Si [row] es la categoría "Tema": la de sistema donde viven las etiquetas.
///
/// Es de sistema, así que no se puede renombrar ni borrar: identificarla
/// por nombre es estable. Mismo criterio que `PropertyDefinition.isTema`, en
/// la capa de base, que trabaja con filas y no con la entidad.
bool isTemaDefinitionRow(PropertyDefinitionRow row) =>
    row.isSystem && row.name.toLowerCase() == kTemaCategoryName.toLowerCase();

/// El id de la categoría "Tema".
///
/// `getSingle`: la siembra `seedSystemPropertyCategories` la crea en toda
/// base nueva y en toda migración, así que su ausencia es una base rota, no
/// un caso a esquivar. Fallar acá es mejor que guardar etiquetas en una
/// categoría que no existe.
Future<String> temaDefinitionId(AppDatabase db) async {
  final row =
      await (db.select(db.propertyDefinitions)..where(
            (d) =>
                d.isSystem.equals(true) &
                d.name.lower().equals(kTemaCategoryName.toLowerCase()),
          ))
          .getSingle();
  return row.id;
}
