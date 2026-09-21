import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/seed_author_category_v22.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Las personas de las obras, en el vocabulario (F15): encuentra —o crea— el
/// valor de la categoría «Autor» que representa a cada una.
///
/// Es lo que hace que dos obras de la misma persona compartan UN valor y no dos
/// textos parecidos: renombrarla, fusionarla con otra escrita distinto o ver
/// «las obras de este autor» son operaciones sobre ese valor.
///
/// Lo usa `KnowledgeEntryWriter` dentro de su transacción, así que no abre la
/// suya: todo lo que crea vuelve a la base junto con la referencia que lo
/// pidió, o no vuelve.
class PersonVocabulary {
  PersonVocabulary(this._db, {required IdGenerator ids, required Clock clock})
    : _ids = ids,
      _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  String? _categoryId;

  /// El id de la categoría de sistema «Autor». Si por algún motivo no está, la
  /// crea: escribir la referencia de una obra no puede fallar por eso.
  Future<String> categoryId() async {
    final known = _categoryId;
    if (known != null) return known;
    var category = await _findCategory();
    if (category == null) {
      await ensureAuthorCategory(_db, ids: _ids);
      category = await _findCategory();
    }
    return _categoryId = category!.id;
  }

  Future<PropertyDefinitionRow?> _findCategory() =>
      (_db.select(_db.propertyDefinitions)..where(
            (d) =>
                d.name.lower().equals(kAutorCategoryName.toLowerCase()) &
                d.type.equalsValue(PropertyValueType.person),
          ))
          .getSingleOrNull();

  /// El id del valor que representa a [contributor], en este orden:
  ///
  /// 1. el que ya trae [Contributor.personId], si sigue existiendo;
  /// 2. el valor de la categoría con su misma etiqueta «Apellido, Nombre» —sin
  ///    distinguir mayúsculas, como el resto del vocabulario—, o el que tenga
  ///    esa etiqueta por alias;
  /// 3. uno nuevo, con el nombre partido.
  ///
  /// `null` si no hay nada que resolver: una persona sin nombre cuyo valor ya
  /// no existe —alguien lo borró mientras tanto—.
  ///
  /// Si el que se encontró por su etiqueta no tenía el nombre partido, se lo
  /// parte con el del contribuyente: no cambia lo que se muestra —la etiqueta
  /// es la misma— y una cita puede usar el apellido. Uno que ya estaba partido
  /// no se toca: lo que alguien corrigió no se pisa.
  Future<String?> resolve(Contributor contributor) async {
    final category = await categoryId();

    final id = contributor.personId;
    if (id != null) {
      final saved =
          await (_db.select(_db.propertyValues)..where(
                (v) => v.id.equals(id) & v.definitionId.equals(category),
              ))
              .getSingleOrNull();
      if (saved != null) return saved.id;
    }

    final name = contributor.name;
    final label = name.label;
    if (label.trim().isEmpty) return null;

    final byLabel =
        await (_db.select(_db.propertyValues)..where(
              (v) =>
                  v.definitionId.equals(category) &
                  v.value.collate(Collate.noCase).equals(label),
            ))
            .getSingleOrNull();
    if (byLabel != null) {
      if (byLabel.nameFamily == null) {
        await (_db.update(
          _db.propertyValues,
        )..where((v) => v.id.equals(byLabel.id))).write(_structure(name));
      }
      return byLabel.id;
    }

    final byAlias =
        await (_db.select(_db.propertyAliases)..where(
              (a) =>
                  a.definitionId.equals(category) &
                  a.alias.collate(Collate.noCase).equals(label),
            ))
            .getSingleOrNull();
    if (byAlias != null) return byAlias.propertyValueId;

    final created = _ids.next();
    await _db
        .into(_db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: created,
            definitionId: category,
            value: label,
            createdAt: _clock(),
            nameFamily: Value(name.family),
            nameGiven: Value(name.given.isEmpty ? null : name.given),
            nameSuffix: Value(name.suffix.isEmpty ? null : name.suffix),
            isInstitution: Value(name.isInstitution),
          ),
        );
    return created;
  }

  PropertyValuesCompanion _structure(PersonName name) =>
      PropertyValuesCompanion(
        nameFamily: Value(name.family),
        nameGiven: Value(name.given.isEmpty ? null : name.given),
        nameSuffix: Value(name.suffix.isEmpty ? null : name.suffix),
        isInstitution: Value(name.isInstitution),
      );
}
