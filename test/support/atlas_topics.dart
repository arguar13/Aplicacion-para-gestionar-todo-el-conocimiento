import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';

/// El árbol de temas de las pruebas del Atlas de la IA (F27): valores de la
/// categoría «Tema» escritos directo en la base, con su padre y su nivel, sin
/// pasar por la pantalla de Vocabulario —que anota hábitos y pide
/// confirmación—.
class AtlasTopics {
  AtlasTopics(this.db);

  final AppDatabase db;

  /// Crea el tema [label] —su id es `t-<label>`— bajo [parentId], o en la
  /// raíz. [createdAt] decide si es «nuevo» para la IA.
  Future<String> add(
    String label, {
    String? parentId,
    DateTime? createdAt,
  }) async {
    final temaId = await temaDefinitionId(db);
    final depth = parentId == null ? 0 : (await row(parentId)).depth + 1;
    final id = 't-$label';
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: id,
            definitionId: temaId,
            value: label,
            createdAt: createdAt ?? DateTime(2026, 10, 2, 10),
            parentId: Value(parentId),
            depth: Value(depth),
          ),
        );
    return id;
  }

  /// Pone el tema [valueId] en el elemento [itemId], a mano.
  Future<void> tag(String itemId, String valueId) => db
      .into(db.itemPropertyValues)
      .insert(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: valueId,
        ),
      );

  Future<PropertyValueRow> row(String valueId) => (db.select(
    db.propertyValues,
  )..where((v) => v.id.equals(valueId))).getSingle();

  /// El padre de [valueId] ahora.
  Future<String?> parentOf(String valueId) async =>
      (await row(valueId)).parentId;

  /// La madurez de la nota [itemId] ahora.
  Future<NoteMaturity> maturityOf(String itemId) async => (await (db.select(
    db.knowledgeNotes,
  )..where((n) => n.itemId.equals(itemId))).getSingle()).maturity;
}
