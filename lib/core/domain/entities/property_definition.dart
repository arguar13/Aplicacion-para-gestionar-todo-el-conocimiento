import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';

part 'property_definition.freezed.dart';

/// El nombre de la categoría de sistema donde viven las etiquetas.
///
/// Desde F8, una etiqueta *es* un valor de esta categoría: no hay otra
/// tabla ni otra fuente de verdad. Una sola constante para no repetir el
/// literal donde se la busca.
const kTemaCategoryName = 'Tema';

/// El nombre de la categoría de sistema donde viven las fechas de los
/// hechos: cuándo ocurrió lo que cuenta un elemento, no cuándo se capturó.
/// Es la que alimenta la línea de tiempo.
const kFechaDelHechoCategoryName = 'Fecha del hecho';

/// El nombre de la categoría de sistema donde viven las personas que hicieron
/// una obra —autores, pero también traductores, editores y directores—: las
/// obras que se citan (F15). Sus valores son de tipo persona, con el apellido
/// y el nombre por separado.
const kAutorCategoryName = 'Autor';

/// Una categoría de propiedad: "Época", "Región", "Tema". La define el
/// usuario, no la app —a diferencia de [SourceKind] o [RelationKind], que
/// son fijos—, porque qué ejes usar para clasificar depende enteramente de
/// qué está organizando cada quien.
///
/// Es a las propiedades lo que [Tag] es a las etiquetas: el nombre de la
/// categoría vive en un solo lugar y se refleja en todo lo que la usa. La
/// diferencia real está un nivel más abajo, en [ItemProperty]: una
/// etiqueta *es* el valor ("Filosofía"), una propiedad *tiene* un valor
/// bajo esta categoría ("Época: Siglo I a.C.").
@freezed
sealed class PropertyDefinition with _$PropertyDefinition {
  const factory PropertyDefinition({
    required String id,

    /// Único, sin distinguir mayúsculas: "Época" y "época" son la misma
    /// categoría. Mismo criterio que [Tag.name].
    required String name,
    required DateTime createdAt,

    /// Qué clase de valor acepta. `text` para toda categoría creada antes
    /// de que esto existiera, y para cualquiera que el usuario cree sin
    /// elegir otra cosa.
    @Default(PropertyValueType.text) PropertyValueType type,

    /// `true` para "Tema" y "Fecha del hecho": categorías que crea la app,
    /// no el usuario, y que por eso no se pueden borrar ni renombrar.
    @Default(false) bool isSystem,
  }) = _PropertyDefinition;
}

extension PropertyDefinitionTema on PropertyDefinition {
  /// `true` para "Tema": la categoría cuyos valores se muestran y se
  /// editan como etiquetas, no como propiedades. Es de sistema, así que no
  /// se puede renombrar ni borrar: identificarla por nombre es estable.
  bool get isTema =>
      isSystem && name.toLowerCase() == kTemaCategoryName.toLowerCase();
}
